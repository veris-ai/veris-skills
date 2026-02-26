# .env.simulation Template

## Structure
Group variables by category. Use comments to explain each.
Values with REPLACE_ME must be filled by the user.
Mock credentials can be committed to version control (they're fake).

## Template

```bash
# ─── LLM Provider Keys (required, intercepted by veris LLM proxy) ───
OPENAI_API_KEY=sk-proj-REPLACE_ME
# ANTHROPIC_API_KEY=sk-ant-REPLACE_ME    # Uncomment if agent uses Anthropic

# ─── Veris Mock Credentials (pre-filled, no changes needed) ───
# These are fake credentials that veris mock services accept
# SALESFORCE_CONSUMER_KEY=mock_consumer_key_12345
# SALESFORCE_CONSUMER_SECRET=mock_consumer_secret_67890
# SLACK_BOT_TOKEN=xoxb-mock-token-for-veris-simulation

# ─── External Service Keys (user must provide if applicable) ───
# Uncomment and fill for services using external endpoints
# PINECONE_API_KEY=REPLACE_ME
# KAFKA_BROKER_URL=REPLACE_ME
# COSMOS_DB_ENDPOINT=REPLACE_ME

# ─── Application Config (typically no changes needed) ───
# APP_ENV=development
# LOG_LEVEL=INFO
```

## Rules
- `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY`) is ALWAYS required -- veris LLM proxy needs a real key.
- `${VAR}` references in veris.yaml point to these values at runtime.
- Mock credentials are safe to commit (they only work with veris mocks).
- Real API keys should be in `.gitignore` or passed via CLI: `veris run local --env OPENAI_API_KEY=sk-...`
- `SIMULATION_ID` is injected automatically -- never set it here.
