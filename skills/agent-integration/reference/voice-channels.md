# Voice Channels (`voice_ws`)

Use this reference when the actor needs to talk to the agent over a real-time audio channel — phone-call analogues, voicebots, kiosk agents, anything where the system under test is a voice agent rather than a text chatbot.

The canonical Veris voice channel is `voice_ws`. It carries PCM16 / 24 kHz / mono audio over a WebSocket, in **one of two framings** selectable via the `protocol` field. The agent (or a small bridge process — see [infrastructure-patterns.md Pattern 9](infrastructure-patterns.md#pattern-9-transport-bridge)) must produce and consume audio in whichever framing the channel is configured for.

| `protocol` | Framing | Maps cleanly to |
|---|---|---|
| `binary` (default) | Bare PCM16 bytes per WS message; WS close = hangup | Gemini Live, ElevenLabs, AssemblyAI, Cartesia |
| `json` | JSON envelope `{"type":"audio","audio":"<b64>"}` + `{"type":"end"}` | OpenAI Realtime, Twilio media streams, Deepgram |

Pick the framing that matches the agent's native transport. If neither matches and you can't reconfigure the framework, [Pattern 9](infrastructure-patterns.md#pattern-9-transport-bridge) covers the in-container bridge.

## Channel shape

```yaml
actor:
  channels:
    - type: voice_ws
      url: ws://localhost:8080/voice
      protocol: binary              # or "json"
      # Optional persona tuning:
      language: en-US
      wait_for_callee_first: true
```

Fields:

| Field | Required | Default | Meaning |
|---|---|---|---|
| `type` | yes | — | Must be `voice_ws`. |
| `url` | yes | — | The WebSocket the actor will dial. Always `ws://localhost:<port>/<path>` — the actor and agent share the sandbox network. `wss://` is also accepted for external endpoints, but the in-sandbox case is `ws://`. |
| `protocol` | no | `binary` | Wire framing — see the table above. |
| `language` | no | `en-US` | BCP-47 tag used by the actor's STT and TTS. Set this when testing non-English flows. |
| `wait_for_callee_first` | no | `true` | If `true`, the actor expects the agent to speak first ("Thanks for calling Acme Bank, this is …"). If `false`, the actor speaks first. Most phone-call analogues want `true`. |

The schema also accepts `max_call_duration_s` and `silence_timeout_s`, but those fields are not currently threaded through to the runner — the actor uses a hardcoded 600 s call cap and does not honor a per-config silence timeout. Don't rely on either knob for tuning; either change the runtime constant or wait for the fields to be wired through.

## Wire protocol

Audio is the same on both ends in either framing:

| Property | Value |
|---|---|
| Sample rate | 24,000 Hz |
| Sample format | signed 16-bit little-endian (`s16le`) |
| Channels | mono |
| Frame cadence | bridges should emit at 50 fps (20 ms / frame). The actor is tolerant of bursty input, but its own *output* pump sends at 50 fps — match it on the way in for symmetric behavior |
| End of call | `binary`: either side closes the WebSocket. `json`: either side closes the WS, or the agent sends `{"type":"end"}` first for a graceful hangup |

### Binary framing (`protocol: binary`)

Every WebSocket message is binary, and every binary message is raw PCM16 bytes — `Int16Array` little-endian. No envelope, no control plane, no JSON metadata. A text frame is a protocol violation (the actor will disconnect).

### JSON framing (`protocol: json`)

Every WebSocket message is text. The actor sends and accepts these message shapes:

```json
{"type": "audio", "audio": "<base64-encoded PCM16 24 kHz mono>"}
{"type": "end"}
```

The agent should respond with `{"type":"audio", ...}` messages of the same shape, and may send `{"type":"end"}` to signal a graceful hangup. Bytes inside `audio` are still raw PCM16 — the JSON layer is just an envelope to match the OpenAI Realtime / Twilio / Deepgram wire shapes.

## Turn detection and the trailing silence convention

The Veris voice actor uses server-side VAD with a ~1500 ms silence window to detect end-of-turn. That means: **after the agent finishes a turn, the bridge must keep sending audio frames** — specifically silence — for at least ~1700 ms so the actor's VAD can commit. If the agent stops emitting bytes entirely between turns, the actor's VAD never sees end-of-speech and the conversation deadlocks.

Speech-to-speech realtime models (OpenAI Realtime, Gemini Live, AWS Nova Sonic) emit audio deltas only while the model is actively speaking — they do **not** fill the gaps between turns with silence on their own. So a naive bridge that just forwards the model's deltas to the actor will hang after the first reply.

Two patterns that work:

1. **Pace a 20 ms frame clock and inject silence during gaps.** Drain the model's audio output into a queue, then run a separate 50 fps pump that pulls a frame from the queue if available or emits a 20 ms silent frame otherwise. This is what Veris's own actor does on its output path — see `sandbox/actors/app/channels/voice_base.py:_forward_audio_delta` in the platform repo for the canonical implementation. The bridge stays "always live" the way a real microphone would be.

2. **Pump explicit silence at turn end.** After detecting "agent turn complete" (on OpenAI Realtime that's the `response.done` event; on most frameworks there's an equivalent signal), send ~1700 ms of zero-valued PCM16 frames in a burst:

   ```python
   SAMPLE_RATE_HZ = 24000
   END_OF_TURN_SILENCE = b"\x00\x00" * (SAMPLE_RATE_HZ * 1700 // 1000)
   await actor_ws.send_bytes(END_OF_TURN_SILENCE)
   ```

   Simpler than the continuous pump, fine for one-turn-per-response shapes, but loses the "always live mic" semantics during long tool calls where the agent should still be hearing the caller.

If your simulation hangs after the agent's first reply (actor never sends a follow-up), missing silence is the first thing to check.

## Choosing how the agent reaches `voice_ws`

The actor will always speak whichever framing the channel is configured for. The agent has three options for matching it:

1. **The framework natively speaks the configured framing.** Pipecat's `WebsocketServerTransport` configured with a `RawAudioFrameSerializer` matches `protocol: binary`. A bare OpenAI Realtime endpoint already speaks `protocol: json` (the envelope is OpenAI's own wire format). With the right transport plugin, the agent serves `voice_ws` directly — no bridge process, no extra container.

2. **The framework speaks a different transport.** LiveKit Agents (WebRTC end-to-end), agents wired to SIP/Twilio media streams, custom in-house frameworks with incompatible message envelopes — all need a small bridge process inside the sandbox container that translates between the actor's framing and the framework's native transport. See [Pattern 9: Transport bridge](infrastructure-patterns.md#pattern-9-transport-bridge) for the architecture.

3. **The agent is custom and you control the wire format.** Implement a `voice_ws` handler directly in the agent — accept WS frames in the configured framing, route them into your speech/LLM stack, write response audio back. Minimum-viable voice agents typically take this path.

The first question to ask of any voice agent is which of these three applies. If the framework's transport is fixed and matches neither `binary` nor `json` framing, you are in case (2) and need a bridge — that's not a Veris limitation, it's a property of the framework.

## Worked examples

### `protocol: binary` — bridge / Pipecat / direct PCM16 endpoint

```yaml
version: "1.0"

actor:
  channels:
    - type: voice_ws
      url: ws://localhost:8080/voice
      protocol: binary
      language: en-US
      wait_for_callee_first: true

agent:
  code_path: /agent
  entry_point: uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port 8080
  port: 8080
  environment:
    LOG_LEVEL: info
```

That's the whole config for an agent whose framework speaks PCM16 over WS directly (case 1) or one that bundles a `Pattern 9` bridge (case 2 — only the `entry_point` changes to `bash start.sh`).

### `protocol: json` — OpenAI Realtime / Twilio-style envelope

```yaml
version: "1.0"

actor:
  channels:
    - type: voice_ws
      url: ws://localhost:8080/voice
      protocol: json
      language: en-US
      wait_for_callee_first: true

agent:
  code_path: /agent
  entry_point: uv run --no-sync python -m app.realtime_server
  port: 8080
```

The agent receives `{"type":"audio","audio":"<b64 PCM16>"}` messages from the actor and replies with the same shape. The actor handles base64 encoding/decoding on its side; the agent's job is to (un)wrap the JSON envelope around the same PCM16 bytes it would handle in binary mode.

## Common pitfalls

- **Wrong sample rate.** If the agent emits 16 kHz or 48 kHz instead of 24 kHz, the actor's STT will fail silently — you'll see "actor never responds" rather than an error. Confirm 24 kHz end to end.
- **Stereo frames.** Mono only. A 2-channel PCM16 frame is twice the bytes for the same wall-clock audio and decodes to garbled audio.
- **WAV/RIFF headers.** Send raw PCM samples (or base64 of raw PCM in JSON mode), not a WAV file. If you're using a TTS that defaults to WAV, request `format: "pcm"` or `response_format: "pcm"`.
- **Framing mismatch.** A binary WS message in `protocol: json` mode (or a text/JSON message in `protocol: binary` mode) is a protocol violation — the actor will disconnect. Make sure the agent's transport and the channel's `protocol` field agree.
- **Missing silence between turns.** Covered above — the most common cause of "simulation hangs after the first turn."

## Not yet covered

- SIP / PSTN ingress. Veris currently exposes the voice channel only over WebSocket; calling the agent from a real phone number is a platform feature, not a `veris.yaml` channel option.
- DTMF events. Tone detection and dialed-digit handling are not part of the `voice_ws` channel today.
- Multi-channel audio (caller + agent recorded on separate channels). Recordings produced by the actor are mono mixed.
