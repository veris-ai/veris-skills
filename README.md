# veris-skills

A skill for coding agents that integrates a raw customer agent repo with the [Veris AI](https://veris.ai) simulation platform end-to-end.

Supported agents: **Claude Code**, **OpenAI Codex CLI**, and **Cursor**.

## What it does

`/agent-integration` takes a repo from "plain customer agent source" to "Veris-ready and pushable":

- Installs or verifies `veris-cli`, logs in, and creates or reuses a Veris environment
- Analyzes the repo to pick the right integration channel (HTTP, WebSocket, email, or function)
- Generates `.veris/veris.yaml`, `.veris/Dockerfile.sandbox`, and supporting files
- Configures runtime env vars and can finish with `veris env push`
- Refreshes stale `.veris/` integrations to current conventions

## Install

This repo exposes one branch per supported coding agent. Point your agent at its branch so it gets native auto-reload on skill updates.

| Agent            | Branch   | Install location                     |
| ---------------- | -------- | ------------------------------------ |
| Claude Code      | `claude` | `~/.claude/skills/agent-integration` |
| OpenAI Codex CLI | `codex`  | `~/.codex/skills/agent-integration`  |
| Cursor           | `cursor` | `~/.cursor/skills/agent-integration` |

### Claude Code

```bash
git clone -b claude https://github.com/veris-ai/veris-skills ~/.claude/skills/agent-integration
```

### OpenAI Codex CLI

```bash
git clone -b codex https://github.com/veris-ai/veris-skills ~/.codex/skills/agent-integration
```

### Cursor

```bash
git clone -b cursor https://github.com/veris-ai/veris-skills ~/.cursor/skills/agent-integration
```

To update later, `git pull` from the skill directory.

## Use

From inside any agent repo:

```
/agent-integration
```

Or point at a different repo:

```
/agent-integration path/to/agent/repo
```

## Repository layout

`main` is the canonical source of truth. Agent-specific branches (`claude`, `codex`, `cursor`) track `main` and exist so each harness can point at its own stable ref for auto-reload. Skill content is identical across branches today; the branches give us room to diverge on install metadata or agent-specific wording without fragmenting into separate repos.

## License

Apache 2.0
