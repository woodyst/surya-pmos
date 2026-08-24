*[Versión en español](README.es.md)*

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
| **Charging** | The battery charges and reports its level, with the BQ25970 charge pump driven and the current limit raised |
| **Battery life** | The phone **suspends properly**: a wakeup line was aborting every single suspend. **−46 %** idle draw (~34 h → ~64 h) |
| **Battery gauge** | The percentage used to be voltage on a straight line and was **19 points off** near empty; now IR-compensated against a measured OCV table |
| **GNSS constellations** | **Galileo and BeiDou reach applications**: ModemManager synthesises the NMEA the modem never emits |
| **Muting a call** | The mute button in the dialer actually mutes — on earpiece and speaker |
| **Remote screen** | VNC into the running phone (patched ) |

## What does not work

- **Front camera.** The sensor reports that it is streaming and the receiver is configured to
  match, yet not a single packet arrives. Several hypotheses have been closed with measurements
  (it is D-PHY, not C-PHY; lane count, lane assignment and mux polarity all match the factory
  blob). Its I²C also fails intermittently, and when the probe fails **libcamera sees no camera at
  all**, not even the rear one.
- **Vibration is weak**, even at maximum. The actuator is a linear motor and only performs at its
  resonant frequency; the driver may not calibrate it.
- **The phone hangs or reboots on its own.** These turned out to be **two different faults**,
  and telling them apart took a while:
  - **The freeze** is the storage: a deadlock between `ufshcd_exception_event_handler` — which
    waits on a device query holding the rwsem as a **reader** — and `ufshcd_devfreq_scale`, which
    wants it as a **writer**. Since the rootfs lives on UFS, everything that touches disk stops
    while the kernel stays **alive and idle**. **Mitigated** by disabling UFS clock scaling
    (`device/power/99-ufs-sin-escalado.rules`); the query still never returns.
  - **The panic** is IPA: `gsi_channel_trans_quiesce()` waits with **no timeout** for the modem's
    last GSI transaction (`drivers/net/ipa/gsi.c`). `irq/172-ipa`, which shows up in every
    signature, is a **victim**. ⛔ **Four different reproduction attempts, none of them work** —
    with a dead network the modem applies **backpressure** rather than stalling, so filling the
    queue is not enough.

  Either way the phone now **recovers by itself and leaves a full dump**: three panic detectors,
  all-CPU backtraces, and a **watchdog that demands the phone actually works** rather than just
  that PID 1 is breathing. See [`docs/watchdog.es.md`](docs/watchdog.es.md) and
  [`docs/ufs-freeze.es.md`](docs/ufs-freeze.es.md).

- **Image quality is uncalibrated**: the software ISP has no tuning file for this sensor, so photos
  look washed out with dark corners.
- **Zoom**: the sensor driver exposes a single mode; the factory firmware has five.
- Bluetooth: returning to the headset mid-call stays silent, and consecutive calls degrade until
  Bluetooth is power-cycled. **Muting the microphone does not work on a headset either**: the mic
  is the headset's, it comes in over SLIMBus and no gain control is exposed on that path. Giving
  the profile a source so the button had something to act on left the call with **no audio at
  all**, so it was reverted. Workaround: switch to speaker and mute there.
- **No A-GPS assistance.** Galileo and BeiDou now *do* reach applications (see above), but there
  is still no assistance data, so a cold fix takes its time. See
  [`packages/libqmi`](packages/libqmi) and [`tools/qmi-loc-idl`](tools/qmi-loc-idl).
- **Xiaomi's 33 W fast charge.** The charge pump works and the limit is raised, but the proprietary
  handshake that unlocks the high-power mode is not implemented, so a Xiaomi charger delivers only
  the standard rate.

## Requirements

- [`pmbootstrap`](https://wiki.postmarketos.org/wiki/Pmbootstrap) with a `pmaports` checkout.
- A POCO X3 NFC (`surya`) with an unlocked bootloader.
- Patience with a device that reboots itself occasionally.

## Building an image

The kernel package here is an overlay on postmarketOS'. Copy it over the aport, then build as
usual:

```sh
git clone https://github.com/woodyst/surya-pmos
cd surya-pmos

# 1. Kernel: 115 patches, the recipe and the config
PMAPORTS=$(pmbootstrap config aports)
cp kernel/*.patch kernel/APKBUILD kernel/config-* \
   "$PMAPORTS/device/testing/linux-postmarketos-qcom-sm7150/"

# 2. libcamera with autofocus. Keep the patches already shipped by postmarketOS
#    (0001-0003) — ours are 0004 and 0005 and the APKBUILD lists all of them.
cp packages/libcamera/*.patch packages/libcamera/APKBUILD "$PMAPORTS/temp/libcamera/"

# 3. libqmi with the GNSS constellation messages. Optional: everything else works
#    without it. libqmi is not in pmaports, so it is built out of temp/.
mkdir -p "$PMAPORTS/temp/libqmi"
cp packages/libqmi/*.patch packages/libqmi/APKBUILD "$PMAPORTS/temp/libqmi/"

# 4. Checksums and build
pmbootstrap checksum linux-postmarketos-qcom-sm7150 libcamera libqmi
pmbootstrap shutdown          # see the pitfalls below
pmbootstrap install
```

⚠️ **`pmbootstrap checksum` leaves its chroot mounted**, and the next build then fails with
*"Failed to umount … /mnt/pmbootstrap/packages"*. Run `pmbootstrap shutdown` in between.

⚠️ **If a package will not rebuild**, bump its `pkgrel`: pmbootstrap reports "up to date" and skips
it otherwise.

## Flashing it onto the phone

### 1. Unlock the bootloader

Xiaomi's own procedure: a Mi account, the Mi Unlock tool and a waiting period of several days. There
is no way around it, and nothing below works until it is done.

### 2. Find out which display your phone has

The POCO X3 NFC ships with **two different panels**, Huaxing and Tianma, and each needs its own
bootloader and its own device tree. Get it wrong and the phone boots to a **black screen** — it is
not bricked, it just shows nothing.

There is no reliable way to tell from the outside, so the practical method is trial: flash one, and
if the display stays black, flash the other. Nothing else is affected. Once postmarketOS is
running, the phone tells you:

```sh
cat /proc/device-tree/model      # → Xiaomi POCO X3 NFC (Huaxing)
```

### 3. Get u-boot

postmarketOS on this SoC boots through u-boot, which then chainloads systemd-boot. Prebuilt images
come from the sm7150-mainline project — **one per panel**:

**https://github.com/sm7150-mainline/u-boot/releases**

```
u-boot-sm7150-xiaomi-surya-huaxing.img
u-boot-sm7150-xiaomi-surya-tianma.img
```

### 4. Empty vbmeta images to disable verified boot

Android Verified Boot has to be turned off, which needs a vbmeta image to flash. Do not hunt for
the stock one: generate empty ones with
[`avbtool`](https://android.googlesource.com/platform/external/avb/) (Apache-2.0):

```sh
python3 avbtool.py make_vbmeta_image --flags 2 --padding_size 4096 --output vbmeta.img
cp vbmeta.img vbmeta_system.img
```

### 5. Flash

With the phone in fastboot (**Volume Down + Power** from a powered-off state):

```sh
# bootloader for YOUR panel
fastboot flash boot u-boot-sm7150-xiaomi-surya-huaxing.img

# the stock device tree overlays must go, or they fight the mainline one
fastboot erase dtbo

# disable verified boot on both vbmeta partitions
fastboot flash vbmeta        vbmeta.img        --disable-verity --disable-verification
fastboot flash vbmeta_system vbmeta_system.img --disable-verity --disable-verification

# the postmarketOS image built earlier
pmbootstrap flasher flash_rootfs

fastboot reboot
```

### If something goes wrong

**Hold Volume Up and Volume Down together while it boots** and u-boot offers a recovery menu,
including **USB mass storage**: the phone appears on your computer as a disk and you can repair the
install without reflashing. This has saved this port more than once.

⚠️ Note that **this phone never really powers off**: u-boot reboots it, even from its own menu.
Do not read a reboot as a failure to shut down.

⚠️ postmarketOS installs into a partition of its own **and does not erase the factory `vendor`
partition**, which is what makes the vendor blobs reachable later (see
[`docs/blobs.md`](docs/blobs.md)). Do not wipe it.

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
- [`tools/qmi-loc-idl/`](tools/qmi-loc-idl/) — decoder for the modem's QMI LOC interface
  table: all 470 messages, and the three that got implemented in
  [`packages/libqmi`](packages/libqmi).
- [Spanish version of this file](README.es.md).
