# postmarketOS on the Xiaomi POCO X3 NFC (`surya`, SM7150)

Patches and configuration that turn mainline postmarketOS on the POCO X3 NFC into a phone you can
actually use: calls with audio, mobile data, camera with autofocus, sensors, GPS, Bluetooth
headsets and notifications that ring and buzz.

Everything here is built on top of the [sm7150-mainline](https://github.com/sm7150-mainline/linux)
kernel fork and postmarketOS' own packages. Nothing here replaces them — it is an overlay.

> **Read this first:** this is a hobbyist port, not a product. It has rough edges, listed honestly
> in [What does not work](#what-does-not-work). It is also **not verified end to end on a clean
> install yet** — see [Status of these instructions](#status-of-these-instructions).

## What works

| | |
|---|---|
| **Calls** | Outgoing and incoming, **audio both ways**, earpiece ⇄ speaker switching with independent volume |
| **Mobile data / SMS** | LTE, data and SMS |
| **Audio** | Stereo speakers with correct L/R, earpiece, headset, per-amplifier trim |
| **Bluetooth** | A2DP music, automatic switching, **calls through a headset** with SCO offloaded to the chip |
| **Rear camera** | Photos and video, correct orientation, **working autofocus** |
| **Sensors** | Accelerometer, light, proximity and magnetometer |
| **GPS** | The engine ships locked in NV from the factory; unlocked persistently here |
| **USB OTG** | Host mode, verified with a webcam |
| **Notifications** | Sound **and vibration**, plus haptic feedback on key presses |
| **Charging** | Including the switched-capacitor charger |

## What does not work

- **Front camera.** The sensor reports that it is streaming and the receiver is configured to
  match, yet not a single packet arrives. Several hypotheses have been closed with measurements
  (it is D-PHY, not C-PHY; lane count, lane assignment and mux polarity all match the factory
  blob). Its I²C also fails intermittently, and when the probe fails **libcamera sees no camera at
  all**, not even the rear one.
- **Vibration is weak**, even at maximum. The actuator is a linear motor and only performs at its
  resonant frequency; the driver may not calibrate it.
- **The phone hangs on its own now and then**, roughly once or twice a night, with no trace of any
  kind — the signature of the hardware watchdog. Cause unknown.
- **Image quality is uncalibrated**: the software ISP has no tuning file for this sensor, so photos
  look washed out with dark corners.
- **Zoom**: the sensor driver exposes a single mode; the factory firmware has five.
- Bluetooth: returning to the headset mid-call stays silent, and consecutive calls degrade until
  Bluetooth is power-cycled.

## Requirements

- [`pmbootstrap`](https://wiki.postmarketos.org/wiki/Pmbootstrap) with a `pmaports` checkout.
- A POCO X3 NFC (`surya`) with an unlocked bootloader.
- Patience with a device that reboots itself occasionally.

## Building an image

The kernel package here is an overlay on postmarketOS'. Copy it over the aport, then build as
usual:

```sh
git clone https://github.com/<user>/surya-pmos
cd surya-pmos

# 1. Kernel: 115 patches, the recipe and the config
PMAPORTS=$(pmbootstrap config aports)
cp kernel/*.patch kernel/APKBUILD kernel/config-* \
   "$PMAPORTS/device/testing/linux-postmarketos-qcom-sm7150/"

# 2. libcamera with autofocus. Keep the patches already shipped by postmarketOS
#    (0001-0003) — ours are 0004 and 0005 and the APKBUILD lists all of them.
cp packages/libcamera/*.patch packages/libcamera/APKBUILD "$PMAPORTS/temp/libcamera/"

# 3. Checksums and build
pmbootstrap checksum linux-postmarketos-qcom-sm7150 libcamera
pmbootstrap shutdown          # see the pitfalls below
pmbootstrap install
```

⚠️ **`pmbootstrap checksum` leaves its chroot mounted**, and the next build then fails with
*"Failed to umount … /mnt/pmbootstrap/packages"*. Run `pmbootstrap shutdown` in between.

⚠️ **If a package will not rebuild**, bump its `pkgrel`: pmbootstrap reports "up to date" and skips
it otherwise.

## Installing the device configuration

The kernel alone is not enough: audio routing, notifications and the call daemons live in
userspace. See [`device/README.md`](device/README.md) for what each file is and where it goes, or
run the helper:

```sh
scripts/install-on-device.sh <hostname-or-ip>
```

## What is deliberately **not** here

No proprietary firmware. Running this phone needs blobs from its own factory partitions — audio
calibration (ACDB), DSP firmware, camera sensor configuration — and those belong to Xiaomi and
Qualcomm, not to this project. **They are not redistributed here.**

They are already on your device: postmarketOS does not erase the `vendor` partition, so they can be
read from it. [`docs/blobs.md`](docs/blobs.md) explains which ones matter and how to extract them
from your own phone.

Also excluded: audio recordings, Bluetooth traces and register dumps from the development sessions.
They carry voices, addresses and identifiers, and none of it is needed to reproduce anything.

## Status of these instructions

Honest disclosure: this overlay is **known to work**, because the phone it was developed on runs
it, and the kernel series is verified to apply cleanly, reproduce the deployed kernel bit for bit
and compile. But **the whole recipe has never been run start to finish on a clean postmarketOS
install**. If you try it, expect gaps, and please report them.

## Licences

The kernel patches are derived work of the Linux kernel and are **GPL-2.0**. The libcamera patches
are **LGPL-2.1-or-later**, matching upstream. Configuration files and scripts are published under
the same terms as the projects they extend. See [`NOTICE.md`](NOTICE.md).

## Documentation

- [`docs/`](docs/) — per-subsystem notes: what was wrong, how it was found, and the traps.
- [`kernel/`](kernel/) — the patch series, one commit per fix.
- [Spanish version of this file](README.es.md).
