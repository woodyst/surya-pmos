# El móvil no dormía nunca

**Xiaomi POCO X3 NFC (surya) · postmarketOS · 2026-08-16**

Este fichero explica un fallo que estuvo semanas escondido detrás de la investigación de
batería, cómo se encontró, y qué se hizo. Se puede leer solo.

---

## El resumen

Durante semanas medimos el consumo en reposo de este móvil y ningún cambio servía de nada.
Apagábamos subsistemas enteros y el consumo no se movía ni un miliamperio.

La razón resultó ser que **el móvil no llegaba a suspenderse nunca**. Ni una vez. Todas las
suspensiones «con éxito» duraban entre uno y tres segundos.

La causa inmediata: la **línea de despertar del UART del Bluetooth** dispara sola en cuanto
el sistema empieza a suspenderse, y el kernel se da la vuelta sin haber dormido.

La solución adoptada: una regla de udev de dos líneas que desactiva esa capacidad de
despertar. Con ella, el móvil suspende de verdad — verificado hasta **602 segundos
seguidos**.

---

## El síntoma, y por qué despistaba tanto

Los contadores de sueño profundo del SoC (`aosd`, `cxsd`, `ddr`) llevaban días clavados a
cero. Eso nos hizo perseguir, uno por uno, a todos los sospechosos de mantener el sistema
despierto. Todos cayeron, y todos **midiendo**:

| sospechoso | resultado |
|---|---|
| el ADSP, que no dormía nunca | dormido el **100 %** del tiempo: **0 mA** de ahorro |
| las interrupciones de audio | de 2.580/s a 330/s: **0 mA** |
| el UFS | clavado despierto el 100 %: **+4 mA reales** |
| el panel | con la pantalla apagada su `ldo18` queda **cortado**, cero usuarios |
| WiFi, módem, radios | 48,8 / 46,1 / 48,2 mA — diferencia de 2,7 mA |
| las aplicaciones del usuario | por debajo de la deriva de la medida |

Seis descartes correctos y ninguna mejora. **Lo que fallaba era la pregunta**: no
buscábamos quién consumía de más, sino por qué un móvil que no puede dormir consume lo que
consume estando despierto.

---

## Cómo se encontró

La pista no fue un contador de consumo sino una **ausencia**. Trazando las fases de la
suspensión con el tracepoint `power:suspend_resume`:

```
1494.790  dpm_suspend begin
1495.977  dpm_suspend end            ← 1,19 s suspendiendo dispositivos
1495.984  dpm_suspend_noirq begin
1495.989  dpm_suspend_noirq end
1495.989  dpm_resume_noirq begin     ← ★ vuelve INMEDIATAMENTE
```

**La fase `machine_suspend` no aparece.** Nunca. Y eso solo ocurre por un camino concreto
del kernel: justo después de `dpm_suspend_noirq` hay una comprobación de
`pm_wakeup_pending()`, y si ya hay un despertar pendiente, se salta el sueño entero y
desanda con `-EBUSY`.

A partir de ahí fue acorralarlo:

1. **Ningún dispositivo** tenía `wakeup_abort_count` ni `wakeup_count` mayor que cero, así
   que no era una fuente de despertar de dispositivo.
2. Quedaba una **interrupción armada**. Este kernel no expone `/sys/power/pm_wakeup_irq`
   (le falta `CONFIG_PM_SLEEP_DEBUG`), así que se pinchó la función con un kprobe:

```
pmirq: (pm_system_irq_wakeup+0x0/0xbc) irq=158
irq 158  ->  msmgpio 41 Edge  88c000.serial:wakeup
```

`88c000.serial` es el UART del Bluetooth (`hci0: Type: Primary Bus: UART`), y `gpio41` es su
línea **RX**, declarada en el árbol de dispositivos como interrupción de despertar por
flanco descendente.

### La prueba que lo cierra

A/B con tramo de control, suspensiones de 60 segundos:

```
base                     →   2 s
sin despertar por el BT  →  61 s     ★
control, reactivado      →   1 s
```

El tramo de control es lo que lo convierte en causa y no en coincidencia: al devolver la
línea, el fallo vuelve.

---

## La solución

`/etc/udev/rules.d/91-bt-uart-sin-despertar.rules`

```
ACTION=="bind", SUBSYSTEM=="platform", KERNEL=="88c000.serial", ATTR{power/wakeup}="disabled"
ACTION=="add",  SUBSYSTEM=="platform", KERNEL=="88c000.serial", ATTR{power/wakeup}="disabled"
```

Escribe `disabled` en el atributo `power/wakeup` del UART. Con eso el núcleo de gestión de
energía deja de armar esa interrupción al suspender, y la suspensión ya no se aborta.

**Por qué dos líneas:** en `add` el atributo `power/wakeup` **todavía no existe** — lo crea
el driver al sondear, con `device_init_wakeup()`. En `bind` ya está. Se ponen las dos porque
el orden depende de si el driver estaba cargado antes, y una regla que no se ejecuta falla
**en silencio**.

### Verificado tras reiniciar

```
power/wakeup del UART BT: disabled      ← la regla se aplica sola
★ DURACION: 47 s de 45
bluetooth: UP RUNNING      audio: 0 [X3] sm8250 - POCO X3
```

Y en una prueba larga, **602 segundos de 600**.

### El coste, y la decisión

El Bluetooth ya no puede despertar al móvil dormido: con el casco puesto, pulsar un botón
con el móvil suspendido no reacciona. **Las llamadas entrantes no se pierden**, porque esas
despiertan por el módem, que es un camino distinto.

Preguntado por ello, el usuario decidió:

> «me da igual que el bluetooth no despierte el móvil. si lo necesito apreto el botón»

📌 Es la **solución adoptada**, no un apaño temporal.

### Cómo comprobarla o revertirla

```sh
# comprobar
cat /sys/devices/platform/soc@0/8c0000.geniqup/88c000.serial/power/wakeup   # -> disabled

# revertir al vuelo, sin tocar ficheros ni reiniciar
echo enabled > /sys/devices/platform/soc@0/8c0000.geniqup/88c000.serial/power/wakeup
```

---

## Lo que NO es, y costó averiguarlo

Dos hipótesis sobre el mecanismo, las dos escritas con detalle, las dos **refutadas
midiendo**. Se dejan aquí porque saber qué no es vale tanto como saber qué es.

### ⛔ No es un flanco falso por remultiplexar el pin

El UART tiene dos estados de pines y el de reposo cambia `gpio41` de función `qup03` a
`gpio`. Encajaba con un problema conocido de esta familia, y se llegó a escribir el parche
**0123**, compilar el kernel **r74** e instalarlo.

No arregló nada. Y la comprobación que lo explica, con kprobes contando durante una
suspensión:

```
mux        0     ← msm_pinmux_set_mux NO SE LLAMA NI UNA VEZ
setwake    2
armwake   17
clearpend  0     ← el código del parche nunca se ejecuta
pmirq      1
```

**No hay remultiplexado.** El parche es inerte en este camino.

### ⛔ No es un enclavamiento dejado por tráfico del Bluetooth

La traza sitúa el disparo **al armar** el despertar:

```
314.549181  setwake  (msm_gpio_irq_set_wake)
314.549683  pmirq irq=158                      ← 502 µs después
```

Eso sugería que el PDC llevaba un flanco enclavado de tráfico anterior del chip BT y que
armarlo lo reproducía. Predecía fallo **intermitente**, siguiendo al tráfico. Medido:

```
tráfico del UART en 20 s de reposo:  0 interrupciones
suspensión:                          falla igual, el 100 % de las veces
```

Con el UART mudo sigue fallando **siempre**. Un enclavamiento por datos habría fallado a
ratos.

---

## Cuánto ahorra, medido

Tres ciclos alternos de 180 s despierto / 180 s suspendido, con la batería asentada
4 minutos antes. La medida útil es `current_avg` del gauge, leída **nada más reanudar**:
durante la suspensión el espacio de usuario está congelado y no se puede muestrear.

```
                  current_avg
suspendido        -32.501   -32.348   -32.196 uA     <- dispersion: 0,9 %
despierto         -64.544   -59.661   -56.152 uA
```

```
suspendido:   32,3 mA gauge   ->  ~81 mA reales
despierto:    60,1 mA gauge   ->  ~150 mA reales
                                   ahorro: -46 %
```

Sobre 5.160 mAh: de **~34 h a ~64 h** en reposo.

⚠️ **El voltaje no sirve a esta escala.** Para la misma condición suspendida dio 3.144, -192
y -64 uV/min. Alternar ciclos y usar `current_avg` era la única forma de sacar el número.

### Confirmado por el camino real (`systemctl suspend`)

La medida de arriba se hizo con `rtcwake`, que se salta systemd. Repetida por el camino que
usa el movil de verdad, con los mismos tres ciclos alternos:

```
                  current_avg
suspendido        -34.790   -34.484   -34.637 uA     <- dispersion: 0,9 %
despierto         -63.324   -60.577   -57.525 uA

suspendido:   34,6 mA gauge   ->  ~86 mA reales
despierto:    60,5 mA gauge   ->  ~151 mA reales
                                   ahorro: -43 %
```

De **~34 h a ~60 h**. Practicamente el mismo resultado que por la otra via (32,3 vs 34,6 mA),
asi que el numero se sostiene con los dos metodos. Y en estos tres ciclos: **0 caidas del
ADSP** y la tarjeta de sonido en pie tras cada despertar.

⚠️ **32 mA es probablemente un techo.** `current_avg` es una media móvil del propio medidor
y se desconoce su ventana; leerla al reanudar puede arrastrar parte del periodo despierto.

📌 Y esto es con `aosd`/`cxsd`/`ddr` **todavía a cero**: es lo que da suspender **sin** que el
SoC entre en su conjunto de sueño profundo. Nueve minutos dormido y el clúster entró en S2
seis veces, **51 ms en total**. La capa 2 sigue entera, y con ella el resto del ahorro.

---

## ⚠️⚠️ CORRECCION IMPORTANTE: `rtcwake` no suspende como suspende el sistema

Durante toda esta investigacion se uso `rtcwake -m mem` para provocar suspensiones. **Escribe
directo en `/sys/power/state` y se salta systemd entero**, con dos consecuencias que
invalidan parte de lo observado:

- **no corren los enganches de `system-sleep`**
- **no se aplican las relaciones `Conflicts=suspend.target` de las unidades**

Y eso importa, porque `hexagonrpcd-adsp-sensorspd.service` declara justo eso:

```
Conflicts=suspend.target
Before=suspend.target
```

O sea que **systemd ya para el servicio de sensores antes de dormir, por su cuenta**. Con
`rtcwake` no se paraba, el proceso de sensores del ADSP se estrellaba
(`err_qdi.c:1040:EX:sensor_process:0x1:frpc_dsp`), y eso se llevaba el audio por delante:

```
wcd937x_codec audio-codec: ASoC error (-16) at snd_soc_component_probe()
snd-sm8250 sound: ASoC: failed to instantiate card -16
```

📌 **Ese estrellon era un artefacto del metodo de prueba, no del camino real.** Comprobado
retirando el enganche y suspendiendo por systemd: **0 caidas del ADSP y el audio intacto**.

📌 **Y el audio NO se puede rearmar** una vez ocurre. Probado uno por uno: re-atar
`snd-sm8250` da `EBUSY`; el codec **no se puede re-atar** (lleva `suppress_bind_attrs`);
recargar `snd_soc_wcd937x` deja el componente igual de `EBUSY`; y forzar los SoundWire a
`on` no sirve porque `62ed0000.soundwire` queda en **`rt=error`** -- el estado de error de
runtime PM del que no se sale sin reiniciar. Misma familia que el `power.runtime_error` de
la camara.

📌 **Para probar la suspension como ocurre de verdad:**

```sh
echo 0 > /sys/class/rtc/rtc0/wakealarm
echo $(( $(cat /sys/class/rtc/rtc0/since_epoch) + 40 )) > /sys/class/rtc/rtc0/wakealarm
systemctl suspend -i
```

## ✅ Pero si aparecio un fallo real: los sensores no vuelven

Systemd para `hexagonrpcd-adsp-sensorspd` antes de dormir y **nadie lo vuelve a arrancar**.
Queda `inactive` indefinidamente, y con el se van los sensores del ADSP.

Arreglo: `energia/50-sensores-adsp`, enganche `post` de `system-sleep`.

⚠️ **Solo la parte `post`.** Un enganche `pre` seria redundante: ya lo para systemd.

⚠️ **Y no vale llamar a `systemctl start` desde el enganche**: corre DENTRO de la
transaccion de suspension y el arranque queda bloqueado por ella. Probado -- el log decia
"rearrancados" y el servicio seguia `inactive`, incluso metiendo un `sleep` antes. Hay que
lanzarlo fuera con `systemd-run --on-active=5`.

Verificado en dos ciclos: `sensorspd=active` tras cada despertar y la tarjeta de sonido en
pie.

---

## Lo que queda abierto

1. **La causa raíz.** El flanco se entrega al armar, de forma determinista, con la línea en
   reposo y sin tráfico. Lo que queda por mirar es la configuración del **disparo**
   —polaridad y tipo de flanco— en el TLMM y en el PDC, que exige leer registros a mano.
   `sm7150_tlmm` lleva además `wakeirq_dual_edge_errata = true`, otra erratum conocida de
   esta familia sobre GPIOs de despertar enrutados por el PDC.

2. **La segunda capa del sueño profundo — ya con culpable identificado (2026-08-16).**

   ⚠️ **Corrección**: se afirmó aquí que «nunca se envía un mensaje `[sleep]` o `[wake]`».
   **Era falso**, y venía de trazar en reposo y con `rtcwake`. Durante una suspensión real
   sí se envían — pero **solo dos**:

   ```
   494 [active]   ·   2 [wake]   ·   2 [sleep]
   ```

   El conjunto de sueño está **casi vacío**: dos recursos con voto de sueño frente a una
   quincena votados activamente. Casi todo conserva su voto activo al dormir.

   Y la causa concreta, medida trazando `rpmhpd` durante una suspensión por systemd:

   ```
   cx/mx ANTES:   mx 256   cx 256
   cx/mx DESPUES: mx 256   cx 256
   rpmhpd_set_performance_state:  0 llamadas en todo el ciclo
   ```

   **Los votos de `cx` y `mx` no se bajan nunca**, ni durmiendo. Y sus consumidores tienen
   nombre:

   ```
   cx  on  256
       88c000.serial   active   256   <- UART del Bluetooth
       a88000.serial   active    64   <- UART de consola (por stdout-path del DT)
   mx  on  256  <- sigue a cx
   ```

   📌 **Es el mismo dispositivo que bloqueaba la capa 1.** `hci_qca` mantiene el puerto del
   Bluetooth abierto de forma permanente, el UART nunca se suspende, y su voto de rendimiento
   sobre `cx` sobrevive a la suspensión. Mientras `cx` este votado, el riel no colapsa y
   `cxsd` no puede ocurrir.

   ★ **Comprobado con kprobe ANTES de escribir nada** (2026-08-16), que es la leccion que
   costo una compilacion esta manana. Sondas sobre las cuatro rutas del driver mas las de
   recursos de geni y el voto de genpd, durante una suspension por systemd:

   ```
   susp     2     <- qcom_geni_serial_suspend SI corre, una vez por UART
   resu     2
   rtsusp   0     <- el de runtime NUNCA (el puerto esta abierto por hci_qca)
   rtresu   0
   resoff   1     <- geni_se_resources_off, 2 s ANTES, no desde la suspension
   reson    3
   perf     0     <- dev_pm_genpd_set_performance_state: CERO
   ```

   ```
   3159.140948  qcom_geni_serial_suspend      <- corre
   3159.142213  qcom_geni_serial_suspend      <- el segundo UART
   3159.162430  machine_suspend begin
   3159.173284  qcom_geni_serial_resume
   ```

   📌 **El callback SI se ejecuta. Lo que no hace es soltar el voto de rendimiento.** Cero
   llamadas a `dev_pm_genpd_set_performance_state` en todo el ciclo, y `geni_se_resources_off`
   tampoco se llama desde ahi. `qcom_geni_serial_suspend()` suspende el puerto pero deja
   puesta la peticion sobre `cx`. Y como el puerto esta abierto de forma permanente por
   `hci_qca`, el camino de *runtime* suspend -- que si apaga recursos -- no corre jamas.

   ⚠️⚠️ **NO descargar `hci_uart` en caliente para bajar el voto: CUELGA EL MOVIL.**
   Probado el 2026-08-16 y el resultado fue un **cuelgue seco** -- sin panico, sin informe de
   tarea colgada y **sin nada en el ramoops**: el diario se corta a mitad de actividad normal
   y reinicia el perro guardian por hardware. Coherente con lo que ya se sabia del WCN3990,
   que es combo WiFi+BT. (La instrumentacion de cuelgues hizo su trabajo: el movil volvio
   solo en un minuto.)

   ⏳ Para probar `cx = 0` sin tocar el chip en caliente quedaria **no cargar `hci_uart` en
   el arranque** (lista negra de modulos) y medir ahi. Tiene su propio riesgo en este movil.

   ### ⛔ Y SIN EMBARGO NO ERA ESO (2026-08-16, medido)

   Antes de escribir ningun parche se quito el voto **de verdad** y se midio. Para llegar
   ahi hubo que descubrir que **hay DOS cargadores del Bluetooth**, no uno:
   `audio-diferido.service` y `armar-audio.service` (que ejecuta `armar-audio-sistema.sh`,
   con un `modprobe --ignore-install hci_uart` que se salta cualquier `install` de
   modprobe.d). Los dos primeros intentos fallaron **en silencio** por esto.

   Con `armar-audio.service` apartado y la precondicion verificada (`hci_uart` = 0, `hci0`
   inexistente):

   ```
   88c000.serial   suspended   voto 0     <- confirmado: el UART del BT era el 256
   a88000.serial   active      voto 64
   cx  256 -> 64
   suspension de 45 s -> aosd=0 cxsd=0 ddr=0
   ```

   Y desatando ademas el UART de consola, hasta dejar **cero consumidores con voto**:

   ```
   cx = 0     (ni un solo voto pendiente)
   suspension de 45 s -> aosd=0 cxsd=0 ddr=0
   cluster S2: Time 21 ms  Usage 3
   ```

   📌 **Con `cx` a cero y sin ningun voto, el conjunto de sueno SIGUE sin activarse.** Los
   votos de los UART eran reales y estaban ahi, pero **no son el bloqueo**. La causa de la
   capa 2 sigue sin encontrar.

   ✅ Lo que si funciono: **esto costo unos reinicios y ninguna compilacion**. Es la
   disciplina que fallo por la manana con el parche 0123, y aqui evito escribir un segundo
   parche inutil.

   📌 **El hueco esta acotado pero NO es la causa**, esta vez con la
   comprobacion hecha por delante. Los unicos consumidores con voto distinto de cero sobre
   `cx` son los dos UART (256 y 64), asi que soltarlos lo llevaria a 0.

   (Nota suelta: el UART de consola esta activo por `stdout-path = serial0:115200n8` del
   arbol de dispositivos, que deja `ttyMSM0` como consola registrada — **no** por haber
   quitado `quiet`.) Ya suspendido de verdad diez minutos,
   `aosd`/`cxsd`/`ddr` **siguen a cero** y el clúster entra en su estado más profundo un par
   de veces y por milisegundos. Pista concreta sin explotar: en ninguna traza aparece un solo
   mensaje de RPMh de tipo `[sleep]` o `[wake]`; todos son `[active]`.

3. ✅ **RESUELTO: cada despertar queda anotado con su causa** (kernel r75 + enganche
   `energia/60-log-despertar`). El r75 compila `CONFIG_PM_SLEEP_DEBUG`, que crea
   `/sys/power/pm_wakeup_irq`; el enganche lo lee al despertar y lo anota **resuelto a
   nombre y dispositivo**. Verificado con el caso real:

   ```
   journalctl -t despertar
   -> irq=20: pmic_arb 6365403 Edge pm8xxx_rtc_alarm
   ```

   Con esto, cuando un despertar espurio aparezca, el subsistema responsable estara en el
   diario sin tener que instrumentar nada.

4. **Que el botón de encendido despierte de la suspensión.** `pwrkey` figura como fuente de
   despertar, pero **no se ha probado**, y ahora es la vía de vuelta del usuario.

4. **Rehacer las medidas de consumo**, que todas se tomaron con un móvil que no podía
   dormir.

---

## Lecciones de método, que aquí se pagaron caras

**Dos instrumentos no existían y leí su silencio como dato.**
`/sys/power/pm_debug_messages` y `/sys/power/pm_wakeup_irq` no están en este kernel. Llegué a
concluir «`pm_wakeup_irq` está vacío, luego no es una interrupción armada» — y era
exactamente una interrupción armada. **Comprobar que el fichero existe antes de interpretar
su ausencia.**

**Compilé e instalé un kernel entero sobre una hipótesis sin verificar.**
La comprobación que la tumbó —contar con un kprobe si la función parcheada llega a
llamarse— cuesta dos minutos y podía haberse hecho antes. **Antes de parchear una función,
comprobar que esa función se ejecuta en el camino que te importa.**

**Una correlación del 100 % puede ser la señal de que estás mirando un síntoma.**
La expiración de GeoClue2 correlacionaba 8 de 8 con el atasco de `gsd-color`, y resultó ser
consecuencia, no causa. Aquí pasó lo mismo con varias pistas.

**El tramo de control no es opcional.**
Casi todos los resultados de esta investigación se sostienen porque al deshacer el cambio el
fallo vuelve. Sin ese tercer tramo, media docena de conclusiones habrían sido deriva
disfrazada de mejora.
