# Device configuration

The kernel gets the hardware working; these files make the system use it. Everything here is
installed **on the phone**, not built into the image.

`scripts/install-on-device.sh <host>` copies them all over SSH. What each one is:

## `audio/` — ALSA UCM

Where: `/usr/share/alsa/ucm2/conf.d/sm8250/`

| File | What it does |
|---|---|
| `POCO-X3.conf` | Card definition; points at the two verbs below |
| `HiFi.conf` | Music, stereo with correct L/R, earpiece, headset, Bluetooth |
| `VoiceCall.conf` | Calls: routing, a **per-mode volume that really attenuates the call**, mute in the DSP (`Voice Tx Capture Switch`), the mic gain fixed at the factory value, and the voice calibration set per device (`Voice Calibration`). ⚠️ Needs kernel **r93**: without those controls the call profile does not load |

⚠️ Call volume works through a **decoy PCM** (`MultiMedia3`): it carries no call audio and exists
only so the profile has a sink, which is what makes the routing run at all and gives the volume
somewhere to land. Without it **the routing is never executed**. The `cset` lines must live in the
`SectionVerb`.

## `wireplumber/` — Bluetooth and call policy

Where: the `.conf` files in `~/.config/wireplumber/wireplumber.conf.d/`, and the **Lua scripts in
`~/.local/share/wireplumber/scripts/device/`** — except `node/suspend-node-surya.lua`, which goes in
`~/.local/share/wireplumber/scripts/node/`.

⚠️ Putting the Lua files anywhere else makes **wireplumber refuse to start**.

| File | What it does |
|---|---|
| `54-offload.conf` | Hands SCO to the chip — `bluez5.hw-offload-sco = true` is the one that matters |
| `55-no-suspender.conf` | Stops the internal route suspending after 5 s, which used to crash the DSP |
| `56-mantener-voz-bt.conf` | Loads the Lua hook below |
| `mantener-voz-bluetooth.lua` | Forces the hands-free profile during a call, from inside wireplumber |
| `find-voice-call-profile.lua` | Finds the call profile for the card |
| `57-suspender-en-llamada.conf` + `node/suspend-node-surya.lua` | Lets idle audio nodes suspend again — keeping them always running cost ~300 mA at idle — **except during a call**, when remounting the internal route used to crash the DSP. It is a full component because only one that declares `requires = [ support.modem-manager ]` actually receives the call notifications |

⚠️ Never mSBC: this chip's SCO rate is fixed at 8 kHz and mSBC gives silence.

## `notifications/` — sound and vibration

| File | Where | Why |
|---|---|---|
| `73-surya-vibra.rules` | `/etc/udev/rules.d/` | The phone has **two** vibration devices and feedbackd picks the first — which is the PMIC one, that accepts commands and moves nothing. This untags it so the real haptic motor is used |
| `xiaomi,surya.json` | `/usr/local/share/feedbackd/themes/` | Adds **sound** to generic notifications (the stock theme gives them none, in any profile), raises the vibration and adds haptics on key presses |

⚠️ `/usr/local`, not `/usr/share`: a package upgrade would wipe the latter. feedbackd looks in
`/usr/local` first.

## `services/`

| File | Where | What it does |
|---|---|---|
| `armar-audio.service` + `armar-audio-sistema.sh` | system | Loads the audio and Bluetooth chain in the right order after boot |
| `armar-audio-usuario.service` + `armar-audio-usuario.sh` | user | Arms PipeWire and the call daemons afterwards |
| `llamada-al-bluetooth.service` + `supervisor-llamada-bt.py` | user | **Headset call supervisor**, replacing the old `llamada-al-bluetooth.sh` (the unit keeps its name). Event-driven over D-Bus (ModemManager and PipeWire), no polling: brings up the headset side when a call starts (voice profile, and the SCO link acquired through the device's `bluetoothOffloadActive`), tears it down when you switch to the speaker, rebuilds it when you come back, watches it and notifies. Needs `py3-gobject3`. See [`bt-return-to-headset.es.md`](../docs/bt-return-to-headset.es.md) and [`hfp-race.es.md`](../docs/hfp-race.es.md) |
| `aviso-bt-caido.service` + `.sh` | user | Watches the kernel log and warns when the Bluetooth controller is wedged: reboot, and **do not touch Bluetooth** — every reconnect attempt against a dead controller has hung or reset this phone. ⚠️ It never queries the adapter; that hangs too. See [`bt-chip-wedged.es.md`](../docs/bt-chip-wedged.es.md) |
| `hfp-registrado.service` + `.sh` | user | Watches that the **live** WirePlumber is the one holding the HFP profile registration, and restarts it if it lost the boot race. Without this, every headset call can come out mute for a whole boot — and rebooting does not fix it |
| `gnss-engine-unlock.service` | system | The GNSS engine ships **locked in NV**; Android unlocks it on every boot, this does the same |
| `goa-keyring-fix.service` | user | `goa-daemon` starts before the keyring and never recovers; this restarts it |

## `echo/` — echo cancellation in calls

See [`echo-cancellation.es.md`](../docs/echo-cancellation.es.md). Needs kernel r93 and `hexagonrpcd`
from [`packages/hexagonrpcd`](../packages/hexagonrpcd), and the factory voice calibration in
`/lib/firmware/qcom/sm7150/xiaomi/surya/`, which is **not** included. Without the calibration the calls
stay in passthrough and work as before.

| File | Where | What it does |
|---|---|---|
| `hexagonrpcd-adsp-audiopd.service` | `/etc/systemd/system/` | Serves the ADSP's **audio PD**, like the vendor's `adsprpcd audiopd`. The canceller (SMECNS V2) is a dynamic module that PD loads over fastrpc: without it the topology never commits |
| `hexagonrpcd-adsp-rootpd.override-fwdir.conf` | `/etc/systemd/system/hexagonrpcd-adsp-rootpd.service.d/override-fwdir.conf` | Gives the root PD's daemon `-R`, so it serves the ADSP's libraries instead of an empty directory |
| `cancelacion-eco.service` + `activar-cancelacion-eco.sh` | `/etc/systemd/system/`, `/usr/local/sbin/` | On every boot: registers the vendor topologies in the DSP, loads their modules and, **only if that worked**, sets the kernel parameters. On any failure it leaves passthrough and says so in the journal |

⚠️ `cancelacion-eco.service` is pulled in by `armar-audio.service`, **not** by `multi-user.target`:
`armar-audio` runs after multi-user, so waiting for it from there is an ordering cycle and systemd
silently drops the job at boot.

## `modprobe/` — kernel module options

Where: `/etc/modprobe.d/`

| File | What it does |
|---|---|
| `slimbus.conf` | ★ `remove_channels=1` for the SLIMbus controller (kernel patch 0130). **Without it, moving a call from the speaker back to a Bluetooth headset comes back mute both ways.** The controller is loaded by `armar-audio-sistema.sh` with `modprobe --ignore-install`, which does read `options`. See [`bt-return-to-headset.es.md`](../docs/bt-return-to-headset.es.md) |
| `q6voice.conf` | Keeps `switch_full_session` (patch 0129) **off**. Rebuilding the whole voice session on every move was tried for the same bug, did not fix it, and once coincided with a DSP crash |

## Load order matters

Bluetooth and audio must come up in this order, or the chip does not enumerate:

```
SLIMBus → wcn-bt-slim → hci_uart      (Bluetooth last)
```

The camera modules are deliberately **blacklisted** and loaded by hand once the system has settled:
loading them from udev at boot takes the phone down.

⚠️ Camera load order is `dw9807_vcm → qcom_camss → imx682 → s5k3t2`, and `camss` waits for **every**
sensor in the device tree — if the front one fails to probe, **no camera appears at all**.
