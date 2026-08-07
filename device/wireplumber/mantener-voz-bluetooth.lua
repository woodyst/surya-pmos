-- Mantener el auricular Bluetooth en camino de VOZ mientras la llamada
-- este enrutada a el.  (surya / postmarketOS, 2026-08-06)
--
-- SPDX-License-Identifier: MIT
--
-- EL PROBLEMA
--
-- `device/autoswitch-bluetooth-profile.lua` decide el perfil del auricular
-- mirando si algun cliente CAPTURA de su fuente: si no hay ninguno, lo devuelve
-- a A2DP.  En este movil esa politica es estructuralmente ciega, porque el
-- audio de la llamada NO PASA POR PIPEWIRE: lo lleva el DSP por SLIMBus, entre
-- el modem y el chip Bluetooth.  Wireplumber no ve ningun flujo de captura,
-- concluye que no hay llamada y deshace el perfil de manos libres.
--
-- Sin perfil de manos libres no se crea el enlace eSCO, y sin eSCO la llamada
-- sale MUDA por el auricular.  Medido con btmon el 2026-08-06: los eSCO se
-- desconectan con `Reason: Connection Terminated By Local Host (0x16)` en ese
-- instante exacto.  No lo tira la radio ni el auricular: lo tiramos nosotros.
--
-- Antes esto se compensaba desde fuera, con un guion que reponia el perfil en
-- bucle.  Era una PELEA: wireplumber lo deshacia cada 3-4 s y el enlace no
-- llegaba a estabilizarse nunca.  Dos autoridades decidiendo lo mismo.
--
-- LA SOLUCION
--
-- Wireplumber ya sabe cuando hay llamada: `device/find-voice-call-profile.lua`
-- se conecta a ModemManager y elige un perfil «Voice Call ...» — pero SOLO para
-- dispositivos ALSA; la tarjeta bluez ni la mira.  Este guion cubre ese hueco,
-- dentro de wireplumber y con su misma fuente de verdad:
--
--   1. Mientras la llamada este enrutada al Bluetooth, no dejar que la politica
--      de autoconmutacion restaure A2DP.
--   2. Al entrar la llamada en el camino Bluetooth, poner el auricular en
--      manos libres.
--
-- ⚠️ SIEMPRE CVSD, NUNCA mSBC.  `bt_sco_rate` del modulo snd_soc_sm8250 esta
-- fijado a 8000 (banda estrecha).  Con mSBC el enlace se negocia a 16 kHz
-- (`Air mode: Transparent` en la traza de btmon) y el DSP sigue escribiendo a
-- 8: eSCO en pie, rutas correctas, cero trafico por HCI y silencio absoluto.
-- Y mSBC tiene MAS prioridad que CVSD (6 frente a 5), asi que si no se fuerza
-- se elige solo.  Mas vale no montar el enlace que montarlo mudo.

cutils = require ("common-utils")
log = Log.open_topic ("s-device")

-- El perfil de voz del auricular. Si algun dia `bt_sco_rate` deja de ser fijo
-- y sigue al codec negociado, aqui es donde hay que permitir mSBC.
PERFIL_VOZ = "headset-head-unit-cvsd"

en_llamada = false

alsa_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "alsa" },
  }
}

bt_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "bluez5" },
  }
}

-- ¿La llamada esta puesta en el auricular Bluetooth?
--
-- Se mira el perfil de la tarjeta del movil, que es quien lleva la llamada.
-- No basta con «hay llamada»: si el usuario esta en el auricular de la oreja o
-- en manos libres del movil, no hay que tocar el Bluetooth para nada.
-- ⚠️ NO se exige la bandera `en_llamada` de ModemManager, a proposito.  Que la
-- tarjeta del movil este en un perfil «Voice Call ... Bluetooth» YA significa
-- que hay llamada y que va al casco; la bandera no añade informacion y se queda
-- rancia: si wireplumber se reinicia con una llamada ya en curso, la señal
-- `voice-call-start` ya paso y la bandera se queda en falso para siempre.
-- Medido el 2026-08-06: con la llamada activa y todo lo demas correcto, el
-- enganche no hacia nada por esto.
function llamadaEnCasco ()
  for device in alsa_devs_om:iterate () do
    for p in device:iterate_params ("Profile") do
      local profile = cutils.parseParam (p, "Profile")
      if profile and profile.name and
         string.find (profile.name, "^Voice Call") and
         string.find (profile.name, "Bluetooth") then
        return true
      end
    end
  end
  return false
end

function perfilActual (device)
  for p in device:iterate_params ("Profile") do
    local profile = cutils.parseParam (p, "Profile")
    if profile then
      return profile
    end
  end
  return nil
end

function ponerCascoEnVoz ()
  for device in bt_devs_om:iterate () do
    local actual = perfilActual (device)
    if actual == nil or actual.name ~= PERFIL_VOZ then
      for p in device:iterate_params ("EnumProfile") do
        local profile = cutils.parseParam (p, "EnumProfile")
        if profile and profile.name == PERFIL_VOZ and profile.available ~= "no" then
          local pod = Pod.Object {
            "Spa:Pod:Object:Param:Profile", "Profile",
            index = profile.index,
            save = false
          }
          log:info (device, "llamada en Bluetooth: perfil de voz '"
                .. profile.name .. "' (venia de '"
                .. tostring (actual and actual.name or "nada") .. "')")
          device:set_params ("Profile", pod)
          break
        end
      end
    end
  end
end

-- (1) No dejar que se restaure A2DP con la llamada puesta en el auricular.
--
-- Se ejecuta ANTES del enganche de la politica y le corta el paso. Sin esto,
-- lo que pongamos dura tres segundos.
no_restaurar_hook = SimpleEventHook {
  name = "no-restaurar-a2dp-en-llamada@mantener-voz-bluetooth",
  before = "restore-profile@autoswitch-bluetooth-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "autoswitch-bluez-a2dp-profile" },
    },
  },
  execute = function (event)
    if llamadaEnCasco () then
      log:info ("llamada enrutada al Bluetooth: no se restaura A2DP")
      event:stop_processing ()
    end
  end
}

-- (2) Al entrar la llamada en el camino Bluetooth, poner manos libres.
--
-- Se dispara con el cambio de perfil de la tarjeta del movil, que es el
-- instante en que la llamada pasa a ir por el auricular — tanto al descolgar
-- como al volver desde manos libres.
perfil_movil_hook = SimpleEventHook {
  name = "poner-voz-al-entrar-llamada@mantener-voz-bluetooth",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "Profile" },
      Constraint { "device.api", "=", "alsa" },
    },
  },
  execute = function (event)
    if llamadaEnCasco () then
      ponerCascoEnVoz ()
    end
  end
}

-- (3) Llevar el volumen de la llamada a la ganancia HFP del casco.
--
-- El deslizador aterriza en el sumidero de la llamada, pero el UCM NO declara
-- `PlaybackVolume` para el dispositivo Bluetooth — y no puede: en ese camino no
-- hay ningun elemento de mezclador donde aplicarlo.  El amplificador, que es
-- donde aterrizan el auricular y el altavoz, no interviene; y el volumen de
-- CS-Voice del DSP (`rx_volume_step`) es best-effort y falla sin tabla de
-- calibracion ACDB, que este movil no carga.  Asi que mover el volumen no
-- tocaba absolutamente nada.
--
-- Lo que SI llega al casco es el volumen de la RUTA de salida del dispositivo
-- bluez: PipeWire lo traduce a `+VGS: n` por HFP, la ganancia del propio
-- auricular.  Verificado el 2026-08-06 con btmon (sale el `+VGS`) y de oido.
--
-- Aqui se copia ganancia LINEAL a ganancia LINEAL, sin conversion: los dos
-- extremos son `channelVolumes`.  (Hacer esto desde fuera con `pactl` obliga a
-- elevar al cubo, porque su porcentaje esta en la escala perceptual.)
-- ⚠️ El volumen NO esta en las propiedades del nodo sumidero.  La tarjeta del
-- movil tiene rutas (`device.routes` en sus nodos), y cuando hay rutas PipeWire
-- guarda el volumen en la RUTA del dispositivo.  Escuchar `node-params-changed`
-- sobre `Props` no dispara jamas: probado el 2026-08-06, el enganche no se
-- ejecutaba ni una vez.  Hay que mirar la ruta de salida del dispositivo ALSA.
vol_antes = nil

-- ⚠️ El volumen se LEE del nodo, no de la ruta.  El parametro `Route` que se
-- obtiene iterando trae `props` pero SIN `channelVolumes` (medido el
-- 2026-08-06: `props=true chV=false vol=nil`), aunque `pw-dump` si lo muestre.
-- El disparador si es el suceso de la ruta del dispositivo: el del nodo no
-- llega, porque cuando un dispositivo tiene rutas el volumen no se guarda en
-- las propiedades del nodo sino en la ruta.  Asi que: disparar con la ruta,
-- leer del nodo.
-- ⚠️ El filtro va por `node.name`, que SI es propiedad global del nodo.
-- `device.api` no lo es —vive en las propiedades de informacion—, y con el el
-- objeto no casaba con nada: medido, devolvia nil sin encontrar ningun nodo.
sumideros_om = ObjectManager {
  Interest {
    type = "node",
    Constraint { "node.name", "matches", "alsa_output.platform-sound.*" },
  }
}

function volumenSumideroAlsa ()
  for nodo in sumideros_om:iterate () do
    for p in nodo:iterate_params ("Props") do
      local props = cutils.parseParam (p, "Props")
      if props then
        if props.channelVolumes and props.channelVolumes[1] then
          return props.channelVolumes[1], nodo.properties["node.name"]
        elseif props.volume then
          return props.volume, nodo.properties["node.name"]
        end
      end
    end
  end
  return nil, nil
end

function rutaSalida (om)
  for device in om:iterate () do
    for p in device:iterate_params ("Route") do
      local r = cutils.parseParam (p, "Route")
      if r and r.direction == "Output" then
        return device, r
      end
    end
  end
  return nil, nil
end

function reflejarVolumen ()
  if not llamadaEnCasco () then
    vol_antes = nil
    return
  end
  local vol, de_donde = volumenSumideroAlsa ()
  log:debug (string.format ("volumen leido de '%s': %s (antes %s)",
        tostring (de_donde), tostring (vol), tostring (vol_antes)))
  if vol == nil or vol == vol_antes then
    return
  end
  local device, destino = rutaSalida (bt_devs_om)
  if device == nil or destino == nil then
    log:debug ("no hay ruta de salida bluez")
    return
  end
  local param = Pod.Object {
    "Spa:Pod:Object:Param:Route", "Route",
    index = destino.index,
    device = destino.device,
    props = Pod.Object {
      "Spa:Pod:Object:Param:Props", "Route",
      -- ⚠️ `Pod.Array` exige el TIPO del elemento como primer campo. Sin el:
      -- «wplua: must have the item type or table on its first field», la
      -- excepcion aborta la funcion y no se escribe nada ni se ve por que.
      channelVolumes = Pod.Array { "Spa:Float", vol },
    },
    save = true,
  }
  device:set_param ("Route", param)
  vol_antes = vol
  log:info (device, string.format ("volumen de llamada -> ganancia HFP %.3f", vol))
end

volumen_hook = SimpleEventHook {
  name = "reflejar-volumen-llamada@mantener-voz-bluetooth",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "Route" },
      Constraint { "device.api", "=", "alsa" },
    },
  },
  execute = function (event)
    reflejarVolumen ()
  end
}

mm = Plugin.find ("modem-manager")
if mm ~= nil then
  mm:connect ("voice-call-start", function ()
    en_llamada = true
    log:info ("llamada iniciada")
    -- El perfil de la tarjeta del movil aun puede no haber cambiado; el
    -- enganche (2) lo rematara cuando cambie.
    if llamadaEnCasco () then
      ponerCascoEnVoz ()
    end
  end)
  mm:connect ("voice-call-stop", function ()
    en_llamada = false
    log:info ("llamada terminada: la politica normal vuelve a mandar")
  end)
else
  log:warning ("sin complemento modem-manager: este guion no hara nada")
end

no_restaurar_hook:register ()
perfil_movil_hook:register ()
volumen_hook:register ()

alsa_devs_om:activate ()
bt_devs_om:activate ()
sumideros_om:activate ()
