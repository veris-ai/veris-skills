# veris-skills

A skill for coding agents that integrates a raw customer agent repo with the [Veris AI](https://veris.ai) simulation platform end-to-end.

Works with **Claude Code**, **OpenAI Codex CLI**, and **Cursor**.

## What it does

`/agent-integration` takes a repo from "plain customer agent source" to "Veris-ready and pushable":

- Installs or verifies `veris-cli`, logs in, and creates or reuses a Veris environment
- Analyzes the repo to pick the right integration channel (HTTP, WebSocket, email, or function)
- Generates `.veris/veris.yaml`, `.veris/Dockerfile.sandbox`, and supporting files
- Configures runtime env vars and can finish with `veris env push`
- Refreshes stale `.veris/` integrations to current conventions

## Install

### One-liner (autodetects your coding agent)

```bash
curl -sSL https://raw.githubusercontent.com/veris-ai/veris-skills/main/install.sh | bash
```

Force a specific target (or install for all):

```bash
curl -sSL https://raw.githubusercontent.com/veris-ai/veris-skills/main/install.sh | bash -s -- --target claude
curl -sSL https://raw.githubusercontent.com/veris-ai/veris-skills/main/install.sh | bash -s -- --target all
```

### Manual (one `git clone` per harness)

```bash
# Claude Code
git clone https://github.com/veris-ai/veris-skills ~/.claude/skills/agent-integration

# OpenAI Codex CLI
git clone https://github.com/veris-ai/veris-skills ~/.codex/skills/agent-integration

# Cursor
git clone https://github.com/veris-ai/veris-skills ~/.cursor/skills/agent-integration
```

## Use

From inside any agent repo:

```
/agent-integration
```

Or point at a different repo:

```
/agent-integration path/to/agent/repo
```

## License

Apache 2.0
