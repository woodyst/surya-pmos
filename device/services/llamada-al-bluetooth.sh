#!/bin/sh
# Sostiene el enlace SCO durante una llamada con casco Bluetooth, y remata la
# vuelta al casco con un ciclo extra de perfil.
#
# ⚠️ El enlace tiene que existir ANTES de que caigan las rutas (el chip solo
# abre sus puertos del bus con SCO en pie); por eso el sosten es un servicio
# aparte y arranca en cuanto hay llamada+casco.
# ⚠️ NO suspender el sink bluez en mitad de la llamada para "refrescar" el SCO:
# wireplumber re-evalua los perfiles al ver el sink caido y lo desmonta todo
# (medido: thrash Speaker->HiFi->BT y el SCO ya no vuelve).
# ⚠️ LIMITACION CONOCIDA (2026-08-04, investigada a fondo y sin resolver): la
# vuelta al casco A MITAD de llamada se queda muda aunque TODO lo visible este
# perfecto. Refutado con medida: no es el vocproc (rekick doble), ni las rutas,
# ni los puertos del bus (re-levantados), ni el SCO viejo (el arranque funciona
# con SCO viejo), ni el SCO fresco (rebotado y tampoco), ni el ciclo de perfil
# automatico. La diferencia arranque-vs-vuelta esta en una capa no instrumentada
# (sospecha: secuencia interna del chip o del CVD). Ver
# OFFLOAD-SLIMBUS-ESTADO.md. Mientras tanto: NO cambiar de salida en mitad de
# una llamada con casco; para moverse al altavoz, mejor colgar y rellamar.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
TARJETA=${TARJETA:-alsa_card.platform-sound}

log() { echo "llamada-al-bluetooth: $*"; }

hay_llamada() {
	sudo -n mmcli -m 0 --voice-list-calls 2>/dev/null | grep -q "/Call/"
}
hay_casco() {
	timeout 3 pactl list short cards 2>/dev/null | grep -q bluez
}
perfil() {
	timeout 3 pactl list cards 2>/dev/null | grep "Active Profile" | head -1 | cut -d: -f2 | tr -d " "
}
# Perfiles de CADA tarjeta por separado: `perfil` coge el primero que salga y
# no distingue la del movil de la del casco, que es justo lo que hace falta.
perfil_movil() {
	timeout 3 pactl list cards 2>/dev/null \
		| awk '/alsa_card/,/Active Profile/' \
		| grep -m1 "Active Profile" | cut -d: -f2- | sed 's/^ *//'
}
perfil_casco() {
	timeout 3 pactl list cards 2>/dev/null \
		| awk '/bluez_card/,0' \
		| grep -m1 "Active Profile" | cut -d: -f2- | sed 's/^ *//'
}

# Mantener el casco en camino de VOZ mientras la llamada este enrutada a el.
#
# No basta con ponerlo al descolgar, que es lo que hacia este guion hasta el
# 2026-08-06: wireplumber REEVALUA los perfiles cada vez que cambia la tarjeta
# del movil —al pasar a manos libres y al volver— y devuelve el casco a
# `a2dp-sink`, que no tiene camino de voz. Sin perfil de manos libres no se crea
# el enlace eSCO, y sin eSCO la llamada sale muda por el casco.
#
# Medido con btmon ese dia: los eSCO se desconectan con
# `Reason: Connection Terminated By Local Host (0x16)` en ese instante exacto.
# No se cae por radio ni lo tira el casco: lo tiramos nosotros.
#
# ⚠️ SIEMPRE CVSD, nunca mSBC. `bt_sco_rate` del modulo snd_soc_sm8250 esta
# fijado a 8000, o sea banda estrecha. Si el enlace se negocia en mSBC va a
# 16 kHz (`Air mode: Transparent` en la traza) y el DSP sigue escribiendo a 8:
# eSCO en pie, rutas correctas, cero trafico por HCI y silencio. Y mSBC tiene
# MAS prioridad que CVSD (6 frente a 5), asi que si no se fuerza, se elige solo.
#
# Solo se actua cuando el movil tiene la llamada puesta en Bluetooth, para no
# pisar al usuario cuando esta en el auricular de la oreja o en manos libres.
#
# Para desactivarlo: touch /etc/bt-no-mantener-voz
mantener_voz() {
	[ -e /etc/bt-no-mantener-voz ] && return 0
	hay_llamada || return 0
	case "$(perfil_movil)" in
		*Bluetooth*) ;;
		*) return 0 ;;
	esac
	P=$(perfil_casco)
	[ -z "$P" ] && return 0
	[ "$P" = "headset-head-unit-cvsd" ] && return 0
	C=$(timeout 3 pactl list short cards 2>/dev/null | grep bluez | cut -f2)
	[ -z "$C" ] && return 0
	if timeout 3 pactl set-card-profile "$C" headset-head-unit-cvsd >/dev/null 2>&1; then
		log "casco devuelto al camino de voz (estaba en '$P')"
	else
		log "AVISO: no se pudo poner headset-head-unit-cvsd (estaba en '$P')"
	fi
}

# Apaga el bombeo de audio por HCI.
#
# El chip se monta con "Input/Output Data Path: Vendor Specific (0x01)", es
# decir, el audio va por su bus interno. Pero PipeWire sigue escribiendo en el
# socket SCO igualmente: medido con btmon el 2026-08-06, 5291 paquetes
# "SCO Data TX" a 333/s durante una llamada establecida, y SIN pausa siquiera
# mientras la llamada estaba enrutada al altavoz. Esos paquetes no pintan nada
# y son los que desestabilizan el chip (y detras van las caidas del ADSP).
#
# bluetoothOffloadActive le dice al nodo que el camino de datos lo lleva el
# hardware y que deje de escribir. ⚠️ El id del nodo CAMBIA al reconfigurar la
# tarjeta, asi que hay que releerlo cada vez, no cachearlo.
#
# Para comparar sin tocar el guion: touch /etc/bt-offload-desactivado
hay_sco() {
	hcitool con 2>/dev/null | grep -q "eSCO\|SCO"
}

activar_offload() {
	[ -e /etc/bt-offload-desactivado ] && return 0
	NODO=$(timeout 3 pw-dump 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for o in d:
    p=(o.get('info') or {}).get('props') or {}
    if str(p.get('node.name','')).startswith('bluez_output.') \
       and str(p.get('media.class','')).startswith('Audio/Sink'):
        print(o['id']); break
" 2>/dev/null)
	[ -z "$NODO" ] && return 0
	if [ "$NODO" != "${OFFLOAD_EN:-}" ]; then
		timeout 3 pw-cli s "$NODO" Props '{ bluetoothOffloadActive: true }' \
			>/dev/null 2>&1 && OFFLOAD_EN="$NODO"
	fi
}

# Llevar el sonido al auricular EN CUANTO APARECE su sumidero de musica.
#
# Al desconectarlo, callaudiod (u otro) fija el altavoz como sumidero por
# defecto (`default.configured.audio.sink` en el estado de wireplumber), y esa
# fijacion GANA a la prioridad — asi que al reconectar el sonido se queda en el
# altavoz aunque el auricular tenga mas prioridad (1010 vs 1000).
#
# Solo se actua en la TRANSICION ausente -> presente, no en bucle: si estando
# conectado eliges el altavoz a mano, se respeta.
#
# Para desactivarlo: touch /etc/bt-no-autoconmutar
BT_ANTES=no
autoconmutar() {
	[ -e /etc/bt-no-autoconmutar ] && return 0
	# ⚠️ NUNCA durante una llamada. La conmutacion automatica es cosa de
	# MUSICA: mueve la salida al sumidero A2DP del auricular, y con el perfil
	# en A2DP no hay enlace SCO — sin SCO el chip no abre sus puertos del bus
	# y la llamada sale MUDA. Medido: "AVISO: sin SCO al activar el offload"
	# seguido de "sonido movido a bluez_output" en mitad de la llamada.
	hay_llamada && return 0
	BTS=$(timeout 3 pactl list short sinks 2>/dev/null | grep -oE "^[0-9]+	bluez_output[^	]*" | cut -f2)
	if [ -n "$BTS" ]; then
		if [ "$BT_ANTES" = no ]; then
			timeout 3 pactl set-default-sink "$BTS" >/dev/null 2>&1
			for I in $(timeout 3 pactl list short sink-inputs 2>/dev/null | cut -f1); do
				timeout 2 pactl move-sink-input "$I" "$BTS" >/dev/null 2>&1
			done
			log "auricular conectado: sonido movido a $BTS"
		fi
		BT_ANTES=si
	else
		BT_ANTES=no
	fi
}

# El volumen de la llamada en el casco lo lleva AHORA el enganche lua de
# wireplumber (`mantener-voz-bluetooth.lua`, apartado 3). Aqui hubo una version
# por sondeo que funcionaba pero llegaba con el retardo del bucle; y sobre todo,
# dos escritores sobre la misma ruta se pisarian.
cogido=0
OFFLOAD_EN=""
while true; do
	autoconmutar
	mantener_voz
	if [ $cogido -eq 0 ] && hay_llamada && hay_casco; then
		C=$(timeout 3 pactl list short cards | grep bluez | cut -f2)
		# Sin respaldo a mSBC a proposito: da silencio garantizado con el
		# bt_sco_rate fijo a 8000. Mas vale no montar el enlace que montarlo
		# mudo. Ver el comentario de mantener_voz.
		timeout 3 pactl set-card-profile "$C" headset-head-unit-cvsd >/dev/null 2>&1
		sleep 1
		SINK=$(timeout 3 pactl list short sinks | grep bluez | cut -f2)
		if [ -n "$SINK" ]; then
			# ⚠️ ORDEN: el SCO tiene que existir (el setsockopt del offload
			# actua sobre ESE socket) y la propiedad tiene que ponerse
			# ANTES de que empiece a fluir audio; si no, el nodo ya esta
			# bombeando por HCI y no se entera.
			for i in 1 2 3 4 5 6 7 8 9 10; do
				hay_sco && break
				sleep 0.5
			done
			hay_sco && log "SCO en pie, activando offload antes de reproducir" \
				|| log "AVISO: sin SCO al activar el offload"
			activar_offload
			# En segundo plano a secas (dentro de una unidad de usuario no
			# hay DBUS_SESSION_BUS_ADDRESS y systemd-run anidado falla).
			( while hay_llamada; do
				  paplay --device="$SINK" "$HOME/.local/share/surya/silencio.wav" \
					  >/dev/null 2>&1 || sleep 1
			  done ) &
			SCO_PID=$!
			cogido=1
			ANTES=""
			CICLO_HECHO=""
		fi
	elif [ $cogido -eq 1 ] && hay_llamada; then
		# El nodo se recrea al cambiar de salida: reaplicar si cambio el id.
		activar_offload
	elif [ $cogido -eq 1 ] && ! hay_llamada; then
		[ -n "${SCO_PID:-}" ] && kill $SCO_PID 2>/dev/null
		pkill -x paplay 2>/dev/null
		SCO_PID=""
		cogido=0
		OFFLOAD_EN=""
		# Devolver el auricular a MUSICA al colgar.
		#
		# Al descolgar se le pone headset-head-unit-cvsd (mono, camino de
		# voz) y wireplumber GUARDA ese perfil como el del dispositivo. Si
		# no se deshace, al reconectarlo entra en perfil de llamada, no hay
		# sumidero de musica al que saltar, y el sonido se queda en el
		# altavoz — parece que "no salta al Bluetooth" cuando lo que pasa
		# es que no hay adonde saltar.
		C=$(timeout 3 pactl list short cards 2>/dev/null | grep bluez | cut -f2)
		if [ -n "$C" ]; then
			timeout 3 pactl set-card-profile "$C" a2dp-sink >/dev/null 2>&1 \
				|| timeout 3 pactl set-card-profile "$C" a2dp-sink-sbc >/dev/null 2>&1
			log "auricular devuelto a A2DP"
		fi
	fi
	sleep 1
done
