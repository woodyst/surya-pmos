# Suspensión y votos de energía en SM7150 mainline — lo que encontramos

**Equipo:** Xiaomi POCO X3 NFC (`surya`, SM7150 / sm6150-family) · postmarketOS ·
kernel **7.1.0-rc3** del fork `sm7150-mainline`, con serie propia de parches.
**Fechas:** agosto de 2026. **Todo lo que sigue está medido**, y donde no, lo digo.

> ## ⚠️ AVISO ANTES DE NADA
>
> Este kernel **sigue teniendo un problema de suspensión abierto**, distinto de los que se
> resuelven abajo: la **suspensión en tiempo de ejecución de IPA** (el camino de datos del
> módem) se cuelga de vez en cuando y, con `hung_task_panic=1`, el móvil **reinicia solo**.
> Cuatro pánicos en una tarde bajo uso intenso del módem. Está en la §7 y **no tiene arreglo
> todavía**. Si copias algo de aquí, copia también esta advertencia.

---

## 1. Resumen para quien tenga prisa

| lo que parecía | lo que era |
|---|---|
| «el SoC no entra en sueño profundo, los votos de RPMh están mal» | **el móvil no se suspendía NUNCA**: una línea de despertar abortaba todas las suspensiones antes de empezar |
| «el ADSP no duerme, por eso gastamos» | el ADSP **no era el problema**: con él dormido el 100 % gasta *más* (39 mA vs 37) |
| «la DDR está votada al máximo, será el gobernador» | un proveedor de interconexión **nunca ejecutaba `sync_state`** porque su único consumidor pendiente estaba en lista negra |
| «los contadores `aosd`/`cxsd` a cero prueban que el hardware no duerme» | el contador no miente, pero **el reloj de traza se congela** en la suspensión y despistaba la lectura |

**Ahorro medido al final: −46 %** en reposo (de ~34 h a ~64 h de autonomía), más **−22 mA**
por arreglar los votos de la interconexión.

---

## 2. Cómo medir sin estropear la medida

Esto es lo primero, porque **el instrumento fue el problema cuatro veces**. Si tu medida no
cuadra, sospecha del instrumento antes que del móvil.

- ⚠️⚠️ **`clk_summary` NO es pasivo.** Leerlo **enciende** los relojes que estás midiendo. Usa
  `clk_enable_count`.
- ⚠️⚠️ **El reloj de traza «local» se congela durante la suspensión.** Una traza tomada con él
  parece decir que el hardware no duerme. Con `trace_clock=boot` se ve que **sí llega** al sueño
  de RPMh.
- ⚠️⚠️ **La sesión SSH bloquea el sueño** (`sleep-inhibitor`, complemento `ssh-session-open`) y
  además despierta la CPU en cada sondeo. Si mides por SSH, estás midiendo otra cosa.
- ⚠️ **El voltaje no sirve** a esta escala: para la misma condición suspendida dio +3.144, −192
  y −64 µV/min. Usa `current_avg` del gauge, que se actualiza cada ~75 s.
- ⚠️ **`systemctl suspend` devuelve el control ANTES de que la suspensión empiece.** Un `sleep`
  detrás abarca la suspensión *y* 15-20 s de móvil despierto, y lees el valor rancio de antes de
  dormir. Lo correcto: un bucle que anote `uptime` + `current_avg` cada 5 s; los procesos se
  **congelan**, así que la primera muestra tras descongelar es la lectura más temprana posible y
  el hueco en `uptime` marca la suspensión sin depender de temporizar nada.
- ⚠️ **Pon siempre un tramo de control** en el A/B, o confundirás deriva térmica con mejora.
  Sin control salieron «ahorros» de −423, −65, −107 y −50 mA para la misma condición.
- ⚠️ **El gauge informa 2,24× menos** de la corriente real. El factor está **medido**, no
  heredado: descarga completa (`5160 mAh / 2307,9 mAh = 2,24`) y corroborado por un segundo
  camino independiente (`1093/489 = 2,24`). Derivación en `energia/datos-calibracion/`. Todas
  las cifras «de gauge» de este informe son **sin corregir**: sirven para comparar entre sí, no
  como consumo absoluto.

Método general: **ciclos alternos** (p. ej. 180 s despierto / 180 s suspendido) × 3, con la
batería asentada 4 minutos antes, y mirar la **dispersión**: la nuestra quedó en 0,9 %.

---

## 3. Hallazgo principal: el móvil no se suspendía NUNCA

`gpio41` es la línea RX del UART del Bluetooth (`88c000.serial`) y lleva su **interrupción de
despertar dedicada** (irq 158, flanco descendente, enrutada por el PDC — `{41,101}` en el mapa
del sm7150).

Medido: el flanco se entrega **~500 µs DESPUÉS de `msm_gpio_irq_set_wake()`**, es decir **al
armarla**. El kernel encuentra `pm_wakeup_pending()` ya cierto nada más terminar
`dpm_suspend_noirq` y sale con **`-EBUSY` sin dormir ni un microsegundo**. La fase
`machine_suspend` no llega a existir.

A/B con tramo de control, suspensiones pedidas de 60 s:

```
con despertar   ->   2 s
sin despertar   ->  61 s      (y 602 s en una prueba de 10 minutos)
control, con    ->   1 s
```

**Arreglo** (regla udev):

```
ACTION=="bind", SUBSYSTEM=="platform", KERNEL=="88c000.serial", ATTR{power/wakeup}="disabled"
ACTION=="add",  SUBSYSTEM=="platform", KERNEL=="88c000.serial", ATTR{power/wakeup}="disabled"
```

Revertir es inmediato:
`echo enabled > /sys/devices/platform/soc@0/8c0000.geniqup/88c000.serial/power/wakeup`

**Coste**: el Bluetooth ya no puede despertar al móvil dormido (p. ej. un botón del casco). Las
llamadas entrantes **no se pierden**: esas despiertan por el módem, que es otro camino.

⚠️ **La causa de fondo sigue sin identificar**: por qué el flanco se entrega al armar la
interrupción. Dos hipótesis ya **refutadas midiendo**:
- *remultiplexado del pin* → no hay: `msm_pinmux_set_mux` se llama **0 veces**;
- *enclavamiento rancio por tráfico del BT* → el UART pasa 20 s con **0 interrupciones** y la
  suspensión falla igual, el 100 % de las veces.

Queda por mirar la configuración del disparo (polaridad / tipo de flanco) en el TLMM y en el
PDC, que exige leer registros.

**Resultado**, tres ciclos alternos por el camino real (`systemctl suspend`):

```
                  current_avg (gauge)
suspendido        -34.790   -34.484   -34.637 uA      <- dispersión 0,9 %
despierto         -63.324   -60.577   -57.525 uA
                                       ahorro: -46 %
```

Sobre 5.160 mAh: de **~34 h a ~64 h** en reposo.

---

## 4. Los votos: `sync_state` que nunca se ejecuta

Este es el que probablemente te interesa si vienes por «los votos de la suspensión».

**Síntoma**: la DDR y los NoC mantienen el **voto inicial `0x7FFFFFFF`** (el máximo) desde el
arranque y **de por vida**. `ebi` en su valor tope, consumo alto en reposo, y nada en el
registro que lo explique.

**Causa**: el marco de `sync_state` de Linux solo llama a `.sync_state()` de un proveedor
cuando **todos** sus consumidores han sondeado. Cuatro proveedores de interconexión tenían un
único consumidor pendiente: **`ace0000.camss`** — que nosotros teníamos en **lista negra**
porque `qcom_camss` cuelga el móvil si udev lo carga en el arranque temprano. Mientras ese
módulo no sondea, `qcom_icc_sync_state` no corre, y el voto inicial máximo no se retira jamás.

```
sin sincronizar:  6/10 proveedores    ebi avg = 2149016551
con camss:       10/10 proveedores    ebi avg = valor real
```

**Arreglo**: cargar `qcom_camss` **diferido**, 10 s después de `multi-user.target`, en vez de
por udev. Con el sistema asentado entra siempre y no cuelga.

Medido en reposo despierto con pantalla apagada y tramo de control:

```
sin sincronizar: -70,6 / -74,8 / -69,4 mA de gauge
sincronizado:    -60,7 mA de gauge
```

→ **9-14 mA de gauge ≈ 22-35 mA reales.**

⚠️ **Trampa al aplicarlo**: que el servicio diferido cargue camss **y nada más**. Si arrastra
los sensores de cámara o el VCM (`dw9807_vcm`), **reintroduces el fallo de la §5** y vuelves a
quedarte sin suspensión — arreglado un problema, creado otro, y el mensaje aparecerá lejos de su
causa. Verificado con camss cargado a solas: **5 de 5 suspensiones entraron** (15-20 s), 0 fallos.

### Cómo encontrar al consumidor culpable

Lo útil no es saber que nos pasó a nosotros con camss, sino cómo localizar **tu** consumidor
pendiente. Los enlaces que se quedan en `available` (en vez de pasar a `active`) son los que
nunca sondearon:

```sh
# 1) ¿qué proveedores no han sincronizado?
for f in /sys/devices/platform/soc@0/*interconnect/state_synced; do
    echo "$(basename $(dirname $f)) $(cat $f)"
done

# 2) ¿a quién están esperando?
for d in /sys/class/devlink/*/; do
    [ "$(cat $d/status 2>/dev/null)" = available ] && basename "$d"
done
```

El segundo comando te da parejas `proveedor--consumidor`. El consumidor que aparece ahí y no
tiene driver cargado es el que bloquea la sincronización.

### ⚠️ Un segundo caso que quizá también tengas: uno SIN arreglo

En este mismo equipo, GCC y GPUCC **no sincronizan en ningún arranque**, y no por una lista
negra:

```
platform:100000.clock-controller--platform:506a000.gmu           -> available
platform:5090000.clock-controller--platform:506a000.gmu          -> available
```

`506a000.gmu` **no tiene driver propio por diseño**: el driver `adreno` se apropia del nodo con
`of_find_device_by_node()` **sin enlazar un driver**, así que su `devlink` se queda en
`available` para siempre. La GPU funciona —`/dev/dri/card0` existe—; es el modelo de enlaces el
que se queda colgado, y con él el `sync_state` de dos controladores de relojes, que es lo que
apagaría los relojes no reclamados. **No le encontramos arreglo.**

📌 **La lección general**: si tienes un módulo en lista negra —o un nodo del que alguien se
apropia sin enlazar—, comprueba si algún proveedor lo está esperando para sincronizar sus votos.

⚠️ Probamos `fw_devlink.sync_state=timeout`, que es el parámetro que el kernel ofrece justo para
esto (forzar `sync_state` pasado un plazo), y **provocó un bucle de arranque**. No lo
recomendamos en este SoC.

---

## 5. Un driver que abortaba todas las suspensiones

El VCM de la cámara (`dw9807-vcm`) **apagaba su regulador dos veces** en la suspensión del
sistema: `SET_SYSTEM_SLEEP_PM_OPS` apuntaba a las mismas funciones que `SET_RUNTIME_PM_OPS`, así
que si el dispositivo ya estaba suspendido en tiempo de ejecución, el segundo apagado devolvía
`-EIO` y **abortaba el ciclo entero**.

```diff
-	SET_SYSTEM_SLEEP_PM_OPS(dw9807_vcm_suspend, dw9807_vcm_resume)
+	SET_SYSTEM_SLEEP_PM_OPS(pm_runtime_force_suspend, pm_runtime_force_resume)
 	SET_RUNTIME_PM_OPS(dw9807_vcm_suspend, dw9807_vcm_resume, NULL)
```

Verificado: 3 de 3 suspensiones con el VCM cargado, frente a 0 de N antes.

📌 **Patrón reutilizable**: cualquier driver que use las mismas funciones para *system sleep* y
*runtime PM* es sospechoso. Un solo `-EIO` en `dpm_suspend` tira la suspensión de todo el móvil,
y el mensaje aparece lejos de su causa.

---

## 6. Lo que descartamos MIDIENDO (y por qué importa)

Perseguimos varias pistas que resultaron falsas. Las dejo escritas para que no las repitas:

- ⛔ **El ADSP.** Parecía culpable (`adsp count=0`, nunca dormía). **Falso**: arrancando sin su
  firmware, `aosd` sigue a 0 — o sea que no era él quien lo impedía. Y medido en positivo: con
  el ADSP dormido el 100 % del tiempo, **39 mA de gauge** (mediana de 30 muestras); con él
  despierto, **37 mA de gauge**. Perseguíamos un contador, no un consumidor.
- ⛔ **Acotar la suspensión de audio**: no ahorra nada (resultado negativo, medido).
- ⛔ **Audio, UFS, panel, WiFi, módem y aplicaciones**: descartados uno a uno con A/B.
- ⚠️⚠️ **NUNCA desates `62b52000.pinctrl` en caliente** para probar: estrella el ADSP y la
  tarjeta de sonido **no vuelve sin reiniciar**.
- ⚠️⚠️ **NUNCA pongas `qcom_q6v5_pas` en lista negra**: deja el móvil **sin WiFi**.

---

## 7. ⚠️ LO QUE SIGUE ROTO EN NUESTRO KERNEL

**La suspensión en tiempo de ejecución de IPA se cuelga.** No es la suspensión del sistema: es
el runtime PM del camino de datos del módem, y ocurre con el móvil en uso.

```
kworker [pm_runtime_work]
  ipa_runtime_suspend            [ipa]
    ipa_endpoint_suspend -> ipa_modem_suspend -> ipa_endpoint_suspend_one
      gsi_channel_suspend -> __gsi_channel_stop
        gsi_channel_trans_quiesce()
          wait_for_completion(&trans->completion)     <- SIN PLAZO
```

`drivers/net/ipa/gsi.c:817`. Espera a la última transacción del canal GSI del módem. Si esa no
se completa, se queda ahí para siempre: `hung_task` salta a los 122 s y —con
`hung_task_panic=1`, que pusimos a propósito para capturar el fallo— **el móvil reinicia**.

Cuatro pánicos en una tarde de uso intenso del módem.

**Dos cosas que parecían pistas y no lo son:**

- **`irq/172-ipa` NO es el culpable**, aunque sale en todas las firmas. `ipa_isr_thread()`
  empieza con `pm_runtime_get_sync()`, que con el dispositivo en `RPM_SUSPENDING` **espera a que
  termine la suspensión** — la que no termina. Es una víctima.
- **IPA y GSI son interrupciones DISTINTAS** (`172 ipa`, `173 gsi`): no es un abrazo mortal
  entre esos dos hilos. Quien debía completar la transacción es GSI.
- **El crash del módem que aparece en algún registro es CONSECUENCIA**: la cuenta de los 122 s
  sitúa el bloqueo **minuto y medio antes** del crash.

**Dónde estamos**: instrumentando con kprobes el bucle
`gsi_isr` → `gsi_isr_ieob` (desactiva la IEOB y programa NAPI) → `gsi_channel_poll` (completa y
reactiva la IEOB), para distinguir si NAPI no llega a correr —y la IEOB se queda apagada para
siempre— o si la transacción está atascada en el hardware.

**Si te pasa lo mismo**, el síntoma que verás es `irq/172-ipa` bloqueado y el móvil reiniciando
o quedándose sin red. No sabemos aún si acotar la espera con `wait_for_completion_timeout` es
seguro: justo después hay un `gsi_trans_free(trans)`, y liberar una transacción viva puede ser
peor que esperar.

---

## 8. Cómo comprobar todo esto en tu equipo

```sh
# ¿se suspende de verdad?
sudo rtcwake -m mem -s 60          # y mirar el hueco en /proc/uptime

# ¿qué aborta la suspensión?
echo 1 | sudo tee /sys/power/pm_debug_messages
sudo dmesg | grep -iE "wakeup|abort|-EBUSY|pm_wakeup_pending"
cat /sys/kernel/debug/wakeup_sources | sort -k3 -n -r | head

# votos de la interconexión
cat /sys/devices/platform/soc@0/*interconnect/state_synced

# contadores de sueño del SoC (necesita qcom_stats)
sudo modprobe qcom_stats
sudo cat /sys/kernel/debug/qcom_stats/*

# consumo: SIEMPRE current_avg, nunca voltaje
cat /sys/class/power_supply/*/current_avg
```

⚠️ Y recuerda: **mide desde el propio móvil, no por SSH**, o la sesión te bloqueará el sueño.

---

## 9. Qué hay en este árbol

| pieza | qué es |
|---|---|
| `energia/91-bt-uart-sin-despertar.rules` | el arreglo principal (§3) |
| `energia/camss-diferido.service` + `scripts/86-camss-diferido.sh` | los votos de la interconexión (§4) |
| `kernel/0124-*dw9807*.patch` | el VCM que abortaba las suspensiones (§5) |
| `kernel/0125-*.patch`, `kernel/0126-*.patch` | compensación de caída óhmica y tabla OCV medida, para que el gauge no mienta |
| `energia/EL-MOVIL-NO-DORMIA.md` | el diagnóstico completo de §3 |
| `energia/CAPA2-CONJUNTO-DE-SUENO.md` | por qué el conjunto de sueño de RPMh parecía vacío y no era el problema |
| `cuelgues/2026-08-22-ipa/` | el problema abierto de §7, con las pilas |
| `ADSP-NO-DUERME.md` | ⛔ documento con la **tesis refutada**; se conserva por el método |

---

*Escrito el 2026-08-22. Si algo de aquí te resulta útil, ten en cuenta que está medido en **un**
equipo: el POCO X3 NFC. El SM7150 downstream se llama `sdmmagpie`/`sm6150-*`; `atoll` es otro
SoC y confundirlos nos costó tres errores.*
