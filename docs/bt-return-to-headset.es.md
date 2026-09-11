# Volver al casco a mitad de llamada: mudo en los dos sentidos, y un bus que nunca se apagaba

> Xiaomi POCO X3 NFC (`surya`, SM7150, WCN3990) con postmarketOS y kernel 7.1 (sm7150-mainline).
> El parche no es específico de este teléfono: afecta a cualquier placa Qualcomm con el controlador
> satélite `qcom-ngd-ctrl` (SLIMbus).

## El síntoma

Llamada con un casco Bluetooth: suena. Pasas a manos libres: suena. Vuelves al casco: **mudo en los
dos sentidos**, ni el otro te oye ni tú a él, hasta colgar. La llamada siguiente vuelve a sonar.

## Cómo se acotó

Con un banco de dos móviles y sin nadie delante: otro teléfono llama, un portátil hace de casco
(oFono y un agente HFP que manda un tono de 1 kHz como si fuera su micro y graba lo que recibe), y se
mide cada tramo —casco, altavoz, casco— en los dos extremos. Lo que fue saliendo:

- **No es el casco**: con el portátil de casco falla igual.
- **No es el HCI**: los mandatos del enlace en la primera entrada y en la vuelta son idénticos byte a
  byte. El fallo está por debajo.
- **Es el enlace DSP↔chip**: en la vuelta, una toma directa del puerto SLIMbus en el DSP da ceros, y
  un tono inyectado por ese puerto no llega al casco. Muerto en los dos sentidos.
- **Las órdenes al DSP son las mismas** en la entrada y en la vuelta, todas con respuesta correcta
  (trazadas en caliente con kprobes sobre `apr_send_pkt` y `apr_callback`).
- **Sin llamada, parar y arrancar el SLIMbus funciona.** Dentro de una llamada, no.
- **Refutado con medida**: cambiar el orden de arranque de los canales, desenganchar la voz antes de
  parar los puertos, recrear entera la sesión de voz del DSP, levantar el eSCO segundos antes que el
  SLIMbus, y la suspensión del controlador (se suspende también en la primera entrada, que suena).

## La causa

`drivers/slimbus/qcom-ngd-ctrl.c`. Al desactivar un flujo, el núcleo SLIMbus manda
`BEGIN_RECONFIGURATION`, `NEXT_DEACTIVATE_CHANNEL`, `NEXT_REMOVE_CHANNEL` y `RECONFIGURE_NOW`, pero
`qcom_slim_ngd_xfer_msg()` descarta esos mensajes —un satélite no manda reconfiguraciones del
núcleo— y el controlador no implementa `disable_stream`. **El gestor del bus, que vive en el DSP,
nunca se entera de que los canales se han ido.**

Los canales siguen definidos, el bus no se apaga de verdad (en un día entero de pruebas no se
reenumeró ni una vez) y, dentro de una llamada, al volver a activar los mismos canales el enlace
queda mudo. Entre llamadas se recupera: por eso la siguiente sonaba.

El kernel de fábrica (`slim-msm-ngd.c`) sí se lo dice al gestor, con mensajes de usuario:
`CHAN_CTRL(REMOVE)` con los canales, y `RECONFIG_NOW`.

## El arreglo

- Parche [`0130`](../kernel/0130-slimbus-qcom-ngd-ctrl-remove-a-stream-s-channels-from-the-manager.patch):
  `qcom_slim_ngd_disable_stream()` hace lo mismo que el kernel de fábrica, calcado de
  `qcom_slim_ngd_enable_stream()`, esperando la confirmación del gestor.
- Va tras el parámetro `remove_channels`, **apagado en el parche** (así se comparó con y sin en el
  mismo kernel) y **encendido por [`device/modprobe/slimbus.conf`](../device/modprobe/slimbus.conf)**,
  que instala `scripts/install-on-device.sh`. En caliente, entre llamadas:
  `echo Y | sudo tee /sys/module/slim_qcom_ngd_ctrl/parameters/remove_channels`.

## Medido

| vuelta al casco | `remove_channels=N` | `remove_channels=Y` |
|---|---|---|
| subida (lo que oye el otro) | silencio digital, 100 % ceros | **tono**, contraste 364 465x |
| bajada (lo que oye el casco) | silencio | **audio**, igual que en la primera entrada |

Con `Y`, al pasar a altavoz el kernel dice `removed 1 channel(s) from the manager` para cada canal y,
al volver, **el bus se reenumera** (`SLIM SAT: Rcvd master capability`): sin canales, el DSP lo apaga
y lo arranca de cero con el chip. Con un casco real: dos llamadas y cuatro idas y vueltas al altavoz,
todas con sonido y el circuito rehecho en alrededor de un segundo.

## Comprobarlo

```sh
cat /sys/module/slim_qcom_ngd_ctrl/parameters/remove_channels    # Y
journalctl -k | grep "removed 1 channel"                          # tras pasar a altavoz
```

## El supervisor de la llamada por casco

[`device/services/supervisor-llamada-bt.py`](../device/services/supervisor-llamada-bt.py), arrancado
por `llamada-al-bluetooth.service`, sustituye al guion anterior. Escucha por eventos D-Bus a
ModemManager y a PipeWire, sin sondear: monta el lado del casco al empezar la llamada (perfil de voz
y enlace SCO, que adquiere con la propiedad `bluetoothOffloadActive` del dispositivo), lo desmonta al
pasar a altavoz, lo rehace al volver, vigila que no se caiga y avisa con notificaciones. Necesita
`py3-gobject3`.
