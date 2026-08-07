# Audio de llamada por Bluetooth en surya: la estructura completa

Como esta montado el camino que **si funciona** (verificado en llamada real con un auricular de
verdad el 2026-08-03: micro del auricular → otro extremo con contraste 436840x, y la voz del
otro extremo saliendo por el auricular). Esto es el "que hay que poner y por que"; el relato de
como se llego esta en `POR-QUE-COSTO-TANTO.md` y el detalle de las medidas en
`OFFLOAD-SLIMBUS-ESTADO.md`.

⚠️ **Antes de reproducir esto**, leer `../ESTADO-COMPATIBLE.md`: tal cual esta, este montaje
**deja la tarjeta de sonido dependiendo del codec Bluetooth**, y hay un problema abierto con el
auricular del movil.

---

## La idea en una frase

El audio de la llamada **no pasa por la CPU**: va del DSP (QDSP6) al chip Bluetooth (WCN3990)
por **SLIMBus**, y el chip lo pone en el aire. El enlace SCO existe, pero **solo como enlace** —
por el no viaja el audio. Es lo que hace el firmware de fabrica.

```
  modem ──► DSP (q6voice/CVP) ──► AFE SLIMBUS_7_RX ──┐
                                                     │  SLIMBus, canal 157
                                          WCN3990 ◄──┘   puerto PGD 16
                                             │
                                             └──► aire (eSCO/CVSD) ──► auricular
                                             ◄──  aire ◄── microfono
                                          WCN3990 ──┐
                                                    │  SLIMBus, canal 159
  modem ◄── DSP (CVP) ◄── AFE SLIMBUS_7_TX  ◄───────┘   puerto PGD 0
```

---

## 1. Firmware del chip — **imprescindible, y es lo que lo tapaba todo**

El WCN3990 elige **en su NV** por donde saca el audio (HCI / PCM / I2S / SLIMBus). El NV
generico de linux-firmware dice **HCI**, y con el **ninguna cantidad de codigo correcto
funciona**: el chip acepta la ruta vendor, negocia el SCO, y sigue emitiendo por HCI.

```sh
# copia de seguridad de los genericos
sudo mkdir -p /root/fw-generico
sudo mv /lib/firmware/qca/crnv21.bin.zst   /root/fw-generico/
sudo mv /lib/firmware/qca/crbtfw21.tlv.zst /root/fw-generico/
# los de fabrica (archivados en firmware-fabrica/, extraidos del movil el 2026-07-19)
sudo cp firmware-fabrica/crnv21.bin firmware-fabrica/crbtfw21.tlv /lib/firmware/qca/
```

Se comprueba en el arranque del chip: `QCA Downloading qca/crbtfw21.tlv` + `qca/crnv21.bin`.
**No afecta a las llamadas normales**, asi que puede quedarse puesto siempre.

## 2. Arbol de dispositivos — los enlaces DAI de SLIMBUS_7

`0007-dts-enlaces-dai-slimbus7-restaurados.patch`: añade `slim7-rx-dai-link` y
`slim7-tx-dai-link` (cpu `<&q6afedai SLIMBUS_7_RX/TX>`, platform `<&q6routing>`, codec
`<&bt_audio 0/1>`).

⚠️ **Consecuencia**: la tarjeta pasa a depender del codec `wcn-bt-slim`. Sin ese modulo,
`/sys/bus/platform/devices/sound` se queda en `waiting_for_supplier` y **no hay audio de ningun
tipo**. Ver `../ESTADO-COMPATIBLE.md`.

## 3. Parches de kernel

| parche | que hace | por que |
|---|---|---|
| `kernel/0078-q6afe-bloque-slimbus-del-puerto.patch` | rellena `slimbus_dev_id` (=1) y deja `data_format` en 0 | ★ **el fallo de mainline**: el campo iba a cero, el ADSP respondia `Success` a todo y **el puerto no movia una sola muestra**. El `I/O error` del PCM era la espera agotada de ALSA, no un error del DSP |
| `kernel/0079-q6voice-mover-la-llamada-de-dispositivo.patch` | rehace el vocproc al cambiar de puerto con la llamada viva | el CVP se construia **una sola vez** con lo que hubiera enrutado, y wireplumber elige el perfil **despues** de arrancar la sesion de voz → la llamada se quedaba siempre en el auricular del movil |
| `kernel/0077-sm8250-tasa-del-enlace-bluetooth.patch` | `bt_sco_rate` (8000 CVSD / 16000 mSBC) para los enlaces SLIMBUS_7 | el resto del sistema es 48 kHz estereo; forzar eso aqui le da al chip seis veces las muestras que lee |
| `bluetooth-call/0006-hci-qca-ruta-de-datos-sco-ajustable.patch` | `hfp_datapath` como parametro | para barrer el identificador de ruta de datos. **Resulto no cambiar nada** (barrido 0..4 midiendo el aire); se conserva porque el barrido es la evidencia |
| `kernel/0075`, `kernel/0076` | control de flujo SCO y el bit correcto | `0076` es **un fallo real de mainline** (`hdev->commands[10] & BIT(4)` debia ser `BIT(2)`). El control de flujo en si se deja **apagado**: el chip lo anuncia, lo acepta, dice que esta activo y **nunca devuelve creditos** |
| `bluetooth-call/0004` | NACK y carrera del runtime resume del NGD | estabilidad del bus |

## 4. `wcn-bt-slim` — el codec del chip en el bus

Modulo fuera del arbol, fuente completa en `wcn-bt-slim/wcn-bt-slim.c`. Registra el WCN3990
como codec SLIMBus con dos DAI (SCO rx/tx). Lo que costo acertar:

- **La reserva del canal va en `hw_params`, no en `prepare`.** ALSA ejecuta todos los
  `hw_params` antes que ningun `prepare`, y el DSP arranca su puerto desde el suyo: reservando
  desde `prepare` el canal llegaba tarde. (Estaba ademas **solo en un gancho de prueba manual**
  y las operaciones del DAI no lo llamaban nunca.)
- **Marca de agua**: el campo son 3 bits desde el bit 1 → recepcion `ENABLE|WM_LB` = **0x17**,
  transmision `ENABLE|WM_L1` = **0x03** + autorecuperacion en `0x01F0+n`. Antes se escribia
  `0x19`, que cae en bits sueltos. Valores sacados del driver descendente
  `btfm_slim_wcn3990.{c,h}`.
- **Bit de canal del puerto de subida**: `1 << port` con port=0 → **0x01**. Con `0x02` la
  bajada iba y la subida daba **silencio digital exacto**.
- Puertos y canales: PGD **16** / canal **157** (hacia el auricular), PGD **0** / canal **159**
  (microfono).

⚠️ **Vive en `$HOME/wcn-bt-slim.ko`, fuera de `/lib/modules`, a proposito**: si udev lo
carga antes que `hci_uart`, coge el chip y el adaptador se queda en `DOWN RAW` hasta reiniciar.

## 5. Orden de carga — no es negociable

```sh
sudo modprobe --ignore-install hci_uart hfp_offload=1   # Bluetooth PRIMERO
sudo hciconfig hci0 up
sudo modprobe --ignore-install slim_qcom_ngd_ctrl
sudo insmod $HOME/wcn-bt-slim.ko
sudo modprobe snd_soc_sm8250                            # el audio, al final
```

(`scripts/cargar-offload.sh` + el audio; `banco-pruebas/ciclo-offload.sh` hace el ciclo entero
incluido el reinicio.)

## 6. Espacio de usuario

**UCM** — `../../audio/VoiceCall.conf`, dispositivo `SectionDevice."Bluetooth"`: apaga
`TERT_MI2S_RX Voice Mixer CS-Voice` y `CS-Voice Capture Mixer TX_CODEC_DMA_TX_3`, enciende
`SLIMBUS_7_RX Voice Mixer CS-Voice` y `CS-Voice Capture Mixer SLIMBUS_7_TX`, baja
`TX_AIF1_CAP Mixer DEC0` y apaga el micro del WCD.

⚠️ **`PlaybackPriority 50`, la mas baja de las tres, a proposito**: UCM no sabe nada de
Bluetooth y anuncia ese perfil como **disponible aunque no haya casco** (comprobado), asi que
con prioridad alta se llevaria TODAS las llamadas y las dejaria mudas.

**wireplumber** — `wireplumber-llamada/find-voice-call-profile.lua` en
`~/.local/share/wireplumber/scripts/device/`. Es **quien elige el perfil al empezar la llamada**
(demostrado con ftrace sobre `snd_ctl_elem_write`: 30 escrituras, **todas suyas**, ninguna de
callaudiod). El añadido prefiere el perfil BT **solo si existe un dispositivo `bluez5`**.

**callaudiod** — `../../audio/callaudiod/0001-boton-de-salida-con-auricular-bluetooth.patch`.
El boton de salida: con casco conectado alterna **auricular Bluetooth ↔ altavoz**; sin casco,
auricular del movil ↔ altavoz como siempre.

**Servicio del SCO** — `scripts/llamada-al-bluetooth.{sh,service}`. Sostiene el enlace SCO
reproduciendo silencio mientras dura la llamada.

⚠️ **Va aparte de callaudiod a proposito**: el enlace tiene que existir **antes** de que se
apliquen las rutas. El DSP abre su lado en cuanto caen los controles del mezclador, y si en ese
instante los puertos SCO del chip siguen dormidos **ya no se recupera**. Medido: enlace antes →
443840x; enlace a la vez que el ruteo → **silencio en los dos sentidos con todos los registros
aparentemente correctos**.

⚠️ Dentro de una unidad de usuario no hay `DBUS_SESSION_BUS_ADDRESS`: un `systemd-run --user`
anidado falla en silencio. El silencio se lanza en segundo plano a secas.

## 7. Como se comprueba

- `banco-pruebas/ciclo-offload.sh` — ciclo entero (reinicio, cadena, PipeWire, auricular falso).
- `banco-pruebas/llamada-por-slimbus.sh` — llamada real, `SENTIDO=bajada|subida`.
- `banco-pruebas/analiza-tono.py` — dice si el tono conocido llego.

⚠️ **`pkill -f` y `pgrep -f` se emparejan con la propia linea de la orden de `ssh`.** Matar y
lanzar en la misma orden = el pkill se suicida, el agente no arranca, y se analiza la grabacion
de la prueba anterior sin que nada lo delate. Patron partido + guardian de frescura
(`find -newermt`), que dice `RANCIA`.

⚠️ **El chip Bluetooth se degrada con los ciclos de SCO**: tras varias llamadas seguidas da
llamadas mudas con todo el camino aparentemente correcto, y **solo se recupera reiniciando**.
Reiniciar antes de concluir nada.

## 8. Lo que NO hace falta (descartado con medida)

- **El identificador de ruta de datos SCO**: barrido 0..4 midiendo *el aire*. Ninguno cambia nada.
- **`HCI_Configure_Data_Path`**: el chip lo rechaza con `Unknown HCI Command`.
- **Reservar el canal desde Linux**: con `slimbus_dev_id=1` el DSP consume igual con la reserva
  apagada (`reservar=0`).
- **El parche a PipeWire**: verificado A/B, no hace falta.

## 9. Abierto

- **El boton de manos libres durante una llamada con casco** mueve el ruteo pero el audio no le
  sigue (dos causas identificadas en `OFFLOAD-SLIMBUS-ESTADO.md`).
- **El volumen con el casco no se puede ajustar**: el dispositivo `Bluetooth` del UCM no declara
  `PlaybackVolume`, y con el casco los amplis no estan en el camino, asi que ese elemento no
  serviria. Haria falta el volumen del DSP (`rx_volume_step`) o AVRCP.
- **El arranque automatico**, y el **auricular del movil**: ver `../ESTADO-COMPATIBLE.md`.
