### Full Schema

```yaml
version: "1.0"                         # Optional

services:                              # Mock services to enable
  - name: <string>                     # Required. Must match veris service catalog.
    dns_aliases:                       # Optional. Override default DNS aliases.
      - <domain>
    config:                            # Optional. Service-specific env vars.
      KEY: value

persona:                               # User simulator configuration
  modality:
    type: http | ws | email            # Required. How persona communicates with agent.
    url: <string>                      # Required for http/ws. Agent's chat endpoint URL.
    email_address: <string>            # Required for email modality.
    method: POST                       # Optional. HTTP method (default: POST).
    headers:                           # Optional. Custom HTTP headers.
      Content-Type: application/json
    request:                           # Optional. Request field mapping.
      message_field: message           # Default: "message"
      session_field: session_id        # Default: "session_id" (null to disable)
      static_fields:                   # Optional. Extra fields in every request.
        key: value
    response:                          # Optional. Response parsing.
      type: json | sse                 # Default: "json"
      message_field: response          # For json: field containing response text (default: "response")
      chunk_event: chunk               # For sse: event name (default: "chunk")
      chunk_field: chunk               # For sse: data field (default: "chunk")
      done_event: end_turn             # For sse: completion event (default: "end_turn")
  config:                              # Optional. Persona env var overrides.
    RESPONSE_INTERVAL: "2"

agent:                                 # Agent configuration
  code_path: /agent                    # Default: "/app". Where agent code lives.
  entry_point: <string>               # How to start. Module path or shell command.
  port: <number>                       # Port agent listens on (default: 8008).
  environment:                         # Env vars injected into agent process.
    KEY: value                         # Supports ${VAR} expansion and SIMULATION_ID literal.
```

### Entry Point Resolution

Entrypoint.sh does `cd $AGENT_CODE_PATH` (from `agent.code_path`), then tries in order:
1. `entry_point` from veris.yaml -- `eval`'d as shell command from code_path directory
   - Module format: `app.main:app` -- convention for uvicorn module path
   - Shell command: `bash start.sh` -- runs start.sh relative to code_path
   - npm command: `npx next start -p 8080` -- eval'd directly
2. If no entry_point: checks for `entrypoint.sh` in code_path directory -> `bash entrypoint.sh`
3. Default: `uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port $AGENT_PORT`

**All paths are relative to code_path** because entrypoint.sh cd's there first.

### Available Services

| Name | Description | Port | Protocol |
|---|---|---|---|
| crm | Salesforce REST API | 6200 | HTTPS (DNS) |
| calendar | Google Calendar API | 6201 | HTTPS (DNS) |
| postgres | PostgreSQL database | 6202 (HTTP) / 5432 (TCP) | TCP + HTTP |
| oracle | Oracle Fusion Cloud | 6203 | HTTP (no DNS) |
| atlassian/jira | Jira Cloud REST API | 6204 | HTTPS (DNS) |
| mcp/stripe | Stripe payments | 6205 | HTTPS (DNS, MCP) |
| slack | Slack API | 6206 | HTTPS (DNS) |
| hogan | Banking/CRM | 6207 | HTTPS (DNS) |
| atlassian/confluence | Confluence REST API v2 | 6209 | HTTPS (DNS) |
| mcp/shopify-storefront | Shopify Storefront | 6211 | HTTPS (DNS, MCP) |
| mcp/shopify-customer | Shopify Customer | 6212 | HTTPS (DNS, MCP) |

### Auto-Injected Environment Variables

These are set by veris automatically -- don't set them manually:
- `SIMULATION_ID` -- unique ID for the simulation run
- `PORT` -- agent's listening port
- `VERIS_MODE=container`
- `NODE_EXTRA_CA_CERTS=/certs/ca.crt` -- for Node.js TLS trust
- `SSL_CERT_FILE=/certs/ca-bundle.crt` -- for Python TLS trust
- `REQUESTS_CA_BUNDLE=/certs/ca-bundle.crt`

### Port Guidelines

- Agent ports: use 8080, 8008, 3000 or similar. Avoid 6100-6299 (reserved by veris).
- Mock service ports: auto-assigned, never override.
- PostgreSQL native: always 5432.
