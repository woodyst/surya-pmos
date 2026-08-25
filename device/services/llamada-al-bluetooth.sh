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

# El estado de llamada lo mantienen los eventos de ModemManager (CallAdded /
# CallDeleted), no una consulta. Antes esto lanzaba `sudo mmcli` UNA VEZ POR
# SEGUNDO — 278 invocaciones en 5 minutos medidas el 2026-08-12, cada una
# levantando sudo (con PAM y su linea en el journal) y mmcli (que abre D-Bus y
# habla con el modem). Con el movil cargado se notaba de sobra.
LLAMADA=no
hay_llamada() { [ "$LLAMADA" = si ]; }

# Solo se consulta al arrancar, para partir de un estado correcto si el guion
# se reinicia con una llamada ya en curso.
consultar_llamada_inicial() {
	if sudo -n mmcli -m 0 --voice-list-calls 2>/dev/null | grep -q "/Call/"; then
		LLAMADA=si
	else
		LLAMADA=no
	fi
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

# ¿Esta la LLAMADA puesta en el casco, o sigue en el auricular de la oreja?
#
# ⚠️⚠️ ESTA ES LA CONDICION QUE FALTABA, y costo una llamada muda de dos minutos
# el 2026-08-24. Sin la tarjeta del movil en el perfil «Voice Call (Bluetooth)»
# NADIE tiene motivo para levantar el eSCO: esperarlo antes de eso es esperar
# algo que todavia no puede pasar. Lo medido en la llamada que fallo:
#
#   17:52:46.8  llamada aceptada; el cvp nace en los puertos internos (tx 120 / rx 20)
#   17:52:49.5  el casco APARECE (lo saca de la caja con la llamada ya sonando)
#   17:52:55.7  este guion se rinde: «sin SCO» ... y se quedaba enganchado asi
#   17:52:56.3  la llamada SE MUEVE al Bluetooth (tx 120 -> 151)   <-- UN SEGUNDO TARDE
#
# Dos minutos de llamada muda por un segundo. La llamada siguiente, con el casco
# ya conectado de antes, engancho el SCO en 1,6 s: la diferencia no era el casco
# ni la radio, era el ORDEN.
en_bluetooth() {
	case "$(perfil_movil)" in
		*Bluetooth*) return 0 ;;
		*) return 1 ;;
	esac
}

# Estado REAL de la llamada, preguntando al modem.
#
# ⚠️ Solo se usa dentro del enganche del SCO, que es un bucle bloqueante: ahi el
# lector de eventos esta parado y `LLAMADA` se queda RANCIA, asi que sin esto
# seguiriamos peleando por levantar un enlace para una llamada ya colgada.
# ⚠️⚠️ Y SOLO AHI. Esto es `sudo` + `mmcli`, y en su dia el guion lo hacia UNA VEZ
# POR SEGUNDO: 278 invocaciones en 5 minutos, con su PAM y su linea en el diario
# cada una, y se notaba en la bateria. Aqui son 5 como mucho, y solo al empezar
# una llamada con casco.
llamada_de_verdad() {
	if sudo -n mmcli -m 0 --voice-list-calls 2>/dev/null | grep -q "/Call/"; then
		LLAMADA=si
		return 0
	fi
	LLAMADA=no
	return 1
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

# Mantener OCUPADO el nodo interno mientras dure la llamada.
#
# Con la llamada en el casco Bluetooth la ruta interna queda ociosa; si
# wireplumber la suspende, el ciclo de relojes LPASS revienta el AFE del DSP
# (`PDM: service 'audio_process' crash`), se va el chip del bus, todo da -110 y
# el movil se REINICIA. Por eso existia 55-no-suspender.conf.
#
# Pero aquel fichero desactivaba la suspension SIEMPRE, y eso sale caro: con el
# nodo eternamente en RUNNING el ADSP no duerme nunca, y con el ADSP despierto
# el SoC entero no entra en aosd/cxsd — medido el 2026-08-12 con qcom_stats:
# adsp count=0, aosd count=0. La bateria se va en eso.
#
# Asi que la suspension vuelve a estar permitida, y aqui se sostiene el nodo
# SOLO mientras hay llamada: reproduciendo silencio, igual que ya se hacia con
# el sumidero Bluetooth para sostener el SCO. Un nodo que reproduce nunca pasa
# a ocioso, asi que nunca se suspende, asi que no hay ciclo de relojes.
# NO hay «sosten» del nodo interno durante la llamada, y conviene explicar por
# que, porque hubo uno y rompio una llamada de verdad el 2026-08-12.
#
# La idea era: como la suspension por inactividad vuelve a estar permitida (ver
# 55-no-suspender.conf), sostener el nodo interno durante la llamada para que no
# se suspenda, que era lo que reventaba el AFE del DSP.
#
# Dos cosas mal:
#   1. El nombre del sumidero se capturaba AL EMPEZAR la llamada, con la tarjeta
#      todavia en HiFi. Al cambiar al perfil «Voice Call (Bluetooth)» ese
#      sumidero DESAPARECE, y el paplay se quedaba insistiendo sobre uno muerto,
#      peleandose con el perfil de llamada. Resultado: sin audio en el casco.
#   2. Y sobre todo: NO HACIA FALTA. Medido en vivo durante una llamada por
#      Bluetooth, el nodo interno ya esta en RUNNING por si solo
#      (alsa_output.platform-sound.Voice_Call__Bluetooth__sink). Nunca llega a
#      ocioso, asi que nunca se suspende. La nota original —«la ruta interna
#      queda ociosa»— es anterior al perfil de llamada dedicado.
#
# ⚠️ Y hay un motivo mas para no reintroducirlo: ese sumidero ES el camino de
# voz. Meterle silencio es inyectarlo en la llamada.

# El volumen de la llamada en el casco lo lleva AHORA el enganche lua de
# wireplumber (`mantener-voz-bluetooth.lua`, apartado 3). Aqui hubo una version
# por sondeo que funcionaba pero llegaba con el retardo del bucle; y sobre todo,
# dos escritores sobre la misma ruta se pisarian.
cogido=0
OFFLOAD_EN=""

# Una pasada de toda la logica. Antes esto corria cada segundo; ahora se llama
# solo cuando algo ha pasado de verdad.
reevaluar() {
	autoconmutar
	mantener_voz
	paso_principal
}

# Levantar el enlace SCO, insistiendo mientras la llamada siga en el casco.
#
# ⚠️⚠️ HASTA EL 2026-08-24 ESTO ERA DE UN SOLO TIRO: se esperaba el enlace 5 s y,
# hubiera o no, se activaba el offload y se daba por enganchado (`cogido=1`)
# para el resto de la llamada. Con el offload puesto y sin enlace, la llamada se
# queda MUDA aunque el SCO aparezca un segundo despues — y aparecia. Ahora no se
# engancha NADA si no hay SCO, y se reintenta.
#
# ⚠️ Bloquea el lector de eventos mientras dura (unos 25 s como mucho). Por eso
# cada vuelta pregunta al modem por el estado REAL de la llamada: `LLAMADA` no
# se actualiza mientras estamos aqui dentro.
#
# ⚠️⚠️ EL PRESUPUESTO ES TIEMPO, NO INTENTOS, y la diferencia importa. La primera
# version daba «5 intentos» y se los comio en 4,7 s (16:59:44.9 -> 16:59:49.6):
# cuando el sumidero del casco todavia no existe, la vuelta no espera el enlace
# —no hay donde esperarlo— y cuesta ~1 s en vez de ~4. Se rindio a los 5 s... y
# 2,5 s despues el SCO subia a la primera. Contando intentos, un fallo rapido
# agota el presupuesto antes de que al casco le de tiempo a aparecer.
LIMITE_SEG=25

enganchar_sco() {
	intento=0
	FIN=$(( $(date +%s) + LIMITE_SEG ))
	while [ "$(date +%s)" -lt "$FIN" ]; do
		intento=$((intento + 1))
		C=$(timeout 3 pactl list short cards | grep bluez | cut -f2)
		[ -z "$C" ] && { log "el casco ha desaparecido durante el enganche"; return 1; }
		# ⚠️⚠️ PASAR PRIMERO POR AURICULARES (A2DP) SI NO ESTA YA AHI.
		#
		# El enlace eSCO se negocia en la TRANSICION de perfil, no por estar
		# en el perfil de voz. Si el casco ya viene en «manos libres»
		# —porque una llamada anterior no lo devolvio a A2DP, o porque el
		# guion se reinicio— entonces `set-card-profile ... cvsd` es un NO-OP:
		# no cambia nada, no se negocia nada, y no hay SCO. La llamada sale
		# muda con todo aparentemente correcto.
		#
		# Observado por el usuario y confirmado en el diario del 2026-08-25:
		# las DOS llamadas que engancharon a la primera venian de 'a2dp-sink'
		#   16:59:43.6  casco devuelto al camino de voz (estaba en 'a2dp-sink') -> SCO en pie
		#   17:00:27.9  casco devuelto al camino de voz (estaba en 'a2dp-sink') -> SCO en pie
		#
		# ⚠️ Solo si NO hay SCO ya en pie: si lo hay, rebotar el perfil lo
		# tiraria, que es justo lo contrario de lo que venimos a hacer.
		PC=$(perfil_casco)
		if [ "$PC" != "a2dp-sink" ] && ! hay_sco; then
			log "el casco esta en '$PC': lo paso primero por auriculares (A2DP) para que haya transicion"
			timeout 3 pactl set-card-profile "$C" a2dp-sink >/dev/null 2>&1 \
				|| timeout 3 pactl set-card-profile "$C" a2dp-sink-sbc >/dev/null 2>&1
			sleep 1
		fi
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
			for i in 1 2 3 4 5 6; do
				hay_sco && break
				sleep 0.5
			done
			if hay_sco; then
				log "SCO en pie (intento $intento), activando offload antes de reproducir"
				activar_offload
				# En segundo plano a secas (dentro de una unidad de usuario no
				# hay DBUS_SESSION_BUS_ADDRESS y systemd-run anidado falla).
				( while hay_llamada; do
					  paplay --device="$SINK" /home/edi/silencio.wav \
						  >/dev/null 2>&1 || sleep 1
				  done ) &
				SCO_PID=$!
				cogido=1
				ANTES=""
				CICLO_HECHO=""
				return 0
			fi
		else
			# Sin sumidero del casco todavia: esta vuelta no ha esperado
			# nada, asi que se espera aqui. Si no, se queman vueltas a
			# ciegas y el presupuesto se va en segundos.
			sleep 1
		fi
		llamada_de_verdad || { log "la llamada termino durante el enganche"; return 1; }
		en_bluetooth || { log "la llamada ya no esta en el casco; dejo de insistir"; return 1; }
		[ $intento -eq 1 ] && log "aun sin SCO; sigo intentandolo hasta ${LIMITE_SEG}s"
	done
	log "AVISO: sin SCO tras $intento intentos en ${LIMITE_SEG}s -- esta llamada saldra MUDA por el casco"
	return 1
}

paso_principal() {
	# ⚠️ `en_bluetooth` es la condicion nueva del 2026-08-24: sin ella se
	# esperaba el enlace ANTES de que la llamada estuviera puesta en el casco.
	if [ $cogido -eq 0 ] && hay_llamada && hay_casco && en_bluetooth; then
		enganchar_sco
	# ⛔ NO se reengancha automaticamente si el SCO se cae a mitad de llamada,
	# y es a proposito: esa es la limitacion conocida de la cabecera (la vuelta
	# al casco se queda muda aunque todo lo visible este perfecto), vive en otra
	# capa y ya se investigo a fondo. Rebotar el perfil aqui solo anadiria
	# trasiego a un enlace que ya esta mal — medido: thrash Speaker->HiFi->BT y
	# el SCO no vuelve. Cuando se resuelva aquella, este es el sitio.
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
}

# ---------------------------------------------------------------------------
# Bucle de eventos
# ---------------------------------------------------------------------------
# Dos fuentes, mezcladas en una sola tuberia:
#   * gdbus monitor sobre ModemManager -> CallAdded / CallDeleted
#   * pactl subscribe                  -> tarjetas y sumideros que aparecen,
#                                         desaparecen o cambian de perfil
# Mas un latido lento de red de seguridad, por si se escapa algun evento.
#
# En reposo esto consume CERO: ambos procesos duermen bloqueados en su socket.

consultar_llamada_inicial
reevaluar

TICK=30   # red de seguridad, en segundos

# ⚠️ Sin `sed -u`: el sed de busybox del movil no tiene -u y el guion moria al
# arrancar. Las lineas se distinguen por su contenido, que ya es inequivoco.
# ⚠️ `stdbuf -oL` en las dos fuentes: si no, sus salidas se quedan en el buffer
# del pipe y los eventos llegan a rafagas o no llegan.
fuentes() {
	if command -v gdbus >/dev/null 2>&1; then
		stdbuf -oL gdbus monitor --system \
			--dest org.freedesktop.ModemManager1 2>/dev/null &
	else
		log "AVISO: no hay gdbus; sin eventos de llamada, solo latido"
	fi
	stdbuf -oL pactl subscribe 2>/dev/null &
	while true; do echo "LATIDO"; sleep $TICK; done &
	wait
}

fuentes | while read -r linea; do
	case "$linea" in
		*CallAdded*)    LLAMADA=si; log "evento: llamada nueva" ;;
		*CallDeleted*)  LLAMADA=no; log "evento: llamada terminada" ;;
		*"on card"*|*"on sink"*) ;;   # cambio de audio: reevaluar sin mas
		LATIDO) ;;                    # red de seguridad periodica
		*) continue ;;                # lo demas no nos incumbe
	esac
	reevaluar
done
