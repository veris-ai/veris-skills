# veris-skills

This repository is retired. It held skills for coding agents that used the Veris simulation platform, which retired on 2026-10-15 and is replaced by [Veris Bench](https://benchmark.veris.ai).

The skills were removed rather than left in place, so that `npx skills add veris-ai/veris-skills/...` fails clearly instead of installing instructions for a platform that no longer answers.

| Former skill | Where to go now |
| --- | --- |
| `agent-integration` | Removed. It installed the retired simulation CLI and pushed agents to the retired platform. Testing your code against Veris twins is the `veris` plugin in [veris-ai/plugins](https://github.com/veris-ai/plugins). |
| `integration-testing` | Removed earlier. Same plugin: `setting-up-veris`, `discovering-vendor-behavior`, `integration-testing`. |

If you still have `agent-integration` installed locally, remove it with the same CLI you installed it with (for example `npx skills remove agent-integration`), or delete it from your agent's skills directory.

Questions: hello@veris.ai. Details: https://docs.veris.ai/deprecation

## License

Apache 2.0
