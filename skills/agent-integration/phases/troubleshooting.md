# Troubleshooting

Common integration issues organized by symptom.

## `veris-cli` bootstrap problems

### `veris` command not found

Install the CLI first:

```bash
uv tool install veris-cli
```

Fallback:

```bash
pip install veris-cli
```

### `veris env push` says no environment is configured

The repo is missing `.veris/config.yaml` with an environment binding. Run:

```bash
veris env create --name "<env-name>"
```

### Auth problems

If the CLI is installed but backend calls fail, the user likely needs:

```bash
veris login
```

Or API-key login for headless contexts.

## Agent fails to start

Common causes:

1. Missing required env var
2. Wrong `entry_point`
3. Wrong `code_path`
4. Missing dependency install in `Dockerfile.sandbox`
5. Bundled service not started before the agent

Check the agent logs first. The startup error usually points directly at the missing dependency or bad command.

## Actor cannot reach the agent

For HTTP / WS / email integrations:

1. `actor.channels[].url` points at the wrong port or path
2. `agent.port` does not match the server’s listen port
3. The agent binds only to `127.0.0.1` instead of `0.0.0.0`
4. The server takes too long to become healthy

For function integrations:

1. `callable` import path is wrong
2. Wrapper file was not copied into `/agent`
3. The callable returns a shape the driver cannot serialize cleanly

## Agent runs but cannot reach mocked services

Common causes:

1. Missing or wrong `services:` entry
2. Wrong `dns_aliases`
3. Wrong env-var override, especially old docker-compose hostnames that should be `localhost`
4. Missing mock credentials

Check `reference/service-mapping.md` and `reference/env-var-overrides.md`.

## Database connection fails

Common causes:

1. Old docker hostname (`postgres`, `db`) instead of `localhost`
2. Password mismatch between `services[].config.POSTGRES_PASSWORD` and `DATABASE_URL`
3. Schema file copied to the wrong path
4. Wrong database name instead of `SIMULATION_ID`

## Bundled service fails

Common causes:

1. Service package not installed in `Dockerfile.sandbox`
2. Service not started or not health-checked in `start.sh`
3. Port conflict
4. Service is too heavy and should have stayed external

## Build fails

Common causes:

1. Wrong build context
2. Bad `COPY` path
3. Dependency manifest copied incorrectly
4. Missing system package
5. `WORKDIR /app` omitted at the end

The correct local smoke-test command is:

```bash
docker build -f .veris/Dockerfile.sandbox .
```

from the repo root.

## Build fails due to source-tree compile errors

If `pip install -e .` or `pip install .` fails because the repo's own source files have syntax errors, broken imports, or missing type stubs:

1. Check whether the repo is a **platform-hosted agent** (config-only, framework-as-runtime). If so, do not install the repo as an editable package.
2. Instead, install the framework and its dependencies from published packages:
   ```dockerfile
   RUN pip install crewai langchain-openai  # framework + plugins
   ```
3. COPY only the config/prompt/tool files the framework needs — not the entire source tree as an installable package.
4. If the repo does contain real application code that must be installed, try `pip install --no-build-isolation .` or fix the specific compile errors. Common causes: missing `build-system` in `pyproject.toml`, Cython extensions without a C compiler, or Python version mismatch.

## `veris env create` scaffold produces broken config

If `veris env create` succeeds but reports a non-fatal config upload error (typically a 422 on the `services` list), the scaffolded `veris.yaml` has fields the backend does not accept.

This is expected — the scaffolded config is a placeholder with commented-out examples. Fix it:

1. Regenerate `.veris/veris.yaml` using the current preferred shape from `reference/veris-yaml-schema.md`
2. Ensure `services:` is a valid YAML list (not commented-out blocks that parse as an empty mapping)
3. Re-push with `veris env push`

## Base image runtime version too old for agent

If the agent requires a newer Python or Node.js than the base image provides:

1. Check the agent's dependency manifests for explicit version constraints (`python_requires >= "3.13"`, `engines.node >= "20"`)
2. Add a runtime version override to `Dockerfile.sandbox` — see the "Runtime version override" section in `templates/dockerfile-sandbox.md`
3. For Python, install the newer version alongside the base and create a dedicated virtualenv
4. For Node.js, overlay the newer binary and it will replace the base version on PATH

## Runtime env vars are missing

Common causes:

1. Secret was never set with `veris env vars set`
2. The value belongs in `agent.environment` but is missing there
3. The user expected `.env.simulation`, which is no longer the preferred flow
4. Secret was set via shell interpolation (`veris env vars set KEY="$VAR" --secret`) but `$VAR` was empty or unset — the CLI saved an empty string with no error

Fix:
- use `veris env vars set` for secrets and per-env overrides
- use `agent.environment` for stable non-secret defaults
- optionally mirror local values in a root `.env` for local-only smoke tests
- if a secret might have been set empty, verify with `printenv VAR` before setting, or re-set it with a literal value
