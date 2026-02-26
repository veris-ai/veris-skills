# veris.yaml Annotated Examples

## Example 1: Python FastAPI + Postgres + Salesforce CRM

```yaml
services:
  - name: postgres
    config:
      POSTGRES_PASSWORD: postgres
      SCHEMA_PATH: /agent/schemas/schema.sql   # Optional: SQL file to initialize DB
  - name: crm
    dns_aliases:
      - login.salesforce.com
      - test.salesforce.com
      - mock-salesforce.salesforce.com

persona:
  modality:
    type: http
    url: http://localhost:8080/api/v1/chat
    request:
      message_field: message
      session_field: session_id
    response:
      type: json
      message_field: response

agent:
  code_path: /agent
  entry_point: app.main:app
  port: 8080
  environment:
    DATABASE_URL: postgresql://postgres:postgres@localhost:5432/SIMULATION_ID
    SALESFORCE_DOMAIN: mock-salesforce
    SALESFORCE_CONSUMER_KEY: mock_consumer_key_12345
    SALESFORCE_CONSUMER_SECRET: mock_consumer_secret_67890
    OPENAI_API_KEY: ${OPENAI_API_KEY}
```

## Example 2: Node.js + Slack + Jira

```yaml
services:
  - name: slack
  - name: atlassian/jira
    dns_aliases:
      - mycompany.atlassian.net

persona:
  modality:
    type: http
    url: http://localhost:3000/api/chat
    request:
      message_field: message
    response:
      type: json
      message_field: reply

agent:
  code_path: /agent
  entry_point: node server.js
  port: 3000
  environment:
    SLACK_BOT_TOKEN: xoxb-mock-token-for-veris-simulation
    JIRA_BASE_URL: https://mycompany.atlassian.net
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
```

## Example 3: Multi-process with bundled Redis + Jira (start.sh entry)

```yaml
services:
  - name: atlassian/jira
    dns_aliases:
      - mycompany.atlassian.net

persona:
  modality:
    type: http
    url: http://localhost:8080/chat

agent:
  code_path: /agent
  entry_point: bash start.sh
  port: 8080
  environment:
    REDIS_URL: redis://localhost:6379/0
    CELERY_BROKER_URL: redis://localhost:6379/0
    JIRA_URL: https://mycompany.atlassian.net
    OPENAI_API_KEY: ${OPENAI_API_KEY}
```

## Example 4: Multi-agent gateway

```yaml
persona:
  modality:
    type: http
    url: http://localhost:8080/api/v1/chat
    request:
      message_field: query
      session_field: conversation_id
    response:
      type: sse
      chunk_event: chunk
      chunk_field: text
      done_event: done

agent:
  code_path: /agent
  entry_point: bash start.sh
  port: 8080
  environment:
    FLIGHT_AGENT_URL: http://localhost:8081
    HOTEL_AGENT_URL: http://localhost:8082
    OPENAI_API_KEY: ${OPENAI_API_KEY}
```

## Field Reference

- **code_path**: Always `/agent` (where Dockerfile.sandbox copies code).
- **port**: Must not conflict with veris reserved range (avoid 6100-6299). Recommended: 8080, 8008, 3000.
- **entry_point**: Module format (`app.main:app`) for simple single-process cases. Command format (`bash start.sh`) for multi-process setups requiring bundled services or background workers. Paths are relative to code_path (entrypoint.sh cd's there first).
- **environment**: Use `${VAR}` syntax for secrets pulled from `.env.simulation` at runtime. Use `SIMULATION_ID` as a literal placeholder in database names (veris replaces it). Hardcode `localhost` URLs for inter-process communication within the container.
