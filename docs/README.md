# Documentation

The per-subsystem notes are **in Spanish** (`*.es.md`): they are the working record kept while the
port was made, and translating them would have meant rewriting them from memory rather than
preserving what was actually measured. They are worth reading even through a translator, because
they record *how* each thing was found, and the traps that cost the most time.

| File | What it covers |
|---|---|
| [`camera.es.md`](camera.es.md) | The camera, from "not a single packet" to autofocus. The root cause was that the sensor transmits in **C-PHY** while the receiver was set to D-PHY |
| [`audio.es.md`](audio.es.md) | Audio architecture: amplifiers, routing, call path through the DSP |
| [`bluetooth.es.md`](bluetooth.es.md) | Bluetooth calls: SCO over SLIMBus and offload to the chip |
| [`notifications.es.md`](notifications.es.md) | Notification sound and vibration — three stacked causes |
| [`changes.es.md`](changes.es.md) | Every change, patch by patch |
| [`pending.es.md`](pending.es.md) | What is still open, and where to start on each |
| [`deploy.es.md`](deploy.es.md) | How the working state is deployed and verified |
| [`blobs.md`](blobs.md) | Extracting the vendor firmware from your **own** phone (English) |
| [`../tools/qmi-loc-idl/`](../tools/qmi-loc-idl/) | Decoding the modem's QMI LOC interface table — all 470 messages (English) |

## Lessons that generalise beyond this phone

A few of these cost days, and none of them are specific to a POCO X3:

- **Matching the factory byte for byte does not prove you are right.** The camera's registers were
  verified identical to the vendor's for months. They were — including a mode bit nobody had
  decoded, which said the sensor speaks C-PHY while the receiver was configured for D-PHY.
- **An I²C ACK does not mean the chip understood you.** The focus actuator accepted every command
  and moved nothing: right manufacturer, wrong protocol dialect.
- **A zero proves nothing without a positive control.** Counters read zero for months; the value
  only became evidence once a test pattern showed the same counters working.
- **Read the row stride from `bytesused / height`, never from the width.** Padding turns a correct
  photo into a banding pattern that looks exactly like a broken sensor.
- **The absence of an error message is not success.** Check the precondition ran at all.
