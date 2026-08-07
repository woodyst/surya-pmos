# Audio en postmarketOS — Xiaomi POCO X3 NFC (surya, SM7150)

Documento de referencia de la arquitectura de audio de este dispositivo bajo
el kernel mainline (`sm7150-mainline`), los parches aplicados para hacerlo
sonar, y cómo instalarlo todo desde cero.

Estado: **completo y funcionando** — altavoces en **estéreo real** (izquierda
arriba, derecha abajo), balance calibrado, auricular para llamadas, y Bluetooth
(nativo de PipeWire). Kernel r33 (pkgrel=33), parches de audio 0005–0023.

---

## 1. La cadena de audio, de arriba a abajo

```
  PipeWire / WirePlumber                 (userspace: mezcla, volumen, rutas)
        │   perfil UCM  (HiFi.conf)
        ▼
  ALSA  →  tarjeta "POCO X3" (sm8250-sndcard)
        │
        ▼
  DSP de Qualcomm (ADSP / q6afe / q6asm / q6routing / q6adm)
        │   puerto TERTIARY_MI2S_RX,  I2S,  48 kHz / 16 bit / estéreo
        ▼
  Bus I2S terciario (SoC = maestro de reloj)
        │
        ├─ SD0 (datos de salida)  ────┬──────────────┐
        │                             │              │
        │              ┌──────────────▼──┐    ┌───────▼─────────┐
        │              │  TAS2562 @ 0x4c │    │  TAS2564 @ 0x4d │
        │              │  ALTAVOZ ABAJO  │    │  ALTAVOZ ARRIBA │
        │              │  prefijo "Right"│    │  prefijo "Left" │
        │              │  canal DERECHO  │    │  canal IZQUIERDO│
        │              │                 │    │  (+ auricular)  │
        │              └────────┬────────┘    └────────┬────────┘
        │                       │                      │
        └─ SD1 (I/V sense) ◄─────┴──────────────────────┘
           (realimentación de tensión/corriente del altavoz al SoC)
```

### Los dos amplificadores

El teléfono tiene **dos amplificadores inteligentes de TI**, cada uno mono,
colgados del **mismo bus I2S** (bus I2C 9 para el control):

| Chip | Dirección I2C | Posición | Controles ALSA | Canal | Función extra |
|------|--------------|----------|----------------|-------|---------------|
| TAS2562 | `0x4c` | abajo (junto al USB) | prefijo `Right` | derecho | — |
| TAS2564 | `0x4d` | arriba (junto a la pantalla) | prefijo `Left` | izquierdo | auricular de llamadas |

Ambos oyen **todo** el audio estéreo por el bus; cada uno elige qué canal
reproduce mediante su **multiplexor de entrada** (`ASI1 Sel`: izquierda,
derecha o mezcla). Como comparten un único PCM, **no hay un mezclador en el DSP
que enrute entre ellos**: el enrutado se hace silenciando por volumen el
amplificador que no debe sonar.

### Bus I2S, no TDM

El bus terciario funciona como **I2S plano** de 2 canales (SD0 salida, SD1
realimentación I/V sense), con el **SoC como maestro de reloj**
(`SND_SOC_DAIFMT_BP_FP`, BCLK 1.536 MHz = 48 kHz × 32). Se intentó TDM (por si
Android lo usaba para meter 4 canales de I/V sense); el DSP lo rechaza y el
propio devicetree de Android confirma `qcom,msm-dai-q6-mi2s`, es decir I2S.

---

## 2. El bug principal, y por qué costó tanto

Durante semanas **no salía ningún sonido**, y lo desconcertante era que **todo
lo demás estaba perfecto**. Cada capa que se inspeccionaba devolvía justo lo
que debía:

| Comprobación | Estado |
|---|---|
| El chip responde por I2C y reporta su ID de revisión | correcto |
| Modo de operación: `ACTIVE`, fuera de reset | correcto |
| Ganancia analógica del amplificador, al máximo | correcto |
| Registros de fallo latcheados (sobrecorriente, térmica, brownout) | sin fallos |
| Relojes del bus I2S presentes y válidos | correcto |
| Enrutado del DSP activo; el DSP consume PCM en tiempo real | correcto |
| Pines muxeados a la función de audio | correcto |
| **Corriente circulando por el altavoz** | **ninguna** |

Ese último dato no es una impresión: es una **medición**. Los TAS2562 llevan
sensado de corriente y tensión integrado (*I/V sense*, parche 0019) y devuelven
al SoC lo que ocurre físicamente en los bornes del altavoz. Reproduciendo un
tono de 1 kHz, la corriente a esa frecuencia era indistinguible del ruido de
fondo. El amplificador no estaba moviendo nada.

**Causa raíz:** el **volumen digital** del TAS2562 es un coeficiente de 32 bits,
y esos registros de coeficientes del chip **solo aceptan escritura en una
ráfaga de 4 bytes**. El driver de mainline los escribía byte a byte, con cuatro
llamadas sueltas. El chip confirma cada transferencia I2C y **no guarda
ninguna**. El volumen se quedaba en `0x00000000` — el DAC multiplicaba cada
muestra de audio por cero. Silencio absoluto, con todo lo demás impecable.

```c
/* Lo que hacía el driver: cuatro escrituras sueltas.
   El chip las acepta educadamente y las descarta.  → hardware: 00 00 00 00 */
snd_soc_component_write(component, TAS2562_DVC_CFG4, reg_val         & 0xff);
snd_soc_component_write(component, TAS2562_DVC_CFG3, (reg_val >>  8) & 0xff);
snd_soc_component_write(component, TAS2562_DVC_CFG2, (reg_val >> 16) & 0xff);
snd_soc_component_write(component, TAS2562_DVC_CFG1, (reg_val >> 24) & 0xff);

/* Lo que hace falta: una sola ráfaga cruda.          → hardware: 40 00 00 00 */
__be32 dvc = cpu_to_be32(reg_val);
regcache_cache_bypass(tas2562->regmap, true);
regmap_raw_write(tas2562->regmap, TAS2562_DVC_CFG1, &dvc, sizeof(dvc));
regcache_cache_bypass(tas2562->regmap, false);
```

**La prueba** (con el mismo tono de 1 kHz sonando, midiendo la corriente real
en el altavoz por el I/V sense):

| | corriente del altavoz @ 1 kHz |
|---|---|
| antes (escritura byte a byte) | **~15 RMS** — el suelo de ruido del conversor: no circulaba nada |
| después (ráfaga de 4 bytes) | **~12.352 RMS** — tono limpio; el altavoz sonó por primera vez |

**El agravante (una familia de bugs, no uno solo):** los `reg_defaults` de
regmap declaraban valores que el hardware **no tiene** al arrancar. Y los
`reg_defaults` solo siembran la **caché**, nunca escriben al chip. Así que la
caché nacía mintiendo, y regmap **descartaba escrituras** creyéndolas
redundantes contra esa caché falsa. Esto afectó al volumen digital, a la
ganancia del amplificador y a la longitud de slot I2S — los tres el mismo
patrón: **estado de regmap que no coincide con el silicio.**

**Lección de diagnóstico:** cuando un chip parece perfecto y no hace nada, lee
sus registros **por I2C en crudo** (`i2cget -y -f`), no a través de regmap:
regmap cachea y te devuelve alegremente el valor que *cree* que hay.

---

## 3. Los parches (serie 0005–0023)

Todos sobre `sound/soc/`, en el fork `sm7150-mainline`, exportados como parches
numerados dentro del APKBUILD del kernel. Marcados **[UPSTREAM]** los que son
bugs genéricos de mainline (afectan a cualquier placa con este códec) y
merecen enviarse aguas arriba; **[surya]** los específicos de este dispositivo;
**[muerto]** los experimentos revertidos que se conservan por historial.

### La solución (lo que hace que funcione)

| # | Parche | Qué arregla |
|---|--------|-------------|
| 0020 | **digital volume: escritura en ráfaga** | **[UPSTREAM]** El bug principal. Escribe el volumen con `regmap_raw_write()` + bypass de caché (4 bytes de golpe); byte a byte el chip los ignora. También acota el control a 108 (la tabla tiene 55 entradas; 110 se salía) y fija el volumen en el probe. |
| 0021 | **quitar los `reg_defaults` falsos** | **[UPSTREAM]** Los defaults no coinciden con el hardware y hacían que regmap descartara escrituras (ganancia, etc.). Sin ellos, la caché se llena de lecturas reales y no puede mentir. |
| 0018 | **longitud de slot RX desde `hw_params`** | **[UPSTREAM]** Mainline solo fijaba la longitud de slot dentro de `set_dai_tdm_slot()`, que los drivers I2S plano nunca llaman → el chip esperaba slots de 32 bits en un bus de 32 BCLK/trama y latcheaba error de reloj TDM en cada reproducción. |
| 0022 | **reafirmar el mux de canal en el encendido del DAC (con bypass de caché)** | **[surya]** El selector de canal (`ASI1 Sel`, bits 5:4 de `TDM_CFG2`) iba a la caché de regmap pero `set_bitwidth` lo pisaba en el chip con una lectura-modificación-escritura de caché rancia, dejándolo en 0 = código de "entrada muda". Se guarda la selección en un `put` propio del control y se reafirma en el evento `POST_PMU` **con `regcache_cache_bypass()`** alrededor del `regmap_update_bits()`, forzando la escritura al silicio (un re-assert cacheado normal se la saltaba por creerla redundante). Esto hace fiable el **estéreo real**. |
| 0023 | **forzar también la longitud de slot en ese re-assert** | **[surya]** El mismo registro `TDM_CFG2` guarda, en sus bits bajos, la longitud de word/slot I2S — y `set_bitwidth` también fallaba por caché en uno de los dos amplis, dejándolo en el default de 32 bits del chip → error de reloj TDM → canal mudo. `set_bitwidth` ahora solo **guarda** esos bits, y el re-assert del `POST_PMU` escribe **todo** el campo configurable de `TDM_CFG2` (canal + word + slot, máscara `0x3f`) de golpe, con bypass de caché. Verificado: ambos amplis leen `0x10`/`0x20` (nibble bajo 0, 16 bits) y los dos canales suenan. |

> **Principio de diseño que emergió de todo esto:** la caché de regmap se usa para
> el **grueso** de registros (necesaria para restaurar el chip al despertar del
> sueño, porque suspender le corta la alimentación por el GPIO de reset y
> `regcache_sync` los reescribe). Pero los **2-3 registros que deben estar exactos
> al reproducir** — volumen digital y todo `TDM_CFG2` — se **fuerzan saltándose la
> caché en cada encendido del DAC**. Así son inmunes a la incoherencia de caché y
> a lo que se pierda al dormir.

### Secuencia de inicialización del vendor (portada del driver de Android)

| # | Parche | Qué hace |
|---|--------|----------|
| 0013 | escribir registros de la página de test del vendor en probe | Página 253 (test/trim); el vendor la escribe siempre. |
| 0014 | replicar el resto de `tas256x_load_init()` | misc/tx/clock config, HPF FF+FB bypass, tabla Class-H. |
| 0015 | book-switching para los 3 registros Class-H del book 0x64 | Registros que viven en otro "book" del chip. |
| 0016 | aplicar los bloques `PRE_POWER_UP`/`POST_SHUTDOWN` del `tas256x_reg.bin` real | Extraídos del ROM de fábrica de este equipo. |

> La secuencia de init del vendor quedó **completa y verificada byte a byte** en
> hardware. No hace falta buscar más registros del códec.

### Reset y formato

| # | Parche | Qué hace |
|---|--------|----------|
| 0005 | `sm8250`: llamar `set_fmt()` en cada códec del enlace | Un enlace con dos códecs; sin esto el 2º se queda con su formato por defecto. |
| 0006 | pulso de reset hardware real en probe | El GPIO podía estar ya alto y el chip no pasaba por reset. |
| 0007 | ensanchar el tiempo de asentamiento del reset a 100 ms | Estabilidad del rail en arranque temprano. |
| 0019 | **[surya]** cablear la captura de I/V sense (TERT_MI2S_TX en SD1) | Permite medir la corriente/tensión reales del altavoz — el instrumento objetivo que confirmó que sonaba. |

### Experimentos muertos (conservados por historial)

`0008`–`0012` y sus reversiones `0009`/`0011`/`0017`: el experimento de
smart-amp AFE del lado DSP, nunca demostrado que sirviera, eliminado en `0017`.
El intento de TDM (`331dac5b5`) fue revertido. El intento de marcar `TDM_CFG2`
como volátil fue revertido (empeoraba el bug del mux: las escrituras volátiles
se descartan en modo caché-only).

---

## 4. Rutas de audio (perfiles UCM)

Fichero: `/usr/share/alsa/ucm2/Xiaomi/surya/HiFi.conf`
(copia buena en `~/claude/postmarketos/audio/HiFi.conf`).

Los dos amplis comparten PCM, así que las rutas son **perfiles mutuamente
excluyentes** (`ConflictingDevice`), y `callaudiod`/phosh conmutan entre ellos
según el contexto (llamada ↔ multimedia):

| Perfil UCM | Casos de uso | Amplis | Modo |
|------------|--------------|--------|------|
| **Speaker** | música, vídeo, manos libres, timbre | los dos | estéreo real (arriba=izq, abajo=der) |
| **Earpiece** | llamada al oído | solo arriba | mono, volumen bajo |

El enrutado de canal lo pone el driver (parche 0022): en el perfil Speaker,
arriba = canal izquierdo, abajo = canal derecho.

**Ganancias analógicas (balance calibrado de oído):**
- **Arriba** (auricular, TAS2564) → `13` = el nivel de 16 dBV que fija el vendor;
  más alto distorsiona el transductor pequeño.
- **Abajo** (altavoz principal, TAS2562) → `0` = su mínimo (8.5 dB). El altavoz
  de abajo es mucho más sensible que el de arriba, así que se atenúa a fondo
  para centrar la imagen estéreo. Esto **prioriza el balance sobre el volumen
  máximo** (todo el equipo suena tan flojo como el altavoz débil). El balance
  además depende de la posición (móvil en la mesa vs en la mano cambia la
  acústica de cada altavoz), así que no hay un valor "perfecto" único.

> Para reequilibrar: usa el control de **ganancia** del ampli (pasos de 0.5 dB).
> El control de volumen digital va en saltos de 2 dB y está topado — demasiado
> grueso para afinar balance. Script interactivo en
> `~/claude/postmarketos/audio/balance-manual.sh`.

**Bluetooth** funciona de forma nativa: PipeWire lo gestiona como un sink
aparte que **no pasa por estos amplificadores**, así que no necesita nada en
UCM — al conectar unos auriculares BT, PipeWire cambia de sink solo.

---

## 5. Instalación desde cero

### 5.1 Requisitos

- Host con `pmbootstrap` configurado para el dispositivo (`qcom-sm7150`).
- El fork del kernel en `sm7150-mainline` con la serie de parches, y el
  `APKBUILD` de `linux-postmarketos-qcom-sm7150` referenciándolos
  (`source=`, `sha512sums=`, `pkgrel` actualizado).

### 5.2 Compilar e instalar el kernel

```sh
# en el host
pmbootstrap build linux-postmarketos-qcom-sm7150 --arch aarch64
#   (tarda ~25 min; NO envolver en un timeout corto, aborta el build)

# copiar al teléfono e instalar
scp ~/.local/var/pmbootstrap/packages/*/aarch64/linux-postmarketos-qcom-sm7150-*.apk <tu-movil>:/tmp/
ssh <tu-movil> "sudo apk add --allow-untrusted /tmp/linux-postmarketos-qcom-sm7150-*.apk && sudo reboot"
```

### 5.3 Instalar el perfil UCM

```sh
scp ~/claude/postmarketos/audio/HiFi.conf <tu-movil>:/tmp/
ssh <tu-movil> "sudo cp /tmp/HiFi.conf /usr/share/alsa/ucm2/Xiaomi/surya/HiFi.conf"
ssh <tu-movil> "export XDG_RUNTIME_DIR=/run/user/\$(id -u); systemctl --user restart wireplumber pipewire"
```

La cadena de resolución de UCM es:
`tarjeta xiaomi-XiaomiPOCOX3NFCHuaxing` → `conf.d/sm8250/POCO X3.conf` →
`Xiaomi/surya/HiFi.conf`.

### 5.4 Comprobar

```sh
ssh <tu-movil> "export XDG_RUNTIME_DIR=/run/user/\$(id -u); pactl list cards | grep -A3 Profiles"
#   debe listar  HiFi (Speaker)  y  HiFi (Earpiece)

# reproducir algo y confirmar que suena por ambos altavoces
```

---

## 6. Recetas de diagnóstico

Para depurar el audio en este dispositivo:

```sh
# parar PipeWire para liberar la tarjeta
systemctl --user stop pipewire.socket pipewire-pulse.socket wireplumber pipewire

# leer un registro del ampli EN CRUDO (no via regmap, que cachea)
#   -f obligatorio: el driver retiene la dirección I2C
sudo i2cset -y -f 9 0x4c 0x00 0x00        # seleccionar página 0 primero
sudo i2cget -y -f 9 0x4c 0x02             # PWR_CTRL: 0x00=ACTIVE, 0x_2=SHUTDOWN

# volumen digital (página 2, regs 0x0c-0x0f): debe ser 40 00 00 00 a 0 dB
sudo i2cset -y -f 9 0x4c 0x00 0x02
sudo i2cget -y -f 9 0x4c 0x0c

# selector de canal (TDM_CFG2, bits 5:4): 1=Left 2=Right 3=L/Rmix 0=mute
#   ¡leer DURANTE la reproducción! es un mux DAPM, solo escribe si el camino está encendido
sudo i2cset -y -f 9 0x4c 0x00 0x00
sudo i2cget -y -f 9 0x4c 0x08

# restaurar PipeWire al terminar
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire
```

Consejos aprendidos a base de perder tiempo:
- Para localizar altavoces, usa tonos **agudos** o de **distinta altura** (una
  quinta, Do/Sol): los graves (<250 Hz) hacen vibrar todo el chasis y no se
  localizan.
- La captura de I/V sense (`arecord -D hw:0,1`) mide la **corriente real** en
  el altavoz — sirve como detector objetivo de "¿está sonando?" sin oídos.
- `i2c-tools` está instalado en el teléfono; el usuario tiene sudo sin
  contraseña por SSH (alias `<tu-movil>`).

> **⚠️ Arranque intermitente sin tarjeta:** en algunos arranques la tarjeta de
> sonido **no aparece** (`/proc/asound/cards` vacío, PipeWire muestra "Dummy
> Output"). Causa en dmesg: `qcom-sm7150-lpass-lpi-pinctrl: Failed to get clk
> 'core'` → el pinctrl LPI del LPASS difiere → `snd-sm8250: MultiMedia1: error
> getting cpu dai name` difiere toda la tarjeta. Es una **carrera de arranque
> del LPASS/ADSP** en el kernel WIP de sm7150, no un problema del audio.
> **Solución: reiniciar** (suele salir al segundo intento). Si el audio no va
> tras arrancar, mira `/proc/asound/cards` primero — si está vacío, reinicia.

> **⚠️ Trampa al probar el estéreo:** los scripts de diagnóstico que aíslan un
> altavoz silenciando el otro ponen el mux de **los dos** amplis en
> `LeftRightDiv2` (mezcla mono en ambos). Eso **sobreescribe** la config estéreo
> del UCM (`0x10`/`0x20`) y hace *parecer* que el estéreo está roto (los dos
> altavoces reproducen lo mismo). **No está roto** — es el test contaminando el
> estado. Para probar estéreo de verdad, usa solo el camino limpio del UCM:
> `systemctl --user restart wireplumber pipewire` + activar el perfil Speaker,
> y reproducir **sin** ningún `amixer ... ASI1 Sel`. Confirma con
> `TDM_CFG2` bits 5:4: `1`/`2` = estéreo, `3`/`3` = contaminado a doble mono.

---

*Trabajo realizado sobre postmarketOS v26.06, kernel 7.1-rc3 (sm7150-mainline),
julio 2026. Amplificadores TI TAS2562/TAS2564.*
