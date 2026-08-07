# ★★★★★ 2026-08-07 — LA CÁMARA FUNCIONA

El IMX682 entrega fotogramas reales al sistema. **Causa raíz: el sensor transmite en C-PHY y el
receptor estaba configurado para D-PHY.** Implementado el soporte C-PHY en `camss` (parche 0110).

## ★★★★★ 2026-08-06 — IMAGEN RECONOCIBLE POR libcamera

**Ya hay foto.** `capturas/2026-08-06-trasera-1538x1157.png`: se ve la mesa, un cable, la silla,
la pared y el borde del teclado.

No hizo falta escribir nada para libcamera: **`SimplePipelineHandler` ya trae `qcom-camss` en su
tabla de dispositivos soportados**. Basta instalar `libcamera-tools`:

```sh
sudo apk add libcamera-tools
cam -l                                        # lista imx682 y s5k3t2
cam -c 1 --capture=60 --file=$HOME/ae#.raw
```

- **60 fotogramas a ~30 fps**, ABGR8888 4616×3472, con ISP por software sobre GPU (Mesa/EGL).
- **La exposición automática funciona**: `IPASoft: Exposure 9-3506, gain 0-978`, y la media de la
  imagen sube de 35,6 a 93,8 según converge. Ya no hace falta subir `analogue_gain` a mano.

⚠️⚠️ **EL PASO DE FILA MUERDE DOS VECES.** También en **crudo**: el fotograma RAW10 empaquetado
mide `20 109 824 / 3472 = `**`5792`** bytes por fila, no los `4624 × 10 / 8 = `**`5780`** que sale
de la cuenta ingenua. Con 5780 cada fila se desplaza 12 bytes y lo que se mide es **ruido de
cizalla, constante por construcción** — me dio una «nitidez» plana en todo un barrido de enfoque y
casi me hace concluir cosas falsas. **Siempre `tamaño_de_fotograma / alto`.**

⚠️⚠️ **TRAMPA DEL PASO DE FILA (me costó un diagnóstico entero equivocado).** El búfer de salida
lleva **relleno**: `bytesused` = 64 884 736 = 3472 × **18 688** bytes = **4672 píxeles** por fila,
no los 4616 de la imagen (4616 redondeado a múltiplo de 64). Al leerlo con 4616 cada fila queda
desplazada 56 píxeles respecto de la anterior, y el resultado es un **bandeado horizontal
perfecto**: filas uniformes de lado a lado, degradado vertical suave, desviación entre columnas
de 0,09 frente a 20,86 entre filas. Lo diagnostiqué como «fotograma oscuro, no llega luz al
sensor» — y era una foto correcta leída mal. **Sacar el paso de `bytesused / alto`, nunca del
ancho.**

⚠️ Esto también **matiza la verificación de ayer**: la «correlación con el vecino 0,996» probaba
estructura espacial, no que hubiera una escena. Un patrón de bandas correlaciona igual de bien.
Lo que prueba que hay imagen es **verla**.

Calidad pendiente (el ISP corre **sin calibrar** para este sensor): imagen lavada, esquinas
oscuras por viñeteo sin corregir y color apagado. Detalle en «Lo que falta».

### En la app: Snapshot, vía PipeWire

`snapshot` y `pipewire-spa-libcamera` **ya venían instalados**. Las dos cámaras aparecen como
`Video/Source` en PipeWire (`imx682` y `s5k3t2`) sin tocar ninguna configuración.

⚠️ **Precondición, no misterio**: el monitor de libcamera de WirePlumber **enumera una sola vez,
al arrancar**. Como los módulos de la cámara están en lista negra y se cargan a mano después del
arranque, WirePlumber ya subió sin cámaras y no hay ningún nodo de vídeo. Se arregla con:

```sh
systemctl --user restart wireplumber       # ⚠️ NUNCA con una llamada en curso
```

Verificado que el audio sobrevive al reinicio (mismo sink, mismo micro, tarjeta en HiFi). Cuando
los módulos salgan de la lista negra esto dejará de hacer falta.

### La imagen sale girada — RESUELTO (parche 0112)

Nadie le decía a libcamera cómo está montado el módulo, así que asumía 0° y la vista salía de
lado (`Rotation control not available, default to 0 degrees` · `Failed to retrieve the camera
location`). Se declara en el árbol y se registran los controles estándar `V4L2_CID_CAMERA_*`.

⚠️ **El `sensor-position-roll` de fábrica está medido AL REVÉS** que la propiedad `rotation` del
binding. Fábrica dice 90 para la trasera; **con 90 la vista sale boca abajo y con 270 derecha**,
verificado en el móvil. La regla es **`rotation = 360 − roll`**.

| sensor | `roll` de fábrica | `rotation` correcta | `orientation` |
|---|---|---|---|
| IMX682 trasera | 90 | **270** ✅ verificada | 1 (back) |
| S5K3T2 frontal | 270 | **90** ⬜ sin verificar (no tiene enlace) | 0 (front) |

Ahora libcamera las llama «Internal back camera» / «Internal front camera» y **Snapshot muestra la
vista derecha**. Verificado por el usuario: **4 fotos y un vídeo, todo correcto**.

📌 Para no gastar un reinicio por cada valor (el árbol solo se relee al arrancar), el parche
**0113** añade `imx682.rotation_override` y `imx682.image_orientation`. El segundo distingue un
giro de un espejo, que a simple vista se confunden: **una rotación nunca puede producir un
espejo**, así que si la imagen sale reflejada la perilla de rotación es la equivocada.

⚠️ Para recargar los módulos hay que **parar `wireplumber` antes**, o `rmmod` falla con
*«qcom_camss is in use»* (tiene abiertos los dispositivos de vídeo).

### ★★★★ ENFOQUE MANUAL — FUNCIONA (2026-08-06/07, parches 0114 + 0115)

**La lente se mueve y el enfoque es real**, verificado por el usuario en la vista previa de la app
mientras se barrían posiciones desde la consola. Objetivamente: nitidez con **pico único en la
posición 600** (0,969 frente a 0,80 de base) con el brillo estable, y visualmente **de no
distinguir nada en la 0 a leer las teclas del teclado en la 600**.

**★ LO QUE LO DESTAPÓ: el blob de fábrica NOMBRA el actuador.**

```
com.qti.sensormodule.j20c_ofilm_imx682_ver2_wide.bin:  actuatorDriver  actuatorName  dw9800
```

Es un **DW9800**. Se había acertado la familia (Dongwoon) por el protocolo, pero **dentro de
Dongwoon hay dos dialectos incompatibles**: el DW9714 se escribe con **16 bits sueltos sin índice
de registro** y el DW9800 va **por registros** (`0x03`=MSB, `0x04`=LSB, `0x02`=control), como el
DW9807. Con el driver equivocado el chip **aceptaba todas las órdenes con `rc=0` y no movía nada**.
⚠️ El `ACK` del bus solo dice que alguien vive en esa dirección, **no que entienda lo que se le
manda**. Y la pila de fábrica menciona los cuatro candidatos (`dw9800`, `dw9714`, `ak7374`,
`lc89821`), así que **no desempata**: lo hace el protocolo, o el blob del módulo.

**Verificación definitiva, independiente de la escena**: se pide 100 / 500 / 900 por el control
V4L2 y el chip devuelve `0x0064` / `0x01F4` / `0x0384`. Escribe la posición exacta.

**Piezas** (parche **0115**): DT con `compatible = "dongwoon,dw9807-vcm"` + `vcc-supply` +
`lens-focus`, `CONFIG_VIDEO_DW9807_VCM=m`, y **dos añadidos al driver de mainline**:
1. **Soporte de regulador** (`vcc-supply`) — no lo tenía. Sin él la bobina no recibe corriente:
   el agujero original era que `uw_ldo_ois_drv` estaba descrito en el árbol **sin ningún consumidor**
   (`num_users=0`, `disabled`).
2. **Fallos de I2C no fatales en las llamadas de energía.** El driver asume que el motor tiene
   alimentación propia; aquí **solo responde con el sensor encendido**. Al cargar, el kernel lo
   suspende, la escritura falla, el driver devuelve error y el núcleo **marca el dispositivo con
   `power.runtime_error` de forma permanente** → a partir de ahí **todo da `EINVAL`, incluso abrir
   el subdispositivo**. Es un arreglo válido para cualquier placa que comparta alimentación.

⚠️ **DEPENDENCIA**: con `lens-focus`, el sensor **espera al módulo de la lente**. Orden de carga:
`dw9807_vcm` → `qcom_camss` → `imx682` → `s5k3t2`. Sin él, **la cámara no aparece**.
⚠️ Al recargar los módulos hay que **rehacer enlaces Y formatos de TODAS las etapas** del grafo
(el CSID y el VFE vuelven a 1920×1080 y el enlace no valida). Antes lo hacía libcamera.
⚠️ El driver **devuelve la lente a 0 al cerrar el nodo** → un `v4l2-ctl --set-ctrl` suelto deshace
lo que acaba de poner; hay que mantenerlo abierto (`exec 3<> /dev/v4l-subdevN`).

### ★★★ ENFOQUE EN libcamera: RESUELTO (parche propio, 2026-08-07) — pero las apps siguen sin verlo

**Hecho**: parche propio en `parches/packages/libcamera/` (APKBUILD + parche + README con la receta
completa de compilación cruzada). El manejador **simple** publica ahora `AfMode` (**solo manual**,
este camino no tiene algoritmo) y `LensPosition`, la aplica **antes de encolar los búferes** del
fotograma y la informa en los metadatos.

**Verificado sin depender de la escena**: pedir **0 / 3,5 / 7 dioptrías** deja el chip en
**0 / 512 / 1023**, leídos del propio DW9800 — y **el usuario oye los movimientos del motor**, que
con el protocolo equivocado no se oían porque no se movía.

⚠️ En 0.7.1 **solo el manejador de Raspberry Pi** publica estos controles (el de IPU3 mueve la
lente **internamente** desde su IPA), así que **hubo que escribirlo, no portarlo**.

#### ⛔ Dónde se corta ahora, capa por capa (medido)

| capa | enfoque manual |
|---|---|
| Kernel + motor DW9800 | ✅ |
| libcamera (nuestro parche) | ✅ |
| **conector de PipeWire** (`libspa-libcamera`) | ⛔ **descarta los controles** — cero apariciones de `LensPosition`/`AfMode`/`focus` en el binario |
| Snapshot (pasa por PipeWire) | ⛔ por lo anterior, **y además no tiene interfaz** de enfoque |
| **qcam** (habla con libcamera directamente) | ⛔ **probado: no enfoca y no está adaptado a móvil** |

📌 **La vía «una app que hable con libcamera directamente» está agotada.**

### ⛔ SENSOR FRONTAL — hipótesis CERRADAS CON DATOS (2026-08-07), sigue sin enlace

**Medido en vivo, con el sensor «emitiendo»** (leyendo sus registros por I2C, bus 13 @0x10):

```
CHIPID        (0x0000) = 0x3142   → responde
MODE_SELECT   (0x0100) = 0x01     → EL SENSOR CREE QUE ESTÁ EMITIENDO
CSI_LANE_MODE (0x0114) = 0x03     → 4 carriles
SIGNALING     (0x0111) = 0x02     → CSI-2 D-PHY  (NO es C-PHY)
```

| hipótesis | veredicto |
|---|---|
| ¿Es C-PHY, como la trasera? | ⛔ **NO** — el propio sensor dice D-PHY |
| ¿Está emitiendo? | ✅ sí, según su registro de modo |
| ¿Coincide el nº de carriles? | ✅ 4 en sensor y receptor |
| ¿La asignación física de carriles? | ✅ `laneAssign = 0x3210` en el blob = `data-lanes = <0 1 2 3>` |
| ¿La polaridad del multiplexor? | ✅ el blob pone `STANDBY=0`; el driver también |
| ¿La configuración del PHY? | ✅ `CTRL0=0x02`, `CTRL5=0xD5` — **idénticos** a la D-PHY que funciona en eut2 |
| ¿El CSID? | ✅ `RX_CFG0 = 0x132103` → 4 carriles, `laneAssign 0x3210`, PHY 1, bit C-PHY a 0 |

**Y el resultado, medido con las IRQ enmascaradas** (única forma de que el cero signifique algo):
**SOT = 0, EOT = 0, TOTAL_PKTS = 0, ECC = 0, CRC = 0, MISR de los 4 carriles = 0.**

### Dos hallazgos nuevos

1. **El I2C del frontal falla de forma intermitente**: unas veces no sondea (`failed to find
   sensor: -5`) y otras no acepta su configuración al arrancar el flujo (`fail to write init
   registers`). Se cura reintentando. ⚠️**Y cuando falla el sondeo, `camss` —que espera a TODOS los
   sensores del árbol— deja el grafo sin enlaces y libcamera NO VE NINGUNA cámara**: el síntoma no
   apunta al culpable. Cura: `modprobe -r s5k3t2 && modprobe s5k3t2`.
2. **La línea del multiplexor se llama en la placa `CAM_SW2_OE_2`** («habilitación de salida» del
   conmutador 2), y fábrica la etiqueta como **`CAM_SEL`**, apuntada por `gpio-standby`.

### ⚠️ Una conclusión antigua del expediente queda EN DUDA

Se dio por bueno que `camera_mipi_switch_en` debía estar **apagado** porque «al forzarlo encendido
csiphy1 no veía nada». Pero **tampoco ve nada apagado**: comparar «nada» con «nada» no decide. Y
aquella medida es anterior a saber que **hay que enmascarar las IRQ** o toda lectura es una muestra
al azar. **Reprobarlo bien es el siguiente experimento** (exige tocar el DT y reiniciar).

### Lo que eut2 NO puede enseñarnos

Su cámara frontal declara **`gpio-no-mux`**: no pasa por ningún conmutador. La de surya sí. **El
multiplexor es la diferencia estructural entre el caso que funciona y el nuestro**, y es
precisamente lo que eut2 no tiene.

⚠️ Y comparar las **tablas de sintonía** del PHY contra eut2 **no es evidencia válida**: es otro SoC
(SM7325) y esas tablas son específicas de cada uno. La referencia buena es el kernel de fábrica de
**surya**, contra el que ya se verificó byte a byte en julio.

## ★ EL SIGUIENTE PASO: AUTOENFOQUE (plan, 2026-08-07)

**Por qué es el objetivo correcto y no el enfoque manual**: un deslizador manual en un móvil no lo
quiere nadie; y sobre todo, **el autoenfoque ocurre DENTRO de libcamera**, así que **no necesita
que PipeWire reenvíe controles ni que la app tenga interfaz**. Todas las apps se benefician sin
tocar ninguna. Es lo que salta por encima del muro de la tabla de arriba.

**Estado de partida medido**: `SwIspStats` (`include/libcamera/internal/software_isp/swisp_stats.h`)
tiene **`valid`, `sum_` (RGB) y `yHistogram`** — **ninguna medida de nitidez**. El IPA por software
solo trae `Agc`, `Awb`, `BlackLevel` y `Ccm`.

**Las cuatro piezas**:

1. **Medida de nitidez en el ISP** — añadir un acumulador a `SwIspStats` y calcularlo en
   `src/libcamera/software_isp/swstats_cpu.cpp`, donde ya se recorren los píxeles para el
   histograma: suma de |diferencia| entre vecinos en una ventana central. Barato.
2. **Algoritmo en el IPA** (`src/ipa/simple/algorithms/`) — escalada de colina sobre esa medida:
   mover, medir, quedarse con el pico. Es literalmente el barrido que se hizo a mano.
3. **Camino para mover la lente desde el IPA** — hoy el IPA solo manda controles al sensor por
   `setSensorControls`. Lo más corto: **desviar `V4L2_CID_FOCUS_ABSOLUTE` a la lente** dentro de
   `SimpleCameraData::setSensorControls()`, que es como lo resuelve el manejador de IPU3.
4. Compilar (receta en `packages/libcamera/README.md`), desplegar y probar con escenas a **varias
   distancias**.

📌 **Versión mínima recomendada para empezar**: enfoque de **una sola pasada al arrancar** la
cámara en vez de continuo. Misma fontanería, algoritmo trivial, y ya da el 80 % del valor —fotos
enfocadas— sin el riesgo de un lazo que persiga escenas cambiantes.

⚠️ Al medir, recordar las trampas ya pagadas: **paso de fila** (`bytesused/alto`), **escena quieta
y exposición fija** (si no, se mide ruido o brillo), y **volver a arrancar `wireplumber`** al
terminar o el Bluetooth deja de conectar.

### ⛔ Enfoque EN LAS APPS: el análisis previo (2026-08-07)

| capa | estado |
|---|---|
| Motor + driver en el kernel | ✅ |
| libcamera **encuentra** la lente | ✅ (`'dw9807 12-000c': Control: Focus, Absolute`) |
| libcamera **define** `LensPosition`, `AfMode`, `FocusFoM`… | ✅ |
| El manejador **simple** los expone a las apps | ⛔ **aquí se corta** |
| Algoritmo de autoenfoque en el ISP software | ⛔ no existe (solo `Agc`, `Awb`, `BlackLevel`, `Ccm`) |

⚠️ `media-ctl` muestra la lente con **«0 link»** y **eso no significa que falte el enlace
auxiliar**: los enlaces auxiliares no tienen pads y esa herramienta no los ve. Comprobarlo con
`LIBCAMERA_LOG_LEVELS=*:DEBUG cam -l | grep -i lens`.

**Plan para la próxima sesión** (fuentes ya descargadas; receta en
`pmaports/temp/libcamera/`, que además **ya trae ficheros de calibración de sensores**, el otro
hueco pendiente):

1. En `src/libcamera/pipeline/simple/simple.cpp` —que hoy **no menciona la lente ni una vez**—
   publicar `controls::LensPosition` y `AfMode` (solo `AfModeManual`) cuando
   `sensor_->focusLens()` exista, y encaminarlos a `CameraLens::setFocusPosition()`.
2. ⚠️ **Decisión de diseño pendiente**: `LensPosition` se define **en dioptrías**, no en unidades
   del motor. Hacerlo bien exige calibración que no tenemos; habrá que documentar la conversión
   que se elija.
3. Autoenfoque, después: hace falta una **medida de nitidez** en el ISP software (hoy solo produce
   histograma) y el algoritmo de escalada en el IPA.

⚠️ **NO copiar de otro manejador**: en 0.7.1 **solo el de Raspberry Pi** expone estos controles a
las aplicaciones. El de IPU3 mueve la lente **internamente** desde su IPA con el control crudo de
V4L2, sin publicarlo. Esto es escribir la función, no portarla.

### ⛔ Megapixels: no sirve — asume un alineamiento de fila que este SoC no usa

`megapixels` + `libmegapixels` **sí traen interfaz de enfoque** (botones de automático y manual) y
conocen `FOCUS_ABSOLUTE`/`FOCUS_AUTO`. Se le escribió configuración para surya
(`/etc/megapixels/config/xiaomi,surya.conf`, copiada de `google,b4s4-sdm670.conf` — un Pixel 3a,
que usa **el mismo camss**) y **captura bien por línea de órdenes** (`megapixels-getframe`).

**Pero la app aborta al abrirse**:

```
Assertion failed: bytesused == (width_to_bytes(fmt,w) + width_to_padding(fmt,w)) * height
```

Preguntado a la propia biblioteca por ctypes: espera **5784** bytes por fila (redondea a múltiplo
de **8**) y el driver entrega **5792** (múltiplo de **16**). El 16 **lo exige el hardware**:
`vfe_bpl_align()` de mainline devuelve 16 para SM7150 y para todos los camss modernos, y 8 solo
para los antiguos. 📌 La configuración del Pixel 3a funciona **por casualidad**: su ancho 4032 da
5040 bytes/fila, múltiplo de 8 **y** de 16. El nuestro, 4624, da 5780: de ninguno de los dos.

Es un **fallo de megapixels** (debería usar el `bytesperline` que publica el driver — su propia
herramienta ya lo imprime bien: `stride 5792`). Descartado recortar a 4608 para hacer coincidir los
números: sería deformar el driver para tapar un fallo ajeno, y costaría 16 columnas.

### ★ ENFOQUE: el intento con el driver equivocado (2026-08-06, parche 0114)

**Lo que quedó hecho y verificado**: el motor está en el árbol (`camera-lens@c`,
`compatible = "dongwoon,dw9714"`), el driver carga, aparece en el grafo como subdispositivo de
tipo **Lens** y expone **`focus_absolute` (0–1023)**. Se activó `CONFIG_VIDEO_DW9714=m` — comprobado
que **no altera el kernel** (misma suma de `vmlinuz.efi` antes y después).

**★ El agujero real que se tapó**: el regulador `uw_ldo_ois_drv`, que alimenta la bobina, **estaba
descrito en el árbol pero sin ningún consumidor** (`num_users=0`, `disabled`). Ahora el nodo de la
lente lo pide con `vcc-supply` y pasa a `enabled` al abrir el dispositivo. Antes el chip
**aceptaba todas las órdenes y no tenía corriente en la bobina**.

**Lo que NO funciona**: la lente no se mueve. Descartado con la app abierta y el usuario mirando
la vista previa en directo, alternando extremos seis veces:

| protocolo probado | resultado |
|---|---|
| **Dongwoon** (16 bits sueltos, `(pos<<4)\|S`) | sin cambio |
| **AK7375** (registro `0x00`, 12 bits; `0x02=0x00` modo activo) | sin cambio |

Y con todas las precondiciones **comprobadas una a una**: rail `enabled` con `num_users=1`,
escrituras I2C con `rc=0`, control aplicado (relectura correcta), subdispositivo mantenido abierto,
y `64M_AF_EN` (tlmm 66) en alto —lo pone `imx682` como *standby* al encender—.

**Hipótesis que quedan** (ninguna se resuelve probando protocolos a ciegas):
1. Falta **otra habilitación de placa**, o importa el **orden de encendido**.
2. **Lo que contesta en `0x0c` no es el actuador**: el `ACK` del bus solo dice que alguien vive en
   esa dirección, no que entienda lo que se le manda.

📌 **Siguiente paso propuesto**: mirar **qué escribe exactamente la pila de fábrica al arrancar el
enfoque**, igual que se hizo con el sensor —comparar contra fábrica fue lo que destapó el C-PHY—.
El actuador **no tiene blob propio** en `/mnt/vendor/lib/camera` (38 ficheros, ninguno de
actuador), así que habría que mirarlo en `camera.qcom.so` o en el kernel de fábrica del `boot.img`.

⚠️ **DEPENDENCIA NUEVA**: con `lens-focus` en el DT, **el sensor espera al módulo de la lente**.
Si `dw9714` no está cargado, `imx682` se queda pendiente y **la cámara no aparece**. Orden de
carga: `dw9714` → `qcom_camss` → `imx682` → `s5k3t2`.

⚠️⚠️ **TRAMPA DEL DRIVER**: `dw9714` ata la energía a la **apertura del subdispositivo** y su
suspensión **devuelve la lente a 0** antes de cortar. Un `v4l2-ctl --set-ctrl` suelto coloca la
lente y la deshace al salir → hay que **mantener el nodo abierto** (`exec 3<> /dev/v4l-subdevN`)
mientras se mide, o las N posiciones del barrido son en realidad la misma.

### Brillo, contraste, enfoque y zoom — qué hay y qué falta (medido 2026-08-06)

- **Contraste y gamma: ya existen.** `cam -c 1 --list-controls` da `Contrast` (0–2) y `Gamma`
  (0,1–10). **Brillo y saturación no**: el ISP por software solo trae `Agc`, `Awb`, `BlackLevel`
  y `Ccm` (comprobado en `ipa_soft_simple.so`).
- **★ Enfoque manual: el motor ESTÁ y responde.** Con la cámara encendida, `i2cdetect` en el bus
  del sensor (i2c-12) muestra **`0x0c`** junto al sensor (`1a`) y la EEPROM (`50`), y una lectura
  devuelve `0x07 0x00`. ⚠️**solo contesta con la cámara alimentada**; apagada, la lectura expira
  (no concluir «no está» de un fallo con la cámara apagada).
  **Identificación**: responde a una lectura de 16 bits **sin índice de registro** → familia
  **Dongwoon DW9714/DW9800**, no DW9807 ni AK7375, que exigen registro. Interpretado como DW9714,
  `0x0700` es la posición de reposo 112 de 1023. La pila de fábrica menciona los cuatro candidatos
  (`dw9800`, `dw9714`, `ak7374`, `lc89821`), así que **no** desempata: lo hace el protocolo.
  **Qué falta**: el kernel trae `dw9714`, `dw9768`, `dw9807-vcm`, `ak7375` y `dw9719` en el árbol
  pero **ninguno activado** en el `.config`; hay que activarlo, añadir el nodo al DT y engancharlo
  al sensor. Después libcamera publica `LensPosition`.
- **Autoenfoque: no existe algoritmo.** `Af` no está en el IPA por software — libcamera *conoce*
  los controles (`AfMode`, `AfState`, `LensPosition`…) pero nadie los calcula por este camino.
  Habría que escribirlo (detección por contraste sobre las estadísticas que ya calcula) o hacerlo
  en la app.
- **Zoom: la vía buena son los modos del sensor.** Nuestro driver expone **un solo modo**
  (4624×3472) y el blob de fábrica trae **cinco tablas de modo**. Añadirlos daría zoom por recorte
  en el propio sensor —sin perder resolución— y de paso modos más ligeros, que 16 megapíxeles por
  ISP software van justos. Recortar la imagen ya revelada es la vía mala, y hoy libcamera ni
  siquiera expone `ScalerCrop` aquí.

## Verificación

```
5 fotogramas de 20 109 824 bytes · 199 829 bytes no nulos de cada 200 000
```

Decodificando RAW10 y muestreando 1 de cada 8 filas y columnas:

| | mín | máx | media | desv | correlación con el vecino |
|---|---|---|---|---|---|
| ganancia 0 (por defecto) | 16 | 57 | 32,1 | 10,9 | **0,996** |
| ganancia 978 (máxima) | 19 | **255** | **202,8** | 84,2 | **0,997** |

- **Correlación con el píxel vecino 0,996**, frente a **0,003** entre píxeles al azar: hay
  estructura espacial. Es una imagen, no ruido ni un patrón atascado.
- Subir la ganancia lleva la imagen a **todo el rango dinámico**: la cadena responde a los
  controles. Eso valida el camino completo — I2C → sensor → enlace C-PHY → CSIPHY → CSID → VFE →
  DMA → espacio de usuario.

⚠️ La `analogue_gain` arranca en **0** (mínimo de 0..978) y la exposición ya viene casi al máximo
(3480 de 3506). Sin exposición automática, la primera captura sale muy oscura y **parece que no
funciona**. No es un fallo.

## Lo que faltaba, y por qué costó tanto verlo

El registro `0x0111` del sensor (`CSI_SIGNALING_MODE` del estándar MIPI CCS) vale **0x03 =
CSI-2 C-PHY**, y lo escriben **tanto el blob de fábrica como nuestro driver**. Se copió fielmente
sin mirar qué significaba.

Durante meses se verificó que nuestra configuración fuera **idéntica a la de fábrica** —sensor,
CSIPHY y CSID, registro a registro— y lo era. Lo que nunca se cuestionó fue **el receptor**.

⚠️⚠️ **LA LECCIÓN**: que una comprobación salga **idéntica a fábrica no prueba que sea
correcta**, solo que coincide.

## El sensor FRONTAL (S5K3T2): es D-PHY, y sigue sin enlace

Comprobado el 2026-08-07: **no es C-PHY**, así que lo del trasero no le aplica.

- Su blob de fábrica **no escribe `0x0111`** (deja el valor por defecto, D-PHY).
- `laneAssign = 0x3210` y `CSI_LANE_MODE = 0x03` → **4 carriles**. El CSIPHY de Qualcomm admite
  como mucho **3 tríos** en C-PHY, así que cuatro carriles solo caben en D-PHY.
- Su endpoint del DT ya declara `clock-lanes`, que solo existe en D-PHY. **Sin cambios**.

O sea que este móvil lleva **los dos tipos de enlace a la vez**: trasero C-PHY con 3 tríos y
frontal D-PHY con 4 carriles más reloj. El soporte añadido convive bien porque el tipo se decide
por endpoint.

**Estado tras arreglar los relojes del VFE1 (parche 0111)**: `STREAMON` ya no da error, los
bloques responden (`VFE:1 HW Version = 1.3.0`, `CSID:1 HW Version = 2.0.0`) y el formato encaja
en toda la cadena. Pero **no llega ningún fotograma**:

```
CSIPHY1 CTRL5 = 0xD5      -> 4 carriles D-PHY + reloj   (correcto)
CSID1   CFG0  = 0x132103  -> 4 carriles, laneAssign 0x3210, phy 1  (correcto)
SOT = 0000   EOT = 0000   PAQUETES = 0   CRC = 0
```

Configuración correcta y **ni un SOT**: el mismo cuadro que tenía el trasero, pero con otra causa,
porque este sí es D-PHY. **Aparcado a propósito** para terminar primero el trasero.

### ★ Cómo atacarlo cuando se retome: ya tenemos la referencia archivada

En `eut2-sm7325/volcado-camara-funcionando.txt` hay **siete volcados del banco de registros del
CSIPHY** tomados con la cámara funcionando, y uno de ellos es de **`CSIPHY_IDX: 0` con
`Datarate: 245760000`** — el **IMX471 frontal**. A esa velocidad, y siendo un Sony frontal, es
D-PHY casi con seguridad (el trasero IMX766 va a 1,93 Gbps y es C-PHY, con `CTRL5 = 0x2a`).

Es decir: **tenemos guardada la configuración de un enlace D-PHY que SÍ engancha**, en el mismo
IP de cámara y las mismas direcciones que surya. Comparar el banco de ese volcado contra lo que
programa mainline en el `csiphy1` de surya es la misma jugada que resolvió el trasero, y **no
hace falta volver a tocar eut2**.

Primer paso al retomar: confirmar en el volcado que el `CTRL5` de ese PHY usa la codificación
D-PHY (bits pares + bit 7), y a partir de ahí diferencia a diferencia.

⚠️ Recordar la limitación: esos volcados se toman **2-3 ms antes** de arrancar el PHY, así que
valen como **configuración de referencia**, no como estado de un enlace en marcha.

⚠️ Trampa de la sesión: el fourcc de `SGRBG10` empaquetado es **`pgAA`** (g minúscula); `pGAA` es
`SGBRG10P`, otro patrón de Bayer, y da `format mismatch` sin decir por qué.

## Pendiente

✅ ~~La app de cámara~~ · ✅ ~~Exposición automática~~ · ✅ ~~Comprobar si el frontal es C-PHY~~
(no lo es, es D-PHY — ver su sección).

✅ ~~La imagen sale girada~~ (0112, verificada con 4 fotos y un vídeo).

Lo que queda, en orden de valor (**el usuario prefiere el enfoque antes que el zoom**):

1. **★ Enfoque: integrado pero la lente NO SE MUEVE** — ver la sección propia más abajo. Es lo
   siguiente a atacar.
2. **Autoenfoque** — hay que escribir el algoritmo, no existe en el ISP por software. Depende de
   que el punto 1 funcione.
3. **Modos del sensor** — hoy hay uno solo; fábrica tiene cinco. Da **zoom real** por recorte en
   el sensor y modos más ligeros. El material de fábrica ya está extraído.
4. **Calidad de imagen** — el ISP corre sin calibrar para el IMX682. Tres piezas, todas en
   espacio de usuario:
   - **`CameraSensorHelper` para `imx682` en libcamera** (`IPASoft: Failed to create camera
     sensor helper for imx682`). Sin él, el automático no sabe convertir código de ganancia a
     ganancia real y **converge muy despacio** (llegó a 13 de 978 tras 2352 fotogramas). Los
     sensores Sony usan `ganancia = 1024 / (1024 − código)`; el tope de 978 da 22,26× — encaja,
     pero **hay que medirlo antes de darlo por bueno**.
   - **Fichero de calibración `imx682.yaml`** (hoy cae en `uncalibrated.yaml`): color y viñeteo.
   - **Enfoque**: el módulo lleva motor de bobina y nadie lo mueve; la lente está en reposo.
5. **Hueco del driver que libcamera sigue reportando**: sin rectángulos de selección (`CROP`,
   `CROP_DEFAULT`, `CROP_BOUNDS`, `NATIVE_SIZE`) → *«The sensor kernel driver needs to be fixed»*.
   Falta `.get_selection`. (La orientación y la rotación ya están, parche 0112.)
6. **El sensor frontal S5K3T2** — es D-PHY y sigue sin enlace (ver su sección).
7. **Los módulos siguen en lista negra** al arrancar: la cámara tumba el móvil si carga temprano.
   Mientras sigan ahí, tras cada arranque hay que cargarlos a mano **y reiniciar `wireplumber`**
   para que las cámaras aparezcan en PipeWire.

---


# ★★★★ 2026-08-07 — LA CAUSA: el sensor va en C-PHY y el receptor está en D-PHY

**Idea del usuario**: «¿seguro que surya usa D-PHY? ¿No debería usar C-PHY, siendo casi el mismo
chip que eut2?». Comprobado, y es eso.

## La evidencia

El registro **`0x0111`** del sensor es `CSI_SIGNALING_MODE` del estándar MIPI CCS. Sus valores los
define el propio kernel, en el driver CCS (`drivers/media/i2c/ccs/ccs-regs.h`):

```c
#define CCS_R_CSI_SIGNALING_MODE            CCI_REG8(0x0111)
#define CCS_CSI_SIGNALING_MODE_CSI_2_DPHY     2U
#define CCS_CSI_SIGNALING_MODE_CSI_2_CPHY     3U
```

**El blob de fábrica escribe `0x0111 = 0x03` — C-PHY.** Y nuestro `imx682.c` escribe exactamente
lo mismo (línea 199 de `imx682_init_regs`). Los dos ponen el sensor en **C-PHY**.

**Pero el receptor está configurado como D-PHY:**

- El árbol de dispositivos de surya **no declara `bus-type`**, así que `v4l2_fwnode` asume D-PHY.
- Declara **`clock-lanes = <7>`**, que solo tiene sentido en D-PHY (C-PHY no tiene carril de reloj:
  va embebido en cada trío).
- `camss-csiphy` de mainline **no tiene soporte C-PHY**: cero apariciones en todo el driver.
- Medido en el móvil: `CTRL5 = 0x95` = bits pares + bit 7 (reloj) = **codificación D-PHY**.
  En eut2, con el IMX766 funcionando: `CTRL5 = 0x2a` = bits impares = **codificación C-PHY**.

## ★ CONFIRMADO EN EL HARDWARE (no solo en las tablas)

Leído del sensor por I2C, con el sensor **encendido y emitiendo**
(`i2ctransfer -f -y 12 w2@0x1a 0x01 0x11 r1`):

```
CHIPID (0x0016/17)              = 0x06 0x82   <- IMX682: valida que la lectura es buena
CSI_SIGNALING_MODE (0x0111)     = 0x03        <- CSI-2 C-PHY
CSI_LANE_MODE      (0x0114)     = 0x02        <- 3 carriles = 3 TRIOS
```

La lectura del identificador del chip funciona como control: el `0x03` es un valor real del
hardware, no una suposición. **El sensor está en C-PHY.**

⚠️ Para leerlo hace falta `-f` (el driver tiene la dirección tomada) **y el sensor encendido**:
sin captura en marcha, la transferencia expira.

## Por qué explica TODO el expediente

| observación | explicación |
|---|---|
| ni un SOT, nunca (medido con control positivo) | un receptor D-PHY no sincroniza con señalización C-PHY |
| cero CRC y cero ECC | nada llega a reconocerse como paquete: no hay nada que verificar |
| el CSIPHY ve actividad eléctrica solo mientras el sensor emite | los tríos C-PHY **sí** transmiten |
| bits de error en los «carriles 1 y 2» | el receptor D-PHY interpreta transiciones que no entiende |
| el «carril 0» mudo, igual que el 3 sin cablear | los tríos C-PHY no se corresponden con los pares D-PHY |
| el TPG del CSID funciona | no pasa por el PHY |
| sensor, CSIPHY y CSID «idénticos a fábrica» | se copió fielmente la configuración del **sensor**, incluido su modo C-PHY; **el receptor nunca se cuestionó** |
| `settle_cnt` inútil en toda la ventana | la ventana `T_HS_SETTLE` es un parámetro **de D-PHY** |
| 3 carriles, y el 4º sin usar | son **3 tríos C-PHY**, no 3 carriles de datos + reloj |

También encaja `laneAssign = 0x0210` (3 «carriles» = 3 tríos) y `CSI_LANE_MODE 0x0114 = 0x02`.

## Qué haría falta

1. **Declarar C-PHY en el árbol de dispositivos**: `bus-type = <4>`
   (`V4L2_FWNODE_BUS_TYPE_CSI2_CPHY`), quitar `clock-lanes`, y ajustar `data-lanes` a los tríos.
2. **Soporte C-PHY en `camss-csiphy`**, que hoy no existe. Hay una serie RFC upstream
   («media: camss: Add support for C-PHY configuration on Qualcomm platforms») que sería el punto
   de partida.
3. **El CSID también lo necesita**: `CSI2_RX_CFG0` tiene el bit 24 (`PHY_TYPE_SEL`) para C-PHY, y
   mainline **nunca lo escribe** — lo deja siempre a 0 = D-PHY. El driver de fábrica sí lo pone:
   `(lane_type & 0x1) << 24`.

## La prueba rápida: hecha, negativa y NO concluyente (como estaba previsto)

Con la captura en marcha se forzó por `/dev/mem`:

```
CSIPHY0 CTRL5 (0xace0814): 0x95 -> 0x2a      (tres tríos, bits impares)
CSID0   CFG0  (0xacb3100): 0x2102 -> 0x01002102   (bit 24 = C-PHY)
```

Las escrituras entraron, y **nada cambió**: cero SOT, cero paquetes, cero CRC.

Era el resultado anticipado. Cambiar la codificación de carriles y el bit de tipo del CSID no
basta, porque **la sintonía analógica del PHY sigue siendo la de D-PHY**: C-PHY usa otro conjunto
de registros (`csiphy_3ph_reg` en fábrica, frente al 2ph que programa mainline), y además el
bloque probablemente necesita reinicializarse para cambiar de modo. Un negativo aquí **no refuta
la hipótesis**; y la hipótesis ya no lo necesita, porque está confirmada leyendo el sensor.

## Prueba rápida antes de implementar nada

Con la captura en marcha, forzar por `/dev/mem` la configuración C-PHY y leer los bits de SOT:

- `CSIPHY0 CTRL5` (`0xace0814`) = **`0x2a`** (tres tríos, bits impares, sin bit de reloj)
- `CSID0 CSI2_RX_CFG0` (`0xacb3100`) = poner el **bit 24**

Si aparece un solo SOT, queda demostrado.

⚠️ Aviso: los valores de sintonía del PHY para C-PHY son **otro conjunto de registros**
(`csiphy_3ph_reg` en fábrica frente al 2ph que programa mainline), así que la prueba rápida
puede no bastar. Un resultado negativo **no** refutaría la hipótesis; uno positivo la demostraría.

---
# Cámara de surya — estado y hallazgos

Estado: **en curso**. **Dos sensores emiten** (principal y frontal) y todo el SoC está
configurado correctamente, pero **ningún CSIPHY entrega un solo paquete al CSID**. El
experimento de control (§ más abajo) demuestra que **el fallo es de camss**, no nuestro.

Plan y datos completos en [`../PENDIENTES.md`](../PENDIENTES.md) §1.

## Resumen de una línea
El CAMSS de sm7150 ya está en mainline; faltaban los drivers (**WL2866D** ✅, **IMX682** ✅ y
**S5K3T2** ✅, los tres escritos y con los sensores emitiendo). Lo que queda es que **el CSIPHY
enganche** — y eso ya está demostrado que es cosa de camss.

---

## ★★★ EL EXPERIMENTO DE CONTROL — hecho, y concluyente (2026-07-17)

Se escribió el driver de la **cámara frontal** (S5K3T2, parches 0044/0045) precisamente para
aislar el fallo. Resultado:

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

**Dos sensores de fabricantes distintos, en dos CSIPHY distintos, con buses, carriles,
frecuencias de enlace, relojes y alimentaciones distintas → fallo idéntico.** Y el **TPG del
CSID**, que usa el mismo CSID/VFE/DMA pero **no pasa por el CSIPHY**, sí captura 3 frames.

→ **El fallo está en el soporte de CSIPHY de camss para sm7150.** No es nuestra configuración,
ni un sensor concreto, ni csiphy0 en particular.

## ★★ El multiplexor MIPI — CARACTERIZADO (ya no se supone nada)

- **`pm6150_gpios 3` (`CAM_SEL`)** elige quién conduce **csiphy1**: **0 → frontal (S5K3T2)**,
  **1 → ultra angular (HI1337)**. **Confirmado con datos**: los blobs de los dos sensores ponen
  ese pin (que la secuencia de encendido llama `STANDBY`, y el DT de fábrica mapea con
  `gpio-standby = <0x02>` → el 3er gpio del nodo) en valores **opuestos**.
- **`camera_mipi_switch_en` (`pm6150_gpios 2`) debe quedarse APAGADO.** Con él forzado a on (un
  `/* PRUEBA */` heredado en `kernel-build`) **csiphy1 no ve absolutamente nada** de la frontal;
  al apagarlo, los registros por carril del PHY reaccionan al sensor. En el DT de fábrica **no lo
  referencia ningún sensor**.
- **La principal no pasa por el mux**: en el DT de fábrica solo los sensores de csiphy1 llevan
  `CAM_SEL`. Probado además: apagar el mux no cambia nada en csiphy0.







## ★★★ 2026-08-07 — CONTESTADA la pregunta de julio: esos bits son ERRORES

La dicotomía abierta desde el 2026-07-17 —*«si los bits son errores → el carril 0 recibe limpio;
si son actividad detectada → el carril 0 no recibe nada»*— queda resuelta comparando con **eut2**
(Nothing Phone 1, SM7325), que tiene **el mismo IP de cámara en las mismas direcciones**
(CSID0 `0x0acb3000`, CSIPHY0 `0x0ace0000`, `csiphy-v1.2.1` frente a `v1.2`) y un enlace que **sí
funciona**.

No hizo falta leer registros —`/dev/mem` no existe allí y `debugfs` no está compilado—: basta
`/proc/interrupts`, donde las interrupciones del CSIPHY están registradas con su número de GIC.

**Medida, con precondición verificada** (3 arranques del PHY desde el reinicio, sensores IMX471 e
IMX766 emitiendo):

| | interrupciones del CSIPHY |
|---|---|
| **eut2, enlace funcionando** | **1 y 2** por sesión (arranque y parada) |
| **surya, enlace roto** | **~280 000 por segundo** (medido en julio: el ISR limpia sin parar) |

**Cinco órdenes de magnitud.** Un CSIPHY sano está callado. Una tormenta continua es un
subsistema gritando. → **los bits del banco de estado son ERRORES.**

⚠️ Salvedad: eut2 usa **C-PHY** y surya **D-PHY**. El argumento se apoya en la **magnitud**
—silencio frente a tormenta—, que es robusta a esa diferencia, no en el significado de un bit
concreto.

### Lo que cambia en la interpretación

Con la semántica fijada, la anomalía central se lee al revés de como la dejó julio:

- **Carriles 1 y 2**: producen bits → **reciben algo, y con errores**.
- **Carril 0**: no produce ninguno, **igual que el carril 3, que no está cableado**.

La lectura de julio decía «si son errores, el carril 0 recibe limpio». **No se sostiene**: un
carril que recibiera limpio, en un enlace donde no llega ni un SOT, no tiene sentido. La lectura
coherente es que **el carril 0 no recibe nada en absoluto**.

Y eso encaja con todo lo demás: un flujo de 3 carriles al que le falta uno no puede sincronizar,
así que no hay SOT, no hay paquetes y no hay errores de CRC — porque nunca llega a montarse nada
que verificar.

⚠️ **Cuidado con una afirmación heredada**: el expediente repite que «el carril 0 **lleva
señal**». Eso nunca se midió — sale de `laneAssign = 0x0210` del blob, que es **configuración**,
no una medida. Con la semántica de los bits ya fijada, la evidencia apunta justo a lo contrario.

### Dónde deja esto el caso

La pregunta ya no es «por qué no engancha el enlace» sino **«por qué el carril 0 no entrega
nada»**, que es mucho más concreta y tiene tres candidatos:

1. El sensor no transmite por ese carril (configuración de `laneAssign` del sensor).
2. El carril está mal enrutado en la placa respecto a lo que cree el PHY.
3. El carril está físicamente muerto en esta unidad.

Las tres se distinguen con la instrumentación física ya descrita, y ahora con una pregunta mucho
más afilada que antes: basta mirar **si hay actividad eléctrica en el carril 0**.

---
## ★★ 2026-08-06 — barrido del settle y comparación del SENSOR contra fábrica

### El `settle_cnt`: barrido de toda la ventana MIPI, negativo

`csiphy_settle_cnt_calc()` toma `T_HS_SETTLE = t_hs_prepare_max = 85 ns + 6·UI`, que es el
**borde inferior** de la ventana que permite la norma D-PHY (tabla 14: min `85 ns + 6·UI`, max
`145 ns + 10·UI`, con la regla de que el receptor debe ignorar transiciones antes del mínimo y
responder después del máximo). Para el IMX682 aquí (UI 524 ps, timer 300 MHz) esa ventana es
`settle_cnt` **20..39**, y la fórmula cae en **20**, justo en el fondo.

Hipótesis razonable: en el borde, si la fase de preparación real del transmisor se alarga un
poco, el receptor muestrea mientras el sensor aún prepara y no sincroniza nunca.

**Refutada.** Barrido con el parámetro `settle_cnt_override` (parche 0109) en 20, 22, 24, 26, 28,
29, 30, 32, 34, 36, 38 y 39, con la captura verificada emitiendo en cada uno:

```
settle=20 … 39   SOT=0000   EOT=0000   PKTS=0
```

Ni un SOT en todo el rango legal. **Queda descartado el último parámetro de software que gobierna
la negociación LP→HS.**

### El sensor, comparado con fábrica registro a registro

El blob del vendor (`/vendor/lib/camera/com.qti.sensormodule.*imx682*.bin`) contiene las tablas
de modo reales. Volcadas con `dump-sensormodule-regs.py` (extiende `parse-sensormodule.py` con
`VOLCAR=fichero`), dan **5 modos**: 9248×6944, **4624×3472**, 3840×2160, 2312×1304 y 1920×1080.

⚠️ Comparar contra la unión de las cinco tablas **induce a error**: mezcla modos y aparecen 43
«diferencias» que solo son resoluciones y PLL distintos. Hay que comparar contra la tabla del
**mismo modo**.

Comparación justa, tabla de fábrica 4624×3472 frente a nuestro driver:

```
registros que fabrica escribe y nosotros NO : 0
mismo registro con valor distinto           : 0
```

**Coincidencia total.** Los 73 registros del modo de fábrica están íntegramente en lo que escribe
nuestro driver, con los mismos valores. (Nuestro driver escribe además una tabla de inicialización
mucho mayor, 544 registros; fábrica se apoya más en los valores por defecto del sensor.)

**Y ninguna de las dos partes escribe nada en `0x0800-0x08ff`**, la zona de temporización MIPI del
sensor. No falta ningún registro de PHY del lado del sensor.

### Dónde deja esto el caso

La configuración por software está ahora **verificada fiel a fábrica en los tres bloques**:

| bloque | comparado | resultado |
|---|---|---|
| sensor IMX682 (modo 4624×3472) | 73 registros | idénticos |
| CSIPHY, habilitación de carriles | `0x95` = reloj + 3 carriles | idéntico |
| CSID, `CSI2_RX_CFG0/CFG1` | carriles, `lane_cfg`, `phy_sel`, ECC, MISR | idénticos |
| CSIPHY, `settle_cnt` | ventana MIPI completa | ningún valor funciona |

Y el enlace **nunca arranca**: cero SOT en ningún carril, con control positivo del TPG.

### Sobre la documentación que falta (investigado el 2026-08-06)

- **CSIPHY HPG/HRD de SM7150**: no existe en abierto. Va por CreatePoint con cuenta OEM bajo NDA.
  Es el que resolvería la pregunta de julio —si los bits de estado del CSIPHY son *errores* o
  *actividad detectada*—, que **sigue abierta**: ni mainline ni el kernel de fábrica decodifican
  un solo bit, los dos se limitan a limpiarlos.
- **Hoja de datos del IMX682**: no existe en abierto (Sony, NDA). **Pero no hace falta**: las
  tablas de modo reales están en el blob del vendor, y ya están comparadas.
- **MIPI D-PHY**: solo para miembros de la alianza. Los valores normativos usados aquí
  (`85 ns + 6·UI` … `145 ns + 10·UI`) coinciden con lo que calcula la propia fórmula de mainline.
- **MIPI CSI-2**: solo para miembros. No hace falta: el fallo está **antes** del SOT, y todo lo
  que esa norma describe ocurre después.

---
## ★★★ 2026-08-06 — LOS BITS DE SOT: el CSID no captura ni una transmisión (con CONTROL POSITIVO)

La medida más concluyente del expediente, y **la primera con control positivo**.

Los bits `PHY_DLn_SOT_CAPTURED` del registro de estado del RX (`0x20` sobre la base del CSID,
bits 4-7; EOT en 0-3, CRC en 19, ECC en 20) marcan cuándo el CSID ve el **inicio de una ráfaga de
alta velocidad** en cada carril. Están en la capa que faltaba: entre «el CSIPHY ve actividad
eléctrica» y «el CSID cuenta paquetes».

Método (el robusto del expediente): **enmascarar** las IRQ del RX (`0x24 = 0`) para que el ISR no
borre el latch, limpiar (`0x28 = 0xffffffff`) y dejar acumular.

| | RX_IRQ_STATUS | SOT DL0..3 | EOT DL0..3 | TOTAL_PKTS |
|---|---|---|---|---|
| **sensor real** (captura verificada emitiendo) | `0x00000000` | 0 0 0 0 | 0 0 0 0 | 0 |
| **TPG del CSID** (control positivo, minutos después) | `0x0303C077` | **1 1 1** 0 | **1 1 1** 0 | 258 |

El control enciende los bits **exactamente en los tres carriles activos** del TPG, con el mismo
registro, la misma lectura y el mismo enmascarado. **El método es válido y el cero del sensor es
un cero real.**

### Qué cierra esto

**El CSID no captura ni un solo SOT del sensor.** No es que los paquetes lleguen mal montados:
**no empieza ninguna transmisión**. Queda descartada de raíz toda la rama de «el enlace engancha
pero falla el ensamblado» — nada de framing, canales virtuales, empaquetado ni formatos puede
explicar esto, porque todo eso ocurre después del SOT.

El muro está **antes**: el PHY nunca resuelve el enlace de alta velocidad. Y encaja con la única
señal positiva que había: los bits de estado del CSIPHY se activan solo mientras el sensor emite,
o sea que hay **actividad eléctrica** en los pines, pero nunca llega a convertirse en una
transmisión que el CSID reconozca.

Lo que queda al otro lado de esa frontera —la negociación LP→HS, que ocurre entre el sensor y el
PHY y no deja rastro en ningún contador— es justo lo que solo se ve con instrumentación física
(§ vía física).

---
## ★★ 2026-08-06 — CSID comparado registro a registro con el driver de fábrica

Comparación del bloque **CSI2 RX**, que es donde vive `TOTAL_PKTS_RCVD` (el camino RDI no puede
explicar nuestro síntoma: cuenta lo que se escribe en memoria, no lo que llega).

| campo | fábrica (`cam_ife_csid_core.c`) | mainline (`camss-csid-gen2.c`) |
|---|---|---|
| `CFG0` carriles | `(lane_num - 1) & 0x3` | `lane_cnt - 1` |
| `CFG0` `lane_cfg` | `(lane_cfg & 0xFFFF) << 4` | `lane_assign << 4` |
| `CFG0` `phy_sel` | `(res_type & 0xFF) - 1` → **0** | `csiphy_id` → **0** |
| `CFG0` tipo PHY | `(lane_type & 1) << 24` → 0 (D-PHY) | no lo escribe → 0 |
| `CFG1` | ECC + MISR (+ VC si vc>3) | ECC + MISR (+ VC si vc>3) |

**Coinciden.** El `-1` del `phy_sel`, que parecía una diferencia real, solo deshace el
desplazamiento del TPG (`CAM_ISP_IFE_IN_RES_BASE = 0x4000`, TPG = BASE+0, PHY_0 = BASE+1): para
PHY0 las dos expresiones dan `0`. **Descartado.**

### ★ Lo que sí ha destapado: los bits de SOT por carril

El driver de fábrica habilita interrupciones del RX que mainline no expone:

```c
CSID_CSI2_RX_INFO_PHY_DL0_SOT_CAPTURED ... DL3_SOT_CAPTURED
CSID_CSI2_RX_INFO_PHY_DL0_EOT_CAPTURED ... DL3_EOT_CAPTURED
```
(en fábrica van tras `csid_debug & CSID_DEBUG_ENABLE_SOT_IRQ`)

Un **SOT** es la marca con la que arranca cada ráfaga de alta velocidad. Esos bits caen justo en
**la capa que nos falta**: entre «el CSIPHY ve actividad eléctrica en sus pines» y «el CSID cuenta
paquetes».

- Si el CSID **captura SOT** pero no cuenta paquetes → el enlace HS sí engancha y lo que falla es
  el ensamblado de paquetes. Cambiaría el caso entero.
- Si **no captura ni un SOT** → el PHY nunca entrega símbolos y el muro está antes, confirmando
  todo lo demás.

**Pendiente de medir.** Es barato: son bits de un registro que ya existe
(`csid_csi2_rx_irq_status_addr`, 0x20 sobre la base del CSID). Hace falta sacar sus definiciones
de bit de la cabecera del vendor y leerlos durante una captura, con el mismo cuidado de siempre:
comprobar antes que la captura esté realmente emitiendo.

---
## ★★ 2026-08-06 (tarde) — tres hipótesis probadas con el método del Fairphone 6

Se usó como guía el relato de puesta en marcha de la cámara del Fairphone 6 sobre CAMSS mainline
(<https://nondescriptpointer.com/articles/fairphone-6-wide-camera-linux/>), que llegó a funcionar
y describe sus fallos uno a uno. Tres de sus hallazgos se contrastaron aquí. **Los tres
descartados**, pero cada uno con medida, no con lectura de código.

### 1. Numeración de carriles de base 1 vs base 0 — NO es nuestro caso

En el Fairphone, el árbol de fábrica numeraba `data-lanes = <1 2 3 4>` y mainline los espera de
base cero; al copiarlos, *«CSIPHY programmed a lane mask with lane 0 missing, and the PHY never
locked»* — que es **literalmente nuestro síntoma**.

Comprobado en el árbol **vivo** del móvil (`/proc/device-tree`), no en las notas:

```
camss@ace0000/ports/port@0/endpoint/data-lanes   = 0 1 2      clock-lanes = 7
cci@ac4a000/i2c-bus@0/camera@1a/…/data-lanes     = 0 1 2
```
Ya es de base cero en los dos extremos. **Descartado.**

### 2. Falta un reloj del bus de registros — CONFIRMADO a medias, pero inocuo

El fallo principal del Fairphone: *«reading the TFE hardware-version register returned 0x0, and
reset timed out as if the block were not powered»*, por faltar `CAM_CC_SOC_AHB_CLK`. Nosotros
teníamos **los dos síntomas**.

Y es verdad a medias: en las tablas de sm7150, **`cpas_ahb`, `camnoc_axi_src` y `camnoc_axi` los
pide únicamente el VFE0**, no el CSIPHY ni el CSID. Medido leyendo la versión del CSIPHY por
`/dev/mem` en dos momentos:

| momento | STATUS12..15 | versión |
|---|---|---|
| cargado, **sin** captura (VFE apagado) | 0 0 0 0 | `0x00000000` |
| **durante** la captura (VFE encendido) | 0 0 01 40 | **`0x40010000`** |

Así que el bus de registros del CSIPHY **solo está vivo cuando el VFE enciende sus relojes**, y
de ahí el `CSIPHY 3PH HW Version = 0x00000000` del arranque del pipeline.

### 3. …pero la configuración NO se pierde — DESCARTADO

La consecuencia temida era que la programación del CSIPHY (máscara de carriles, sintonía D-PHY)
se escribiera sobre un bus sin relojar y no llegara nunca. **No ocurre.** Leído durante la
captura:

```
CTRL0 (0x800) = 0x00000002     CTRL5 (0x814) = 0x00000095   <- reloj + 3 carriles, CORRECTO
CTRL6 (0x818) = 0x00000001     CTRL7 (0x81c) = 0x00000002
```

`0x95` es exactamente el valor esperado. La configuración llega y se queda puesta.

**Conclusión**: la lectura de versión a cero es real pero **cosmética** — ocurre en una ventana
en que el bus aún no está relojado, y la configuración de verdad se escribe después. Arreglarlo
(añadir `cpas_ahb`/`camnoc_axi` al CSIPHY) haría el mensaje correcto y sería más limpio, pero
**no es la causa del muro**.

⚠️ Los cuatro «settle count» leídos en `0x?_0e0` salieron a cero, pero **ese offset está
inventado**: no vale como dato hasta verificarlo contra la cabecera del vendor.

---
## ★★ 2026-08-06 — la capa nunca medida, y una REGRESIÓN que la bloquea

### La capa nunca medida: los MISR de los carriles 1, 2 y 3

Toda la conclusión «los datos no cruzan del PHY al CSID» (§ *Dónde está el muro*) descansa en
`MISR = 0`. Ese registro es **`LANE0_MISR` (0x150)** — y **es el único MISR que se ha leído
nunca**, ni con el TPG ni con el sensor.

El CSID tiene **un MISR por carril**, confirmado en la cabecera del vendor
(`cam_ife_csid175_200.h`):

```
csid_csi2_rx_lane0_misr_addr = 0x150     <- el único leído hasta ahora
csid_csi2_rx_lane1_misr_addr = 0x154
csid_csi2_rx_lane2_misr_addr = 0x158
csid_csi2_rx_lane3_misr_addr = 0x15c
```
Con CSID0 en `0xacb3000`: **`0xacb3150`–`0xacb315c`**.

**El problema es que el carril 0 es precisamente el carril anómalo**: el que no produce ningún
bit de estado en el CSIPHY y «se comporta como el carril 3, que ni siquiera está cableado». O
sea que la afirmación más fuerte del expediente se apoya, sin querer, en el único carril del que
ya sabíamos que va mal.

**Si `LANE1_MISR` o `LANE2_MISR` salen no nulos**, el caso cambia entero: los datos *sí* cruzan
del PHY al CSID por 1 y 2, y lo que falla es solo el carril 0. Eso convierte «no hay enlace» en
«falta un carril de tres» — un problema distinto, que explica los 0 paquetes sin necesidad de
ningún fallo eléctrico (un flujo de 3 carriles al que le falta uno no se puede desempaquetar,
pero los otros dos sí estarían clockeando bits).

**Segundo hueco, menor**: en todo el expediente no hay ni una prueba con **distinto número de
carriles**. Si el carril 0 está muerto o mal enrutado, configurar el enlace a 2 carriles es un
experimento de software, barato, y nunca se ha hecho.

### ✅ La medida, HECHA — y la hipótesis REFUTADA (2026-08-06, sesión siguiente)

Con la regresión arreglada (ver abajo) se leyeron **los cuatro MISR** con el sensor emitiendo,
comprobando antes que la captura estuviera realmente en curso (el proceso `v4l2-ctl` vivo más de
8 s sin error: si `STREAMON` falla, sale al instante):

```
TOTAL_PKTS = 0    LANE0_MISR = 0    LANE1_MISR = 0
CRC_ERR    = 0    LANE2_MISR = 0    LANE3_MISR = 0     (a los 4 s y a los 8 s)
```

**No es solo el carril 0: ningún carril clockea un solo bit.** La conclusión original del
expediente —«los datos no cruzan del PHY al CSID»— **era correcta**; lo único que le faltaba era
apoyarse en los cuatro carriles en vez de en el único que ya sabíamos anómalo. Ahora se apoya.

### El segundo hueco, también cerrado: distinto número de carriles

Probado el 2026-08-06 con un parámetro nuevo del driver (`imx682.lane_mode`, parche 0108) que
sobreescribe `CSI_LANE_MODE` (0x0114) después de la tabla de modo, sin tocar el árbol de
dispositivos ni reiniciar. Con la captura **verificada emitiendo** en los tres casos, y con el
override **confirmado en el registro del kernel** (`EXPERIMENT: forcing CSI_LANE_MODE …`):

| sensor | PKTS | ECC | CRC | LANE0..3 MISR |
|---|---|---|---|---|
| 3 carriles (control) | 0 | 0 | 0 | 0 0 0 0 |
| 2 carriles (`0x0114=1`) | 0 | 0 | 0 | 0 0 0 0 |
| 1 carril (`0x0114=0`) | 0 | 0 | 0 | 0 0 0 0 |

**Y esto dice más de lo que parece.** Con menos carriles la temporización del sensor queda mal
—la frecuencia de enlace sigue calculada para tres—, así que el flujo debería llegar deformado, y
un flujo deformado produce **errores de CRC**. Que no haya *ni errores* significa que no llega
nada en absoluto: **el enlace no se establece nunca, con ningún número de carriles**.

Los dos huecos que se abrieron al releer el expediente quedan por tanto cerrados, los dos en
negativo. El muro descrito en 2026-07-17 sigue en pie, y ahora se apoya en tres medidas
independientes en vez de en una.

### ✅ REGRESIÓN — encontrada y ARREGLADA (parche 0107)

**Era un fallo nuestro.** El parche 0080 (*keep the interrupt disabled until the block is
powered*), que arregló el cuelgue al cargar el módulo, puso `enable_irq()` **después** de
`vfe_reset()`. Y `vfe_reset()` **espera una interrupción de reset-hecho**: con la línea aún
deshabilitada solo podía expirar. De ahí el `VFE reset timeout` y el `-EIO` en cada
`VIDIOC_STREAMON`. En su día se verificó que el módulo **cargaba**, pero no se llegó a probar una
captura, y por eso pasó desapercibido.

**El arreglo** (0107) mueve `enable_irq()` **antes** del reset. Sigue cumpliendo lo que la línea
deshabilitada protegía —dominio de potencia encendido, `pm_runtime` resumido y relojes en
marcha— y **coincide con el driver de fábrica**, que arma la interrupción del reset justo antes
de resetear y la desarma después (`cam_vfe_reset()`, `cam_vfe_core.c`). Además deshabilita la
línea en el camino de error, para que un reset fallido no la deje activa mientras se apagan los
relojes.

Verificado: el pipeline enciende, `CSID:0 HW Version = 2.0.0` (antes el CSIPHY devolvía
`0x00000000`), la validación de enlaces pasa y aparece `vfe irq handled!`.

⚠️ **Dos trampas de método, las dos comprobadas:**

1. `camss` **espera a TODOS los sensores del árbol de dispositivos** antes de crear los enlaces.
   Con solo `imx682` el sensor sale con **`0 link`** y `media-ctl -l` falla con *«Unable to parse
   link: Invalid argument»* — parece sintaxis y no lo es. Hay que cargar **también `s5k3t2`**.
2. `modprobe imx682 s5k3t2` **no carga dos módulos**: carga `imx682` pasándole `s5k3t2` como
   parámetro (`imx682: unknown parameter 's5k3t2' ignored`). Un `modprobe` por módulo.

⚠️ **El módulo se compila con clang, no con gcc** (`PATH=…/llvm-shim`, `LLVM=1`): el `.config`
lleva CFI y gcc rechaza `-fsanitize-cfi-icall-experimental-normalize-integers`.

### Historia: cómo se veía la regresión antes de arreglarla

**El pipeline ya no llega a encenderse.** Con los módulos cargados a mano sobre el sistema
asentado (2 h de uptime), `VIDIOC_STREAMON` falla con `-EIO` y el kernel dice:

```
csiphy_reset id 0 with base ... and offset 2048
qcom-camss ace0000.camss: CSIPHY 3PH HW Version = 0x00000000
Writing reset_bits=3f9f to vfe->base=... with id 0
qcom-camss ace0000.camss: VFE reset timeout
qcom-camss ace0000.camss: Failed to power up pipeline: -5
```

Reproducido dos veces seguidas. **Ninguno de los dos mensajes aparece en el resto de este
expediente**: en julio el sensor sí emitía y se llegaba a medir 0 paquetes. Ahora ni siquiera se
enciende el VFE.

Dos observaciones que hay que explicar antes de seguir:

1. **`CSIPHY 3PH HW Version = 0x00000000`** — un bloque alimentado y relojado no debería
   devolver cero al leer su versión.
2. **`VFE reset timeout`** — el VFE no responde al reset, que suele ser reloj o alimentación.

Hipótesis a descartar, por orden de coste: (a) el kernel ha cambiado mucho desde julio —la serie
pasó de ~55 parches a 106, casi todos de audio/Bluetooth— y la cámara **no se ha vuelto a probar
desde entonces**; (b) cargar `camss` a mano con el sistema asentado deja relojes o dominios de
potencia en un estado distinto del que tenían los experimentos de julio.

⚠️ **Trampa nueva, comprobada**: `camss` **espera a TODOS los sensores declarados** en el árbol
de dispositivos antes de crear los enlaces del grafo. Cargando solo `imx682`, el sensor aparece
con **`0 link`** y `media-ctl -l` falla con *«Unable to parse link: Invalid argument»* — parece
un problema de sintaxis y no lo es. Hay que cargar **también `s5k3t2`**.

### Estado tras la sesión

Los módulos de cámara se **descargaron** al terminar; audio, Bluetooth y el resto siguieron
funcionando sin tocarse. El experimento del MISR **queda pendiente** hasta que el pipeline
vuelva a encenderse.

---
## ★★ Dónde está el muro (2026-07-17)

**El CSID no recibe NADA del PHY.** Medido en vivo con `/dev/mem` durante la captura
(CSID0 = vfe0 + 0x4000 = **0xacb3000**, offsets de `cam_ife_csid175_200.h`):

```
TOTAL_PKTS_RCVD (0x160) = 0     STATS_ECC   (0x164) = 0
TOTAL_CRC_ERR   (0x168) = 0     LANE0_MISR  (0x150) = 0
CAP_LONG_PKT_0  (0x130) = 0     RX_IRQ_STATUS (0x20) = 0
```
**Cero paquetes y cero errores.** No es un problema de margen de temporización (eso daría
errores CRC/ECC): el PHY sencillamente no engancha.

**La única señal positiva que hay**: los registros de estado del CSIPHY se activan **solo
mientras el sensor emite** → **el PHY ve actividad eléctrica en sus pines, pero nunca resuelve HS**.
**Ya están decodificados** (ver § siguiente): son **por carril de datos**, y en csiphy0
`STATUS[2].7` = carril 1 y `STATUS[5].3` = carril 2 — **mientras que el carril 0, que sí lleva
señal, no produce nada: se comporta como el carril 3, que ni siquiera está cableado.**

---

## ★★★ DECODE DE LOS BITS DE ESTADO DEL CSIPHY (2026-07-17)

### 1. Cómo se leen bien (esto era la mitad del problema)

Los 11 registros `0x8b0 + 4·n` son **estado de IRQ LATCHEADO**, no estado vivo. Se limpian con la
secuencia del ISR de mainline (`csiphy_isr`), y **el orden importa**:

```
1) escribir el valor a limpiar en CTRL[22+n]  (0x858 + 4·n)
2) pulsar CTRL10 (0x828): 1 y luego 0          <- ESTO es lo que confirma el borrado
3) poner a cero CTRL[22..32]
```
⚠️ Poner a cero los registros de clear **antes** de pulsar (mi primer intento) no borra nada.

⚠️⚠️ **Con las IRQ activadas, el ISR limpia sin parar (~280k/s) y cualquier lectura es una muestra
al azar de la tormenta, no el estado.** Para observar bien: **enmascarar** (escribir 0 en
`CTRL11..21` = `0x82c..0x854`), que para el ISR, y entonces el estado **latchea y se acumula**.
Enmascarar **no** impide el latcheo (comprobado) → el estado es *raw*, no *masked*.

Todas las lecturas de sesiones anteriores se hicieron con la tormenta activa → **no eran fiables**.

### 2. Los bits son POR CARRIL DE DATOS — aislados uno a uno

Escribiendo `CTRL5` en caliente por `/dev/mem` con el sensor emitiendo, y limpiando el latch entre
medidas (`CTRL5 = 0x80|BIT(pos·2)` habilita reloj + un solo carril). **csiphy0 / IMX682, repetido
3 veces, idéntico:**

| CTRL5 | carril habilitado | STATUS[0..10] |
|---|---|---|
| 0x81 | reloj + **ln0** (*sí lleva señal*) | `00 00 00 00 00 00 00 00 00 00 00` |
| 0x84 | reloj + **ln1** | `00 00 **80** 00 00 00 00 00 00 00 00` |
| 0x90 | reloj + **ln2** | `00 00 00 00 00 **08** 00 00 00 00 00` |
| 0xc0 | reloj + **ln3** (*sin conectar*) | `00 00 00 00 00 00 00 00 00 00 00` |

→ **`STATUS[2] bit7` = carril 1 · `STATUS[5] bit3` = carril 2.**
→ **El reloj no influye**: `0x15` (3 carriles **sin** habilitar el reloj) da exactamente lo mismo
   que `0x95`. Los bits son de la capa analógica del carril, no del decodificado HS.
→ El carril **3, que no está conectado, no produce nada** — eso demuestra que **los bits los
   provoca la señal de cada carril**, y valida el método.

### 3. ★ La anomalía: el carril 0 se comporta como uno DESCONECTADO

**El carril 0 lleva señal** (el sensor emite por 0,1,2 — `laneAssign = 0x0210`) **y no produce
ningún bit: exactamente igual que el carril 3, que no está cableado.** Los carriles 1 y 2 sí.

Dos lecturas posibles, y **con los datos que hay no se puede decidir** (no hay documentación de
los bits):
- **si los bits son errores** → el carril 0 recibe limpio y los carriles 1 y 2 fallan;
- **si los bits son "actividad detectada"** → el carril 0 no recibe nada (mal enrutado o muerto).

En ambos casos explica los 0 paquetes: no se puede montar un flujo de 3 carriles así. **Es la
pista más concreta que hay y es lo que hay que llevar a los mantenedores.**

### 4. Verificado además
- **Con señal**: tras limpiar, los bits **vuelven al instante** y siguen volviendo.
  **Sin señal**: tras limpiar, **todo a cero y se queda a cero** 2 s. → el PHY **sí recibe**.
- Al **parar** el sensor (transición HS→LP) se latchean además `STATUS[0] bit2` y `STATUS[2] bit6`
  → parecen indicadores de transición / stop-state. No confundirlos con los de señal.
- **csiphy1 se comporta distinto**: **ningún carril suelto** produce bits; solo con **los 4 a la
  vez** (`CTRL5 = 0xd5`) aparecen `STATUS[1].0`, `[3].5`, `[6].2`, `[8].7` y `STATUS[9] = 0x0b`.
  Curiosamente esos índices de bit (8, 29, 50, 71) van **de 21 en 21**. Sin explicar.
- ⚠️ **`0x_94` de cada banco de carril NO sirve**: es un registro **vivo y fluctuante** (una lectura
  da 0x05 en los 4 carriles, la siguiente solo en 2). Lo de "a csiphy1 le falta LN2" que se apuntó
  antes **era un artefacto de muestreo**, no un dato.

### 5. Mapa de registros (para no volver a buscarlo)
`CTRLn = 0x800 + 4·n` · `STATUSn = 0x8b0 + 4·n` (n = 0..10) · **clear** = `CTRL[22..32]` =
`0x858 + 4·n` · **glbl_irq_cmd** = `CTRL10` = `0x828` · **máscara de IRQ** = `CTRL[11..21]` =
`0x82c..0x854`. Bases: **csiphy0 = 0xace0000**, **csiphy1 = 0xace2000**.
`CTRL5 (0x814)` = habilitación de carriles: `BIT(7)` = reloj, `BIT(pos·2)` = carril de datos `pos`.

---

## ★★ La secuencia del downstream, portada entera — NO ARREGLA (2026-07-17)

Se replicó `cam_csiphy_config_dev()` del downstream **paso a paso**, no comparando tablas:
tabla `csiphy_2ph_v1_2_reg[5][22]` literal, recorrido de `lane_mask` escribiendo **solo los
bancos de los carriles cableados**, registros comunes primero (CTRL5, CTRL6=0x01, CTRL7=0x02,
**CTRL0=0x02**), sin tabla de data-rate (el downstream **solo la aplica en C-PHY**:
`if (csiphy_3phase) cam_csiphy_cphy_data_rate_config()`) y sin los `0x_5C`/`0x_60` que solo
escribía mainline. Parche completo: [`csiphy-secuencia-downstream.patch`](csiphy-secuencia-downstream.patch).

**Verificado en hardware** leyendo el PHY durante el streaming: banco del carril 3 sin tocar
(0x00, antes 0x91), `0x05c = 0x00`, `CTRL0=02 CTRL5=95 CTRL6=01 CTRL7=02`, settle 0x1D en los
carriles usados. **El PHY queda configurado registro a registro y en el mismo orden que el driver
del vendor. `TOTAL_PKTS_RCVD` sigue en 0 y los bits de estado son los mismos.**

→ **La causa NO está en la configuración del CSIPHY.** Es el descarte más fuerte que hay.

### Y no hay bloque PPI en este SoC
El downstream trae un driver de **PPI** (*PHY Protocol Interface*, entre el D-PHY y el protocolo:
`cam_csid_ppi170.c`, compatible `qcom,ppi170`) que mainline ni contempla — parecía LA explicación.
**Pero solo lo instancia `atoll-camera.dtsi`, y atoll no es nuestro SoC**; `sdmmagpie-camera.dtsi`
no tiene nodo PPI. (La trampa de atoll otra vez → [[reference-sm7150-downstream-tree]].)

### Descartado además, en caliente por `/dev/mem`
- **Codificación de `CTRL5`**: los bits impares no hacen nada (`0x82`, `0x88`, `0xa0` → cero) →
  `BIT(pos*2)` de mainline **es correcta**; el carril 0 está realmente habilitado.
- **`0x_C4`** (que el downstream escribe a 0 y mainline no): **es de solo lectura**, lee `0x5E` y
  no acepta escrituras. El downstream escribe ahí en balde.
- **`0x_5C`/`0x_60`** puestos a 0 en caliente (sí cuajan) + re-pateo de `CTRL5`: nada.
- **`PHY_NUM_SEL` del CSID**: barrido 0→7 en caliente: nada.
- ⚠️ **Cambiar `0x0114` (nº de carriles) del sensor en caliente lo cuelga** (FRAME_COUNT se para):
  hay que reprogramar el modo entero. Ese test quedó inválido, no concluyente.

## ★★ Minado del kernel de Android de fábrica — CONFIRMA el port (2026-07-17)

**Técnica reutilizable** (no hace falta arrancar Android): el `boot.img` de la ROM lleva el kernel
que Xiaomi compiló para surya, con las tablas del CSIPHY **compiladas dentro**. Se extraen así:

```sh
# boot.img: cabecera ANDROID! v2, page=4096, el kernel va en el primer page, gzip
python3 -c "import struct;d=open('boot.img','rb').read();\
 k=struct.unpack('<I',d[8:12])[0];open('k.gz','wb').write(d[4096:4096+k])"
gunzip -c k.gz > vmlinux_xiaomi.bin     # ~35 MB
```
Luego se busca la tabla por su patrón de bytes: `struct csiphy_reg_t` = **4 × u32**
(`reg_addr, reg_data, delay, csiphy_param_type`) = **16 B/entrada**, y el array es
`[MAX_LANES=5][MAX_SETTINGS_PER_LANE=43]` = **3440 B (0xD70) por tabla**. `csiphy_2ph_v1_2_reg`
empieza por `{0x0030,0,0,0}, {0x0904,0,0,0}, {0x0910,0,0,0}`. Tipos:
`0=DEFAULT 1=LANE_ENABLE 2=SETTLE_LO 3=SETTLE_HI 4=DNP 5=2PH 6=3PH`.

**Resultado**: las tablas 2PH del binario de Xiaomi son **byte a byte idénticas** a las del árbol
de ubports que porté (las que difieren son las de `combo_mode`, que no usamos: `isComboMode = 0`).
Y `sdmmagpie-camera.dtsi` declara `compatible = "qcom,csiphy-v1.2"`, que en `cam_csiphy_soc.c`
selecciona justo `csiphy_2ph_v1_2_reg` + `csiphy_common_reg_1_2` — **la versión que porté**.

→ **El parche 0046 es demostrablemente fiel a lo que Xiaomi ejecuta en este móvil.** Eso hace el
descarte definitivo: **la programación del CSIPHY NO es la causa.**

### Trampa que casi me como
El binario tiene **tres** tablas de registros comunes. Una, en `0x2108e14`, trae un pulso extra
que parecía la solución:
```
{0x0800, 0x03, delay=1, DEFAULT}    <- pulso de reset de CTRL0 que mainline no hace
{0x0800, 0x02, 2PH}
```
**Pero es la de `csiphy_common_reg_1_2_2`** (`cam_csiphy_1_2_2_hwreg.h`), que se selecciona con
`qcom,csiphy-v1.2.2` — **otro SoC**. sdmmagpie usa v1.2. Misma lección que atoll: comprobar
siempre de qué variante viene el valor antes de copiarlo.

### Descartado también
- **`secure_mode`**: el `scm_call2` a TZ (`cam_csiphy_notify_secure_mode`) **solo se hace si
  `secure_mode[i]`**, que por defecto es 0 → el CSIPHY no está en modo seguro. No es eso.
- **`camxoverridesettings.txt`** de la ROM: solo trae `enableICAInGrid=1` y
  `enableBubbleRecovery=FALSE`. Nada de CSIPHY.
- ⚠️ **Arrancar Android para volcar registros en un estado que funciona: descartado.** pmOS vive
  en una **imagen por loop** (`/dev/loop0` sobre `/dev/sda16`, 101 GB) y Android formatearía/
  cifraría userdata → se llevaría por delante la instalación.

## ★★ El DTB base de fábrica y el reloj `cphy_rx` — HILO ABIERTO (2026-07-17)

**El DTB base también sale del `boot.img`** (no solo el kernel): cabecera **v2**, campo `dtb_size`
en el offset **1648** y `dtb_addr` en 1652; el blob va tras kernel+ramdisk+second+recovery_dtbo,
alineado a página. Son **14 DTB concatenados** (cada uno con su `d00dfeed` + totalsize en big
endian); **el de SM7150 es el índice 9** (`qcom,msm-id = <0x16d 0x00>`).
Esto **completa el par**: `dtbo.img` daba el overlay de la placa, y esto da la base del SoC.

**Confirma que el port (0046) es a la versión correcta**: el DTB que arranca el móvil declara
`compatible = "qcom,csiphy-v1.2"` en los cuatro csiphy → selecciona `csiphy_2ph_v1_2_reg` +
`csiphy_common_reg_1_2`, que son las que porté y que en el binario de Xiaomi coinciden byte a byte.

### ★ Lo que sí destapó: `cphy_rx_clk_src`

El nodo csiphy0 del DTB de fábrica:
```
clock-names = "cphy_rx_clk_src", "csiphy0_clk", "csi0phytimer_clk_src", "csi0phytimer_clk"
clock-rates = <384000000 0 300000000 0>,   (svs)
              <400000000 0 300000000 0>,   (svs_l1)
              <400000000 0 300000000 0>;   (turbo)
```
**Xiaomi nunca baja `cphy_rx` de 384 MHz. Nosotros corremos a 300** (medido en `clk_summary`
durante la captura).

**Y hay una errata real en camss** (parche **0047**): `vfe0_cphy_rx` listaba **`38400000`** donde
todas las demás listas del fichero —las dos de justo debajo incluidas— ponen **`384000000`**. El
`ftbl` real de `camcc-sm7150.c` (idéntico al de `camcc-sdmmagpie.c`) solo ofrece **19,2 / 300 /
384 / 400 MHz**, así que la errata **no nombra ninguna frecuencia que exista** y además deja la
lista desordenada → el selector (`primera freq > min_rate`, recorriendo de frente) **nunca puede
elegir 384**. Es la única aparición de `38400000` en todo el fichero.

### ★★ RESUELTO: quién bajaba el reloj a 300 — era camss, contra sí mismo

Printks en los **tres** `clk_set_rate` de camss (`csiphy.c:186`, `csid.c:587` y `:593`,
`vfe.c:1014`). La traza, en orden:
```
PRUEBA-CLK csiphy0 set 'cphy_rx_src'  -> 384000000   <- lo pone a 384
PRUEBA-CLK csiphy0 set 'csiphy0'      -> 300000000   <- ...y acto seguido lo baja
PRUEBA-CLK csiphy0 set 'csiphy0_timer'-> 300000000
PRUEBA-CLK vfe0    set 'vfe0'         -> 510000000
PRUEBA-CLK vfe0    set 'camnoc_axi'   -> 240000000
PRUEBA-CLK csid0   set 'vfe0_csid'    -> freq[0]=300000000  (rama else-if)
PRUEBA-CLK csid0   set 'vfe0'         -> freq[0]=380000000  (rama else-if)
```
**Nadie más lo toca.** El culpable es el propio csiphy, dos líneas después, porque en
`camcc-sm7150.c`:
```c
static struct clk_branch camcc_csiphy0_clk = {
	.parent_hws = { &camcc_cphy_rx_clk_src.clkr.hw },   /* rama del MISMO RCG */
	.flags = CLK_SET_RATE_PARENT,                       /* y arrastra al padre */
```
`csiphy0_clk` **es una rama de `cphy_rx_clk_src` con `CLK_SET_RATE_PARENT`**, así que pedirle
300 MHz tira del RCG compartido —el que alimenta la ruta RX de **todos** los csiphy y los IFE—
hasta 300. Su lista en `csiphy_res_7150` **empieza en `300000000`** y el selector coge la primera
por encima de `link_freq/4`, así que con nuestro enlace de 953,6 MHz elige 300.
El DTB del vendor pide **384 (svs) / 400** en `cphy_rx_clk_src` y deja `csiphy0_clk` **a 0**.

**Arreglo (parche 0048), solo datos, sin tocar código**: quitar el `300000000` de la lista de
`csiphy0` → la rama pide 384 y sube el RCG con ella. **Verificado en `clk_summary` durante la
captura: `cphy_rx_clk_src = 384000000`, sostenido.**

⚠️ **La lista de `cphy_rx_src` es DATO MUERTO**: `csiphy_set_clock_rates()` solo ajusta los relojes
cuyo **nombre** casa (`csiphy%d_timer`, `csiphy%d`, y `csi%d_phy` en CAMSS_660), y `"cphy_rx_src"`
no casa con ninguno. La tasa **hay que pedirla por la rama**. (Otro campo inerte, como `init_load_uA`.)

**Pero NO arregla la captura**: con el reloj ya en 384, `TOTAL_PKTS_RCVD` sigue en 0. Era un bug
real —mainline corre la ruta RX del CSIPHY por debajo del mínimo del vendor en **todas** las placas
sm7150— pero no es la causa del silencio. Coherente con la física: un reloj corto daría
*overflows*, no cero paquetes (300 MHz ya estaba por encima de los 238,4 del byte-clock).

## ★★★ El TPG SÍ atraviesa el CSI2 RX — el bloque RX del CSID está probado (2026-07-17)

**No existe BIST/loopback en el CSIPHY** (`grep -i bist|loopback|selftest` en el driver del vendor:
nada) y **estructuralmente no puede haberlo: el CSIPHY es solo receptor**, no tiene con qué
generarse datos. Por eso el TPG vive en el CSID.

**Pero el TPG del CSID no bypasea el CSI2 RX: lo alimenta.** La pista estaba en
`CSID_TPG_CTRL (0x600)` teniendo un campo `TPG_CTRL_NUM_ACTIVE_LANES` — un generador interno no
necesitaría saber de carriles salvo que emule al PHY. **Confirmado midiendo**, con el TPG activo y
**ningún PHY conectado**:
```
TPG_CTRL        = 0x00A06427   (TEST_EN=1, FS/FE_PKT_EN=1, NUM_ACTIVE_LANES=2 -> 3 carriles)
TOTAL_PKTS_RCVD = 0x00077FA6   = 491.430 paquetes
TOTAL_CRC_ERR   = 0x127
LANE0_MISR      = 0xF547BBD4   <- no nulo
```
→ **El bloque CSI2 RX del CSID FUNCIONA**: cuenta paquetes, calcula el MISR y verifica CRC.

**Esto cierra la última duda del lado CSID.** Con el sensor real: `TOTAL_PKTS = 0` **y**
`MISR = 0` → no es que el RX esté roto o mal configurado; **los datos no cruzan del PHY al CSID**.
Es lo más parecido a la medida con analizador que se puede hacer por software, y responde por la
mitad de la ruta que sí es observable.

⚠️ **Falsa alarma que casi cuela**: varias pruebas del TPG dieron **0 bytes** y pareció una
regresión de los parches 0046-0048. **No lo era**: el pipeline arrastraba el enlace
`csiphy1 -> csid0` de los tests de la frontal. Con camss **prístino** y con **mis parches** el TPG
captura idéntico: 3 frames, patrón incremental `00 00 00 00 e4 01 01 01 01 e4 02...`
(7.776.000 B a 1920×1080 · 60.329.472 B a 4624×3472). **Comprobado A/B contra `v7.1_rc3` prístino.**
**Receta buena**: desconectar **los dos** PHY (`csiphy0` *y* `csiphy1`) de `csid0`, fijar el formato
en `msm_csid0:0` **y** `msm_vfe0_rdi0:0`, `test_pattern=1` en `/dev/v4l-subdev4`, y capturar.

## ★★★ TRAMPA QUE INVALIDÓ TODOS LOS EXPERIMENTOS ANTERIORES

**`clock-lanes` NO puede nombrar un carril que use `data-lanes`.** Si colisionan,
`v4l2_fwnode_endpoint_parse` **descarta el mapeo del DT sin avisar** y usa el suyo por defecto
(`v4l2-fwnode.c`, `use_default_lane_mapping`):

```c
if (have_clk_lane && lanes_used & BIT(clock_lane) && !use_default_lane_mapping) {
        pr_warn("duplicated lane %u in clock-lanes, using defaults\n", v);
        use_default_lane_mapping = true;
}
...
unsigned int dfl_data_lane_index = bus_type == V4L2_MBUS_CSI2_DPHY;   /* = 1 */
if (use_default_lane_mapping)
        for (i = 0; i < num_data_lanes; i++)
                bus->data_lanes[i] = dfl_data_lane_index + i;         /* 1, 2, 3 */
```

Con `clock-lanes = <0>` + `data-lanes = <0 1 2>` → el carril 0 está en ambos → **defaults
{1,2,3}**. Comprobado con printk en el dispositivo:

| | `pos` | `CTRL5` | `lane_assign` | `RX_CFG0` |
|---|---|---|---|---|
| `clock-lanes = <0>` (mal) | `[1 2 3]` | `0xd4` | `0x321` | `0x3213` |
| `clock-lanes = <7>` (bien) | `[0 1 2]` | `0x95` | `0x210` | `0x2102` |

El blob del sensor dice `laneAssign = 0x0210` → carriles **[0,1,2]**, así que lo bueno es `<7>`.
**Convención de camss**: el reloj va siempre **fuera** del rango de datos — `<7>` en
sc8280xp-x13s y lemans-evk, `<4>` en sm8550-qrd. Solo los DT de sm7150 de Xiaomi (surya y
davinci, ninguno con captura probada) ponen `<0>`; en davinci no colisiona porque usa
`data-lanes = <1 2>`.

⚠️ **El parche 0041 SIEMPRE tuvo `<7>`**: el `<0>` era una divergencia del árbol de iteración
rápida `kernel-build`, **que es justo el que genera el DTB que se copia al móvil**. Así que el
móvil llevaba meses arrancando con el mapeo roto y **todo lo probado antes (barrido de settle,
tablas de data-rate, valores por carril, 3 vs 4 carriles) se midió sobre una configuración
inválida y NO cuenta**. Al repetir el barrido de settle ya con el mapeo bueno: sigue en cero.

**Lección**: `kernel-build` puede divergir del repo git. Antes de creerse un resultado,
`diff` los ficheros tocados contra `/ext_r/ext_edi/src/suria/kernel/sm7150-mainline`.

---

## ★★ La tabla de init real del IMX682 (parche 0040, corregido hoy)

El driver tenía **16 registros de init**: 7 sacados del blob pequeño + **9 inventados**.
El sensor necesita la **tabla global de Sony de 638 registros**, y está en el blob **`_ver2_`**:

| blob | tamaño | tabla init (off=41968) |
|---|---|---|
| `com.qti.sensormodule.j20c_ofilm_imx682_wide.bin` | 146 KB | **7 registros** (un muñón) |
| `com.qti.sensormodule.j20c_ofilm_imx682_ver2_wide.bin` | **343 KB** | **638 registros** ← la buena |

La sesión anterior parseó el blob pequeño y se quedó con el muñón. Las dos empiezan igual
(`0x0136=0x13, 0x0137=0x33` = EXTCLK 19,20 MHz; `0x0111=0x03` = CSI_SIGNALLING_MODE D-PHY),
pero la ver2 sigue con los bloques de calibración analógica seleccionados por `0x33f2`
(0x01/0x02/0x03) y `0x1f04/0x1f05`. Diferencia notable: `0x33f0/0x33f1` = **0x03** (ver2) vs
0x04 (pequeño).

**Verificado por lectura de vuelta en el móvil durante el streaming**: `0x0136=0x13`,
`0x33f0=0x03`, `0x0111=0x03`, `0x9004=0x1f`, `0xa737=0x20`. La tabla llega entera.
**No desbloqueó la captura**, pero era un hueco real.

Las **14 tablas** del blob: 5 modos × 73 registros + 9 + **638** + 2 + 1.
- La de **9** (`0x3030, 0x444a/b, 0x443d, 0x4b48/9, 0x4425, 0x3020, 0xd70c`) es una segunda
  tabla del vendor → en el driver es `imx682_init_regs2`, escrita tras la global.
- Las de 2 (`0x0002=0x02, 0x0006=0x40`) y 1 (`0x0000=0x1f41`) parecen identificadores, no secuencias.
- **Modos** (por `X_OUTPUT_SIZE` 0x034c/0x034d): 4672→9248 (full 64 MP) · **11920→4624** (el
  nuestro) · 19096→3840 · 26272→2312 · 33448→1920.

**La tabla de modo del driver es byte a byte idéntica al blob** (73/73, comprobado).

**PLL del modo 4624×3472, verificado**: `op_pll = 19,2/3 × 298 = 1907,2 MHz` →
**link_freq = 953,6 MHz** ✔ exactamente lo que declara el driver. Y
`vt_pix_clk = 6,4 × 312/(2×8) = 124,8 MHz` con LLP=9432 / FLL=3528 → **30 fps** ✔ que es
justo el ritmo medido en `FRAME_COUNT`. Todo coherente: **el driver del sensor es correcto**.

Herramienta: [`dump-regtable.py`](dump-regtable.py) `<blob> <offset>` vuelca una tabla como C.
Los blobs están en [`blobs/`](blobs/).

---

## ★★ El DT de fábrica de Xiaomi — YA LO TENEMOS

`images/dtbo.img` de la ROM de fábrica → 27 overlays. **El de surya es el índice 7**
(`qcom,msm-id = <0x16d 0x00>` = 365 = SM7150, `board-id = <0x22 0x00>`, y es el único con
msm-id 365 que trae el WL2866D). Volcado en [`surya-factory-dtbo.dts`](surya-factory-dtbo.dts).

Confirma toda la topología (ya no hay que suponer nada):

| nodo | sensor | csiphy | bus (cci-device/master) | MCLK | reset | extra |
|---|---|---|---|---|---|---|
| `cam-sensor@0` | **IMX682** | **0** | **i2c-12** (0/0) | MCLK1 = tlmm14 | tlmm25 | CAM_STANDBY tlmm66 |
| `cam-sensor@1` | depth | 2 | **i2c-13** (0/1) | MCLK0 = tlmm13 | tlmm93 | — |
| `cam-sensor@2` | **S5K3T2 frontal** | **1** | **i2c-13** (0/1) | MCLK0 = tlmm13 | tlmm23 | **CAM_SEL `pm6150_gpios 3`** |
| `cam-sensor@3` | HI1337 ultra | 1 | **i2c-14** (1/0) | MCLK3 = tlmm16 | tlmm24 | **CAM_SEL `pm6150_gpios 3`** |
| `cam-sensor@4` | HI259 macro | 2 | **i2c-14** (1/0) | MCLK2 = tlmm15 | tlmm64 | CAM_CHIP_EN tlmm57 |
| `cam-sensor@5` | — | 3 | i2c-13 (0/1) | MCLK2 | tlmm72 | CAM_STANDBY tlmm88 |

⚠️ **El bus lo dan DOS propiedades**: `cci-device` (0 = cci0 → i2c-12/13; 1 = cci1 → i2c-14) y
`cci-master` (el bus dentro del bloque). Si `cci-device` falta, vale 0. **Mirar solo `cci-master`
lleva al bus equivocado** — de ahí venía el error de creer que la frontal iba en i2c-14.

⚠️ Los GPIO **no son todos del tlmm**: el `__fixups__` del overlay dice a qué controlador apunta
cada referencia. `CAM_SEL` es **`pm6150_gpios 3`** (no tlmm3), y `camera_vdig` es
**`pm6150l_gpios 12`**.

**El multiplexor MIPI queda descartado con datos** (ya no por razonamiento): solo los sensores
de **csiphy1** llevan `CAM_SEL`. **El IMX682 va solo en csiphy0 y no pasa por el mux.**

El IMX682 declara `regulator-names = "cam_vio", "cam_vdig", "cam_clk"` con
`rgltr-min-voltage = <1800000, 2800000, 0>` → **cam_vdig son 2,8 V** (el comentario `//dvdd 1.1v`
del DT downstream miente, como ya decía la memoria).

---

## ★ Alimentación del CSIPHY — dos huecos tapados hoy (parches 0042/0043)

El nodo csiphy0 del downstream (`sdmmagpie-camera.dtsi`, **no atoll**) pide cosas que mainline no:
```
regulator-names = "gdscr", "refgen";
gdscr-supply  = <&titan_top_gdsc>;
refgen-supply = <&refgen>;              ← mainline: camss no lo votaba
csi-vdd-voltage = <1200000>;
mipi-csi-vdd-supply = <&pm6150l_l3>;    ← = vdda_csi0_1p25 = vreg_l3c (mainline SÍ lo pide)
```

1. **`refgen`** (generador de referencia del SoC, **0xff1000** en SM7150 — *no* 0x88e7000, que es
   de atoll/sm8150). El nodo **ya existe** en `sm7150.dtsi` y mainline trae driver
   (`qcom-refgen-regulator.c`, variante **sdm845**: `BG_CTRL(0x14) |= 0x6`, `BIAS_EN(0x08) = 0x7`;
   la variante sm8250 usa 0x80, fuera de la región de 0x60 → descartada). Pero **solo lo votaba el
   DSI, al que no le hace falta**: en un móvil arrancado se leía **apagado** (`BIAS_EN = 0x06`,
   `BG_CTRL & 0x6 = 0x4` = las constantes de *disable* exactas del driver). Parche 0043 → camss lo
   pide como tercera supply del CSIPHY. Verificado: `refgen: state=enabled users=1`.
2. **Tensiones al mínimo del constraint** (mismo patrón que el bug del WCD9375): camss solo hace
   `regulator_bulk_enable` y **nunca pide tensión**, así que los rieles arrancan en el mínimo:
   - `vdda-pll` = `vreg_l3c` estaba a **1144000 µV**; el downstream pide **1200000**.
   - `vdda-phy` = `vreg_l4a_0p88` estaba a **824000 µV** pese a llamarse *0p88*.

   Parche 0042 sube los dos mínimos. Verificado: `ldo3: 1200000uV enabled`, `ldo4: 880000uV enabled`.

**Ninguno de los dos desbloquea la captura**, pero los dos eran huecos reales.

---

## Descartado con datos (no repetir)

- **Barrido de settle 4→60** ya con el mapeo de carriles bueno: **0 paquetes y 0 errores** en todo
  el rango. No es temporización.
- **Los 98 registros del CSIPHY leen exactamente lo configurado** durante el streaming
  (script que extrae `lane_regs_sm7150` del fuente y lo compara con el volcado de `/dev/mem`):
  `CTRL0=0x02`, `CTRL5=0x95`, `CTRL6=0x01`, `CTRL7=0x02`, settle=29. La tabla de mainline ya
  coincide con la del downstream salvo `0x_C4=0x00` (solo downstream) y `0x_5C/0x_60` (solo
  mainline).
- **Relojes y dominios**: `camcc_csiphy0_clk` 300 MHz on · `camcc_csi0phytimer_clk` 300 MHz on ·
  `camcc_cphy_rx_clk_src` 300 MHz (≥ los 238,4 MHz de byte-clock que pide el enlace) ·
  `camcc_ife_0_csid_clk` 300 MHz · `titan_top_gdsc` + `ife_0_gdsc` **on**.
- **Sensor emitiendo**: `FRAME_COUNT (0x0005)` +30/s · `MODE_SELECT (0x0100) = 0x01` ·
  `CSI_LANE_MODE (0x0114) = 0x02` (3 carriles). ⚠️ Registros de **16 bits**: usar `i2ctransfer`,
  no `i2cget`. Y solo responde **mientras hay streaming** (si no, el sensor está sin alimentar).
- **CSID sano**: `RX_CFG0 = 0x2102`, `RDI0_CFG0 = 0x802BF007` (enable=1, DT=**0x2b** RAW10, VC=0,
  decode=PAYLOAD_ONLY). El **TPG del CSID captura 3 frames perfectos** → CSID+VFE+DMA+nodo de vídeo OK.
- **Data-rate del downstream**: `data_rate_delta_table_1_2` compara contra `data_rate × 2,28`;
  1907,2 Mbps × 2,28 = 4,35e9 < 5,7e9 → **tramo 0**, que es el que ya se probó. Sin cambio.
- ⚠️ **`csiphy0 IRQ = 0` NO PRUEBA NADA**: mainline enmascara todas las IRQ del PHY
  (`for (i = 11; i < 22; i++) writel(0, ...CTRLn(i))`). Activándolas hay ~280k interrupciones =
  tormenta (el printk del ISR **inunda el ring de dmesg y borra las trazas útiles** → dejarlo en
  `printk_ratelimited`).

## ★★ El sensor frontal S5K3T2 (parches 0044/0045)

Blob: `com.qti.sensormodule.j20c_ofilm_s5k3t2_front.bin` (165 KB). **El de `sunny` trae tablas
byte a byte idénticas** → la variante de módulo da igual. **No hay `_ver2_`** para este sensor.

| dato | valor |
|---|---|
| I2C | **0x10** en **i2c-13** (`cci0_i2c1`) — *no* i2c-14 |
| chip ID | **0x3142** en reg **0x0000** |
| tipos | WORD / **WORD** (los valores son de 16 bits, ojo) |
| carriles | **4** (`laneAssign = 0x3210`, `0x0114 = 0x0300`) |
| link_freq | **896 MHz** (1792 Mbps/carril) |
| modos | **5184×3880** @29,90 · 2592×1940 @30,13 · 1280×720 @120,41 |
| tablas | 3 modos × 65 registros + **280 de init global** |

**Samsung escribe en WORD**, así que `0x0114` sale como `0x0300` y el byte útil es **el alto**
(por eso vale 0x03 = 4 carriles). Y usa una **ventana indirecta**: `0x6028` elige la página,
`0x602a` la dirección dentro de ella y cada escritura a `0x6f12` guarda una palabra y
autoincrementa. El preámbulo `{0x0000, 0x0005}, {0x0000, 0x3142}` es la secuencia mágica de
identificación de Samsung. Nada de eso está documentado → **se reproduce verbatim**.
⚠️ El volcador debe **conservar orden y duplicados** (`0x6f12` aparece 244 veces).

**Power-up** (del blob): `CAM_SEL=0 (+1ms) → VDIG=1 (+1ms) → VIO=1 (+1ms) → MCLK 19,2MHz (+15ms)
→ RESET=1 (+5ms)`. Sin VANA. Los raíles: `dovdd` = `pm6150_l13` (1,8 V), `avdd` = **AVDD1 del
WL2866D** (2,8 V; el `wl2866d_camera_power_up(2)` del downstream enciende **solo** ese) y
`avdd2` = `camera_vdig` (`pm6150l_gpios 12`, 2,8 V — el downstream lo llama "vdig" pero 2,8 V no
es una tensión de core digital, la misma mentira que en el IMX682).

**Validación cruzada del PLL** (la misma técnica que con el IMX682, y sale exacta):
`vt_pix_clk = 19,2/3 × 185 / (1 × 7) = 169,14 MHz`, **4 píxeles por reloj** → 676,57 MHz; sobre
`LLP × FLL` de cada modo da **29,90 / 30,13 / 120,41 fps** — que es **exactamente** lo que el
propio blob declara como `double` en `resolutionData[10]`. Y el contador de frames del chip late
a ese ritmo en el hardware. `link_freq` sale del **2º PLL** del modo: `19,2/3 (0x030e) × 140
(0x0310) = 896 MHz` → 1792 Mbps/carril, contra los 1612 que exige el tiempo de línea (margen
×1,11, lo típico de un diseño real).

**★ `resolutionData` es oro** (768 B = 3 modos × 32 u64): `[3]`=LLP, `[4]`=FLL, `[5]`=hblank,
`[6]`=vblank, **`[10]`=fps como `double`**, **`[11]`=nº de carriles**. Sirve para cualquier sensor.

**Sin confirmar**: el **orden Bayer** (se usa `SGRBG10_1X10`) y el máximo de ganancia analógica
(Samsung codifica ×32, se asume tope 16×).

⚠️ Para capturar de la frontal el nodo de vídeo va en **`pgAA`** (SGRBG10P), no `pRAA`; si no,
`video_check_format` da **`STREAMON: Broken pipe`**. Y **hay que fijar el formato de cada pad
explícitamente** (`msm_csiphy1` incluido): tras reiniciar vuelven a `UYVY8/1920x1080`.

## Herramientas
- [`dump-regtable.py`](dump-regtable.py) — vuelca una tabla de registros del blob como C.
- [`parse-sensormodule.py`](parse-sensormodule.py) — resumen del blob (I2C, power seq, laneAssign, modos).
- [`mmr.c`](mmr.c) — lector/escritor MMIO por `/dev/mem` (`gcc -static`, el host ya es aarch64).
  **`busybox devmem` NO tiene applet en este móvil.** Ojo: leer MMIO con el reloj parado da 0
  (o cuelga) → leer **durante** la captura.
- [`diagnostico-camara.sh`](diagnostico-camara.sh) — solo lee.
- [`csiphy-lane-decode.sh`](csiphy-lane-decode.sh) `<base_phy> <valores de CTRL5...>` — enmascara
  las IRQ, y por cada `CTRL5` limpia el latch y vuelca los 11 STATUS. **Es la herramienta que
  decodificó los bits.** Lanzar **con el sensor emitiendo**. Ej.:
  `csiphy-lane-decode.sh $((0xace0000)) 0x81 0x84 0x90 0xc0` (cada carril por separado).
- [`csiphy-latch.sh`](csiphy-latch.sh) `<base_phy> <bus_i2c> <addr>` — prueba con/sin señal:
  limpia, latchea 2 s emitiendo, para el sensor, limpia y latchea 2 s sin señal.
- `settle_override` como parámetro del módulo: `/sys/module/qcom_camss/parameters/settle_override`
  (-1 = calculado) → barrer settle sin recompilar ni reiniciar.

## ★★ Las 4 hipótesis del prompt post-telefonía — probadas, TODAS descartadas (2026-07-18)

Ver [`PROMPT-proxima-sesion-camara.md`](PROMPT-proxima-sesion-camara.md) para el razonamiento
completo. Resultado de probarlas la misma noche, en orden:

1. **Parámetros del CSIPHY vía blob del vendor**: parseado `imx682_ofilm_ver2.bin` entero
   (`streamConfiguration`, `resolutionInfo`, `cameraModuleData`) — no hay ningún campo de
   settle/modo-de-reloj más allá de `laneAssign`/`isComboMode`, que ya coincidían. **Descartada**:
   no hay dato de runtime que se nos escape por esta vía; el settle debe salir de la fórmula
   estática (ya verificada igual al vendor).
2. **Off-by-one en la máscara de carriles**: ya descartada antes de esta ronda por el volcado
   registro a registro contra el **kernel real de fábrica** (byte a byte idéntico). Redundante,
   sigue descartada.
3. **Orden de arranque / LP-11**: revisado `video_start_streaming()` en `camss-video.c` — el orden
   GRUESO ya es correcto (VFE→CSID→CSIPHY→sensor, el sensor arranca el último). Pero
   `csiphy_stream_on()` no esperaba nada tras programar los registros antes de que el framework
   llamase al sensor — hueco real, invisible, que en Android podría llenar CamX en userspace.
   **Añadido parámetro de diagnóstico** `csiphy_settle_delay_us` (parche **0055**,
   `/sys/module/qcom_camss/parameters/csiphy_settle_delay_us`) y **probado en captura real del
   IMX682 hasta 20 ms** (tres órdenes de magnitud por encima de cualquier asentamiento analógico
   real de D-PHY): `TOTAL_PKTS_RCVD` y `TOTAL_CRC_ERR` se quedan en 0 sea cual sea el margen.
   **Descartada con datos duros**, no solo por lectura de código.
4. **Reloj MIPI continuo vs no-continuo**: ni mainline ni el downstream implementan esa
   distinción para este PHY (sin `continuous`/`clk_lane` mode-switch en ninguno de los dos
   drivers) — no es un parámetro que exista en esta plataforma. **Descartada** por ausencia total
   de la noción en el código, sin necesidad de probarlo en hardware.

**Las 4 hipótesis agotadas sin mover el resultado ni un bit.** El caso vuelve a estar donde estaba
antes del prompt: `TOTAL_PKTS_RCVD=0`, `TOTAL_CRC_ERR=0`, con dos sensores de fabricantes
distintos, la config verificada byte a byte contra el kernel real de Xiaomi, y ahora también el
timing de arranque probado hasta 20 ms sin efecto. Esto refuerza — no debilita — la recomendación
ya anotada: **llevar el caso a los mantenedores de sm7150-mainline** (item 2 más abajo), con el
dossier completo (carril 0 sin estado, TPG bueno, byte a byte contra fábrica, timing descartado).

## Siguiente

1. ~~Decodificar los bits de estado~~ → ✅ **HECHO** (ver § DECODE). Resultado accionable: **el
   carril 0 de csiphy0 no produce estado pese a llevar señal**, igual que el carril 3 desconectado.
2. **★ Ir a los mantenedores de sm7150-mainline** con el caso — ya es la opción con más peso
   relativo: las 4 hipótesis nuevas post-telefonía están agotadas (ver arriba), y el caso ya tiene
   dossier completo (carril 0 sin estado, TPG bueno, byte a byte contra fábrica, timing hasta
   20 ms sin efecto) (ver `../PENDIENTES.md` §1).
3. ~~Cámara frontal como experimento de control~~ → ✅ **HECHO** (ver arriba): csiphy1 tampoco
   engancha → **el fallo es de camss**.
4. Investigar por qué a csiphy1 le falta **LN2** (`0x494` no se mueve y los otros tres sí).
5. **Pendiente (anotado 2026-07-17)**: buscar `cam_sensor` en el DTS downstream de referencia
   `sdmmagpie` (`$HOME/src/en_ext/ubports/kernel-surya/out/arch/arm64/boot/dts/qcom/.sdmmagpie.dtb.dts.tmp`,
   21125 líneas) — hay mucho contenido de cámara ahí sin revisar todavía (nodos `cam_sensor`,
   posiblemente `cam_csiphy`/`cam_csid` con parámetros que comparar contra mainline).
   También existe como fichero fuente aparte (sin compilar, más fácil de leer):
   `$HOME/src/en_ext/ubports/kernel-surya/arch/arm64/boot/dts/qcom/sdmmagpie-camera.dtsi`.
