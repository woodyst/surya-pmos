#!/bin/sh
# Avisar a PipeWire de que ya hay camaras.
#
# POR QUE
#   wireplumber enumera las camaras AL ARRANCAR. Los sensores estan en lista negra
#   y se cargan despues (camss-diferido.service), asi que cuando aparecen ya es
#   tarde: `cam -l` las lista, pero la aplicacion sigue sin camara. Hay que
#   reiniciar wireplumber para que las vea.
#
#   Esto lo hacia audio-diferido.service; al desactivarlo el 2026-08-22 se perdio,
#   y la camara dejo de funcionar aunque los modulos estuvieran cargados.
#
# ⚠️⚠️ NUNCA con una llamada en curso: reiniciar wireplumber la deja sin audio.
#    Si hay llamada, no se hace nada -- ya se hara al siguiente arranque.
set -u
sleep 5

if mmcli -m 0 --voice-list-calls 2>/dev/null | grep -q '/Call/[0-9]'; then
	echo "avisar-camaras: hay una llamada en curso, NO toco wireplumber"
	exit 0
fi

U=$(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}' | head -1)
[ -n "$U" ] || { echo "avisar-camaras: no hay sesion de usuario todavia"; exit 0; }

if systemctl --user -M "$U@" restart wireplumber 2>/dev/null; then
	sleep 4
	n=$(systemctl --user -M "$U@" is-active wireplumber 2>/dev/null)
	echo "avisar-camaras: wireplumber reiniciado ($n)"
else
	echo "avisar-camaras: no se pudo reiniciar wireplumber"
fi
