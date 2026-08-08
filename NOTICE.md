# Notices, licences and what is not here

## Licences

| What | Licence |
|---|---|
| `kernel/*.patch` | **GPL-2.0** — derived work of the Linux kernel |
| `packages/libcamera/*.patch` | **LGPL-2.1-or-later** — matching libcamera upstream |
| `packages/libqmi/*.patch` | **GPL-2.0-or-later AND LGPL-2.1-or-later** — matching libqmi upstream |
| `tools/qmi-loc-idl/**` | **GPL-2.0-or-later** |
| `packages/*/APKBUILD` | **GPL-2.0-or-later**, as the postmarketOS/Alpine aports they extend |
| `device/**`, `scripts/**` | Configuration and glue, same terms as the projects they configure |

## No proprietary firmware is redistributed here

This phone needs binaries that belong to Xiaomi and Qualcomm to work fully:

- **ACDB** — audio calibration for the DSP.
- **ADSP / modem firmware** — signed by the vendor.
- **Camera sensor configuration** (`com.qti.sensormodule.*.bin`) — power sequences, register
  tables and lane assignment for each module.
- **The factory device tree overlay**, useful as a reference for the camera topology.

**None of them are in this repository.** They are on your own device, and postmarketOS does not
erase the partitions that hold them, so you can read them from there. See
[`docs/blobs.md`](docs/blobs.md).

This applies to [`tools/qmi-loc-idl`](tools/qmi-loc-idl) as well. What it publishes is the
*result* of reading the modem's interface description — message ids, field layouts, names — so
that free software can talk to hardware you own. The library it reads is not included; the tool
expects you to point it at the copy already on your phone.

## Nor is development material

Left out on purpose: audio recordings from the call test bench (they contain voices), Bluetooth
traces (they contain addresses), register dumps and terminal logs from working sessions, and
compiled binaries. None of it is needed to reproduce anything.

## Attribution

The mainline port of this SoC is the work of the
[sm7150-mainline](https://github.com/sm7150-mainline/linux) project, and the distribution is
[postmarketOS](https://postmarketos.org). This repository only adds what was missing for daily use.
