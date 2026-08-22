# Llamadas mudas: el puerto SoundWire del micrófono se registra con CERO canales

**Estado: RESUELTO** — 2026-08-22. El arreglo son cuatro líneas menos en `HiFi.conf`.

## El síntoma

Llamadas en las que **el otro no te oye**. Tú sí oyes al remoto. Aparentemente
aleatorio: unas veces sí, otras no, con auricular, altavoz o Bluetooth por igual.
A veces se «arreglaba» cambiando entre manos libres y auricular en mitad de la
llamada. Ni un solo error en el diario, en ninguna capa.

## La cadena, de fuera adentro

Cada eslabón se midió, no se supuso.

1. **Solo la subida.** Dos mensajes grabados en el buzón desde el mismo móvil, uno
   bueno y uno mudo, con el resto idéntico.
2. **El audio no llega al DSP.** La toma del DSP (`VOC_REC_UL`) graba `0.000000`
   en las mudas y `0.026–0.190` en las buenas.
3. **El micrófono está bien.** 10 de 10 capturas correctas fuera de llamada.
4. **La configuración es idéntica.** Volcados del perfil, del mezclador, del macro
   LPASS, del códec WCD y del regmap: byte a byte iguales entre una muda y una
   buena de la misma tanda.
5. **El discriminador está en el hardware del bus.** Bit 24 (`EN_CHAN`) del
   registro `0x1224` del controlador SoundWire —el puerto de datos 2, por donde
   el micro manda sus muestras— **puesto en las buenas y a cero en las mudas**.
   Comprobados los DOS bancos (`0x1224` y `0x1264`): cerrado en ambos, así que no
   es un artefacto de leer el banco inactivo.
6. **El puerto nunca se abre.** `qcom_swrm_port_enable` no se llama ni una vez en
   las mudas, y exactamente una vez en las buenas. 9 de 9.
7. **Y nadie da error.** `sdw_prepare_stream` devuelve 0 y `sdw_enable_stream`
   devuelve 0 — en las mudas también.
8. **La lista de puertos del maestro está vacía.** `sdw_enable_disable_ports` SÍ
   se llama (luego el maestro existe), pero recorre una lista vacía.
9. **El flujo se registra con cero puertos.** Cuarto argumento de
   `sdw_stream_add_slave`: `np=1` en las buenas, **`np=0` en las mudas**. 8 de 8.

## La causa

`np` sale de `wcd->active_ports`, que `wcd937x_sdw_hw_params()` cuenta leyendo
`port_config[].ch_mask`. Y ese `ch_mask` **no lo pone el driver**: lo pone el
espacio de usuario, con el control de mezclador `ADC1 Switch`
(`wcd937x_set_swr_port` → `wcd937x_connect_port`).

O sea: **`ch_mask` se lee una sola vez, en el `hw_params` del PCM.** Si en ese
instante vale 0, el flujo SoundWire queda registrado con cero puertos, el puerto
de datos no se abre nunca, y la subida está muerta hasta que se cuelga. Nadie
comprueba nada: `sdw_stream_add_slave(..., num_ports=0, ...)` devuelve 0.

Y `HiFi.conf` apagaba `ADC1 Switch` en sus dos `DisableSequence`. Al pasar de HiFi
a Voice Call, wireplumber escribe primero esos ceros y ~220 ms después el uno del
verbo de llamada. `q6voiced` abre el PCM de voz en cuanto ModemManager da la
llamada por activa — y si cae dentro de esa ventana, llamada muda.

Capturado con kprobes, reloj en segundos de arranque:

```
60201.337729  wireplumber   ADC1 Switch = 0     <- DisableSequence del micro (HiFi)
60201.337829  wireplumber   ADC1 Switch = 0     <- DisableSequence del verbo HiFi
60201.384579  q6voiced      wcd937x_sdw_hw_params
60201.384590  q6voiced      sdw_stream_add_slave  np=0     <- cero puertos
60201.561142  wireplumber   ADC1 Switch = 1     <- 177 ms tarde, ya no sirve
```

Eso explica lo «aleatorio» (es una carrera de ~220 ms), y por qué cambiar de
altavoz a auricular a veces lo arreglaba: el cambio de perfil cierra el PCM y lo
vuelve a abrir, y el segundo `hw_params` ya encuentra el `ch_mask` puesto.

## El arreglo

Quitar `ADC1_MIXER Switch 0` y `ADC1 Switch 0` de las **dos** `DisableSequence` de
`audio/HiFi.conf` (la del verbo y la del dispositivo «Built-in Microphone»).

No es un apaño: `ADC1 Switch` no enciende hardware, solo marca un canal en una
estructura del driver, y `ADC1_MIXER Switch` es una ruta DAPM que no alimenta nada
mientras no haya un flujo de captura corriendo. El propio `HiFi.conf` ya lo dice en
su `EnableSequence`, y ya se había hecho exactamente lo mismo con las rutas
CS-Voice por esta misma clase de carrera — solo que entonces se dejó `ADC1` fuera.
`VoiceCall.conf` ya mantiene la cadena encendida en sus tres dispositivos.

## Comprobación

`scripts/tanda-puerto.sh N` marca cada llamada leyendo el bit del registro. No
graba audio, no reproduce tonos, no necesita un segundo móvil y no perturba la
llamada. Con `scripts/sondas5.sh` puestas además registra la cadena entera.

| tanda | antes/después | resultado |
|---|---|---|
| 9 llamadas  | antes | 6 abiertas / 3 cerradas |
| 3 llamadas  | antes | 2 abiertas / 1 cerrada  |
| 8 llamadas  | antes | 3 abiertas / 5 cerradas |
| 1 llamada   | antes | 0 abiertas / 1 cerrada  |
| **21 en total** | **antes** | **10 mudas (48 %)** |
| **10 llamadas** | **después** | **10 abiertas, 0 mudas** |

Con una tasa previa del 48 %, diez seguidas buenas por azar tienen una probabilidad de
0,52¹⁰ ≈ **0,14 %**. Y las diez traen `np=1` y `qcom_swrm_port_enable` llamado una vez,
que es el mecanismo, no solo el resultado.

⚠️ El otro móvil tiene que estar en **modo avión** para que las llamadas al
buzón de voz propio vayan al buzón, que descuelga siempre. Con él operativo suenan sin que
nadie conteste y no llegan a activarse: eso invalidó dos tandas.

⚠️ **45 s entre llamadas.** Encadenarlas más rápido atasca el módem
(`glink-edge: intent request timed out`), tira el WiFi y cuelga el móvil.

## Lo que este caso enseña del método

- El instrumento definitivo **lee un registro**. Las tres versiones anteriores
  grababan audio: molestaban al usuario con tonos, rompían la propia subida que
  medían y dependían de un segundo móvil. Llegar antes a leer el registro habría
  ahorrado horas.
- **Comprobar los dos bancos** antes de creerse una lectura de SoundWire: el
  controlador alterna banco 0 y 1, y leer solo uno habría dado un falso negativo.
- **Una función que devuelve 0 no ha hecho nada necesariamente.** Aquí tres
  funciones seguidas devolvieron éxito sin tocar el hardware.
