import json, sys
from qmiidl import IDL, BASENAME

d = IDL('libloc_api_v02.so')
names = {int(k): v for k, v in json.load(open('names.json')).items()}

def tname(f):
    if f.base == 7:
        if f.tbl: return 'struct@commonTable[%d]' % f.tidx
        return 'struct[%d]' % f.tidx
    return BASENAME.get(f.base, '?%d' % f.base)

def fmt(f, indent='    '):
    t = tname(f)
    if f.is_str:  desc = 'string, max %d chars' % f.count
    elif f.array: desc = '%s x%d%s' % (t, f.count, ' (variable length)' if f.var else ' (fixed)')
    else:         desc = t
    o = '%sTLV 0x%02x  %-11s %-40s off_C=%-5d wire<=%d' % (
        indent, f.tlv, 'optional' if f.optional else 'mandatory', desc, f.offset, 3 + d.field_wire(f))
    return o

def show(kind, mid, tidx, mlen):
    nm = names.get(mid, '')
    if tidx & 0xf000:
        print('%-4s 0x%04x  %-52s  (type in the common QMI table, external)  wire_max=%d'
              % (kind.upper(), mid, nm, mlen)); return
    sz, p = d.msg_entry(tidx)
    print('%-4s 0x%04x  %-52s  struct_C=%-6d wire_max=%d' % (kind.upper(), mid, nm, sz, mlen))
    if not p:
        print('     (empty message: no TLVs)'); return
    fields, _ = d.parse(p, p + 512, True)
    for f in fields: print(fmt(f))

if __name__ == '__main__':
    want = [int(x, 0) for x in sys.argv[1:]]
    for kind in ('req', 'resp', 'ind'):
        for mid, tidx, mlen in d.msgs(kind):
            if want and mid not in want: continue
            show(kind, mid, tidx, mlen); print()
