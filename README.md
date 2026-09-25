# veris-skills

Skills for coding agents that use the [Veris AI](https://veris.ai) simulation platform.

## Skills

| Skill | What it does |
| --- | --- |
| `agent-integration` | Retired 2026-09-28. It targeted the Veris simulation platform, which shuts down 2026-10-31. Twins setup is the `veris` plugin in [veris-ai/plugins](https://github.com/veris-ai/plugins). |
| `integration-testing` | Retired. Testing against a Veris environment is the `veris-sim` plugin in [veris-ai/plugins](https://github.com/veris-ai/plugins): `setting-up-veris`, `discovering-vendor-behavior`, `integration-testing`. |

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
