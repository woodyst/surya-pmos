
---

## 2026-08-20 · llamadas sin audio tras un cambio de SIM en caliente

**Síntoma**: las llamadas dejaron de funcionar, con y sin cascos.

**Lo que se descartó midiendo, no suponiendo**:

```
callaudiocli -m 1  ->  Active Profile: Voice Call (Earpiece)
                       sumidero alsa_output.platform-sound.Voice_Call__Earpiece__sink
callaudiocli -m 0  ->  vuelve a HiFi (Mic, Speaker)
```

La cadena de audio **nunca estuvo rota**: perfiles UCM, `callaudiod` y el sumidero de llamada
respondían a la primera.

**Lo que en realidad pasó**: el fallo vivía en el arranque en el que se cambió la SIM de ranura
**en caliente** (ver `../modem/RANURA-SIM.md`). Al reiniciar, la primera llamada funcionó:

```
11:18:48  reinicio
11:20:40  call state: unknown -> dialing
11:20:40  Started dbus-...org.mobian_project.CallAudio@1.service
11:21:01  call state: ringing-out -> active     (PCM en marcha 35 s)
```

⛔ **La causa NO está establecida**: el estado roto se perdió con el reinicio. Si se repite,
lanzar `scripts/capturar-llamada.sh` **ANTES** de reiniciar.

⚠️ **Corrección a una conclusión propia**: se llegó a decir que la activación de `callaudiod`
por D-Bus era una «fragilidad latente», y **no lo es** — es su diseño. Trae su
`/usr/share/dbus-1/services/org.mobian_project.CallAudio.service` con `Exec=/usr/bin/callaudiod`.
Los mensajes de arranque («Card lacks speaker and/or earpiece port» → «No suitable card found,
stopping here») son una activación temprana, antes de que `armar-audio` haya montado la tarjeta:
sale, y la siguiente activación —la de la llamada— vuelve a sondear y la encuentra.

⚠️ **`pactl` NO funciona desde root**: no llega al PulseAudio del usuario. Una captura lanzada
con `sudo` devolvió perfil, sumideros y fuentes **vacíos** y un `callaudiod: NO` falso, dejando
la mitad del informe inservible. Hay que bajar a la sesión:
`su - <usuario> -c "XDG_RUNTIME_DIR=/run/user/<uid> pactl ..."`. Corregido en el guion.

---

## 2026-08-21 (tarde) · banco de pruebas de dos móviles

`scripts/dos-moviles.sh` **se ejecuta en el PC**, no en el móvil, y orquesta los dos: eut2
emite un tono de 1 kHz al 30 % junto al micro de epo y **epo mide su propia subida** con la toma
del DSP (`0.000000` = muda). Alterna saliente y entrante.

📌 **El otro extremo es irrelevante**: la subida se mide DENTRO de epo, así que da igual quién
conteste. Se llegó a montar un contestador automático por ofono en eut2 que no hacía falta.

⚠️ **`paplay` NO lee de la entrada estándar** (`open() No such file or directory`): usar `pacat`
con formato crudo. Con `paplay` no sonaba nada y la medida habría sido un falso «muda».
⚠️ eut2 = Ubuntu Touch: usuario `phablet`, alias `eut2lan`, ofono (`/ril_0`), **disco al 99 %**.
⚠️ Un bucle de descuelgue por SSH llega tarde: la llamada **se desvía al buzón**. Tiene que
correr dentro del propio móvil.

### Hipótesis caídas en esta tanda (van nueve en total)

| hipótesis | cómo cayó |
|---|---|
| reiniciar wireplumber antes de llamar | 3 de 3 al principio, pero luego una BUENA sin remedio (0.907); y el A/B quedó **inválido** porque eut2 salió del modo avión a mitad |
| una suspensión rompe la siguiente llamada | el experimento **no se ejecutó** (`suspensiones nuevas: 0`): ni probada ni refutada |
| cambiar de perfil recupera la llamada | ⛔ **refutado dentro de la misma llamada muda**: 0.000000 antes y después |

### ⚠️⚠️ Errores propios, para no repetirlos

1. **`pkill -f` se mató a sí mismo** tres veces: el patrón coincidía con mi propia línea de
   órdenes. Ya estaba anotado (`pkill -x`, nunca `-f`). Para listar sin auto-coincidencia:
   `ps -eo pid,args | grep "dos-movi[l]es"`.
2. Como los `pkill` fallaban en silencio, cada relanzamiento acumuló otra tanda: llegaron a
   correr **TRES a la vez** con llamadas solapadas (el usuario vio el «botón de espera»
   activado). → Guardar el PID en fichero y matar por PID.
3. El registro decía «descolgado» **solo porque se envió la orden**. Mismo error que el ACK del
   I2C: hay que leer el estado después.
4. El tono sonaba antes de la llamada y demasiado alto.

### ★ Línea base en estado sano (uptime 51 min)

```
[1] SALIENTE 0.091   [2] ENTRANTE 0.037   [3] SALIENTE 0.070
[4] ENTRANTE 0.047   [5] SALIENTE 0.100   [6] ENTRANTE 0.098    -> 6 de 6 BUENAS
```

📌 **La dirección queda descartada del todo**: las tres salientes bien, y eran las que fallaban.

📌 Lo único que sobrevive: **la degradación con el tiempo de marcha**. 51 min → 6/6 buenas;
~4,5 h → fallos constantes. Encaja con que reiniciar siempre lo arreglara. Siguiente paso:
repetir la tanda a distintas horas de uptime y ver si sube la tasa de mudas.

---

# ★★★ 2026-08-22 · «no me oyen»: LOCALIZADO — el puerto SoundWire del micro no se abre

**Estado: causa localizada, falta el último eslabón.**

## El hallazgo

En las llamadas mudas, el **puerto de datos 2 del bus SoundWire** —por donde el micrófono envía
sus muestras— **nunca se abre**:

```
SWRM_DPn_PORT_CTRL_BANK(0x1124, n=2, m=0) = 0x1224      bit 24 = EN_CHAN
  BUENA:  0x1000101      MUDA:  0x0000101
```

Validado con la mejor comparación posible: **8 volcados de la misma tanda** (3 mudas, 5 buenas,
90 s entre ellas), **byte a byte idénticos** en perfil, mezclador, macro TX del LPASS, los 413
registros del códec WCD y el regmap — **salvo** ese bit y otros cuatro registros del mismo puerto.

## Dónde se rompe (9 llamadas, 9 de 9 consistente)

```
BUENA:  sdw_prepare_stream ×1  →  qcom_swrm_port_enable ×1
MUDA:   sdw_prepare_stream ×1  →  qcom_swrm_port_enable ×0
```

📌 `sdw_prepare_stream` **sí se llama** también en las mudas, lo que **refuta** la hipótesis de
la bandera `stream_prepared` pegada en `true`.

La sospecha viva, en `sound/soc/qcom/sdw.c:qcom_snd_sdw_prepare()`:

```c
ret = sdw_prepare_stream(sruntime);
if (ret)  return ret;                /* si prepare FALLA, nunca se llama a enable */
ret = sdw_enable_stream(sruntime);   /* este acaba abriendo el puerto */
```

## ✅ RESUELTO (2026-08-22)

La sospecha de arriba quedó **refutada**: `sdw_prepare_stream` y `sdw_enable_stream` devuelven
**los dos 0** también en las mudas. El corte está más adentro y no da error en ninguna capa.

Bajando eslabón a eslabón (`scripts/sondas3.sh`, `sondas4.sh` y `sondas5.sh`):

| sonda | buena | muda |
|---|---|---|
| `sdw_enable_disable_ports` | 1 | 1 | ← el maestro existe, su lista de puertos está vacía |
| `sdw_stream_add_slave` `np=` | **1** | **0** | ← el flujo se registra con CERO puertos (8 de 8) |
| `qcom_swrm_port_enable` | 1 | **0** | |

`np` sale de `wcd->active_ports`, que `wcd937x_sdw_hw_params()` cuenta leyendo
`port_config[].ch_mask` — y ese `ch_mask` lo pone el **espacio de usuario**, con el control de
mezclador `ADC1 Switch`. Se lee **una sola vez**, en el `hw_params` del PCM.

`HiFi.conf` lo apagaba en sus dos `DisableSequence`, y `q6voiced` abría el PCM de voz dentro de
esa ventana de ~220 ms:

```
60201.337729  wireplumber   ADC1 Switch = 0
60201.337829  wireplumber   ADC1 Switch = 0
60201.384579  q6voiced      wcd937x_sdw_hw_params
60201.384590  q6voiced      sdw_stream_add_slave  np=0     <- cero puertos
60201.561142  wireplumber   ADC1 Switch = 1                <- 177 ms tarde
```

**Arreglo:** quitar esas cuatro líneas de `audio/HiFi.conf`. Historia completa y comprobación en
**`audio/LLAMADAS-MUDAS-SOUNDWIRE.md`**.

## ★ El instrumento bueno: `scripts/medir-puerto.sh`

Lee el bit 24 de `0x1224`. **ABIERTO = la subida lleva audio; CERRADO = muda.** Coincidió con el
audio real en todas las llamadas comprobadas.

Frente al método anterior (grabar con la toma del DSP), este **no reproduce ningún tono**, **no
rompe la subida** al medir, **no necesita el segundo móvil** ni descolgar — y además el PCM de la
toma dejó de abrir (`Unable to install hw params`), así que aquel método ya ni funciona.

⚠️ Para las tandas, **eut2 en MODO AVIÓN**: así las llamadas van al buzón, que descuelga siempre.
Con eut2 operativo suenan sin que nadie conteste y **no llegan a activarse** — invalidó dos tandas.

## ✅ Silenciar el micrófono en llamada (2026-08-22)

**El síntoma.** El botón de silencio de la app de llamadas no hacía nada.

**Por qué.** El perfil «Voice Call» declaraba `PlaybackPCM` pero ningún `CapturePCM`, así que
no producía **fuente** (`sources: 0`) y `callaudiod` no tenía nada que silenciar. Y aunque la
hubiera tenido, un silencio de PipeWire no habría servido: el audio de la llamada **no pasa por
la CPU**.

**El arreglo.** Cada dispositivo del teléfono declara ahora una fuente señuelo —igual que el
sink señuelo de la reproducción— y el silencio cae sobre un control **real** del camino:

```
CapturePCM   "hw:${CardId},1"     # señuelo: solo para que el perfil tenga fuente
CaptureChannels 1
CapturePriority 200               # la MISMA que la de reproducción (ver abajo)
CaptureVolume "name='ADC1 Volume'"
```

`ADC1 Volume` es la ganancia del ADC del códec, que sí está en el camino de la llamada, y su
escala declara `mute=1` en el mínimo: **0 es silencio de verdad, no ganancia mínima**. Medido
en HiFi, la captura pasa de `0,250183` a `0,000000` exacto. Y de extremo a extremo, con llamada
activa: `MuteMic true` → `ADC1 Volume 0`; `false` → `20`; la llamada sigue `active` y el puerto
SoundWire sigue abierto.

Además, el verbo tiene que rutar `MultiMedia2 Mixer TX_CODEC_DMA_TX_3`, o el `CapturePCM`
señuelo no abre al sondear y **el perfil entero se descarta**. Misma trampa que con MultiMedia3.

### Tres trampas que costaron encontrarlo

⚠️ **`CaptureSwitch` no sirve.** Los booleanos del camino (`CS-Voice Capture Mixer …`,
`TX_AIF1_CAP Mixer DEC0`) existen como elementos simples, pero alsa-lib los clasifica **por el
nombre** y todos salen como `pswitch` (reproducción), no `cswitch`. PulseAudio los ignora para
la captura y cae en un silencio **por software**, que no toca la llamada. Probado: el control
se quedaba en `on` con la fuente marcada como muda.

⚠️ **`ADC1 Switch` es una trampa.** La mezcla simple lo presenta como el interruptor del
elemento `ADC1` y parece el candidato natural. No es un interruptor de audio: pone o quita un
canal en el `ch_mask` del driver, que **solo se lee en el `hw_params`**. Silenciar con él no
haría nada en la llamada en curso y dejaría **muda la siguiente**.

⚠️ **Hay que fijar `CapturePriority` a mano.** Sin ella ACP recalcula la prioridad del perfil y
el orden **se invierte**: Bluetooth pasó de 4050 a 4450 y adelantó al auricular, que es justo lo
que `PlaybackPriority 50` existe para evitar. Con `CapturePriority` igual a la de reproducción,
el orden vuelve a ser Earpiece 4400 > Speaker 4200 > Bluetooth 4050.

### ⛔ Con auricular Bluetooth NO hay silencio — y el intento SALIÓ MAL

Con el casco el micro es el **del casco**: entra por SLIMBUS_7 desde el WCN3990 y no pasa por el
códec, así que `ADC1 Volume` no lo toca y en ese camino **no hay ninguna ganancia expuesta**.

**Lo que se probó el 2026-08-22 y hay que NO repetir.** Se le dio al dispositivo Bluetooth un
`CapturePCM` señuelo (`CaptureChannels`/`CapturePriority`) para que el perfil tuviera fuente y el
botón tuviera dónde actuar, más un servicio puente que reflejara el mudo sobre
`CS-Voice Capture Mixer SLIMBUS_7_TX`. Resultado:

- la llamada por casco se quedó **sin audio ninguno**, ni siquiera con el silencio quitado;
- y el perfil Bluetooth pasó a **ganar la elección automática** de toda llamada con el casco
  emparejado — exactamente lo que `PlaybackPriority 50` existe para evitar. Se comprobó en el
  volcado: las rutas ya estaban en SLIMBUS **antes** de tocar el perfil.

Revertido. El dispositivo Bluetooth vuelve a no declarar fuente (`sources: 0`, prioridad 4050).

**Lo que sí quedó establecido, y ahorra repetir el camino:**

| hecho | cómo se supo |
|---|---|
| el control del enrutador **sí corta** la subida | medido: 0,078 → 0,001068 (−37 dB), llamada activa |
| PulseAudio **no puede** accionarlo | de los **1201** elementos simples de la tarjeta, **cero** exponen `cswitch` |
| el puente por `pactl subscribe` **funciona** | `MuteMic true` → control a `off`, `false` → `on` |
| pero **exige** una fuente en el perfil… | …y declararla es lo que rompe el audio del casco |

⚠️ El fallo `qcom-q6cvp: command 0x112c2 failed with error 1` que aparece en estas llamadas
**es anterior** (78 apariciones el 2026-08-21, antes de tocar nada): no es la causa de esto,
aunque conviene mirarlo algún día — es el paso de volumen de bajada.

**Mientras tanto, la vuelta que funciona:** pasar a **altavoz** y silenciar ahí. En el altavoz el
silencio es el de la UCM (`ADC1 Volume` a 0), que es mute real medido.

📌 El arreglo bueno sigue siendo un **control de mute de subida en `q6voice`** (el DSP tiene
comando; el de bajada ya se usa, `0x112c2`). Sería nativo por UCM, no necesitaría fuente señuelo
ni servicio, y por tanto no tocaría el camino del casco. Las piezas del intento se conservan en
`audio/silencio-bt/` **desactivadas**, por si sirven de partida.
