# Equivalencias de numeración de parches — 2026-08-06

La serie pasó de **83 parches a 106** al regenerarla desde git. Hizo falta porque la vieja
**estaba incompleta**: 73 de 83 aplicaban y 10 fallaban, porque faltaban commits intermedios
(ver `../VERIFICACION-2026-08-06.md`). La serie nueva aplica limpia y reproduce el kernel
desplegado **bit a bit**.

Los documentos vivos (`LISTA.md`, `DOCUMENTACION.md`, `COMO-DEJAR-TODO-FUNCIONANDO.md`,
`PENDIENTES.md`) usan ya la numeración **nueva**. Los documentos históricos —`HALLAZGOS-*`,
`SESION-*`, `PLAN-TODO-A-LA-VEZ.md`— conservan la **vieja** a propósito: son el registro de lo
que pasó y reescribirlos falsearía el relato. Esta tabla sirve para leerlos.

⚠️ **No siempre es uno a uno.** Varios parches viejos eran diffs hechos a mano que agrupaban
más de un commit: el viejo `0082` es hoy `0100`+`0101`, y el viejo `0083` es `0102`+`0103`.
Ese agrupamiento es justo lo que rompía la serie.

| viejo | nuevo | asunto / nota |
|---|---|---|
| 0001 | **0001** | arm64: dts: qcom: sm7150-xiaomi-common: fix USB-C to |
| 0002 | **0002** | power: supply: add TI BQ25970 switched-capacitor |
| 0003 | **0003** | arm64: dts: qcom: sm7150-xiaomi-common: raise max |
| 0004 | **0004** | power: supply: qcom_qg: use empirically-calibrated |
| 0005 | **0005** | ASoC: qcom: sm8250: call set_fmt() on every codec DAI |
| 0006 | **0006** | ASoC: tas2562: force a real hardware reset pulse at |
| 0007 | **0007** | ASoC: tas2562: widen reset pulse settle time to 100ms |
| 0008 | **0008** | ASoC: qcom: experimental TAS256x smart-amp AFE module |
| 0009 | **0009** | Revert: remove experimental smart-amp AFE call from |
| 0010 | **0010** | ASoC: qcom: fix TAS256x smart-amp AFE experiment port |
| 0011 | **0011** | Revert: remove smart-amp AFE call from sm8250.c |
| 0012 | **0012** | ASoC: qcom: q6afe-dai: try smart-amp AFE registration |
| 0013 | **0013** | ASoC: tas2562: write vendor test-page registers at |
| 0014 | **0014** | ASoC: tas2562: replicate the rest of the vendor |
| 0015 | **0015** | ASoC: tas2562: implement book-switching for the last |
| 0016 | **0016** | ASoC: tas2562: apply the real tas256x_reg.bin |
| 0017 | **0017** | Revert: remove the smart-amp AFE experiment from |
| 0018 | **0018** | ASoC: tas2562: set the RX slot length from hw_params, |
| 0019 | **0019** | arm64: dts: qcom: sm7150-xiaomi-surya: wire up the |
| 0020 | **0022** | ASoC: tas2562: write the digital volume as one burst, |
| 0021 | **0023** | ASoC: tas2562: drop the regmap defaults, they do not |
| 0022 | **0026** | ASoC: tas2562: re-assert the channel mux from the DAC |
| 0023 | **0027** | ASoC: tas2562: force the RX slot length too in the |
| 0024 | **0028** | ASoC/remoteproc: q6v5-pas keep modem proxy power vote |
| 0025 | **0029** | ASoC: qcom: q6voice: import CS voice-call driver from |
| 0026 | **0030** | arm64: dts: qcom: sm7150: wire up q6voice CS-Voice |
| 0027 | **0031** | arm64: dts: qcom: sm7150/surya: wire up WCD9375 |
| 0028 | **0032** | arm64: dts: qcom: sm7150: drop unimplemented LPASS |
| 0029 | **0033** | ASoC: codecs: wcd937x: use cansleep accessor for the |
| 0030 | **0034** | arm64: dts: qcom: sm7150: fix SoundWire controller |
| 0031 | **0035** | arm64: dts: qcom: sm7150: mux WCD9375 reset GPIO as |
| 0033 | **0036** | arm64: dts: qcom: sm7150: don't force WCD9375 reset |
| 0034 | **0039** | arm64: dts: qcom: sm7150: add SoundWire TX wake |
| 0035 | **0037** | arm64: dts: qcom: sm7150-xiaomi-common: pin WCD9375 |
| 0036 | **0038** | pinctrl: qcom: sm7150-lpass-lpi: fix swr_tx_data mux |
| 0037 | **0040** | arm64: dts: qcom: sm7150-xiaomi-surya: fix WCD9375 TX |
| 0038 | **0041** | regulator: add Will Semiconductor WL2866D camera PMIC |
| 0039 | **0042** | arm64: dts: qcom: sm7150-xiaomi-surya: add WL2866D |
| 0040 | **0043** | media: i2c: add Sony IMX682 sensor driver |
| 0041 | **0044** | arm64: dts: qcom: sm7150-xiaomi-surya: add IMX682 |
| 0042 | **0045** | arm64: dts: qcom: sm7150-xiaomi-common: fix CSIPHY |
| 0043 | **0046** | media: qcom: camss: vote for refgen on sm7150 |
| 0044 | **0047** | media: i2c: add Samsung S5K3T2 sensor driver |
| 0045 | **0048** | arm64: dts: qcom: sm7150-xiaomi-surya: add S5K3T2 |
| 0046 | **0049** | media: qcom: camss: follow the vendor's CSIPHY |
| 0047 | **0050** | media: qcom: camss: fix a typo in sm7150's cphy_rx |
| 0048 | **0051** | media: qcom: camss: keep sm7150's CSIPHY RX clock at |
| 0049 | **0052** | ASoC: qcom: q6voice: allow taking the call uplink |
| 0050 | **0053** | ASoC: qcom: q6voice: implement the CVS stream and |
| 0051 | **0054** | ASoC: qcom: q6voice: use the vendor's vocproc |
| 0052 | **0056** | ASoC: qcom: q6voice: pair CVD sessions using the |
| 0053 | **0057** | ASoC: qcom: q6voice: default the vocproc Tx topology |
| 0054 | **0058** | ASoC: qcom: q6voice: log the vocproc ports at call |
| 0055 | **0059** | media: qcom: camss: add a runtime-tunable settle |
| 0056 | **0060** | arm64: dts: qcom: sm7150-xiaomi-common: enable the |
| 0057 | **0061** | media: input: pm8xxx-vibrator: fix the drv2 (extended |
| 0058 | **0062** | arm64: dts: qcom: sm7150-xiaomi-surya: add a |
| 0059 | **0063** | arm64: dts: qcom: sm7150-xiaomi-common: the Bluetooth |
| 0060 | **0064** | ASoC: tas2562: live +/-6 dB gain/volume trim over |
| 0061 | **0065** | arm64: dts: qcom: sm7150-xiaomi-common: enable the |
| 0062 | **0079** | input: touchscreen: nt36xxx: read the firmware size |
| 0063 | **0080** | media: qcom: camss: vfe: keep the interrupt disabled |
| 0064 | **0081** | arm64: dts: qcom: sm7150-xiaomi-surya: give call |
| 0065 | **0083** | ASoC: qdsp6: q6asm-dai: remember a stream that is |
| 0066 | **0084** | ASoC: qdsp6: q6routing: tell the voice stream before |
| 0067 | **0085** | ASoC: qdsp6: q6routing: rebuild the ADM matrix when a |
| 0068 | **0086** | ASoC: qdsp6: q6afe: set the AFE topology of the |
| 0069 | **0087** | ASoC: qdsp6: q6routing: knobs for the in-call |
| 0070 | **0088** | ASoC: qdsp6: match the vendor ADM/AFE command stream |
| 0071 | **0089** | ASoC: qdsp6: q6asm-dai: do not rebuild the DSP |
| 0072 | **0090** | ASoC: qdsp6: q6asm: open PCM streams with media |
| 0073 | **0092** | ASoC: qdsp6: q6core: ask the DSP to load a topology's |
| 0074 | **0093** | ASoC: qdsp6: q6afe: send port parameters the way the |
| 0075 | **0095** | Bluetooth: check the right bit for Write Synchronous |
| 0076 | **0095** | Bluetooth: check the right bit for Write Synchronous |
| 0077 | **0097** | ASoC: qcom: sm8250: the Bluetooth SCO link is not 48 |
| 0078 | **—** | plegado en los parches de q6afe (0086/0088/0093); era un diff a mano |
| 0079 | **—** | plegado en los parches de q6voice; era un diff a mano |
| 0080 | **0098** | ASoC: tas2562: resync the register page at every DAC power-up |
| 0081 | **0099** | ASoC: qdsp6: q6voice: repeat a device move once, unprompted |
| 0082 | **0100 + 0101** | el viejo juntaba el parche Y su corrección posterior |
| 0083 | **0102 + 0103** | íd.: la descarga del NGD y el `of_node_put` de más |
| 0084 | **0104** | slimbus: no aplazar el sondeo sin dirección lógica |

## Lo que la serie vieja no tenía

31 parches de la serie nueva no existían en la vieja. Entre ellos, los que explicaban los
fallos de aplicación: los commits intermedios de `hci_qca.c` (había 6 en git y 2 exportados) y
`slimbus/qcom-ngd-ctrl.c` (3 y 1), incluido **`0066`**, *«fixes para que el NGD funcione en
sm7150»*, sin el cual el bus no funciona en este SoC.

La serie anterior se conserva en `../kernel-serie-anterior/` por si hay que consultarla.
