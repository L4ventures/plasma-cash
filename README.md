PoC, untested. 188 CLOC.

Forked from https://github.com/omisego/plasma-cash

to generate the abi json file:

```
solc --combined-json abi,bin,bin-runtime RootChain.sol > contracts.json
```

requires a patched pyethereum that allows passing `data` directly
