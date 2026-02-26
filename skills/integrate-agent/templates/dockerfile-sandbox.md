# Dockerfile.sandbox Templates

Reference templates for building agent containers on the veris base image.

---

## Template 1: Python Agent (pip / requirements.txt)

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Copy dependency manifest first (Docker layer caching)
COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

# Copy agent source code
COPY app/ /agent/app/
# COPY config/ /agent/config/         # Uncomment if agent has config files
# COPY schemas/ /agent/schemas/       # Uncomment if agent has SQL schemas

# IMPORTANT: veris requires this final WORKDIR
WORKDIR /app
```

---

## Template 2: Python Agent (uv / pyproject.toml)

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

COPY pyproject.toml uv.lock /agent/
WORKDIR /agent
RUN uv sync --frozen --no-dev

COPY app/ /agent/app/

WORKDIR /app
```

---

## Template 3: Python Agent (Poetry)

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

RUN pip install poetry
COPY pyproject.toml poetry.lock /agent/
WORKDIR /agent
RUN poetry config virtualenvs.create false && poetry install --no-dev --no-interaction

COPY app/ /agent/app/

WORKDIR /app
```

---

## Template 4: Node.js Agent (npm)

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install Node.js (not in base image)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json /agent/
WORKDIR /agent
RUN npm ci --production

COPY src/ /agent/src/
COPY public/ /agent/public/
# For Next.js: build at image time
# RUN npm run build

WORKDIR /app
```

---

## Template 5: With Bundled Redis

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install bundled services
RUN apt-get update && \
    apt-get install -y redis-server && \
    rm -rf /var/lib/apt/lists/*

# Install agent dependencies
COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /agent/app/
COPY start.sh /agent/start.sh
RUN chmod +x /agent/start.sh

WORKDIR /app
```

---

## Template 6: With Bundled Elasticsearch

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install Elasticsearch (single-node)
RUN curl -fsSL https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.12.0-linux-x86_64.tar.gz \
    | tar xz -C /opt/ && \
    mv /opt/elasticsearch-8.12.0 /opt/elasticsearch && \
    /opt/elasticsearch/bin/elasticsearch-plugin remove x-pack-ml 2>/dev/null || true && \
    useradd -r elasticsearch && \
    chown -R elasticsearch:elasticsearch /opt/elasticsearch

COPY requirements.txt /agent/
WORKDIR /agent
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /agent/app/
COPY start.sh /agent/start.sh
RUN chmod +x /agent/start.sh

WORKDIR /app
```

---

## Template 7: Multi-service Agent (gateway + sub-agents)

```dockerfile
FROM gcr.io/veris-ai-dev/veris-gvisor:latest

# Install all Python dependencies from all sub-agents
COPY gateway/requirements.txt /tmp/gateway-req.txt
COPY flight-agent/requirements.txt /tmp/flight-req.txt
COPY hotel-agent/requirements.txt /tmp/hotel-req.txt
RUN pip install --no-cache-dir \
    -r /tmp/gateway-req.txt \
    -r /tmp/flight-req.txt \
    -r /tmp/hotel-req.txt

# Copy all agent code
COPY gateway/ /agent/gateway/
COPY flight-agent/ /agent/flight-agent/
COPY hotel-agent/ /agent/hotel-agent/
COPY shared/ /agent/shared/

COPY start.sh /agent/start.sh
RUN chmod +x /agent/start.sh

WORKDIR /app
```

---

## Important Notes

- **ALWAYS end with `WORKDIR /app`** -- veris infrastructure runs from /app.
- **Do NOT copy veris.yaml** -- it's mounted at runtime by the CLI (`-v .veris/veris.yaml:/config/veris.yaml:ro`), not baked into the image.
- **Agent code goes to `/agent/`** -- set `agent.code_path: /agent` in veris.yaml to match.
- **Build context is the project root** -- the CLI runs `docker build -f .veris/Dockerfile.sandbox .` from the project root.
- **COPY paths are relative to build context** (project root), not to the Dockerfile location.
- **Base image includes:** Python 3.12, uv, pip, apt-get, curl, openssl, nginx, postgres client libs.
- **Base image does NOT include:** Node.js, Go, Java, Ruby -- install these in Dockerfile if needed.
- **Copy dependency manifests before source code** for Docker layer caching -- source changes won't re-install deps.
- **Use `--no-cache-dir` with pip** to reduce image size.
- **For Next.js:** set `NEXT_PUBLIC_*` env vars before `npm run build` (they are build-time vars baked into the bundle).
- **If start.sh exists, always `chmod +x`** -- the file won't be executable otherwise.
- **If the agent needs Prisma:** add `RUN npx prisma generate` after npm install.
