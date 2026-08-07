#!/bin/sh
# Parte de USUARIO del arranque de audio: espera a la cadena de sistema y hace
# el baile de PipeWire.
#
# ⚠️ Los nodos de toma/inyeccion (90-tomas-llamada.conf) no abren si su ruta de
# mezclador esta a 0 y PipeWire se cae entero: rutas puestas ANTES de arrancarlo
# y quitadas despues.
# ⚠️ callaudiod arranca antes de que la tarjeta exista y no detecta el perfil de
# voz (el boton no conmutaria): se relanza al final.
n=0
while [ ! -e /run/audio-armado ] || [ ! -e /proc/asound/card0 ]; do
	n=$((n+1)); [ $n -gt 90 ] && { echo "la cadena de sistema no llego"; exit 1; }
	sleep 2
done
amixer -c0 cset name="MultiMedia2 Mixer VOC_REC_DL" 1 >/dev/null 2>&1
amixer -c0 cset name="VOICE_PLAYBACK_TX Audio Mixer MultiMedia4" 1 >/dev/null 2>&1
systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
systemctl --user restart pipewire;       sleep 5
systemctl --user restart pipewire-pulse; sleep 2
systemctl --user restart wireplumber;    sleep 7
amixer -c0 cset name="MultiMedia2 Mixer VOC_REC_DL" 0 >/dev/null 2>&1
amixer -c0 cset name="VOICE_PLAYBACK_TX Audio Mixer MultiMedia4" 0 >/dev/null 2>&1
pkill -x callaudiod 2>/dev/null
sleep 2
pgrep -x callaudiod >/dev/null || setsid /usr/bin/callaudiod >/dev/null 2>&1 &
systemctl --user restart llamada-al-bluetooth 2>/dev/null
exit 0
