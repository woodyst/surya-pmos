# `qcom_camss` en surya — todo en un sitio

`camss` es el subsistema de cámara del SoC, pero en este proyecto **aparece en tres sitios que
no tienen nada que ver entre sí**, y por eso costaba tener la foto completa:

1. **Arranque** — cargarlo por udev **cuelga el móvil**, así que está en lista negra.
2. **Energía** — precisamente *por* estar en lista negra, cuatro proveedores de interconexión
   **nunca ejecutaban `sync_state`** y la DDR se quedaba votada al máximo de por vida.
3. **Cámara** — es lo que hace que haya foto y vídeo.

Este documento junta las tres.

> **Si lo estás leyendo de fuera del proyecto**: las rutas tipo `energia/…`, `scripts/…` o
> `camera/README.md` son ficheros de **nuestro** repositorio y no te hacen falta para entender
> nada — lo que importa (el porqué, las órdenes y las medidas) está aquí. Las rutas del sistema
> (`/etc/modprobe.d/…`, `/sys/…`) sí son las de cualquier equipo.

---

## 1. Por qué está en lista negra

`/etc/modprobe.d/99-carga-diferida.conf`:

```
# La camara arreglada (parche 0080) carga BIEN a mano con el sistema asentado,
# pero en el arranque sigue tumbando el movil: queda fuera hasta aclarar por que.
blacklist qcom_camss
blacklist imx682
blacklist s5k3t2
blacklist s5k3l6xx
```

**El bug que sí se identificó** (parche **0080**): el VFE pedía su interrupción **ya
habilitada** en el `probe`, mucho antes de que nada encendiera el bloque. Su manejador lee
registros del VFE, así que una interrupción pendiente con el dominio de energía apagado leía
registros de un bloque muerto y tumbaba el arranque. **CSID y CSIPHY ya lo hacían bien**
(`IRQF_NO_AUTOEN` + `enable_irq()` al encender); al VFE se le había quedado sin ese trato.

Y el **0107** lo remató: armar la interrupción **antes** del reset, no después.

⚠️ **Aun con los dos parches, cargarlo en el arranque temprano sigue tumbando el móvil.** La
causa de eso **no está identificada**. Con el sistema asentado entra siempre y sin problemas —
de ahí la carga diferida. Que quede claro: la lista negra **no es un resto histórico**, sigue
haciendo falta.

📌 Nota de numeración: documentos antiguos citan este arreglo como «parche 0063». Tras
regenerar la serie desde git, **0063 es otra cosa** (Bluetooth); el del VFE es el **0080**.

---

## 2. La carga diferida, y lo que NO debe arrastrar

`energia/camss-diferido.service`, que despliega `scripts/86-camss-diferido.sh`:

```ini
Description=Cargar qcom_camss tras el arranque (sincroniza la interconexion: ~22 mA menos)
After=multi-user.target armar-audio.service
ExecStartPre=/bin/sleep 10
ExecStart=/sbin/modprobe -q qcom_camss
```

⚠️⚠️ **Carga camss y NADA MÁS.** Nada de sensores (`imx682`, `s5k3t2`) ni del VCM
(`dw9807_vcm`). El VCM **rompía la suspensión**: su `suspend` apagaba el regulador por segunda
vez, devolvía `-EIO` y **abortaba el ciclo entero**. Lo arregla el parche **0124**, pero el
servicio sigue sin cargarlos porque no los necesita para lo que está aquí: sincronizar los votos.

✅ **Verificado**: con camss cargado a solas, **5 de 5 suspensiones entraron** (15-20 s), 0 fallos.

---

## 3. Los votos: por qué un módulo en lista negra costaba 22 mA

**Síntoma**: la DDR y los NoC mantenían el voto inicial `0x7FFFFFFF` (el máximo) desde el
arranque **de por vida**.

**Causa**: `sync_state` solo se llama cuando **todos** los consumidores enlazados de un
proveedor han sondeado. Cuatro proveedores tenían un único consumidor pendiente:
**`ace0000.camss`**. Mientras ese módulo no sondee, `qcom_icc_sync_state` no corre y el voto
máximo no se retira jamás.

```
sin sincronizar:  6/10 proveedores    ebi avg = 2149016551
con camss:       10/10 proveedores    ebi avg = valor real
```

Medido en reposo despierto, pantalla apagada, con tramo de control:

```
sin sincronizar: -70,6 / -74,8 / -69,4 mA de gauge
sincronizado:    -60,7 mA de gauge
```

→ **9-14 mA de gauge ≈ 22-35 mA reales.**

### Cómo se diagnostica

```sh
# ¿qué proveedores no han sincronizado?
for f in /sys/devices/platform/soc@0/*interconnect/state_synced; do
    echo "$(basename $(dirname $f)) $(cat $f)"
done

# ¿a quién esperan? Los enlaces que se quedan en 'available' (y no pasan a 'active')
for d in /sys/class/devlink/*/; do
    [ "$(cat $d/status 2>/dev/null)" = available ] && basename "$d"
done
```

⚠️ **`fw_devlink.sync_state=timeout` NO es la solución**: es el parámetro que el kernel ofrece
justo para esto, y **provocó un bucle de arranque** en este SoC.

📌 **Hay un segundo caso, sin arreglo**: GCC y GPUCC no sincronizan en **ningún** arranque
porque `506a000.gmu` no tiene driver propio **por diseño** — `adreno` se apropia del nodo con
`of_find_device_by_node()` sin enlazar un driver, así que su `devlink` se queda en `available`
para siempre. La GPU funciona; es el modelo de enlaces el que se cuelga. Esto **no** lo arregla
cargar camss.

---

## 4. La parte de cámara

Los parches que hacen que haya imagen (los de `camss`, más uno de los drivers i2c de los
sensores):

| parche | qué hace |
|---|---|
| **0110** | ★ **soporte C-PHY** y cambiar surya a C-PHY. **La causa raíz**: el IMX682 transmite en C-PHY y el receptor estaba configurado en D-PHY |
| 0111 | dar a VFE1 y VFE_LITE los relojes correctos en sm7150 |
| 0107 | armar la interrupción del VFE antes del reset (regresión nuestra) |
| 0112 | rotación de montaje — ⚠️ este **no** es de `camss`, es de los drivers i2c `imx682` / `s5k3t2` |
| 0046 | votar `refgen` en sm7150 |
| 0049 | seguir la secuencia CSIPHY del fabricante |
| 0050 | corregir una errata en el reloj `cphy_rx` de sm7150 |
| 0051 | mantener el reloj RX del CSIPHY al ritmo bueno |
| 0059 | retardo de asentamiento ajustable en caliente |
| 0109 | anulación de `settle_cnt` en el CSIPHY |
| 0080 | mantener la interrupción del VFE apagada hasta que el bloque tiene corriente |

⚠️ **El paso de fila es `bytesused/alto`, no el ancho.**
⛔ El **sensor frontal** (D-PHY) sigue **sin enlace**.

Detalle completo, incluido el enfoque: `camera/README.md` y `packages/libcamera/README.md`.

---

## 5. Comprobar que está bien

```sh
# ¿cargó el servicio diferido?
systemctl is-enabled camss-diferido.service && systemctl is-active camss-diferido.service
journalctl -t camss-diferido -n 3

# ¿sincronizaron los votos? (tiene que decir 10)
cat /sys/devices/platform/soc@0/*interconnect/state_synced | grep -c 1

# ¿hay cámara?
ls /dev/video*        # deben salir video0..9
```

---

## 6. Trampas, juntas

- ⚠️⚠️ **La lista negra sigue haciendo falta**: no es un resto histórico. Cargarlo en el
  arranque temprano tumba el móvil, con parches y todo, y **no se sabe por qué**.
- ⚠️⚠️ **El servicio diferido no debe arrastrar el VCM ni los sensores**, o se reintroduce un
  fallo de suspensión que aparecerá lejos de su causa.
- ⚠️ **`fw_devlink.sync_state=timeout` da bucle de arranque.**
- ⚠️ **Numeración**: el parche del VFE es **0080**, no 0063 (los documentos anteriores al
  2026-08-06 usan la serie vieja; equivalencias en `kernel/EQUIVALENCIAS.md`).
- ⚠️ **El DTB solo se relee al reiniciar.**
