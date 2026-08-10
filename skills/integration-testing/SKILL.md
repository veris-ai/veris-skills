---
name: integration-testing
description: Run a repo's integration tests against a Veris dependency sandbox instead of real vendors, with veris-proxy rerouting the code's outbound HTTP(S) at the kernel level. Verifies prerequisites (API key, Veris MCP server, veris-proxy binary, docker), creates a sandbox, runs the tests in a container beside the proxy with one command, and proves the sandbox actually received the traffic before trusting any green. Use when code that talks to external services needs its integration behavior verified before a change is called done.
---

Run this repo's integration tests against a Veris dependency sandbox.

The sandbox is a set of stateful, contract-accurate twins of the services this
code depends on. The code under test is **never modified and never told**: it
keeps its production hostnames, credentials, and client stack, and
`veris-proxy` reroutes its outbound HTTP(S) into the sandbox from outside the
process. Your job is to stand that pipeline up, prove it actually intercepted,
and only then trust any test result.

## Core framing: green means nothing without proof of interception

Everything in this skill exists to make one sentence true: *a passing test
proves the integration works against the sandbox*. Two rules follow.

- **Never modify the code under test to point it at Veris.** No base-URL
  overrides, no injected config, no test doubles. If the code path you test is
  not the code path that ships, the green is fiction. The proxy is the whole
  mechanism.
- **Never report tests as passing without evidence the sandbox received the
  traffic.** A suite that quietly stopped calling its dependency, a runtime
  that ignored the interception, and a working run all print the same test
  output. The proxy prints a **receipt** — what the sandbox actually received,
  per service — after every run, and `--require-service <name>` turns an empty
  receipt into exit code 3. Always pass `--require-service` for each service
  the tests are supposed to exercise, and read the receipt before drawing any
  conclusion.

Do not declare the task done until the tests are green **and** the receipt
shows the sandbox received the traffic the tests were supposed to send.

## The two modes, and why container wins

`veris-proxy run` has two tiers:

- **Container (`run --image ...`) — the default; use it whenever docker is
  available.** The proxy runs in its own container and your image runs in a
  second one sharing its network namespace; an `iptables` redirect moves the
  traffic in the kernel, below every library. Nothing in the process under
  test has to cooperate, so it covers **every** runtime: Java, static Go
  binaries, Apache HttpClient, aiohttp, SDKs that pin their own CA bundle.
  Your image needs no capability, no iptables, no entrypoint change, and no
  particular base — distroless and scratch work. All requirements sit on the
  proxy's own container.
- **Host (`run -- <cmd>`) — the fallback for work that cannot run in a
  container.** Runs the command locally with proxy and CA environment
  variables set, which is a *request*, not an enforcement: it covers only
  libraries that honour those variables. Known gaps, all covered by the
  container tier: Go on macOS (verifies via Security.framework), Apache
  HttpClient `createDefault()`, `aiohttp` without `trust_env=True`, the
  Stripe Python/Ruby SDKs (own CA bundle). `run` prints what it cannot cover
  to stderr — read those warnings.

There is no committed proxy config to maintain. `--sandbox <id>` derives the
whole routing — which production hostnames map to which sandbox services —
from the control plane plus a routing table measured against the real vendors
and embedded in the binary. Do not write hosts files by hand;
`veris-proxy serve --sandbox <id> --print-routes` shows the derived routing if
you need to inspect it.

## Phase 0 — Preflight (once per project)

Work through these gates in order. Each is check-first: if it already holds,
move on silently. Ask before installing anything.

### 1. API key

`VERIS_API_KEY` must be set in the environment. If it is missing, stop and ask
the user for it — it arrives out of band (Veris console or their team) and you
must never write it into any file in the repo. `VERIS_API_BASE` names the
control plane base URL; it defaults to `https://api.veris.ai`, so set it only
when the user's team runs elsewhere.

### 2. Veris MCP server

Sandbox lifecycle is driven **through MCP**. Check whether the `veris` MCP
tools are available to you: `get_testing_guide`, `get_environment`,
`create_sandbox`, `get_sandbox`, `reset_sandbox`, `promote_sandbox`,
`delete_sandbox`.

If they are not, instruct the user to register the server and restart the
session — a server registered mid-session is not loaded into it:

```bash
claude mcp add veris --transport http "$VERIS_API_BASE/mcp" \
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

### 4. Docker, and the proxy's runner image

Container mode needs `docker` on PATH. The proxy's own image is pulled
automatically from Veris's registry; a first run wants one-time registry
auth:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
```

If docker is genuinely unavailable (some CI shapes, a machine without a
daemon), fall back to host mode and record why.

### 5. Decide how the tests run in a container

The image under test needs nothing Veris-specific, so the choice is purely
about the repo:

| Evidence in the repo | Choice |
|---|---|
| A Dockerfile / test image the team already uses | use it as `--image` |
| No image, interpreted or JVM runtime | stock language image + bind-mount the repo: `--image maven:3-eclipse-temurin-21 -v "$PWD:/work" -w /work` (adjust for node/python/etc.) |
| No image, compiled binary | build it in a stock toolchain image the same way |
| Cannot run containerised at all | host mode, note the coverage warnings |

Mount dependency caches too when they exist (`-v "$PWD/.m2:/root/.m2"`,
node_modules, pip cache) — the proxy does not intercept package registries by
default, so dependency resolution works normally either way.

One constraint: the image must not run as uid 14741 (the uid the kernel
redirect exempts for the proxy itself). The CLI refuses with an explanation
if it does; `--proxy-uid` moves the exemption.

## Phase 1 — Every run

Autonomous once preflight holds.

### 1. Choose the sandbox: per-run by default

The default needs no step at all: pass `--environment <env_id>` (from
`VERIS_ENVIRONMENT_ID` or the user) on the command below and the proxy
deploys a fresh sandbox of that environment for the run and deletes it when
the run ends (`--ttl-minutes` bounds a leak if teardown never runs). A
sandbox per run is hermetic, and for webhook tests it is also the safe
shape — two runs sharing a sandbox would overwrite each other's callback
registration.

Create a sandbox through MCP instead — `create_sandbox`, poll `get_sandbox`
until `ready` (stop and read `failure_reason` on `failed`), run with
`--sandbox <id>`, `delete_sandbox` after — when the run needs a world you
prepared: state seeded before the tests, several suites against one world,
or post-run inspection. Note each service's `url` and `control_url` —
`/veris/*` control endpoints always live on `control_url`.

### 2. Run the tests through the proxy

One command — proxy container, workload container, environment, trust,
receipt, and teardown are all its job:

```bash
veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" \
  --image maven:3-eclipse-temurin-21 \
  -v "$PWD:/work" -v "$PWD/.m2:/root/.m2" -w /work \
  -e SOME_CREDENTIAL="..." \
  --require-service stripe \
  -- mvn -q verify
```

(`--sandbox "$SANDBOX_ID"` in place of `--environment` when attaching to an
MCP-managed sandbox.)

- `-v`, `-e`, `-w` pass through to the workload container. Credentials the
  code expects still come from its environment, exactly as in production —
  the sandbox publishes known-good credentials readable at
  `{control_url}/veris/data`; the service's manual
  (`{control_url}/veris/manual`) names where.
- With no command after `--`, the image's own ENTRYPOINT/CMD run untouched.
- `--require-service <name>[:count]`, repeatable — the assertion that makes
  an empty receipt fail. Use one per service the suite must touch.
- Exit codes: the command's own status; `3` = a `--require-service` /
  `--require-callback` went unmet; `4` = outcome indeterminate (treat as
  failure, not success).
- By default only mapped hosts are rerouted; everything else (registries,
  telemetry, internal APIs) reaches its real destination. Add `--strict` for
  a run that must prove the code reached nothing but the sandbox — an
  unmapped host then fails with a 502 naming the host, which is information,
  not an obstacle.
- `--keep-proxy` leaves the proxy container up afterwards for inspection.

Host-mode fallback is the same command without `--image`:
`veris-proxy run --sandbox "$SANDBOX_ID" -- make integration`. Host mode
needs an MCP-managed sandbox — `--environment` (like `--expose`) lives in
the proxy container, so the CLI refuses both without `--image`. Read its
stderr warnings — they name exactly what the environment cannot cover. For a
long-lived interactive session instead of per-run supervision, use
`veris-proxy serve --sandbox <id> --write-env <file>`, source the file, and
run `veris-proxy check` before trusting any result — `check` fails closed
(exit 2) on a missing proxy, a non-Veris proxy, or a proxy left over from an
earlier run against different data.

### 3. Receiving webhooks

The proxy routes your code OUT; a webhook comes back IN, and a sandbox in the
cluster cannot reach an app on your laptop. `--expose <port>` (the port your
app listens on) opens a public tunnel and registers it with the sandbox. In
container mode the app shares the proxy's port space, and 8080/8081/8443 are
the proxy's own listeners — `--expose 8080` is refused; have the app listen
elsewhere (e.g. 3000).
`--require-callback <path>[:count]` (or `'*'`) asserts delivery the same way
`--require-service` asserts egress — a webhook suite that received nothing
must not pass. Your app is handed `VERIS_PUBLIC_URL` and registers it with
the vendor through the vendor's own API, because that registration call is
also code under test. Combine with `--environment` so concurrent runs cannot
overwrite each other's callback URL.

### 4. Set up cases, force failures, diagnose

- Seed state through `{control_url}/veris/data` / `seed`; read the service's
  manual at `{control_url}/veris/manual` before testing it.
- Inject faults and latency per the testing guide to force the unhappy paths
  — retries, duplicates, out-of-order deliveries are exactly what the
  stateful twins exist to catch.
- When a test fails, check `{control_url}/veris/requests` **before forming a
  theory**, and reproduce with curl before blaming the sandbox, the proxy, or
  the code. The trace shows the wire exchange; most "sandbox bugs" are
  harness bugs.
- `reset_sandbox` between suites for a fresh coherent world — never mid-test.
  Once a sandbox holds a world worth keeping, `promote_sandbox` makes it the
  environment's default for later runs.

### 5. Teardown

`delete_sandbox` (or let `--environment` do it). Sandboxes are ephemeral and
yours to break; leave nothing running that a later session could accidentally
trust.

## Reporting back

Keep a running record of anything about the **sandbox** that confused or
blocked you: gaps in its documentation, behavior that contradicted the docs,
responses that differ from the real vendor, failures you could not attribute.
Include request/response evidence. Give that list to the user verbatim at the
end — it goes back to Veris, and it is how the twins improve.

## Ask before

- installing veris-proxy
- registering the MCP server (the user runs this — it needs a restart)
- anything that sends repo code or data to a new external destination

Sandbox lifecycle operations (`create_sandbox`, `reset_sandbox`,
`delete_sandbox`, `promote_sandbox`) are routine and yours to perform freely.
