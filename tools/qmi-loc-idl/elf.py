import struct, sys

class ELF:
    def __init__(self, path):
        self.data = open(path,'rb').read()
        d = self.data
        assert d[:4] == b'\x7fELF'
        assert d[4] == 2 and d[5] == 1, "solo ELF64 LE"
        e_shoff, = struct.unpack_from('<Q', d, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', d, 0x3a)
        self.sections = []
        for i in range(e_shnum):
            o = e_shoff + i*e_shentsize
            name, typ, flags, addr, off, size, link, info, align, entsize = \
                struct.unpack_from('<IIQQQQIIQQ', d, o)
            self.sections.append(dict(name_off=name, type=typ, flags=flags,
                                      addr=addr, off=off, size=size, entsize=entsize))
        sh = self.sections[e_shstrndx]
        strtab = d[sh['off']:sh['off']+sh['size']]
        for s in self.sections:
            n = strtab[s['name_off']:]
            s['name'] = n[:n.index(b'\0')].decode()

    def sec(self, name):
        for s in self.sections:
            if s['name'] == name: return s
        return None

    def off(self, vaddr):
        """vaddr -> file offset (None si es NOBITS o no mapeado)"""
        for s in self.sections:
            if s['addr'] and s['addr'] <= vaddr < s['addr']+s['size']:
                if s['type'] == 8:  # NOBITS
                    return None
                return s['off'] + (vaddr - s['addr'])
        return None

    def read(self, vaddr, n):
        o = self.off(vaddr)
        if o is None: return None
        return self.data[o:o+n]

    def u8(self, v):  return self.read(v,1)[0]
    def u16(self, v): return struct.unpack('<H', self.read(v,2))[0]
    def u32(self, v): return struct.unpack('<I', self.read(v,4))[0]
    def u64(self, v): return struct.unpack('<Q', self.read(v,8))[0]

    def cstr(self, vaddr, maxlen=200):
        b = self.read(vaddr, maxlen)
        if b is None: return None
        i = b.find(b'\0')
        return b[:i].decode('utf-8','replace') if i >= 0 else None

    def symbols(self):
        out = {}
        for secname, strname in (('.dynsym','.dynstr'), ('.symtab','.strtab')):
            s = self.sec(secname); st = self.sec(strname)
            if not s or not st: continue
            strtab = self.data[st['off']:st['off']+st['size']]
            for i in range(s['size']//24):
                o = s['off'] + i*24
                nm, info, other, shndx, value, size = struct.unpack_from('<IBBHQQ', self.data, o)
                n = strtab[nm:]
                n = n[:n.index(b'\0')].decode()
                if n: out[n] = (value, size, info)
        return out
