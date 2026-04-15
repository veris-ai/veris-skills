# start.sh Templates

## Template 1: Bundled services + single agent process

```bash
#!/bin/bash
set -e

echo "Starting bundled services..."

# Start Redis
redis-server --daemonize yes --maxmemory 128mb --maxmemory-policy allkeys-lru
until redis-cli ping 2>/dev/null | grep -q PONG; do sleep 0.5; done
echo "Redis ready"

# Start agent (foreground — must be last, must use exec)
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
```

## Template 2: Multi-agent gateway + sub-agents

```bash
#!/bin/bash
set -e

echo "Starting sub-agents..."

# Start sub-agents in background
(cd /agent/flight-agent && uvicorn main:app --host 0.0.0.0 --port 8081) &
(cd /agent/hotel-agent && uvicorn main:app --host 0.0.0.0 --port 8082) &

# Wait for sub-agents to be ready
echo "Waiting for sub-agents..."
for port in 8081 8082; do
  for i in $(seq 1 30); do
    if curl -sf http://localhost:$port/health >/dev/null 2>&1; then
      echo "  Port $port ready"
      break
    fi
    sleep 1
  done
done

# Start gateway (foreground — must be last, must use exec)
exec bash -lc 'cd /agent/gateway && uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}'
```

## Template 3: FastAPI + background workers

```bash
#!/bin/bash
set -e

echo "Starting background workers..."

# Start Celery worker (or other background processor)
python -m app.workers.celery_worker \
  --concurrency 2 \
  --loglevel info &

# Start webhook listener (if needed)
python -m app.webhook_listener &

# Start main API server (foreground — must be last, must use exec)
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
```

## Rules

- The LAST command must use `exec` (replaces shell process, receives signals correctly).
- Background processes use `&`.
- Always wait for bundled services to be healthy before starting the agent.
- `set -e` at the top: exit immediately on any error.
- Use `${PORT:-8080}` to respect veris port injection.
- Never use supervisord in sandbox -- start.sh is simpler and sufficient.
- Veris already starts `start.sh` from `agent.code_path`, so do not add a redundant `cd /agent` at the top.
- If you must launch work from a subdirectory, use an explicit absolute-path subshell like `(cd /agent/worker && python main.py) &` or `exec bash -lc 'cd /agent/gateway && ...'`.
- If a background process fails, the container continues -- that's intentional for simulation.
