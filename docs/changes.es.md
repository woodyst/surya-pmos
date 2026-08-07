# LISTA de todos los cambios — Xiaomi POCO X3 NFC "surya" (SM7150) en postmarketOS

Dispositivo: `sm7150-xiaomi-surya` (POCO X3 NFC, codename **surya**, panel Huaxing/Tianma).
Paquete de kernel: `linux-postmarketos-qcom-sm7150` (fork `github.com/sm7150-mainline/linux`, tag `v7.1_rc3`).
Paquete de dispositivo: `device-qcom-sm7150` (compartido por todos los sm7150).

Leyenda estado: ✅ funciona · 🟡 parcial/pendiente verificar · ⛔ bloqueado.

---

## 1. KERNEL — 115 parches (`kernel/`, aplicados por el APKBUILD sobre el tag limpio)

Serie **regenerada desde git el 2026-08-06**. La anterior tenía 83 y **estaba incompleta**: 73
aplicaban y 10 fallaban porque faltaban commits intermedios. Ésta aplica limpia sobre el tag
virgen, reproduce el kernel desplegado **bit a bit** y **compila** (ver
`VERIFICACION-2026-08-06.md`). Equivalencias viejo→nuevo en `kernel/EQUIVALENCIAS.md`.

| # | Asunto del parche | Estado |
|---|---|---|
| 0001 | arm64: dts: qcom: sm7150-xiaomi-common: fix USB-C to | ✅ |
| 0002 | power: supply: add TI BQ25970 switched-capacitor | ✅ |
| 0003 | arm64: dts: qcom: sm7150-xiaomi-common: raise max | ✅ |
| 0004 | power: supply: qcom_qg: use empirically-calibrated | ✅ |
| 0005 | ASoC: qcom: sm8250: call set_fmt() on every codec DAI | ✅ |
| 0006 | ASoC: tas2562: force a real hardware reset pulse at | ✅ |
| 0007 | ASoC: tas2562: widen reset pulse settle time to 100ms | ✅ |
| 0008 | ASoC: qcom: experimental TAS256x smart-amp AFE module | ✅ |
| 0009 | Revert: remove experimental smart-amp AFE call from | ✅ |
| 0010 | ASoC: qcom: fix TAS256x smart-amp AFE experiment port | ✅ |
| 0011 | Revert: remove smart-amp AFE call from sm8250.c | ✅ |
| 0012 | ASoC: qcom: q6afe-dai: try smart-amp AFE registration | ✅ |
| 0013 | ASoC: tas2562: write vendor test-page registers at | ✅ |
| 0014 | ASoC: tas2562: replicate the rest of the vendor | ✅ |
| 0015 | ASoC: tas2562: implement book-switching for the last | ✅ |
| 0016 | ASoC: tas2562: apply the real tas256x_reg.bin | ✅ |
| 0017 | Revert: remove the smart-amp AFE experiment from | ✅ |
| 0018 | ASoC: tas2562: set the RX slot length from hw_params, | ✅ |
| 0019 | arm64: dts: qcom: sm7150-xiaomi-surya: wire up the | ✅ |
| 0020 | ASoC: qcom: sm7150-xiaomi-surya: drive the tertiary | ✅ |
| 0021 | Revert "ASoC: qcom: sm7150-xiaomi-surya: drive the | ✅ |
| 0022 | ASoC: tas2562: write the digital volume as one burst, | ✅ |
| 0023 | ASoC: tas2562: drop the regmap defaults, they do not | ✅ |
| 0024 | ASoC: tas2562: mark TDM_CFG2 volatile so the channel | ✅ |
| 0025 | Revert "ASoC: tas2562: mark TDM_CFG2 volatile so the | ✅ |
| 0026 | ASoC: tas2562: re-assert the channel mux from the DAC | ✅ |
| 0027 | ASoC: tas2562: force the RX slot length too in the | ✅ |
| 0028 | ASoC/remoteproc: q6v5-pas keep modem proxy power vote | ✅ |
| 0029 | ASoC: qcom: q6voice: import CS voice-call driver from | ✅ |
| 0030 | arm64: dts: qcom: sm7150: wire up q6voice CS-Voice | ✅ |
| 0031 | arm64: dts: qcom: sm7150/surya: wire up WCD9375 | ✅ |
| 0032 | arm64: dts: qcom: sm7150: drop unimplemented LPASS | ✅ |
| 0033 | ASoC: codecs: wcd937x: use cansleep accessor for the | ✅ |
| 0034 | arm64: dts: qcom: sm7150: fix SoundWire controller | ✅ |
| 0035 | arm64: dts: qcom: sm7150: mux WCD9375 reset GPIO as | ✅ |
| 0036 | arm64: dts: qcom: sm7150: don't force WCD9375 reset | ✅ |
| 0037 | arm64: dts: qcom: sm7150-xiaomi-common: pin WCD9375 | ✅ |
| 0038 | pinctrl: qcom: sm7150-lpass-lpi: fix swr_tx_data mux | ✅ |
| 0039 | arm64: dts: qcom: sm7150: add SoundWire TX wake | ✅ |
| 0040 | arm64: dts: qcom: sm7150-xiaomi-surya: fix WCD9375 TX | ✅ |
| 0041 | regulator: add Will Semiconductor WL2866D camera PMIC | ✅ |
| 0042 | arm64: dts: qcom: sm7150-xiaomi-surya: add WL2866D | ✅ |
| 0043 | media: i2c: add Sony IMX682 sensor driver | ✅ |
| 0044 | arm64: dts: qcom: sm7150-xiaomi-surya: add IMX682 | ✅ |
| 0045 | arm64: dts: qcom: sm7150-xiaomi-common: fix CSIPHY | ✅ |
| 0046 | media: qcom: camss: vote for refgen on sm7150 | ✅ |
| 0047 | media: i2c: add Samsung S5K3T2 sensor driver | ✅ |
| 0048 | arm64: dts: qcom: sm7150-xiaomi-surya: add S5K3T2 | ✅ |
| 0049 | media: qcom: camss: follow the vendor's CSIPHY | ✅ |
| 0050 | media: qcom: camss: fix a typo in sm7150's cphy_rx | ✅ |
| 0051 | media: qcom: camss: keep sm7150's CSIPHY RX clock at | ✅ |
| 0052 | ASoC: qcom: q6voice: allow taking the call uplink | ✅ |
| 0053 | ASoC: qcom: q6voice: implement the CVS stream and | ✅ |
| 0054 | ASoC: qcom: q6voice: use the vendor's vocproc | ✅ |
| 0055 | WIP: load captured RX volume calibration into the DSP | ✅ |
| 0056 | ASoC: qcom: q6voice: pair CVD sessions using the | ✅ |
| 0057 | ASoC: qcom: q6voice: default the vocproc Tx topology | ✅ |
| 0058 | ASoC: qcom: q6voice: log the vocproc ports at call | ✅ |
| 0059 | media: qcom: camss: add a runtime-tunable settle | ✅ |
| 0060 | arm64: dts: qcom: sm7150-xiaomi-common: enable the | ✅ |
| 0061 | media: input: pm8xxx-vibrator: fix the drv2 (extended | ✅ |
| 0062 | arm64: dts: qcom: sm7150-xiaomi-surya: add a | ✅ |
| 0063 | arm64: dts: qcom: sm7150-xiaomi-common: the Bluetooth | ✅ |
| 0064 | ASoC: tas2562: live +/-6 dB gain/volume trim over | ✅ |
| 0065 | arm64: dts: qcom: sm7150-xiaomi-common: enable the | ✅ |
| 0066 | slimbus: qcom-ngd: fixes para que el NGD funcione en | ✅ |
| 0067 | Bluetooth: hci_qca: declarar HFP hw offload en el | ✅ |
| 0068 | ASoC: qcom: q6dsp: puerto SLIMBUS_7 completo para el | ✅ |
| 0069 | arm64: dts: qcom: sm7150-surya: SLIMBus NGD + WCN3990 | ✅ |
| 0070 | quitar el WIP de calibracion: alinear con la serie | ✅ |
| 0071 | ASoC: qcom: tomas de audio de llamada (in-call | ✅ |
| 0072 | q6voice: incall_taps desactivado por defecto y | ✅ |
| 0073 | q6voice: record_dirs para elegir direcciones de las | ✅ |
| 0074 | q6voice+q6routing: disparo de grabacion en llamada | ✅ |
| 0075 | ASoC: qdsp6: pseudo ports need real AFE config + | ✅ |
| 0076 | ASoC: qdsp6: fix in-call record/playback stop opcodes | ✅ |
| 0077 | ASoC: qdsp6: route audio into a call through the | ✅ |
| 0078 | Bluetooth: hci_qca: do not claim HFP hw offload on | ✅ |
| 0079 | input: touchscreen: nt36xxx: read the firmware size | ✅ |
| 0080 | media: qcom: camss: vfe: keep the interrupt disabled | ✅ |
| 0081 | arm64: dts: qcom: sm7150-xiaomi-surya: give call | ✅ |
| 0082 | ASoC: qdsp6: q6voice: arm the call taps the way the | ✅ |
| 0083 | ASoC: qdsp6: q6asm-dai: remember a stream that is | ✅ |
| 0084 | ASoC: qdsp6: q6routing: tell the voice stream before | ✅ |
| 0085 | ASoC: qdsp6: q6routing: rebuild the ADM matrix when a | ✅ |
| 0086 | ASoC: qdsp6: q6afe: set the AFE topology of the | ✅ |
| 0087 | ASoC: qdsp6: q6routing: knobs for the in-call | ✅ |
| 0088 | ASoC: qdsp6: match the vendor ADM/AFE command stream | ✅ |
| 0089 | ASoC: qdsp6: q6asm-dai: do not rebuild the DSP | ✅ |
| 0090 | ASoC: qdsp6: q6asm: open PCM streams with media | ✅ |
| 0091 | ASoC: qdsp6: q6asm: knob for the stream | ✅ |
| 0092 | ASoC: qdsp6: q6core: ask the DSP to load a topology's | ✅ |
| 0093 | ASoC: qdsp6: q6afe: send port parameters the way the | ✅ |
| 0094 | Bluetooth: hci_qca: let the core use SCO flow control | ✅ |
| 0095 | Bluetooth: check the right bit for Write Synchronous | ✅ |
| 0096 | Bluetooth: hci_qca: do not ask for SCO flow control | ✅ |
| 0097 | ASoC: qcom: sm8250: the Bluetooth SCO link is not 48 | ✅ |
| 0098 | ASoC: tas2562: resync the register page at every DAC | ✅ |
| 0099 | ASoC: qdsp6: q6voice: repeat a device move once, | ✅ |
| 0100 | ASoC: qcom: sm8250: register the card without | ✅ |
| 0101 | ASoC: qcom: sm8250: no esperar al propio trabajo al | ✅ |
| 0102 | slimbus: qcom-ngd-ctrl: arreglar la descarga del | ✅ |
| 0103 | slimbus: qcom-ngd-ctrl: quitar el of_node_put de mas | ✅ |
| 0104 | slimbus: no aplazar el sondeo si el dispositivo aun | ✅ |
| 0105 | ASoC: qdsp6: q6voice: fotografiar los puertos antes | ✅ |
| 0106 | Revert "ASoC: qdsp6: q6voice: fotografiar los puertos | ✅ |
| 0107 | media: qcom: camss: vfe: armar la interrupción antes | ✅ |
| 0108 | media: i2c: imx682: perilla `lane_mode` (diagnóstico) | ✅ |
| 0109 | media: qcom: camss: csiphy: perilla `settle_cnt` (diag.) | ✅ |
| **0110** | **media: qcom: camss: soporte C-PHY — LA CÁMARA FUNCIONA** | ✅ |
| 0111 | media: qcom: camss: relojes del bus para VFE1/VFE_LITE | ✅ |
| 0112 | media: i2c: imx682, s5k3t2: rotación y orientación | ✅ |
| 0113 | media: i2c: imx682: perillas de rotación y volteo (diag.) | ✅ |
| 0114 | dts: surya: motor de enfoque (intento con dw9714) | ⚠️ |
| **0115** | **media: dw9807-vcm: regulador + I2C no fatal — ENFOQUE OK** | ✅ |

## 2. PAQUETES userspace (abuild) (`packages/`)

| Paquete | Cambio | Por qué | Estado |
|---------|--------|---------|--------|
| **tqftpserv** 1.1.1→**1.2** | bump de versión (upstream commit `9ef11c0` "ACK short DATA packets in WRQ window mode") | **causa raíz del módem**: 1.1.1 no ACKeaba bloques DATA cortos en modo ventana → el módem no completaba su init de config → RF nunca online | ✅ |
| **libqmi** 1.38 (+patch) | `0001-qmicli-pdc-fix-invalid-free-of-mmapped-config.patch` | `qmicli --pdc-load-config` hacía `g_free()` de un puntero mmap → SIGSEGV | ✅ |

Ambos se compilaron con **abuild nativo en el dispositivo** (aarch64). También se pueden cross-compilar (ver scripts).

Paquetes **stock** (solo instalar + activar, sin build): `pd-mapper` (+systemd), `rmtfs` (+systemd/udev), `q6voiced` (+systemd), `callaudiod`.

---

## 3. AUDIO userspace / UCM (`audio/`)

| Elemento | Destino en el móvil | Estado |
|----------|---------------------|--------|
| `HiFi.conf` (perfil UCM) | `/usr/share/alsa/ucm2/Xiaomi/surya/HiFi.conf` | ✅ |
| Dispositivos UCM: **Speaker** (estéreo L/R real), **Earpiece** (top mono, quieto) | vía `ConflictingDevice` | ✅ |
| Dispositivo UCM **Mic** (AMIC1 → ADC1 → SoundWire TX → DEC0 → MultiMedia2) | **añadido 2026-07-17**; PipeWire ya expone el Source. Usa `hw:...,1` **a propósito**: MultiMedia1 lo ocupa el playback, y son FE DPCM con un cliente q6asm cada uno | ✅ |
| **Fix de sondeo de perfiles PipeWire/ACP** (2026-07-17, misma noche) | los `cset` de ruteo del Mic (mux + mixer, NO el volumen) se **duplicaron en el `EnableSequence` del `SectionVerb`**, porque ACP solo aplica el `EnableSequence` del *verbo* antes de sondear cada PCM candidato, nunca el del *dispositivo* — sin esto, `MultiMedia2` (el FE de captura) daba `EINVAL` al abrir (`dpcm_fe_dai_open`: "no valid Capture path") y **todos** los perfiles `HiFi` que incluyen Mic desaparecían de PipeWire como "not supported". Inofensivo: son solo selecciones de ruta DAPM, el bias/ADC analógico solo se enciende de verdad cuando hay una captura activa. Verificado: `HiFi (Earpiece, Mic)` y `HiFi (Mic, Speaker)` pasan a `available: yes` | ✅ **VERIFICADO** |
| `VoiceCall.conf` (perfil UCM de llamada) | `/usr/share/alsa/ucm2/Xiaomi/surya/VoiceCall.conf` | ✅ |
| **★ ENRUTAMIENTO Y VOLUMEN DE LLAMADA** (2026-07-19) | **RESUELTO**: auricular ↔ manos libres, **y volumen propio por modo** que atenúa la llamada de verdad. Clave: **PCM señuelo `MultiMedia3`** (kernel 0058) para que el perfil tenga sink → puerto (aplica el ruteo) y destino del volumen (`PlaybackVolume` → volumen digital del ampli, que está tras el mezclador del DSP). **Un ampli por modo** (arriba=auricular, abajo=manos libres, como el firmware de Xiaomi) para que cada uno tenga su control. Piezas: kernel **0058** + `VoiceCall.conf` + parche a **callaudiod** + `q6voice_device=3`. **El parche a PipeWire NO hace falta** (se conserva documentado por ser bug real de upstream). Documento maestro: **`audio/ENRUTAMIENTO-LLAMADA.md`**; verificación sin llamar: `audio/scripts/verify-call-routing.sh` | ✅ **VERIFICADO** |
| Scripts de ayuda: `audio-id.sh`, `audio-gain.sh`, `estereo.sh`, `test-estereo.sh`, `verifica-estereo.sh` | herramientas de calibración | ✅ |
| `scripts/rebuild-call-routing.sh` · `scripts/verify-call-routing.sh` | reinstalar los parches tras un `apk upgrade` · verificar el ciclo de llamada **sin llamar a nadie** | ✅ |
| `ARQUITECTURA-AUDIO.md` · `ENRUTAMIENTO-LLAMADA.md` | arquitectura de audio · enrutamiento de llamada | ref |

Notas: la tarjeta se resuelve como `xiaomi-XiaomiPOCOX3NFCHuaxing`; el perfil se carga vía `conf.d/sm8250/"POCO X3".conf`. Bluetooth funciona y **no** pasa por UCM (sink PipeWire aparte).

---

## 4. SENSORES / HEXAGON (`sensors/`) — ✅ FUNCIONAN **TODOS** (2026-08-06)

| Elemento | Qué es | Estado |
|----------|--------|--------|
| `hexagonrpcd/` (aport parcheado, **r9**, commit `9f987970f9` de `z3ntu/hexagonrpc@apps_std_fwrite`) | añade **soporte de registry escribible** al DSP | ✅ **este fue el fix** |
| `mount/setup-vendor-mount.sh` (+ wrapper) | monta vendor(ro)+overlay+persist para `/mnt/vendor/persist/sensors/registry` | ✅ necesario |
| `systemd-dropins/` (drop-ins de los 3 servicios hexagonrpcd) | `override-fwdir.conf`: `-R /usr/share/qcom/sm7150/Xiaomi/surya -P /mnt/vendor/persist/sensors/registry/` + `RequiresMountsFor=/mnt/vendor/persist` | ✅ necesario |

**Cómo se resolvió** (el bloqueo que la memoria antigua daba por perdido): el ADSP crasheaba en `SNS_REG_INIT` porque `hexagonrpcd` no sabía **escribir** el registry de sensores. Los patches del aport `0002-hexagonfs-add-read-write-support`, `0003-add-writable-sensor-registry-directory-override` (añade el flag `-P`), `0005-apps_std-implement-frename` y `0006-listener-dont-kill-connection-on-unsupported-call` habilitan la escritura; combinados con el drop-in `-P /mnt/vendor/persist/sensors/registry/` (registry escribible sobre la partición persist real) el DSP completa su `SNS_REG_INIT` y arranca los sensores.

**Funcionan los cuatro, con datos en vivo** (`monitor-sensor`): acelerómetro ✅, luz ambiental ✅,
proximidad ✅ y **magnetómetro / brújula ✅**.

★ **El magnetómetro NO faltaba** (corregido el 2026-08-06). La nota anterior decía que
`HasCompass` no existía en el sensor-proxy; **sí existe, pero en OTRO objeto de D-Bus**:
`/net/hadess/SensorProxy/Compass`, con su propia interfaz `net.hadess.SensorProxy.Compass`, no
en el objeto principal. Medido girando el móvil: 144 lecturas, **los cuatro cuadrantes** y 2141°
de recorrido angular acumulado, cruzando el 0/360 sin saltos.

⚠️ **Las banderas `Has*` no prueban nada por sí solas**: se leen `true` con el sensor sin
entregar datos. Y **mirar `/sys/bus/iio/devices` induce a error**: ahí solo salen los dos ADC del
PMIC; los sensores del ADSP no aparecen como dispositivos IIO. La comprobación buena es
`sudo monitor-sensor`, que reclama y muestra lecturas.

---

## 4b. GPS (`gps/`) — ★ RESUELTO (2026-07-18)

| Elemento | Qué es | Estado |
|----------|--------|--------|
| `gnss-engine-unlock.service` | **EL FIX**: el módem de Xiaomi trae el motor GNSS **bloqueado en NV** (*engine lock*); Android lo desbloquea en cada arranque desde el HAL y en pmOS nadie lo hacía → todo `START` (qmicli, ModemManager, cliente C propio) fallaba con el genérico `QMI error 46`. El servicio replica el desbloqueo (`qmicli -d qrtr://0 --loc-set-engine-lock=none`) tras ModemManager, con reintentos. Desplegado en `/etc/systemd/system/` y habilitado | ✅ **VERIFICADO** (NMEA fluyendo) |
| `loc_test.c` | cliente QMI LOC mínimo (API C de libqmi-glib/libqrtr-glib, `REGISTER_EVENTS`→`START`) — descartó la hipótesis del registro de eventos y acorraló la causa real | ✅ herramienta |
| Cableado userspace | ModemManager SÍ soporta localización aquí (`mmcli -m 0 --location-status`; ojo: NO sale en `mmcli -m 0` a secas); GeoClue ya trae `[modem-gps] enable=true` → apps GeoClue reciben GPS real sin tocar nada | ✅ |

Pendiente menor: confirmar fix al aire libre · XTRA fresco (TTFF) · gnss-share/gpsd para apps
NMEA ("Satellite"). Detalle completo: `gps/README.md`.

---

## 4c. WAYDROID (`waydroid/`) — RED ✅ ARREGLADA (2026-07-19)

Arrancaba bien pero se quedaba sin IP (`IP address: UNKNOWN`). **Dos causas apiladas**; arreglar solo una no da red.

| Elemento | Qué es | Estado |
|----------|--------|--------|
| `waydroid-modules.conf` | **FIX 1**: `netd` de Android usa iptables **legacy**, pero el host solo carga `nf_tables`/`nft_*` (su firewall es nftables) → `ip_tables` y familia nunca se cargan, `netd` no crea ninguna cadena (`Table does not exist`; decenas de `iptables-restore ... status=512`) y Android **ni intenta** pedir DHCP. Va a `/etc/modules-load.d/` | ✅ **VERIFICADO** |
| `60_waydroid.nft` | **FIX 2**: el firewall de pmOS (tabla `inet filter`, `policy drop` en `input` y `forward`) descarta el DHCP del contenedor — solo permite `bootps` en `usb*`/`wlan*`/`p2p-wlan*`. ⚠️ Que la tabla `inet lxc` de `waydroid-net.sh` lo acepte **no salva** al paquete: en nftables **cada tabla evalúa por separado**. Drop-in en `/etc/nftables.d/` | ✅ **VERIFICADO** |

Resultado: lease `<ip>`, `ping 8.8.8.8` 0% pérdida.

Pendiente menor (cosmético): las cadenas `st_*` de *strict mode* siguen fallando (`-m u32` y `-j NFLOG` no están en el kernel; los `CONFIG_` en el README). Ruido no relacionado: `com.android.nfc` hace coredump (Waydroid no tiene HAL de NFC).

**MIGRACIÓN DESDE UBUNTU TOUCH ✅ COMPLETADA (2026-07-19)**: 77 apps con sus datos y el `/sdcard` entero. **No hizo falta remapear UIDs** — los de Android son internos al contenedor e idénticos en ambos sistemas (0 ficheros con uid 32011 dentro de `data/`); solo el **directorio contenedor** lleva UID del host (`chown edi:edi`). La ventana transparente **se resolvió sola** por el camino (era el contenedor en mal estado, no gráficos). Detalle completo: `waydroid/README.md`.

---

## 4d. AUDIO BLUETOOTH Y LLAMADAS (`bluetooth-call/`) — ✅ (2026-08-06)

Auditado y automatizado el 2026-08-06: **hasta ese día no había paso de despliegue**, así que
una reproducción desde cero se quedaba sin todo esto. Ahora lo cubre
`scripts/70-bluetooth-llamadas.sh`, que toma el contenido exacto de los estados congelados.

| Elemento | Qué es | Estado |
|---|---|---|
| `54-offload.conf` | las **dos** propiedades del offload SCO: sin `bluez5.hw-offload-sco` PipeWire sigue bombeando ~330 paquetes/s por HCI y desestabiliza el chip | ✅ |
| `55-no-suspender.conf` | evita que la ruta interna se suspenda a los 5 s; ese ciclo de relojes LPASS **estrellaba el ADSP** en llamadas Bluetooth | ✅ |
| `56-mantener-voz-bt.conf` + `mantener-voz-bluetooth.lua` | enganche propio de wireplumber: mantiene el casco en camino de voz durante la llamada y lleva el volumen a la ganancia HFP (`+VGS`) | ✅ |
| `llamada-al-bluetooth.{sh,service}` | sostiene el enlace SCO y activa `bluetoothOffloadActive` | ✅ |
| `armar-audio-sistema.sh` + unidades | carga los módulos en el **orden correcto**: SLIMBus → wcn-bt-slim → hci_uart | ✅ |
| firmware BT **de fábrica** (`crnv21.bin`, `crbtfw21.tlv`) | el genérico no vale | ✅ |
| `q6voice_device=4` en `/etc/conf.d/q6voiced` | dispositivo de CS-Voice | ✅ |

⚠️ **El `.conf` y el guion lua van en directorios distintos**: el primero en
`~/.config/wireplumber/wireplumber.conf.d/`, el segundo en
`~/.local/share/wireplumber/scripts/device/`. Mal colocado, wireplumber **no arranca** (el
componente es `required`) y el móvil se queda sin audio.

⚠️ **Siempre CVSD, nunca mSBC**: `bt_sco_rate` está fijo a 8000 y con mSBC el enlace va a 16 kHz
→ silencio absoluto con todo lo demás aparentemente correcto.

**Abierto**: la vuelta al casco a mitad de llamada sigue muda (los mandatos HCI del enlace que
suena y del que no son *idénticos*, así que es estado interno del chip o del DSP), y las llamadas
seguidas se degradan (apagar y encender el Bluetooth lo cura).


## 5. Resumen de estado por subsistema

- ✅ **Carga / batería** (0001-0004)
- ✅ **Audio reproducción** (altavoz estéreo L/R, auricular, BT) — kernel 0005-0023 + UCM
- ✅ **Módem** (LTE + datos + SMS) — tqftpserv 1.2 + libqmi + pd-mapper + 0024
- ✅ **MICRÓFONO FUNCIONANDO (2026-07-17)** — **BLOQUEO RESUELTO** (parche **0036**, mux del pinctrl LPI): el SoundWire TX enumera, el códec proba entero (~685 controles), hay PCMs de captura y **PipeWire está sano** (el "dummy audio" era síntoma del mismo bug). **Falta** el front-end analógico: `MIC BIAS1` no enciende y se graban ceros (solo sale el transitorio de continua del ADC).
- ✅ **AUDIO DE LLAMADA COMPLETO (2026-07-18)** — salientes + entrantes, ambos sentidos (0052 nombre de sesión + 0053 topología TX + fix de carrera en UCM).
- ✅ **GPS (2026-07-18)** — el motor venía **bloqueado de fábrica** (engine lock NV); desbloqueo persistente vía `gps/gnss-engine-unlock.service`. NMEA fluyendo; GeoClue conectado. Falta confirmar fix al aire libre.
- ✅ **USB OTG / modo host (2026-07-31)** — QMP PHY habilitado (0061); webcam por OTG funcionando entera (source attach + VBUS + host + UVC). Trampas: wedge de la máquina typec (reiniciar) y boost solo-con-attach → `drivers/0002-usb-otg-host.md`.
- ✅ **Cuentas en línea / WebDAV (2026-08-01)** — el "login incorrecto" era una **carrera de arranque**: `goa-daemon` arrancaba antes que el llavero y no se recuperaba nunca. Arreglo persistente `goa/goa-keyring-fix.service`; manual: `pkill -f /usr/libexec/goa-daemon`. Ver `goa/README.md`.
- ✅ **Sensores** — acelerómetro + luz + proximidad + **magnetómetro** (hexagonrpcd r9 + registry escribible + montaje vendor/persist). **Ya no falta ninguno** (2026-08-06).
- ✅ **★AUTOENFOQUE FUNCIONANDO (2026-08-07)** — el actuador es un **DW9800** (parche kernel **0115**) y libcamera ahora lo conduce sola: parches propios en `packages/libcamera/` (pkgrel=7) que añaden una **medida de nitidez al ISP por software** y un algoritmo **por escalada** —paso, comparar, seguir mientras mejore, y al empeorar invertir y partir el paso—, con reenganche cuando la imagen se ablanda. Verificado por el usuario en la app: «enfoca rápido y reenfoca al cambiar distancia»; medido, **11 medidas** frente a 20 de un barrido fijo y mucho más fino. ⚠️Se hizo **autoenfoque y no manual** porque el manual no llega a las apps: el conector de PipeWire descarta esos controles y Snapshot no tiene interfaz (qcam probado y descartado). El autoenfoque salta ese muro porque ocurre **dentro de libcamera**. Detalle y trampas: `packages/libcamera/README.md`.
- ✅ **ENFOQUE MANUAL (2026-08-07)** — el actuador es un **DW9800** (lo nombra el blob del módulo: `actuatorName = dw9800`), de protocolo **por registros** como el DW9807, no como el DW9714. Parche **0115**: `dw9807-vcm` con soporte de regulador y fallos de I2C no fatales. Verificado: se piden 100/500/900 y el chip devuelve `0x0064`/`0x01F4`/`0x0384`, y el enfoque se ve cambiar en la vista previa. ⛔**Todavía no accesible desde las apps**: libcamera encuentra la lente pero su manejador «simple» no expone `LensPosition`/`AfMode` (en 0.7.1 **solo el de Raspberry Pi** lo hace). Plan escrito en `camera/README.md`.
- ✅ **CÁMARA TRASERA (2026-08-06)** — **hay foto y sale en la app** (Snapshot vía PipeWire). Causa raíz: el IMX682 transmite en **C-PHY** y el receptor estaba en D-PHY → soporte C-PHY en camss (**0110**), más 0107 (regresión nuestra del VFE), 0111 (relojes VFE1) y 0112 (rotación/orientación). libcamera la reconoce sola: `SimplePipelineHandler` ya trae `qcom-camss`, solo hay que `apk add libcamera-tools`. **Falta**: calidad de imagen (helper de sensor, calibración, enfoque) y el **sensor frontal**, que es D-PHY y sigue sin enlace. Expediente: `camera/README.md`.
- ✅ **NOTIFICACIONES: sonido y ★VIBRACIÓN (2026-08-07)** — tres causas apiladas. ★**La vibración iba al dispositivo equivocado**: surya tiene DOS (el del PMIC, que no mueve nada, y el motor háptico real `aw8695-haptics`), los dos etiquetados para feedbackd, y este cogía el primero → **desde julio se depuraba el driver equivocado**. + el demonio estaba **atascado** («Feedback already present» bloqueaba todo) + el tema de serie **no da sonido** a `notification-new-generic` en ningún perfil. Arreglos en `notificaciones/`: regla udev + tema propio `xiaomi,surya.json` (sonido, vibración 0,25/50 ms → 1,0/250 ms, y respuesta a las pulsaciones). ⚠️`fbcli` **no reproduce el caso real** (dispara otro evento): probar con `notify-send`.
- 🔧 **Llamadas por Bluetooth (2026-07-20)** — **bloqueo del acceso al chip RESUELTO**: el WCN3990
  responde (`slave rev 2.4 step 1`) y **sus puertos SCO se configuran**. Dos causas apiladas, ninguna
  del chip: **reintentar sin dormir** (responde `61/150` sin hueco, `0/150` con 50 ms) y un
  **desplazamiento base `0x800`** en el mapa de registros (leyendo crudo se lee una zona que responde
  con ceros → `rev 0.0 step 0`, que parece un chip mudo). Hechos además: `SLIMBUS_7` completo en el
  DSP, mapa de canales SLIMBus en `sm8250.c` (no tenía nada), códec ASoC en el driver, arreglo del
  NACK que no fallaba la transacción, y el perfil UCM **`Voice Call (Bluetooth)`**.
  **Falta**: probar una llamada real con auricular emparejado. Ver `parches/bluetooth-call/REPRODUCIR.md`.
- ⚠️ **Waydroid (2026-07-19)** — **red arreglada** (módulos iptables legacy + drop-in nftables); arranca con IP e internet. **Falta**: la ventana sale **transparente**, y migrar los datos del Waydroid de Ubuntu Touch.
