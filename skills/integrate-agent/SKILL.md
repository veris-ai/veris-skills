---
name: integrate-agent
description: Convert an existing agent's infrastructure into a veris-sandbox single-container setup. Analyzes docker-compose, Dockerfiles, env files, and source code to generate veris.yaml, Dockerfile.sandbox, .env.simulation, and start.sh. Use after running `veris init`.
---

Integrate an agent with veris-sandbox: $ARGUMENTS

Convert this agent's infrastructure into a single-container veris-sandbox setup. Walk the user through the process interactively — explain what you're doing at each step, show what you find, and get their input before making decisions.

**Core principle: The user should always know what's happening and be able to steer it.**
- Before each step, briefly explain what you're about to do and why.
- When you find something noteworthy, tell the user.
- When there's a decision to make (what to bundle, what to skip, how to restructure), present options and let them choose.
- Never silently make a consequential decision. If in doubt, ask.
- **Explain veris concepts when you first mention them.** The user may not know what start.sh, entry_point, Dockerfile.sandbox, or veris.yaml are. Don't assume familiarity — give a one-liner explanation the first time you reference something.

**How veris simulations work (you must understand this):**

The veris container is a single Docker container that runs everything: mock services, LLM proxy, persona simulator, simulation engine, AND the user's agent. Here's the lifecycle:

1. **User's repo** has `.veris/` with three files: `veris.yaml`, `Dockerfile.sandbox`, `.env.simulation`.
2. **Build**: `docker build -f .veris/Dockerfile.sandbox .` — build context is the PROJECT ROOT (not `.veris/`). Dockerfile.sandbox extends the veris base image and COPY's agent code into the image.
3. **Run (local)**: `veris run local` does:
   - Builds the image from `.veris/Dockerfile.sandbox`
   - Runs it with: `-v .veris/veris.yaml:/config/veris.yaml:ro` (mounted, NOT in the image), `-v ./scenarios:/scenarios:ro`, `-e OPENAI_API_KEY=...`, `-e SCENARIO_ID=...`
4. **Run (cloud)**: `veris env push` builds+pushes the image. `veris run create` launches a K8s Job. veris.yaml and env vars are injected by the backend.
5. **Inside the container**, veris's `entrypoint.sh` orchestrates 7 phases: DNS config → TLS cert generation → nginx assembly → CA injection → start mock services → start agent → health gate → run simulation.
6. **Agent startup (Phase 5)**: entrypoint.sh does `cd $AGENT_CODE_PATH` (from veris.yaml `agent.code_path`, default `/app`) then resolves entry point:
   - If `agent.entry_point` set in veris.yaml → `eval` it as a shell command
   - Else if `entrypoint.sh` exists in agent code dir → `bash entrypoint.sh`
   - Else → `uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port $AGENT_PORT`

**Container filesystem at runtime:**
- `/app/` — veris infrastructure (mock services, engine, personas, llm-proxy). From base image.
- `/agent/` — user's agent code. COPY'd by Dockerfile.sandbox. Path set via `agent.code_path` in veris.yaml.
- `/config/veris.yaml` — simulation config. Mounted by CLI at runtime (NOT baked into image).
- `/scenarios/` — scenario YAML files. Mounted by CLI at runtime.
- `/certs/` — generated TLS certs + CA bundle. Created by entrypoint.sh at startup.
- `/sessions/{sim_id}/` — simulation logs and results. Mounted output directory.

**Key implications for this skill:**
- Dockerfile.sandbox should NOT `COPY .veris/veris.yaml` — it's mounted by the CLI.
- Agent code COPY'd to `/agent/` means `agent.code_path: /agent` in veris.yaml.
- start.sh (if needed) must end up inside the agent code path (e.g., COPY to `/agent/start.sh`), because entrypoint.sh does `cd $AGENT_CODE_PATH` before running it. Set `entry_point: bash start.sh` (relative path, since we're already cd'd there).
- `.env.simulation` holds secrets (OPENAI_API_KEY, external API keys). For local runs, the CLI reads `.env` from project root. For cloud, secrets are managed via the backend.

**Where files go:**
- **`.veris/`** (in user's repo): veris.yaml, Dockerfile.sandbox, .env.simulation — inputs to the veris CLI.
- **start.sh** (if needed): Ask user where to put it in their repo. It gets COPY'd into `/agent/` by Dockerfile.sandbox. Referenced as `entry_point: bash start.sh` in veris.yaml (relative to code_path).
- **Agent code changes**: Made to existing source files in place.
- **If code needs to be reorganized**, ask the user where they want the new structure. Never move files without asking.

## Workflow Overview

| Phase | What | Checkpoint? |
|-------|------|-------------|
| 0 | Discover & inventory | No |
| 1 | Analyze dependencies | Yes |
| 2 | Design container architecture | Yes |
| 3 | Generate veris.yaml | Yes |
| 4 | Generate Dockerfile.sandbox | Yes |
| 5 | Generate supporting files | No |
| 6 | Final review | Summary |

---

## Phase 0: Discover & Inventory
[Phase 0/6]

Tell the user: "I'm going to explore your codebase to understand what your agent does and what it depends on."

If $ARGUMENTS provides a path, use it as the root. Otherwise, use the current working directory.

### 0.1: Verify `.veris/` directory exists

Check for `.veris/veris.yaml`. If it doesn't exist, tell the user to run `veris init` first and stop.

### 0.2: Docker infrastructure

Search for and read:
- `docker-compose.yml` / `docker-compose.yaml` / `compose.yml`
- `Dockerfile` / `Dockerfile.*`
- `supervisord.conf` / `supervisord.ini`
- `Procfile`
- `vercel.json`, `serverless.yml`, `netlify.toml`
- Kubernetes manifests (`k8s/`, `kubernetes/`, `*.yaml` with `apiVersion`)

From docker-compose, extract:
- Every service name, image, ports, command, environment, volumes, depends_on
- Which service is the **agent** (the thing a user talks to) vs **infrastructure**

### 0.3: Environment and secrets

Search for and read:
- `.env.example`, `.env.sample`, `.env.template`, `.env.development`
- `config/` directory, `settings.py`, `config.py`, `config.ts`
- Any file with vault/secrets references

Collect every environment variable the agent reads.

### 0.4: Dependencies

Read the package manifest:
- Python: `requirements.txt`, `pyproject.toml`, `Pipfile`, `setup.py`, `setup.cfg`
- Node.js: `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- Go: `go.mod`
- Other: identify language and package manager

### 0.5: Source code analysis

Find and read:
- Entry point file (main.py, app.py, index.ts, server.ts, etc.)
- Config/settings module (where env vars are consumed)
- All import statements that reference external services
- Agent/LLM framework detection (OpenAI SDK, LangChain, Google ADK, Anthropic SDK, CrewAI, AutoGen, etc.)

### 0.6: Persona interface — how does a user talk to this agent?

This is critical. Veris needs to know how to simulate a user talking to the agent. Find:

- **The chat/message endpoint** — look for route definitions that accept user messages. Common patterns: `/api/chat`, `/api/v1/messages`, `/chat`, `/webhook`. Check the entry point file and router definitions.
- **Communication type** — HTTP POST (most common), WebSocket, or email-based.
- **Request format** — what fields does the endpoint expect? Look at the request body schema: which field holds the user's message, which holds a session/conversation ID, any required static fields (like `model` or `user_id`).
- **Response format** — does it return JSON with the reply in a field? Or does it stream via SSE? If SSE, what event names and data fields does it use? Read the endpoint handler to understand the response structure.

Tell the user what you found: "Your agent accepts messages at `POST /api/chat` with a JSON body like `{message: ..., session_id: ...}` and returns `{response: ...}`." Confirm this is correct — this is what veris's persona will use to talk to the agent during simulation.

### 0.7: Build inventory

Compile a complete picture:
- **Agent entry point**: what command starts the agent, what port it listens on
- **Persona interface**: endpoint URL, request/response format, communication type
- **Language/runtime**: Python version, Node version, etc.
- **Package manager**: pip, uv, poetry, npm, pnpm, yarn
- **Every external dependency**: service name, type (DB/cache/queue/API/monitoring/CDN), how the agent connects (SDK, HTTP, TCP), which env vars configure it
- **LLM provider**: which SDK, which models, how API keys are configured

Proceed directly to Phase 1.

---

## Phase 1: Analyze Dependencies
[Phase 1/6]

Tell the user: "Here's what I found. I'll go through each dependency and explain what veris can do with it."

Read [reference/service-mapping.md](reference/service-mapping.md) for the veris mock service catalog.
Read [reference/bundling-recipes.md](reference/bundling-recipes.md) for bundleable service recipes and resource costs.

### For each dependency, determine how to handle it:

**1. Veris can mock it** — The dependency matches a veris mock service (check service-mapping.md). Agent's API calls get transparently intercepted via DNS/TLS. No code changes needed. Just declare it in `veris.yaml`.

**2. Install it in the container** — The agent needs this at runtime and veris doesn't mock it (e.g., Redis, Elasticsearch, SQLite). Install it in the Dockerfile and start it before the agent. Check bundling-recipes.md for how.

**3. Not needed for simulation** — The agent's source code doesn't actually import or call this service, and the agent won't crash without it. **You must verify this by reading the code.** Don't assume — a Datadog dependency is core logic if the agent queries Datadog metrics, but skippable if it's just a monitoring sidecar the code never touches.

**4. Connect to an external endpoint** — Service is too heavy to install locally, or proprietary, or not mockable. The user provides a staging/dev URL and credentials.

**5. Needs discussion** — You're not sure, or there are multiple valid approaches. Ask the user.

### Services that need extra input from the user

**PostgreSQL** — ask the user: do you want veris to mock your database, or do you want to connect to your own Postgres instance?
- **Option A: Veris mock** — veris spins up a fresh Postgres per simulation. Ask the user which file defines their database schema (e.g., `schema.sql`, migrations directory, Prisma schema). If they're not sure, look for common patterns (`schema.sql`, `alembic/`, `migrations/`, `prisma/schema.prisma`, SQL init scripts in docker-compose volumes). This file gets COPY'd into the container and referenced as `SCHEMA_PATH` in veris.yaml so veris can initialize the database. Set `POSTGRES_PASSWORD` in `services[].config` and update `DATABASE_URL` to `postgresql://postgres:{password}@localhost:5432/SIMULATION_ID`.
- **Option B: External Postgres** — user provides their own connection string and credentials. No veris postgres service needed. Just set `DATABASE_URL` in agent environment to their external URL. Add credentials to `.env.simulation`.

**Any service with authentication** — if the agent uses specific API keys or credentials to talk to a service that veris mocks (e.g., Salesforce consumer key/secret, Slack bot token), note that veris accepts mock credentials. Pre-fill them from service-mapping.md. But if the agent validates credential formats strictly, ask the user.

### LLM providers

LLM API calls (OpenAI, Anthropic, Azure OpenAI, Google AI, etc.) are automatically intercepted by veris's LLM proxy — no config needed. Just mention this so the user knows.

### How to figure out the right approach

For each dependency:
1. Check service-mapping.md — does veris mock this? If yes, it's straightforward.
2. Read the agent's source code — find imports and function calls. Understand whether this dependency is core to what the agent does.
3. If the agent needs it but veris doesn't mock it — check bundling-recipes.md. Can it be installed in the container? What's the resource cost?
4. If it's too heavy or proprietary — external endpoint.
5. If you're not sure — ask.

### Present your findings

Walk through each dependency conversationally. For each one, explain:
- What it is
- How the agent uses it (cite specific files, imports, function calls)
- What you recommend and why

**When a decision has real tradeoffs, surface them.** For example: "Your agent uses Elasticsearch for order search. We could install it in the container (~512MB memory, adds ~500MB to image), or you could point it at a staging instance instead. What do you prefer?"

**When you plan to skip something, show your evidence.** For example: "I see Prometheus in your docker-compose, but I checked your source code and the agent never imports or calls it — it's only a metrics scraper sidecar. Safe to leave out."

**CHECKPOINT: Present your dependency analysis.**

Walk through everything you found. The user should understand what veris will mock, what gets installed in the container, what gets skipped (and why), and what needs their input. Get their confirmation before proceeding.

**Wait for user approval before proceeding.**

---

## Phase 2: Design Container Architecture
[Phase 2/6]

Tell the user: "Now I'll figure out how to restructure your agent to run inside the veris container."

Read [reference/infrastructure-patterns.md](reference/infrastructure-patterns.md) to match the agent's setup to a restructuring approach.

### 2.1: Identify the current architecture

Common patterns:
1. **Docker Compose** — single agent process + infrastructure services
2. **Supervisord / multi-process** — everything in one container already
3. **Cloud-specific** — Azure, AWS, or GCP managed services
4. **Serverless** — Vercel, Lambda, Cloud Functions, no Docker
5. **Multi-agent gateway** — orchestrator + sub-agents
6. **Hybrid** — frontend + backend workers (Next.js + Python)
7. **Custom**

### 2.2: Design the container layout

Determine:

- **What goes into `/agent/`** — which directories and files to COPY. Only runtime code, not tests/CI/docs/docker-compose.

- **How the agent starts** (entrypoint.sh does `cd $AGENT_CODE_PATH` first, so paths are relative):
  - Single process → `entry_point: app.main:app` (module path — veris defaults to uvicorn)
  - Multi-process or bundled services → `entry_point: bash start.sh` (relative to code_path)
  - Node.js → `entry_point: npx next start -p 8080` or `node dist/index.js`

- **Port**: Must NOT conflict with veris reserved ports (6100-6299, 8000-8010, 5432, 443). Use 8080, 8008, or 3000.

- **Code changes needed** — only what's necessary:
  - Connection strings: Docker service hostnames → `localhost` (read [reference/env-var-overrides.md](reference/env-var-overrides.md))
  - Graceful fallbacks for skipped services
  - Hardcoded cloud paths that won't work in the container

- **start.sh needed?** If there are bundled services (Redis, ES, etc.) or multiple agent processes, we create a `start.sh` script. This is a new file — not part of the user's existing code. It starts bundled services in order (with health checks), then starts the agent. Ask the user where to put it in their repo. Dockerfile.sandbox COPY's it into `/agent/`, and veris.yaml references it as `entry_point: bash start.sh` (relative to code_path, since entrypoint.sh cd's there first). Read [templates/start-sh.md](templates/start-sh.md) for templates. **Explain this to the user when you first mention it** — they may not know what start.sh is or why it's needed.

### 2.3: Walk the user through it

Explain:
- "Your agent currently runs as X. In the veris container, it'll run as Y."
- What files get copied and where
- What the entry point command will be
- Any code changes needed (explain each one — what file, what changes, why)
- If start.sh is needed, what it will do

**CHECKPOINT: Present architecture design.**

The user should understand and approve how their agent will be restructured before you generate any files.

**Wait for user approval before proceeding.**

---

## Phase 3: Generate veris.yaml
[Phase 3/6]

Tell the user: "I'll now generate the veris.yaml configuration based on what we've agreed."

Read [reference/veris-yaml-schema.md](reference/veris-yaml-schema.md) for the full schema reference.
Read [templates/veris-yaml.md](templates/veris-yaml.md) for annotated examples.

### 3.1: Services section

List each veris mock service the agent needs:
```yaml
services:
  - name: <veris_service_name>    # From service-mapping.md
```

Only add `dns_aliases:` if the agent uses non-default domains. Only add `config:` if needed.

### 3.2: Persona section

Determine how the agent accepts user input:
- **HTTP REST API** → `modality.type: http`, set `url` to the chat/message endpoint
- **WebSocket** → `modality.type: ws`, set `url` to the WebSocket endpoint
- **Email** → `modality.type: email`

Configure request/response field mapping based on the agent's actual API contract:
- What field contains the user message? (default: `message`)
- What field contains the session ID? (default: `session_id`, null to disable)
- Response type: json or sse?
- What field in the response has the agent's reply?

### 3.3: Agent section

```yaml
agent:
  code_path: /agent
  entry_point: <from Phase 2>
  port: <from Phase 2>
  environment:
    # Mock credentials (pre-filled)
    # Localhost overrides for bundled services
    # External URLs (use ${VAR} for secrets user must provide)
    # App config
```

**Environment variable rules:**
- Secrets user provides at runtime → `${VAR}` syntax (expanded from `.env.simulation`)
- Values known at build time → hardcode them
- Mock service credentials → use pre-filled values from [reference/env-var-overrides.md](reference/env-var-overrides.md)
- `SIMULATION_ID` is auto-injected — use the literal string where needed

### 3.4: Present and explain

Show the complete `veris.yaml` and briefly explain each section so the user understands what they're approving.

**CHECKPOINT: Present veris.yaml.**

**Wait for user approval before proceeding.**

---

## Phase 4: Generate Dockerfile.sandbox
[Phase 4/6]

Tell the user: "Now I'll generate the Dockerfile that builds your agent on top of the veris base image."

Read [templates/dockerfile-sandbox.md](templates/dockerfile-sandbox.md) for templates.

### 4.1: Build the Dockerfile

The build context is the project root (`docker build -f .veris/Dockerfile.sandbox .`), so all COPY paths are relative to the project root.

Follow this order:
1. `FROM gcr.io/veris-ai-dev/veris-gvisor:latest`
2. System packages — two sources:
   - **From the agent's original Dockerfile**: look for `apt-get install` lines and carry over build dependencies (`build-essential`, `libpq-dev`, `libmagic1`, `libxml2-dev`, etc.). These are needed for compiling Python C extensions or linking native libraries. Don't assume wheels exist for everything.
   - **For bundled services**: Redis, Elasticsearch, etc. from bundling-recipes.md.
   - Combine into a single `apt-get` layer when possible.
3. Node.js install if Node agent (not in base image)
4. Copy dependency manifest to `/agent/`, install dependencies
5. Copy agent source code to `/agent/`
6. Copy `start.sh` to `/agent/start.sh` if multi-process
7. Final `WORKDIR /app` (required by veris — this is where veris infrastructure lives)

Do NOT `COPY .veris/veris.yaml` — veris.yaml is mounted by the CLI at runtime (`-v .veris/veris.yaml:/config/veris.yaml:ro`), not baked into the image.

**Base image includes:** Python 3.12, uv, pip, PostgreSQL 15 client.
**Base image does NOT include:** Node.js, Go, Java, Ruby.

### 4.2: Present and explain

Show the complete Dockerfile. Explain any non-obvious choices (why certain files are copied, why certain packages are installed).

**CHECKPOINT: Present Dockerfile.sandbox.**

**Wait for user approval before proceeding.**

---

## Phase 5: Generate Supporting Files
[Phase 5/6]

### 5.1: .env.simulation

Read [templates/env-simulation.md](templates/env-simulation.md).

Generate `.veris/.env.simulation` with all env vars the agent needs, grouped clearly:
1. **LLM API keys** — always needed, user must fill
2. **Mock service credentials** — pre-filled with veris defaults
3. **External service credentials** — user must fill
4. **App configuration** — sensible defaults

Tell the user which values they need to fill in and which are already set.

### 5.2: start.sh (only if needed)

Read [templates/start-sh.md](templates/start-sh.md).

Only generate if there are bundled services or multiple agent processes. Ask the user where to put it in their repo. Dockerfile.sandbox must COPY it to `/agent/start.sh`. veris.yaml references it as `entry_point: bash start.sh` (relative — entrypoint.sh cd's to code_path first).

Rules:
- Start bundled services first, with health check waits
- Background all processes except the last one
- Last command MUST use `exec`
- Use `${PORT:-8080}` for the agent port

### 5.3: Code changes

Apply the minimal code changes from Phase 2. **For each change:**
1. Tell the user what you're changing and why
2. Show the before/after
3. Make the change

Common changes:
- Docker service hostnames → `localhost` in connection strings
- Graceful error handling for optional services
- Env var name adjustments
- Remove cloud-specific init that won't work in the container

**Keep changes minimal.** The goal is making the agent run in the container, not refactoring it. If a change is risky or unclear, skip it and note it as a limitation.

Proceed to Phase 6.

---

## Phase 6: Final Review
[Phase 6/6]

### 6.1: Summarize everything

List every file created or modified:

| File | Action | Description |
|------|--------|-------------|
| `.veris/veris.yaml` | Created/Updated | Services, persona, agent config |
| `.veris/Dockerfile.sandbox` | Created/Updated | Container build instructions |
| `.veris/.env.simulation` | Created/Updated | Runtime environment variables |
| `{start.sh path}` | Created | Multi-process startup (if needed) — COPY'd to `/agent/` |
| `{path}` | Modified | {what changed and why} |

### 6.2: Completeness check

Walk through the dependency list one more time and confirm everything is accounted for:
- Mocked services → in veris.yaml
- Bundled services → installed in Dockerfile, started in start.sh
- Skipped services → documented why
- External services → placeholder in .env.simulation
- Discussed items → resolved

### 6.3: Known limitations

Be upfront about anything that might not work perfectly:
- External services that need real credentials
- Cloud-specific features that don't translate
- Background workers or cron jobs that may behave differently
- Code changes that were too risky to make

### 6.4: Next steps

Tell the user what to do next:
1. **Fill secrets** — create a `.env` file in the project root with `OPENAI_API_KEY` and any other secrets
2. **Test build** — `docker build -f .veris/Dockerfile.sandbox -t agent-test .` (verifies the Dockerfile works)
3. **Create scenarios** — add simulation scenario YAML files in `scenarios/` directory
4. **Run locally** — `veris run local` (builds image, mounts veris.yaml + scenarios, runs simulation)
5. **Deploy** — `veris env push` (builds + pushes image for cloud runs)

---

## Guidelines

### Transparency and User Control
- **Explain before acting.** Tell the user what you're about to do and why before each step.
- **Surface decisions.** When there's a real choice (bundle vs external, skip vs keep, how to restructure), present the options with tradeoffs and let the user decide.
- **Show evidence.** When you determine something can be skipped, cite the specific files you checked. When you recommend bundling, mention the resource cost.
- **Never go silent.** Don't process a bunch of dependencies quietly and dump a table. Walk through them, explain as you go.

### Dependency Analysis Integrity
- **Always read the source code.** Don't classify based on service name alone. A monitoring service might be core agent logic.
- **Context matters.** The same service (e.g., Splunk) is core logic in an incident response bot but infrastructure in an e-commerce bot.
- **When in doubt, ask.** It's better to ask the user than to silently make the wrong call.

### Code Changes
- **Minimal and targeted.** Only change what's necessary for the container.
- **No refactoring.** Don't improve code style, add types, or restructure modules.
- **Prefer env var overrides over code changes.** If a connection string comes from an env var, just set the var.
- **Explain every change.** Before modifying a file, say what and why.

### Self-Containment
- All veris knowledge is in the reference/ and templates/ files within this skill.
- NEVER reference files outside this skill's directory.
- When you need veris-specific information, read the appropriate reference doc.

### Troubleshooting
- If integration issues come up, read [phases/troubleshooting.md](phases/troubleshooting.md) for common problems and fixes.

Confirm each phase is complete before moving to the next.
