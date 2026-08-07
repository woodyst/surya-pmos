# Extracting the vendor blobs from your own phone

Nothing in this repository redistributes proprietary firmware. What follows reads it from **your**
device, where it already is: postmarketOS installs alongside the factory partitions and does not
erase them.

## Audio calibration (ACDB)

Needed for call audio to sound right. It lives in the `vendor` partition:

```sh
sudo mkdir -p /mnt/vendor
sudo mount -o ro /dev/disk/by-partlabel/vendor /mnt/vendor
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

📌 These files name things nothing else does. The front camera's actuator, for instance, is
identified only there: `actuatorName = dw9800`. Guessing it from the I²C protocol alone cost a whole
session.

## The factory device tree

Useful as a reference for camera topology, GPIOs and regulators. It is **not** on the device — the
`dtbo` partition is zeroed by the postmarketOS install — but it is inside the stock ROM image:

```
images/dtbo.img → overlay 7 is surya (qcom,msm-id = <0x16d 0x00>, i.e. 365)
```

⚠️ `atoll` is a **different SoC** (msm-id 407). This phone reports 365 and its downstream name is
`sdmmagpie`. Using atoll's data as a reference caused three separate wrong turns.
