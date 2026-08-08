# Decoding the QMI LOC IDL table

The modem's location engine speaks a QMI service (LOC, service 16) with far more messages
than any public documentation covers. `libqmi` only knows a subset, and the ones missing
are exactly the interesting ones — constellation control, assistance, measurement
reporting.

Those messages are not secret so much as unpublished: the vendor location library carries
the whole interface description with it. `libloc_api_v02.so` exports
**`loc_qmi_idl_service_object_v02`**, the table Qualcomm's IDL compiler generates, and it
describes **every one of the 470 messages** — id, TLVs, field types, offsets and lengths.

This decodes it.

**No vendor binary is redistributed here.** Only the result of the analysis — interface
facts — and the tool that extracts it from the blob already on your own phone. See
[`../../docs/blobs.md`](../../docs/blobs.md) for how to get at it.

## Use

```sh
cp /mnt/vendor/lib64/libloc_api_v02.so .
python3 dump.py            # all 470 messages
python3 dump.py 0x88 0xb8  # just the ones you care about
```

[`loc-idl-full.txt`](loc-idl-full.txt) is the full dump, so you can read it without a
phone to hand.

## How the table is laid out

`loc_qmi_idl_service_object_v02` is 72 bytes:

| offset | type | contents |
|---|---|---|
| 0x00 | u32 ×2 | library and IDL versions (6, 2) |
| 0x08 | u32 | **service id = 16** (LOC) |
| 0x0c | u32 | maximum message length, 10015 |
| 0x10 | u16 ×3 | number of requests / responses / indications = **141 / 141 / 188** |
| 0x18 | ptr ×3 | the three message tables |
| 0x30 | ptr | the type table object |

Each message table is an array of 6-byte entries:

```c
struct { uint16_t msg_id; uint16_t idx; uint16_t max_wire_len; };
```

`idx` indexes the message table; with bits 12-15 set, the type lives in QMI's common
table, external to this library.

The type table object gives 98 struct types and 312 message descriptors, each
`{ uint64_t c_struct_size; const uint8_t *encoding; }`.

## The field encoding

This is the part documented nowhere. Each field:

```
  byte 0 ─ if 0x40 is set:  OPTIONAL TLV. Bits 0-5 hold the distance between the
                            field and the "_valid" byte that precedes it.
                            The TLV type is the next byte.
           otherwise:       mandatory TLV, and bits 0-5 are its type.
           bit 0x80 marks the LAST field of the message.

  byte 1 ─ type descriptor:
             bits 0-3  base type   0=1 byte  1=2  2=4  3=8
                                   6=char  7=struct (carries a type index)
             0x10      variable length (has a "_len" field)
             0x20      the array's maximum count takes 2 bytes
             0x40      it is an array
             0x80      the offset takes 2 bytes

  then   ─ offset (1 or 2 bytes)
           if array: maximum count (1 or 2 bytes)
           if also variable and not a string: distance to the "_len" field
           if struct: type index (1 byte) + table (1 byte, 0 = this one)
```

Struct descriptors use the same encoding without the TLV byte, and end in `0x20`.

One detail that is easy to miss: **a string in a TLV of its own is N bytes on the wire,
but N+1 inside a struct** — as a fixed-size field, the terminator travels with it.

## Why this is trustworthy

Four independent checks, rather than one plausible reading:

1. **466 out of 466.** The decoder recomputes each message's maximum length from its
   descriptor and matches the value the library itself stores, for every one of the 466
   messages that has a type of its own.
2. **The C struct sizes fall out on their own.** `applicationId` comes to 68 = 25+33+1+9,
   which is what the table declares. `START_REQ` comes to 148; message `0x0088`, to 40.
3. **The vendor code agrees.** The function that fills message `0x0088` writes at offsets
   0, 8, 16 and 24 — exactly where the decoding says the fields are.
4. **A real modem agrees.** It answers `0x00BF` with a 49-byte payload, which is the
   maximum the decoding predicts.

## Message names

`loc_get_v02_event_name` carries no static table: it is an `unordered_map` filled by a
static initialiser, 14.6 KB of code. Walking it yields **170 ids with a name, 170 distinct
names, none repeated**. A separate check: all 42 ids that are indications only carry
`_IND` in the name, and all 128 request ids are consistent. No mismatches.

## What came out of it

Three messages nobody was sending, now implemented in
[`../../packages/libqmi`](../../packages/libqmi):

```
0x0088  QMI_LOC_SET_GNSS_CONSTELL_REPORT_CONFIG   two u64 masks + three u8
0x00B8  QMI_LOC_SET_CONSTELLATION_CONTROL         u8 + two u64 masks
0x00BF  QMI_LOC_GET_CONSTELLATION_CONTROL         empty request; the answer
                                                  arrives in an indication
```

⚠️ **The pattern that matters in LOC: the response tells you nothing.** Almost every LOC
response carries only the generic result TLV; the real answer arrives in a later
**indication** with the same id. This is why `--loc-set-operation-mode` reports
"Successfully set" while nothing changes — that is the acknowledgement, not the outcome.
Anyone reading only the response is not measuring anything.
