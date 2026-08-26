#!/bin/sh
# Avisar al usuario cuando el chip Bluetooth se queda encallado.
#
# POR QUE
#   Cuando el enlace con el casco se atasca, el driver estrella el chip a
#   proposito para recoger un volcado ("crash the soc to collect controller
#   dump") y en este movil a veces NO VUELVE: tres reintentos de encendido y
#   -110. A partir de ahi el telefono parece normal... hasta que se toca el
#   Bluetooth. Medido tres veces: cada intento de reconectar desde la interfaz
#   es lo que ha COLGADO O REINICIADO el movil. El 25 de agosto el diario
#   termina justo despues de tres "br-connection-adapter-not-powered" seguidos.
#
#   O sea que lo que mata al movil no es la averia: es lo que uno hace despues
#   sin saber que el chip esta muerto. Este aviso existe para que se sepa.
#
# ⚠️⚠️ NO CONSULTA EL ADAPTADOR. Ni hciconfig, ni bluetoothctl, ni nada que le
#    hable al chip: con el encallado, esas consultas SE CUELGAN. Se aprendio a
#    base de colgar el movil intentando justo eso (2026-08-26). Aqui solo se lee
#    el diario del kernel, que es pasivo.
#
# ⚠️ El aviso se anota tambien en /dev/kmsg: si el movil muere despues, en
#    ramoops quedara si al usuario se le habia avisado o no.
set -u

# El tercer y ultimo reintento del driver. En los tres episodios medidos, a
# partir de aqui el chip no volvio ni una vez.
PATRON='Retry BT power ON:2'
DESCANSO=${DESCANSO:-600}     # segundos entre avisos, para no dar la lata

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

ahora() { cut -d' ' -f1 /proc/uptime | cut -d. -f1; }

# ⚠️ La redireccion fallida la reporta el INTERPRETE, no el comando, asi que un
#    `2>/dev/null` pegado al printf no la calla: hay que envolver el bloque. Sin
#    esto, el diario se llenaba de "can't create /dev/kmsg: Permission denied".
anotar() {
	echo "aviso-bt-caido: $*"
	# /dev/pmsg0 es el canal de pstore para espacio de usuario y sobrevive al
	# reinicio (hace falta la regla de udev 99-pmsg-escribible.rules). Si no
	# esta disponible se prueba /dev/kmsg, que solo funciona siendo root.
	{ printf 'aviso-bt-caido: %s\n' "$*" > /dev/pmsg0; } 2>/dev/null && return 0
	{ printf '<3>aviso-bt-caido: %s\n' "$*" > /dev/kmsg; } 2>/dev/null || true
}

avisar() {
	notify-send -u critical -i bluetooth-disabled \
		"Bluetooth caído" \
		"El chip no responde y no va a volver solo.

Reinicia el móvil cuando puedas.

⚠️ NO toques el conmutador de Bluetooth ni intentes reconectar el casco: con el chip así, cada intento puede colgar el teléfono." \
		2>/dev/null
}

anotar "vigilando el diario del kernel"
ULTIMO=0

# -n0: solo lo que llegue de ahora en adelante. -o cat: sin adornos.
journalctl -k -f -n0 -o cat 2>/dev/null | while IFS= read -r linea; do
	case "$linea" in
		*"$PATRON"*) ;;
		*) continue ;;
	esac
	T=$(ahora)
	if [ $((T - ULTIMO)) -lt "$DESCANSO" ] && [ "$ULTIMO" -ne 0 ]; then
		continue
	fi
	ULTIMO=$T
	anotar "CHIP BLUETOOTH ENCALLADO: aviso al usuario (reiniciar, y no tocar el Bluetooth)"
	avisar
done
