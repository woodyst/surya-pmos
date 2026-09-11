-- WirePlumber
--
-- Copyright © 2022 Collabora Ltd.
-- Copyright © 2025 Richard Acayan
--
-- SPDX-License-Identifier: MIT
--
-- Find the best Voice Call profile for a device if there is an active call
-- (adapted from device/find-best-profile.lua)

cutils = require ("common-utils")
log = Log.open_topic ("s-device")
started = false

alsa_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "alsa" },
  }
}

-- Añadido para surya: preferir el auricular Bluetooth cuando hay uno.
--
-- El perfil `Voice Call (Bluetooth)` lleva a proposito la prioridad MAS BAJA
-- de los tres: UCM no sabe nada de Bluetooth y anuncia ese perfil como
-- disponible aunque no haya auricular conectado, asi que elegirlo por
-- prioridad mandaria TODAS las llamadas a un sitio donde no hay nadie y se
-- oirian mudas. Aqui si se puede saber si hay auricular, mirando si existe un
-- dispositivo bluez5, y solo entonces se elige.
-- ⚠️ 2026-09-10: se probo a quitar esta preferencia y dejar que el supervisor de
-- la cadena (supervisor-llamada-bt.py) metiera la tarjeta en el casco despues de
-- levantar el enlace. Resultado: LLAMADAS MUDAS. callaudiod tambien elige el
-- casco al empezar la llamada; con este guion eligiendo el auricular, la tarjeta
-- entraba en Bluetooth, salia y volvia a entrar en 1,3 s, y el canal de bajada
-- del SLIMbus (157) arrancado dos veces seguidas deja la llamada muda entera.
-- Wireplumber y callaudiod tienen que elegir LO MISMO. Ver bluetooth-call/SUPERVISOR.md
bt_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "bluez5" },
  }
}

-- ⚠️ 2026-09-10: no basta con que HAYA casco, tiene que tener el perfil de manos
-- libres DISPONIBLE. Recien arrancado el movil, el casco conecta a veces solo en
-- A2DP (el registro del HFP aun no esta), y elegir aqui Bluetooth obligaba al
-- supervisor a sacar la tarjeta al auricular nada mas empezar la llamada: un
-- cambio de ruta encima del arranque (17:10, con el ADSP estrellado detras).
local function hay_auricular ()
  for device in bt_devs_om:iterate () do
    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      if profile and profile.name and
         string.find (profile.name, "^headset%-head%-unit") and
         profile.available ~= "no" then
        return true
      end
    end
  end
  return false
end

mm = Plugin.find ("modem-manager")
mm:connect ("voice-call-start", function ()
  started = true
  source = source or Plugin.find ("standard-event-source")

  for device in alsa_devs_om:iterate () do
    event = source:call ("push-event", "select-profile", device, nil)
  end
end)

mm:connect ("voice-call-stop", function ()
  started = false
  source = source or Plugin.find ("standard-event-source")

  for device in alsa_devs_om:iterate () do
    event = source:call ("push-event", "select-profile", device, nil)
  end
end)

SimpleEventHook {
  name = "device/find-calling-profile",
  before = "device/find-stored-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    local selected_profile = event:get_data ("selected-profile")
    if selected_profile then
      return
    end

    if not started then
      return
    end

    local device = event:get_subject ()
    local dev_name = device.properties["device.name"] or ""

    local con_auricular = hay_auricular ()
    local bt_profile = nil

    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      log:debug (device, string.format (
          "Checking profile '%s': available == %s, priority == %d",
          profile.name, profile.available, profile.priority))
      local found = string.find (profile.name, "^Voice Call")
      if profile.available ~= "no" and found ~= nil then
        if string.find (profile.name, "Bluetooth") then
          -- Solo si hay auricular de verdad; si no, ni mirarlo.
          if con_auricular then
            bt_profile = profile
          end
        elseif (not selected_profile) or selected_profile.priority < profile.priority then
          selected_profile = profile
        end
      end
    end

    -- Con auricular conectado, gana el auricular por encima de la prioridad.
    if bt_profile then
      selected_profile = bt_profile
    end

    if selected_profile then
      log:info (device, string.format (
          "Found calling profile '%s' (%d) for device %s",
          selected_profile.name, selected_profile.index, dev_name))
      event:set_data ("selected-profile", selected_profile)
    end
  end
}:register ()

alsa_devs_om:activate ()
bt_devs_om:activate ()
