# Llamadas por casco mudas: DOS carreras distintas, las dos arregladas

> Xiaomi POCO X3 NFC (`surya`, SM7150) con postmarketOS, PipeWire/WirePlumber 0.5.15 y BlueZ.
> Nada de esto es específico de este teléfono: la carrera del registro HFP puede darse en
> cualquier sistema donde wireplumber se reinicie más de una vez durante el arranque.

**Fecha:** 2026-08-24 · **Estado:** las dos causas encontradas y arregladas

El mismo día aparecieron dos fallos que dan **exactamente el mismo síntoma** —llamada
muda por el casco y `AVISO: sin SCO al activar el offload` en el diario— pero tienen
causas y arreglos distintos. Se distinguen por su alcance:

| | **(a) registro del HFP** | **(b) enganche del SCO** |
|---|---|---|
| alcance | **el arranque entero** | **una llamada suelta** |
| ¿reiniciar el móvil lo arregla? | **no** (se vuelve a echar la carrera) | no aplica |
| se reconoce por | `RegisterProfile() failed` en el **pid vivo** | llamadas buenas y malas **mezcladas** |
| arreglo | `hfp-registrado.service` | reintentos en `llamada-al-bluetooth.sh` |

La parte (a) está abajo; la (b), al final.

## El síntoma

Cinco llamadas seguidas por el auricular Bluetooth salieron mudas. **Reiniciar el
móvil no lo arregló**: las cuatro llamadas posteriores al reinicio fallaron igual.
En el diario:

```
llamada-al-bluetooth: AVISO: sin SCO al activar el offload
llamada-al-bluetooth: AVISO: no se pudo poner headset-head-unit-cvsd (estaba en 'a2dp-sink')
```

…y ese segundo aviso repetido **una vez cada 200 ms**, porque el bucle del guion
lo reintenta sin descanso mientras dure la llamada.

Del lado del kernel, lo que se ve es otra cosa y despista:

```
qcom,slim-ngd qcom,slim-ngd.1: Tx:MT:0x0, MC:0x60, LA:0xce failed:-110
wcn-bt-slim 217:220:1:0: startup: hw rev read -> -110
qcom,slim-ngd-ctrl 62e40000.slim-ngd: Error Interrupt received 0x82000000
```

⚠️ **Ese `-110` no es la avería, es la consecuencia.** El chip solo abre sus
puertos del bus SLIMBus cuando hay un enlace SCO en pie; sin SCO no contesta y
todo lo que se le pregunta expira. Perseguir el SLIMBus aquí es perder el día.

## La causa

El backend nativo de HFP de WirePlumber hace dos cosas **exclusivas** al arrancar:

1. abre un socket RFCOMM a la escucha, y
2. registra en BlueZ los UUID `0000111e` (Handsfree) y `0000111f` (Handsfree AG).

Solo puede tenerlas **una** instancia. La segunda recibe:

```
wireplumber[1472]: spa.bluez5.native: listen(): Address in use
bluetoothd: register_profile() :1.42 tried to register 0000111f-… which is already registered
wireplumber[1289]: spa.bluez5.native: RegisterProfile() failed: org.bluez.Error.NotPermitted
```

Y en este móvil **wireplumber se arranca y se reinicia cinco veces en 40 segundos**
durante el arranque. Medido en un arranque real (2026-08-24, 12:18):

| hora | pid | qué le pasó |
|---|---|---|
| 12:18:02 | 1289 | arranca; BlueZ aún no está |
| 12:18:03 | 1472 | **segundo gestor de usuario** arranca otro |
| 12:18:13 | 1472 | `listen(): Address in use` |
| 12:18:13 | 1289 | `RegisterProfile() failed: NotPermitted` |
| 12:18:21 | 3745 | reinicio; falla igual |
| 12:18:26 | 3827 | reinicio; falla igual ← **este es el que sobrevive** |
| 12:18:40 | 4563 | otro más, del otro gestor |

Dos cosas se suman para provocarlo:

- **Hay dos gestores de usuario de systemd para el mismo uid** (`systemd[1089]` y
  `systemd[1133]`), y cada uno arranca su `wireplumber.service`.
- **`avisar-camaras.sh` reinicia wireplumber a propósito**, 5 s después de que
  `camss-diferido.service` cargue `qcom_camss` — se añadió para que la aplicación
  de cámara viera los sensores.

El resultado: **el que gana la carrera no es el que sobrevive**. Nadie sirve el
HFP. El auricular conecta solo en A2DP, `pactl set-card-profile …
headset-head-unit-cvsd` falla siempre, no hay eSCO, y toda llamada por casco sale
muda **para el resto del arranque**. Y como es una carrera, reiniciar el móvil
tiene tantas papeletas de arreglarlo como de no.

La propia WirePlumber lo dice con todas las letras, y es la línea que más ayuda:

```
spa.bluez5: Properties changed in unknown transport '…/fd0'. Multiple sound server
instances (PipeWire/Pulseaudio/bluez-alsa) are probably trying to use Bluetooth
audio at the same time…
```

## Cómo comprobarlo en 5 segundos

```sh
P=$(pgrep -x wireplumber | head -1)
journalctl --no-pager -b | grep -E "wireplumber\[$P\]:.*(RegisterProfile\(\) failed|Address in use)"
```

Si sale algo, **el wireplumber vivo no tiene el HFP** y las llamadas por casco
saldrán mudas. Si no sale nada, está bien.

⚠️ Hay que acotar al **pid vivo**. Los errores de las instancias muertas son
normales y salen en todos los arranques, incluidos los buenos: mirar el arranque
entero da un falso positivo siempre. Esa fue la primera lectura equivocada.

## El arreglo

Un reinicio limpio de wireplumber, sin nadie compitiendo, lo recupera:

```sh
systemctl --user restart wireplumber     # ⚠️ NUNCA con una llamada en curso
```

Verificado el 2026-08-24: tras el reinicio, 21 endpoints registrados y **cero**
colisiones.

Para que no haya que hacerlo a mano está **`hfp-registrado.service`**, una unidad
de usuario que 90 s después de la sesión gráfica —o sea, detrás de todos los
reinicios del arranque, incluido el de las cámaras— comprueba el pid vivo y, si
perdió la carrera, reinicia wireplumber una sola vez. No es un bucle de sondeo:
una comprobación y a callar.

```
hfp-registrado: el HFP esta bien registrado (wireplumber pid 16443)
```

## Lo que NO era

- **No era el auricular.** Anuncia el UUID Handsfree y BlueZ lo tiene en caché.
- **No era el SLIMBus** ni el `wcn-bt-slim`: los `-110` son aguas abajo del SCO
  que falta.
- **No era la configuración**: `HiFi.conf` y `VoiceCall.conf` del móvil coinciden
  bit a bit con el repo, y los tres perfiles de llamada están con sus prioridades
  correctas (Earpiece 4400 > Speaker 4200 > Bluetooth 4050).
- **No era el offload**: `hci_uart` tiene `hfp_datapath=1` y `hfp_offload=Y`, y
  `main.conf` su `KernelExperimental`.

## Enlaces

- [`bluetooth.es.md`](bluetooth.es.md) — cómo funciona el audio Bluetooth de llamada y el offload por SLIMBus
- [`camss.es.md`](camss.es.md) — por qué existe el otro reinicio de wireplumber, el de la cámara
- [`../device/services/hfp-registrado.sh`](../device/services/hfp-registrado.sh) — el guardián
- [`../device/services/llamada-al-bluetooth.sh`](../device/services/llamada-al-bluetooth.sh) — el que engancha el SCO
- [`../device/power/avisar-camaras.sh`](../device/power/avisar-camaras.sh) — el reinicio que dispara la carrera


---

# (b) Una llamada suelta muda: el enganche del SCO llegaba un segundo antes de tiempo

Con el HFP ya bien registrado seguían saliendo mudas **algunas** llamadas, mezcladas con
otras perfectas. Esa mezcla es la firma: si fuera (a), fallarían **todas** las de ese
arranque.

## La carrera, medida

Llamada que **falló** (17:52) — el casco se saca de la caja con el teléfono ya sonando:

```
17:52:46.8  llamada aceptada; el cvp nace en los puertos INTERNOS (tx 120 / rx 20)
17:52:49.5  el casco APARECE  (input: Soundcore Sport X10)
17:52:55.7  el guion se rinde: «sin SCO al activar el offload»
17:52:56.3  la llamada SE MUEVE al Bluetooth (tx 120 -> 151)   ← UN SEGUNDO TARDE
```

Llamada que **funcionó** (17:57), con el casco ya conectado de antes:

```
17:57:57.6  la llamada se mueve al Bluetooth (tx 120 -> 151)
17:57:58.6  «SCO en pie»                                        ← 1,6 s
```

**No era el casco ni la radio: era el orden.** El guion esperaba el enlace nada más ver
«hay llamada + hay casco», sin comprobar que la llamada estuviera *puesta* en el casco. Y
sin la tarjeta del móvil en el perfil `Voice Call (Bluetooth)` **nadie tiene motivo para
levantar el eSCO**: esperarlo antes de eso es esperar algo que todavía no puede pasar.

Peor: al rendirse **activaba el offload igualmente y se daba por enganchado**
(`cogido=1`) para el resto de la llamada. Con el offload puesto y sin enlace, la llamada
se quedó muda los **2 min 13 s** que duró — aunque el SCO se hubiera podido levantar un
segundo después.

## El arreglo

En `llamada-al-bluetooth.sh`, tres cambios:

1. **Condición nueva `en_bluetooth`**: no se intenta nada hasta que la llamada está de
   verdad en el casco.
2. **No se engancha nada sin SCO.** Antes se activaba el offload a ciegas.
3. **Se reintenta** hasta 5 veces mientras la llamada siga en el casco, en vez de un solo
   tiro con latch permanente.

Como el enganche bloquea el lector de eventos, cada vuelta pregunta al módem por el estado
**real** de la llamada: `LLAMADA` se queda rancia mientras estamos ahí dentro. ⚠️ Eso es
`sudo` + `mmcli`, y solo se hace **ahí**: en su día el guion lo hacía una vez por segundo
—278 invocaciones en 5 minutos— y se notaba en la batería.

⛔ **Lo que NO se ha tocado**: el reenganche automático si el SCO se cae a mitad de
llamada. Esa es la limitación conocida de la cabecera del guion (la vuelta al casco sale
muda aunque todo lo visible esté perfecto), vive en otra capa y ya se investigó a fondo.
Rebotar el perfil ahí solo añadiría trasiego a un enlace que ya está mal.

## ⚠️ La trampa del nombre — casi cuesta cara

El repo tenía **dos guiones llamados `llamada-al-bluetooth.sh`**: el bueno (por eventos de
ModemManager) y uno viejo que sondeaba con `sudo mmcli` cada segundo. Se editó y desplegó
el viejo por error: **64 invocaciones de `sudo mmcli` en 20 s** y **42 s de CPU en 3m39s**,
o sea ~19 % de un núcleo, hasta que se vio en el diario.

Dos cosas lo permitieron, y las dos están cerradas:

- **El fichero que el móvil ejecutaba no estaba declarado en el manifiesto** del árbol de
  replicación. El verificador decía «el árbol y el móvil coinciden» mientras el móvil corría
  un fichero sin copia canónica declarada. Ya está declarado.
- **Había dos ficheros con el mismo nombre.** Ahora hay **uno**.

📌 Lección: el verificador solo comprueba lo que está en el manifiesto. Un fichero que el
móvil ejecuta y el manifiesto no menciona es un punto ciego, no un aprobado.


---

# Segunda vuelta (2026-08-25): la correlación queda probada, y dos arreglos más

## La prueba definitiva de que (a) es lo que es

Cinco arranques seguidos el 25 de agosto, cruzando los errores de registro **del pid
vivo** con lo que hizo el casco:

| arranque | errores del pid vivo | llamadas por casco |
|---|---|---|
| -4 | 0 | bien |
| -3 | 0 | bien |
| **-2** | **2** | **MUDAS** |
| **-1** | **3** | **MUDAS** |
| 0 | 0 | bien |

Cinco de cinco. No hay margen de interpretación.

⚠️ Los cinco reinicios de ese día **no fueron cuelgues**: `systemd-logind` los registra
como `reboot requested from client ... gnome-session`, es decir, pedidos a mano desde el
móvil. Se sintieron como petadas porque el casco no funcionaba y reiniciar parecía lo
razonable — pero reiniciar es justo lo que **no** arregla (a): vuelve a echar la carrera.

## El guardián se rendía en el peor momento posible

`hfp-registrado` era `oneshot` y, si al comprobar había una llamada en curso, hacía
`exit 0`. En los dos arranques que fallaron el usuario estaba **al teléfono peleándose con
el casco** justo en ese minuto, así que el guardián se fue sin tocar nada **las dos veces
que hacía falta**:

```
12:46:57  hfp-registrado: hay una llamada en curso, no toco nada
12:50:59  hfp-registrado: hay una llamada en curso, no toco nada
```

Ahora es vigilancia continua: espera a que se cuelgue y repara entonces. La llamada en
curso se pierde igual, pero la siguiente ya va bien.

⚠️ En reposo cuesta **un `pgrep` al minuto**: mientras el pid de wireplumber no cambie se
reutiliza el veredicto anterior, sin volver a leer el diario ni llamar a `mmcli`.

📌 **Probando el camino de reparación a propósito** (forzando `roto_pid` a decir que sí)
apareció un fallo que la comprobación normal nunca habría enseñado: el tope de reparaciones
**no aguantaba** —llegó a «reparación 5 de 3»— porque cada reinicio crea un pid nuevo, el
pid nuevo se reevalúa y la reevaluación pisaba el estado «rendido». Era un bucle de
reinicios de wireplumber cada minuto contra algo sin arreglo. Corregido y vuelto a probar:
se para en 3.

## El presupuesto del enganche era en intentos, y tenía que ser en tiempo

En una llamada real del 25 a las 16:59 el enganche se comió sus **5 intentos en 4,7 s**:

```
16:59:44.9  aun sin SCO; sigo intentandolo (hasta 5 veces)
16:59:49.6  AVISO: sin SCO tras 5 intentos
16:59:52.1  SCO en pie (intento 1)          ← 2,5 s despues, a la primera
```

La causa: cuando el sumidero del casco **todavía no existe**, la vuelta no espera el enlace
—no hay dónde esperarlo— y cuesta ~1 s en vez de ~4. Contando intentos, un fallo rápido
agota el presupuesto antes de que al casco le dé tiempo a aparecer.

Ahora el presupuesto es **25 segundos**, no 5 intentos, y si no hay sumidero la vuelta
espera igualmente. Medido con el caso peor (todo fallando, sin sumidero nunca): **13
intentos en 26 s**, en vez de 5 en 4,7.


## (b-2) Y una tercera pieza: el eSCO se negocia en la TRANSICIÓN, no en el perfil

Lo aportó el usuario probando en vivo: conmutar a Bluetooth a mitad de llamada **sí**
funciona, pero **el casco tiene que estar en «auriculares» (A2DP), no en «manos libres»**.

La razón, confirmada en el diario del 25 de agosto: las dos llamadas que engancharon a la
primera venían de `a2dp-sink`.

```
16:59:43.6  casco devuelto al camino de voz (estaba en 'a2dp-sink')   →  SCO en pie
17:00:27.9  casco devuelto al camino de voz (estaba en 'a2dp-sink')   →  SCO en pie
```

Si el casco **ya viene en el perfil de voz** —porque una llamada anterior no lo devolvió a
A2DP, o porque el guion se reinició— entonces `pactl set-card-profile … headset-head-unit-cvsd`
es un **no-op**: no cambia nada, no se negocia nada, y no hay eSCO. La llamada sale muda con
absolutamente todo lo visible correcto, que es el peor tipo de fallo.

Arreglo: antes de pedir el perfil de voz, si el casco no está en `a2dp-sink` **se le pasa por
ahí primero**, para que la siguiente sea una transición de verdad.

⚠️ Solo si **no** hay SCO ya en pie: si lo hay, rebotar el perfil lo tiraría — justo lo
contrario de lo que se busca.

📌 Esto explica también por qué la ruta de colgar devuelve el casco a A2DP y por qué eso no
era solo cosmética para que volviera la música: **deja el casco en el estado desde el que la
siguiente llamada puede engancharse**.
