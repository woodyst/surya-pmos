<!-- Numeración de parches ACTUALIZADA el 2026-08-06 (83 -> 106 parches, serie
     regenerada desde git). Equivalencias en kernel/EQUIVALENCIAS.md -->
# PENDIENTES / roadmap — surya (POCO X3 NFC, SM7150)

Prioridad fijada por el usuario (2026-07-16): **0) TERMINAR TELEFONÍA (micro + audio de
llamada) — ✅ HECHO (2026-07-18) · 1) Cámara · 2) Sensores que faltan · 3) Carga rápida Xiaomi**.
Huella = posible en el futuro. Descartados por hardware: carga inalámbrica (sin bobina
Qi) y HDMI/DP por USB-C (USB 2.0, sin líneas DP cableadas).


## ✅ RESUELTO — Sin respuesta táctil ni sonora al pulsar / notificaciones mudas (2026-08-07)

Resuelto: **tres causas apiladas**, y la principal invalida meses de trabajo previo.
**★ La vibración iba al dispositivo equivocado**: surya tiene **DOS** entradas con vibración
(el vibrador del PMIC, que acepta órdenes y no mueve nada, y el motor háptico real
`aw8695-haptics`), las reglas de `feedbackd` etiquetan las dos y cogía la primera. **El driver
del PMIC que se depuró desde julio estaba bien: el motor era otro.** Detalle completo, con las
otras dos causas y el diagnóstico, en `notificaciones/README.md`.

## 💡 IDEA — Telegram en Chatty vía tdlib-purple (2026-08-07)

**Problema**: Telegram Desktop y Kotatogram son clientes de escritorio **sin servicio en segundo
plano**: solo reciben mientras el proceso vive. **Resuelto de momento** activando «seguir en
segundo plano al cerrar» en el propio Telegram (**346 MB**), que le sirve al usuario.

⚠️ **Waydroid descartado con datos**: mantener el contenedor vivo para que su Telegram (153 MB)
reciba mensajes cuesta **2 781 MB en 45 procesos**, de los 5,5 GB del móvil. Absurdo como precio.

**La vía elegante, si algún día se aborda**: `tdlib-purple` en **Chatty**, que **ya corre siempre**
(19 MB, gestiona los SMS) — Telegram entraría por ahí sin proceso extra y notificaría por el mismo
camino que los mensajes de texto. ⚠️**Ni el complemento ni tdlib están en los repositorios**
(comprobado: solo hay `purple-xmpp`, `purple-mm-sms` y similares), así que habría que empaquetar
**las dos** cosas; tdlib es un proyecto C++ grande, de compilación larga. **Es un proyecto propio,
no algo de pasada.**

## ✅ CERRADO — El micrófono no iba en llamada sin cascos (2026-08-07)

Una llamada entrante por altavoz se quedó **sin micrófono**. **En la siguiente llamada funcionó**,
y el usuario lo dio por resuelto.

**Causa casi segura, y era mía**: ese día reinicié **WirePlumber muchas veces** para liberar la
cámara, y de esa cadena depende el enrutamiento de llamada (PCM señuelo + verbo UCM + `callaudiod`).
Quedó un estado a medias que se deshizo solo al rearmarse.

⚠️ **Si reaparece**, no dar por hecho que es lo mismo: comprobar en este orden
`pactl list short cards` (que la tarjeta siga en HiFi — si desaparece, `callaudiod` la descarta
entera y hace falta reiniciar el móvil), el estado de `q6voiced` y el verbo UCM durante la llamada,
y `audio/scripts/verify-call-routing.sh`, que verifica el enrutamiento **sin necesidad de llamar**.

📌 **La lección operativa**: parar WirePlumber para trabajar con la cámara **toca la telefonía y el
Bluetooth**, no solo el altavoz. Volver a arrancarlo al terminar y comprobar que la tarjeta sigue
en HiFi.

## ⚠️ ABIERTO — El móvil se cuelga solo por la noche (2026-08-07)

Tres reinicios en una noche. **Analizados uno a uno, y NO son todos lo mismo**:

| arranque | fin | causa |
|---|---|---|
| 23:46→00:50 | suspensión sin reanudar | **la suspensión** |
| 00:51→03:10 | `reboot requested from … 'gnome-session-s'` | **a propósito** (tras pulsar el botón) |
| 03:11→04:55 | sin apagado ordenado ni petición | **cuelgue seco** |
| 04:58→07:55 | ídem, y sin pulsar ningún botón | **cuelgue seco** |

⚠️ **Corrige una conclusión precipitada**: en el arranque de las 00:51 **la suspensión funcionó y
el móvil despertó bien**. No está rota siempre; falló una de dos veces.

**Los dos cuelgues secos no dejan NADA**: ni apagado ordenado, ni pánico, ni traza en
`/var/lib/systemd/pstore` (el `pmsg` que hay es el registro del arranque *siguiente*, no una
traza). Ese patrón es la firma del **perro guardián por hardware** (`qcom_wdt`, 5 s): un cuelgue
duro no deja escribir nada.

**Causa: DESCONOCIDA.** Para cazarlo haría falta instrumentar antes de la próxima noche —ampliar
la región de ramoops y preservar la consola—, porque tal como está el reinicio no deja evidencia.

📌 Descartado como sospechoso: `llamada-al-bluetooth.sh` sondea el módem cada medio segundo con
`sudo` (tres líneas al diario por vuelta), pero **es correcto y necesario** —ajusta el audio de
llamada y Bluetooth, confirmado por el usuario— y su consumo es modesto (21 s de CPU en 91 min).
Lo único mejorable, y solo si molesta el ruido en los registros, es evitar el `sudo` por sondeo.

## ★ Cámara — por dónde retomar (2026-08-06)

Estado completo en `camera/README.md`. Resumen para no releerlo entero:

**Arreglado**: la regresión del VFE (parche 0107) — `enable_irq()` iba **después** de
`vfe_reset()`, que espera esa interrupción, así que ninguna captura funcionaba desde hace dos
meses. Ahora el pipeline enciende y el CSID responde.

**Medido y cerrado, todo con precondición verificada**: los MISR de los cuatro carriles (cero),
el número de carriles 3/2/1 (cero), el `settle_cnt` en toda la ventana MIPI 20-39 (cero), la
numeración de carriles base-1 (ya era base cero), la configuración del CSIPHY perdida por relojes
(no se pierde), el sensor comparado registro a registro con fábrica (idéntico) y el CSI2 RX del
CSID contra fábrica (idéntico).

**El resultado que ordena todo**: ★ **el CSID no captura ni un SOT**, con el TPG como control
positivo encendiendo los bits en tres carriles. Es la primera medida del expediente con control.
Cierra de raíz toda la rama del ensamblado de paquetes: el fallo está **antes**, en que el enlace
de alta velocidad nunca arranca.

**Lo único que queda por probar y no es físico**: un volcado del banco de estado del CSIPHY
**durante** un enlace en marcha, para saber si esos bits son *errores* o *actividad detectada* —
la dicotomía abierta desde julio. En eut2 (mismo IP, mismas direcciones, enlace que funciona) el
driver de fábrica solo vuelca **al arrancar**, así que sus ceros no valen. Habría que provocar un
volcado a mitad de flujo.

**Y si no**: instrumentación física de la fase LP (analizador de 200-500 MSa/s, esquemático de
HalabTech, placa de sacrificio para practicar). Coste 150-250 €. La pregunta que respondería es
binaria: si el sensor ejecuta `LP-11 → LP-01 → LP-00 → HS` o nunca sale de LP-11.


## ★★ PENDIENTE MAYOR — probar la receta de punta a punta en un pmOS limpio

**Es lo único que separa al kit de estar demostrado.** El kernel ya lo está: los 106 parches
aplican limpios, reproducen el kernel desplegado bit a bit y compilan
(`VERIFICACION-2026-08-06.md`). Lo que **nunca se ha ensayado** es el espacio de usuario: los
pasos `20-paquetes` … `70-bluetooth-llamadas` están escritos y automatizados, pero nadie los ha
corrido sobre una instalación limpia.

**Qué haría falta**: un postmarketOS recién instalado en surya —o una segunda tarjeta/partición,
para no arriesgar el móvil que funciona— y ejecutar `scripts/00-replicar-todo.sh` de principio a
fin, anotando cada punto donde haga falta intervenir a mano.

**Qué probaría**: que un tercero (o nosotros dentro de seis meses) puede rehacer esto sin la
memoria de estas sesiones.

**Riesgos conocidos que probablemente aparezcan**, por lo visto en la auditoría del 2026-08-06:

- Rutas cableadas en los guiones (`DEVICE_SSH`, `APORTS`, `PMAPORTS`) que hay que revisar.
- Pasos que piden reiniciar y no lo dicen con suficiente claridad (sensores, módem).
- El orden importa más de lo que parece: el módem necesita reinicio tras `tqftpserv`, y el audio
  necesita el kernel nuevo **con sus módulos de la misma compilación**.
- ⚠️ El guion lua de wireplumber va en `~/.local/share/…`, no en `~/.config/…`; mal puesto,
  wireplumber no arranca y el móvil se queda **sin audio ninguno**.

**Hasta que se haga, el kit está "verificado en el kernel y descrito en el resto"**, que no es lo
mismo que reproducible.


## ★ Tomas de llamada FUNCIONANDO (2026-08-01 noche) — siguientes pasos

La grabación de la bajada en llamada VoLTE **ya funciona en el surya** (ver
`bluetooth-call/tomas-llamada/README.md`, parche 0002 = kernel `b788ae4cc` en deploy-r59).
Pendiente, en orden:
1. Confirmar con el usuario que la subida sobrevive al armar la ruta en llamada (antes
   rompía SIEMPRE; con el puerto bien arrancado no debería).
2. Probar `VOC_REC_UL` (subida) y `VOICE_PLAYBACK_TX` (inyección hacia el otro extremo) —
   son las dos piezas del puente Bluetooth por tomas.
3. Promover 0001+0002 de tomas-llamada a la serie del APKBUILD (¿0079-0080?).
4. Cosmético: el STOP del CVS devuelve `error 3` al soltar la ruta.
5. App/integración de grabación de llamadas (medio objetivo cumplido de por sí).
⚠️ Vigilantes por SSH en el surya: systemd mata la sesión al desconectar —
`sudo systemd-run --unit=X --collect`.

## Pendientes menores (2026-08-01)

- **El phosh de surya vuelve a arrancar con el brillo bajo** (reportado por el usuario;
  existe `brillo/` con brillo-persistente pero no está cumpliendo). Revisar CUANDO las
  llamadas Bluetooth estén funcionando, no antes.
- Volumen de llamada por hardware: la regresión observada por la mañana (PipeWire en volumen
  software) **desapareció por la tarde** (verify-call-routing muestra 108→95→77 correcto tras
  los módulos de la fase 1). Vigilar si reaparece; puede depender del orden de arranque.

---


## USB OTG / modo host — ✅ FUNCIONANDO (2026-07-31)

Webcam C270 por adaptador OTG verificada entera (attach source → VBUS 5 V → host →
`uvcvideo` → captura). Parche **0065** (QMP PHY USB3/DP). Detalle y trampas en
`drivers/0002-usb-otg-host.md`.

**Pendiente:**
- ~~Añadir 0064 y 0065 al APKBUILD~~ ✅ HECHO (2026-07-31): APKBUILD a **pkgrel=59** con **0062-0065** (el 0062 era imprescindible: el enrutamiento de llamada desplegado depende del PCM señuelo). Serie 0001-0065 verificada aplicando limpia sobre `v7.1_rc3`. Aport real de pmaports sincronizado (tenía el parche QMP duplicado como "0062" con otro nombre — eliminado). ⚠️ Falta un build+flash de verificación con pmbootstrap; hasta entonces el móvil sigue con el kernel del árbol kernel-build.
- **Wedge de la máquina typec**: un arranque entero con la detección source muerta
  (SM_STATUS clavado en `0x10`); solo lo arregló reiniciar. Causa sin identificar
  (¿estado que deja u-boot? ¿arrancar con cable puesto?). Si reaparece, diagnosticar antes de reiniciar.
- **Cuelgue duro** (sin oops/pstore) con el surya de **source PD hacia otro móvil** (C-a-C
  a un móvil UT, contrato 5V/3A). No dejar esa configuración sin vigilancia.

---

## 0) TERMINAR TELEFONÍA  ✅ FUNCIONANDO (2026-07-18)

### ★★★★★ AUDIO DE LLAMADA COMPLETO (2026-07-18, ~00:00): salientes y entrantes, ambos sentidos

Eran **TRES causas apiladas** (por eso ningún fix aislado sonaba). En orden de descubrimiento:

1. **Parche 0056 — nombre de sesión CVD.** El CVD empareja la sesión pasiva del AP con la del
   módem **POR NOMBRE**. Usábamos `"default modem voice"` (legacy msm8916); surya usa
   exclusivamente voicemmode1 → nombre **`"11C05000"`** (VSID en hex). Un nombre no coincidente
   se acepta sin error: sesión huérfana, todo ACKa al vacío. Verificado en HAL vendor (strings:
   solo `voicemmode1-call`) + downstream (`q6voice.c` 959-987). Con esto **sonó la recepción por
   primera vez en el proyecto**. Parámetro en caliente:
   `/sys/module/q6voice_common/parameters/session_name`.
2. **Parche 0057 — topología TX.** `TX_SM_ECNS` (canceladora de eco) **sin calibración ACDB saca
   silencio puro**, mientras el sidetone (pre-procesado) sigue vivo — el "acople" local que
   delató que el micro SÍ llegaba al vocproc. Default nuevo: TX = `NONE` (0x10F70, passthrough).
   Verificado A/B en llamada real: ECNS = nada al otro lado, NONE = perfecto. Parámetros:
   `/sys/module/q6cvp/parameters/{tx,rx}_topology`. La comparación previa "da igual" (0054) era
   inválida (hecha con el bug 1 activo).
3. **Solo UCM — carrera q6voiced-vs-callaudiod en ENTRANTES.** Al descolgar, `q6voiced` abre el
   PCM CS-Voice en el mismo segundo del `ringing-in → active`, antes de que `callaudiod` aplique
   el verbo "Voice Call" → la ruta de captura no existe → `Failed to open tx: EINVAL` → toda la
   llamada sin uplink. En salientes se ganaba la carrera; en entrantes se perdía siempre (el tono
   retiene el verbo HiFi). Arreglo: rutas `TERT_MI2S_RX Voice Mixer CS-Voice` y `CS-Voice Capture
   Mixer TX_CODEC_DMA_TX_3` **siempre activas** (EnableSequence de ambos verbos, sin
   DisableSequence — una ruta a un FE parado no lleva audio). `audio/HiFi.conf` +
   `audio/VoiceCall.conf`.

### ★★★★★ ENRUTAMIENTO Y VOLUMEN DE LLAMADA — ✅ RESUELTO (2026-07-19)

Al descolgar entra por el **auricular**; el botón de manos libres pasa al **altavoz inferior** y
vuelve; **cada modo tiene su propio volumen** y el deslizador atenúa la llamada de verdad; al
colgar se restaura HiFi. Verificable sin llamar a nadie con
`audio/scripts/verify-call-routing.sh`. Documento maestro: **`audio/ENRUTAMIENTO-LLAMADA.md`**.

**La idea que lo resolvió:** la llamada CS no pasa por la CPU, así que los dispositivos UCM no
declaraban PCM — y sin PCM no hay mapping → ni sink → ni puerto → **el `EnableSequence` del
dispositivo no se ejecuta jamás**, y además no hay nada que controlar con el volumen. Solución:
un **PCM señuelo** (`MultiMedia3`, kernel **0062**) que no lleva audio de la llamada y solo existe
para que el perfil tenga sink → puerto (aplica el ruteo) y destino del volumen, enganchado con
`PlaybackVolume` al **volumen digital del amplificador**, que está *después* del mezclador del DSP
y por eso **sí atenúa la llamada** (un volumen software del sink no haría nada).
**Un amplificador por modo** (arriba = auricular, abajo = manos libres, como el firmware de
Xiaomi), que es lo que permite un control de volumen por modo.

Piezas: kernel **0062** · `audio/VoiceCall.conf` · parche a **callaudiod**
(`audio/callaudiod/`: crash SIGSEGV del botón + cambio de **perfil**, porque aquí cada modo es un
perfil y no un puerto) · **`q6voice_device=3`** en `/etc/conf.d/q6voiced`.

⚠️ **El PCM señuelo no abre sin ruta**, y el cset tiene que ir en el **`SectionVerb`** (ACP sondea
los PCM antes de aplicar el `EnableSequence` de dispositivo) — misma trampa que el micro.
⚠️ **0062 desplaza CS-Voice a `hw:0,3`** → sin `q6voice_device=3` **se rompe el audio de llamada**.
⚠️ `apk upgrade` de callaudiod **pisa el binario parcheado** → `~/bin/rebuild-call-routing.sh`.
⚠️ **Nunca reiniciar wireplumber/pipewire con una llamada en curso**: el re-sondeo de verbos UCM
corta el audio de la llamada.

**El parche a PipeWire (`audio/pipewire/`) NO es necesario** — resolvía la causa de fondo (activar
dispositivos UCM sin PCM) y fue lo que hizo funcionar el cambio de modo antes de dar con el PCM
señuelo, pero **verificado que con el señuelo todo funciona con PipeWire original sin parchear**.
No instalado (evita mantener una librería del sistema parcheada); se conserva documentado porque
es un bug real de upstream y merece subirse.

**Pendiente residual (menor, no bloquea)**: calibración de volumen RX (`MAP_PHYSICAL error 2` en
todas las variantes de dirección probadas; best-effort) · volver a ECNS cuando cargue la
calibración (sin canceladora el otro lado puede notar eco — si molesta, subir prioridad) ·
upstream del stack q6voice · **subir upstream los parches de PipeWire y callaudiod** (los dos son
arreglos genuinos y acotados, no hacks específicos de surya).

### ✅✅ MICRÓFONO FUNCIONANDO (2026-07-17)

Hicieron falta **dos** bugs, uno detrás de otro. El primero impedía que el códec existiera; el
segundo hacía que, existiendo, capturase silencio.

**Bug 1 — parche 0038 (mux del pinctrl LPI).** `gpio1` = lane 0 de datos del bus SoundWire **TX**
tenía `swr_tx_data` en **FUNC_SEL 1**; el silicio lo expone en **FUNC_SEL 3**:
```c
- LPI_PINGROUP(1, 2, swr_tx_data, audio_ref, _, _),
+ LPI_PINGROUP(1, 2, _, audio_ref, swr_tx_data, _),
```
Despistó porque el **reloj** TX (gpio0) sí era correcto → todo el SoC medía impecable (frame-gen,
9.6 MHz, IRQs) mientras la línea de **datos** no llegaba al controlador. El esclavo no podía
anunciarse (`SLV_STATUS = 0x0` eterno) y, como el **regmap del WCD9375 vive sobre el TX**, el códec
moría con `-110`. El RX vivía porque su clk (gpio3) y data0 (gpio4) ya estaban en FUNC_SEL 2.
Al arreglarlo: `sdw:3` → `Attached`, y los bits de *bus clash* de `COMP_STATUS` desaparecieron
(0x2a01 → 0x1), confirmando que eran **consecuencia** de la línea mal enrutada.

**Bug 2 — parche 0040 (mapeo de puertos TX).** `qcom,tx-port-mapping` estaba **desplazado uno**:
`<1 1 2 3>` mandaba el ADC1 al puerto SoundWire **1**, que es `PCM_OUT1` y no lleva datos de
captura → el macro TX leía un puerto vacío. Síntoma: **silencio digital exacto** (ni ruido de fondo,
que un ADC analógico vivo siempre tiene) **pese a que toda la cadena DAPM estaba `On`**. El binding
lo documenta: ADC1→SWR2 puerto 2, ADC2/3→2, DMIC0-3→3, DMIC4-7→4 = **`<2 2 3 4>`**, idéntico al
`swr-port-mapping` de sm6150/sdmmagpie.

**Verificación (objetiva, sin oído humano):**
- Ruido de fondo **sostenido** los 4 s completos, ~92-96% de muestras no-cero.
- La ganancia **escala** la señal: `ADC1 Volume` 0/10/20 → RMS 3.1 / 6.0 / 41.3 (causalidad).
- **Loopback acústico**: tono de 1 kHz por el altavoz → pico a 1 kHz **300× sobre el ruido**
  (10189 vs ~30), más el 3er armónico del altavoz a 3 kHz. Capta sonido real.
- **Por PipeWire** (`pw-record`): 96.7% no-cero, -61 dBFS.

**UCM:** añadido `SectionDevice."Mic"` → PipeWire expone `Audio Interno Built-in Microphone` como
Source. Usa **`hw:...,1` (MultiMedia2) a propósito**: MultiMedia1 lo ocupa el playback y son FE DPCM
con **un cliente q6asm cada uno**, así que capturar en el mismo FE da `Audio Client already active`
+ `q6asm_open_write failed`.

Cadena completa: `AMIC1 → MIC BIAS1 → ADC1 → ADC1_OUTPUT → TX SWR_ADC0 (SoundWire puerto 2) →
TX SMIC MUX0 → TX DEC0 → TX_AIF1_CAP → TX_CODEC_DMA_TX_3 → MultiMedia2 (hw:0,1)`.

### ★★★ AUDIO DE LLAMADA — CVS implementado, sigue muda: causa acotada a calibración/VSID (2026-07-17)

**Parche 0053.** Se implementó el CVS que faltaba (§ hallazgo original abajo) y se verificó en
**cuatro llamadas reales** con distintas variantes. Ninguna suena. Pero cada intento acotó más
la causa.

**Con CVS + `ATTACH_STREAM` explícito**: sesión perfecta, sin errores. Muda.

**Comprobado (leyendo `voice_create_mvm_cvs_session()` del downstream con lupa)**: el
`ATTACH_STREAM` **solo está en la rama VoIP** (`is_voip_session`); la rama CS (la nuestra) crea el
CVS pasivo y **nunca lo engancha explícitamente** — el DSP debe emparejar la sesión pasiva del AP
con la del módem por **coincidencia de nombre** (`"default modem voice"`). Se quitó el
`ATTACH_STREAM`. Sesión sigue perfecta. Sigue muda.

**El verbo UCM se aplicó de verdad**: las primeras pruebas solo picaban controles del verbo a
mano con `amixer`, saltándose la secuencia del **dispositivo** (`SectionDevice."Earpiece"`), que
es la que pone `Left ASI1 Sel = LeftRightDiv2` y muta el ampli inferior. Aplicado con
`alsaucm -c ... set _verb "Voice Call" set _enadev Earpiece` de verdad. Sigue muda.

**★ El comando de volumen es el único que el DSP rechaza**: `q6cvp_set_rx_volume()` (RX, step) da
siempre `command 0x112c2 failed with error 1` = `ADSP_EFAILED`. El de mute (`q6cvs_mute()`, TX,
booleano) **siempre se acepta**. El paso de volumen se resuelve contra una **tabla de calibración
ACDB** que nada de este puerto carga; con el perfil `NONE/NONE` (sin cal, elegido para esquivar la
falta de calibración de las topologías ECNS/DEFAULT) no hay tabla registrada → falla siempre.
**Verificado en llamada real** (log del propio dispositivo): `command 0x112c2 failed with error 1`.

**Se implementó de todos modos** (parche 0053), en modo *best-effort* igual que el downstream (si
falla, se registra y la llamada sigue montándose — no aborta): `q6cvp_set_rx_volume()` +
`q6cvs_mute()`, llamadas entre el attach del vocproc y el arranque del MVM. El paso de volumen es
un **parámetro de módulo** (`rx_volume_step`, sysfs `/sys/module/q6voice/parameters/`) para poder
barrear valores colgando y volviendo a llamar, sin recompilar ni reiniciar — nadie lo ha barrido
todavía porque el error es genérico (`EFAILED`) y no varía con el valor.

**Conclusión honesta**: no es ya "falta un comando". Cargar calibración ACDB real (parsear los
blobs del vendor) o hacer que el DSP negocie el VSID real de la llamada con el módem (que
`q6voiced` hoy no consulta) son **proyectos aparte**, no un fix de tarde. No hay datos para saber
cuál de los dos hace falta, o si son los dos.

### ★★★ La topología del vocproc NO es la causa — probado con la topología real (2026-07-17)

**Gap de metodología corregido**: el cambio a topologías `NONE/NONE` se hizo hoy mismo basándose
en el comentario `TODO: Implement calibration` heredado, **sin probar antes** si `ECNS`/`RX_DEFAULT`
(las topologías reales, con cancelación de eco y supresión de ruido) fallaban de verdad. Las
primeras 4 llamadas de la sesión se hicieron todas con `NONE/NONE`.

**Revertido y probado con la topología real** (parche 0054): la sesión **se crea y activa
exactamente igual**, sin ningún error nuevo — solo sigue fallando el mismo comando de volumen
(`0x112c2`, `ADSP_EFAILED`), igual que con `NONE/NONE`. **Llamada 5, con `ECNS`/`RX_DEFAULT`: sigue
muda.** → La elección de topología **no hace ninguna diferencia**. Se mantiene la topología real
del vendor (mejor calidad de audio si algún día suena) en vez del passthrough.

### ★★★ Se buscó la calibración ACDB de UT/ubports — el subsistema entero falta (2026-07-17)

**¿Es de volumen?** Sí. El comando concreto que el DSP rechaza (`VSS_IVOLUME_CMD_SET_STEP`,
`0x112c2`) resuelve un **paso** (0, 1, 2...) contra una **tabla de dB por dispositivo/uso**
(auricular en llamada, altavoz en llamada, etc.). Es justo lo que un fabricante ajusta con
herramientas como QACT/QXDM para que el auricular no quede ni flojo ni saturado. **Si algún día
suena, esas tablas son las que se tocarían para subir o bajar el nivel** — pero primero hace falta
que suene algo, y ahí es donde estamos atascados.

**La calibración SÍ está disponible, y verificada auténtica**: `/mnt/vendor/etc/acdbdata/` en el
propio móvil (mismo MD5 que en `~/src/en_ext/ubports/surya-fw-V12.0.9.0/vendor_extracted/etc/
acdbdata/`, el firmware de fábrica extraído para el port de Ubuntu Touch). Hay una carpeta
**`IDP/sm6150-tavil-snd-card/`** — "Tavil" es la familia del WCD9340/9375, nuestro códec, y
"sm6150" es el árbol downstream correcto (ver [[reference-sm7150-downstream-tree]]) — con
`IDP_WCD9340_Handset_cal.acdb` (534 KB) que casi seguro trae la tabla de volumen del auricular.

**Pero mainline no tiene NADA de la infraestructura para cargarla, y es un subsistema entero, no
un fichero que se pueda simplemente "copiar":**

1. El formato `.acdb` (`QCMSNDDB`/`AVDB`, contenedor binario propietario con secciones etiquetadas:
   `MODIFIED`, `SWPNAME`, `OEMINFO`, `DEVCATI`...) **lo parsea `libacdbloader.so`**, una librería
   **cerrada** de Qualcomm de la que no hay fuente — solo el binario ARM64 en la partición vendor.
2. El downstream tiene un **driver de carácter completo** (`audio_cal_utils.c`,
   `/dev/msm_audio_cal`, `msm_audio_calibration.h`) con su propio protocolo de IOCTLs para que
   `libacdbloader.so` (en Android) le pase los bloques de calibración ya parseados.
3. Los datos **no viajan dentro del paquete APR**: se copian a un buffer DMA físicamente contiguo,
   se mapean en el DSP con `VSS_ICOMMON_CMD_MAP_MEMORY`, y el comando de registro
   (`VSS_IVOCPROC_CMD_REGISTER_VOL_CALIBRATION_DATA`) solo manda el *handle* de esa memoria.
4. **Mainline no tiene ni el driver de carácter, ni el asignador de memoria, ni el mapeo de
   memoria del voice**, `grep`eado y confirmado vacío en `sound/soc/qcom/qdsp6/`.

**★★★★ SUPERADO (misma sesión, 2026-07-17): no hizo falta parsear `.acdb`.** Se ejecutó la
librería vendor real (`libacdbloader64.so`) nativamente en el PC (también ARM64) bajo el
`linker64` real de Android extraído del `super.img` del firmware stock, con un módulo de kernel
propio (`msm_audio_cal_stub.ko`) simulando `/dev/msm_audio_cal` + `/dev/ion` para capturar
exactamente los bytes que la librería le pasa al kernel. Resultado: **4316 bytes reales de la
tabla de volumen del auricular** (rx=7, tx=4, feature_set=0), más el struct `AUDIO_SET_CALIBRATION`
confirmado byte a byte contra la cabecera UAPI. Todo en `~/claude/postmarketos/calibrations/`
(README con el protocolo completo + harness reutilizable para capturar otros cal_type). Detalle
completo en la memoria [[project-pmos-surya-mic]].

#### Siguientes pasos
1. ~~Implementar el CVS~~ → ✅ **HECHO** (parche 0053). Sesión perfecta, sigue muda.
2. ~~Cargar calibración ACDB real~~ → ✅ **bytes ya extraídos** (ver arriba). Falta: escribir el
   driver kernel mainline que reproduzca la MISMA secuencia de ioctls capturada y le pase estos
   bytes reales tal cual (sin interpretarlos) — debería bastar para que
   `q6cvp_set_rx_volume()` deje de fallar con `ADSP_EFAILED`.
3. **Recalibración (ajustar el volumen), aparte, como trabajo futuro**: interpretar el formato
   interno de los 4316 bytes. Solo decodificados los primeros ~0x70 (registro module_id/param_id,
   no valores numéricos todavía). El truco de diff fs0(normal)/fs1(VOL_BOOST) no sirvió para el
   auricular (bytes idénticos, este dispositivo no tiene perfil boost distinto ahí) — probar con
   el altavoz (acdb_id=10011) en su lugar.
4. **O averiguar si hace falta el VSID real de la llamada** — `q6voiced` hoy no consulta al módem
   qué VSID lleva la llamada en curso; usa un nombre de sesión fijo. Si el DSP necesita que
   coincida el VSID además del nombre, ninguna cantidad de calibración arreglará el silencio.
4. **Quién activa el verbo UCM** al entrar una llamada: ahora mismo **nadie** (probado a mano con
   `alsaucm`). Pendiente integrarlo en `callaudiod` o un hook de `q6voiced`.
3. **Señalización** (llamada en espera, etc.) vía ModemManager/QMI.
4. Probar el **micro en llamada real** (uplink) una vez haya downlink.
4. Pendiente menor: mic secundario (AMIC2/AMIC3) para cancelación de ruido; `Fixes:` del 0038 sin
   hash upstream real.

**El "LPASS boot flake" ya NO está pendiente** — resuelto 2026-07-17 con `CONFIG_QRTR_SMD=y`
(carrera: el HELLO qrtr del ADSP se perdía porque udev aún no había cargado el módulo, y el NS
local nunca vuelve a saludar). Detalle completo en `LISTA.md` §1.

**Criterio de "terminado" (usuario, 2026-07-16):**
- ✔ **Llamadas con audio** (micro/uplink + altavoz/auricular/downlink) — objetivo principal.
- ✔ **Señalización**: llamada en espera, etc.
- ○ **VoLTE**: opcional (deseable, no bloqueante).
Con eso, el resto de funcionalidad (cámara, sensores que faltan, carga rápida) se pospone.

Trabajo pendiente para llegar ahí: ver **"Siguientes pasos"** arriba (el micro ya no está
bloqueado; falta el front-end analógico y el UCM de captura). Además:
- **VoLTE (opcional):** IMS. El módem ya usa el bearer IMS; requeriría configurar el
  stack IMS (probablemente `ims`/`doubango`-like o el del propio módem). A evaluar.
- Detalle en la memoria `project_pmos_surya_mic.md`.

---

## 1) CÁMARA  🟠 (EN CURSO desde 2026-07-17)

**Toda la base de conocimiento verificada está en [`camera/README.md`](camera/README.md).**
Aquí solo el estado, el criterio de aceptación y el caso para los mantenedores.

### Estado

| pieza | estado |
|---|---|
| PMIC de cámara **WL2866D** (0041/0042) | ✅ funciona, tensiones verificadas en hardware |
| Driver del sensor **IMX682** principal (0043/0044) | ✅ **emite a 30 fps** |
| Driver del sensor **S5K3T2** frontal (0047/0048) | ✅ **emite a 29,9 fps** |
| **CSID + VFE + DMA + nodo de vídeo** | ✅ el **TPG del CSID captura 3 frames perfectos** |
| **CSIPHY → CSID** (csiphy0 **y** csiphy1) | ⛔ **0 paquetes, 0 errores** ← **el muro** |
| libcamera / resto de sensores | ⬜ sin empezar |

### ★★★ El experimento de control — HECHO, y es concluyente

Se escribió el driver de la **cámara frontal** precisamente para esto. Resultado:

| | principal | frontal |
|---|---|---|
| sensor | Sony IMX682 | **Samsung S5K3T2** |
| CSIPHY | 0 | **1** |
| bus CCI | i2c-12 (cci0_i2c0) | **i2c-13 (cci0_i2c1)** |
| carriles | 3 | **4** |
| link_freq | 953,6 MHz | **896 MHz** |
| MCLK | MCLK1 (tlmm14) | **MCLK0 (tlmm13)** |
| raíles | WL2866D DVDD2+AVDD2 + wide_ldo | **WL2866D AVDD1 + camera_vdig** |
| **emite** | 30 fps ✔ | 29,9 fps ✔ |
| **el PHY ve la señal** | ✔ | ✔ |
| **paquetes al CSID** | **0** | **0** |
| **errores CRC/ECC** | **0** | **0** |

**Dos sensores de fabricantes distintos, en dos CSIPHY distintos, con buses, número de carriles,
frecuencias de enlace, relojes y alimentaciones distintas → fallo idéntico.** Y el TPG del CSID,
que usa el mismo CSID/VFE/DMA pero **no pasa por el CSIPHY**, sí captura.

→ **El fallo está en el soporte de CSIPHY de camss para sm7150, no en nuestros drivers ni en
nuestra configuración de placa.** Eso es exactamente lo que faltaba para cerrar el caso.

### ★ Los bits de estado — YA DECODIFICADOS

**Método** (herramienta: `camera/csiphy-lane-decode.sh`). Los 11 registros `0x8b0+4·n` son estado
de IRQ **latcheado**; se limpian escribiendo en `CTRL[22..32]` (`0x858+4·n`) y **pulsando `CTRL10`
(0x828) 1→0** — poner a cero los clear antes del pulso no borra nada. Y **hay que enmascarar las
IRQ** (`CTRL11..21` = `0x82c..0x854` a 0) para parar la tormenta del ISR: con ella activa toda
lectura es una muestra al azar. Enmascarar no impide el latcheo.

**Resultado** (csiphy0 / IMX682, escribiendo `CTRL5` en caliente, repetido 3 veces):

| CTRL5 | carril | STATUS |
|---|---|---|
| 0x81 | reloj + **ln0** (*lleva señal*) | — nada |
| 0x84 | reloj + **ln1** | **STATUS[2] bit7** |
| 0x90 | reloj + **ln2** | **STATUS[5] bit3** |
| 0xc0 | reloj + **ln3** (*sin cablear*) | — nada |

- Los bits son **por carril de datos**. El **reloj no influye** (`0x15`, sin reloj, da lo mismo que
  `0x95`) → son de la capa analógica del carril, no del decodificado HS.
- Que **ln3, desconectado, no dé nada** valida el método: los bits los provoca la señal del carril.
- **★ La anomalía: el carril 0 lleva señal y no produce nada — igual que el carril 3, que ni
  siquiera está cableado.** Los carriles 1 y 2 sí. Sin documentación de los bits **no se puede
  decidir** entre: (a) son errores → ln0 recibe limpio y ln1/ln2 fallan; (b) son "actividad" →
  ln0 no recibe nada. **En ambos casos explica los 0 paquetes**, y es lo más concreto que hay.
- Con señal, tras limpiar los bits **vuelven al instante**; sin señal, **cero y se queda a cero**
  → el PHY **sí recibe**.
- **csiphy1 se comporta distinto**: ningún carril suelto produce bits, solo los 4 a la vez
  (`STATUS[1].0, [3].5, [6].2, [8].7` — índices 8/29/50/71, **de 21 en 21**). Sin explicar.
- ⚠️ El `0x_94` por banco de carril **es un registro vivo y fluctuante**: lo de "a csiphy1 le falta
  LN2" era **un artefacto de muestreo**, no un dato.

### Criterio de aceptación
`v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3 --stream-to=/tmp/raw` devuelve
**3 frames** (no ceros), y la imagen se ve al revelarla.

### Descartado con datos (todo re-medido con el mapeo de carriles ya correcto)
- **Settle**: barrido 4→60 → 0 paquetes **y 0 errores** en todo el rango. No es temporización.
- **Tabla del CSIPHY**: los **98 registros leen exactamente lo configurado** durante el streaming,
  en csiphy0 **y** en csiphy1 (CTRL0=0x02, CTRL5, CTRL6=0x01, CTRL7=0x02, settle).
- **Relojes y dominios**: csiphy0/1 + phytimer + cphy_rx a 300 MHz, titan_top y ife_0 gdsc **on**.
- **Multiplexor MIPI**: caracterizado del todo (ver abajo). No afecta a csiphy0.
- **Alimentación**: los dos huecos reales (refgen apagado; `vdda-pll` a 1144 mV) tapados
  (0045/0046). No desbloquean.
- **Los dos drivers de sensor**: validados de forma independiente — el PLL de cada blob reproduce
  **exactamente** los fps que el propio blob declara, y el contador de frames late a ese ritmo.

### ⚠️ Dos trampas que costaron caro (ya resueltas)
1. El móvil arrancaba con **el mapeo de carriles roto** (`clock-lanes = <0>` colisionando con
   `data-lanes` → `v4l2_fwnode` usaba {1,2,3}). **Todos los resultados anteriores a eso no cuentan.**
2. **`camera_mipi_switch_en` forzado always-on** (un `/* PRUEBA */` heredado) **impedía por
   completo** que csiphy1 viese la frontal. Con él apagado, el PHY ve la señal. El mux está ahora
   caracterizado: `pm6150_gpios 3` = 0 → frontal, 1 → ultra angular (**confirmado**: los blobs de
   ambos sensores ponen ese pin en valores opuestos), y `camera_mipi_switch_en` (`pm6150_gpios 2`)
   debe quedarse **apagado** — en el DT de fábrica **no lo referencia ningún sensor**.

### Siguiente
1. ~~Decodificar los bits de estado~~ · ~~investigar el LN2 de csiphy1~~ (era un artefacto) →
   ✅ **HECHO** (ver arriba).
2. **Ir a los mantenedores de sm7150-mainline** con el caso, que ahora está cerrado:

   > Dos sensores independientes (Sony IMX682 en csiphy0 con 3 carriles a 953,6 MHz; Samsung
   > S5K3T2 en csiphy1 con 4 carriles a 896 MHz) emiten a los fps que declara el vendor, sus
   > CSIPHY ven actividad eléctrica, y **ambos entregan 0 paquetes y 0 errores al CSID**. El TPG
   > del CSID captura 3 frames perfectos por el mismo CSID/VFE/DMA. Los registros del PHY leen lo
   > configurado y coinciden con la secuencia del downstream (`csiphy_2ph_v1_2_reg` de
   > `cam_csiphy_1_2_hwreg.h`); settle barrido 4→60; relojes, GDSCs y alimentación verificados
   > (incluidos refgen y `vdda-pll` a 1,2 V, que mainline no ponía).
   >
   > Los bits de estado del PHY están decodificados y son **por carril**: en csiphy0,
   > `STATUS[2].7` = carril 1 y `STATUS[5].3` = carril 2, aislados habilitando un carril a la vez
   > en `CTRL5`. **El carril 0 no produce estado pese a llevar señal — igual que el carril 3, que
   > no está cableado.** Sin documentación de los bits no se puede decir si son errores (→ ln1/ln2
   > fallan) o actividad (→ ln0 no recibe); cualquiera de las dos explica los 0 paquetes.
   >
   > Su camss lleva printks de depuración dentro (`v7.1_rc3`) → lo están depurando; nadie ha
   > capturado imagen en sm7150 mainline todavía.

## 2) SENSORES QUE FALTAN  🟢 (prioridad media)

- ✅ **Funcionan los cuatro**: acelerómetro, luz, proximidad **y magnetómetro/brújula**
  (SSC/hexagonrpcd r9). Ver `sensors/`.
- ★ **El magnetómetro nunca faltó** (2026-08-06). La nota anterior decía que
  `net.hadess.SensorProxy` no exponía `HasCompass`: **sí lo expone, pero en otro objeto de
  D-Bus** — `/net/hadess/SensorProxy/Compass`, interfaz `net.hadess.SensorProxy.Compass`.
  Verificado girando el móvil: 144 lecturas, los **4 cuadrantes** y **2141°** de recorrido
  angular acumulado, cruzando el 0/360 sin saltos.
- ⚠️ **Lección**: se dio por ausente mirando el objeto principal de D-Bus y
  `/sys/bus/iio/devices` (donde solo salen los ADC del PMIC — los sensores del ADSP **no**
  aparecen como dispositivos IIO). La comprobación válida es `sudo monitor-sensor`, que reclama
  y muestra lecturas; las banderas `Has*` se leen `true` sin que haya datos.
- Pendiente menor: **giroscopio** — `iio-sensor-proxy` no lo expone; verificar si el SSC lo
  ofrece. Con lo aprendido, mirar primero si está en algún objeto aparte antes de darlo por
  ausente.

---

## 3) CARGA RÁPIDA XIAOMI  🟢 (prioridad baja — requiere cargador Xiaomi)

- Ya está el charge-pump **BQ25970** (`bq25970-charger`, patches 0002-0004) y el límite
  en **3A**. Hay TCPM (`tcpm-source-psy`) gestionando USB-C PD.
- Falta el **handshake del protocolo propietario Xiaomi** para la potencia alta (33W).
  Requiere un cargador Xiaomi compatible para probar.
- **Esfuerzo:** acotado pero depende de tener el cargador y de ingeniería del protocolo.

---

## 4) VIBRACIÓN y GPS 🟡 (abiertos 2026-07-18, ninguno resuelto todavía)

### Vibración — driver enlaza, sin vibración física confirmada

`pm6150.dtsi` ya trae el nodo del vibrador (`qcom,pm6150-vib`/`qcom,pmi632-vib`, driver
mainline `pm8xxx-vibrator.c` ya compilado) — solo estaba `status = "disabled"` (parche
**0060**). Downstream confirma que surya lo tiene cableado (`qcom,vibrator@5300`, LDO 3.0 V,
driver downstream `leds-qpnp-vibrator-ldo.c`).

Con el nodo activado, el driver **enlaza sin error** (`pm8xxx_vib_ffmemless`, API estándar de
force-feedback) y acepta comandos `FF_RUMBLE` — tanto un test crudo con `EVIOCSFF`/`EV_FF`
como el stack real de Phosh (`fbcli`/feedbackd) — **sin ningún error en ningún punto**. Pero
**no se siente vibración física en el terminal, en ningún intento**.

**Bug real encontrado y corregido (parche 0061), insuficiente por sí solo**: comparando
registro a registro contra `leds-qpnp-vibrator-ldo.c` downstream, el campo `drv2` (byte alto
del voltaje del LDO, valor de ~12 bits repartido en dos registros de 8 y 4 bits) necesita un
desplazamiento a la **derecha** para extraer los bits altos antes de la máscara; el código
mainline hacía `level << drv2_shift` (izquierda), que con `drv2_shift=8` siempre deja los 4
bits enmascarados en cero — el voltaje pedido al LDO queda muy por debajo del mínimo
operativo (1504-3544 mV) pase lo que pase. Aplicado en caliente (rmmod/modprobe, sin
reiniciar) y **probado: sigue sin vibrar**. No se ha revertido (es una corrección de lógica
defendible por sí misma) pero no es la causa completa.

**Sin verificar todavía, por falta de herramienta**: leer los registros REALES del periférico
SPMI tras disparar el efecto, para confirmar si los valores calculados llegan de verdad al
hardware. No hay debugfs de regmap disponible (`/sys/kernel/debug/regmap` vacío para este
periférico) — haría falta una herramienta nueva de lectura SPMI (el truco de `/dev/mem` que
usamos para CSIPHY **no sirve aquí**: el espacio de direcciones del PMIC no es MMIO directo,
se accede indirectamente a través del controlador SPMI `c440000.spmi`).

**Próximos pasos**:
1. Construir una herramienta de lectura/escritura SPMI (vía el controlador MMIO real, o vía
   una interfaz de kernel si `CONFIG_DEBUG_FS` + regmap cache se puede habilitar) para leer
   `STATUS1` (0x08, bit `VREG_READY`) tras habilitar, y los propios registros VSET/EN_CTL, y
   confirmar si el valor programado realmente llega.
2. Revisar si falta el **poll de `VREG_READY`** que downstream sí hace tras habilitar (con
   reintento y apagado si no llega) — mainline no lo tiene; puede que el LDO necesite ese
   tiempo/verificación para arrancar de verdad, no solo el valor de voltaje.
3. Descartar que el motor físico simplemente no esté poblado en esta unidad concreta (poco
   probable en un teléfono de serie, pero no verificado).

### GPS — ★ RESUELTO (2026-07-18, la misma noche): el motor venía BLOQUEADO de fábrica

**Causa raíz**: el módem de Xiaomi trae el motor GNSS **bloqueado en NV** (*engine lock*);
Android lo desbloquea desde su HAL residente y en pmOS nadie lo hacía → todo `START`
fallaba con el error genérico 46. Fix: `qmicli -d qrtr://0 --loc-set-engine-lock=none` y el
GPS arranca a la primera (vía ModemManager: `--location-enable-gps-nmea`/`-raw`, NMEA
fluyendo, **satélites a la vista confirmados por el usuario**).

⚠️ **Segundo hallazgo, confirmado empíricamente**: el desbloqueo **REVIERTE** cuando la
sesión GPS se para — un oneshot al arranque NO basta (falló a los ~10 min). Por eso
`gps/gnss-engine-unlock.service` es un servicio **residente** que re-afirma el desbloqueo
cada 10 s (verificado: el ciclo disable→enable que antes fallaba pasa limpio). GeoClue ya
tenía la fuente `modem-gps` activada → las apps GeoClue reciben GPS real sin tocar nada.
Detalle completo: `gps/README.md`. Pendiente menor: fix con vista al cielo (satélites ya se
ven), XTRA fresco para acelerar TTFF, gnss-share/gpsd para apps NMEA ("Satellite").

Lo de abajo queda como historia de la investigación de esa noche:

### (histórico) GPS — el motor GNSS existe y responde, pero `--loc-start` falla

No hay nodos GNSS en el DTS (normal: en SM7150 el GPS vive dentro del firmware del propio
módem, expuesto solo por QMI). Confirmado que el servicio existe:
```
sudo qrtr-lookup | grep -i location
#  → "16  2  0  0  80  Location service (~ PDS v2)"
```
`qmicli -d qrtr://0 --loc-get-operation-mode` responde (`standalone`), y
`--loc-set-nmea-types=all`/`--loc-stop` también funcionan sin error. Pero
**`--loc-start` falla siempre con `QMI protocol error (46): 'GeneralError'`**, incluso tras
parar una sesión previa que sí estaba activa (id 0).

`ModemManager` no expone ninguna sección `Location` en `mmcli -m 0` para este módem — el
plugin `qcom-soc` (basado en QRTR, no en el `/dev/cdc-wdmX` tradicional) probablemente no
tiene implementado el wiring de localización. `GeoClue2` (`geoclue.service`, ya activo) SÍ
funciona pero solo da **ubicación aproximada por red** (GeoIP + triangulación 3GPP/WiFi,
precisión ~25 km — probado con `/usr/libexec/geoclue-2.0/demos/where-am-i`), no GPS real.
Apps como "Satellite" fallan directamente porque buscan una fuente **NMEA** (protocolo gpsd)
que hoy no existe en el sistema.

**Ya descartado (probado en directo, sin cambio en el error)**:
- Datos de asistencia GNSS (XTRA) **caducados** (`--loc-get-predicted-orbits-data-validity` →
  válidos hasta 2026-07-04, dos semanas caducados el 18 de julio) — parecía un candidato
  fuerte. `--loc-delete-assistance-data` (borra los caducados) + reintentar `--loc-start`:
  **mismo error, sin cambio**.
- `--loc-inject-time` (inyectar hora UTC actual) + reintentar: **mismo error, sin cambio**.
- `--loc-get-engine-lock` no da un valor útil (`missing` — el TLV no viene en la respuesta,
  no necesariamente un error).
- `--loc-set-operation-mode=msb` (asistido por red en vez de `standalone`) + reintentar:
  **mismo error, sin cambio**. Devuelto a `standalone` (estado original) al terminar.

### ★ Causa probable encontrada: falta el registro de eventos/cliente maestro antes de START

Montada (solo lectura) la partición `vendor.img` real del firmware de fábrica
(`~/src/en_ext/ubports/surya-fw-V12.0.9.0/vendor.img`, ext4, `mount -o loop,ro`) — están
**todas** las librerías HAL de GPS de Qualcomm: `libloc_api_v02.so`, `libizat_core.so`,
`libgnss.so`, servicios `vendor.qti.gnss@*`, `xtwifi-client`, etc. (`lib64/`, `lib/`, `bin/`,
`etc/gps.conf`).

Los símbolos de `libloc_api_v02.so` (`LocApiV02::open()`, `::registerEventMask()`,
`::registerMasterClient()`, `::setOperationMode()`, `::startFix()`) muestran que el HAL real
de Android **siempre** registra una máscara de eventos y se declara cliente maestro **antes**
de mandar `QMI_LOC_START_REQ_V02`. **`qmicli --help-loc` no expone ninguna opción para
registrar eventos ni cliente maestro** — pero el mensaje SÍ existe en la librería C
(`libqmi-glib`, confirmado por `strings`: mensaje `"Register Events" (0x0021)`, con TLV
obligatorio `Event Registration Mask`). Es decir: **`qmicli` es un envoltorio incompleto para
esta operación concreta**, no un límite del hardware/firmware — el motor probablemente
rechaza `START` porque ningún cliente se ha suscrito a recibir sus resultados.

**Hecho y probado en hardware real (2026-07-18)**: escrito `gps/loc_test.c` — cliente QMI LOC
mínimo contra la API C de `libqmi-glib`/`libqrtr-glib` (no `qmicli`) que abre un nodo QRTR,
aloja un cliente LOC, manda `REGISTER_EVENTS` (posición + estado del motor + NMEA) y, solo si
eso tiene éxito, manda `START`. Ver `gps/README.md` para cómo compilarlo (hay que descargar a
mano los `.apk` de `-dev`, la versión del repo no coincide con la runtime instalada).

**Resultado: `REGISTER_EVENTS` tiene éxito, pero `START` falla exactamente igual** (`error 46
GeneralError`). **Esto descarta la hipótesis del registro de eventos** — no era eso, o no era
*solo* eso. El motor GNSS rechaza `START` por algún motivo que sigue sin identificarse.

**Próximos pasos (en orden)**:
1. Revisar `etc/gps.conf`/`etc/izat.conf` del `vendor.img` (montado en solo lectura, ver
   `gps/README.md`) por parámetros que Android aplica antes de `START` y que no replicamos.
2. Añadir más campos opcionales al mensaje `START` (`loc_test.c` solo fija `session_id`,
   `intermediate_report_state` y el intervalo — la librería real probablemente fija más:
   modo de posición, `fix_recurrence`, `min_distance`... revisar `qmi-loc.h` completo y
   comparar contra el desensamblado de `libloc_api_v02.so::startFix()`).
3. Si nada de eso destapa la causa: capturar traza QMI real (cuidado con el riesgo de
   `/dev/diag` ya documentado en el trabajo de audio) o plantear si es un bloqueo de
   permisos/antena a nivel de firmware, no de secuencia de comandos.
4. Si arranca de verdad: evaluar conectar el NMEA resultante a `gpsd` o escribir el wiring
   para que ModemManager lo exponga vía `Location`, que es lo que GeoClue2 y apps como
   "Satellite" esperan.

**Descartado ya (probado en directo, sin cambio en el error 46)**:
- Datos de asistencia XTRA caducados (dos semanas) → borrados, sin cambio.
- `--loc-inject-time` → sin cambio.
- `--loc-set-operation-mode=msb` (asistido) → sin cambio, devuelto a `standalone`.
- `--loc-get-engine-lock` no da dato útil (`missing`).
- **Registro de eventos correcto antes de START** (`loc_test.c`, API C directa) → sin cambio,
  es el descarte más fuerte de los cinco.

---

## 5) WAYDROID ✅ COMPLETADO (2026-07-19 — red, pantalla y migración desde Ubuntu Touch)

### ✅ RESUELTO: sin IP (`IP address: UNKNOWN`) — dos causas apiladas

1. **Módulos de iptables legacy sin cargar.** `netd` de Android usa iptables **legacy**;
   el host solo carga `nf_tables`/`nft_*`. Sin `ip_tables` y familia, `netd` no crea
   ninguna cadena (`Table does not exist`, decenas de `iptables-restore ... status=512`)
   y Android **ni intenta** pedir DHCP. → `/etc/modules-load.d/waydroid.conf`.
2. **El firewall de pmOS descarta el DHCP del contenedor.** Tabla `inet filter`,
   `policy drop` en `input` y `forward`, y `bootps` permitido solo en
   `usb*`/`wlan*`/`p2p-wlan*`. ⚠️ **Trampa**: `waydroid-net.sh` crea su tabla `inet lxc`
   que sí lo acepta, pero en nftables **cada tabla evalúa por separado** — un `accept` en
   una no salva al paquete del `drop` de la otra. → `/etc/nftables.d/60_waydroid.nft`.

Verificado: lease `<ip>`, `ping 8.8.8.8` 0% pérdida. Ver `waydroid/README.md`.

### ✅ RESUELTO por el camino: la ventana salía TRANSPARENTE

Se resolvió sola al reiniciar el contenedor con la red ya sana. **No era gráficos**
(gralloc/Mesa/freedreno estaban bien: `RenderEngine: vendor freedreno`, SurfaceFlinger
arriba) sino el contenedor en mal estado. Si reaparece: `waydroid logcat` filtrando
`gralloc|SurfaceFlinger|EGL|gbm`.

### ✅ RESUELTO: migración del Waydroid de Ubuntu Touch (2026-07-19)

Hecha y verificada: **77 apps** con sus datos (Triodos, CaixaBankNow, N26, PayPal,
WhatsApp, Telegram, Authenticator, Keepass2Android…) y el `/sdcard` entero.

- **NO hace falta remapear UIDs.** Los UIDs de Android son **internos al contenedor e
  idénticos en ambos sistemas** (`u0_a138` = 10138 en los dos). Comprobado: **0 ficheros
  con uid 32011 (phablet) dentro de `data/`**. Lo único con UID del host es el
  **directorio contenedor** → `chown edi:edi ~/.local/share/waydroid`, y nada de dentro.
  Remapear los UIDs internos habría roto todo.
- **La causa del fallo original** era solo la **ruta**: el script de sync copia a la misma
  ruta en ambos equipos (`/home/phablet/…`), pero pmOS lee de `$HOME/…`
  (`waydroid.host_data_path`), así que los 17,5 GB quedaban sin usar.
- Los `system.img` de ambos son **idénticos** (mismo sha256, 1981640704 bytes) = mismo
  LineageOS 20 / **Android 13**. El "Android 11 / Nothing Spacewar" de UT es un **spoof
  de props** de `waydroid_script`, no otro Android. ⚠️ No instalar Android 11: los datos
  son de 13 y Android no soporta bajar de versión el `/data`.
- **No** se migra `/var/lib/waydroid/` (vendor `HALIUM_11`/Adreno vs `MAINLINE`/Mesa;
  binder `anbox-binder` vs `binder`; 1.5.1 vs 1.6.2). Cada equipo conserva el suyo.
- Todo en el **mismo sistema de ficheros** (`/dev/loop0p2`) → `mv` instantáneo y sin
  coste de espacio, importante porque solo quedaban ~17,4 GB libres frente a 17,5 GB.
- **Identidad copiada** a `waydroid_base.prop` (`ro.build.fingerprint` de
  Nothing/Spacewar + `ro.product.waydroid.*`) para que las apps no vean cambio de
  dispositivo. Verificado dentro: `getprop ro.product.model` → `A063`. ⚠️ **No** copiar
  `ro.sf.lcd_density` (el panel es otro) ni tocar los `ro.hardware.*` de gráficos.
  Backup en `waydroid_base.prop.pre-migracion`.
- **El keystore es portable aquí**: `ro.crypto.state=unsupported` (sin FBE/FDE),
  `ro.hardware.keystore` vacío (keymaster por software), sin `gatekeeper.*` — no hay TEE
  que ancle las claves, así que viajan con los datos.
- `dalvik-cache` vaciado por precaución, pero es **casi irrelevante**: desde Android 8 los
  `.oat` por app viven en `/data/app/*/oat/` y viajaron intactos.
- Copias de seguridad que quedaron en pie: el Waydroid original en eut2lan (intacto),
  `~/.local/share/waydroid.bkp` (11,8 G), `data.vacio`, `waydroid.orig`, y el
  `.SeedVaultAndroidBackup` (5,5 G) dentro de los propios datos migrados.

**Residual conocido**: `com.android.nfc` muere en bucle (no hay HAL de NFC en Waydroid,
es ruido) · `cm.aptoide.pt` da `FATAL EXCEPTION` al arrancar (una sola app) · el primer
arranque tras migrar deja la carga en ~18 varios minutos escaneando los 77 paquetes.

---

## FUTURO / posible: HUELLA DACTILAR  🟠

- Lector capacitivo lateral. Hay un `spi0.0` (los capacitivos suelen ir por SPI) = gancho,
  pero **sin driver** y hay que identificar el chip (FPC/Goodix/FocalTech). Rara vez existe
  driver mainline abierto para estos. Se deja como exploratorio para más adelante.

## DESCARTADOS (límite físico del POCO X3 NFC)
- ⛔ Carga inalámbrica — sin bobina Qi.
- ⛔ HDMI/DP por USB-C — USB 2.0, líneas SuperSpeed/DP no cableadas al conector.


---

## ★ HISTÓRICO — COMPARACIÓN `lane_regs_sm7150` vs CSIPHY del downstream (2026-07-17)

> ⚠️ **Medido con el mapeo de carriles roto** (ver `camera/README.md` §TRAMPA): los resultados
> negativos de aquí **no cuentan**. La comparación de tablas sí sigue siendo válida y útil.

**Fuente correcta**: `sdmmagpie-camera.dtsi` dice `compatible = "qcom,csiphy-v1.2"` → la tabla del
downstream es **`cam_csiphy_1_2_hwreg.h`** (`techpack`/`drivers/media/platform/msm/camera/
cam_sensor_module/cam_csiphy/include/`). Ojo: hay que usar **`csiphy_2ph_v1_2_reg`** (2PH = **D-PHY**,
que es lo nuestro), NO `csiphy_3ph_*` (ése es C-PHY). El fichero de mainline se llama
`camss-csiphy-3ph-1-0.c` pero su "3ph" se refiere a la generación del bloque, no a C-PHY.

Tamaños: mainline **115** escrituras / 95 direcciones · downstream **110** (5 bancos de carril).

### 1. Valores DISTINTOS en direcciones comunes (10)
| registro | downstream | mainline |
|---|---|---|
| 0x900 / 0xa00 / 0xb00 / 0xc00 | **0x06 / 0x0b / 0x01 / 0x0e** (uno por carril) | **0x0F en todos** |
| 0x908 / 0xa08 / 0xb08 / 0xc08 | **0x07 / 0x01 / 0x03 / 0x1d** | **0x06 en todos** |
| 0xc88 | 0x14 | 0x06 |
| 0x000 | 0x91 | 0x91 (+ceros de otros bancos) |

**El downstream usa valores específicos por carril donde mainline pone uno uniforme.** ← **el
sospechoso más fuerte que queda.**

### 2. Direcciones que solo escribe el downstream (9)
`0x0c4, 0x2c4, 0x4c4, 0x6c4, 0x7c4` (los `0x00c/0x20c/0x40c/0x60c` son **DNP** = do-not-program, no cuentan).

### 3. Direcciones que solo escribe mainline (8)
`0x05c, 0x060, 0x25c, 0x260, 0x45c, 0x460, 0x65c, 0x660`.

### 4. Ajustes por VELOCIDAD DE DATOS — mainline no tiene ninguno
El downstream trae `data_rate_delta_table_1_2` con 3 tramos:
`5.7e9` (≤2,5 Gbps/carril, 12 regs) · `7.98e9` (≤3,5 Gbps, 24 regs) · `10.26e9` (≤4,5 Gbps, 24 regs).
Nuestro enlace (**1907 Mbps/carril**) cae en el primero → 12 registros:
`0x15C/0x35C/0x55C=0x66` · `0x9B4/0xAB4/0xBB4=0x03` · `0x144/0x344/0x544=0x22` · `0x16C/0x36C/0x56C=0xAD`.
**mainline no escribe ninguno de los 12.** (Detalle bonito: los bancos van de tres en tres —
0x15C/0x35C/0x55C = bases 0x000/0x200/0x400 — **coherente con nuestros 3 carriles**.)

### ⚠️ PROBADO: aplicar los 12 registros de data-rate **NO arregla nada** (sigue 0 bytes).

### Verificado de paso (con prints en camss)
`csiphy_set_stream(1)` **SÍ se llama**, `lanes_enable` **SÍ se ejecuta**, `settle_cnt = 20`.
O sea: **el CSIPHY sí se está configurando**. El problema son los *valores*, no la falta de ejecución.
⚠️ Un print mío mostró `CTRL5=0x0`: **es un artefacto** — puse el `dev_info` al final de la función,
donde `val` ya se había reutilizado (`val = 0x00` para CTRL0). **No es el valor real de CTRL5.**

### ⚠️ PROBADOS LOS DOS CAMBIOS — NINGUNO ARREGLA NADA (2026-07-17)

1. **Los 12 registros de data-rate** del tramo ≤2,5 Gbps → **0 bytes**.
2. **Los 9 valores por carril** del downstream (0x900=0x06, 0x908=0x07, 0xa00=0x0b, 0xa08=0x01,
   0xb00=0x01, 0xb08=0x03, 0xc00=0x0e, 0xc08=0x1d, 0xc88=0x14), aplicados **junto con** los
   anteriores (como hace el downstream) → **0 bytes**. csiphy0 IRQ sigue en **0**.

Mapa de bancos (verificado) para quien siga: `csiphy_2ph_v1_2_reg[5]` indexa
`[0]`=datos0 (0x000 + 0x900) · `[1]`=**RELOJ** (0x700 + 0xc80) · `[2]`=datos1 (0x200 + 0xa00) ·
`[3]`=datos2 (0x400 + 0xb00) · `[4]`=datos3 (0x600 + 0xc00). Todo lo demás de los bancos **coincide**
entre mainline y downstream (0x_04, 0x_10 iguales; 0xc80=0x0f igual).

### Lo que queda por probar (sin orden de confianza — ya no tengo pista fuerte)
- Añadir los `0x_c4 = 0x00` (0x0c4, 0x2c4, 0x4c4, 0x6c4, 0x7c4) que el downstream escribe y mainline no.
- Quitar los que **solo** escribe mainline: `0x05c, 0x060, 0x25c, 0x260, 0x45c, 0x460, 0x65c, 0x660`.
- **Diferencia estructural de fondo**: el downstream (`cam_csiphy_core.c`) itera
  `for (i = 0; i < num_lanes; i++)` → **configura solo los carriles en uso**; la tabla plana de
  mainline **configura los 4 carriles + reloj siempre**. Con 3 carriles, el carril 3 queda
  configurado pero sin señal. *(Pero SDM845 usa el mismo esquema plano y funciona → no está claro.)*
- **Ir a los mantenedores de sm7150-mainline** con todo esto: es lo más sensato. Tienen camss
  instrumentado con printks, o sea que están en ello. Nuestro caso es sólido y acotado:
  **el sensor emite a 30 fps (FRAME_COUNT), el TPG del CSID captura 3 frames perfectos, y el CSIPHY
  no ve nada (IRQ=0)** — con las diferencias de tabla ya comparadas y descartadas.

### Experimento ya realizado (era "el que queda")
Portar **los valores por carril del downstream** (`csiphy_2ph_v1_2_reg`) a `lane_regs_sm7150`:
0x900=0x06, 0x908=0x07, 0xa00=0x0b, 0xa08=0x01, 0xb00=0x01, 0xb08=0x03, 0xc00=0x0e, 0xc08=0x1d,
0xc88=0x14, y añadir los `0x_c4`. Es la única diferencia estructural que queda sin probar.


---

## ★ HISTÓRICO — INVESTIGACIÓN A FONDO DEL CSIPHY (2026-07-17, madrugada)

> ⚠️ **Todo lo de esta sección se midió con el mapeo de carriles roto** → los resultados
> negativos **no cuentan**. El barrido de settle se ha repetido ya en condiciones válidas
> (sigue en cero). Ver `camera/README.md`.

### ⚠️⚠️ CORRECCIÓN GRAVE: "csiphy0 IRQ = 0" NO PRUEBA NADA
Durante toda la investigación anterior usé `csiphy0 IRQ = 0` como prueba de que "el PHY no ve señal
en el cable". **ES FALSO.** El final de `csiphy_lanes_enable()` hace:
```c
/* IRQ_MASK registers - disable all interrupts */
for (i = 11; i < 22; i++)
	writel_relaxed(0, csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, i));
```
**mainline enmascara TODAS las IRQ del PHY** → el contador está a 0 por diseño. (El downstream hace
lo contrario: `csiphy_irq_reg_1_2[]` las activa en 0x82c–0x854, que son **exactamente** los registros
que mainline pone a cero.)

### Activando las IRQ del PHY (valores del downstream)
Resultado: **~280.000 interrupciones**, estado **constante**:
`STATUS: 00 00 80 00 00 08 00 00 00 00 00` (status[2]=0x80, status[5]=0x08).
⚠️ **Pero esto TAMPOCO prueba que el PHY vea señal**: es una **tormenta de interrupciones** (el ISR
lee el estado y escribe en CTRL(22+i) para limpiar, y no lo consigue), y **el estado es idéntico con
3 y con 4 carriles** → es un bit latcheado, no un error por paquete. **Sigue sin saberse si el PHY
recibe algo.**

### Experimentos hechos esta madrugada — TODOS con 0 bytes
| experimento | resultado |
|---|---|
| 12 registros de **data-rate** del downstream (tramo ≤2,5 Gbps) | 0 bytes |
| 9 **valores por carril** del downstream (0x900=0x06, 0x908=0x07, 0xa00=0x0b, 0xa08=0x01, 0xb00=0x01, 0xb08=0x03, 0xc00=0x0e, 0xc08=0x1d, 0xc88=0x14) | 0 bytes |
| **Barrido completo de settle_cnt: 6, 10, 14, 18, 20, 24, 29, 34, 39, 44** | 0 bytes en todos |
| **4 carriles** (sensor `0x0114=0x03` + DT `<0 1 2 3>`) | 0 bytes, **estado del PHY idéntico** |
| **Activar las IRQ del PHY** | tormenta de 280k, estado constante |

### Cosas verificadas por el camino (útiles)
- **`csiphy_set_stream(1)` SÍ se llama** y **`lanes_enable` SÍ se ejecuta** (comprobado con prints).
- El registro **0x800 (CTRL0)**: mainline escribe 0x00 en `lanes_enable`, **pero la tabla lo corrige
  después a 0x02** (5 veces, una por banco) — igual que el downstream para D-PHY. **No es un bug.**
- **CTRL5 (0x814) = lane enable**: mainline calcula `BIT(7) | BIT(pos*2)` y el downstream
  `lane_enable |= 0x80; lane_enable |= 0x1 << (i<<1)` → **misma fórmula**. Con `data-lanes = <0 1 2>`
  sale **0x95**, que es lo correcto para 3 carriles. (El `0xd5` de la tabla del downstream es un
  **placeholder**: el `case CSIPHY_LANE_ENABLE` escribe el valor **calculado**.)
- **Orden del downstream**: (1) calcula lane_enable, (2) programa `csiphy_common_reg`, (3) `while
  (lane_mask)` → `reg_array[lane_pos]` **solo para los carriles de la máscara**. En su máscara,
  **el bit 1 es el RELOJ** (`reg_array[1]` = banco 0x700/0xc80).
- **`t_hs_settle` de mainline usa el borde INFERIOR exacto** de la ventana MIPI (85ns+6UI = 88,1 ns de
  un rango 88,1–150,2 ns). Parecía marginal → probado el centro y todo el barrido: **no es eso**.

### Estado: sin pista fuerte. RECOMENDACIÓN: ir a los mantenedores
Caso acotado y sólido: **el sensor emite a 30 fps** (FRAME_COUNT por I2C) · **el TPG del CSID captura
3 frames perfectos** (CSID+VFE+DMA OK) · **el CSIPHY no entrega datos** con settle barrido, tablas
comparadas con el downstream y ambas variantes de carriles probadas.

**Herramienta útil que queda**: `settle_override` como parámetro de módulo de `qcom_camss`
(`/sys/module/qcom_camss/parameters/settle_override`, -1 = calculado) para barrer sin recompilar.

**Estado del árbol de build** (`/ext_r/ext_edi/src/suria/kernel-build`, **NO** en los parches):
camss lleva los experimentos (regs de data-rate, valores por carril, IRQ activadas + volcado de
estado en el ISR, `settle_override`, settle al centro). El sensor y el DT están **restaurados a 3
carriles**. Los parches 0041-0044 solo llevan lo que funciona.

## Llamadas por Bluetooth (2026-07-20)

**Siguiente paso concreto**: llamada real con SIM puesta y auricular emparejado, seleccionando el
perfil `Voice Call (Bluetooth)`. Todo lo demás está montado y verificado.

Pendientes menores:
- Integrar el nuevo modo en **callaudiod** para que el botón lo ofrezca (hoy el perfil existe pero
  hay que seleccionarlo a mano con `pactl set-card-profile`).
- Sin explicar y **sin bloquear**: bajo martilleo continuo, cada ~1,28 s una transacción no recibe
  ni respuesta ni NACK ni interrupt y agota el segundo. El reintento lo cubre.
- Corregir por exactitud `qcom,wcn3998-pmu` → `qcom,wcn3990-pmu` (mismo comportamiento: el driver
  mapea ambos compatibles a los mismos datos).
- Candidatos a upstream, todos arreglos genuinos y acotados:
  - `slimbus: qcom-ngd`: fallar la transferencia cuando el hardware reporta NACK (parche 0004).
  - `slimbus` (núcleo): `slim_device_probe()` difiere el probe si la dirección lógica no está a la
    primera, y **devm destruye lo que el driver acaba de registrar**.
  - ASoC: `SLIMBUS_7` en q6dsp y el mapa de canales SLIMBus que a `sm8250.c` le falta entero.


## Bugs de telefonía reportados 2026-08-01 (a revisar, NO investigados aún)

- **El auricular (earpiece) no suena en llamada; por altavoz sí.** Visto varias veces esta
  noche. ⚠️ Ojo: durante las pruebas se mata `callaudiod` a propósito, y eso YA provoca este
  síntoma — hay que reproducirlo con `callaudiod` vivo antes de darlo por bug real.
  `verify-call-routing.sh` pasa correctamente (auricular ↔ manos libres con sus volúmenes),
  así que el ruteo en sí funciona.
- **Silenciar el micro en llamada no funciona: siempre emite.** El driver tiene
  `q6cvs_mute()` implementado y se usa al descolgar (para *desmutear*), pero **nada conecta
  el botón de silencio de la app con él** — probablemente no está cableado en callaudiod ni
  en el UCM. Candidato claro para arreglar, es pequeño y de valor directo.

---

## callaudiod deja el sistema configurado para LLAMAR (2026-08-06)

Al colgar, `callaudiod` **no restaura la salida previa**: deja fijada la de llamada. Como
wireplumber **guarda** esas elecciones en `~/.local/state/wireplumber/`, el efecto persiste entre
desconexiones y reinicios. Dos manifestaciones medidas:

1. **Fija el sumidero por defecto** (`pa_context_set_default_sink`, visible en sus símbolos) →
   `default.configured.audio.sink = ...HiFi__Speaker__sink`. Esa fijación **gana a la prioridad**
   (el nodo bluez tiene 1010 frente a 1000 del altavoz), así que al conectar el auricular el
   sonido no salta.
2. **Deja el móvil en `HiFi (Earpiece, Mic)`** → al desconectar el Bluetooth el audio cae **al
   auricular de la oreja** (mono, flojísimo) en vez de al altavoz. Se confunde fácilmente con
   «no ha cambiado de salida», y así fue como se detectó.

**Compensado, no arreglado**: `llamada-al-bluetooth.sh` devuelve el auricular a `a2dp-sink` al
colgar y autoconmuta al conectarlo (transición ausente→presente; `touch
/etc/bt-no-autoconmutar` lo desactiva). Pero la causa sigue ahí.

**Arreglo de fondo**: que `callaudiod` recuerde la salida y el perfil antes de tomar el control
de la llamada y los restaure al colgar. Ya existe un parche propio sobre ese binario
(`audio/callaudiod/0001-boton-de-salida-con-auricular-bluetooth.patch`), así que no es terreno
nuevo.

⚠️ Antes de tocarlo, **confirmar que el comportamiento persiste tras una llamada real** con el
estado actual: la restauración a A2DP se añadió después de las últimas pruebas y podría cambiar
el cuadro.

---

## Conmutación automática de salida al conectar/desconectar el auricular Bluetooth

**Qué se quiere**: al conectar el auricular, el sonido salta a él; al desconectarlo, vuelve al
**altavoz** (no al auricular de la oreja).

### Piezas necesarias, y estado de cada una

**1. A2DP disponible** — ⛔ *hoy desactivado*. Sin A2DP el auricular solo ofrece el perfil de
manos libres (mono, 8 kHz), que wireplumber **no elige para reproducción normal** —de ahí los
mensajes `Could not find valid non-headset profile, not switching`—. **No hay sumidero de música
al que saltar**, y por eso parece que «no conmuta».
→ Requiere quitar `53-solo-hfp.conf` (`bluez5.roles = [ hfp_ag hsp_ag ]`).
⚠️ Se reactivó el 2026-08-06 porque tras quitarlo las llamadas con auricular fallaron; **luego se
demostró que la causa era otra y ya está arreglada** (el DSP se estrellaba por la suspensión de
la ruta interna, ver la sección RESUELTO más abajo). → **Reintentar quitarlo**, probando una
llamada inmediatamente después; ahora hay motivos para pensar que funcionará.

**2. Que no haya un sumidero fijado al altavoz** — `default.configured.audio.sink` en
`~/.local/state/wireplumber/default-nodes`. Esa fijación **gana a la prioridad** (bluez 1010 vs
altavoz 1000). La escribe **`callaudiod`** al colgar (`pa_context_set_default_sink`).
⚠️ Editarla con el auricular **ausente** no sirve: se reescribe. Hay que actuar **con el
dispositivo presente**.

**3. Conmutar al aparecer el sumidero** — ✅ *implementado* en `llamada-al-bluetooth.sh`
(`autoconmutar()`): al detectar un `bluez_output.*` mueve ahí el predeterminado **y los flujos en
curso**. Solo en la transición ausente→presente, para no pisar una elección manual.
⚠️ **NUNCA durante una llamada** (`hay_llamada && return 0`): mover la salida al sumidero A2DP
deja el perfil sin HFP, sin SCO, y **la llamada sale muda**. Ya ocurrió.
Interruptor: `touch /etc/bt-no-autoconmutar`.

**4. Devolver el auricular a A2DP al colgar** — ✅ *implementado*. Al descolgar se le pone
`headset-head-unit-cvsd` y wireplumber **guarda** ese perfil; sin deshacerlo, al reconectar entra
en perfil de llamada y volvemos al punto 1.

**5. Que la vuelta caiga al ALTAVOZ, no al auricular de la oreja** — ⛔ *pendiente*. Visto que al
desconectar el Bluetooth el móvil cae a `HiFi (Earpiece, Mic)` (mono, flojísimo), lo que se
confunde fácilmente con «no ha cambiado». El perfil fijado del dispositivo ya era
`HiFi (Mic, Speaker)` y aun así cayó al auricular → lo fuerza **`callaudiod`**, no la fijación.
→ Arreglo de fondo: que `callaudiod` restaure la salida previa al colgar (§ pendiente propio).

### Resumen operativo

Con (1) reactivado, (3) y (4) ya hechos, la conmutación **funcionó y se verificó** en ambos
sentidos el 2026-08-06. Lo que falta para dejarlo permanente es **(1) sin romper las llamadas** y
**(5)**.

---

## ✅ RESUELTO — El ADSP se caía en llamadas por Bluetooth (2026-08-06)

**Causa**: wireplumber suspendía la ruta interna del móvil a los 5 s de quedar ociosa (con la
llamada en el casco) y, al remontarla, el ciclo apagado/encendido de los relojes LPASS hacía
reventar al servicio AFE del firmware del DSP.
**Arreglo**: `55-no-suspender.conf` (`session.suspend-timeout-seconds = 0`,
`node.pause-on-idle = false` para los nodos `platform-sound`). Verificado: cero caídas.
Detalle completo en `COMO-DEJAR-TODO-FUNCIONANDO.md` §9.

Lo que sigue es el diagnóstico previo, conservado porque documenta el camino:

**Corrige un diagnóstico anterior**: no es el cambio a manos libres lo que lo estrella.

```
13:16:37  moving call: tx 151 -> 151      (repeticion, la llamada EN el casco)
13:16:42  crash detected in adsp          <- 5,5 s despues, SIN tocar nada
13:16:43  moving call: tx 151 -> 120      <- el cambio de salida llega DESPUES del crash
```

El ADSP muere **con la llamada en Bluetooth**, a veces al cambiar de salida (visto a 46 ms) y a
veces solo a los pocos segundos. Todo lo que viene después falla con `-110` y el móvil acaba
reiniciándose. Explica el síntoma «se oye por cascos, luego nada por ningún lado».

📌 Pista sin explotar: **`failed to send del client cmd`** (del controlador SLIMBus NGD) aparece
repetidamente antes de las caídas — **688 veces** en el arranque que se estrelló dos veces,
**185** en uno que no se estrelló, **0** en otro. No es concluyente pero correlaciona.
