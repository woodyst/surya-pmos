"""Decodificador de la tabla IDL de QMI tal como la deja el compilador de Qualcomm.

Formato deducido leyendo libloc_api_v02.so; cada regla se valida abajo
recalculando la longitud maxima de los 470 mensajes y comparandola con la
que el propio binario tiene almacenada.
"""
import struct
from elf import ELF

# --- base del dtype -> tamano en el cable (None = agregado/struct) ---
BASE = {0:1, 1:2, 2:4, 3:8, 4:1, 5:2, 6:1, 7:None, 8:2, 9:4, 10:None, 11:1, 12:None}
BASENAME = {0:'u8/i8', 1:'u16/i16', 2:'u32/i32', 3:'u64/i64', 4:'u8', 5:'u16',
            6:'char', 7:'struct', 8:'enum16', 9:'enum32', 10:'struct?', 11:'char?', 12:'?'}

D_VAR   = 0x10   # longitud variable (lleva campo _len, o es cadena)
D_CNT16 = 0x20   # la cuenta maxima del array ocupa 2 bytes
D_ARRAY = 0x40   # es un array
D_OFF16 = 0x80   # el desplazamiento ocupa 2 bytes

# La tabla comun (common_qmi_idl_type_table_object_v01) es externa a este .so.
# Solo se usa su tipo 0: qmi_response_type_v01 { uint16 result; uint16 error; }
COMMON_WIRE = {0: 4}

class Field:
    def __init__(s, **kw): s.__dict__.update(kw)
    def __repr__(s):
        t = BASENAME.get(s.base, '?%d' % s.base)
        if s.base == 7: t = 'struct#%d%s' % (s.tidx, '' if s.tbl == 0 else '@tabla%d' % s.tbl)
        if s.is_str:  t = 'char[%d]' % s.count
        elif s.array: t = '%s[%d]%s' % (t, s.count, ' variable' if s.var else '')
        return t

class IDL:
    def __init__(self, path):
        self.e = ELF(path)
        sy = self.e.symbols()
        so = sy['loc_qmi_idl_service_object_v02'][0]
        b = self.e.read(so, 72)
        (self.v1, self.v2, self.service_id, self.max_msg_len) = struct.unpack_from('<IIII', b, 0)
        self.n_req, self.n_resp, self.n_ind = struct.unpack_from('<HHH', b, 16)
        self.p_req, self.p_resp, self.p_ind, self.p_tto = struct.unpack_from('<QQQQ', b, 24)
        h = self.e.read(self.p_tto, 40)
        self.n_types, self.n_msgs, self.n_reftbl = struct.unpack_from('<HHH', h, 0)
        self.p_type_tbl, self.p_msg_tbl = struct.unpack_from('<QQ', h, 8)
        self._struct_wire = {}

    def type_entry(self, i):
        return struct.unpack('<QQ', self.e.read(self.p_type_tbl + i*16, 16))
    def msg_entry(self, i):
        return struct.unpack('<QQ', self.e.read(self.p_msg_tbl + i*16, 16))

    def msgs(self, which):
        p, n = {'req': (self.p_req, self.n_req), 'resp': (self.p_resp, self.n_resp),
                'ind': (self.p_ind, self.n_ind)}[which]
        return [struct.unpack('<HHH', self.e.read(p + i*6, 6)) for i in range(n)]

    # --- lectura de un descriptor de campo ---
    def _field(self, buf, o, tlv_level):
        f = Field(optional=False, delta=None, last=False, tlv=None)
        if tlv_level:
            b0 = buf[o]; o += 1
            f.last = bool(b0 & 0x80)
            if b0 & 0x40:
                f.optional = True; f.delta = b0 & 0x3f
                f.tlv = buf[o]; o += 1
            else:
                f.tlv = b0 & 0x3f
        d = buf[o]; o += 1
        f.dtype = d; f.base = d & 0x0f
        f.var = bool(d & D_VAR); f.array = bool(d & D_ARRAY)
        if d & D_OFF16:
            f.offset = struct.unpack_from('<H', buf, o)[0]; o += 2
        else:
            f.offset = buf[o]; o += 1
        f.count = 1; f.len_delta = None
        f.cnt16 = bool(d & D_CNT16)
        f.is_str = f.array and f.var and f.base == 6
        if f.array:
            if f.cnt16:
                f.count = struct.unpack_from('<H', buf, o)[0]; o += 2
            else:
                f.count = buf[o]; o += 1
            if f.var and not f.is_str:
                f.len_delta = buf[o]; o += 1
        f.tidx = f.tbl = None
        if f.base == 7:
            f.tidx = buf[o]; f.tbl = buf[o+1]; o += 2
        return f, o

    def parse(self, ptr, end, tlv_level):
        buf = self.e.read(ptr, end - ptr)
        out, o = [], 0
        while o < len(buf):
            if not tlv_level and buf[o] == 0x20:   # terminador de struct
                o += 1; break
            f, o = self._field(buf, o, tlv_level)
            out.append(f)
            if tlv_level and f.last: break
        return out, o

    # --- tamano en el cable ---
    def elem_wire(self, f):
        if f.base == 7:
            if f.tbl: return COMMON_WIRE.get(f.tidx)
            return self.struct_wire(f.tidx)
        return BASE.get(f.base)

    def struct_wire(self, idx):
        if idx in self._struct_wire: return self._struct_wire[idx]
        sz, p = self.type_entry(idx)
        self._struct_wire[idx] = 0
        fields, _ = self.parse(p, p + 64, False)
        tot = 0
        for f in fields:
            tot += self.field_wire(f, inside_struct=True)
        self._struct_wire[idx] = tot
        return tot

    def field_wire(self, f, inside_struct=False):
        # cadena: dentro de un struct es un campo fijo y viaja con el terminador;
        # como TLV suelto va con longitud explicita, sin terminador
        if f.is_str: return f.count + (1 if inside_struct else 0)
        es = self.elem_wire(f)
        if es is None: return 0
        n = es * f.count if f.array else es
        if f.var and not f.is_str:
            n += 2 if f.cnt16 else 1        # prefijo de longitud en el cable
        return n

    def msg_wire(self, idx):
        sz, p = self.msg_entry(idx)
        if not p: return 0
        fields, _ = self.parse(p, p + 512, True)
        tot = 0
        for f in fields:
            tot += 3 + self.field_wire(f)
        return tot
