#!/bin/sh
# Parte de SISTEMA del arranque de audio: la cadena de modulos en el orden
# obligado, esperando SEÑALES REALES en cada paso (las esperas fijas fallaban
# bajo carga de arranque: el chip no llegaba a enumerar y la tarjeta quedaba
# diferida para siempre con "SLIMBUS_7 Playback: codec dai not found").
#
# ⚠️ ORDEN: Bluetooth primero; audio al final (ver COMO-DEJAR-TODO-FUNCIONANDO).
# ⚠️ Corre tras multi-user, nunca en el arranque temprano (colgaba el movil).

log() { echo "armar-audio: $*"; }

# MODO SIN BLUETOOTH: si existe esta bandera, cargar solo el audio (para
# cuando el chip BT esta en su estado terminal y no enumera: sin esto la
# tarjeta no subiria nunca y ademas martillear el chip cuelga el movil).
# Requiere el DTB SIN slim7 y q6voice_device=3. Quitar la bandera y reponer
# DTB con-slim7 + device=4 + UCM con Bluetooth para volver al modo completo.
if [ -e /etc/audio-sin-bt ]; then
	log "modo SIN Bluetooth (bandera /etc/audio-sin-bt)"
	modprobe snd_soc_sm8250 2>/dev/null
	for i in $(seq 1 25); do [ -e /proc/asound/card0 ] && break; sleep 2; done
	[ -e /proc/asound/card0 ] && log "tarjeta arriba" || log "ERROR: sin tarjeta"
	touch /run/audio-armado
	exit 0
fi

# ===== EXPERIMENTO 2026-08-05: ORDEN INVERTIDO =====
# La receta que SI enumero el 3-ago era: SLIMBus -> wcn-bt-slim -> hci_uart,
# con el Bluetooth el ULTIMO. Desde entonces se hacia al reves (BT primero),
# y el chip no enumera. Se prueba el orden original.
# Para volver: /root/armar-audio-sistema.sh.orden-bt-primero

# 1) el controlador del bus, ANTES que nada del Bluetooth
modprobe --ignore-install slim_qcom_ngd_ctrl 2>/dev/null
sleep 2

# 2) el codec, con el bus en pie y el chip aun sin firmware
modprobe --ignore-install wcn-bt-slim 2>/dev/null
sleep 2

# 3) AHORA el Bluetooth, que enciende el chip y le mete el firmware
modprobe --ignore-install hci_uart hfp_offload=1 2>/dev/null

# ⚠️ NO forzar "hciconfig hci0 up" aqui. Antes se hacia, y competia con
# bootmac: este pone la direccion publica (el chip declara una invalida,
# 39:90:21:...) y encola un power_on para completar la transicion a
# "configurado". Si nosotros ya habiamos abierto el dispositivo, ese
# power_on falla con -EALREADY (-114), hci_power_on() retorna antes de
# tiempo y NUNCA limpia HCI_RAW ni anuncia el controlador como
# configurado -> hci0 se queda en RAW y bluetoothd no lo ve
# ("No default controller available"). Medido con trazas en el kernel.
#
# Basta con ESPERAR a que el kernel y bootmac terminen su baile.
for i in $(seq 1 30); do
	hciconfig hci0 2>/dev/null | grep -q "UP RUNNING" && break
	sleep 1
done
if hciconfig hci0 2>/dev/null | grep -q "RAW"; then
	log "AVISO: bluetooth arriba pero en RAW (bluetoothd no lo vera)"
elif hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; then
	log "bluetooth arriba y configurado"
else
	log "AVISO: bluetooth no confirma"
fi

# 4) dar tiempo a que el chip se anuncie en el bus ya con firmware
for i in $(seq 1 15); do
	dmesg | grep -q "enumerated: pgd laddr" && break
	sleep 1
done
if dmesg | grep -q "enumerated: pgd laddr"; then
	log "enumeracion: SI (orden invertido)"
else
	log "enumeracion: no (orden invertido tampoco)"
fi

# 4) el audio, y esperar a la tarjeta
modprobe snd_soc_sm8250 2>/dev/null
for i in $(seq 1 25); do
	[ -e /proc/asound/card0 ] && break
	sleep 2
done
[ -e /proc/asound/card0 ] && log "tarjeta arriba" || log "ERROR: sin tarjeta"

touch /run/audio-armado
