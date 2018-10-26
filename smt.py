import sha3

def short_keccak256(x):
  k = sha3.keccak_256()
  k.update(x)
  return k.digest()[0:1]

def bl(x):
    k = short_keccak256(x)
    k = int.from_bytes(k, 'big')
    return "{0:b}".format(k)

print(bl(b''))
print(bl(b'a'))

# def smt(depth, elems)