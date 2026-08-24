# Un perro guardián que exige que el móvil SIRVA, no sólo que respire

## El problema que resuelve

`systemd` acaricia `/dev/watchdog` desde **PID 1**. Eso sólo prueba que PID 1 existe.

El **2026-08-23** el móvil estuvo minutos congelado —pantalla muerta, teclas sin respuesta,
sin red— con systemd vivo acariciando tan tranquilo. El perro **no ladró** hasta que systemd
también murió. Y sin poder reiniciar en caliente hubo que apagar con el botón: eso **borra la
RAM**, y con ella ramoops. **Cero evidencia de un cuelgue de varios minutos.**

📌 Medido en ese mismo volcado: cuando PID 1 deja de acariciar, el perro ladra en **~5 s**
(`timeout=5`, `pretimeout=1`). El mecanismo funciona; lo que falla es el **criterio**.

## Qué hace este

Coge el perro y lo acaricia **sólo si el móvil supera una prueba de vida real**: crear un
proceso, escribir y leer un fichero, y leer `/proc`. Justo lo que deja de funcionar en un
congelado aunque PID 1 siga en pie.

Si falla varias veces seguidas, **deja de acariciar** → reinicio **por hardware en caliente** →
la RAM se conserva → **ramoops queda intacto** y el rastro aparece en
`/var/lib/systemd/pstore/` al arrancar.

Con los valores de serie (`PLAZO=30 CADA=5 FALLOS=2`), un congelado real reinicia en **40-60 s**
sin tocar nada.

## ⚠️⚠️ EL TRASPASO NO SE PUEDE HACER EN CALIENTE. Aprendido a base de reinicio.

En este SoC el perro **no se puede parar una vez arrancado**. Al quitárselo a systemd con
`daemon-reexec`, el kernel dijo:

```
[5846.9] watchdog: watchdog0: watchdog did not stop!
[5850.9] Kernel panic - not syncing: watchdog pretimeout event
```

systemd cerró el dispositivo **sin el cierre mágico**, el hardware siguió armado, nadie lo
acariciaba, y mordió **4 segundos después**. El móvil se reinició en mitad de la instalación.

📌 **Por tanto: el traspaso tiene que ocurrir EN EL ARRANQUE.** systemd no debe abrirlo nunca
(`RuntimeWatchdogSec=0`) y `perro-vivo` lo coge desde el principio.

## Instalar (y reiniciar)

```sh
# 1) que systemd no lo abra nunca
sudo tee /etc/systemd/system.conf.d/watchdog.conf <<'EOF'
[Manager]
RuntimeWatchdogSec=0
RebootWatchdogSec=15
EOF

# 2) instalar y habilitar -- SIN --now
sudo install -m755 perro-vivo.sh /usr/local/sbin/
sudo install -m644 perro-vivo.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable perro-vivo

# 3) REINICIAR. El traspaso ocurre aqui, y solo aqui.
```

⚠️ **Entre el paso 1 y el reinicio no hay perro vigilando.** Es un hueco asumible y corto; lo
que NO se puede hacer es intentar cerrarlo en caliente, que es justo lo que provocó el reinicio.

Después: `journalctl -u perro-vivo -f`

## Riesgos, dichos claramente

⚠️ **Una prueba de vida demasiado estricta reinicia el móvil sin motivo.** Por eso la prueba es
barata, el plazo generoso y hacen falta **dos fallos seguidos**. Aun así, es un servicio que
puede reiniciar el móvil: vigílalo unos días antes de fiarte.

⚠️ **Si el propio guion muere y no vuelve, el perro muerde.** Es lo que se quiere en un
congelado, pero también significa que un fallo suyo reinicia. Lleva `Restart=always`.

⚠️ Al pararlo escribe `'V'` (**cierre mágico**) para desarmar el perro. Sin eso, el móvil se
reiniciaría solo tras un apagado limpio.

## Alternativa sin instalar nada

**Esperar.** Si el congelado llega a matar a systemd, el perro de systemd ya reinicia en ~5 s.
Lo que este añade es cubrir el caso «congelado con PID 1 vivo», que es el que nos dejó sin
evidencia.
