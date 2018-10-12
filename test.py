#!./venv/bin/python3

import json

with open("contracts.json") as f:
    rootchain = json.loads(f.read())['contracts']['RootChain.sol:RootChain']['abi']
    rootchain = json.loads(rootchain)

functions = dict()

for elem in rootchain:
    if elem['type'] == 'function':
        functions[elem['name']] = elem
    elif elem['type'] == 'constructor':
        functions['constructor'] = elem

def decode_input(inp):
    if inp['type'] == 'tuple':
        return "(" + ",".join(decode_input(component) for component in inp['components']) + ")"
    else:
        return inp['type']

def decode_inputs(fn):
    return "(" + ",".join(decode_input(inp) for inp in fn['inputs']) + ")"

import binascii
import bitcoin
import ethereum

import eth_abi

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

def Transfer(*args): return tuple(args)
def IncludedTransfer(*args): return tuple(args)

startExitSig = decode_inputs(functions['startExit'])
selector = ethereum.utils.sha3("startExit" + startExitSig)[0:4]

myAddr = tester.a1

it = IncludedTransfer(
    0,
    Transfer(
        myAddr, myAddr, 0, 0, b"", b""
    )
)
calldata = selector + eth_abi.encode_single(startExitSig, (0, it, b"", it, b""))

print(RootChain.startExit(data=calldata, sender=tester.k1))
