#!/bin/sh
# activar-cancelacion-eco.sh — deja la cancelación de eco de las llamadas lista en cada arranque
# (2026-09-12). Lo lanza cancelacion-eco.service después de armar-audio.service y del PD de audio.
#
# Qué hace falta para que el DSP cancele el eco (ver docs/echo-cancellation.es.md):
#   1. el PD de audio del ADSP servido (hexagonrpcd-adsp-audiopd.service): la canceladora SMECNS V2
#      es un módulo dinámico que ese PD carga por fastrpc
#   2. las topologías propias del fabricante registradas en el DSP (q6core custom_topologies) y
#      sus módulos cargados (load_topology)
#   3. los parámetros del kernel: CREATE V3, topologías TX/RX del fabricante, preparación del
#      vocproc con calibración (vendor_steps=15, cal_set) y mapeo con is_cached=1 (map_cached)
#
# ⚠️ Los parámetros SOLO se ponen si 1 y 2 salieron bien. Con la topología del fabricante y sin
#    ellos, el vocproc no confirma y la llamada queda MUDA. Si algo falla se dejan los de paso
#    directo (la llamada funciona, sin cancelar el eco) y queda escrito en el diario.
#
# Ajustes (opcional) en /etc/default/cancelacion-eco:
#   ECO=0                 no activar nada (paso directo)
#   CAL_SET=handset       juego de calibración (handset|speaker|handset-aec|speaker-aec)
#   TX=0x10000003 RX=0x10010F8B
set -u
ECO=1; CAL_SET=handset; TX=0x10000003; RX=0x10010F8B
[ -f /etc/default/cancelacion-eco ] && . /etc/default/cancelacion-eco
M=/sys/module
FW=qcom/sm7150/xiaomi/surya/acdb-custom-topologies.bin
log() { logger -t cancelacion-eco "$*"; echo "$*"; }

paso_directo() {
	echo N > $M/q6cvp/parameters/create_v3 2>/dev/null
	echo 0x10F70 > $M/q6cvp/parameters/tx_topology 2>/dev/null
	echo 0x10F77 > $M/q6cvp/parameters/rx_topology 2>/dev/null
	echo 0 > $M/q6voice/parameters/vendor_steps 2>/dev/null
}
falla() { log "⛔ $* -> llamadas en paso directo, SIN cancelación de eco"; paso_directo; exit 1; }

[ "$ECO" = 1 ] || { log "ECO=0 en /etc/default/cancelacion-eco: paso directo"; paso_directo; exit 0; }

# Los parámetros existen cuando armar-audio ha cargado los módulos de voz.
n=0
until [ -e $M/q6voice/parameters/vendor_steps ] && [ -e $M/q6core/parameters/custom_topologies ] \
      && [ -e $M/q6mvm/parameters/map_cached ]; do
	n=$((n + 1)); [ $n -gt 120 ] && falla "los módulos de voz no aparecen (¿kernel sin r86+?)"
	sleep 1
done
[ -f /lib/firmware/$FW ] || falla "falta /lib/firmware/$FW (ver docs/echo-cancellation.es.md)"
for p in handset speaker; do
	[ -f /lib/firmware/qcom/sm7150/xiaomi/surya/voice-$p-static.bin ] \
		|| falla "falta la calibración voice-$p-* (ver docs/echo-cancellation.es.md)"
done

# 1. el PD de audio
n=0
until systemctl is-active -q hexagonrpcd-adsp-audiopd.service; do
	n=$((n + 1)); [ $n -gt 60 ] && falla "hexagonrpcd-adsp-audiopd no está activo"
	sleep 1
done

# 2. topologías del fabricante (el resultado del DSP solo sale en el registro del kernel)
MARCA="cancelacion-eco: registro $(date +%s)"
echo "$MARCA" > /dev/kmsg
echo $FW > $M/q6core/parameters/custom_topologies || falla "no se pudo pedir el registro de topologías"
sleep 2
dmesg | sed -n "/$MARCA/,\$p" | grep -q "register custom topologies .*): 0$" \
	|| falla "el DSP no aceptó las topologías propias"
for t in $TX $RX; do
	echo $t > $M/q6core/parameters/load_topology || falla "no se cargaron los módulos de la topología $t"
done

# 3. parámetros
echo Y > $M/q6cvp/parameters/create_v3
echo $TX > $M/q6cvp/parameters/tx_topology
echo $RX > $M/q6cvp/parameters/rx_topology
echo Y > $M/q6mvm/parameters/map_cached
printf '%s' "$CAL_SET" > $M/q6voice/parameters/cal_set
echo 15 > $M/q6voice/parameters/vendor_steps
log "✓ cancelación de eco lista: TX $TX, RX $RX, calibración $CAL_SET"
