# ★★★ LOS CONGELADOS NO SON IPA: SON EL ALMACENAMIENTO (UFS)

**2026-08-23, 20:10.** El primer cuelgue capturado con la instrumentación completa. Y el
resultado cambia el diagnóstico: **la clase «congelado» no tiene nada que ver con IPA.**

## El abrazo mortal, literal

```
[10199.74] INFO: task kworker/u32:3 blocked for more than 122 seconds.
           Workqueue: devfreq_wq devfreq_monitor
             ufshcd_devfreq_scale → down_write → rwsem_down_write_slowpath
                                                  ↑ quiere el semáforo para ESCRIBIR

[10199.84] blocked on an rw-semaphore likely owned by task kworker/0:1 <reader>

           task kworker/0:1  Workqueue: events ufshcd_exception_event_handler
             ufshcd_exception_event_handler → ufshcd_query_attr_retry
             → ufshcd_query_attr → ufshcd_exec_dev_cmd → blk_execute_rq
             → wait_for_completion_io_timeout
                                                  ↑ esperando al chip UFS

[10199.94] Kernel panic - not syncing: hung_task: blocked tasks
```

1. El **manejador de excepciones del UFS** lanza una consulta al chip y se queda esperándola,
   con el semáforo cogido **como lector**.
2. El **escalado de frecuencia** del UFS (`devfreq`) quiere ese mismo semáforo **para escribir**
   y se bloquea detrás.
3. La consulta **no vuelve**. Y como la raíz del sistema vive en el UFS (`/dev/loop0p2` sobre
   `sda16`), **todo lo que toque disco se queda parado** → el espacio de usuario entero se
   congela.

## Por qué encaja con lo que veíamos

| observación del congelado del 2026-08-23 | explicación |
|---|---|
| espacio de usuario **parado del todo** | la raíz está en UFS: sin disco no se hace nada |
| **kernel vivo y ocioso** (las 7 CPU en `cpuidle_enter_state`) | el kernel no tiene trabajo; solo dos hilos atascados |
| systemd deja de acariciar al perro | tampoco él puede hacer E/S |
| **ningún aviso de `hung_task`** aquella vez | el aviso llega a los 122 s; aquel día se apagó antes |
| pantalla y táctil muertos | el táctil recarga firmware **desde disco** |

## Lo que descarta

⛔ **No es IPA.** En este volcado IPA no aparece en ninguna de las dos pilas bloqueadas. Las 200
menciones de `gsi_channel_stop` son de la **cola de traza de ftrace** que el volcado arrastra —
nuestras sondas, funcionando, y con sus últimas marcas normales (`done:`, `alloc:`).

📌 Son **dos fallos distintos**:
- **pánico por tarea bloqueada en IPA** — los cuatro del 2026-08-22, `gsi_channel_trans_quiesce`;
- **congelado por UFS** — este, y muy probablemente el del 2026-08-23 por la mañana.

## Estado del chip

`SAMSUNG KM2V8001CM-B707`. **Ningún error de UFS antes** del bloqueo: el almacenamiento venía
funcionando con normalidad y de pronto una consulta de atributo no volvió.

## Qué falta por saber

- **Qué excepción** levanta el chip (`ufshcd_exception_event_handler` se dispara cuando el
  dispositivo señala una condición: temperatura, WriteBooster, operaciones en segundo plano…).
- **Por qué la consulta no vuelve**: `wait_for_completion_io_timeout` tiene plazo, así que o el
  plazo es larguísimo o `ufshcd_query_attr_retry` reintenta en bucle.
## ★ Mitigación aplicada: quitar el escalado de frecuencia del UFS

`cuelgues/99-ufs-sin-escalado.rules` pone `clkscale_enable=0` en `1d84000.ufshc`.

**Sin escalado no hay escritor** que pida el semáforo, así que la consulta atascada deja de
arrastrar al resto del sistema: el lector puede seguir bloqueado, pero los demás lectores pasan
y el móvil no se congela.

⚠️ **Es una mitigación, no el arreglo.** La consulta al chip sigue sin volver; lo que se evita
es que eso tumbe el móvil entero.

✅ **Coste comprobado**: el reloj **NO se clava arriba** — se queda en el mínimo (50 MHz), igual
que con el escalado activo, y el disco sigue escribiendo a **604 MB/s**. No debería costar
batería, pero conviene vigilarlo unos días.

Revertir: `echo 1 > /sys/devices/platform/soc@0/1d84000.ufshc/clkscale_enable` y quitar la regla.

## Qué falta por saber

- **Qué excepción** levanta el chip (`ufshcd_exception_event_handler` se dispara cuando el
  dispositivo señala una condición: temperatura, WriteBooster, operaciones en segundo plano…).
- **Por qué la consulta no vuelve**: `wait_for_completion_io_timeout` tiene plazo, así que o el
  plazo es larguísimo o `ufshcd_query_attr_retry` reintenta en bucle.
- Si con la mitigación puesta el móvil **sigue congelándose** — eso diría que el bloqueo del
  lector basta por sí solo y habría que ir a por la consulta.

★ **El perro guardián hizo su trabajo**: `hung_task_panic` disparó a los 122 s, `panic_sys_info`
imprimió las pilas de **las siete CPU**, y ramoops lo conservó entero. Sin esa instrumentación
este cuelgue habría sido otro congelado mudo más.
