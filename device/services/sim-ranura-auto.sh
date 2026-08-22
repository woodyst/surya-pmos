#!/bin/sh
# Apunta la sesion de aprovisionamiento del modem a la ranura donde ESTE la SIM.
#
# EL PROBLEMA
#   La sesion "Primary GW" del modem se guarda apuntando a una ranura FISICA. Al cambiar la
#   tarjeta de ranura, esa sesion sigue apuntando a la vieja -- ahora vacia -- y el modem
#   nunca aprovisiona la tarjeta nueva:
#
#     Primary GW:   session doesn't exist
#     Slot [1]: Application [1] usim, Application state: 'detected'   <- detectada, sin sesion
#     Slot [2]: Card state: 'error: no-atr-received'                  <- la vieja, vacia
#
#   ModemManager entonces ni siquiera puede consultar el estado de bloqueo y se queda en bucle:
#
#     [modemN] couldn't be initialized: Couldn't check unlock status:
#              QMI operation failed: GW primary session index unknown
#     [modemN] state changed (locked -> failed)
#
#   Visto el 2026-08-19 al pasar la SIM de la ranura 2 a la 1.
#
# QUE HACE
#   Busca la ranura con tarjeta presente, coge el AID de su aplicacion USIM, y si la sesion
#   primaria no apunta ya ahi, la cambia. Es IDEMPOTENTE: si ya esta bien, no toca nada.
#
# ⚠️ Se ejecuta ANTES de ModemManager, porque si MM arranca con la sesion mala se queda en
#    bucle de reintentos y ya no sale solo.
# ⚠️ Espera a que el servicio UIM responda: tras arrancar, el modem tarda en registrar sus
#    servicios QMI y una consulta temprana falla sin que eso signifique nada.
# ⚠️ NO tocar el remoteproc del modem ni rmtfs: cuelgan el movil.
D=qrtr://0
log() { logger -t sim-ranura "$*"; echo "sim-ranura: $*"; }

# Esperar a que la TARJETA este leida, no solo a que el servicio UIM conteste.
# ⚠️ En el arranque el UIM responde varios segundos antes de que el modem haya leido la
#    tarjeta: la consulta funciona pero no lista ninguna aplicacion, y el guion se iba sin
#    hacer nada ("no encuentro el AID"). Medido el 2026-08-19 en el primer intento.
t=0
while [ $t -lt 90 ]; do
  CARD=$(qmicli -d $D --uim-get-card-status 2>/dev/null)
  echo "$CARD" | grep -q "Application type" && break
  sleep 3; t=$((t+3))
done
if [ $t -ge 90 ]; then log "el modem no ha leido ninguna tarjeta tras ${t}s: no hago nada"; exit 0; fi
log "tarjeta leida tras ${t}s"

SLOTS=$(qmicli -d $D --uim-get-slot-status 2>/dev/null)
# ranura con tarjeta presente
RANURA=$(echo "$SLOTS" | awk '/^  Physical slot/ { s=$3; sub(":","",s) } /Card status: present/ { print s; exit }')
if [ -z "$RANURA" ]; then log "ninguna ranura con tarjeta: no hago nada"; exit 0; fi

ACTUAL=$(echo "$CARD" | awk "/Primary GW:/ { print }")

# ¿ya apunta a la ranura buena?
if echo "$ACTUAL" | grep -q "slot '$RANURA'"; then
  log "la sesion primaria ya apunta a la ranura $RANURA, nada que hacer"
  exit 0
fi

# AID de la aplicacion usim de esa ranura
AID=$(echo "$CARD" | awk -v r="$RANURA" '
  $0 ~ "^Slot \\["r"\\]" { en=1; next }
  /^Slot \[/ { en=0 }
  en && /Application type:.*usim/ { usim=1; next }
  en && usim && /Application ID:/ { getline; gsub(/[ \t:]/,""); print; exit }')
if [ -z "$AID" ]; then log "no encuentro el AID de la usim en la ranura $RANURA"; exit 0; fi

log "la tarjeta esta en la ranura $RANURA y la sesion primaria no; la cambio (aid=$AID)"
if qmicli -d $D --uim-change-provisioning-session="session-type=primary-gw-provisioning,activate=yes,slot=$RANURA,aid=$AID" >/dev/null 2>&1; then
  sleep 3
  EST=$(qmicli -d $D --uim-get-card-status 2>/dev/null | awk "/Primary GW:/ { print }")
  log "hecho: $EST"
else
  log "el cambio de sesion FALLO"
fi
