-- WirePlumber
--
-- Copyright © 2022 Collabora Ltd.
-- Copyright © 2025 Richard Acayan
--
-- SPDX-License-Identifier: MIT
--
-- Find the best Voice Call profile for a device if there is an active call
-- (adapted from device/find-best-profile.lua)
--
-- Override de surya (2026-08-01), instalado en /etc/wireplumber/scripts/device/:
-- prefiere el perfil "Voice Call (Bluetooth)" SOLO cuando hay un auricular
-- Bluetooth conectado (existe un device bluez5). Sin auricular, ese perfil se
-- ignora por completo, con lo que su PlaybackPriority en la UCM puede quedarse
-- baja (50) sin peligro: si este override desaparece (actualización), el
-- comportamiento vuelve al de siempre (auricular/altavoz), nunca a llamadas
-- mudas por el camino BT.

cutils = require ("common-utils")
log = Log.open_topic ("s-device")
started = false

alsa_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "alsa" },
  }
}

-- Auriculares/dispositivos de audio Bluetooth presentes ahora mismo.
bluez_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "bluez5" },
  }
}

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
    local have_bt = false
    for _ in bluez_devs_om:iterate () do
      have_bt = true
      break
    end

    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      log:debug (device, string.format (
          "Checking profile '%s': available == %s, priority == %d",
          profile.name, profile.available, profile.priority))
      local found = string.find (profile.name, "^Voice Call")
      local is_bt = string.find (profile.name, "Bluetooth") ~= nil
      if profile.available ~= "no" and found ~= nil then
        if is_bt and not have_bt then
          -- El camino BT sin auricular es una llamada muda: fuera.
          log:debug (device, "skipping Bluetooth voice profile: no bluez device")
        elseif is_bt then
          -- Con auricular, el perfil BT gana siempre, tenga la prioridad
          -- UCM que tenga.
          selected_profile = profile
          break
        elseif (not selected_profile) or selected_profile.priority < profile.priority then
          selected_profile = profile
        end
      end
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
bluez_devs_om:activate ()
