<!-- Numeración de parches ACTUALIZADA el 2026-08-06 (83 -> 106 parches, serie
     regenerada desde git). Equivalencias en kernel/EQUIVALENCIAS.md -->
# De un postmarketOS limpio al estado actual

Receta lineal para llevar un pmOS recién instalado en surya (Xiaomi POCO X3 NFC, Huaxing) hasta
el estado de hoy: **estéreo L/R, auricular del móvil, llamadas por auricular y manos libres con
su volumen, y llamadas por auricular Bluetooth con el audio por el bus del chip** — todo a la
vez, sin modos.

⚠️ **ESTA RECETA NO SE HA EJECUTADO DE PUNTA A PUNTA.** Está reconstruida a partir del estado
que funciona y de lo aprendido llegando a él. Cada paso está verificado *en su momento*, pero
nadie ha partido de cero siguiéndola. Trátala como la mejor reconstrucción disponible, no como
un procedimiento probado.

**Última actualización: 2026-08-06.** Sustituye a la versión del 2026-08-04, que contenía
**afirmaciones hoy demostradas falsas** — ver §11.

---

## 1. Compilar el kernel

⚠️ **Kernel y módulos SIEMPRE de una sola compilación, e instalar LOS DOS.** Desplegar un
`vmlinuz` nuevo con los módulos viejos da un móvil que **arranca, llega a `greetd` y muere en
silencio a los ~25 s**, sin Oops ni nada en `ramoops`: `CONFIG_MODVERSIONS` está desactivado y
nada detecta el desajuste. Costó media noche creyendo que el árbol estaba roto.

```sh
# En el arbol git (el que genera los parches). Si se quiere un par de PRUEBA
# aparte, usar un `git worktree` y cambiar CONFIG_LOCALVERSION; el checkout
# tarda >5 min en ese disco.
export PATH=/ext_r/ext_edi/src/suria/llvm-shim:$PATH
make LLVM=1 ARCH=arm64 LOCALVERSION= -j8 vmlinuz.efi modules
make LLVM=1 ARCH=arm64 LOCALVERSION= INSTALL_MOD_STRIP=1 \
     INSTALL_MOD_PATH=<staging> modules_install
```

📌 **`LOCALVERSION=` en el entorno es imprescindible** para que la release salga
`7.1.0-rc3-sm7150` limpia: `setlocalversion` añade un `+` salvo que esa variable esté definida.
Un `.scmversion` vacío **no** basta. Si la release lleva `+`, el directorio de módulos no
coincide y estás en el caso de la compilación mezclada.

📌 `INSTALL_MOD_STRIP=1` deja los módulos en ~20 MB en vez de 241 MB (símbolos de depuración).

**Parches**: `kernel/0001–0085`. Imprescindibles para audio+llamadas+BT: `0005`, `0018`,
`0022–0027` (amplis) · `0038`, `0040` (micro) · `0052–0058` (llamada) · `0062` (PCM señuelo) ·
`0063` (wcn3990) · `0064` (trim) · `0095`, `0097` (SCO) · `0078` (`slimbus_dev_id`) · `0079`
(mover la llamada de dispositivo) · `0098` (página del regmap) · `0099` (repetir el cambio) ·
**`0100`** (tarjeta sin Bluetooth si el códec no aparece) · **`0102`** (descarga del NGD) ·
**`0104`** (`laddr_optional`).

⚠️ `0085` **NO existe**: fue revertido (razonamiento invertido, ver §11).

## 2. Desplegar kernel, módulos e initramfs

El initramfs lleva **10 módulos dentro** bajo `usr/lib/modules/<release>/`, así que tiene que
casar con la release. ⚠️ **`mkinitfs` NO sirve para otra versión**: saca la release de
`syscall.Uname`, la del kernel en marcha, y no acepta argumento. Y por defecto ejecuta
`boot-deploy`, que **regenera `/boot`** — si se usa, siempre con `-no-bootdeploy` y `-d` fuera
de `/boot`.

Para una release distinta a la que corre, construirlo a mano **en el móvil y con `sudo`** (para
conservar propietarios): extraer, renombrar el directorio a la release nueva, sustituir los
`.ko.zst` y los `modules.*`, y reempaquetar con `cpio -o -H newc | gzip`.

**Verificar siempre la suma del artefacto INSTALADO**, no dar por bueno el comando: un `scp`
cuya salida pasa por `tail` enmascara el fallo, y `/tmp` del móvil se vacía al reiniciar.

## 3. Red de seguridad de arranque — ANTES de probar kernels

Sin esto, un kernel malo obliga a recuperación física por USB.

```
/boot/loader/loader.conf                 timeout 20 · default pmos.conf
/boot/loader/entries/pmos-respaldo.conf  linux vmlinuz-respaldo + initramfs-respaldo
/boot/vmlinuz-respaldo, /boot/initramfs-respaldo   copias de un par que arranca
```

📌 Generar la entrada de respaldo **con `sed` desde la original**, nunca a mano: la línea
`options` lleva parámetros que un tecleo torpe convierte en bootloop.

📌 Nombres **estables** (`-respaldo`), para que ningún despliegue futuro los pise.

⚠️ **`bootctl set-oneshot` NO funciona**: `efivarfs` está en solo lectura (la EFI de u-boot no
permite escribir variables en ejecución). La alternativa es mejor: dejar el predeterminado en el
kernel bueno y **elegir la entrada de prueba a mano en el menú** — si se cuelga, el siguiente
arranque vuelve solo.

⚠️ Tras consolidar un kernel nuevo, **el anterior deja de ser respaldo válido** (sus módulos han
sido sustituidos): el respaldo debe apuntar a un par kernel+módulos **autónomo**.

## 4. Firmware del chip Bluetooth — de FÁBRICA

`bluetooth-call/firmware-fabrica/{crnv21.bin,crbtfw21.tlv}` → `/lib/firmware/qca/`.

En los QCA **el transporte de audio se elige en el NV**: el genérico de linux-firmware dice
"HCI" y con él ningún código correcto puede funcionar. Inocuo para lo demás → permanente.
Señal de que ha entrado el bueno: `Bluetooth: hci0: HFP non-HCI data transport is supported`.

## 5. Módulo fuera de árbol `wcn-bt-slim`

Fuente en `bluetooth-call/wcn-bt-slim/`. Se compila contra el mismo árbol del kernel y **vive
fuera de `/lib/modules`** (en `$HOME/wcn-bt-slim.ko`), con listas negras
(`blacklist-wcn-bt-slim.conf`, `slimbus-desactivado.conf`) para que udev no lo autocargue.

Lleva `.laddr_optional = true` (necesita el parche 0104) y **no** el bucle de espera de 20 s.

## 6. Árbol de dispositivos

El DTB **con los enlaces `slim7-rx/tx-dai-link`** → códec `<&bt_audio>`, con MultiMedia3 y
MultiMedia4. Un solo DTB, ya no hacen falta dos.

- `/etc/conf.d/q6voiced` → **`q6voice_device=4`**, siempre.
  📌 Los enlaces slim7 son *backend*: **no consumen número de PCM**. `CS-Voice` se queda en
  `00-04` aunque se desactiven. (La nota antigua de «4 con mm4, 3 sin él» era incorrecta.)
- Gracias a **0100** la tarjeta **ya no depende** del códec Bluetooth: si no aparece en
  `bt_deadline_ms`, desactiva los enlaces slim7 y se registra igual.
  `/etc/modprobe.d/sm8250-plazo-bt.conf` → `options snd_soc_sm8250 bt_deadline_ms=15000`.
- 📌 Los 18 controles `SLIMBUS_7_*` los crea **`q6routing`**, no el driver de la tarjeta, así
  que el UCM con dispositivo Bluetooth **no revienta** aunque los enlaces se desactiven.

## 7. `bootmac` — es NECESARIO

El chip **declara una dirección Bluetooth inválida** (`XX:XX:XX:XX:XX:XX`) y el kernel lo marca
«sin configurar». `bootmac` le pone una pública generada del `machine-id` (`MAC_PREFIX=0200`) y
eso completa la transición a «configurado». Sin él, `ACL MTU 0:0` y la init HCI no corre.

Es estándar de pmOS: **no tocarlo, no desactivarlo**.

## 8. ★ Orden de carga — INVERTIDO respecto a la versión anterior

`bluetooth-call/scripts/armar-audio-sistema.sh` → `/usr/local/sbin/`, lanzado por
`armar-audio.service` **tras `multi-user.target`** (nunca en arranque temprano: colgaba el móvil).

```
1) slim_qcom_ngd_ctrl          el bus PRIMERO
2) insmod wcn-bt-slim.ko       el codec, con el chip aun sin firmware
3) hci_uart hfp_offload=1      el Bluetooth el ULTIMO
4) snd_soc_sm8250              el audio
```

★ **Por qué el Bluetooth va el último**: el códec tiene que estar **enlazado al bus antes** de
que el firmware encienda el chip, para estar ahí cuando este se anuncie. Con el Bluetooth
primero, el chip se anuncia sin nadie escuchando y **no vuelve a hacerlo** → nunca enumera.
Esto **solo es viable con el parche 0104**: antes, enlazar el códec pronto devolvía
`-EPROBE_DEFER` y derribaba el componente ASoC sin parar.

⚠️ **NO forzar `hciconfig hci0 up`.** Competía con `bootmac`: este pone la dirección y encola el
`power_on` que completa la transición, pero ese `power_on` fallaba con `-EALREADY` porque el
guion ya había abierto el dispositivo. Y `hci_power_on()` retorna al primer error, así que
**nunca limpiaba `HCI_RAW` ni anunciaba el controlador** → `bluetoothctl` decía *«No default
controller available»*. **Solo esperar** a que aparezca `UP RUNNING`.

⚠️ **NO rebotar el bus con `rmmod` si no enumera.** Ese bucle terminaba con `wcn-bt-slim`
descargado y la tarjeta subía sin Bluetooth. Cargar el códec **una vez** y dejarlo: con 0104 se
queda enlazado aunque el chip no responda, y `device_status()` avisa si aparece más tarde.

## 9. Espacio de usuario

| pieza | canónico | destino |
|---|---|---|
| UCM música / llamada | `audio/HiFi.conf`, `audio/VoiceCall.conf` | `/usr/share/alsa/ucm2/Xiaomi/surya/` |
| ★ offload SCO | `bluetooth-call/scripts/54-offload.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| ~~solo HFP (sin A2DP)~~ | `bluetooth-call/scripts/53-solo-hfp.conf` | **YA NO SE USA** — ver abajo |
| perfil BT solo si hay casco | `bluetooth-call/wireplumber-llamada/find-voice-call-profile.lua` | `~/.local/share/wireplumber/scripts/device/` |
| callaudiod (botón con BT) | `audio/callaudiod/0001-*.patch` | binario en `/usr/bin/callaudiod` |
| sostiene el SCO en llamada | `bluetooth-call/scripts/llamada-al-bluetooth.{sh,service}` | `$HOME/` + unidad de usuario |

### ★★ Las DOS propiedades del offload (2026-08-06)

```
monitor.bluez.properties = {
  bluez5.hw-offload-datapath = 1      # dice AL CHIP que el audio va por su bus
  bluez5.hw-offload-sco      = true   # ★ hace que WIREPLUMBER no escriba en el socket
}
```

**Hacen falta las dos y solo teníamos la primera.** La segunda no estaba definida en ningún
sitio; solo aparecía sin asignar en `/usr/share/wireplumber/scripts/monitors/bluez.lua`, donde
decide crear `createOffloadScoNode()` — un loopback con el lado de reproducción en
`node.passive`, que **no escribe en el socket** — en vez del nodo SCO normal.

**Medido con `btmon`, misma llamada y misma captura**: de **331 paquetes `SCO Data TX`/s a
CERO**, con el enlace montado igual y `Data Path: Vendor Specific (0x01)`. Es la firma
documentada de «lo que hace fábrica», reproducida por primera vez, **y el audio del casco se oye
por ese camino**.

### ★★ NO suspender la ruta interna: si no, el DSP se estrella en llamadas Bluetooth

`bluetooth-call/scripts/55-no-suspender.conf` → `~/.config/wireplumber/wireplumber.conf.d/`

Con la llamada en el auricular Bluetooth, la ruta interna del móvil queda ociosa y wireplumber la
suspende a los 5 s (`session.suspend-timeout-seconds`, por defecto). Al volver a montarse, el
ciclo apagado/encendido de los relojes LPASS **hace reventar al servicio AFE del firmware**:

```
clk 780/781/782 -> freq=0            (suspension)
   ...3 s...
q6afe_i2s_port_prepare
clk 780..783 -> 19200000             (reencendido)
PDM: service 'audio_process' crash: 'EX:audio_process:0x2:AfeS:0xbf:PC=0xb002b79c'
remoteproc0: crash detected in adsp: type fatal error
```

y detrás se va el chip del bus, todo da `-110` y **el móvil se reinicia**. Explica el síntoma
«se oye por el casco y de pronto no suena por ningún lado».

📌 **El propio `51-qcom.conf` del sistema trae la perilla, pero COMENTADA.** Se anula desde un
fichero propio (`55-...`) con `session.suspend-timeout-seconds = 0` y `node.pause-on-idle = false`
para los nodos `alsa_*.platform-sound.*`.

⚠️ **El servicio `call-audio-idle-suspend-workaround` NO sirve para esto**: actúa sobre
`module-suspend-on-idle` de PulseAudio, que en este sistema **no existe**. Alguien identificó el
problema en su día y parcheó el sistema de audio equivocado.

✅ **Verificado 2026-08-06**: llamada por Bluetooth con cambios a manos libres y vuelta →
**cero caídas del ADSP**, sin reinicio. El ciclo de relojes que queda es el del desmontaje al
colgar, ya inofensivo.

⚠️ Esto ataca **el disparador, no el fallo**: el bug está en el firmware del DSP, que ante un
ciclo de relojes inesperado revienta en vez de devolver error. Evitamos ponerlo en esa situación
— que es lo que hace la pila de fábrica, que nunca suspende esa ruta.

### El sonido no salta al auricular al conectarlo

**No falta ninguna política de conmutación**: lo que lo impide es una **fijación previa** del
sumidero por defecto. WirePlumber guarda la última salida elegida a mano en
`~/.local/state/wireplumber/default-nodes`:

```
default.configured.audio.sink = alsa_output.platform-sound.HiFi__Speaker__sink
```

y esa fijación **gana sobre la prioridad** (el nodo bluez tiene `priority.session` 1010 frente a
1000 del altavoz, pero da igual). Arreglo: con el auricular **presente**, elegirlo como salida
(`pactl set-default-sink bluez_output.<addr>.1`) → la fijación pasa a apuntarle, y a partir de
ahí se usa cuando está y se cae al altavoz cuando no.

⚠️ Quitar la fijación con el auricular **ausente** no sirve: wireplumber vuelve a escribirla.

⚠️ **Quién la escribe: `callaudiod`** — llama a `pa_context_set_default_sink` (visible en sus
símbolos). Es quien había dejado fijado el altavoz, probablemente al terminar una llamada. Si
tras cada llamada vuelve a hacerlo, el arreglo de fondo sería que restaurase la salida previa al
colgar en vez de dejar el altavoz fijado.

### ⚠️ Los demonios de llamada dejan el sistema configurado para LLAMAR

Patrón de fondo, visto tres veces el 2026-08-06. Nadie devuelve el sistema a estado de *música*
al colgar, y wireplumber **guarda** cada elección, así que el efecto persiste entre sesiones:

| lo que queda mal | quién lo escribe | síntoma |
|---|---|---|
| perfil del auricular en `headset-head-unit-cvsd` | `llamada-al-bluetooth.sh` | al reconectar **no hay sumidero de música**, el sonido se queda en el altavoz y parece que «no salta al Bluetooth» |
| sumidero por defecto fijado | `callaudiod` (`pa_context_set_default_sink`) | no conmuta al conectar el auricular |
| perfil del móvil en `HiFi (Earpiece, Mic)` | `callaudiod` (probable) | al desconectar el Bluetooth cae **al auricular de la oreja** (mono, flojísimo), no al altavoz — se confunde con «no ha cambiado» |

★ **Arreglados (2026-08-06)**, los dos en `llamada-al-bluetooth.sh`:

- **devuelve el auricular a `a2dp-sink` al colgar** → al reconectar entra en perfil de música.
- **autoconmuta al conectar**: cuando aparece un sumidero `bluez_output.*` mueve ahí el
  predeterminado **y los flujos que estén sonando**. Solo en la transición ausente→presente, no
  en bucle: si con el auricular puesto eliges el altavoz a mano, se respeta.
  Interruptor: `touch /etc/bt-no-autoconmutar`.

⚠️ Esto **compensa la causa, no la arregla**: `callaudiod` sigue fijando el altavoz al colgar.
El arreglo de fondo sería que restaurase la salida previa — ya hay un parche propio sobre ese
binario, así que no es terreno nuevo. Queda pendiente. Y sigue abierto que al desconectar el
Bluetooth el móvil caiga a veces al **auricular de la oreja** (mono, flojísimo) en vez de al
altavoz.

📌 Estado guardado en `~/.local/state/wireplumber/`: `default-nodes` (sumidero fijado),
`default-profile` (perfil por dispositivo). ⚠️ Editarlos con el dispositivo **ausente** no sirve:
se reescriben. Hay que elegir la salida/perfil **con el dispositivo presente**.

### Nodos de toma/inyección: DESACTIVADOS

`90-tomas-llamada.conf` debe estar **fuera** de `~/.config/pipewire/pipewire.conf.d/`. El nodo
`hw:0,3` no abre sin su ruta de mezclador puesta y **se lleva por delante todo el contexto de
PipeWire** — que a su vez deja a wireplumber sin arrancar y al Bluetooth sin ningún perfil de
audio registrado. Son de la investigación de inyección, que está aparcada.

### Otras claves que costaron sangre

- El perfil `Voice Call (Bluetooth)` lleva **la prioridad más baja a propósito** (el UCM lo
  anuncia disponible aunque no haya casco); lo eleva el lua **solo si hay un `bluez5`**.
- El enlace SCO debe existir **antes** de que caigan las rutas: el chip solo abre sus puertos
  del bus con SCO en pie. Por eso el servicio aparte, no callaudiod.
- ★ **`53-solo-hfp.conf` YA NO HACE FALTA (2026-08-06)**. Se puso el 3-ago porque registrar
  A2DP mataba el chip; con el offload SCO activo eso ya no ocurre. Retirado y probado: vuelven
  los perfiles **`a2dp-sink` (AAC)** y `a2dp-sink-sbc`, el sumidero pasa a **estéreo 48 kHz**,
  la música se oye bien y el chip queda con **`errors:0`** en ambos sentidos, sin caídas del
  ADSP. Los perfiles de llamada siguen presentes con prioridad baja (5-6 frente a 132-133), que
  es lo correcto: manda A2DP para música y el lua eleva el de manos libres en llamada.
  ⚠️ **Prueba corta**: la degradación histórica era acumulativa («tras varias tandas»), así que
  conviene usarlo unos días antes de darlo por cerrado. Volver atrás es renombrar el fichero y
  reiniciar wireplumber.

### ★ Inventario COMPLETO — nada de esto puede faltar

Auditado el 2026-08-06 contra los dos estados congelados. Si una pieza no está, el móvil
**parece** funcionar hasta que se toca lo que dependía de ella.

| pieza | canónico en `parches/` | destino en el móvil |
|---|---|---|
| kernel + initramfs | se compila (§1) | `/boot/vmlinuz`, `/boot/initramfs` |
| DTB de surya (los dos paneles) | se compila (§1) | `/boot/dtbs/qcom/sm7150-xiaomi-surya-{huaxing,tianma}.dtb` |
| menú de arranque + respaldo | §3 | `/boot/loader/loader.conf`, `/boot/loader/entries/pmos.conf` |
| módulos del kernel | se compilan (§1) | `/lib/modules/7.1.0-rc3-sm7150/` **enteros, de la misma compilación** |
| `wcn-bt-slim.ko` | `bluetooth-call/wcn-bt-slim/` | `$HOME/wcn-bt-slim.ko` |
| firmware BT de fábrica | §4 | `/lib/firmware/qca/crnv21.bin`, `crbtfw21.tlv` |
| UCM música / llamada | `audio/HiFi.conf`, `audio/VoiceCall.conf` | `/usr/share/alsa/ucm2/Xiaomi/surya/` |
| `callaudiod` parcheado | `audio/callaudiod/0001-*.patch` | `/usr/bin/callaudiod` |
| offload SCO (**dos** propiedades) | `bluetooth-call/scripts/54-offload.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| no suspender la ruta interna | `bluetooth-call/scripts/55-no-suspender.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| ★ registro del enganche lua | `bluetooth-call/scripts/56-mantener-voz-bt.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| ★ **enganche lua** | `bluetooth-call/scripts/mantener-voz-bluetooth.lua` | **`~/.local/share/wireplumber/scripts/device/`** |
| sostén del SCO + offload | `bluetooth-call/scripts/llamada-al-bluetooth.{sh,service}` | `$HOME/` + `~/.config/systemd/user/` |
| armado del audio al arrancar | `bluetooth-call/scripts/armar-audio-sistema.sh`, `armar-audio.service`, `armar-audio-usuario.service` | `/usr/local/sbin/` + `/etc/systemd/system/` + `~/.config/systemd/user/` |
| carga diferida (arranque) | `bluetooth-call/scripts/audio-diferido.service` | `/etc/systemd/system/` |
| listas negras y plazos | `99-carga-diferida.conf`, `blacklist-wcn-bt-slim.conf`, `blacklist-bq25980.conf`, `slimbus-desactivado.conf`, `sm8250-plazo-bt.conf` | `/etc/modprobe.d/` |
| dispositivo de CS-Voice | `bluetooth-call/scripts/q6voiced` | `/etc/conf.d/q6voiced` (**`q6voice_device=4`**) |
| rescate y verificación | `armar-todo.sh`, `verify-call-routing.sh`, `capturar-llamada.sh` | `$HOME/` |

**Y dos cosas que no son ficheros a copiar pero rompen el arranque si están mal:**

- `/var/lib/systemd/rfkill/platform-88c000.serial:bluetooth` tiene que valer **`0`**. Con `1` el
  móvil entra en bucle de arranque; ha pasado dos veces.
- Las unidades tienen que quedar **habilitadas**: `armar-audio.service` (sistema) y, de usuario,
  `wireplumber`, `llamada-al-bluetooth` y `armar-audio-usuario`.

⚠️ **La lista viva y con contenido está en `estado/2026-08-06b-bt-completo/` y
`estado/2026-08-06-llamadas-bt/`**, con `restaurar.sh` para comprobar o reponer. Esta tabla dice
*qué* hace falta; esos directorios guardan *el fichero exacto*.

## 10. Verificación

- **Estéreo / amplis**: `audio/scripts/caza-loteria.sh N` — mide con el micro del móvil.
  ⚠️ Regla: tonos ≤30 % de amplitud y ≤20 s, nunca bucles largos.
- **Ruteo de llamada sin llamar**: `audio/scripts/verify-call-routing.sh`.
- **★ Todas las capas durante una llamada**: `~/capturar-llamada.sh` en el móvil → escribe en
  `~/capturas/` (sobrevive a reinicios) con `btmon`, muestreo de `hcitool con` cada 0,5 s,
  dmesg, y registros de usuario. **Criterio objetivo del offload: `SCO Data TX` debe ser 0.**
- **Estado desplegado**: `estado/verificar.sh` compara contra `estado/SUMAS-*.txt`.

## 11. ⚠️ Correcciones a la versión anterior de este documento

Lo que la versión del 2026-08-04 decía y **hoy sabemos falso**:

1. *«El Bluetooth PRIMERO: si `wcn-bt-slim` coge el chip antes, el adaptador queda `DOWN RAW`»*
   → **Es al revés.** El orden correcto es el códec antes que el Bluetooth (§8), y el `RAW` lo
   causaba nuestro propio `hciconfig hci0 up`.
2. *«La tarjeta depende del códec Bluetooth: sin `wcn-bt-slim` no hay audio de ningún tipo»*
   → **Ya no**, gracias a 0100.
3. *«`q6voice_device` sigue al DTB: 4 con MultiMedia4, 3 sin él»* → **Siempre 4**; los enlaces
   slim7 no desplazan la numeración de PCM.
4. *«El UCM con dispositivo BT y un DTB sin SLIMBUS_7 no pueden convivir»* → los controles los
   crea `q6routing`; el acoplamiento es menor.
5. *«El estado terminal del WCN3990 persiste a reinicios y al reset PMIC»* → **No existe.** La
   MAC basura y la init a medias eran síntomas del orden de carga equivocado.
6. *«Un segundo toque recupera siempre la vuelta al casco»* → **Ya no es cierto.**

## 12. Pendiente conocido

- ★ **La vuelta al casco a mitad de llamada sigue muda** (casco ok → manos libres ok → casco
  mudo). **Sobrevive a eliminar el bombeo por HCI**, así que es un problema **independiente** del
  offload — hasta 2026-08-06 estaban confundidos en uno. Refutado con medida: no es el vocproc,
  ni las rutas, ni los canales del bus, ni el SCO viejo ni el fresco. Mientras tanto: **con
  casco, no cambiar de salida a mitad de llamada**; para pasar al altavoz, colgar y rellamar.
- ~~El ADSP se estrella en llamadas Bluetooth~~ → ✅ **RESUELTO** (§9, `55-no-suspender.conf`).
  Era la suspensión de la ruta interna a los 5 s y el ciclo de relojes al remontarla, no el
  cambio de salida. La pista definitiva fue el motivo que reporta el propio DSP:
  `EX:audio_process:0x2:AfeS:0xbf`.
- **Volumen de la llamada en el casco** (el UCM BT no declara `PlaybackVolume`).
- ~~**A2DP desactivado** por `53-solo-hfp.conf`~~ → ✅ **RESUELTO (2026-08-06 tarde)**. Retirado:
  vuelve la música por Bluetooth en estéreo Y la conmutación automática al conectar/desconectar,
  que fallaba **por la misma causa** (`autoconmutar` pedía un perfil `a2dp-sink` inexistente).
  Las llamadas por casco, que dependían de él sin saberlo, las cubre ahora el enganche lua
  `mantener-voz-bluetooth.lua`. Ver `estado/2026-08-06b-bt-completo/MANIFIESTO.md`.
- ★ **NUEVO: las llamadas seguidas por casco se degradan** (1ª bien, 2ª distorsionada, 3ª solo
  ruido). Por HCI está impecable (cinco eSCO, todos CVSD y con éxito) y los parámetros del puerto
  del DSP son idénticos cada vez. **Apagar y encender el Bluetooth lo cura**, y después tres
  seguidas salen bien: el estado que se degrada está en el chip o en la pila HCI.
- **`hci0` fuera de la capa de gestión** ya está resuelto (§8), pero conviene revisar que
  `bluetoothd` empareja bien tras un arranque limpio.
