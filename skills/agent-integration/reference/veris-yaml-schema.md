# `veris.yaml` Reference For This Skill

Use this reference when generating or refreshing `.veris/veris.yaml`.

This skill targets the current preferred single-target shape used by `veris env create`. Do not generate legacy `persona.modality` config unless the user explicitly asks for compatibility.

## Preferred shape

```yaml
version: "1.0"

services:
  - name: salesforce
    dns_aliases:
      - login.salesforce.com

actor:
  init:                             # Optional pre-message setup call
    type: http
    method: POST
    url: http://localhost:8080/api/session
  channels:
    - type: http                    # http | ws | email | function | voice | browser-use
      url: http://localhost:8080/chat
      method: POST
      headers:
        Content-Type: application/json
      request:
        message_field: message
        session_field: session_id
        static_fields:
          prompt_type: default
      response:
        type: json                  # json | sse
        message_field: response
        session_field: session_id
  config:
    MAX_TURNS: "1"                  # Optional; use only when needed

agent:
  code_path: /agent
  entry_point: python -m app.main
  port: 8080
  environment:
    DATABASE_URL: postgresql://postgres:postgres@localhost:5432/SIMULATION_ID
    LOG_LEVEL: info
```

## Canonical choices

- Use `actor`, not `persona`
- Use `channels`, not `modality`
- Use `agent_inbox`, not `email_address`
- Use canonical service names from `reference/service-mapping.md`
- Use uppercase env-style keys in `actor.config`

## Services

Each `services[]` entry may include:

```yaml
services:
  - name: postgres
    dns_aliases: []                 # Only for DNS-routed services
    config:
      POSTGRES_PASSWORD: postgres
      SCHEMA_PATH: /agent/db/schema.sql
    port: 5432                      # Rarely needed
    description: "..."              # For generic services only
```

Notes:
- Only add `dns_aliases` when the agent calls non-default domains
- Only add `config` when the service needs it
- Do not add auth helper services (`google/auth`, `microsoft/auth`, etc.) unless there is a specific reason

## Actor channels

### HTTP

```yaml
actor:
  channels:
    - type: http
      url: http://localhost:8080/chat
      method: POST
      request:
        message_field: message
        session_field: session_id
      response:
        type: json
        message_field: response
```

### WebSocket

```yaml
actor:
  channels:
    - type: ws
      url: ws://localhost:8080/ws
      request:
        message_field: message
        session_field: session_id
      response:
        message_field: response
```

### Email

```yaml
actor:
  channels:
    - type: email
      agent_inbox: agent@email.test
      poll_interval: 15
```

`poll_interval` belongs on the email channel itself. Do not treat it as a general actor-global config knob.

### Function

```yaml
actor:
  config:
    MAX_TURNS: "1"                  # For one-shot/stateless callables
  channels:
    - type: function
      callable: app.handlers:handle_message
```

Function-channel rules:
- Omit `agent.entry_point`
- Omit `agent.port`
- Keep `agent.code_path`
- Use `MAX_TURNS: "1"` when the callable is one-shot/stateless

## SSE responses

```yaml
actor:
  channels:
    - type: http
      url: http://localhost:8080/chat
      request:
        message_field: message
      response:
        type: sse
        chunk_event: message
        chunk_field: delta
        chunk_filter_field: type
        chunk_filter_equals: delta
        done_data: "[DONE]"
```

Use this when the agent streams user-visible content through SSE.

## Agent section

```yaml
agent:
  name: Billing Assistant           # Optional display name
  code_path: /agent
  entry_point: uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port 8080
  port: 8080
  environment:
    DATABASE_URL: postgresql://postgres:postgres@localhost:5432/SIMULATION_ID
    SERVICE_BASE_URL: http://localhost:9000
```

If you reference service config artifacts like `SCHEMA_PATH: /agent/db/schema.sql`, make sure `.veris/Dockerfile.sandbox` copies that directory into the image.

Rules:
- `code_path` is usually `/agent`
- `entry_point` is required for non-function channels
- `port` is required for non-function channels
- Keep secrets out of `veris.yaml`
- Put stable non-secret defaults in `agent.environment`
- Use `veris env vars set --secret` for API keys and other sensitive values

## Environment expansion

`agent.environment` supports shell-style expansion:

```yaml
agent:
  environment:
    LOG_LEVEL: info
    DB_NAME: app_${SIMULATION_ID}
    API_BASE: ${API_BASE}
```

Use `${VAR}` only when you need expansion or composition. If the agent can simply read `OPENAI_API_KEY` or another runtime variable directly, prefer `veris env vars set` without duplicating that key in `veris.yaml`.

## `MAX_TURNS`

Use `actor.config.MAX_TURNS` sparingly:
- Set it for one-shot or stateless agents that should stop after one actor turn
- Do not add it by default for conversational agents
- Do not add the `*_INTERVAL` actor tuning knobs unless the user explicitly asks for advanced harness tuning
