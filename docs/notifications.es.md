# Notificaciones: sonido y ★VIBRACIÓN — RESUELTO (2026-08-07)

Las notificaciones **llegaban** (el aviso salía en pantalla) pero **no sonaban ni vibraban**.
Eran **tres causas apiladas**, ninguna evidente.

## ★★★ 1. La vibración iba al dispositivo equivocado — cierra un hilo abierto desde julio

surya tiene **DOS** dispositivos de entrada con vibración:

| dispositivo | qué es | ¿vibra? |
|---|---|---|
| `pm8xxx_vib_ffmemless` (event4) | vibrador del PMIC | **NO** — acepta órdenes y no mueve nada |
| `aw8695-haptics` (event5, i2c-1 @0x5a) | **el motor háptico real del móvil** | **SÍ** |

**Los dos** venían etiquetados `FEEDBACKD_TYPE=vibra` por `/usr/lib/udev/rules.d/72-feedbackd.rules`
(que trae una regla para `aw8695-haptics` **y** otra genérica que pilla al del PMIC), y `feedbackd`
usa **el primero que encuentra** — el que no sirve.

⚠️⚠️ **LA LECCIÓN**: desde julio se daba por hecho que «la vibración no funciona» y se depuraba el
driver del PMIC (parches 0056/0057: nodo activado, bug de *shift* corregido, «el driver enlaza pero
NO vibra»). **El driver estaba bien; el motor era otro.** Nadie miró si había un segundo dispositivo.

**Arreglo**: `73-surya-vibra.rules` quita la etiqueta al del PMIC.

## 2. El demonio estaba atascado (por eso no sonaba NADA)

`feedbackd` repetía sin parar **`Feedback 0xffff... already present`**: un aviso previo se quedó
colgado y **bloqueaba todos los siguientes**. Reiniciarlo lo desbloqueó y el sonido volvió.

⚠️ **Queda abierto**: no se sabe **qué** aviso se queda enganchado. Si vuelve a pasar, hay que
averiguarlo — es un fallo de verdad, no configuración. Síntoma: `fbcli` no produce nada y el
registro del servicio repite «already present».

## 3. Las notificaciones genéricas NO tienen sonido en el tema de serie

El tema `default.json` define `notification-new-generic` **solo como vibración, y solo en el perfil
`quiet`** (magnitud 0,25). **Ningún perfil le pone sonido.** Por eso `fbcli -E message-new-instant`
sonaba pero una notificación real no: **son eventos distintos**.

📌 Los perfiles son **acumulativos**: el perfil `full` reproduce también lo de `quiet`. Por eso la
vibración se ajusta en `quiet` aunque el móvil esté en modo completo (así lo hacen los temas de
`xiaomi,davinci` y compañía).

**Arreglo**: tema propio `xiaomi,surya.json` que añade **sonido** a `notification-new-generic` y
sube la vibración de 0,25/50 ms a **1,0/250 ms**, más respuesta háptica a las **pulsaciones de
tecla y botón** (que era otro pendiente del usuario).

## Instalación

```sh
sudo install -Dm644 73-surya-vibra.rules /etc/udev/rules.d/73-surya-vibra.rules
sudo udevadm control --reload-rules && sudo udevadm trigger -s input

# ⚠️ en /usr/local, NO en /usr/share: una actualización del paquete borraría el tema
sudo install -Dm644 'xiaomi,surya.json' '/usr/local/share/feedbackd/themes/xiaomi,surya.json'
pkill -x feedbackd     # se relanza solo por D-Bus al siguiente aviso
```

Verificado: `Loading theme file at '/usr/local/share/feedbackd/themes/xiaomi,surya.json'`.
📌 `feedbackd` elige el fichero por el `compatible` del árbol: busca `xiaomi,surya-huaxing.json` y
luego `xiaomi,surya.json`, en `/usr/local/share` **antes** que en `/usr/share`.

## Cómo diagnosticar esto

`feedbackd` no registra nada útil por sí solo. Hay que ejecutarlo a mano:

```sh
pkill -x feedbackd      # ⚠️ -x, NUNCA -f: 'pkill -f' mata la propia sesión ssh
G_MESSAGES_DEBUG=all /usr/libexec/feedbackd 2>&1 | tee /tmp/fbd.log &
notify-send "prueba" "cuerpo"        # la vía REAL, no fbcli
grep -E "Event .* for|Running .* feedbacks|Sound event|Vibra" /tmp/fbd.log
```

⚠️ **`fbcli` no reproduce el caso real**: dispara `message-new-instant`, y una notificación normal
dispara `notification-new-generic`, que tiene otra configuración. Probar siempre con `notify-send`.

## Dónde se elige cada tema (dos cosas distintas, se confunden)

- **Sonidos** (qué fichero suena): `org.gnome.desktop.sound theme-name`. En este móvil está en
  `__custom`, un tema del usuario en `~/.local/share/sounds/` que hereda de `phosh` y solo cambia
  dos campanas. **Correcto, no era el problema.**
- **Avisos** (qué hace cada evento: sonido, vibración o luz): `org.sigxcpu.feedbackd theme`,
  en `default`, con los ficheros en `/usr/share/feedbackd/themes/`.

## Pendiente

- La vibración **sigue siendo floja** aunque la magnitud esté al máximo (1,0) y
  `max-haptic-strength` también. El usuario la ha dado por buena. Si se quisiera más: el AW8695 es
  un motor **lineal**, y solo rinde excitado en su **frecuencia de resonancia**; habría que mirar si
  el driver la calibra (`drivers/input/misc/aw8695-haptics.c`, en el árbol como
  `CONFIG_INPUT_AW8695_HAPTICS=m`).
- Valorar **desactivar el vibrador del PMIC** en el árbol de dispositivos (lo activó el parche
  0056) ahora que se sabe que no es el motor real.
