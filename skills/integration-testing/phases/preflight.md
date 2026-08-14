# Preflight — every run, about a second

One command, one exit code, before every run:

```bash
veris-proxy preflight --environment "$VERIS_ENVIRONMENT_ID" --image <the image .veris/setup.json names>
```

- **exit 0** — go to [running.md](running.md).
- **exit 2** — a precondition is missing. Fix exactly what it named, or tell
  the user and stop. Nothing else.

It costs about a second, so run it every time rather than trusting that
[setup](setup.md) still holds. The failure this catches is not "setup was
never done" — it is *setup silently stopped holding*: a credential that was
exported in another shell, a docker daemon that is not up today, an image that
was never rebuilt after the runtime changed.

Preflight also prints one line that is not a precondition: whether the
environment has a **promoted world**. If it does not, every sandbox boots the
stock profile and the accounts, connections and fixtures the tests need are
rebuilt on every run — including this one. See [setup.md](setup.md) §5 and
[running.md](running.md) §2 for the two ways to keep a world once.

## Failing closed is the point

When preflight fails, the work stops until the named thing is fixed. It is
worth being explicit about what "stops" rules out, because the alternative is
not hypothetical — it is what eight of eight measured agents did when the
credential was missing, every one of them producing a green whose code path
was not the code path that ships:

- **No base URL pointed at a sandbox.** Not in application code, not in
  config, not in an environment variable, not "just for the test."
- **No hand-authored `--config` file**, and no `--sandbox` of your own, in
  place of `--environment`.
- **No tunnel, proxy, or interception of your own** — ngrok, cloudflared, a
  local MITM, a `NODE_OPTIONS` preload, a patched CA bundle.
- **No host tier.** `veris-proxy run` without `--image` covers only libraries
  that honour proxy variables, and its gaps are silent.

Each of these turns a missing precondition into a passing suite, which is
strictly worse than a red one. If the precondition cannot be met — no docker
on the machine, no API key the user can produce — say so and stop.

## What each failure means

| Preflight says | What to do |
|---|---|
| `credential` | Ask the user for `VERIS_API_KEY`; it arrives out of band and never goes into the repo. If the Veris MCP server is registered, the same key is its `X-API-Key` header value — export that. |
| `control plane` unreachable | Check `VERIS_API_BASE` and the network. Do not proceed against a control plane you cannot read. |
| `control plane` refused the key | The key is wrong, revoked, or for another deployment. Ask the user; do not try another route in. |
| `environment` | Ask the user which environment to test against, or export `VERIS_ENVIRONMENT_ID`. A run needs one — it is what deploys the sandbox. |
| `docker` | Start the daemon. If the machine has none, stop and tell the user: this skill does not run without the container tier. |
| `test image` | Build it: `docker build -f Dockerfile.veris -t <tag> .`. If the Dockerfile no longer matches the repo, that is a [setup](setup.md) §3 change, not a run-time workaround. |

## If the binary predates `preflight`

`veris-proxy version` older than the subcommand: assert the same things by
hand, in this order, and stop at the first failure exactly as above.

1. `VERIS_API_KEY` is set in *this* shell (not only in an MCP config file).
2. `veris-proxy version` runs.
3. `docker version` reaches a daemon.
4. `VERIS_ENVIRONMENT_ID` (or a user-supplied id) names an environment, and
   `get_environment` reads it.
5. `docker image inspect <tag>` finds the image `.veris/setup.json` names.

The checks are cheap; the discipline is the part that matters. A hand-run
check that fails means the same thing the command's exit 2 means.
