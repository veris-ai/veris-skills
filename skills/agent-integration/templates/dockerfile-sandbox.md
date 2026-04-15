# `Dockerfile.sandbox` Templates

Reference templates for building agent containers on the current Veris base image.

## Current base-image assumptions

Use the current build-arg pattern:

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}
```

The current base image already includes:
- Python 3.12
- `uv`
- Node.js
- nginx
- PostgreSQL
- Veris infrastructure and mock services

Do not re-install Node.js unless the repo specifically requires a different version.

## Template 1: Python agent with `uv`

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

COPY pyproject.toml uv.lock /agent/
WORKDIR /agent
RUN uv sync --frozen --no-dev

COPY app /agent/app

WORKDIR /app
```

## Template 2: Python agent with `pip`

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY app /agent/app

WORKDIR /app
```

## Template 3: Node.js agent

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

COPY package.json package-lock.json /agent/
WORKDIR /agent
RUN npm ci --omit=dev

COPY src /agent/src
COPY public /agent/public

WORKDIR /app
```

If the app needs a build step:

```dockerfile
RUN npm run build
```

## Template 4: Function-channel Python agent

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

COPY pyproject.toml uv.lock /agent/
WORKDIR /agent
RUN uv sync --frozen --no-dev

COPY app /agent/app

WORKDIR /app
```

A function-channel integration usually needs the same dependency install as any other Python repo. The difference is in `veris.yaml`: no `entry_point` and no `port`.

## Template 5: Bundled Redis + `start.sh`

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

RUN apt-get update && \
    apt-get install -y redis-server && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY app /agent/app
COPY start.sh /agent/start.sh
RUN chmod +x /agent/start.sh

WORKDIR /app
```

## Template 6: Multi-process gateway

```dockerfile
ARG GVISOR_BASE
FROM ${GVISOR_BASE}

COPY gateway/requirements.txt /tmp/gateway-requirements.txt
COPY worker/requirements.txt /tmp/worker-requirements.txt
RUN pip install --no-cache-dir \
    -r /tmp/gateway-requirements.txt \
    -r /tmp/worker-requirements.txt

COPY gateway /agent/gateway
COPY worker /agent/worker
COPY start.sh /agent/start.sh
RUN chmod +x /agent/start.sh

WORKDIR /app
```

## Rules

- Build context is the repo root
- Copy dependency manifests before source code
- Copy only what the agent actually needs
- End with `WORKDIR /app`
- Do not copy `.veris/veris.yaml` into the image
- Do not assume `.veris/` is the build context
- If you add `start.sh` or a wrapper file, copy it into `/agent`
- If the repo needs schemas, migrations, prompt assets, or static files at runtime, copy those explicitly
