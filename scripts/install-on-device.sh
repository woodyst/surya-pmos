#!/bin/sh
# Copy the device configuration onto a running postmarketOS install.
#
#   ./install-on-device.sh <hostname-or-ip>
#
# It only writes configuration; it never touches the kernel or the packages,
# which come from the image built with pmbootstrap.
set -eu

HOST=${1:?usage: install-on-device.sh <hostname-or-ip>}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

say() { printf '\n== %s\n' "$*"; }

say "ALSA UCM (audio routing and call volume)"
ssh "$HOST" 'sudo mkdir -p /usr/share/alsa/ucm2/conf.d/sm8250'
scp -q "$HERE"/device/audio/*.conf "$HOST":/tmp/
ssh "$HOST" 'sudo mv /tmp/POCO-X3.conf /tmp/HiFi.conf /tmp/VoiceCall.conf \
                     /usr/share/alsa/ucm2/conf.d/sm8250/'

say "wireplumber (Bluetooth calls)"
ssh "$HOST" 'mkdir -p ~/.config/wireplumber/wireplumber.conf.d \
                      ~/.local/share/wireplumber/scripts/device'
scp -q "$HERE"/device/wireplumber/*.conf "$HOST":'~/.config/wireplumber/wireplumber.conf.d/'
# The Lua files MUST go here: anywhere else and wireplumber refuses to start.
scp -q "$HERE"/device/wireplumber/*.lua "$HOST":'~/.local/share/wireplumber/scripts/device/'

say "notifications (sound and vibration)"
scp -q "$HERE"/device/notifications/73-surya-vibra.rules "$HOST":/tmp/
scp -q "$HERE"/device/notifications/'xiaomi,surya.json' "$HOST":/tmp/
ssh "$HOST" 'sudo install -Dm644 /tmp/73-surya-vibra.rules /etc/udev/rules.d/73-surya-vibra.rules
             # /usr/local, not /usr/share: a package upgrade would wipe the latter
             sudo install -Dm644 /tmp/"xiaomi,surya.json" \
                  /usr/local/share/feedbackd/themes/"xiaomi,surya.json"
             sudo udevadm control --reload-rules && sudo udevadm trigger -s input
             pkill -x feedbackd || true'

say "services"
scp -q "$HERE"/device/services/* "$HOST":/tmp/
ssh "$HOST" 'set -e
  mkdir -p ~/.local/bin ~/.config/systemd/user
  install -m755 /tmp/armar-audio-usuario.sh /tmp/llamada-al-bluetooth.sh ~/.local/bin/
  install -m644 /tmp/armar-audio-usuario.service /tmp/llamada-al-bluetooth.service \
                /tmp/hfp-registrado.service /tmp/goa-keyring-fix.service \
                ~/.config/systemd/user/
  sudo install -m755 /tmp/armar-audio-sistema.sh /tmp/hfp-registrado.sh /usr/local/bin/
  sudo install -m644 /tmp/armar-audio.service /tmp/gnss-engine-unlock.service \
                     /etc/systemd/system/
  systemctl --user daemon-reload
  systemctl --user enable armar-audio-usuario llamada-al-bluetooth hfp-registrado goa-keyring-fix
  sudo systemctl daemon-reload
  sudo systemctl enable armar-audio gnss-engine-unlock'

say "Done. Reboot the phone so everything comes up in the right order."
