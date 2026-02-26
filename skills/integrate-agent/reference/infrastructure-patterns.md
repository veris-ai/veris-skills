# Infrastructure Patterns — Restructuring Guide

Reference for converting agent infrastructure into the veris-sandbox single-container setup. Covers 7 common architecture patterns.

## Veris-Sandbox Container Model

Everything runs in ONE Docker container. The agent's code is COPY'd to `/agent/` by the Dockerfile.sandbox. The simulation config (`veris.yaml`) is mounted at `/config/veris.yaml` by the CLI at runtime — it is NOT baked into the image. Veris provides mock services (CRM, Calendar, Stripe, Postgres, Jira, Oracle), an LLM proxy, a persona simulator, and a simulation engine — all as co-resident processes. The agent starts via a single `entry_point` command defined in `veris.yaml`.

At startup, veris's `entrypoint.sh` does `cd $AGENT_CODE_PATH` (from `agent.code_path` in veris.yaml, typically `/agent`), then runs the entry_point command. This means **all entry_point paths are relative to code_path**.

**Reserved veris ports (do NOT use for the agent):** 6100-6299, 5432, 443.
**Recommended agent ports:** 8080, 8008, 3000.

---

## Pattern 1: Docker Compose — Single Agent + Infrastructure

**Typical setup:** FastAPI app + Postgres + Redis + Elasticsearch + Celery workers + nginx, all defined in `docker-compose.yml`.

**Characteristics:** One service is the agent (the thing a user talks to). Everything else is infrastructure the agent depends on.

### How to identify the agent service

Look for these signals in `docker-compose.yml`:

- Has the main HTTP port mapping (`ports: "8000:8000"`)
- Has a `command:` like `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- Other services `depends_on` it, or it depends on everything else
- Named something like `api`, `app`, `web`, `server`, `agent`

### Restructuring steps

**1. Copy only the agent's code:**

```dockerfile
# Dockerfile.sandbox
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY ./src /agent/src/

WORKDIR /app
```

Only copy the directory the agent service mounts or builds from. Do NOT copy Postgres data dirs, nginx configs, etc.

**2. Set the entry point:**

```yaml
# veris.yaml
agent:
  entry_point: uvicorn app.main:app --host 0.0.0.0 --port 8080
  port: 8080
  code_path: /agent
```

Match the `command:` from docker-compose, adjusting the port if needed. Entry point paths are relative to code_path (entrypoint.sh cd's there first).

**3. Replace infrastructure hostnames with localhost:**

Docker compose services communicate by service name (`postgres`, `redis`, `elasticsearch`). In veris, everything is localhost. Override via environment variables:

```yaml
# veris.yaml
agent:
  environment:
    DATABASE_URL: "postgresql://postgres:postgres@localhost:5432/${SIMULATION_ID}"
    REDIS_URL: "redis://localhost:6379"
    ELASTICSEARCH_URL: "http://localhost:9200"
```

**4. Handle Celery workers:**

- If Celery processes tasks triggered during a user conversation (e.g., async tool calls, webhook processing), they are needed. Add them to a `start.sh`:

```bash
#!/bin/bash
# Start Celery worker in background
celery -A app.celery_app worker --loglevel=info &

# Start the agent in foreground
exec uvicorn app.main:app --host 0.0.0.0 --port 8080
```

Note: start.sh runs from code_path (/agent), so no `cd` needed at the top.

- If Celery only runs scheduled/cron tasks (daily reports, batch jobs), it is likely not needed during simulation. Skip it.

**5. Skip nginx:**

Veris has its own nginx for TLS termination. The agent's nginx reverse proxy config is not needed.

**6. Bundle or skip other services:**

| Service | Decision |
|---|---|
| Redis | Bundle if agent uses it for caching/sessions during requests. Install in Dockerfile.sandbox: `apt-get install -y redis-server`, start in start.sh. |
| Elasticsearch | Heavy (~500MB). Use external endpoint if possible. Bundle only if agent queries ES on the critical path. Ask user first|
| MinIO/S3 | Lightweight. Bundle if agent stores/retrieves files during conversation. |
| Monitoring (Prometheus, Grafana) | Skip. Not needed for simulation. |

---

## Pattern 2: Single Container + supervisord / Multi-Process

**Typical setup:** supervisord managing FastAPI + webhook listener + alert poller + log shipper, all in one container.

**Characteristics:** Already single-container. Multiple processes managed by supervisord or a process manager.

### Restructuring steps

**1. Copy the entire app directory:**

```dockerfile
# Dockerfile.sandbox
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY ./app /agent/app/

WORKDIR /app
```

**2. Replace supervisord with start.sh:**

Supervisord adds unnecessary complexity for simulation. Replace it with a shell script that backgrounds processes.

Given a `supervisord.conf` like:

```ini
[program:api]
command=uvicorn app.main:app --port 8080

[program:webhook_listener]
command=python webhook_listener.py

[program:alert_poller]
command=python alert_poller.py

[program:fluent-bit]
command=/opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit.conf
```

Create this `start.sh`:

```bash
#!/bin/bash

# Triage: which processes are needed for simulation?

# NEEDED — webhook listener (persona/services send webhooks to agent)
python webhook_listener.py &

# NEEDED — alert poller (triggers agent behavior during simulation)
python alert_poller.py &

# SKIP — fluent-bit is a log shipper sidecar, agent code doesn't import it

# FOREGROUND — main API server (always needed)
exec uvicorn app.main:app --host 0.0.0.0 --port 8080
```

**3. Process triage rules:**

| Process type | Needed? |
|---|---|
| Main API server | Always. Runs in foreground with `exec`. |
| Webhook listener | Yes, if persona or veris services send webhooks to the agent. |
| Poller/scheduler | Yes, if it triggers agent actions during simulation time window. |
| Log shipper (fluent-bit, fluentd) | No, unless agent code directly imports/queries it. |
| Health check sidecar | No. Veris has its own health checks. |
| Metrics exporter | No. Not needed for simulation. |

**4. SQLite:**

If the agent uses SQLite, it works out of the box (file-based, no install needed). Ensure the path is writable — use `/agent/data/` or `/tmp/`.

**5. Entry point:**

```yaml
# veris.yaml
agent:
  entry_point: bash start.sh
  port: 8080
  code_path: /agent
```

Entry point paths are relative to code_path (entrypoint.sh cd's there first).

---

## Pattern 3: Cloud-Specific Services (Azure / AWS / GCP)

**Typical setup:** Azure OpenAI + Azurite + Cosmos DB emulator + Azure FHIR, or AWS services via LocalStack, or GCP BigQuery + Cloud SQL.

**Characteristics:** Heavy use of cloud-native services, sometimes with local emulators in docker-compose for development.

### Restructuring steps

**1. Classify each cloud service:**

| Service | Veris equivalent | Action |
|---|---|---|
| Azure OpenAI, OpenAI, Anthropic | LLM Proxy (port 443) | Automatic interception, no config needed |
| Google Calendar API | Calendar mock (port 6201) | Automatic via DNS aliasing |
| Salesforce API | CRM mock (port 6200) | Automatic via DNS aliasing |
| Postgres (RDS, Cloud SQL, Neon) | Postgres mock (port 6202/5432) | Change `DATABASE_URL` to localhost |
| Azure Blob (via Azurite) | Bundle Azurite or MinIO | Lightweight, works in-container |
| Cosmos DB emulator | External endpoint | Too heavy (~2GB) to bundle |
| LocalStack (full) | Evaluate per-service | ~200MB. Bundle only if agent uses multiple AWS services |
| LocalStack (just S3) | Bundle MinIO instead | MinIO is lighter and S3-compatible |
| FHIR, BigQuery, Snowflake | External endpoint | No veris mock. User provides staging URL + credentials. |

**2. Cloud SDK endpoint overrides:**

Most cloud SDKs read endpoint URLs from environment variables. No code changes needed — just override the env vars:

```yaml
# veris.yaml
agent:
  environment:
    # Azure Blob → local Azurite
    AZURE_STORAGE_CONNECTION_STRING: "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=...;BlobEndpoint=http://localhost:10000/devstoreaccount1"

    # AWS → local LocalStack or MinIO
    AWS_ENDPOINT_URL: "http://localhost:4566"
    AWS_ACCESS_KEY_ID: "test"
    AWS_SECRET_ACCESS_KEY: "test"

    # GCP → emulator
    STORAGE_EMULATOR_HOST: "http://localhost:9023"
```

**3. LLM proxy — automatic interception:**

Veris intercepts calls to `api.openai.com`, `api.anthropic.com`, and Azure OpenAI endpoints via DNS aliasing + TLS termination. The agent's LLM calls are proxied transparently. No environment variable changes needed for LLM endpoints.

**4. Bundle lightweight emulators in Dockerfile.sandbox:**

```dockerfile
# Dockerfile.sandbox
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install Node.js (needed for Azurite)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Install Azurite (Azure Blob emulator)
RUN npm install -g azurite

# Agent code
COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt
COPY ./src /agent/src/

WORKDIR /app
```

Start emulators in `start.sh`:

```bash
#!/bin/bash
# Start Azurite in background
azurite --silent --location /tmp/azurite --debug /tmp/azurite-debug.log &

# Start agent in foreground
exec uvicorn app.main:app --host 0.0.0.0 --port 8080
```

**5. External endpoints for heavy/unmocked services:**

For services without a veris mock or lightweight emulator, the user must provide an external endpoint:

```yaml
# veris.yaml
agent:
  environment:
    COSMOS_DB_ENDPOINT: "https://staging-cosmos.documents.azure.com:443/"
    COSMOS_DB_KEY: "<user-provided-key>"
    BIGQUERY_PROJECT: "staging-project-id"
```

---

## Pattern 4: Serverless / No Docker (Vercel, Railway, Fly.io)

**Typical setup:** Next.js on Vercel + Neon Postgres + Upstash Redis + Pinecone. No Dockerfile exists.

**Characteristics:** Agent has never been containerized. Deployed to a PaaS. Uses managed/serverless databases.

### Restructuring steps

**1. Determine the runtime:**

| Framework | Runtime | Install in Dockerfile.sandbox? |
|---|---|---|
| FastAPI, Flask, Django | Python | No (already in base image) |
| Next.js, Express, Hono | Node.js | Yes |
| Go (Gin, Echo) | Go | Yes |
| Rust (Actix, Axum) | Rust | Yes |

**2. Install non-Python runtimes:**

```dockerfile
# Dockerfile.sandbox — Node.js agent example
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install Node.js (not in base image)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Copy agent code and install dependencies
COPY package.json package-lock.json /agent/
WORKDIR /agent
RUN npm ci --production

COPY ./src /agent/src
COPY ./next.config.js /agent/
COPY ./tsconfig.json /agent/

# Build step (Next.js needs this)
RUN cd /agent && npm run build

# Prisma (if used)
COPY ./prisma /agent/prisma
RUN cd /agent && npx prisma generate

WORKDIR /app
```

**3. Map serverless databases to veris mocks:**

| Serverless DB | Veris replacement |
|---|---|
| Neon Postgres | Postgres mock. `DATABASE_URL=postgresql://postgres:postgres@localhost:5432/${SIMULATION_ID}` |
| PlanetScale (MySQL) | No veris mock. Bundle MySQL or use external endpoint. |
| Upstash Redis | Bundle Redis. `REDIS_URL=redis://localhost:6379` |
| Pinecone, Weaviate | No veris mock. Use external endpoint. |
| Supabase | Postgres mock for the DB. Auth/storage need external endpoint. |

**4. Entry point:**

```yaml
# veris.yaml
agent:
  entry_point: npx next start -p 8080
  port: 8080
  code_path: /agent
```

For Python serverless frameworks (FastAPI on Railway):

```yaml
agent:
  entry_point: uvicorn app.main:app --host 0.0.0.0 --port 8080
  port: 8080
  code_path: /agent
```

Entry point paths are relative to code_path (entrypoint.sh cd's there first).

**5. Handle Vercel/Railway-specific config:**

- `vercel.json`: Ignore `cron`, `rewrites`, `regions`, `functions`. The agent runs as a standard server.
- `railway.toml` / `fly.toml`: Extract the `start_command` — that becomes your entry point.
- `Procfile` (Heroku/Railway): The `web:` line is the entry point.

**6. Environment variables:**

- `NEXT_PUBLIC_*` vars must be set at **build time** (in the Dockerfile RUN build step), not just at runtime.
- All other env vars go in `veris.yaml` agent.environment.
- Do NOT copy `.env.local` or `.env.production` into the container. Declare all needed vars explicitly in veris.yaml.

**7. API routes:**

Next.js API routes (`app/api/*/route.ts`) work as-is — they are standard HTTP endpoints when running `next start`. No special handling needed.

---

## Pattern 5: Multi-Agent System with Gateway

**Typical setup:** API gateway + flight-agent + hotel-agent + activity-agent + itinerary-agent + Kafka or NATS for inter-agent messaging.

**Characteristics:** Multiple separate agent services that coordinate to handle requests. A gateway routes to sub-agents.

### Restructuring steps

**1. Copy all agent code:**

```dockerfile
# Dockerfile.sandbox
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install all dependencies from all sub-agents
COPY gateway/requirements.txt /tmp/gateway-req.txt
COPY flight-agent/requirements.txt /tmp/flight-req.txt
COPY hotel-agent/requirements.txt /tmp/hotel-req.txt
COPY itinerary-agent/requirements.txt /tmp/itinerary-req.txt
RUN pip install --no-cache-dir \
    -r /tmp/gateway-req.txt \
    -r /tmp/flight-req.txt \
    -r /tmp/hotel-req.txt \
    -r /tmp/itinerary-req.txt

# Copy each sub-agent
COPY ./gateway /agent/gateway/
COPY ./flight-agent /agent/flight-agent/
COPY ./hotel-agent /agent/hotel-agent/
COPY ./itinerary-agent /agent/itinerary-agent/

WORKDIR /app
```

If sub-agents share a `requirements.txt`, install it once. If they have conflicts, use separate virtualenvs (more complex — try to unify first).

**2. Determine the persona-facing port:**

The gateway is what the persona talks to. Its port goes in veris.yaml:

```yaml
agent:
  entry_point: bash start.sh
  port: 8080
  code_path: /agent
```

**3. Create start.sh with health-check waits:**

```bash
#!/bin/bash

# Start sub-agents in background
cd /agent/flight-agent && uvicorn main:app --host 0.0.0.0 --port 8081 &
cd /agent/hotel-agent && uvicorn main:app --host 0.0.0.0 --port 8082 &
cd /agent/itinerary-agent && uvicorn main:app --host 0.0.0.0 --port 8083 &

# Wait for sub-agents to be ready
for port in 8081 8082 8083; do
  echo "Waiting for service on port $port..."
  until curl -sf http://localhost:$port/health > /dev/null 2>&1; do sleep 1; done
  echo "Service on port $port is ready."
done

# Start gateway in foreground
cd /agent/gateway
exec uvicorn main:app --host 0.0.0.0 --port 8080
```

Use absolute paths inside start.sh for clarity — background processes with `&` make relative `cd` fragile.

**4. Override inter-agent communication URLs:**

Docker compose hostnames become localhost:

```yaml
# veris.yaml
agent:
  environment:
    FLIGHT_AGENT_URL: "http://localhost:8081"
    HOTEL_AGENT_URL: "http://localhost:8082"
    ITINERARY_AGENT_URL: "http://localhost:8083"
```

**5. Handle message queues (Kafka, NATS, RabbitMQ):**

This is the biggest decision for multi-agent systems:

| Option | When to use |
|---|---|
| **Bundle Kafka** | Only if event streaming is core to agent logic (e.g., agents react to event streams, not just request-response). Very heavy (~500MB+ with Zookeeper). |
| **Bundle RabbitMQ** | If message routing/acknowledgment matters. Lighter than Kafka (~150MB). |
| **Bundle Redis pub/sub** | If the queue is just for async task dispatch. Lightest option. |
| **Replace with direct HTTP** | If the queue is used as a simple job queue between known services. Modify agent code to call HTTP endpoints directly. |
| **External endpoint** | If bundling is too heavy and code changes are too invasive. User provides a managed Kafka/NATS URL. |

If bundling Kafka, add to start.sh:

```bash
# Start Zookeeper and Kafka
/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
sleep 3
/opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
sleep 3

# Create required topics
/opt/kafka/bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --topic agent-events --partitions 1 --replication-factor 1 2>/dev/null || true
```

**6. gRPC between agents:**

gRPC works on localhost. Just update the target addresses:

```yaml
agent:
  environment:
    FLIGHT_AGENT_GRPC: "localhost:50051"
    HOTEL_AGENT_GRPC: "localhost:50052"
```

---

## Pattern 6: Hybrid Frontend + Backend Workers

**Typical setup:** Next.js frontend + Python workers (content generator, image processor, scheduler) + RabbitMQ or Redis queue.

**Characteristics:** Mixed-language stack. Frontend handles user interaction; backend workers process tasks from a queue.

### Restructuring steps

**1. Identify the persona-facing process:**

The persona interacts with the frontend (HTTP chat endpoint). The frontend port goes in veris.yaml.

**2. Install both runtimes:**

```dockerfile
# Dockerfile.sandbox
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install Node.js (Python already in base image)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Install RabbitMQ (if needed as message broker)
RUN apt-get update && apt-get install -y rabbitmq-server && rm -rf /var/lib/apt/lists/*

# Copy and install frontend
COPY frontend/package.json frontend/package-lock.json /agent/frontend/
RUN cd /agent/frontend && npm ci && npm run build

COPY ./frontend /agent/frontend/

# Copy backend workers
COPY backend/requirements.txt /agent/backend/requirements.txt
RUN pip install --no-cache-dir -r /agent/backend/requirements.txt

COPY ./backend /agent/backend/

WORKDIR /app
```

**3. Create start.sh:**

```bash
#!/bin/bash

# Start message broker
rabbitmq-server -detached
until rabbitmqctl status > /dev/null 2>&1; do sleep 1; done
echo "RabbitMQ is ready."

# Start Python workers in background
cd /agent/backend/content-worker && python main.py &
cd /agent/backend/image-processor && python main.py &

# Start frontend in foreground
cd /agent/frontend
exec npx next start -p 8080
```

**4. veris.yaml:**

```yaml
agent:
  entry_point: bash start.sh
  port: 8080
  code_path: /agent
```

**5. Queue alternatives:**

If the original stack uses RabbitMQ, it can be bundled (~150MB). For lighter alternatives:

| Original | Lighter alternative | Trade-off |
|---|---|---|
| RabbitMQ | Redis with `rq` or `celery[redis]` | Simpler, less robust routing |
| Kafka | Redis Streams | Only works for simple pub/sub patterns |
| SQS (AWS) | Redis with `rq` | Need code changes to swap SDK |

**6. Skip monitoring and observability:**

- Prometheus + Grafana: skip unless agent code queries the Prometheus metrics API at runtime.
- Jaeger/Zipkin tracing: skip. Tracing is for debugging, not simulation.
- ELK stack: skip. Logs go to stdout in the container.

**7. Shared state between frontend and workers:**

If frontend and workers share state via Redis or a database, ensure both point to the same instance:

```yaml
agent:
  environment:
    REDIS_URL: "redis://localhost:6379"
    DATABASE_URL: "postgresql://postgres:postgres@localhost:5432/${SIMULATION_ID}"
    RABBITMQ_URL: "amqp://guest:guest@localhost:5672/"
```

---

## Pattern 7: Custom / Doesn't Match Above

When the agent architecture doesn't fit any of the patterns above, use this decision framework.

### Questions to ask the user

1. **Which process handles user/persona interaction?** This is the HTTP endpoint where a user sends a chat message. It becomes the entry point and its port goes in veris.yaml.
2. **What happens when a user sends a message?** Trace the full request path: API server -> queue -> worker -> database -> response. Every service on this path must run in the container.
3. **Which services are on the critical path for responding?** If the agent can't respond without a service, it must be bundled or connected externally.
4. **Are there background processes that MUST run during simulation?** Pollers, schedulers, webhook listeners that trigger agent behavior.

### Decision framework for each dependency

```
Is it a database?
  ├── Postgres → Use veris postgres mock (port 5432)
  ├── SQLite → Works as-is (file-based)
  ├── MongoDB → Bundle (apt-get install -y mongod) or external
  └── Other → Bundle if lightweight, external if heavy

Is it a message queue?
  ├── Redis → Bundle (lightweight, ~50MB)
  ├── RabbitMQ → Bundle (~150MB) or replace with Redis
  ├── Kafka → External endpoint or replace with Redis Streams
  └── NATS → Bundle (single binary, very lightweight)

Is it an API the agent calls?
  ├── OpenAI/Anthropic/Azure OpenAI → Automatic (veris LLM proxy)
  ├── Google Calendar → Automatic (veris calendar mock)
  ├── Salesforce → Automatic (veris CRM mock)
  ├── Stripe → Automatic (veris Stripe mock)
  ├── Jira → Automatic (veris Jira mock)
  └── Other → External endpoint (user provides URL + credentials)

Is it a runtime/language?
  ├── Python → Already in base image
  ├── Node.js → Install in Dockerfile.sandbox
  ├── Go → Install or compile binary in Dockerfile.sandbox
  └── Other → Install in Dockerfile.sandbox

Is it infrastructure tooling?
  ├── nginx → Skip (veris has its own)
  ├── Monitoring (Prometheus, Grafana) → Skip
  ├── Log shipping (fluent-bit, fluentd) → Skip
  ├── Service mesh (Envoy, Istio) → Skip
  └── Health check sidecar → Skip
```

### General principles

- The entry point process runs in **foreground** (with `exec` in start.sh).
- Supporting processes run in **background** (with `&` in start.sh).
- All inter-process communication uses **localhost**.
- Agent port = the port the persona sends requests to.
- When in doubt, start minimal and add services only when the agent fails without them.

---

## Common Rules Across All Patterns

These apply regardless of which pattern the agent matches.

### File placement (inside the container at runtime)

| What | Where | How it gets there |
|---|---|---|
| Agent code | `/agent/` | COPY'd by Dockerfile.sandbox. Matches `code_path: /agent` in veris.yaml |
| veris.yaml | `/config/veris.yaml` | Mounted by CLI at runtime (`-v .veris/veris.yaml:/config/veris.yaml:ro`). Do NOT COPY it. |
| start.sh (if needed) | `/agent/start.sh` | COPY'd by Dockerfile.sandbox. Referenced as `entry_point: bash start.sh` (relative to code_path) |

### Dockerfile.sandbox requirements

Every `Dockerfile.sandbox` must end with:

```dockerfile
WORKDIR /app
```

This is a veris requirement. The entrypoint.sh expects this working directory.

### Port conflicts

Agent ports must NOT conflict with veris service ports:

| Port range | Used by |
|---|---|
| 443 | Veris nginx (TLS termination, DNS interception) |
| 5432 | Veris Postgres mock (native TCP) |
| 6100-6102 | Veris infrastructure (engine, persona, LLM proxy) |
| 6200-6299 | Veris mock services (CRM=6200, Calendar=6201, Postgres HTTP=6202, Oracle=6203, Jira=6204, Stripe=6205, Slack=6206, Hogan=6207, Confluence=6209, Shopify=6211-6212) |

**Safe agent ports:** 8080, 8008, 3000, 3001, 4000, 5000, 9000.

### Hostname translation

Docker compose service names become localhost. Common translations:

```yaml
# docker-compose hostnames → veris environment
postgres:5432     → localhost:5432
redis:6379        → localhost:6379
rabbitmq:5672     → localhost:5672
elasticsearch:9200 → localhost:9200
kafka:9092        → localhost:9092
api-gateway:8080  → localhost:8080
```

### start.sh template

When the agent needs multiple processes:

```bash
#!/bin/bash
set -e

# ---- Background services ----
# Start each supporting process and wait for readiness

some-service --daemon &
until some-health-check; do sleep 1; done

# ---- Background workers ----
cd /agent/worker && python main.py &

# ---- Foreground: main agent process ----
exec uvicorn app.main:app --host 0.0.0.0 --port 8080
```

Rules for start.sh:
- Use `exec` for the final (foreground) process so it receives signals correctly.
- Use `&` for background processes.
- Add health-check waits (`until curl ...`) before starting processes that depend on background services.
- Use `set -e` so the script fails fast if a critical setup step fails.
