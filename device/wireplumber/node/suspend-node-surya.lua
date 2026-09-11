-- WirePlumber
--
-- Copyright © 2021 Collabora Ltd.
--    @author George Kiagiadakis <george.kiagiadakis@collabora.com>
--
-- SPDX-License-Identifier: MIT
--
-- ---------------------------------------------------------------------------
-- COPIA MODIFICADA PARA SURYA (2026-08-13). Un solo cambio, al final.
-- ---------------------------------------------------------------------------
--
-- POR QUE
--
-- Este movil tenia `session.suspend-timeout-seconds = 0` para TODOS los nodos
-- de la tarjeta, es decir, no suspender NUNCA. Se puso por una razon real: con
-- la llamada en el auricular Bluetooth la ruta interna queda ociosa, al
-- remontarla el ciclo de relojes del LPASS revienta el AFE del DSP
-- (`PDM: service 'audio_process' crash`) y el movil se reinicia.
--
-- Pero el apaño se puso para proteger LAS LLAMADAS y se aplico SIEMPRE. Y eso
-- cuesta, medido el 2026-08-13:
--
--   pcm0p en RUNNING sin reproducir nada
--     -> el hilo data-loop de PipeWire habla con el lpass (ADSP) por el canal
--        apr_audio_svc ~150 veces por segundo
--     -> ~940 interrupciones/s con la pantalla apagada
--     -> el sistema nunca junta los 9,8 ms que pide `cluster_aoss_sleep`
--     -> ese estado profundo NUNCA se elige (usage 0 en 2,6 h)
--     -> aosd / cxsd / ddr / adsp a cero: NADA duerme
--     -> ~300 mA en reposo, unas 14 h de bateria
--
-- QUE HACE ESTA COPIA
--
-- Suspender normalmente, salvo mientras haya una llamada en curso. La señal es
-- el fichero de bandera que escribe `device/mantener-voz-bluetooth.lua`, que ya
-- sabe de llamadas por ModemManager — la misma fuente de verdad que usa la
-- propia wireplumber. Si hay llamada, el nodo NO se suspende y se vuelve a
-- comprobar al siguiente ciclo, en vez de quedar excluido para siempre.
--
-- ⚠️ Se comprueba EN EL MOMENTO DE SUSPENDER, no al quedar ocioso. Es
-- deliberado: una llamada puede empezar durante los 5 s de espera.
--
-- ⚠️ Y NO se sostiene el nodo reproduciendo nada. El intento del 12-08 fallo
-- justamente por eso: inyectaba silencio en un sumidero que ES el camino de
-- voz, y ademas capturaba su nombre antes del cambio de perfil, con lo que
-- escribia en un sumidero muerto. Aqui no se reproduce nada; solo se decide.

log = Log.open_topic ("s-node")

sources = {}

-- ---------------------------------------------------------------------------
-- COMO SABE ESTE GUION QUE HAY LLAMADA
-- ---------------------------------------------------------------------------
-- Preguntandoselo a ModemManager EL MISMO, con la misma API que usa
-- `device/mantener-voz-bluetooth.lua` y la propia `find-voice-call-profile` de
-- wireplumber.
--
-- ⚠️ Se intento antes compartirlo con el otro guion y NO SE PUEDE. Medido:
--
--     surya: suspender? global=nil io=false
--
--   * `io` es nil  -> el Lua de wireplumber esta restringido: no hay ficheros
--     (y `os.remove` tampoco existe).
--   * la global sale `nil`, no `false` -> cada guion corre en SU PROPIO estado
--     Lua. No comparten variables.
--
-- Comprobarlo con un registro, y no con una llamada, evito soltar una
-- proteccion que no existia: la primera llamada por casco habria reventado el
-- AFE del DSP y reiniciado el movil.

en_llamada = false
mm = nil

function conectarModemManager ()
  if mm ~= nil then return end
  mm = Plugin.find ("modem-manager")
  if mm == nil then return end
  mm:connect ("voice-call-start", function ()
    en_llamada = true
    log:warning ("surya: llamada iniciada; no se suspendira el audio")
  end)
  mm:connect ("voice-call-stop", function ()
    en_llamada = false
    log:warning ("surya: llamada terminada; vuelve la suspension normal")
  end)
end

-- Al cargar puede que el complemento aun no este; se reintenta cada vez.
conectarModemManager ()

function hay_llamada ()
  conectarModemManager ()
  return en_llamada
end

SimpleEventHook {
  name = "node/suspend-node-surya",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "matches", "Audio/*" },
    },
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "matches", "Video/*" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local new_state = event:get_properties ()["event.subject.new-state"]

    log:debug (node, "changed state to " .. new_state)

    -- Always clear the current source if any
    local id = node["bound-id"]
    if sources[id] then
      sources[id]:destroy()
      sources[id] = nil
    end

    -- Add a timeout source if idle for at least 5 seconds
    if new_state == "idle" or new_state == "error" then
      -- honor "session.suspend-timeout-seconds" if specified
      local timeout =
          tonumber(node.properties["session.suspend-timeout-seconds"]) or 5

      if timeout == 0 then
        return
      end

      -- add idle timeout; multiply by 1000, timeout_add() expects ms
      sources[id] = Core.timeout_add(timeout * 1000, function()
        -- surya: con llamada en curso NO se suspende, y se reintenta luego.
        -- Se registra SIEMPRE de donde sale la respuesta: si la global saliera
        -- `nil` en vez de `false`, los guiones NO comparten estado Lua y esta
        -- proteccion no existiria -- se veria aqui antes que en una llamada rota.
        log:info (node, "surya: suspender? llamada=" .. tostring (en_llamada)
                        .. " mm=" .. tostring (mm ~= nil))
        if hay_llamada () then
          log:info (node, "ocioso, pero hay llamada: no se suspende")
          return true
        end

        -- Suspend the node
        -- but check first if the node still exists
        if (node:get_active_features() & Feature.Proxy.BOUND) ~= 0 then
          log:info(node, "was idle for a while; suspending ...")
          node:send_command("Suspend")
        end

        -- Unref the source
        sources[id] = nil

        -- false (== G_SOURCE_REMOVE) destroys the source so that this
        -- function does not get fired again after 5 seconds
        return false
      end)
    end
  end
}:register ()
