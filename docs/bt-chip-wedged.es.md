# El chip Bluetooth se estrella, no vuelve, y lo que mata al móvil es tocarlo después

> Xiaomi POCO X3 NFC (`surya`, SM7150, WCN3990) con postmarketOS y kernel 7.1.
> El parche y el detector de abajo no son específicos de este teléfono.

## La cadena, medida cuatro veces

Cuando el enlace con el auricular se atasca, **el driver estrella el chip a propósito** para
recoger un volcado. En esta placa no resucita:

```
Bluetooth: hci0: link tx timeout
Bluetooth: hci0: killing stalled connection b0:38:e2:…        ← el auricular deja de contestar
Bluetooth: hci0: crash the soc to collect controller dump     ← el DRIVER lo estrella
Bluetooth: hci0: Injecting HCI hardware error event / memdump timeout
Bluetooth: hci0: setting up wcn399x
Bluetooth: hci0: Frame reassembly failed (-84)
Bluetooth: hci0: Reading QCA version information failed (-110)
Bluetooth: hci0: Retry BT power ON: 0, 1, 2                   ← NO VUELVE
Bluetooth: hci0: Opcode 0x0c03 failed: -110
```

**Los tres atascos del enlace registrados escalaron a esto: el 100 %.**

## Lo que de verdad mata al teléfono

No la avería: **lo que uno hace después sin saber que el chip está muerto.** Cada intento de
reconectar desde el escritorio, contra un adaptador que no responde, ha colgado o reiniciado la
máquina. En una de las muertes, el diario termina justo detrás de tres de estos seguidos:

```
phosh: Failed to connect: org.bluez.Error.NotReady: br-connection-adapter-not-powered
```

Un intento de recuperarlo en caliente con `rfkill block bluetooth` **colgó el móvil entero**.
⛔ **No se hace.** Y consultar el adaptador encallado (`hciconfig`, y compañía) **también se
cuelga**: hay que diagnosticar leyendo el diario del kernel, que es pasivo, y nunca preguntándole
al chip.

De ahí `aviso-bt-caido`: un servicio de usuario que vigila el diario y, al ver `Retry BT power
ON:2`, avisa de que hay que reiniciar y **no tocar el Bluetooth**. No consulta el adaptador.
Deja además constancia en `/dev/pmsg0` —el canal de pstore para espacio de usuario, que sobrevive
al reinicio— para que tras una muerte súbita se sepa si al usuario se le había avisado.

## Por qué no volvía: el parche 0127

En placas WCN399x **sin GPIO `bt_en`** —ésta es una— lo único que reinicia el controlador es que
se vayan los reguladores. Y el camino de reintento de `qca_setup()` los volvía a encender
**inmediatamente** después de apagarlos: microsegundos, con los raíles todavía cargados. Desde el
punto de vista del chip, eso no es un ciclo de alimentación.

El parche le da 250 ms para descargarse antes de reintentar. Solo toca el camino de fallo, que ya
se gasta unos diez segundos por intento expirando.

## ⚠️ Por qué los congelados de este teléfono eran MUDOS

Esto vale para cualquier equipo ARM64 sin NMI, y cuesta dar con ello:

```
watchdog: NMI not fully supported
watchdog: Hard watchdog permanently disabled
```

**Sin detector de bloqueo duro, una CPU girando con las interrupciones desactivadas no produce
nada**: ni pánico, ni traza, ni ramoops. Y no lo cubren los otros dos:

| detector | por qué no lo ve |
|---|---|
| `hung_task_panic` | no hay ninguna tarea en espera ininterrumpible |
| `softlockup_panic` | necesita que lleguen interrupciones de temporizador **a esa CPU** |
| perro guardián por hardware | si solo se atasca una CPU de ocho, las demás siguen acariciándolo |

El kernel trae una alternativa que **no necesita NMI** y estaba disponible y apagada:
`CONFIG_HARDLOCKUP_DETECTOR` en su variante **buddy**, en la que cada CPU vigila a otra. Activada.
Un congelado de tres minutos y medio que no dejó una sola línea es lo que lo puso en evidencia.

📌 Si tu placa tampoco tiene NMI y tienes congelados sin rastro, mira esto antes que nada: no vas
a diagnosticar nada mientras el fallo sea invisible.

## Lo que sigue abierto

**Por qué `rfkill block` cuelga la máquina sobre un chip encallado.** Hay un camino plausible —el
mutex **global** de rfkill retenido mientras espera `hci_req_sync_lock`, que arrastraría a
NetworkManager, a systemd-rfkill y al escritorio— pero `hung_task_panic` **no saltó** en tres
minutos y medio, lo que lo contradice. No se parchea a ciegas: primero el detector, y luego se
arregla lo que la traza señale.
