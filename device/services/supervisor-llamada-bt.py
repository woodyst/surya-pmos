#!/usr/bin/env python3
"""Supervisor de la cadena de llamada por casco Bluetooth — surya (POCO X3 NFC).

QUE HACE
  Con una llamada en curso y el casco conectado, se asegura de que la llamada va
  al casco: casco en voz (CVSD), enlace eSCO adquirido por el movil y tarjeta del
  movil en «Voice Call (Bluetooth)». Si falla el lado del casco, lo desmonta y lo
  vuelve a montar. Avisa con una notificacion cuando queda montado y cuando algo
  falla. Sustituye a llamada-al-bluetooth.sh. Documento: bluetooth-call/SUPERVISOR.md

⚠️⚠️ LA TARJETA DEL MOVIL NO SE MUEVE DOS VECES SEGUIDAS
  Pruebas reales del 2026-09-10: TODAS las llamadas mudas tenian el canal de
  bajada del SLIMbus (157) arrancado dos veces con 1,3-1,5 s de separacion (la
  tarjeta entraba en Bluetooth, salia y volvia a entrar) y TODAS las que se oian
  lo tenian arrancado una vez. Cuando pasa, la llamada no se recupera aunque
  despues todo lo visible este bien. Por eso:
    - con la tarjeta en Bluetooth, el supervisor NUNCA la saca durante la
      llamada; la unica excepcion es que el casco se desconecte (al auricular);
    - desmontar y volver a montar se limita al LADO DEL CASCO (perfil y SCO);
    - volver a meter la tarjeta en Bluetooth espera GUARDA_RUTAS_SEG desde que
      salio (casco desconectado y reconectado).
  La tarjeta la pone en el casco wireplumber al empezar la llamada, igual que
  callaudiod; el supervisor solo la mueve si no esta en el casco.

⚠️ REFUTADO: «si las rutas se rearrancan, rehacer el enlace despues». Se probo
  el 2026-09-10 a las 15:45: tres vueltas del altavoz con el SCO rehecho detras
  del rearranque, y las tres mudas o a medias. Retirado.

POR QUE ADQUIERE EL SCO EL MISMO
  Con `bluez5.hw-offload-sco = true` wireplumber no crea nodos SCO: crea un
  loopback pasivo (createOffloadScoNode en monitors/bluez.lua) y NADIE adquiere
  el transporte. En PipeWire 1.6.8 la unica via es la propiedad del DISPOSITIVO
  (bluez5-device.c: apply_prop_offload_active -> spa_bt_transport_acquire).

POR EVENTOS, NUNCA SONDEO
  En reposo no ejecuta nada: duerme esperando senales D-Bus de ModemManager,
  eventos de `pactl subscribe` y lineas del diario del kernel. Con llamada hay
  ademas una revision cada VIGILANCIA_SEG segundos, y solo mientras monta
  consulta capas en bucle, durante segundos. Los eventos se agrupan.

⚠️ NUNCA reinicia wireplumber, pipewire, bluetoothd, rmtfs ni remoteprocs, ni
   hace rfkill, ni pregunta al adaptador con hciconfig.
⚠️ Con el chip Bluetooth encallado («Retry BT power ON:2») no toca NADA del
   Bluetooth: cada intento puede colgar el movil (lo avisa aviso-bt-caido).
⚠️ Los guiones lua de wireplumber 0.5.15 NO pueden leer ni escribir ficheros:
   una primera version se comunicaba con ellos por ficheros y no llego a
   funcionar nunca (la bandera `llamada-en-curso` del lua tampoco existio jamas).
"""

import json
import os
import re
import signal
import subprocess
import threading
import time
import traceback

MODO = os.environ.get("SUPERVISOR_MODO", "actuar")          # actuar | observar
MAX_REPARACIONES = int(os.environ.get("SUPERVISOR_MAX_REPARACIONES", "3"))
VIGILANCIA_SEG = int(os.environ.get("SUPERVISOR_VIGILANCIA_SEG", "15"))
# Cuanto esperar para volver a meter la tarjeta en el casco desde que salio. Las
# mudas fueron con 1,3-1,5 s; la vuelta del altavoz a mano, con varios segundos,
# si funcionaba con el guion viejo. 8 s es margen, no una medida.
GUARDA_RUTAS_SEG = float(os.environ.get("SUPERVISOR_GUARDA_RUTAS_SEG", "8"))
DOBLE_ARRANQUE_SEG = 3.0      # por debajo de esto se avisa: medido 1,3-1,5 s en las mudas

TARJETA_MOVIL = "alsa_card.platform-sound"
P_MOVIL_BT = "Voice Call (Bluetooth)"
P_MOVIL_AURICULAR = "Voice Call (Earpiece)"
P_MOVIL_ALTAVOZ = "Voice Call (Speaker)"
# ⚠️ SIEMPRE CVSD, nunca mSBC: bt_sco_rate esta fijo a 8000 y con mSBC el enlace
# sube a 16 kHz con el DSP escribiendo a 8 -> eSCO en pie y silencio absoluto.
P_CASCO_VOZ = "headset-head-unit-cvsd"
# Sin negociacion de codec (p. ej. oFono haciendo de casco en un portátil) el perfil sale sin
# sufijo, y tambien es CVSD. Los guiones viejos ya caian a el; el supervisor lo
# perdio y con ese casco falso decia «casco sin manos libres» (2026-09-10). Nunca mSBC.
P_CASCO_VOZ_SIN_CODEC = "headset-head-unit"
PERFILES_VOZ = (P_CASCO_VOZ, P_CASCO_VOZ_SIN_CODEC)


def perfil_voz(casco):
    """El perfil de voz CVSD que ofrece el casco (el de codec negociado primero), o None."""
    if not casco:
        return None
    return next((p for p in PERFILES_VOZ if casco["perfiles"].get(p)), None)
P_CASCO_MUSICA = ("a2dp-sink", "a2dp-sink-sbc")
PUERTO_TX_CASCO = 151
PCM_VOZ = "/proc/asound/card0/pcm4p/sub0/status"
# Parche 0129 (kernel r81): rehacer la sesion de voz ENTERA (MVM+CVS+CVP) al
# mover la llamada. El 2026-09-10 a las 17:10 se aplico tambien al PRIMER paso
# al casco de la llamada y coincidio con el ADSP estrellado (y detras el modem).
# Por eso va apagado por defecto (bluetooth-call/scripts/q6voice-modprobe.conf) y el supervisor
# solo lo enciende cuando la llamada ya ha salido del casco: afecta a la VUELTA.
PARAM_SESION_COMPLETA = "/sys/module/q6voice/parameters/switch_full_session"

MM = "org.freedesktop.ModemManager1"
MM_DIALING, MM_RINGING_OUT, MM_RINGING_IN, MM_ACTIVE, MM_HELD = 1, 2, 3, 4, 5
# Una entrante SONANDO no cuenta: el audio de la llamada aun no existe.
ESTADOS_CON_AUDIO = (MM_DIALING, MM_RINGING_OUT, MM_ACTIVE, MM_HELD)


def log(msg):
    print("supervisor: " + msg, flush=True)


def _entero(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def parse_tarjetas(texto):
    """`pactl -f json list cards` -> {"movil": info|None, "casco": info|None}."""
    res = {"movil": None, "casco": None}
    for c in json.loads(texto):
        nombre = c.get("name") or ""
        info = {
            "nombre": nombre,
            "perfil": c.get("active_profile") or "",
            "perfiles": {k: bool((v or {}).get("available"))
                         for k, v in (c.get("profiles") or {}).items()},
            # object.id de la tarjeta = id del DISPOSITIVO en PipeWire
            "id": _entero((c.get("properties") or {}).get("object.id")),
        }
        if nombre == TARJETA_MOVIL:
            res["movil"] = info
        elif nombre.startswith("bluez_card."):
            res["casco"] = info
    return res


class Nucleo:
    """Lo que el diario del kernel dice de la cadena. Solo se lee: es pasivo."""

    RE_TX = re.compile(r"(?:creating cvp: tx_port=|moving call: tx_port \d+ -> )(\d+)")
    RE_CANAL = re.compile(r"wcn-bt-slim .*bus channel (157|159) reserved")
    RE_ERROR_SLIM = re.compile(r"(?:wcn-bt-slim|slim-ngd).*(?:-110|timed out|failed)")
    RE_CHIP_CAIDO = re.compile(r"Retry BT power ON:2")

    def __init__(self, reloj=time.monotonic):
        self.reloj = reloj
        self.tx = None
        self.t_tx = 0.0
        self.t_salida_casco = 0.0      # ultima vez que la llamada salio del puerto del casco
        self.t_canal = {157: 0.0, 159: 0.0}
        self.arranques_157 = []        # instantes en que se reservo el canal de bajada
        self.t_error_slim = 0.0
        self.error_slim = ""
        self.chip_caido = False

    def linea(self, texto, t=None):
        """Anota una linea. Devuelve True si merece una revision."""
        if t is None:
            t = self.reloj()
        m = self.RE_TX.search(texto)
        if m:
            nuevo = int(m.group(1))
            if self.tx == PUERTO_TX_CASCO and nuevo != PUERTO_TX_CASCO:
                self.t_salida_casco = t
            self.tx, self.t_tx = nuevo, t
            return True
        m = self.RE_CANAL.search(texto)
        if m:
            canal = int(m.group(1))
            self.t_canal[canal] = t
            if canal == 157:
                self.arranques_157 = (self.arranques_157 + [t])[-20:]
                return True
            return False
        if self.RE_ERROR_SLIM.search(texto):
            self.t_error_slim, self.error_slim = t, texto.strip()[-120:]
            return True
        if self.RE_CHIP_CAIDO.search(texto):
            self.chip_caido = True
            return True
        return False


class Sistema:
    """Todo lo que lee o cambia en el movil. Las pruebas lo sustituyen."""

    def _cmd(self, args, plazo=4):
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=plazo)
            return r.returncode, r.stdout, r.stderr
        except (subprocess.TimeoutExpired, OSError) as e:
            log("AVISO: %s: %s" % (" ".join(args[:3]), e))
            return -1, "", str(e)

    def tarjetas(self):
        rc, out, err = self._cmd(["pactl", "-f", "json", "list", "cards"])
        if rc != 0:
            log("AVISO: pactl list cards fallo (rc=%s): %s" % (rc, err.strip()[:100]))
            return None
        try:
            return parse_tarjetas(out)
        except (ValueError, AttributeError, TypeError) as e:
            log("AVISO: no entiendo el JSON de pactl: %s" % e)
            return None

    def poner_perfil(self, tarjeta, perfil):
        rc, _, err = self._cmd(["pactl", "set-card-profile", tarjeta, perfil])
        if rc != 0:
            log("AVISO: set-card-profile %s '%s' fallo: %s" % (tarjeta, perfil, err.strip()[:100]))
        return rc == 0

    def esco(self):
        # Lee la tabla de conexiones del KERNEL (ioctl), no le pregunta al chip.
        _, out, _ = self._cmd(["hcitool", "con"])
        return re.search(r"\be?SCO\b", out) is not None

    def offload(self, dev_id, activo):
        valor = "true" if activo else "false"
        for intento in (1, 2):
            rc, _, err = self._cmd(["pw-cli", "s", str(dev_id), "Props",
                                    "{ bluetoothOffloadActive: %s }" % valor])
            if rc == 0 and "rror" not in err:
                return True
            # «no global N any more»: pw-cli se topa con un objeto recien recreado
            # por un cambio de perfil (visto dos veces el 2026-09-10).
            if intento == 1 and ("no global" in err or "Stale" in err):
                time.sleep(0.3)
                continue
            log("AVISO: pw-cli no acepta bluetoothOffloadActive=%s en %s: %s"
                % (valor, dev_id, " ".join(err.split())[:120]))
            return False

    def offload_leido(self, dev_id):
        _, out, _ = self._cmd(["pw-cli", "e", str(dev_id), "Props"])
        m = re.search(r"bluetoothOffloadActive.*?\n\s*Bool (true|false)", out)
        return None if m is None else m.group(1) == "true"

    def mezclador_bt(self):
        _, out, _ = self._cmd(["amixer", "-c0", "cget", "name=SLIMBUS_7_RX Voice Mixer CS-Voice"])
        m = re.search(r": values=(on|off)", out)
        return None if m is None else m.group(1) == "on"

    def sesion_dsp(self):
        try:
            with open(PCM_VOZ) as f:
                return "closed" not in f.read()
        except OSError:
            return None

    def sumideros_casco(self):
        _, out, _ = self._cmd(["pactl", "list", "short", "sinks"])
        campos = (l.split("\t") for l in out.splitlines())
        return [c[1] for c in campos if len(c) > 1 and c[1].startswith("bluez_output.")]

    def sesion_completa(self, activa):
        """True si se escribio, None si el kernel no tiene el 0129, False si fallo."""
        valor = "Y" if activa else "N"
        if not os.path.exists(PARAM_SESION_COMPLETA):
            return None
        try:
            with open(PARAM_SESION_COMPLETA, "w") as f:
                f.write(valor)
            return True
        except PermissionError:
            # El parametro es de root (0644). sudo sin contrasena, como hacia el
            # guion viejo con mmcli; solo al empezar, al salir del casco y al colgar.
            try:
                r = subprocess.run(["sudo", "-n", "tee", PARAM_SESION_COMPLETA],
                                   input=valor, capture_output=True, text=True, timeout=4)
                if r.returncode == 0:
                    return True
                log("AVISO: sudo tee %s fallo: %s" % (PARAM_SESION_COMPLETA, r.stderr.strip()[:100]))
            except (OSError, subprocess.TimeoutExpired) as e:
                log("AVISO: sudo tee %s: %s" % (PARAM_SESION_COMPLETA, e))
            return False
        except OSError as e:
            log("AVISO: no puedo escribir %s: %s" % (PARAM_SESION_COMPLETA, e))
            return False

    def mover_sonido_a(self, sumidero, flujos=True):
        self._cmd(["pactl", "set-default-sink", sumidero])
        if not flujos:
            return True
        _, out, _ = self._cmd(["pactl", "list", "short", "sink-inputs"])
        for l in out.splitlines():
            i = l.split("\t")[0]
            if i.isdigit():
                self._cmd(["pactl", "move-sink-input", i, sumidero], plazo=2)
        return True


class Supervisor:
    """La logica. Sin hilos ni D-Bus: `revisar()` es una pasada sincrona."""

    def __init__(self, sistema, nucleo, llamadas, avisar, reloj=time.monotonic,
                 dormir=time.sleep, modo=MODO, max_reparaciones=MAX_REPARACIONES,
                 guarda_rutas=GUARDA_RUTAS_SEG):
        self.sis = sistema
        self.nucleo = nucleo
        self.llamadas = llamadas      # () -> {ruta: estado MM} | None si no contesta
        self.avisar = avisar          # (clave, titulo, cuerpo, urgencia 0/1/2)
        self.reloj = reloj
        self.dormir = dormir
        self.modo = modo
        self.max_reparaciones = max_reparaciones
        self.guarda_rutas = guarda_rutas
        self.en_llamada = False
        self.t_fin_llamada = 0.0
        self.casco_antes = None
        self.perfiles_vistos = None
        self.sesion_completa_puesta = None
        self.bt_antes = False
        self._reiniciar_llamada()

    def _reiniciar_llamada(self):
        self.montado = False
        self.rendido = False
        self.reparaciones = 0
        self.eleccion = None          # None | "altavoz"
        self.paso_por_altavoz = False # desde entonces no se avisa de dobles arranques
        self.volviendo = False        # acabas de volver del altavoz
        self.t_altavoz = 0.0          # cuando pasaste al altavoz
        self.tocado = False           # si esta llamada ha tocado el casco
        self.avisado = set()
        self.t_llamada = 0.0
        self.t_sco = 0.0              # cuando se establecio el enlace vigente

    # ── utilidades ─────────────────────────────────────────────────────────
    def estado_llamada(self):
        """True/False, o None si ModemManager no contesta (y entonces no se toca nada)."""
        ll = self.llamadas()
        if ll is None:
            return None
        return any(e in ESTADOS_CON_AUDIO for e in ll.values())

    def _hacer(self, que, fn, *args):
        if self.modo != "actuar":
            log("(observar) haria: " + que)
            return True
        log("   -> " + que)
        return fn(*args)

    def _esperar(self, cond, plazo, paso=0.25):
        fin = self.reloj() + plazo
        while True:
            try:
                if cond():
                    return True
            except Exception as e:      # una comprobacion rota no debe tumbar el montaje
                log("AVISO: comprobacion con error: %s" % e)
            if self.reloj() >= fin:
                return False
            self.dormir(paso)

    def _perfil(self, cual):
        t = self.sis.tarjetas()
        info = t and t[cual]
        return info["perfil"] if info else None

    def _avisar(self, clave, titulo, cuerpo, urgencia):
        if self.modo != "actuar":
            log("(observar) avisaria [%s]: %s" % (clave, cuerpo.replace("\n", " ")))
            return
        self.avisar(clave, titulo, cuerpo, urgencia)

    def _avisar_una_vez(self, clave, titulo, cuerpo, urgencia):
        if clave not in self.avisado:
            self.avisado.add(clave)
            self._avisar(clave, titulo, cuerpo, urgencia)

    def _anotar_perfiles(self, t):
        """Deja en el diario cada cambio de perfil visto, sea de quien sea."""
        ahora = (t["movil"] and t["movil"]["perfil"], t["casco"] and t["casco"]["perfil"])
        antes = self.perfiles_vistos or (None, None)
        if ahora == antes:
            return
        partes = []
        if ahora[0] != antes[0]:
            partes.append("tarjeta '%s' -> '%s'" % (antes[0], ahora[0]))
        if ahora[1] != antes[1]:
            partes.append("casco '%s' -> '%s'" % (antes[1], ahora[1]))
        log("visto: " + ", ".join(partes))
        self.perfiles_vistos = ahora

    # ── la pasada ──────────────────────────────────────────────────────────
    def revisar(self):
        llamada = self.estado_llamada()
        if llamada is None:
            log("AVISO: ModemManager no contesta; no toco nada")
            return
        t = self.sis.tarjetas()
        if t is None:
            return
        self._anotar_perfiles(t)
        casco = t["casco"] is not None
        if casco != self.casco_antes:
            if self.casco_antes is not None:
                log("casco %s" % ("conectado" if casco else "desconectado"))
            if casco:                 # conectarlo es una peticion de reintento
                self.rendido, self.reparaciones = False, 0
            self.casco_antes = casco

        if not llamada:
            if self.en_llamada:
                self.fin_de_llamada(t)
            self._poner_sesion_completa(False)
            self.tarjeta_fuera_de_llamada(t)
            self.autoconmutar()
            return
        if not self.en_llamada:
            self.en_llamada = True
            self._reiniciar_llamada()
            self.t_llamada = self.reloj()
            log("llamada con audio en curso (casco %s)" % ("conectado" if casco else "no"))

        # Sesion de voz entera solo si la llamada ya ha salido del casco en esta
        # llamada: el siguiente paso al casco es una VUELTA, no el primero.
        # REFUTADO el 2026-09-10 (17:46): rehacer la sesion entera tampoco trae
        # el audio de vuelta al casco, y a las 17:10 coincidio con el ADSP
        # estrellado. Se deja siempre apagado.
        self._poner_sesion_completa(False)
        self._vigilar_doble_arranque()
        if t["movil"] is None:
            # La tarjeta de sonido ha desaparecido: el DSP de audio se ha caido
            # (2026-09-10 16:00:40, `audio_process ... AfeS`). Ni el casco ni el
            # altavoz tienen arreglo desde aqui, y tocar nada solo empeora (aquel
            # dia se tomo por «vuelves del altavoz» y se intento montar tres veces).
            self.montado = False
            if "sin-tarjeta" not in self.avisado:
                log("AVISO: la tarjeta de sonido ha desaparecido (DSP de audio caido): no toco nada")
            self._avisar_una_vez(
                "sin-tarjeta", "Se ha caido el audio del movil",
                "El procesador de audio se ha caido: esta llamada no tiene sonido. "
                "Cuelga; si al volver a llamar sigue sin sonido, reinicia el movil.", 2)
            return
        objetivo = self.objetivo(t)
        if objetivo == "casco":
            self.asegurar_casco(t)
        elif objetivo == "altavoz":
            self.montado = False
        elif objetivo == "chip-caido":
            if "chip" not in self.avisado:
                self.avisado.add("chip")
                log("AVISO: chip Bluetooth encallado en este arranque: no toco el Bluetooth")
        elif objetivo in ("sin-casco", "casco-sin-hfp"):
            movil = t["movil"]
            if self.montado or (movil and movil["perfil"] == P_MOVIL_BT):
                self.montado = False
                log("la llamada no puede seguir en el casco (%s): al auricular del movil" % objetivo)
                self.devolver_al_auricular(t)
                if objetivo == "sin-casco":
                    self._avisar_una_vez(
                        "desconectado", "Casco desconectado",
                        "La llamada pasa al auricular del movil. Si vuelves a "
                        "conectar el casco, la llevo otra vez a el.", 1)
            if objetivo == "casco-sin-hfp":
                self._avisar_una_vez(
                    "sin-hfp", "Casco sin manos libres",
                    "El casco esta conectado pero sin HFP: la llamada no puede "
                    "ir a el. Apaga y enciende el casco.", 1)

    def objetivo(self, t):
        if self.nucleo.chip_caido:
            return "chip-caido"
        if t["casco"] is None:
            return "sin-casco"
        if perfil_voz(t["casco"]) is None:
            return "casco-sin-hfp"
        movil = t["movil"]
        if movil and movil["perfil"] == P_MOVIL_ALTAVOZ:
            # Solo callaudiod pone el altavoz: wireplumber elige el casco si esta
            # conectado y, si no, por prioridad (el auricular 4400 gana al altavoz
            # 4200). Si esta ahi, lo has pedido tu con el boton: no se pelea. El
            # casco se queda en voz con el enlace en pie (el lua mantener-voz
            # impide la vuelta a A2DP durante toda la llamada) para que la vuelta
            # encuentre el enlace ya montado.
            if self.eleccion != "altavoz":
                self.eleccion = "altavoz"
                self.paso_por_altavoz = True
                self.aparcar_en_musica(t)
            return "altavoz"
        if self.eleccion == "altavoz":
            log("vuelves del altavoz tras %.1f s: rehago el lado del casco como al empezar"
                % (self.reloj() - self.t_altavoz if self.t_altavoz else 0.0))
            self.eleccion = None
            self.rendido, self.reparaciones = False, 0
            self.volviendo = True
        return "casco"

    def aparcar_en_musica(self, t):
        """En altavoz: SCO fuera, casco a A2DP y la salida por defecto al casco.

        Asi la vuelta rehace el lado del casco igual que al empezar la llamada.
        REFUTADO el 2026-09-10 que la vuelta necesite un flujo A2DP o un silencio
        por la voz del casco (17:59, 18:10, 18:11 con 25 s): se quitaron.
        """
        casco = t["casco"]
        self.t_altavoz = self.reloj()
        log("has elegido el altavoz: el casco pasa a musica")
        if casco is None or self.modo != "actuar":
            return
        if casco["id"] is not None:
            self._hacer("soltar el SCO", self.sis.offload, casco["id"], False)
        if casco["perfil"] not in P_CASCO_MUSICA:
            self._casco_a_musica(casco)
        self._salida_al_casco("altavoz", flujos=False)

    def _salida_al_casco(self, momento, flujos):
        """Salida por defecto de PipeWire al sumidero A2DP del casco, SOLO si existe.

        Idea del usuario (2026-09-10): tras la llamada de las 17:48, con el casco
        conectado, el sonido se quedo en los altavoces. En llamada no se mueven
        los flujos (`flujos=False`): solo la salida por defecto.
        """
        if not self._esperar(lambda: bool(self.sis.sumideros_casco()), 3):
            log("   %s: no existe el sumidero A2DP del casco: la salida no se toca" % momento)
            return None
        sumidero = self.sis.sumideros_casco()[0]
        self._hacer("%s: salida por defecto al casco (%s)" % (momento, sumidero.rsplit(".", 1)[-1]),
                    self.sis.mover_sonido_a, sumidero, flujos)
        return sumidero

    def _vigilar_musica(self):
        if not self.t_musica or self.musica_vista:
            return
        bts = self.sis.sumideros_casco()
        if bts and self.sis.estado_sumidero(bts[0]) == "RUNNING":
            self.musica_vista = self.reloj()
            log("flujo A2DP en marcha a los %.1f s de pasar a musica" % (self.musica_vista - self.t_musica))

    def _poner_sesion_completa(self, activa):
        if self.sesion_completa_puesta == activa:
            return
        self.sesion_completa_puesta = activa
        if self.modo != "actuar":
            return
        r = self.sis.sesion_completa(activa)
        if r is None:
            if "sin-0129" not in getattr(self, "_avisos_globales", set()):
                self._avisos_globales = getattr(self, "_avisos_globales", set()) | {"sin-0129"}
                log("este kernel no tiene switch_full_session (parche 0129): la vuelta al casco rehace solo el vocproc")
        elif r:
            log("reconstruccion completa de la sesion de voz: %s"
                % ("SI, para la vuelta al casco" if activa else "no"))

    def _vigilar_doble_arranque(self):
        # Solo al empezar la llamada. Tras pasar por el altavoz, un rearranque es
        # la vuelta que tu pides y avisar de ella no sirve de nada (el usuario lo
        # pidio expresamente el 2026-09-10).
        if self.paso_por_altavoz:
            return
        arr = [x for x in self.nucleo.arranques_157 if x >= self.t_llamada - 5]
        for a, b in zip(arr, arr[1:]):
            if b - a < DOBLE_ARRANQUE_SEG:
                log("AVISO: el canal de bajada del SLIMbus (157) ha arrancado dos veces en %.1f s" % (b - a))
                self._avisar_una_vez(
                    "doble-arranque", "Llamada en el casco: aviso",
                    "La ruta al casco se ha arrancado dos veces seguidas: esta llamada "
                    "puede quedar muda.\nSi no oyes, cuelga y vuelve a llamar.", 1)
                return

    def comprobar(self, t):
        """(lado, texto) de la primera capa que falla, o None si esta entero.

        lado: "casco" (se puede desmontar y montar), "tarjeta" (la tarjeta no esta
        en el casco: se mete una vez) o "rutas" (con la tarjeta en el casco: no
        tiene arreglo sin sacarla y volverla a meter, que es lo que deja muda la
        llamada, asi que solo se avisa).
        """
        casco, movil = t["casco"], t["movil"]
        if casco is None:
            return ("casco", "casco desconectado")
        if casco["perfil"] not in PERFILES_VOZ:
            return ("casco", "perfil del casco ('%s')" % casco["perfil"])
        if not self.sis.esco():
            return ("casco", "enlace eSCO")
        if movil is None or movil["perfil"] != P_MOVIL_BT:
            return ("tarjeta", "tarjeta del movil ('%s')" % (movil and movil["perfil"]))
        n = self.nucleo
        if n.tx != PUERTO_TX_CASCO:
            return ("rutas", "puertos del DSP (tx=%s)" % n.tx)
        if n.t_error_slim > n.t_tx:
            return ("rutas", "SLIMbus (%s)" % n.error_slim)
        if self.sis.mezclador_bt() is False:
            return ("rutas", "mezclador SLIMBUS_7 apagado")
        if self.sis.sesion_dsp() is False:
            return ("rutas", "sesion de voz del DSP cerrada")
        return None

    def asegurar_casco(self, t):
        fallo = self.comprobar(t)
        volvia, self.volviendo = self.volviendo, False
        if fallo is not None and self.modo == "actuar":
            if volvia:
                # El DSP tarda unos cientos de ms en mover la llamada tras el cambio
                # de tarjeta: se le espera a EL y se vuelve a juzgar.
                self._esperar(lambda: self.nucleo.tx == PUERTO_TX_CASCO, 4)
                t2 = self.sis.tarjetas()
                if t2 is not None:
                    fallo = self.comprobar(t2)
            elif fallo[0] == "rutas" and "rutas" not in self.avisado:
                fallo = self._esperar_circuito(4)
        if fallo is None:
            if not self.montado:
                self.montado = True
                if not self.t_sco:          # enlace que ya estaba (supervisor reiniciado)
                    self.t_sco = self.reloj()
                texto = ("De vuelta en el casco: circuito entero." if volvia
                         else "Circuito comprobado: todo en su sitio.")
                log(texto)
                self._avisar("montado", "Llamada en el casco", texto, 0)
                self._aviso_bus_al_empezar()
            return
        if self.rendido:
            return
        lado, texto = fallo
        if self.modo != "actuar":
            if fallo != getattr(self, "_ultimo_observado", None):
                self._ultimo_observado = fallo
                log("(observar) falla: %s" % texto)
            return
        if lado == "rutas":
            self._rutas_sin_arreglo(texto)
            return
        if self.montado:
            self.montado = False
            log("AVISO: se ha caido: %s" % texto)
            self._avisar("fallo", "Llamada en el casco: fallo",
                         "Se ha caido: %s.\nDesmonto el lado del casco y lo vuelvo a montar." % texto, 1)
        self.reparar(texto, volvia)

    def _rutas_sin_arreglo(self, texto):
        self.montado = False
        if "rutas" not in self.avisado:
            log("AVISO: con la tarjeta en el casco fallan las rutas (%s): no las toco" % texto)
        self._avisar_una_vez(
            "rutas", "Llamada en el casco: fallo",
            "Falla: %s.\nNo tiene arreglo sin cortar el audio. Si no oyes, cuelga y "
            "vuelve a llamar." % texto, 1)

    # ── montar y desmontar (el lado del casco) ─────────────────────────────
    def _sigue_pidiendo_casco(self):
        ll = self.estado_llamada()
        if ll is not True:
            return "sin llamada" if ll is False else "ModemManager no contesta"
        t = self.sis.tarjetas()
        if t is None:
            return "pactl no contesta"
        if t["casco"] is None:
            return "casco desconectado"
        if t["movil"] and t["movil"]["perfil"] == P_MOVIL_ALTAVOZ:
            return "has elegido el altavoz"
        return True

    def reparar(self, fallo, volvia=False):
        t0 = self.reloj()
        while True:
            if self.reparaciones >= self.max_reparaciones:
                self.rendirse(fallo)
                return
            self.reparaciones += 1
            log("MONTAJE %d/%d (parto de: %s)" % (self.reparaciones, self.max_reparaciones, fallo))
            self.desmontar_casco()
            if volvia and self.reparaciones == 1:
                self._salida_al_casco("vuelta", flujos=False)
            resultado = None
            # Rutas (solo si la tarjeta no esta en el casco, una vez) ANTES que el
            # enlace: tras cualquier arranque de las rutas el SCO tiene que venir despues.
            for paso in (self.paso_rutas, self.paso_casco_en_voz, self.paso_enlace):
                sigue = self._sigue_pidiendo_casco()
                if sigue is not True:
                    log("dejo el montaje: %s" % sigue)
                    return
                resultado = paso()
                if resultado:
                    break
            if resultado is None:
                f = self._esperar_circuito(5)
                if self.estado_llamada() is not True:
                    log("dejo el montaje: la llamada ha terminado")
                    return
                if f is not None and f[0] == "rutas":
                    self._rutas_sin_arreglo(f[1])
                    return
                resultado = None if f is None else f[1]
            if resultado is None:
                self.montado = True
                seg = self.reloj() - t0
                extra = "" if self.reparaciones == 1 else " (intento %d)" % self.reparaciones
                log("CIRCUITO MONTADO en %.1f s%s" % (seg, extra))
                texto = ("De vuelta en el casco: enlace rehecho en %.1f s%s." if volvia
                         else "Circuito montado en %.1f s%s.") % (seg, extra)
                self._avisar("montado", "Llamada en el casco", texto, 0)
                self._aviso_bus_al_empezar()
                return
            log("AVISO: el montaje %d falla en: %s" % (self.reparaciones, resultado))
            if self.estado_llamada() is not True:
                log("dejo el montaje: la llamada ha terminado")
                return
            if self.reparaciones < self.max_reparaciones:
                self._avisar("fallo", "Llamada en el casco: fallo",
                             "Falla: %s.\nDesmonto el lado del casco y lo vuelvo a montar." % resultado, 1)
            fallo = resultado

    def _aviso_bus_al_empezar(self):
        """Solo al diario, y una vez por llamada.

        Se notificaba como «puede quedar muda» por la llamada de las 14:44 del
        2026-09-10 (error del SLIMbus al empezar y muda entera). Pero la de las
        15:56 dio el mismo error y se oyo perfectamente: no predice nada.
        """
        n = self.nucleo
        if (self.t_llamada and n.t_error_slim >= self.t_llamada - 5
                and "bus-al-empezar" not in self.avisado):
            self.avisado.add("bus-al-empezar")
            log("AVISO: el SLIMbus dio error al empezar la llamada: %s" % n.error_slim)

    def _esperar_circuito(self, plazo):
        ultimo = [("casco", "pactl no contesta")]

        def entero():
            if self.estado_llamada() is False:
                ultimo[0] = ("casco", "la llamada ha terminado")
                return True             # corta la espera; reparar() lo ve y se va
            t = self.sis.tarjetas()
            ultimo[0] = ("casco", "pactl no contesta") if t is None else self.comprobar(t)
            return ultimo[0] is None
        return None if self._esperar(entero, plazo, paso=0.5) else ultimo[0]

    def rendirse(self, fallo):
        self.rendido = True
        log("AVISO: me rindo en esta llamada (%s). La tarjeta NO se mueve" % fallo)
        self._avisar("rendido", "La llamada no ha podido ir al casco",
                     "Falla: %s.\nPulsa altavoz para oirla por el movil; al volver "
                     "al casco lo intento otra vez." % fallo, 2)

    def desmontar_casco(self):
        """Solo el lado del casco: soltar el SCO, casco a A2DP, esperar al eSCO viejo."""
        t = self.sis.tarjetas()
        casco = t and t["casco"]
        if not casco:
            log("desmonto el lado del casco: no hay casco")
            return
        log("desmonto el lado del casco:")
        self.t_sco = 0.0
        if casco["id"] is not None:
            self._hacer("soltar el SCO (bluetoothOffloadActive=false en %d)" % casco["id"],
                        self.sis.offload, casco["id"], False)
        log("   1/2 enlace: SCO soltado")
        if casco["perfil"] not in P_CASCO_MUSICA:
            self._casco_a_musica(casco)
        ok = self._esperar(lambda: not self.sis.esco(), 6, paso=0.5)
        log("   2/2 casco en A2DP; %s" % ("sin eSCO" if ok else "⚠️ el eSCO viejo NO se ha ido"))

    def _casco_a_musica(self, casco):
        perfil = next((p for p in P_CASCO_MUSICA if casco["perfiles"].get(p)), P_CASCO_MUSICA[0])
        self._hacer("casco a '%s'" % perfil, self.sis.poner_perfil, casco["nombre"], perfil)
        return self._esperar(lambda: self._perfil("casco") in P_CASCO_MUSICA, 3)

    def paso_casco_en_voz(self):
        t = self.sis.tarjetas()
        casco = t and t["casco"]
        if not casco:
            return "casco desaparecido"
        self.tocado = True
        voz = perfil_voz(casco)
        if voz is None:
            return "perfil del casco (sin manos libres CVSD)"
        if casco["perfil"] != voz:
            self._hacer("casco a '%s'" % voz, self.sis.poner_perfil, casco["nombre"], voz)
            if not self._esperar(lambda: self._perfil("casco") == voz, 4):
                return "perfil del casco (no pasa a CVSD: '%s')" % self._perfil("casco")
        log("   casco en voz (CVSD)")
        return None

    def paso_enlace(self):
        t = self.sis.tarjetas()
        casco = t and t["casco"]
        if not casco:
            return "casco desaparecido"
        if casco["id"] is None:
            return "id del casco en PipeWire"
        t0 = self.reloj()
        if not self._hacer("adquirir el SCO (bluetoothOffloadActive=true en %d)" % casco["id"],
                           self.sis.offload, casco["id"], True):
            return "enlace SCO (pw-cli no acepta la propiedad)"
        if not self._esperar(self.sis.esco, 6, paso=0.5):
            return "enlace eSCO (no sube en 6 s; offload leido: %s)" % self.sis.offload_leido(casco["id"])
        self.t_sco = self.reloj()
        log("   eSCO en pie en %.1f s" % (self.t_sco - t0))
        return None

    def paso_rutas(self):
        """Mete la tarjeta en el casco si no esta. Si ya esta, NO se toca."""
        t = self.sis.tarjetas()
        movil = t and t["movil"]
        if not movil:
            return "tarjeta del movil desaparecida"
        if movil["perfil"] == P_MOVIL_BT:
            return None
        if not movil["perfiles"].get(P_MOVIL_BT):
            return "tarjeta del movil sin perfil Bluetooth"
        n = self.nucleo
        espera = n.t_salida_casco + self.guarda_rutas - self.reloj()
        if n.t_salida_casco and espera > 0:
            log("   espero %.1f s antes de volver a meter la tarjeta en el casco "
                "(dos arranques seguidos dejan la llamada muda)" % espera)
            if self._esperar(lambda: self._sigue_pidiendo_casco() is not True, espera, paso=1.0):
                return "la llamada ya no pide el casco"
        t0 = self.reloj()
        self._hacer("tarjeta del movil a '%s'" % P_MOVIL_BT,
                    self.sis.poner_perfil, TARJETA_MOVIL, P_MOVIL_BT)
        if not self._esperar(lambda: self._perfil("movil") == P_MOVIL_BT, 4):
            return "tarjeta del movil (no pasa a Bluetooth: '%s')" % self._perfil("movil")
        if not self._esperar(lambda: n.tx == PUERTO_TX_CASCO and n.t_tx >= t0, 4):
            return "puertos del DSP (tx=%s, esperaba %d)" % (n.tx, PUERTO_TX_CASCO)
        if n.t_error_slim >= t0:
            return "SLIMbus (%s)" % n.error_slim
        log("   rutas en el casco (puerto %d)" % PUERTO_TX_CASCO)
        return None

    # ── fuera del circuito ─────────────────────────────────────────────────
    def devolver_al_auricular(self, t):
        movil, casco = t["movil"], t["casco"]
        if movil and movil["perfil"] == P_MOVIL_BT:
            self._hacer("tarjeta del movil a '%s'" % P_MOVIL_AURICULAR,
                        self.sis.poner_perfil, TARJETA_MOVIL, P_MOVIL_AURICULAR)
        if casco and casco["id"] is not None:
            self._hacer("soltar el SCO", self.sis.offload, casco["id"], False)

    def fin_de_llamada(self, t):
        log("fin de la llamada")
        self.en_llamada = False
        self.t_fin_llamada = self.reloj()
        casco = t["casco"]
        if casco is not None and self.tocado and not self.nucleo.chip_caido:
            if casco["id"] is not None:
                self._hacer("soltar el SCO", self.sis.offload, casco["id"], False)
            if casco["perfil"] not in P_CASCO_MUSICA:
                # wireplumber GUARDA el perfil de voz: sin devolverlo, al
                # reconectar el casco no hay sumidero de musica al que saltar.
                self._casco_a_musica(casco)
        if casco is not None and not self.nucleo.chip_caido:
            self._salida_al_casco("colgada", flujos=True)
        self._reiniciar_llamada()

    def tarjeta_fuera_de_llamada(self, t):
        """Sin llamada, la tarjeta del movil no puede quedarse en un perfil de llamada.

        Al colgar la devuelve a HiFi wireplumber (voice-call-stop). Pero si el
        movil se cuelga con la llamada puesta, wireplumber GUARDA ese perfil y lo
        restaura al arrancar: el 2026-09-10 tras el cuelgue de las 16:01 la
        tarjeta arranco en «Voice Call (Speaker)» sin llamada ninguna, y ahi la
        musica y los avisos no van por su camino.
        """
        movil = t["movil"]
        if not movil or not movil["perfil"].startswith("Voice Call"):
            return
        # Recien colgada, la devuelve wireplumber y elige el HiFi que toca: no
        # pisarle. Esto es para lo que queda tras un cuelgue.
        if self.t_fin_llamada and self.reloj() - self.t_fin_llamada < 10:
            return
        hifi = [p for p, disponible in movil["perfiles"].items()
                if disponible and p.startswith("HiFi")]
        if not hifi:
            return
        destino = "HiFi (Mic, Speaker)" if "HiFi (Mic, Speaker)" in hifi else sorted(hifi)[0]
        # Justo antes de tocarla: que de verdad no haya llamada.
        if self.estado_llamada() is not False:
            return
        log("la tarjeta del movil sigue en '%s' sin llamada: la devuelvo a '%s'"
            % (movil["perfil"], destino))
        self._hacer("tarjeta del movil a '%s'" % destino,
                    self.sis.poner_perfil, TARJETA_MOVIL, destino)

    def autoconmutar(self):
        """Musica al casco en la TRANSICION ausente -> presente, nunca en llamada.

        callaudiod fija el altavoz como sumidero por defecto al desconectar el
        casco, y esa fijacion gana a la prioridad: sin esto, al reconectarlo el
        sonido se quedaba en el altavoz.
        """
        bts = self.sis.sumideros_casco()
        if bts and not self.bt_antes:
            self._hacer("sonido al casco (%s)" % bts[0].rsplit(".", 1)[-1],
                        self.sis.mover_sonido_a, bts[0])
        self.bt_antes = bool(bts)


# ── piezas con D-Bus y hilos (solo en el movil) ───────────────────────────────
class ModemManager:
    def __init__(self, Gio, GLib):
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def llamadas(self):
        Gio, GLib = self.Gio, self.GLib
        try:
            r = self.bus.call_sync(MM, "/org/freedesktop/ModemManager1",
                                   "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                                   None, GLib.VariantType("(a{oa{sa{sv}}})"),
                                   Gio.DBusCallFlags.NONE, 3000, None)
        except Exception as e:
            log("AVISO: ModemManager: %s" % e)
            return None
        rutas = []
        for interfaces in r.unpack()[0].values():
            voz = interfaces.get(MM + ".Modem.Voice")
            if voz:
                rutas += list(voz.get("Calls", []))
        res = {}
        for ruta in rutas:
            try:
                v = self.bus.call_sync(MM, ruta, "org.freedesktop.DBus.Properties", "Get",
                                       GLib.Variant("(ss)", (MM + ".Call", "State")),
                                       GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE, 3000, None)
                res[ruta] = int(v.unpack()[0])
            except Exception:
                continue            # la llamada acaba de desaparecer
        return res

    def al_cambiar(self, fn):
        Gio = self.Gio

        def senal(con, remitente, ruta, interfaz, miembro, params, *datos):
            if interfaz in (MM + ".Call", MM + ".Modem.Voice"):
                detalle = params.unpack()[:2] if miembro == "StateChanged" else ""
                log("ModemManager: %s %s %s" % (miembro, ruta.rsplit("/", 1)[-1], detalle))
                fn()

        def dueno(*args):
            log("ModemManager ha cambiado de dueno en el bus")
            fn()
        self.bus.signal_subscribe(MM, None, None, None, None, Gio.DBusSignalFlags.NONE, senal)
        self.bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus",
                                  "NameOwnerChanged", "/org/freedesktop/DBus", MM,
                                  Gio.DBusSignalFlags.NONE, dueno)


class Notificador:
    def __init__(self, Gio, GLib):
        self.Gio, self.GLib = Gio, GLib
        self.bus = None
        self.id = 0

    def __call__(self, clave, titulo, cuerpo, urgencia):
        log("notificacion [%s]: %s: %s" % (clave, titulo, cuerpo.replace("\n", " ")))
        Gio, GLib = self.Gio, self.GLib
        icono = "bluetooth-active" if urgencia == 0 else "dialog-warning"
        try:
            if self.bus is None:
                self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            r = self.bus.call_sync(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications", "Notify",
                GLib.Variant("(susssasa{sv}i)", (
                    "Llamada por casco", self.id, icono, titulo, cuerpo, [],
                    {"urgency": GLib.Variant("y", urgencia)},
                    6000 if urgencia == 0 else -1)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 3000, None)
            self.id = r.unpack()[0]
        except Exception as e:
            self.bus = None
            log("AVISO: no puedo notificar: %s" % e)


class Motor:
    """Agrupa eventos y ejecuta las pasadas de una en una, fuera del bucle principal."""

    def __init__(self, sup, GLib):
        self.sup, self.GLib = sup, GLib
        self.programado = self.ocupado = self.pendiente = self.vigilando = False

    def pedir(self, *_):
        if not self.programado:
            self.programado = True
            self.GLib.timeout_add(300, self._disparar)
        return False

    def _disparar(self):
        self.programado = False
        if self.ocupado:
            self.pendiente = True
        else:
            self._lanzar()
        return False

    def _lanzar(self):
        self.ocupado, self.pendiente = True, False
        threading.Thread(target=self._trabajo, name="revision", daemon=True).start()

    def _trabajo(self):
        try:
            self.sup.revisar()
        except Exception:
            log("AVISO: revision con error:\n" + traceback.format_exc())
        self.GLib.idle_add(self._fin)

    def _fin(self):
        self.ocupado = False
        if self.pendiente:
            self._lanzar()
        if self.sup.en_llamada and not self.vigilando:
            self.vigilando = True
            self.GLib.timeout_add_seconds(VIGILANCIA_SEG, self._vigilar)
        return False

    def _vigilar(self):
        if not self.sup.en_llamada:
            self.vigilando = False
            return False
        self.pedir()
        return True


def lanzar_lector(nombre, args, al_leer):
    def bucle():
        while True:
            try:
                p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     text=True, bufsize=1)
            except OSError as e:
                log("AVISO: no puedo lanzar %s: %s" % (nombre, e))
                time.sleep(30)
                continue
            for linea in p.stdout:
                try:
                    al_leer(linea.rstrip("\n"))
                except Exception:
                    log("AVISO: %s:\n%s" % (nombre, traceback.format_exc()))
            log("AVISO: %s ha terminado (rc=%s); lo relanzo en 5 s" % (nombre, p.wait()))
            time.sleep(5)
    threading.Thread(target=bucle, name=nombre, daemon=True).start()


def main():
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    log("arranca: modo %s, guarda de rutas %.0f s, pid %d" % (MODO, GUARDA_RUTAS_SEG, os.getpid()))
    nucleo = Nucleo()
    try:
        out = subprocess.run(["journalctl", "-k", "-b", "-o", "cat", "--no-pager"],
                             capture_output=True, text=True, timeout=60).stdout
        for l in out.splitlines():
            nucleo.linea(l, t=0.0)
        log("kernel de este arranque: ultimo puerto tx=%s, chip BT encallado=%s"
            % (nucleo.tx, nucleo.chip_caido))
    except (OSError, subprocess.TimeoutExpired) as e:
        log("AVISO: no puedo leer el diario del kernel: %s" % e)

    mm = ModemManager(Gio, GLib)
    sup = Supervisor(Sistema(), nucleo, mm.llamadas, Notificador(Gio, GLib))
    motor = Motor(sup, GLib)
    mm.al_cambiar(motor.pedir)

    # "on sink #" y no "on sink": eso casaria tambien con sink-input, que es
    # justo el ruido que dejaba al guion viejo segundos por detras.
    evento_audio = re.compile(r"on (?:card|sink) #")
    lanzar_lector("pactl subscribe", ["stdbuf", "-oL", "pactl", "subscribe"],
                  lambda l: evento_audio.search(l) and GLib.idle_add(motor.pedir))
    lanzar_lector("diario del kernel",
                  ["stdbuf", "-oL", "journalctl", "-k", "-f", "-n0", "-o", "cat"],
                  lambda l: nucleo.linea(l) and GLib.idle_add(motor.pedir))

    motor.pedir()
    bucle = GLib.MainLoop()
    try:                        # GLib >= 2.80; el nombre viejo da un aviso de obsolescencia
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import GLibUnix
        senal_add = GLibUnix.signal_add
    except (ValueError, ImportError):
        senal_add = GLib.unix_signal_add
    for sig in (signal.SIGTERM, signal.SIGINT):
        senal_add(GLib.PRIORITY_DEFAULT, sig, lambda *a: (bucle.quit(), False)[1])
    bucle.run()
    log("termina")


if __name__ == "__main__":
    main()
