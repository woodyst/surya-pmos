# wayvnc: capturar aunque no se pueda controlar la energía de la pantalla

Sin este parche, **wayvnc no funciona en phosh**: conecta, negocia, y sirve una pantalla
**gris uniforme** (`#606060`) sin un solo error que lo explique.

## La causa, en tres piezas

1. **wlroots admite un único dueño de la energía por salida.** Si ya hay otro cliente,
   manda `failed`:

   ```c
   wl_list_for_each(mgmt, &manager->output_powers, link) {
       if (mgmt->output == output) {
           zwlr_output_power_v1_send_failed(output_power->resource);
           return;
       }
   }
   ```

2. **En phosh ese dueño es phosh**, que es quien apaga y enciende la pantalla. Así que
   wayvnc siempre recibe `failed`.

3. **Y wayvnc se queda esperando para siempre.** Aplaza la captura hasta recibir un evento
   de energía —`wayvnc_start_capture_immediate()` retorna sin llamar a `screencopy_start()`—
   y al llegar `failed` **destruye el objeto sin avisar a nadie**. El evento que espera no
   puede llegar ya nunca. El cliente recibe el búfer recién reservado: gris.

## El parche

- Recuerda que la gestión de energía falló (`power_management_failed`), para que la
  siguiente petición **no vuelva a pedirla y a fallar** en bucle.
- **Avisa a los observadores** al recibir `failed`: les habían prometido un evento que ya
  no va a llegar.
- Trata el estado **desconocido** como razón para capturar, no para no hacer nada.

## Verificado en surya

```
Warning: Output DSI-1 power state failure
Warning: Failed to acquire power state control. Capturing may fail.   ← camino nuevo
DEBUG: Buffer dimensions: 1080x2400                                   ← la salida, ya no solo el cursor
DEBUG: Init done
```

Antes solo aparecía la sesión del **cursor** (512x512). Medido con un cliente RFB mínimo:
el búfer pasa de 360x800 a **1080x2400** y los píxeles dejan de ser un color plano.

⚠️No es específico de phosh: afecta a **cualquier compositor cuyo shell gestione la energía
de la pantalla**. El mensaje del commit está escrito para poder mandarlo a upstream tal cual.

## Uso

Desde el portátil, una sola orden (arranca el servicio en el móvil, abre el túnel y
conecta):

```sh
pantalla-movil            # ~/bin/pantalla-movil, copia aquí como pantalla-movil.sh
pantalla-movil vinagre    # con otro cliente
```

A mano, si hace falta:

```sh
ssh epo 'XDG_RUNTIME_DIR=/run/user/10000 systemctl --user start wayvnc'
ssh -f -N -L 5900:localhost:5900 epo
remmina -c vnc://localhost:5900
```

En el móvil hay una unidad de usuario (`wayvnc.service`, copia aquí) que **no se arranca
sola**: se enciende cuando se pide, para no dejar el servidor abierto ni gastar batería.
Para pararlo: `ssh epo 'XDG_RUNTIME_DIR=/run/user/10000 systemctl --user stop wayvnc'`.

Atado a `127.0.0.1` a propósito: el **túnel SSH es el único acceso**, comprobado
intentando conectar directamente a la IP del móvil (conexión rehusada).

⚠️**TigerVNC corta la conexión con «Too big cursor»** — no es un aviso, aborta. Por eso se
arranca con `--render-cursor`. Remmina y Vinagre lo toleran igualmente.
