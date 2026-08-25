#!/bin/sh
# Vigila que el wireplumber VIVO sea el que tiene registrado el perfil HFP, y lo
# repara cuando no lo es.
#
# POR QUE EXISTE (2026-08-24)
#   En el arranque wireplumber se arranca y se reinicia VARIAS veces en menos de
#   un minuto: hay dos gestores de usuario de systemd para el mismo uid y ademas
#   avisar-camaras.sh lo reinicia a proposito cuando entra qcom_camss. Medido en
#   un arranque real: cinco instancias en 40 s (pid 1289, 1472, 3745, 3827, 4563).
#
#   El backend nativo de HFP de wireplumber hace DOS cosas exclusivas:
#     - abre un socket RFCOMM a la escucha  -> la 2a instancia da "listen(): Address in use"
#     - registra los UUID 0000111e/0000111f -> la 2a da "RegisterProfile() failed:
#       org.bluez.Error.NotPermitted" y bluetoothd anota "already registered"
#
#   Si el que gana esa carrera NO es el que sobrevive, nadie sirve el HFP:
#   el auricular conecta solo en A2DP, `pactl set-card-profile ...
#   headset-head-unit-cvsd` FALLA siempre, no hay enlace eSCO y TODA llamada por
#   casco sale MUDA para el resto del arranque. Un reinicio del movil NO lo
#   arregla: vuelve a echarse la carrera. Medido el 2026-08-25 en cinco arranques
#   seguidos, correlacion PERFECTA:
#
#     arranque   errores de registro del pid vivo   llamadas por casco
#       -4                 0                              bien
#       -3                 0                              bien
#       -2                 2                              MUDAS
#       -1                 3                              MUDAS
#        0                 0                              bien
#
# ⚠️⚠️ POR QUE ES UN BUCLE Y NO UNA COMPROBACION UNICA (2026-08-25)
#   La primera version comprobaba una sola vez y, si habia una llamada en curso,
#   se rendia: `exit 0`. Resulto ser justo el peor momento posible — en los dos
#   arranques que fallaron, el usuario estaba al telefono peleandose con el casco
#   cuando toco la comprobacion, asi que el guardian se fue sin hacer nada las
#   DOS veces que hacia falta. Ahora espera a que cuelgue y lo repara entonces:
#   la llamada en curso se pierde igual, pero la siguiente ya va bien.
#
# ⚠️ NUNCA se reinicia wireplumber con una llamada en curso: la deja sin audio.
# ⚠️ Se mira el diario DE ESA INSTANCIA (desde que arranco su pid), no el
#    arranque entero: los errores de las instancias muertas son normales y
#    esperados, y mirarlos daria un falso positivo siempre.
# ⚠️ En reposo esto NO consulta el diario ni llama a mmcli: mientras el pid de
#    wireplumber no cambie se reutiliza el veredicto anterior. Un `pgrep` al
#    minuto y nada mas.
set -u

ESPERA_INICIAL=${1:-90}   # a que se asiente el arranque (detras de avisar-camaras)
INTERVALO=60
MAX_REPARACIONES=3        # por generacion de wireplumber; luego se avisa y se calla

log() { echo "hfp-registrado: $*"; }

hay_llamada() {
	sudo -n mmcli -m 0 --voice-list-calls 2>/dev/null | grep -q '/Call/'
}

# ¿Se quejo ESTE wireplumber al registrar el perfil?
roto_pid() {
	D=$(ps -o etimes= -p "$1" 2>/dev/null | tr -d ' ')
	[ -n "$D" ] || return 1
	journalctl --no-pager --since "$((D + 2)) seconds ago" 2>/dev/null \
		| grep -qE "wireplumber\[$1\]:.*(RegisterProfile\(\) failed|listen\(\): Address in use)"
}

[ "$ESPERA_INICIAL" -gt 0 ] 2>/dev/null && sleep "$ESPERA_INICIAL"

PID_VISTO=""
ESTADO=""          # bien | roto | rendido
REPARACIONES=0
AVISADO_LLAMADA=0
REPARANDO=0        # el proximo cambio de pid lo hemos provocado nosotros

while true; do
	P=$(pgrep -x wireplumber | head -1)

	if [ -z "$P" ]; then
		PID_VISTO=""
		sleep "$INTERVALO"
		continue
	fi

	# Solo se reevalua cuando cambia el proceso: en reposo esto es un pgrep.
	if [ "$P" != "$PID_VISTO" ]; then
		PID_VISTO="$P"
		AVISADO_LLAMADA=0
		# ⚠️⚠️ DOS COSAS QUE NO SE REINICIAN si el proceso ha cambiado PORQUE
		# LO HEMOS REINICIADO NOSOTROS: el contador de reparaciones y el
		# estado «rendido». Sin esto el tope de $MAX_REPARACIONES no llega
		# nunca —cada reparacion crea un pid nuevo, el pid nuevo se reevalua,
		# la reevaluacion pisa el «rendido» y vuelta a empezar— y queda un
		# bucle de reinicios de wireplumber contra algo que no tiene arreglo.
		# Cazado probandolo a proposito el 2026-08-25: llego a «reparacion 5
		# de 3» antes de que se cortara la prueba.
		if [ $REPARANDO -eq 1 ]; then
			REPARANDO=0
		else
			# Generacion nueva y ajena: borron y cuenta nueva.
			REPARACIONES=0
			[ "$ESTADO" = rendido ] && ESTADO=""
		fi
		if roto_pid "$P"; then
			# Si ya nos rendimos con esta generacion, ni se avisa ni se toca.
			if [ "$ESTADO" != rendido ]; then
				ESTADO=roto
				log "el wireplumber vivo (pid $P) NO tiene el HFP: perdio la carrera del registro"
			fi
		else
			ESTADO=bien
			log "el HFP esta bien registrado (wireplumber pid $P)"
		fi
	fi

	if [ "$ESTADO" = roto ]; then
		if hay_llamada; then
			[ $AVISADO_LLAMADA -eq 0 ] && log "hay una llamada en curso; espero a que termine para reparar"
			AVISADO_LLAMADA=1
		else
			REPARACIONES=$((REPARACIONES + 1))
			log "reinicio wireplumber (reparacion $REPARACIONES de $MAX_REPARACIONES)"
			if systemctl --user restart wireplumber 2>/dev/null; then
				sleep 6
				REPARANDO=1
				PID_VISTO=""      # forzar reevaluacion del proceso nuevo
			else
				log "AVISO: no se pudo reiniciar wireplumber"
			fi
			if [ $REPARACIONES -ge $MAX_REPARACIONES ]; then
				ESTADO=rendido
				log "AVISO: sigue sin registrar el HFP tras $REPARACIONES reinicios -- las llamadas por casco saldran MUDAS"
			fi
		fi
	fi

	sleep "$INTERVALO"
done
