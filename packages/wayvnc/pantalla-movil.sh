#!/bin/sh
# Abre la pantalla de surya en el portatil, por tunel SSH.
# Uso: [MOVIL=host] pantalla-movil [cliente]     (por defecto: surya, remmina)
set -e
CLIENTE="${1:-remmina}"
MOVIL="${MOVIL:-surya}"          # nombre o IP del móvil por SSH

echo "· arrancando wayvnc en el movil..."
ssh "$MOVIL" 'export XDG_RUNTIME_DIR=/run/user/10000
         systemctl --user start wayvnc' || { echo "no se pudo arrancar wayvnc"; exit 1; }

if ! pgrep -f "ssh -f -N -L 5900:localhost:5900" >/dev/null; then
    echo "· abriendo el tunel SSH..."
    ssh -f -N -L 5900:localhost:5900 "$MOVIL"
    sleep 2
fi

echo "· conectando ($CLIENTE)..."
case "$CLIENTE" in
    remmina) remmina -c vnc://localhost:5900 ;;
    vinagre) vinagre vnc://localhost:5900 ;;
    *)       "$CLIENTE" localhost:5900 ;;
esac
