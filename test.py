#!./venv/bin/python3

import binascii
import bitcoin
import ethereum

import eth_abi

from ethereum.tools import tester
from ethereum.tools._solidity import get_solidity

import rootchain_abi

def sign(h, priv):
    assert len(h) == 32
    V, R, S = bitcoin.ecdsa_raw_sign(h, priv)
    return V,R,S

c = tester.Chain()

with open('./RootChain.sol') as f:
    code = f.read()

RootChain = c.contract(
    sourcecode=code, # todo: better error message if a list of lines is passed
    language="solidity"
)

assert(RootChain.authority(sender=tester.k1) == f"0x{tester.a0.hex()}")

RootChain.deposit(sender=tester.k1, value=5)

c.mine() # bump gas limit

assert(RootChain.coins(0) == 5)

deposit_block = RootChain.childBlockRoots(0)

def Transfer(*args): return tuple(args)
def IncludedTransfer(*args): return tuple(args)

startExitSig = rootchain_abi.decode_inputs(rootchain_abi.functions['startExit'])
selector = ethereum.utils.sha3("startExit" + startExitSig)[0:4]

myAddr = tester.a1

it = IncludedTransfer(
    0,
    Transfer(
        myAddr, myAddr, 0, 0, b"", b""
    )
)
calldata = selector + eth_abi.encode_single(startExitSig, (0, it, b"", it, b""))

# print(RootChain.startExit(data=calldata, sender=tester.k1))
