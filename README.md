# veris-skills

Skills for coding agents that use the [Veris AI](https://veris.ai) simulation platform.

## Skills

| Skill | What it does |
| --- | --- |
| [`agent-integration`](skills/agent-integration) | Integrate a raw customer agent repo with Veris end-to-end: `.veris/veris.yaml`, `Dockerfile.sandbox`, env vars, and `veris env push`. |
| [`discovering-vendor-behavior`](skills/discovering-vendor-behavior) | Find out what a dependency actually does before designing around it: read the service's own contract notes, then probe a sandbox. For the design phase, before the code exists. |
| [`integration-testing`](skills/integration-testing) | Run a repo's integration tests against a Veris dependency sandbox: veris-proxy runs the tests in a container beside a kernel-level interception proxy (any runtime, image unmodified), and a per-service receipt proves the sandbox actually received the traffic. |

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
