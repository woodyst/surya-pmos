# Extracting the vendor blobs from your own phone

Nothing in this repository redistributes proprietary firmware. What follows reads it from **your**
device, where it already is: postmarketOS installs alongside the factory partitions and does not
erase them.

## First: getting at the `vendor` partition at all

On this phone `vendor` is **not** a plain partition — it lives inside `super` as a *dynamic
partition*, so `/dev/disk/by-partlabel/vendor` does not exist and the obvious `mount` fails.
You have to map it first:

```sh
sudo apk add lvm2 device-mapper          # provides dmsetup
sudo scripts/setup-vendor-mount.sh       # maps /dev/mapper/vendor and mounts vendor + persist
```

`scripts/setup-vendor-mount.sh` in this repository does the whole thing and is **idempotent**.
Re-run it after every `pmbootstrap flasher flash_rootfs`, which wipes the mapping.

Afterwards:

| what | where |
|---|---|
| vendor, read-only lower layer | `/mnt/vendorlower` |
| vendor, writable overlay | `/mnt/vendor` |
| persist (sensor registry) | `/mnt/vendor/persist` |

## Audio calibration (ACDB)

Needed for call audio to sound right:

```sh
ls /mnt/vendor/etc/acdbdata/
```

## Camera sensor configuration

Only needed to *develop* sensor drivers, not to use the camera — the drivers in this kernel already
carry the register tables they need.

```sh
ls /mnt/vendor/lib/camera/com.qti.sensormodule.*.bin
```

⚠️ For the IMX682 use the `_ver2_` file (≈343 KB). The smaller one (≈146 KB) carries a **truncated**
init table — 7 registers instead of 638 — and quietly produces a sensor that never streams.

### Finding which partition holds something

When you do not know where a file lives, this beats guessing:

```sh
ls /dev/disk/by-partlabel/            # what partitions exist at all
for p in /dev/disk/by-partlabel/*; do
    sudo mkdir -p /mnt/x
    sudo mount -o ro "$p" /mnt/x 2>/dev/null || continue
    sudo find /mnt/x -iname 'what-you-want*' 2>/dev/null
    sudo umount /mnt/x
done
```

⚠️ Mount **read-only**, always. These partitions are the only copy you have: postmarketOS does not
back them up, and a stock ROM re-flash is the only way back.

📌 These files name things nothing else does. The front camera's actuator, for instance, is
identified only there: `actuatorName = dw9800`. Guessing it from the I²C protocol alone cost a whole
session.

## Bluetooth firmware (needed for calls over a headset)

The generic `linux-firmware` build announces **HCI** transport, and with it no amount of correct
code works: the chip accepts the vendor route, negotiates SCO, and still emits over HCI. You need
the factory firmware, which is in its **own partition** — not in `vendor`:

```sh
sudo mkdir -p /mnt/bt && sudo mount -o ro /dev/disk/by-partlabel/bluetooth /mnt/bt
ls /mnt/bt/image/        # apbtfw*.tlv, apnv*.bin, crbtfw*.tlv, crnv*.bin
```

For the WCN3990 in this phone the pair is `crbtfw21.tlv` + `crnv21.bin`. Install them over the
generic ones (keep a backup first — the generic files are `.zst`-compressed):

```sh
sudo mkdir -p /root/fw-generic
sudo mv /lib/firmware/qca/crbtfw21.tlv.zst /lib/firmware/qca/crnv21.bin.zst /root/fw-generic/
sudo cp /mnt/bt/image/crbtfw21.tlv /mnt/bt/image/crnv21.bin /lib/firmware/qca/
```

Check it took at chip startup: `QCA Downloading qca/crbtfw21.tlv` and `qca/crnv21.bin` in dmesg.
It does not affect normal (non-Bluetooth) calls, so it can stay in place permanently.

⚠️ **Honest caveat.** The exact files that are running on our phone were extracted on 2026-07-19
and their provenance was never written down; they do **not** match the copy in this partition
(228956 vs 230260 bytes, different checksums), so they must have come from somewhere else — a
stock ROM dump, most likely. The partition copy is the one you can actually reproduce; if it does
not work for you, that difference is the first thing to look at.

## The factory device tree

Useful as a reference for camera topology, GPIOs and regulators. It is **not** on the device — the
`dtbo` partition is zeroed by the postmarketOS install — but it is inside the stock ROM image:

```
images/dtbo.img → overlay 7 is surya (qcom,msm-id = <0x16d 0x00>, i.e. 365)
```

⚠️ `atoll` is a **different SoC** (msm-id 407). This phone reports 365 and its downstream name is
`sdmmagpie`. Using atoll's data as a reference caused three separate wrong turns.
