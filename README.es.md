*[English version](README.md)*

# postmarketOS en el Xiaomi POCO X3 NFC (`surya`, SM7150)

Parches y configuración que convierten postmarketOS en el POCO X3 NFC en un teléfono realmente
utilizable: llamadas con audio, datos móviles, cámara con autoenfoque, sensores, GPS, auriculares
Bluetooth y notificaciones que suenan y vibran.

Todo esto se apoya en el fork del kernel [sm7150-mainline](https://github.com/sm7150-mainline/linux)
y en los paquetes del propio postmarketOS. No sustituye a ninguno de los dos: es una capa encima.

> **Léelo antes de empezar:** esto es un porte hecho por afición, no un producto. Tiene aristas, y
> están listadas sin adornos en [Lo que no funciona](#lo-que-no-funciona). Además **no se ha
> verificado de punta a punta sobre una instalación limpia** — ver
> [Estado de estas instrucciones](#estado-de-estas-instrucciones).

## Lo que funciona

| | |
|---|---|
| **Llamadas** | Salientes y entrantes, **con audio en ambos sentidos**, conmutación auricular ⇄ altavoz y volumen propio de cada modo |
| **Datos móviles / SMS** | LTE, datos y SMS |
| **Audio** | Altavoces estéreo con canales correctos, auricular, cascos, ajuste por amplificador |
| **Bluetooth** | Música A2DP, conmutación automática y **llamadas por auricular**, con el SCO descargado al chip |
| **Cámara trasera** | Fotos y vídeo, orientación correcta y **autoenfoque funcionando** |
| **Sensores** | Acelerómetro, luz, proximidad y magnetómetro |
| **GPS** | El motor viene **bloqueado de fábrica** en la NV; aquí se desbloquea de forma persistente |
| **USB OTG** | Modo anfitrión, verificado con una cámara web |
| **Notificaciones** | Sonido **y vibración**, más respuesta háptica al pulsar |
| **Carga** | La batería carga e informa de su nivel, con la bomba de carga BQ25970 en marcha y el límite de corriente subido |

## Lo que no funciona

- **La cámara frontal.** El sensor dice que está emitiendo y el receptor está configurado igual,
  pero no llega ni un paquete. Varias hipótesis están cerradas con medidas (es D-PHY y no C-PHY; el
  número de carriles, su asignación física y la polaridad del multiplexor coinciden con el blob de
  fábrica). Además su I²C falla de forma intermitente, y cuando falla el sondeo **libcamera no ve
  ninguna cámara**, ni siquiera la trasera.
- **La vibración es floja**, incluso al máximo. El motor es lineal y solo rinde en su frecuencia de
  resonancia; es posible que el driver no la calibre.
- **El móvil se cuelga solo de vez en cuando**, una o dos veces por noche, **sin dejar rastro
  alguno** — la firma del perro guardián por hardware. Causa desconocida.
- **La imagen no está calibrada**: el ISP por software no tiene fichero de ajuste para este sensor,
  así que las fotos salen lavadas y con las esquinas oscuras.
- **Zoom**: el driver del sensor expone un solo modo; el firmware de fábrica tiene cinco.
- Bluetooth: volver al auricular a mitad de llamada se queda mudo, y las llamadas seguidas se
  degradan hasta que se apaga y enciende el Bluetooth.
- **Galileo y BeiDou no llegan a las aplicaciones**, así que el cielo se ve solo con GPS y
  GLONASS, y tampoco hay asistencia A-GPS. El módem sí los sigue —preguntándole por QMI
  reporta 31 satélites de las cuatro constelaciones—, pero su NMEA solo lleva `$GPGSV` y
  `$GLGSV`, y el NMEA es lo que leen las aplicaciones. Ver
  [`packages/libqmi`](packages/libqmi) para cómo preguntar, y
  [`tools/qmi-loc-idl`](tools/qmi-loc-idl) para cómo se recuperaron los mensajes.
- **La carga rápida de 33 W de Xiaomi.** La bomba de carga funciona y el límite está subido, pero
  falta el protocolo propietario que desbloquea la potencia alta, así que un cargador de Xiaomi
  entrega solo el ritmo estándar.

## Qué hace falta

- [`pmbootstrap`](https://wiki.postmarketos.org/wiki/Pmbootstrap) con una copia de `pmaports`.
- Un POCO X3 NFC (`surya`) con el gestor de arranque desbloqueado.
- Paciencia con un móvil que se reinicia solo de vez en cuando.

## Generar una imagen

El paquete del kernel es una capa sobre el de postmarketOS. Se copia encima del suyo y se compila
como siempre:

```sh
git clone https://github.com/woodyst/surya-pmos
cd surya-pmos

# 1. Kernel: los 115 parches, la receta y la configuración
PMAPORTS=$(pmbootstrap config aports)
cp kernel/*.patch kernel/APKBUILD kernel/config-* \
   "$PMAPORTS/device/testing/linux-postmarketos-qcom-sm7150/"

# 2. libcamera con autoenfoque. Conserva los parches que ya trae postmarketOS
#    (0001-0003): los nuestros son el 0004 y el 0005, y el APKBUILD los lista todos.
cp packages/libcamera/*.patch packages/libcamera/APKBUILD "$PMAPORTS/temp/libcamera/"

# 3. libqmi con los mensajes de constelaciones GNSS. Opcional: todo lo demás
#    funciona sin él. libqmi no está en pmaports, así que se compila desde temp/.
mkdir -p "$PMAPORTS/temp/libqmi"
cp packages/libqmi/*.patch packages/libqmi/APKBUILD "$PMAPORTS/temp/libqmi/"

# 4. Sumas y compilación
pmbootstrap checksum linux-postmarketos-qcom-sm7150 libcamera libqmi
pmbootstrap shutdown          # ver las trampas de abajo
pmbootstrap install
```

⚠️ **`pmbootstrap checksum` deja su entorno montado**, y la compilación siguiente falla con
*«Failed to umount … /mnt/pmbootstrap/packages»*. Hay que hacer `pmbootstrap shutdown` en medio.

⚠️ **Si un paquete no se recompila**, sube su `pkgrel`: pmbootstrap dice «up to date» y se lo salta.

## Instalarlo en el móvil

### 1. Desbloquear el gestor de arranque

El procedimiento de Xiaomi: cuenta Mi, herramienta Mi Unlock y un periodo de espera de varios días.
No hay atajo, y nada de lo de abajo funciona hasta que esté hecho.

### 2. Averiguar qué pantalla lleva tu móvil

El POCO X3 NFC se vendió con **dos paneles distintos**, Huaxing y Tianma, y cada uno necesita su
propio gestor de arranque y su propio árbol de dispositivos. Si te equivocas, el móvil arranca con
**la pantalla en negro** — no está estropeado, simplemente no muestra nada.

No hay forma fiable de saberlo desde fuera, así que el método práctico es probar: graba uno y, si la
pantalla sigue negra, graba el otro. No afecta a nada más. Con postmarketOS ya en marcha, el propio
móvil lo dice:

```sh
cat /proc/device-tree/model      # → Xiaomi POCO X3 NFC (Huaxing)
```

### 3. Conseguir u-boot

postmarketOS arranca en este SoC a través de u-boot, que a su vez encadena systemd-boot. Las
imágenes ya compiladas las publica el proyecto sm7150-mainline, **una por panel**:

**https://github.com/sm7150-mainline/u-boot/releases**

```
u-boot-sm7150-xiaomi-surya-huaxing.img
u-boot-sm7150-xiaomi-surya-tianma.img
```

### 4. Imágenes vbmeta vacías para desactivar el arranque verificado

Hay que desactivar Android Verified Boot, y para eso hace falta una imagen vbmeta que grabar. No
busques la de fábrica: genera unas vacías con
[`avbtool`](https://android.googlesource.com/platform/external/avb/) (Apache-2.0):

```sh
python3 avbtool.py make_vbmeta_image --flags 2 --padding_size 4096 --output vbmeta.img
cp vbmeta.img vbmeta_system.img
```

### 5. Grabar

Con el móvil en fastboot (**Bajar volumen + Encendido** desde apagado):

```sh
# el gestor de arranque de TU panel
fastboot flash boot u-boot-sm7150-xiaomi-surya-huaxing.img

# los overlays de fábrica del árbol de dispositivos tienen que irse,
# o pelean con el de mainline
fastboot erase dtbo

# desactivar el arranque verificado en las dos particiones vbmeta
fastboot flash vbmeta        vbmeta.img        --disable-verity --disable-verification
fastboot flash vbmeta_system vbmeta_system.img --disable-verity --disable-verification

# la imagen de postmarketOS compilada antes
pmbootstrap flasher flash_rootfs

fastboot reboot
```

### Si algo sale mal

**Mantén pulsados Subir y Bajar volumen a la vez mientras arranca** y u-boot ofrece un menú de
recuperación que incluye **almacenamiento masivo USB**: el móvil aparece en tu ordenador como un
disco y puedes reparar la instalación sin volver a grabar nada. Esto ha salvado este porte más de
una vez.

⚠️ Ten en cuenta que **este móvil no se apaga nunca del todo**: u-boot lo reinicia, incluso desde su
propio menú. No interpretes un reinicio como que no ha llegado a apagarse.

⚠️ postmarketOS se instala en una partición propia y **no borra la partición `vendor` de fábrica**,
que es lo que permite llegar después a los blobs del fabricante (ver [`docs/blobs.md`](docs/blobs.md)).
No la borres.

## Instalar la configuración del dispositivo

Con el kernel no basta: el enrutamiento de audio, las notificaciones y los demonios de llamada
viven en espacio de usuario. En [`device/README.md`](device/README.md) está qué es cada fichero y
dónde va, o se puede usar el guion:

```sh
scripts/install-on-device.sh <nombre-o-ip>
```

## Lo que **deliberadamente** no está aquí

Ningún firmware propietario. Este móvil necesita blobs de sus propias particiones de fábrica
—calibración de audio (ACDB), firmware del DSP, configuración de los sensores de cámara— y esos son
de Xiaomi y Qualcomm, no de este proyecto. **Aquí no se redistribuyen.**

Ya los tienes en tu móvil: postmarketOS no borra la partición `vendor`, así que se leen de ahí.
En [`docs/blobs.md`](docs/blobs.md) se explica cuáles importan y cómo extraerlos del tuyo.

Tampoco están las grabaciones de audio, las trazas de Bluetooth ni los volcados de registros de las
sesiones de desarrollo: llevan voces, direcciones e identificadores, y no hacen falta para
reproducir nada.

## Estado de estas instrucciones

Con toda honestidad: esta capa **funciona**, porque el móvil en el que se desarrolló la usa a
diario, y la serie de parches está verificada —aplica limpia, reproduce el kernel desplegado bit a
bit y compila—. Pero **la receta entera nunca se ha ejecutado desde cero sobre una instalación
limpia de postmarketOS**. Si lo intentas, cuenta con encontrar huecos, y avisa de ellos.

## Licencias

Los parches del kernel son obra derivada de Linux y son **GPL-2.0**. Los de libcamera son
**LGPL-2.1-or-later**, como el proyecto original. Los ficheros de configuración y los guiones se
publican bajo los mismos términos que los proyectos que extienden. Ver [`NOTICE.md`](NOTICE.md).

## Documentación

- [`docs/`](docs/) — notas por subsistema: qué fallaba, cómo se encontró y con qué trampas.
- [`kernel/`](kernel/) — la serie de parches, un commit por arreglo.
- [`tools/qmi-loc-idl/`](tools/qmi-loc-idl/) — decodificador de la tabla de interfaz QMI
  LOC del módem: los 470 mensajes, y los tres que se implementaron en
  [`packages/libqmi`](packages/libqmi).
- [Versión en inglés](README.md).
