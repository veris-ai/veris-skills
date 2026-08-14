# Proposal: split setup from preflight, resolve the guide conflict, make the path enforceable

Draft, 2026-08-14. Evidence: eight benchmark treatment arms across two runs
(traces in `veris-benchmark-harness`, see its `docs/GUIDANCE-CONFLICT.md` and
`docs/TOKEN-ECONOMICS.md`). Nothing here is committed to the skill yet.

## The problem in one sentence

An agent that registers the Veris MCP server and reads `get_testing_guide` is
told to **replace base URLs**, which `SKILL.md` forbids as producing a
"fiction" green — and eight of eight measured agents did exactly that, none
ever invoked `veris-proxy`, and none ever promoted a world.

## 1. Resolve the conflict: one owner per concern

The MCP guide and the skill currently both describe how to connect. They
should not.

| concern | owner | why |
|---|---|---|
| **transport** — how the code's traffic reaches the sandbox | **the skill** (proxy, receipt, `--require-service`, `--strict`) | it is the thing that must not be improvised; it carries the interception guarantee |
| **service state** — data, schema, faults, virtual clock, callbacks, redaction, Postgres | **the MCP guide** (its §2–§8, which are excellent and unique) | state manipulation is per-service and belongs next to the service |

Concretely, the guide's opening paragraph and §1 step 4 should be replaced by
a pointer: *"Transport is not configured by hand. Use the
`integration-testing` skill; if it is not installed, run
`veris-proxy setup --environment <id>` and follow its output. Do not set
vendor base URLs in application code or config."* Everything from §2 onward
stays as-is.

This also removes the guide's implicit claim that config rewiring is
supported, which is what put harness routing into a customer-shaped diff in
one measured run.

## 2. Rename and re-cut: `setup` (once) vs `preflight` (every run)

`phases/preflight.md` is titled *"Phase 0 — Preflight (once per environment)"*
but contains two different kinds of work, which is why agents re-do the
expensive half:

| current §  | kind | proposed home |
|---|---|---|
| 1 API key, 2 MCP server, 4 binary, 5 docker | assertion, cheap, must hold **every run** | `preflight` |
| 6 make tests runnable in a container (`Dockerfile.veris`) | construction, produces an artifact | `setup` |
| 7 read manuals, prepare + **promote** the default world | construction, produces environment state | `setup` |
| 3 read the generic guide | reading | `setup` |

So:

- **`phases/setup.md` — once per repo × environment.** Produces durable
  artifacts: `Dockerfile.veris`, `.veris/run.sh` (the exact invocation),
  `.veris/setup.json` (env id, image tag, promoted-world marker, skill
  version). Ends by promoting the world. Idempotent and resumable: if the
  artifacts exist and match, setup exits immediately saying so.
- **`phases/preflight.md` — every run, ~1 second, machine-checkable.** One
  command, one exit code: credential present, control plane reachable, docker
  up, image built and matching `.veris/setup.json`, environment resolvable.
  **On failure it stops the agent — it never suggests a workaround.** This is
  the fail-closed rule the skill already applies to test results, applied to
  its own preconditions.
- **`phases/running.md`** unchanged in substance.

The user's instinct is right: setup is one-time and should be
checkpointed. But a cheap per-run assertion must survive, because the
observed failure mode is not "setup was never done" — it is "setup silently
stopped holding, and the agent improvised around it."

## 3. Make the happy path the cheapest path

Agents take the shortest route to a working command. Today the shortest route
is to invent one.

- **`veris-proxy setup --environment <id>`** — writes `.veris/run.sh` and
  prints it. After that the correct command is a file, not a composition.
- **`veris-proxy preflight`** — the per-run gate above; exits nonzero with one
  diagnostic line. When the credential is absent but an MCP config exists, the
  message should name the fix (*"export the `X-API-Key` from your MCP config
  as `VERIS_API_KEY`"*) — in the measured runs the agent had the key in a
  readable file and still could not use the CLI.
- **An MCP tool `get_run_command(environment_id, repo_path)`** returning the
  literal shell line. This is the strongest lever available: it makes
  compliance strictly cheaper than improvisation for an agent that only has
  the MCP server.
- **Friction on the wrong path:** `veris-proxy run --config` without
  `--environment` warns and names the supported form.
- **Receipt records the path** (`path=environment|config|sandbox`) so
  compliance is gradeable from telemetry instead of trace forensics.

## 4. Promote is missing from the agent's world model

`promote_sandbox` is the platform's setup-once primitive — *"a world built
once becomes the starting point for every run after it"*, reversible via
`reset_environment`. Zero of eight measured arms called it; the MCP guide
never mentions it. Every run rebuilt accounts, connections, OAuth grants and
fixtures from the boot profile and paid tokens for it.

Fixes: add a promote section to the MCP guide (with the boundary semantics —
the sandbox is frozen and scrubbed, so promote *last*); make "promote the
world" the closing step of `setup.md`; have `preflight` report whether the
environment has a promoted baseline, so an agent starting from a bare boot
profile knows it is paying setup cost that someone else already paid.
`delete_sandbox` and `reset_environment` deserve a line each for the same
reason.

## 5. Deterministic enforcement (hooks) — for deployments, not benchmarks

The skill is prose; hooks are executed by the harness, so they do not depend
on the agent having read anything. Ship them as a `.claude/settings.json`
fragment the `agent-integration` skill installs:

- **`SessionStart`** — run `veris-proxy preflight`; inject either the exact
  `.veris/run.sh` invocation or a hard stop with the reason.
- **`PreToolUse(Bash)`** — block the improvisation signatures and return the
  supported command in the block message: `ngrok|cloudflared|localtunnel`,
  `veris-proxy … --config` without `--environment`, writes of
  `*_API_BASE=<sandbox url>` into repo source or `.env`, `NODE_OPTIONS`
  intercept preloads.
- **`PostToolUse(Bash)`** — after a `veris-proxy run`, parse the receipt and
  surface an empty one loudly.

**Benchmark caveat:** blocking hooks change the experimental condition — they
measure the product as designed rather than an agent's unaided use of it.
Both are legitimate questions; a study must state which one it ran. The
current benchmark deliberately runs without hooks so that discovery failures
remain visible.

## Suggested order

1. Guide edit (§1) — one paragraph, removes the contradiction, unblocks
   everything else. Cheapest, highest impact.
2. `preflight`/`setup` split + `.veris/run.sh` artifact.
3. `veris-proxy preflight` / `setup` subcommands, receipt `path=` field.
4. `get_run_command` MCP tool.
5. Promote coverage in guide + setup.
6. Hook fragment shipped with `agent-integration`.
