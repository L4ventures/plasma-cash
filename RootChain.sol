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
        IncludedTransfer c;
        IncludedTransfer pc;
        uint256 numChallenges;
        uint256 coinId;
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
    mapping(uint256 => mapping(address => mapping(uint256 => IncludedTransfer))) challenges;
    mapping(uint256 => bool) isDeposit;

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
        isDeposit[coins.length] = true;
        childBlockRoots.push(keccak256(abi.encode(coins.length, Transfer({
            oldOwner: msg.sender,
            newOwner: msg.sender,
            oldBlkNum: 0,
            sigV: uint8(0),
            sigR: bytes32(0),
            sigS: bytes32(0)
        }))));
        coins.push(msg.value);
    }

    function checkInclusion(
        uint256 coinId,
        IncludedTransfer itxn,
        bytes txnProof
    ) public view returns (bool) {
        bytes32 blkRoot = childBlockRoots[itxn.blkNum];
        bytes32 digest = keccak256(abi.encode(coinId, itxn.txn));
        return checkMembership(digest, coinId, blkRoot, txnProof);
    }

    function checkSignatures(
        uint256 coinId,
        IncludedTransfer itxn
    ) public view returns (bool) {
        if (isDeposit[itxn.blkNum]) {
            return true;
        }
        bytes32 txnDigest = keccak256(abi.encode(coinId, itxn.txn));
        return (itxn.txn.oldOwner == ecrecover(txnDigest, itxn.txn.sigV, itxn.txn.sigR, itxn.txn.sigS));
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

        // check signatures
        require(checkSignatures(coinId, c));
        require(checkSignatures(coinId, pc));

        // check separation
        require(pc.blkNum < c.blkNum || isDeposit[c.blkNum]);

        // Record the exit tx.
        require(exits[coinId][msg.sender].stage == ExitStage.NOT_STARTED);
        exits[coinId][msg.sender] = Exit({
            stage: ExitStage.STARTED,
            challengeDeadline: block.number + 100,
            c: c,
            pc: pc,
            numChallenges: 0,
            coinId: coinId
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

        if ( /* Type 1: C has been spent */
            spends(exits[coinId][exitBeneficiary].c, cs, uint256(-1))
        ) {
            exits[coinId][exitBeneficiary].stage = ExitStage.FINISHED;
        } else if ( /* Type 2: P(C) has been spent before C */
            spends(exits[coinId][exitBeneficiary].pc, cs, exits[coinId][exitBeneficiary].c.blkNum)
        ) {
            exits[coinId][exitBeneficiary].stage = ExitStage.FINISHED;
        } else if ( /* Type 3: Challenger provides a tx in history. Exitor needs to respond it. */
            cs.blkNum < exits[coinId][exitBeneficiary].pc.blkNum
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

        exitBeneficiary.transfer(coins[exit.coinId]);
        exit.stage = ExitStage.FINISHED;
    }
}

