#!./venv/bin/python3

import binascii
import bitcoin

from ethereum.tools import tester
from ethereum.tools._solidity import get_solidity

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

assert(RootChain.coins(0) == 5)

deposit_block = RootChain.childBlockRoots(0)

assert(RootChain.checkMembership(deposit_block, 0, deposit_block, "0x"))
