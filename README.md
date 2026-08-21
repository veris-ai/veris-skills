# veris-skills

Skills for coding agents that use the [Veris AI](https://veris.ai) simulation platform.

## Skills

| Skill | What it does |
| --- | --- |
| [`agent-integration`](skills/agent-integration) | Integrate a raw customer agent repo with Veris end-to-end: `.veris/veris.yaml`, `Dockerfile.sandbox`, env vars, and `veris env push`. |
| [`setting-up-veris`](skills/setting-up-veris) | Wire a repository to a Veris dependency sandbox once: a preflight script, a test image, the exact run command in `.veris/run.sh`, and a smoke run whose receipt proves the wiring. |
| [`discovering-vendor-behavior`](skills/discovering-vendor-behavior) | Measure what a dependency actually does before designing around it: the service's own contract notes, the schema, probes, the failure the task describes made to happen, and a ledger of what was measured. For the design phase, before the code exists. |
| [`integration-testing`](skills/integration-testing) | Exercise a change against a Veris dependency sandbox through veris-proxy with the code unmodified: arrange, arm a fault, drive the boundary the task names, read back what the twin recorded, and flip red to green — with a receipt proving the sandbox received the traffic. |

The three dependency-sandbox skills are one arc — set up once, discover before
designing, test the change — and hand off to each other by name.

More coming soon (scenario creation, running simulations, …).

## Install

Works across Claude Code, OpenAI Codex CLI, Cursor, and 40+ other coding agents via the [`skills`](https://github.com/vercel-labs/skills) CLI. It autodetects which agents you have installed and places files in the right location for each.

Browse and install skills from this repo:

```bash
npx skills add veris-ai/veris-skills
```

Install a specific skill directly:

```bash
npx skills add veris-ai/veris-skills/skills/agent-integration
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
