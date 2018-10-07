#!./venv/bin/python3

from eth_tester import EthereumTester
t = EthereumTester()
authority = t.get_accounts()[0]