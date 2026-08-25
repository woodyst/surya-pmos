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
| `VoiceCall.conf` | Calls: routing, and a **per-mode volume that really attenuates the call** |

⚠️ Call volume works through a **decoy PCM** (`MultiMedia3`): it carries no call audio and exists
only so the profile has a sink, which is what makes the routing run at all and gives the volume
somewhere to land. Without it **the routing is never executed**. The `cset` lines must live in the
`SectionVerb`.

## `wireplumber/` — Bluetooth and call policy

Where: the `.conf` files in `~/.config/wireplumber/wireplumber.conf.d/`, and the **Lua scripts in
`~/.local/share/wireplumber/scripts/device/`**.

⚠️ Putting the Lua files anywhere else makes **wireplumber refuse to start**.

| File | What it does |
|---|---|
| `54-offload.conf` | Hands SCO to the chip — `bluez5.hw-offload-sco = true` is the one that matters |
| `55-no-suspender.conf` | Stops the internal route suspending after 5 s, which used to crash the DSP |
| `56-mantener-voz-bt.conf` | Loads the Lua hook below |
| `mantener-voz-bluetooth.lua` | Forces the hands-free profile during a call, from inside wireplumber |
| `find-voice-call-profile.lua` | Finds the call profile for the card |

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
| `llamada-al-bluetooth.service` + `.sh` | user | Holds the SCO link up during a call with a headset. Waits until the call is actually *routed* to the headset before reaching for the link, and retries for 25 s — see [`hfp-race.es.md`](../docs/hfp-race.es.md) |
| `hfp-registrado.service` + `.sh` | user | Watches that the **live** WirePlumber is the one holding the HFP profile registration, and restarts it if it lost the boot race. Without this, every headset call can come out mute for a whole boot — and rebooting does not fix it |
| `gnss-engine-unlock.service` | system | The GNSS engine ships **locked in NV**; Android unlocks it on every boot, this does the same |
| `goa-keyring-fix.service` | user | `goa-daemon` starts before the keyring and never recovers; this restarts it |

## Load order matters

Bluetooth and audio must come up in this order, or the chip does not enumerate:

```
SLIMBus → wcn-bt-slim → hci_uart      (Bluetooth last)
```

The camera modules are deliberately **blacklisted** and loaded by hand once the system has settled:
loading them from udev at boot takes the phone down.

⚠️ Camera load order is `dw9807_vcm → qcom_camss → imx682 → s5k3t2`, and `camss` waits for **every**
sensor in the device tree — if the front one fails to probe, **no camera appears at all**.
