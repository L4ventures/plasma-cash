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
