# ModemManager: parches propios

Dos cosas distintas: las sentencias GSV que el módem no emite (**0002**) y el PIN de la
SIM contra la ranura equivocada (**0003**).

---

# 0003 · El PIN se verificaba contra la ranura 1, y la SIM está en la 2

**2026-08-12.** Tras un reinicio, la SIM pidió PIN y **no había forma de desbloquearla**:

```
Couldn't verify PIN: QMI protocol error (3): 'Internal'
```

Lo que despistaba: **leer del UIM funcionaba** (`Card state: 'present'`, aplicación USIM
viva) y **los intentos no bajaban** — se quedaban en 3 por muchos errores que dieras. Un
PIN incorrecto no se comporta así.

La traza de depuración de ModemManager lo enseña en una línea:

```
<<<<<< TLV: type = "Session" (0x01)   value = 06:00
<<<<<<      translated = [ session_type = 'card-slot-1' ]
```

Y el módem, preguntado por sus ranuras:

```
Slot [1]:  Card state: 'error: no-atr-received (3)'     ← vacía
Slot [2]:  Card state: 'present'                        ← la SIM
```

`card-slot-1` es una **ranura física**, no una sesión de aprovisionamiento. Se le estaba
pidiendo a una ranura vacía que verificara un PIN, y el módem contesta con un `Internal`
genérico que no se parece en nada a un problema de ranura. Las lecturas seguían bien
porque **usan otra sesión** (`primary-gw-provisioning`), y el PIN nunca llegaba a la
tarjeta: por eso el contador de intentos no se movía.

En `src/mm-sim-qmi.c` las **cuatro** operaciones de PIN —verificar, desbloquear, cambiar y
activar/desactivar— llevaban `QMI_UIM_SESSION_TYPE_CARD_SLOT_1` escrito a mano. Los objetos
SIM creados desde la enumeración de ranuras ya saben en cuál están
(`mm_base_sim_get_slot_number`), así que el parche usa ese número. Ranura 0 significa
«desconocida» y conserva el comportamiento anterior.

## Comprobado en el móvil

Antes de escribir el parche, con `qmicli` apuntando a mano a la ranura correcta:

```sh
sudo bash -c 'read -s -p "PIN: " P; echo; \
  qmicli -d qrtr://0 --uim-set-pin-protection=PIN1,disable,"$P",session-type=card-slot-2'
```

Funcionó a la primera, con el mismo PIN que había fallado cuatro veces seguidas. Eso es lo
que convierte la hipótesis en causa.

⚠️ **`sudo` registra la línea de orden entera en el diario**, PIN incluido. De ahí el
`read` en vez de escribirlo en la orden. ModemManager sí lo enmascara (`pin_value = '###'`),
pero `sudo` no.

📌 Esto **no es específico de surya**: le pasa a cualquier equipo con dos ranuras cuya SIM
no esté en la primera. Candidato claro a mandar aguas arriba.

---

# 0002 · Las sentencias GSV que el módem no emite

El módem genera él mismo el NMEA (`NMEA_PROVIDER=0` en el `gps.conf` de fábrica), y en
este SoC **solo emite `$GPGSV` y `$GLGSV`** por muchas constelaciones que esté siguiendo.
En la misma sesión reporta Galileo y BeiDou por la indicación de satélites de QMI LOC
—31 satélites de cuatro constelaciones— pero su NMEA no los lleva. Y el NMEA es lo que
leen las aplicaciones.

El parche **0002** registra ModemManager a ese evento y **construye las sentencias que
faltan** a partir de él. Solo sintetiza lo que el módem se deja: GPS y GLONASS siguen
viniendo del módem, intactas.

## Resultado

```
$GAGSV,1,1,02,21,26,219,,30,43,049,,1*73
```

Sale en el bloque NMEA que publica ModemManager, junto a las del módem. **Ninguna
aplicación hay que tocarla**: es NMEA normal, y el parser de Navius ya lo entiende.

- Galileo → `$GAGSV`, identificador QMI **301-336** → 1-36
- BeiDou → `$GBGSV`, identificador QMI **201-237** → 1-37

Un satélite a la vista pero sin seguir lleva el campo de relación señal/ruido **vacío**,
como hacen los receptores, en vez de un cero que se leería como medida real.

El valor de sistema de BeiDou va escrito como número y no por su nombre, para que esto
siga compilando contra versiones de libqmi cuyo `QmiLocSystem` no lo tenga.

## ⚠️⚠️ TRAMPA: la unidad de systemd va en un SUBPAQUETE

`modemmanager-systemd` es un subpaquete aparte. Al instalar solo `modemmanager` y
`libmm-glib`, apk **eliminó** `modemmanager-systemd` por incompatibilidad de versión y con
él `/usr/lib/systemd/system/ModemManager.service`. El proceso viejo seguía vivo, así que
no se notaba nada… hasta el siguiente reinicio, que habría dejado el móvil **sin módem y
sin datos**.

Al desplegar hay que instalar **todos** los subpaquetes que hubiera:

```sh
apk add --allow-untrusted ./libmm-glib-*.apk ./modemmanager-*.apk \
                          ./modemmanager-systemd-*.apk ./modemmanager-udev-*.apk \
                          ./modemmanager-lang-*.apk
systemctl daemon-reload && systemctl restart ModemManager
```

Y comprobar que la unidad existe: `ls /usr/lib/systemd/system/ModemManager.service`.

## Dos ajustes en la receta de Alpine

- **`$depends_dev` fuera de `makedepends`**: apunta a `libmm-glib` en esta misma versión,
  que es subpaquete de esta receta; pmbootstrap intenta instalarlo antes de compilar y no
  puede, porque es justo lo que se está compilando.
- **`dbus` añadido a `makedepends`**: tres pruebas abortaban con *«Failed to spawn child
  process dbus-daemon»*. Era del entorno, no del código — con `dbus` presente pasan las
  38. Preferible a desactivar las pruebas, que habría tapado un fallo real si lo hubiera.
