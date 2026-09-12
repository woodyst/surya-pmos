# Cancelación de eco en las llamadas

> Estado (2026-09-12, kernel r93): **funciona**. En llamadas reales cancela el eco, y medido con un
> tono metido en la llamada por el otro teléfono, el eco que vuelve por la subida de surya **baja
> unos 23 dB** respecto al paso directo.
>
> ⚠️ **Necesita la calibración de voz de fábrica, que no está en este repositorio** (son datos de
> Xiaomi). Sin ella, el servicio de arranque deja las llamadas en paso directo: funcionan igual que
> antes, sin cancelar el eco. Ver [La calibración](#la-calibración).

## Síntoma de partida

Con el auricular del móvil o el altavoz, **el otro lado se oye a sí mismo**. La subida del vocproc iba
en paso directo (`0x10F70`, parche 0057), porque la ECNS de serie `0x10F71` sin calibración saca silencio.

## Qué hacía falta (en el orden en que apareció)

| pieza | dónde | por qué |
|---|---|---|
| Topologías propias del fabricante registradas en el DSP (TX `0x10000003`, RX `0x10010F8B`) | kernel 0131 (`q6core custom_topologies`) | la calibración de Xiaomi usa sus propias topologías |
| Secuencia del vocproc como el downstream: CREATE **V3**, info de canales, formato del extremo **antes** del `TOPOLOGY_COMMIT`, registro de la calibración | kernel 0132, 0133 (`q6cvp create_v3`, `q6voice vendor_steps`) | con el CREATE V2 de mainline la topología del fabricante falla |
| Calibración de fábrica (flujo, config. de dispositivo, estática, volumen, con columnas) | `/lib/firmware/qcom/sm7150/xiaomi/surya/` (no incluida) | la ECNS sin su calibración no cancela |
| Mapear la calibración con `is_cached=1` | kernel 0134 (`q6mvm map_cached`) | con 0 el DSP responde `ADSP_EBADPARAM`; la cabecera del downstream solo admite 1 |
| **El PD de audio del ADSP servido** | `packages/hexagonrpcd` (0007–0010), `device/echo/hexagonrpcd-adsp-audiopd.service` | la canceladora **SMECNS V2 es un módulo dinámico** (`smecns_v2_module.so.1`) que el PD `audio_process` carga por fastrpc; la ROM lo sirve con `adsprpcd audiopd`; sin él, cualquier topología SMECNS V2 falla el commit |
| El dominio raíz sirviendo las bibliotecas | `device/echo/hexagonrpcd-adsp-rootpd.override-fwdir.conf` (`-R`) | sin `-R` servía un directorio vacío |
| Heap remoto del canal fastrpc del ADSP y sus VMIDs | kernel 0137 (DT: `memory-region` + `qcom,vmids <LPASS ADSP_HEAP>`) | el PD estático recibe su heap al crearse |
| Devolver el heap a HLOS antes de liberarlo; pool de 32 MiB | kernel 0138 | el PD de audio pide 3 MiB por llamada y los libera al colgar |
| Micro con las ganancias de Xiaomi (ADC1 12, TX_DEC0 84) | `device/audio/VoiceCall.conf` | PipeWire lo subía a 20: saturaba, distorsionaba y la canceladora no podía con el eco recortado |
| Silencio de verdad | kernel 0139 (`Voice Tx Capture Switch`) + `VoiceCall.conf` (`CaptureSwitch`) | el silencio anterior (`ADC1 Volume` 0) aún deja pasar −29 dB; el nuevo da silencio digital |
| Calibración por dispositivo | kernel 0140 (`Voice Calibration`: Handset, Speaker, Handset AEC, Speaker AEC) + `VoiceCall.conf` (`cset` en Earpiece y Speaker) | con un juego fijo, el manos libres usaba el volumen del auricular. Cambiarlo en plena llamada da de baja la calibración vieja, carga la nueva y rehace el vocproc |

Los parches 0135 (arrancar la llamada en `prepare`) y 0136 (extremos en estéreo) se probaron y no eran
la causa: van incluidos, apagados.

Cada arranque, `cancelacion-eco.service` (`activar-cancelacion-eco.sh`):
1. espera a los módulos de voz, a la calibración y al PD de audio;
2. registra las topologías y carga sus módulos;
3. **solo si todo va bien**, pone los parámetros.

Si algo falla, deja paso directo, y las llamadas funcionan igual pero sin cancelar el eco. Queda escrito
en el diario (`journalctl -u cancelacion-eco`). Ajustes en `/etc/default/cancelacion-eco` (`ECO=0`,
`CAL_SET=`).

## Instalar

1. Kernel r93 o posterior (`kernel/`) y `hexagonrpcd` de `packages/hexagonrpcd` (ver el README).
2. `scripts/install-on-device.sh <host>`: perfiles UCM, PD de audio, drop-in del dominio raíz y el
   servicio de arranque.
3. La calibración de fábrica en `/lib/firmware/qcom/sm7150/xiaomi/surya/`.
4. Reiniciar. Debe salir `✓ cancelación de eco lista` en `journalctl -u cancelacion-eco`.

## La calibración

El servicio espera en `/lib/firmware/qcom/sm7150/xiaomi/surya/`:
- `acdb-custom-topologies.bin`: el bloque de topologías propias de la ACDB (tipo 39);
- `voice-<juego>-{devcfg,static,vol,stream}.bin` y sus `-col`, para los juegos `handset` y `speaker`
  (y, si se quieren probar, `handset-aec` y `speaker-aec`).

Salen de la ACDB de Xiaomi, que está en la partición `vendor` de tu propio móvil. **No se redistribuyen
aquí.** Para obtenerlos hace falta ejecutar el cargador de la ACDB del fabricante y capturar lo que
envía al DSP. El script que lo hace desde tu móvil, sin copiar nada de nadie, **está en preparación**.
Mientras tanto, sin estos ficheros todo lo demás funciona y las llamadas van en paso directo.

## Medidas

El otro teléfono descuelga y mete un tono de 1 kHz pulsado en la llamada. Se mide la energía a 1 kHz
que vuelve por la subida de surya: en su toma del DSP y en lo que graba el otro teléfono.

| configuración | toma de surya | otro teléfono |
|---|---|---|
| paso directo | 16072 | 9725 |
| TX `0x10000003` + calibración de altavoz | 3937 | 1446 |
| TX `0x10000003` + RX `0x10010F8B` + calibración | **1101** | **648** |
| lo mismo con el micro en 0 (el silencio antiguo) | 39,5 | 48 |
| silencio en el DSP (`Voice Tx Capture Switch`) | silencio digital | 0 |

## Pendiente

- A volumen máximo, el manos libres distorsiona; un poco más bajo suena bien. El volumen del teléfono
  mueve el digital del amplificador (`Right Digital Volume Control`, 108 = 0 dB, con `Right Amp Gain
  Volume` 24 = +20,5 dB), y el paso de volumen del DSP va fijo (`q6voice rx_volume_step`, 4).
  Arreglos posibles: bajar la ganancia del amplificador en `Speaker` o llevar el volumen al paso del
  DSP, como hace el downstream.
- Los juegos de dos micros (`handset-aec`, `speaker-aec`, TX `0x10000005`).

## Trampas

- **Probar con los dos teléfonos en habitaciones distintas.** En la misma habitación, el altavoz de uno
  entra por el micro del otro y ese retorno no lo puede quitar ninguna canceladora.
- ⛔ `cancelacion-eco.service` **no puede ir `WantedBy=multi-user.target`**: `armar-audio.service` va
  después de multi-user, y esperar a él desde multi-user es un ciclo. systemd borra el trabajo en el
  arranque (`Found ordering cycle`) y la cancelación no se activa sola, aunque a mano funcione. Lo
  arrastra `armar-audio.service`.
- ⛔ No enganchar `strace` a `hexagonrpcd`: estrelló el ADSP, y la tarjeta de sonido no volvió sin
  reiniciar.
- ⛔ Anunciar los extremos en estéreo (`vendor_rx/tx_channels=2`) deja la subida en silencio.
- El PD de audio sin `ftell` rompe ASM (el audio normal) hasta reiniciar.
- El control de silencio **tiene que acabar en «Capture Switch»**: alsa-lib clasifica los controles
  por el nombre, y con otro nombre sale como interruptor de reproducción y PulseAudio/ACP no lo usa.
- El nombre del juego de calibración se escribe con `printf`, no con `echo`: el salto de línea acababa
  dentro del nombre del fichero de firmware.
