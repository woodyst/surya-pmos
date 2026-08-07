# libcamera: enfoque manual y ★AUTOENFOQUE para las apps

## Qué arregla

El manejador **«simple»** de libcamera —el que atiende a `qcom-camss`, y por tanto a surya— **no
menciona la lente de enfoque ni una sola vez**. En un dispositivo cuyo sensor tiene actuador, la
lente se enumera y luego queda **inalcanzable**: ninguna aplicación puede moverla, y la cámara se
comporta como si no tuviera motor.

Con el parche, cuando `CameraSensor` expone una lente, el manejador publica:

- **`AfMode`, solo con `AfModeManual`** — este camino no tiene algoritmo de autoenfoque, así que
  ofrecer más sería mentir.
- **`LensPosition`**, que se aplica **antes de encolar los búferes** del fotograma (para que valga
  desde ese mismo fotograma) y se informa de vuelta en los metadatos.

## ⚠️ La decisión de diseño: las dioptrías

`LensPosition` se define **en dioptrías** (el inverso de la distancia en metros), no en unidades
del motor. Convertirlo bien exige calibración óptica. El parche hace un mapa **lineal** sobre el
recorrido del actuador tomando **cero = infinito** —que es donde queda una bobina en reposo, y lo
respalda que la primera captura con la lente sin corriente tenía el fondo nítido y lo cercano
blando— y **7 dioptrías** en el extremo opuesto.

**Esas 7 dioptrías son una estimación, no una calibración**: salen de una sola medida (la posición
600 enfocaba a unos 25 cm). Está marcado como tal en el código. Su sitio natural es el fichero de
ajuste del sensor, donde una medida de dos puntos a distancias conocidas lo dejaría correcto. En
la práctica el deslizador funciona y es monótono; lo que puede no cuadrar es la distancia que
anuncie.

## Reproducir

```sh
# 1. copiar el parche y el APKBUILD a la receta de pmOS
cp 0004-*.patch APKBUILD <pmaports>/temp/libcamera/
# 2. sumas y compilación cruzada
pmbootstrap checksum libcamera
pmbootstrap shutdown            # ⚠️ si no, el build falla al desmontar /mnt/pmbootstrap/packages
pmbootstrap build libcamera --arch aarch64
# 3. instalar en el móvil (los tres subpaquetes que usa surya)
scp .../packages/v26.06/aarch64/libcamera{,-ipa,-tools}-99990.7.1-r1.apk epo:/tmp/
ssh epo 'sudo apk add --allow-untrusted /tmp/libcamera*.apk'
```

⚠️ `pmbootstrap checksum` **deja el chroot montado**; el `build` siguiente falla con
*«Failed to umount … /mnt/pmbootstrap/packages»* si no se hace `pmbootstrap shutdown` en medio.

📌 La receta de pmOS ya trae **ficheros de calibración de sensores** (`imx355.yaml`, `imx363.yaml`…):
es el sitio donde añadir un `imx682.yaml` cuando se aborde la calidad de imagen.

## Lo que NO resuelve

- **Autoenfoque**: hace falta una medida de nitidez en el ISP por software (hoy solo produce
  histograma) y el algoritmo de escalada en el IPA. Ninguna de las dos existe.
- ⚠️ En libcamera 0.7.1 **solo el manejador de Raspberry Pi** publica estos controles a las
  aplicaciones; el de IPU3 mueve la lente **internamente** desde su IPA. Esto es escribir la
  función, no portarla.

## ⚠️ Un fallo propio, cazado en la primera prueba (y cómo evitarlo)

La primera versión **estrellaba libcamera** con `SIGSEGV` en
`SimpleCameraData::imageBufferReady`. Causa: al insertar la línea que informa de `LensPosition` en
los metadatos, quedó así —

```c
	if (request)
		if (focusLens_)
			request->_d()->metadata().set(controls::LensPosition, lensPosition_);

		request->_d()->metadata().set(controls::SensorTimestamp, ...);   /* ¡FUERA del if! */
```

— y la línea original de la marca de tiempo pasó a ejecutarse **siempre**, desreferenciando
`request` cuando es nulo. **La indentación lo disimula perfectamente.** Arreglado poniendo llaves.

📌 Método: la traza del volcado (`coredumpctl info`) señaló la función exacta. Mirar ahí **antes**
de teorizar.

## Verificación — ✅ HECHA (2026-08-07)

```
cam -c 1 --list-controls
  Control: [inout] libcamera::AfMode:
  Control: [inout] libcamera::LensPosition: [0.000000..7.000000]
  Control: [inout] libcamera::Contrast: [0.000000..2.000000]
  Control: [inout] libcamera::Gamma: [0.100000..10.000000]
```

`cam` **no permite fijar controles**, así que para comprobar que además *mueve* la lente se usa
`py3-libcamera` (compilado por el mismo `pmbootstrap build`) y se lee del chip la posición escrita:
guion `probar-foco2.py`. ⚠️ Los enlaces de Python **no exponen `ControlList`**: los controles de
`Camera.start()` se pasan como **diccionario**.


### Que además MUEVE la lente

`cam` no permite fijar controles, así que se comprueba con `py3-libcamera` (lo construye el mismo
`pmbootstrap build`) pidiendo posiciones y **leyendo del propio chip** lo que ha quedado escrito —
una verificación que no depende de la escena ni del ojo:

| pedido | código esperado | el chip dice |
|---|---|---|
| 0,0 dioptrías | 0 | **0** |
| 3,5 dioptrías | 512 | **512** |
| 7,0 dioptrías | 1023 | **1023** |

Y **el usuario oye los movimientos del motor**, que es la confirmación física: con el protocolo
equivocado (DW9714) no se oía nada, porque no se movía.

⚠️ En una sesión **en frío** la primera petición puede no aplicarse (el chip se queda donde
estaba): en ese instante el sensor aún no tiene corriente y el motor no responde. Con la cadena ya
caliente se aplican todas, incluida la primera. No es un defecto del parche sino el acoplamiento
de alimentación de esta placa.

⚠️⚠️ **Al terminar, VOLVER A ARRANCAR WIREPLUMBER.** Hay que pararlo para que libcamera pueda
tomar la cámara, y sin él **BlueZ deja de conectar**: el perfil `a2dp-sink` falla *antes de mandar
un solo mandato HCI* y el error que se ve, `br-connection-unknown`, no dice nada. Se delata mirando
`btmon`: **si no hay `Create Connection`, el fallo es de BlueZ, no del chip**.


---

# ★★★ AUTOENFOQUE (parche 0005, pkgrel=7) — FUNCIONA

**Verificado por el usuario en la app: «enfoca rápido y reenfoca al cambiar distancia».**

## Por qué el autoenfoque y no el manual

El enfoque manual quedó expuesto (parche 0004) **pero las apps no llegaban a verlo**: el conector
de PipeWire descarta esos controles y Snapshot no tiene interfaz. `qcam` se probó y se descartó (no
enfoca y no es para móvil). El autoenfoque **salta ese muro** porque ocurre **dentro de libcamera**:
no necesita ni que PipeWire reenvíe nada ni que la app cambie.

## Las cuatro piezas

1. **Medida de nitidez en el ISP** (`swisp_stats.h`, `swstats_cpu.cpp`): suma de la diferencia
   absoluta de luminancia entre muestras vecinas, acumulada **donde ya se recorren los píxeles**
   para el histograma, así que no añade una pasada. El desenfoque borra justo esas diferencias.
   ⚠️Se **normaliza por la luminancia total** del fotograma: el AGC sigue trabajando mientras la
   lente se mueve, y sin normalizar un fotograma *más brillante* ganaría a uno *más nítido*.
2. **Algoritmo por escalada** (`src/ipa/simple/algorithms/af.cpp`): la detección por contraste mide
   **cuán bueno** es el punto actual pero nunca **hacia dónde** está el foco, así que hay que
   tantear — paso, comparación con la medida anterior, seguir mientras mejore, y **al empeorar
   invertir y partir el paso**. Empieza con 1/8 del rango y baja hasta 4 unidades.
3. **Camino IPA → lente**: la posición viaja en la **lista de controles del sensor** y el manejador
   la separa hacia el subdispositivo de la lente, igual que hace el manejador de IPU3. El IPA recibe
   los controles de la lente fusionados con los del sensor para poder fijarla.
4. **Reenganche**: si la nitidez cae por debajo del 70 % de la conseguida durante 5 medidas
   seguidas, vuelve a escalar. Con margen de 20 medidas tras asentarse para que no encadene.

## Medido en el móvil

```
511 → 1,32   638 → 1,44   765 → 2,01   892 → 1,82   (empeora → invierte)
829 → 2,06   766 → 2,01   797 → 1,96   782 → 2,11   (mejor)
767 → 1,86   774 → 2,01   781 → 1,75
Autofocus settled at 782 (fom 2,11) after 11 measurements
```

**11 medidas** frente a las 20 del barrido fijo que se probó antes, y **mucho más fino**: aquel solo
podía elegir múltiplos de ~54, este afina hasta la unidad.

## ⚠️ Cuatro sitios donde el control de la lente se perdía (costó cuatro compilaciones)

Cada capa tiene **su propia copia del mapa de controles**:

1. El IPA solo recibía el mapa del **sensor** → hay que fusionarlo con el de la lente.
2. libcamera **verifica con una aserción** que todo control esté en su **tabla de identificadores**
   → hay que fusionar también la tabla. Y se guarda **por puntero**, así que la fusionada tiene que
   vivir como miembro o el objeto queda con una referencia colgante. Sin esto: **SIGABRT**.
3. El IPA **no ejecuta todos los algoritmos compilados**, sino los que lista el fichero de ajuste
   (`src/ipa/simple/data/uncalibrated.yaml`) → hay que añadir `- Af:` ahí.
4. Al **configurar**, el manejador volvía a pasar el mapa del sensor a secas, deshaciendo la fusión
   → ahora usa `SoftwareIsp::sensorControls()`. Sin esto, el algoritmo dice «no hay lente».

## ⚠️ Trampas al probar (todas pagadas)

- **`Failed to start streaming: Permission denied`** = `-EACCES` = la **gestión de energía está
  deshabilitada** en algún dispositivo de la tubería (`runtime_status = unsupported` en
  `/sys/bus/i2c/devices/*/power/`). En este caso era **estado sucio acumulado** de muchas recargas
  de módulo y de una caída de libcamera: **se cura reiniciando el móvil**, no recargando módulos.
- **`WARNING … call_s_stream`** = se llamó a arrancar un subdispositivo **ya arrancado**: tubería
  colgada de un intento anterior abortado.
- **El sensor FRONTAL falla al sondear** con `-5` con cierta frecuencia, y como `camss` espera a
  **todos** los sensores del árbol, el grafo se queda sin enlaces y **libcamera no ve ninguna
  cámara** — el síntoma («no sensor found») no apunta al culpable. Se cura con
  `modprobe -r s5k3t2 && modprobe s5k3t2`.
- El `cam` **no puede capturar si wireplumber tiene la cámara**; hay que pararlo… y **volver a
  arrancarlo al terminar**, o el Bluetooth deja de conectar.
