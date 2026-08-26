# El casco conecta pero no aparece en PipeWire: se ha enganchado solo por BLE

> Xiaomi POCO X3 NFC (`surya`) con postmarketOS, BlueZ 5.86 y PipeWire/WirePlumber.
> Nada de esto es específico de este teléfono: le pasa a cualquier auricular de doble modo.

**Fecha:** 2026-08-26 · **Estado:** reconocido y con receta; la causa de fondo es del casco

## El síntoma

Conectas el auricular, el móvil dice que está conectado… y **no hay tarjeta Bluetooth** en
PipeWire, así que no hay dónde mandar el sonido.

```
$ pactl list short cards
130   alsa_card.platform-sound   alsa          ← y nada más
```

## Cómo se reconoce en dos vistazos

**1. El nombre en caché ha cambiado**, y ese sufijo lo dice todo:

```
$ bluetoothctl info B0:38:E2:...
    Name: Soundcore_Sport_X10_BLE          ← ese _BLE
```

**2. El enlace es LE, no clásico:**

```
$ hcitool con
    < LE B0:38:E2:... handle 2 state 1 lm CENTRAL      ← LE
```

Cuando está bien, se ve así:

```
    < ACL  B0:38:E2:... handle 4 state 1 lm CENTRAL AUTH ENCRYPT
    < eSCO B0:38:E2:... handle 5 state 1 lm CENTRAL      (solo durante llamada)
```

**A2DP y HFP existen únicamente sobre BR/EDR.** Por LE no hay perfiles de audio, así que
PipeWire no tiene nada que enseñar. No es que falle el audio: es que no hay dispositivo.

## Lo que NO es

- **No es que se haya perdido el emparejamiento.** El `[LinkKey]` de BR/EDR sigue en
  `/var/lib/bluetooth/<adaptador>/<casco>/info`. No hay que reemparejar nada.
- **No es alcance ni batería.** Un rastreo clásico lo ve perfectamente:
  `bluetoothctl --timeout 12 scan bredr` → `RSSI: -48`.
- **No es el chip encallado.** Eso es otra avería distinta, con su propia firma
  (`Retry BT power ON:2`) y su propio aviso → ver [`hfp-race.es.md`](hfp-race.es.md) y
  [`bt-chip-wedged.es.md`](bt-chip-wedged.es.md).

## Qué lo arregla

**Reiniciar el auricular** (apagarlo y encenderlo, o meterlo y sacarlo del estuche).

El móvil pide la conexión clásica y **el casco la rechaza**:

```
$ gdbus call ... org.bluez.Device1.ConnectProfile 0000110b-...
Error: org.bluez.Error.Failed: br-connection-refused
```

Ese rechazo, con el casco visible y a −48 dBm, apunta a que **tiene sus plazas ocupadas**:
estos auriculares admiten dos dispositivos a la vez, y si el portátil o la tablet lo tienen
cogido, rechazan la página del tercero. Al reiniciarlo suelta lo que tuviera y acepta.

## ⚠️ Lo que probé y NO funcionó, para que nadie lo repita

**Cambiar el portador preferido no arregla nada, y encima no se puede fijar.**

En el fichero de caché aparece:

```
PreferredBearer=last-used
LastUsedBearer=le            ← el síntoma, no la causa
```

Da la impresión de que basta con forzar `bredr`. No:

- `bluetoothctl bearer <mac> bredr` → **`org.freedesktop.DBus.Error.UnknownProperty`**. En
  BlueZ 5.86 el mando existe en la interfaz de línea de órdenes pero **el demonio no expone
  la propiedad**, así que no hay forma de fijarlo en vivo.
- Editar el fichero con `bluetoothd` parado **sí** deja `PreferredBearer=bredr`… y BlueZ lo
  **reescribe a `last-used`** en cuanto reconecta. No se puede clavar.
- Y sobre todo: **el rechazo `br-connection-refused` siguió igual después de cambiarlo.** Lo
  que restauró la conexión fue reiniciar el casco.

📌 O sea que `LastUsedBearer=le` es **consecuencia** de haberse enganchado por LE, no la razón
por la que no consigue engancharse por el clásico. Es fácil confundirlo, porque el valor salta
a la vista y parece el culpable perfecto.

⛔ **`ControllerMode = bredr` en `/etc/bluetooth/main.conf`** apagaría LE en todo el
controlador y esto no volvería a pasar — pero se lleva por delante cualquier dispositivo BLE
del sistema. Es un martillo demasiado grande para este clavo; queda anotado, no puesto.

## Receta rápida

```sh
# 1. ¿es esto?
hcitool con | grep -q "< LE" && echo "enganchado por LE: no habra audio"
bluetoothctl info <mac> | grep Name        # ¿acaba en _BLE?

# 2. arreglo
#    apagar y encender el auricular. Y si otro aparato tuyo puede tenerlo
#    cogido (portátil, tablet), apagarle el Bluetooth.

# 3. comprobar
pactl list short cards | grep bluez_card   # tiene que salir
hcitool con | grep "< ACL"                 # enlace clasico
```
