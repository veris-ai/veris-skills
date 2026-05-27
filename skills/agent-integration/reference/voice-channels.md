# Voice Channels (`voice_ws`)

Use this reference when the actor needs to talk to the agent over a real-time audio channel — phone-call analogues, voicebots, kiosk agents, anything where the system under test is a voice agent rather than a text chatbot.

The canonical Veris voice channel is `voice_ws`. It carries raw PCM16 audio frames over a binary WebSocket. It is intentionally minimal — no envelope, no control plane, no JSON metadata. That makes it interoperable with almost any voice agent framework, but it also means the agent (or a small bridge process — see [infrastructure-patterns.md Pattern 9](infrastructure-patterns.md#pattern-9-transport-bridge)) must produce and consume bare PCM16 on the wire.

## Channel shape

```yaml
actor:
  channels:
    - type: voice_ws
      url: ws://localhost:8080/voice
      protocol: binary
      # Optional tuning — defaults shown.
      language: en-US
      max_call_duration_s: 600
      wait_for_callee_first: true
      silence_timeout_s: 12
```

Fields:

| Field | Required | Default | Meaning |
|---|---|---|---|
| `type` | yes | — | Must be `voice_ws`. (`voice` is reserved for future channel variants and is not currently used.) |
| `url` | yes | — | The WebSocket the actor should connect to. Always `ws://localhost:<port>/<path>` — the actor and agent share the sandbox network. |
| `protocol` | no | `binary` | Wire format. Only `binary` (raw PCM16) is supported today. |
| `language` | no | `en-US` | BCP-47 tag used by the actor's STT and TTS. Set this when testing non-English flows. |
| `max_call_duration_s` | no | `600` | Hard cap on call length. The actor closes the WS after this many seconds even if the conversation hasn't naturally ended. |
| `wait_for_callee_first` | no | `true` | If `true`, the actor expects the agent to speak first ("Thanks for calling Acme Bank, this is …"). If `false`, the actor speaks first. Most phone-call analogues want `true`. |
| `silence_timeout_s` | no | `12` | If the actor hears no audio from the agent for this many seconds, it ends the call. Set higher for slow tool calls. |

## Wire protocol

Once the WebSocket is open, both sides exchange **binary frames carrying raw PCM16 audio**:

| Property | Value |
|---|---|
| Sample rate | 24,000 Hz |
| Sample format | signed 16-bit little-endian (`s16le`) |
| Channels | mono |
| Frame size | variable — pass through as the source emits |
| Metadata frames | none — every binary frame is audio bytes |
| End of call | either side closes the WebSocket |

No JSON, no protobuf, no Twilio-style envelope. Just `Int16Array` bytes in, `Int16Array` bytes out.

## Turn detection and the trailing silence convention

The Veris voice actor uses server-side VAD with a ~1500 ms silence window to detect end-of-turn. That means: **after the agent finishes a turn, it should keep sending audio frames** — specifically silence — for at least ~1700 ms so the actor's VAD can commit. Most agent frameworks emit silence between turns naturally, but some only emit audio while speaking and go quiet between turns, which leaves the actor's VAD waiting forever for either silence or speech to commit on.

Two ways to satisfy this:

1. **Let the framework's VAD pump silence.** OpenAI Realtime, Gemini Live, and most server-VAD speech-to-speech models emit silent frames continuously while idle. No extra work needed.
2. **Pump explicit silence at turn end.** After detecting "agent turn complete" (e.g., on OpenAI Realtime's `response.done` event), send ~1700 ms of zero-valued PCM16 frames:

   ```python
   SAMPLE_RATE_HZ = 24000
   END_OF_TURN_SILENCE = b"\x00\x00" * (SAMPLE_RATE_HZ * 1700 // 1000)
   await actor_ws.send_bytes(END_OF_TURN_SILENCE)
   ```

If your simulation hangs after the agent's first reply (actor never sends a follow-up), the trailing silence is the first thing to check.

## Choosing how the agent reaches `voice_ws`

The actor will always speak this exact protocol. The agent has three options for matching it:

1. **The framework natively speaks the same wire format.** Pipecat's `WebsocketServerTransport` configured with a `RawAudioFrameSerializer` (rather than the default `ProtobufFrameSerializer` or a Twilio JSON serializer) is the canonical example. With ~5 lines of transport config, the agent serves `voice_ws` directly — no bridge process, no extra container.

2. **The framework speaks a different transport.** LiveKit Agents (WebRTC end-to-end), agents wired to SIP/Twilio media streams, custom in-house frameworks with mandatory message envelopes — all need a small bridge process inside the sandbox container that translates between the actor's bare PCM16 WS and the framework's native transport. See [Pattern 9: Transport bridge](infrastructure-patterns.md#pattern-9-transport-bridge) for the architecture.

3. **The agent is custom and you control the wire format.** Write a `voice_ws` handler directly in your agent — accept binary WS frames, route them into your speech/LLM stack, write the response audio back as binary frames. Minimum-viable voice agents typically take this path.

The first question to ask of any voice agent is which of these three applies. If the framework's transport is fixed and not raw PCM16, you are in case (2) and need a bridge — that's not a Veris limitation, it's a property of the framework.

## Worked example: `voice_ws` veris.yaml

```yaml
version: "1.0"

actor:
  channels:
    - type: voice_ws
      url: ws://localhost:8080/voice
      language: en-US
      wait_for_callee_first: true

agent:
  code_path: /agent
  entry_point: uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port 8080
  port: 8080
  environment:
    LOG_LEVEL: info
```

That's the whole config for an agent whose framework speaks `voice_ws` directly (case 1). For case 2 (framework needs a bridge), the only `veris.yaml` change is `entry_point: bash start.sh` so the in-container `start.sh` can launch the framework plus the bridge — the channel definition stays the same. The actor doesn't care what's behind the WebSocket; it just sends and receives PCM16.

## Common pitfalls

- **Wrong sample rate.** If the agent emits 16 kHz or 48 kHz instead of 24 kHz, the actor's STT will fail silently — you'll see "actor never responds" rather than an error. Confirm 24 kHz end to end.
- **Stereo frames.** Mono only. A 2-channel PCM16 frame is twice the bytes for the same wall-clock audio and decodes to garbled audio.
- **WAV/RIFF headers.** Send raw PCM samples, not a WAV file. If you're using a TTS that defaults to WAV, request `format: "pcm"` or `response_format: "pcm"`.
- **JSON control frames.** The protocol has no control plane. Sending `{"type": "ready"}` over the WS will either be ignored or cause the actor to disconnect. Use binary frames only.
- **Missing trailing silence.** Covered above — the most common cause of "simulation hangs after the first turn."

## Not yet covered

- SIP / PSTN ingress. Veris currently exposes the voice channel only over WebSocket; calling the agent from a real phone number is a platform feature, not a `veris.yaml` channel option.
- DTMF events. Tone detection and dialed-digit handling are not part of the `voice_ws` channel today.
- Multi-channel audio (caller + agent recorded on separate channels). Recordings produced by the actor are mono mixed.
