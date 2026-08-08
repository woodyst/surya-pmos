# libqmi

Two things live here. The first patch is a plain bug fix. The other two add GNSS
constellation control to the LOC service.

| Patch | What it does |
|---|---|
| `0001-qmicli-pdc-…` | Fixes an invalid free of an mmapped config in `qmicli`'s PDC code |
| `0002-loc-add-constellation-control-messages…` | Adds three LOC messages and an adapter for the query |
| `0003-qmicli-loc-expose-constellation-control…` | Exposes them on the command line |

## The constellation messages

```
0x0088  Set GNSS Constellation Report Config
0x00B8  Set Constellation Control
0x00BF  Get Constellation Control
```

They exist in the modem but are published nowhere. Their layout was recovered from the
QMI IDL table the vendor location library carries, and checked four independent ways —
see [`../../tools/qmi-loc-idl`](../../tools/qmi-loc-idl), which has the decoder and the
full dump of all 470 LOC messages.

```sh
qmicli -p -d qrtr://0 --loc-get-constellation-control
qmicli -p -d qrtr://0 --loc-set-constellation-control=[reset|disabled-mask[,enabled-mask]]
qmicli -p -d qrtr://0 --loc-set-gnss-constellation-report-config=mask[,mask]
```

On this phone the query answers:

```
Enabled:  gps, glonass, beidou, galileo, qzss
Disabled: navic
Reported state values:
        GPS:     0
        GLONASS: 1
        BeiDou:  1
        QZSS:    1
        Galileo: 1
        NavIC:   100
```

## The adapter

The modem reports one TLV per constellation, each holding an unpublished enumeration.
`qmi_indication_loc_get_constellation_control_output_get_constellations()` collapses the
six into a single enabled/disabled pair, which is the shape a location manager such as
ModemManager actually wants.

A constellation the modem did not report lands in neither set, and so does one whose
state value is not recognised: **absent is not the same as disabled**, and neither is
guessed at.

## Two deliberate restraints

**The masks taken by the setters are left as plain `guint64`.** Their bit order is *not*
the same in every message — the one taken by Set Constellation Control is written straight
from Android's `GnssSvTypesMask`, while the multi-band conversion uses a different order —
so giving them a named flags type would have looked authoritative without being so.

**The state values are printed raw as well as interpreted.** The vendor binary shows how
the values are grouped (up to 2, and 100 to 103) but not which group means what. That was
settled on hardware: a first attempt had the grouping backwards and reported GPS as
disabled on a phone that was tracking GPS. So `qmicli` prints the numbers too, rather than
hide the reply behind an interpretation.

## What this does not fix

**Galileo and BeiDou come back enabled and still do not appear** in the satellite list. So
whatever is keeping them out, it is not the constellation control. That is still open.
