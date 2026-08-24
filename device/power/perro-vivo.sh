#!/bin/sh
# Perro guardián por HARDWARE que exige que el móvil SIRVA, no sólo que respire.
#
# EL PROBLEMA
#   systemd acaricia /dev/watchdog desde PID 1. Eso sólo prueba que PID 1 existe.
#   El 2026-08-23 el móvil estuvo minutos congelado -- pantalla muerta, teclas sin
#   respuesta, sin red -- con systemd vivo acariciando tan tranquilo. El perro no
#   ladró hasta que systemd tambien murió, a los 6009 s. Y sin poder reiniciar en
#   caliente, hubo que apagar con el botón: eso BORRA la RAM y con ella ramoops.
#   Resultado: cero evidencia de un cuelgue de varios minutos.
#
#   Medido: cuando PID 1 deja de acariciar, el perro ladra en ~5 s. Funciona. Lo
#   que falla es el criterio.
#
# QUÉ HACE ESTE
#   Coge el perro y sólo lo acaricia si supera una prueba de vida DE VERDAD:
#   crear un proceso, escribir y leer un fichero, y leer /proc. Son justo las
#   cosas que dejan de funcionar en un congelado aunque PID 1 siga en pie.
#   Si la prueba falla varias veces seguidas, deja de acariciar -> reinicio POR
#   HARDWARE en caliente -> la RAM se conserva -> **ramoops queda intacto**.
#
# ⚠️ PARA QUE FUNCIONE hay que soltarle el perro a systemd:
#      /etc/systemd/system.conf ->  RuntimeWatchdogSec=0
#    Si no, systemd lo tiene abierto y este no puede cogerlo.
#
# ⚠️ RIESGO: una prueba de vida demasiado estricta reinicia el móvil sin motivo.
#    Por eso: prueba barata, plazo generoso, y hacen falta VARIOS fallos seguidos.
#    Con los valores de serie, un congelado real reinicia en ~40-60 s.
#
# ⚠️ Al parar el servicio se escribe 'V' (cierre mágico) para desarmar el perro.
#    Sin eso, el móvil se reiniciaría solo tras un apagado limpio.
set -u

DISPOSITIVO=/dev/watchdog
PLAZO=${PLAZO:-30}          # margen del perro, en segundos (max 32 en este SoC)
CADA=${CADA:-5}             # cada cuanto se comprueba la vida
FALLOS=${FALLOS:-2}         # fallos seguidos antes de dejar de acariciar
ESPERA_PRUEBA=${ESPERA_PRUEBA:-8}

log() { echo "perro-vivo: $*"; }

# ⚠️ `[ -w ]` NO basta: para root da verdadero aunque el dispositivo este OCUPADO.
#    Y ojo: un `exec` con redireccion fallida MATA el interprete, asi que el
#    intento de apertura va en un SUBINTERPRETE y el de verdad despues.
if ! ( exec 3>"$DISPOSITIVO" ) 2>/dev/null; then
	log "no puedo abrir $DISPOSITIVO."
	log "  Casi seguro lo tiene systemd. Sueltaselo con:"
	log "    RuntimeWatchdogSec=0 en /etc/systemd/system.conf  +  systemctl daemon-reexec"
	exit 1
fi

# La prueba de vida: crear proceso, escribir, leer, y mirar /proc. Barata, y toca
# justo lo que se muere en un congelado.
vivo() {
	timeout "$ESPERA_PRUEBA" sh -c '
		f=/run/perro-vivo.marca
		echo $$ > "$f" 2>/dev/null || exit 1
		read -r _ < "$f"           || exit 1
		read -r _ < /proc/uptime   || exit 1
		exit 0
	' 2>/dev/null
}

desarmar() { printf 'V' > "$DISPOSITIVO" 2>/dev/null && log "perro desarmado (cierre mágico)"; }
trap 'desarmar; exit 0' INT TERM EXIT

# ★ AUTODIAGNOSTICO ANTES DE ARMAR NADA. Armar un perro cuya prueba de vida esta
#   rota es la forma mas rapida de meter al movil en un bucle de reinicios. Si la
#   prueba no pasa con el sistema SANO, no se arma y se dice por que.
n=0
for i in 1 2 3 4 5; do vivo && n=$((n+1)); done
if [ $n -lt 5 ]; then
	log "⛔ NO ARMO: la prueba de vida solo pasa $n de 5 con el sistema sano."
	log "   Con el perro armado, eso reiniciaria el movil sin motivo."
	log "   Comprueba que /run es escribible por root y que 'timeout' existe."
	desarmar; exit 1
fi
log "autodiagnostico: la prueba de vida pasa 5 de 5"

exec 3>"$DISPOSITIVO"          # ahora si, de verdad
# ⚠️ El margen NO se fija por sysfs: ese fichero es de SOLO LECTURA y el intento
#    solo ensucia el diario ("Permission denied"). El driver aplica su propio
#    valor al abrirlo -- en este SoC, 30 s, que es justo lo que queriamos. Se lee
#    y se informa del real, sin intentar cambiarlo.
PLAZO_REAL=$(cat /sys/class/watchdog/watchdog0/timeout 2>/dev/null)
log "armado: margen ${PLAZO_REAL:-?}s (lo fija el driver), prueba cada ${CADA}s, $FALLOS fallos para soltar"

seguidos=0
while :; do
	if vivo; then
		[ $seguidos -gt 0 ] && log "vida recuperada tras $seguidos fallo(s)"
		seguidos=0
		printf '\0' >&3        # caricia
	else
		seguidos=$((seguidos+1))
		log "PRUEBA DE VIDA FALLIDA ($seguidos/$FALLOS)"
		if [ $seguidos -ge $FALLOS ]; then
			log "dejo de acariciar: el perro reiniciara en <=${PLAZO}s. ramoops se conserva."
			# no acariciar mas: que muerda
			while :; do sleep 60; done
		fi
	fi
	sleep "$CADA"
done
