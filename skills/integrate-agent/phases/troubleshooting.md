# Troubleshooting

Common integration issues organized by symptom, with causes and fixes.

---

## Agent fails to start

**Symptom:** Container starts but the agent process crashes immediately.

**Common causes:**

1. **Missing environment variable** -- the agent reads a required env var that is not defined in veris.yaml. Check the agent's config or settings module for required vars.
2. **Cannot connect to service** -- the agent tries to connect to a service at startup (e.g., Redis, database). Either the service is not bundled/started, or the connection URL is wrong.
3. **Wrong entry point** -- the entry_point command does not match how the agent actually starts. Check the original Dockerfile CMD/ENTRYPOINT for the correct command.
4. **Module not found** -- agent code was not copied to the right directory. Verify that COPY paths in Dockerfile.sandbox match code_path in veris.yaml.
5. **Node.js not installed** -- Node agent but the base image only has Python. Add the Node.js install step to Dockerfile.sandbox.

**Fix:** Check container logs with `docker logs <container>`. The error message usually tells you exactly what went wrong.

---

## Agent starts but API calls fail

**Symptom:** Agent runs but cannot reach mocked services (Salesforce, Jira, etc.).

**Common causes:**

1. **DNS not intercepted** -- the service is not listed in the veris.yaml services section, or dns_aliases are missing for the domain the agent calls.
2. **TLS trust issue** -- the agent does not trust the veris CA cert. For Python: check SSL_CERT_FILE. For Node: check NODE_EXTRA_CA_CERTS. Both are auto-set by veris at container startup.
3. **Wrong API endpoint** -- the agent calls a different domain than what veris intercepts. Check service-mapping.md for the correct DNS aliases.
4. **Auth failure** -- the agent expects specific credentials. Use mock credentials from env-var-overrides.md.

---

## Bundled service won't start

**Symptom:** Redis, Elasticsearch, or RabbitMQ does not start in start.sh.

**Common causes:**

1. **Not installed** -- the apt-get install step was not added to Dockerfile.sandbox.
2. **Permission error** -- Elasticsearch needs a non-root user. Redis needs a writable /tmp directory.
3. **Port conflict** -- the bundled service port conflicts with a veris mock service. Check port assignments in veris.yaml.

**Fix:** Add explicit error checking in start.sh:

```bash
redis-server --daemonize yes || { echo "Redis failed to start"; exit 1; }
```

---

## Database connection fails

**Symptom:** Agent cannot connect to PostgreSQL.

**Common causes:**

1. **Wrong connection string** -- the agent must use `localhost:5432`, not a docker-compose hostname like `db` or `postgres`.
2. **Missing SIMULATION_ID** -- the database name should be SIMULATION_ID (created per simulation run).
3. **Schema not loaded** -- if using SCHEMA_PATH config, verify the SQL file is copied into the container at the path specified.
4. **Password mismatch** -- POSTGRES_PASSWORD in services[].config must match the password in the agent's DATABASE_URL.

---

## Persona can't reach agent

**Symptom:** Simulation starts but the persona gets a connection refused error.

**Common causes:**

1. **Wrong port** -- persona.modality.url port does not match agent.port in veris.yaml.
2. **Agent not listening on 0.0.0.0** -- the agent must bind to all interfaces, not just 127.0.0.1 or localhost.
3. **Agent not ready** -- the agent takes too long to start. The veris health gate waits up to 120 seconds before timing out.
4. **Wrong endpoint path** -- persona.modality.url path does not match the agent's actual chat endpoint.

---

## Build fails

**Symptom:** `docker build -f .veris/Dockerfile.sandbox .` fails.

**Common causes:**

1. **Build context wrong** -- the command must be run from the project root, not from inside .veris/.
2. **COPY path does not exist** -- a file referenced in a COPY instruction does not exist in the build context.
3. **Dependency install fails** -- pip or npm install error. Check that lock files are up to date and consistent with the manifest.

---

## Environment variable not expanded

**Symptom:** Agent receives the literal string `${OPENAI_API_KEY}` instead of the actual key value.

**Cause:** The variable is not present in .env.simulation or was not passed to the container at runtime.

**Fix:** For `veris run local`, pass the variable explicitly via `--env OPENAI_API_KEY=sk-...` or ensure it is defined in .env.simulation.
