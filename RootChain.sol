pragma solidity ^0.4.25;
pragma experimental "ABIEncoderV2";

contract RootChain {

    enum ExitStage {
        NOT_STARTED, // default unintialized
        STARTED,
        FINISHED
    }

    struct Transfer {
        address oldOwner;
        address newOwner;
        uint256 oldBlkNum;
        uint8 sigV;
        bytes32 sigR;
        bytes32 sigS;
    }

    struct IncludedTransfer {
        uint256 blkNum;
        Transfer txn;
    }

    struct Exit {
        ExitStage stage;
        uint256 challengeDeadline;
        uint256 numChallenges;
        address pcOwner;
        uint256 cBlkNum;
        uint256 pcBlkNum;
    }

    /**
     * @dev Validate the merkle proof of a specifc leaf with index
     */
    function checkMembership(
        bytes32 leaf,
        uint256 index,
        bytes32 rootHash,
        bytes proof
    )
        public
        pure
        returns (bool)
    {
        bytes32 proofElement;
        bytes32 computedHash = leaf;

        require(proof.length == 256);

        for (uint256 i = 32; i <= proof.length; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }
            if (index % 2 == 0) {
                computedHash = keccak256(abi.encode(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encode(proofElement, computedHash));
            }
            index = index / 2;
        }
        return computedHash == rootHash;
    }

    /*
     * Storage
     */
    address public authority;
    bytes32[] public childBlockRoots;
    uint256[] public coins;
    mapping(uint256 => mapping(address => Exit)) exits;
    mapping(uint256 => mapping(address => bytes32)) exitHashes;
    mapping(uint256 => mapping(address => mapping(uint256 => IncludedTransfer))) challenges;
    uint256[] coinDepositBlkNum;

    constructor ()
        public
    {
        authority = msg.sender;
    }

    // @dev Allows Plasma chain operator to submit block root
    // @param blkRoot The root of a transaction SMT
    function submitBlock(bytes32 blkRoot)
        public
    {
        require(msg.sender == authority);
        childBlockRoots.push(blkRoot);
    }

    function deposit()
        payable
        public
    {
        coinDepositBlkNum.push(childBlockRoots.length);
        childBlockRoots.push(bytes32(0));
        coins.push(msg.value);
    }

    function checkInclusion(
        uint256 coinId,
        IncludedTransfer itxn,
        bytes txnProof
    ) public view returns (bool) {
        if (itxn.blkNum == coinDepositBlkNum[coinId]) return true;
        bytes32 txnDigest = keccak256(abi.encode(coinId, itxn.txn));
        if (itxn.txn.oldOwner != ecrecover(txnDigest, itxn.txn.sigV, itxn.txn.sigR, itxn.txn.sigS)) return false;
        bytes32 blkRoot = childBlockRoots[itxn.blkNum];
        bytes32 digest = keccak256(abi.encode(coinId, itxn.txn));
        return checkMembership(digest, coinId, blkRoot, txnProof);
    }

    function startExitOfDeposit(
        uint256 coinId
    ) {
        exits[coinId][msg.sender] = Exit({
            stage: ExitStage.STARTED,
            challengeDeadline: block.number + 100,
            numChallenges: 0,
            pcOwner: address(0),
            cBlkNum: coinDepositBlkNum[coinId],
            pcBlkNum: uint256(0)
        });
    }

    // @dev Starts to exit a transaction producing an output C
    function startExit(
        uint256 coinId,

        IncludedTransfer c,
        bytes cProof,

        IncludedTransfer pc,
        bytes pcProof
    )
        public
    {
        require(msg.sender == c.txn.newOwner);

        // check inclusion proofs
        require(checkInclusion(coinId, c, cProof));
        require(checkInclusion(coinId, pc, pcProof));

        // check owners match
        require(c.txn.oldOwner == pc.txn.newOwner);

        // check separation
        require(pc.blkNum < c.blkNum);

        // Record the exit tx.
        require(exits[coinId][msg.sender].stage == ExitStage.NOT_STARTED);

        // todo: gas limit nonsense

        exits[coinId][msg.sender] = Exit({
            stage: ExitStage.STARTED,
            challengeDeadline: block.number + 100,
            numChallenges: 0,
            pcOwner: pc.txn.newOwner,
            cBlkNum: c.blkNum,
            pcBlkNum: pc.blkNum
        });
    }

    function spends(
        IncludedTransfer a,
        IncludedTransfer b,
        uint256 deadline
    ) public pure returns (bool) {
        return (
            a.blkNum < b.blkNum
            && a.txn.newOwner == b.txn.oldOwner
            && a.blkNum == b.txn.oldBlkNum
            && b.blkNum < deadline
        );
    }

    // @dev Challenge an exit transaction
    function challengeExit(
        uint256 coinId,
        address exitBeneficiary,
        IncludedTransfer cs,
        bytes csProof
    ) public {
        require(exits[coinId][exitBeneficiary].stage == ExitStage.STARTED);
        require(checkInclusion(coinId, cs, csProof));

        Exit storage exit = exits[coinId][exitBeneficiary];

        if ( /* Type 1: C has been spent */
            (exit.cBlkNum < cs.blkNum)
            && (exit.cBlkNum == cs.txn.oldBlkNum)
            && (exitBeneficiary == cs.txn.oldOwner)
        ) {
            exits[coinId][exitBeneficiary].stage = ExitStage.FINISHED;
        } else if ( /* Type 2: P(C) has been spent before C */
            (exit.pcBlkNum < cs.blkNum)
            && (exit.pcOwner == cs.txn.newOwner)
            && (exit.pcBlkNum == cs.txn.oldBlkNum)
            && (cs.blkNum < exit.cBlkNum)
        ) {
            exits[coinId][exitBeneficiary].stage = ExitStage.FINISHED;
        } else if ( /* Type 3: Challenger provides a tx in history. Exitor needs to respond it. */
            cs.blkNum < exits[coinId][exitBeneficiary].pcBlkNum
        ) {
            challenges[coinId][exitBeneficiary][cs.blkNum] = cs;
            exits[coinId][exitBeneficiary].numChallenges += 1;
        }
    }

    function respondChallengeExit(
        uint256 coinId,
        address exitBeneficiary,
        uint256 csBlkNum,
        IncludedTransfer css,
        bytes cssProof
    )
        public
    {
        require(checkInclusion(coinId, css, cssProof));
        IncludedTransfer storage cs = challenges[coinId][exitBeneficiary][csBlkNum];
        require(spends(cs, css, uint256(-1)));
        exits[coinId][exitBeneficiary].numChallenges -= 1;
    }

    function finalizeExit(uint256 coinId, address exitBeneficiary) public {
        Exit storage exit = exits[coinId][exitBeneficiary];

        require(exit.stage == ExitStage.STARTED);
        require(block.number >= exit.challengeDeadline);
        require(exit.numChallenges == 0);

        exitBeneficiary.transfer(coins[coinId]);
        exit.stage = ExitStage.FINISHED;
    }
}

