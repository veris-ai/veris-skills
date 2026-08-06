---
name: integration-testing
description: Run a repo's integration tests against a Veris dependency sandbox instead of real vendors, with veris-proxy transparently rerouting the code's outbound HTTP(S). Verifies prerequisites (API key, Veris MCP server, veris-proxy binary, committed .veris.toml), creates a per-run sandbox, starts and canary-checks the proxy, proves interception with a smoke test, then runs the real tests. Use when code that talks to external services needs its integration behavior verified before a change is called done.
---

Run this repo's integration tests against a Veris dependency sandbox.

The sandbox is a set of stateful, contract-accurate twins of the services this
code depends on. The code under test is **never modified and never told**: it
keeps its production hostnames, credentials, and client stack, and
`veris-proxy` reroutes its outbound HTTP(S) into the sandbox. Your job is to
stand that pipeline up, prove it is actually intercepting, and only then trust
any test result.

## Core framing: green means nothing without the canary

Everything in this skill exists to make one sentence true: *a passing test
proves the integration works against the sandbox*. Two rules follow.

- **Never modify the code under test to point it at Veris.** No base-URL
  overrides, no injected config, no test doubles. If the code path you test is
  not the code path that ships, the green is fiction. The proxy is the whole
  mechanism; if the proxy cannot cover a runtime (see the coverage table),
  that is a mode decision, not a license to patch the code.
- **Never report tests as passing without a fresh canary check.** A proxy left
  over from an earlier run, a half-set environment, or a runtime that silently
  ignores proxy variables all look identical to success. `veris-proxy check`
  fails closed on each of these. Run it after setting the environment and
  before drawing any conclusion from a test result. If the canary fails,
  interception is not live and nothing downstream means anything.

Do not declare the task done, and do not present results to the user as
passing, until the tests are green **and** the canary was live for that run.

## Phase 0 — Preflight (once per project)

Work through these gates in order. Each is check-first: if it already holds,
move on silently. Ask before installing anything or creating remote resources.

### 1. API key

`VERIS_API_KEY` must be set in the environment. If it is missing, stop and ask
the user for it — it arrives out of band (Veris console or their team) and you
must never write it into any file in the repo. `VERIS_API_URL` names the
control plane; if unset, ask for it alongside the key.

### 2. Veris MCP server

The control plane is driven **through MCP only**. Check whether the `veris`
MCP tools are available to you: `get_testing_guide`, `get_environment`,
`create_sandbox`, `get_sandbox`, `reset_sandbox`, `delete_sandbox`.

If they are not, instruct the user to register the server and restart the
session — a server registered mid-session is not loaded into it:

```bash
claude mcp add veris --transport http "$VERIS_API_URL/mcp" \
  --header "X-API-Key: $VERIS_API_KEY"
```

Then stop. Do not fall back to raw HTTP against the control plane.

Once connected, call `get_testing_guide` first and read it fully — seeding,
resets, fault injection, time control, diagnosis. It is the authority on
sandbox mechanics; this skill does not repeat it.

### 3. veris-proxy binary

Check first — never reinstall over a working binary:

```bash
veris-proxy version
```

Only if that fails, install (ask the user first):

```bash
curl -fsSL https://raw.githubusercontent.com/veris-ai/veris-proxy/main/scripts/install.sh | sh
```

The installer drops a static binary into `~/.local/bin` (no root, no package
manager), so the same line works on a laptop, in CI, and inside a container
build.

### 4. Committed `.veris.toml`

The repo's Veris test configuration lives in a committed, team-shared
`.veris.toml` at the repo root. If it exists, use it. If not, build it now:

1. `get_environment` with the env id — from `VERIS_ENV_ID`, or ask the user
   which environment this repo tests against (if they have none, that is an
   environment-creation task upstream of this skill). This yields the service
   names the sandbox will offer.
2. **Discover the real hostnames** the code believes it calls, from repo
   evidence: config files, `application*.yml`, `.env.example`, constants,
   SDK defaults. Cite the evidence. These hostnames — not sandbox URLs — go
   in the service map; the proxy's job is to claim them.
3. Set `upstream_base_url` to the sandbox ingress origin, always `https`
   (e.g. `https://svc.dev.api.veris.ai`): create a sandbox and take the
   origin of its service URLs, upgrading `http` to `https`.
4. Decide `[run]` (see the mode table below) and record the test command.
5. Write the file, show it to the user, and commit it with their approval.

```toml
# .veris.toml — committed, team-shared, no secrets
[veris]
env_id = "env_abc123"
api_url = "https://api.veris.ai"     # the key itself stays in $VERIS_API_KEY

[proxy]
upstream_base_url = "https://svc.dev.api.veris.ai"   # sandbox ingress; always https
allow_passthrough = ["@build"]       # package registries; add private ones
# listen defaults to 127.0.0.1:8080; set it only if that port is taken

[services.stripe]                     # one table per sandbox service
hosts = ["api.stripe.com", "*.stripe.com"]   # what the CODE believes it calls

[run]
mode = "host"                        # host | container — decided once, below
test_cmd = "make integration"
# container_image = "..."            # when mode = "container"
# reason = "why this mode"           # leave a trail for the next agent
```

Two values are deliberately absent: `sandbox_id` and the canary token are
per-run and arrive as flags. A committed canary would defeat stale-proxy
detection — the token only proves anything because each run mints its own.
Never commit secrets, sandbox URLs, or tunnel hostnames.

### Choosing `[run] mode` — once, with evidence

This is more than a proxy limitation question: some code cannot easily run in
a container, some runtimes cannot be covered outside one. Assess, decide,
record the decision and its reason in `[run]`, and confirm with the user.

| Evidence in the repo | Mode |
|---|---|
| Tests run on the host today; runtime is Python, Node, Ruby, .NET, or JVM | `host` |
| Go code under test **on macOS** (ignores `SSL_CERT_FILE`, verifies via Security.framework) | `container` |
| JVM using Apache HttpClient `createDefault()` (ignores JVM proxy properties) | `container` |
| Static binaries / anything that ignores proxy env vars | `container` |
| Repo is dockerized and its tests already run in Docker | `container` |
| Host tier's canary or TLS fails after honest setup | switch to `container`, record why |

`container` mode uses the proxy's transparent tier (`--transparent` +
iptables REDIRECT, `--cap-add=NET_ADMIN`, CA in the image's trust store) —
see `container/README.md` in veris-proxy. Nothing in the process has to
cooperate, which is why it covers what host mode cannot.

## Phase 1 — Every run

Autonomous once preflight holds. The loop, in order — do not reorder, because
each step's failure mode is caught by the next:

### 1. Create the sandbox

`create_sandbox` with the env id (pass `client_base_url` only if the code
must receive webhooks — see the testing guide for tunneling). Poll
`get_sandbox` until `ready`; stop and read `failure_reason` on `failed`.
Note each service's `url` and `control_url`.

### 2. Start the proxy

Mint a fresh canary; `.veris.toml` (including `upstream_base_url`) is found
automatically from the repo root:

```bash
CANARY="run-$(date +%s)-$RANDOM"
veris-proxy serve --sandbox-id "$SANDBOX_ID" --canary "$CANARY" &
```

Sanity-check the committed `upstream_base_url` against the **origin** of the
service URLs `get_sandbox` returned (scheme + host, no path — always prefer
`https` even if the control plane prints `http` URLs). If they differ, pass
`--upstream <origin>` to both `serve` and `env` for this run and tell the
user the committed value looks stale.

### 3. Environment, trust, canary

```bash
eval "$(veris-proxy env --sandbox-id "$SANDBOX_ID" --canary "$CANARY")"
veris-proxy check    # exit 2 = interception NOT live; fix before proceeding
```

Read `env`'s stderr warnings — they name exactly what the environment cannot
cover. For JVM code: run `veris-proxy trust --java` once (env then emits
`JAVA_TOOL_OPTIONS` automatically, which Gradle/Maven test forks inherit).
If the app loads its **own** keystore from disk (a mounted `keystore.p12` is
the common shape), the JVM default truststore is never consulted — put the CA
where the app actually looks: `veris-proxy trust --inject path/to/keystore`.

### 4. Smoke test before real tests

Prove interception through the repo's **own client stack** — not a bare curl:
one read and one write against a mapped service, exercising the same HTTP
client, TLS setup, and auth the production code uses. Verify the write landed
by querying the sandbox directly (`{control_url}/veris/data`, bypassing the
proxy). Seeded sandbox data that the real vendor could not have returned is
the cleanest possible proof. If the repo has no cheap entry point, write one
minimal test and keep it — it is the canary's application-level twin.

### 5. Run the real tests

Run `[run] test_cmd`. Strict mode is the default and stays on: an unmapped
host fails with a 502 naming the host — that is information, not an obstacle.
Either the host belongs to a service (add it to the map) or it is
infrastructure (add it to `allow_passthrough`). The `@build` preset already
covers public package registries, so dependency resolution works in the same
phase as the tests; private registries (Artifactory, corporate mirrors) get
their own explicit entry.

### 6. Set up cases, force failures, diagnose

- Seed state through `{control_url}/veris/data` / `seed`; read the service's
  own manual at `{control_url}/veris/manual` before testing it.
- Inject faults and latency per the testing guide to force the unhappy paths
  — retries, duplicates, out-of-order deliveries are exactly what the
  stateful twins exist to catch.
- When a test fails, check `{control_url}/veris/requests` **before forming a
  theory**, and reproduce with curl before blaming the sandbox, the proxy, or
  the code. The trace shows the wire exchange; most "sandbox bugs" are
  harness bugs.
- `reset_sandbox` between suites for a fresh coherent world — never mid-test.

### 7. Teardown

Kill the proxy, `delete_sandbox`. Sandboxes are ephemeral and yours to break;
leave nothing running that a later session could accidentally trust — that is
the exact staleness the canary guards against.

## Reporting back

Keep a running record of anything about the **sandbox** that confused or
blocked you: gaps in its documentation, behavior that contradicted the docs,
responses that differ from the real vendor, failures you could not attribute.
Include request/response evidence. Give that list to the user verbatim at the
end — it goes back to Veris, and it is how the twins improve.

## Ask before

- installing veris-proxy
- registering the MCP server (the user runs this — it needs a restart)
- committing `.veris.toml`
- anything that sends repo code or data to a new external destination

Sandbox lifecycle operations (`create_sandbox`, `reset_sandbox`,
`delete_sandbox`) are routine and yours to perform freely.
