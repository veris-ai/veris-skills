---
name: integration-testing
description: Run a repo's integration tests against a Veris dependency sandbox instead of real vendors, with veris-proxy rerouting the code's outbound HTTP(S) at the kernel level. Verifies prerequisites (API key, Veris MCP server, veris-proxy binary, docker), then runs the tests in a container beside the proxy with one command that deploys a per-run sandbox and proves the sandbox actually received the traffic before trusting any green. Use when code that talks to external services needs its integration behavior verified before a change is called done.
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
  per service — after every run, and an `--environment` run whose receipt is
  empty exits 3 on its own: the environment already names the services, so
  "the suite reached the sandbox at all" is asserted for you. When the tests
  must touch a *specific* service, sharpen with `--require-service
  <name>[:count]`. Either way, read the receipt before drawing any
  conclusion.

Do not declare the task done until the tests are green **and** the receipt
shows the sandbox received the traffic the tests were supposed to send.

## The mode: container, always

Everything runs through **`veris-proxy run --image ...`**. The proxy runs in
its own container and your image runs in a second one sharing its network
namespace; an `iptables` redirect moves the traffic in the kernel, below
every library. Nothing in the process under test has to cooperate, so it
covers **every** runtime: Java, static Go binaries, Apache HttpClient,
aiohttp, SDKs that pin their own CA bundle. Your image needs no capability,
no iptables, no entrypoint change, and no particular base — distroless and
scratch work. All requirements sit on the proxy's own container.

(The binary also has a host tier — `run` without `--image`, environment
variables only. Do not use it in this skill: it covers only libraries that
honour proxy variables, and its gaps are silent. If the work truly cannot
run in a container, stop and tell the user rather than falling back.)

There is no committed proxy config to maintain. The run names an
`--environment` and the whole routing — which production hostnames map to
which sandbox services — is derived from the control plane plus a routing
table measured against the real vendors and embedded in the binary. Never
write hosts files by hand.

## Phase 0 — Preflight (once per environment)

Work through these gates in order. Each is check-first: if it already holds,
move on silently. Ask before installing anything.

### 1. API key

`VERIS_API_KEY` must be set in the environment. If it is missing, stop and ask
the user for it — it arrives out of band (Veris console or their team) and you
must never write it into any file in the repo. `VERIS_API_BASE` names the
control plane base URL; it defaults to `https://api.veris.ai`, so set it only
when the user's team runs elsewhere.

### 2. Veris MCP server

The control plane is driven **through MCP** — the testing guide, the
environment's shape, and any sandbox you manage yourself (the per-run
`--environment` sandboxes in Phase 1 are the proxy's job, but seeded worlds,
resets, and promotion are yours). Check whether the `veris` MCP tools are
available to you: `get_testing_guide`, `get_environment`, `create_sandbox`,
`get_sandbox`, `reset_sandbox`, `promote_sandbox`, `delete_sandbox`.

If they are not, instruct the user to register the server and restart the
session — a server registered mid-session is not loaded into it:

```bash
claude mcp add veris --transport http "$VERIS_API_BASE/mcp" \
  --header "X-API-Key: $VERIS_API_KEY"
```

Then stop. Do not fall back to raw HTTP against the control plane.

### 3. Generic client testing guide

Once the MCP server is connected, call `get_testing_guide` and read the
returned guide fully before creating a sandbox or planning tests. It is the
client-facing authority on sandbox mechanics: seeding, resets, fault
injection, time control, callbacks, and diagnosis.

### 4. veris-proxy binary

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

### 5. Docker, and the proxy's runner image

Container mode needs `docker` on PATH and a logged-in gcloud
(`gcloud auth login`) — the proxy's own image is pulled automatically from
Veris's registry using that login. If the pull still answers 401, docker is
not wired to gcloud yet: `gcloud auth configure-docker
us-central1-docker.pkg.dev` (once). This goes away when the image becomes
publicly pullable.

If docker is genuinely unavailable (some CI shapes, a machine without a
daemon), stop and tell the user — this skill does not run without the
container tier.

### 6. Make the tests runnable in a container

Every run uses `--image`, so the tests must run inside one — but the image
needs nothing Veris-specific, so this is ordinary dockerization, and usually
no work at all:

| Evidence in the repo | What to use |
|---|---|
| A Dockerfile / test image the team already uses | use it as `--image` |
| No image, interpreted or JVM runtime | stock language image + bind-mount the repo: `--image maven:3-eclipse-temurin-21 -v "$PWD:/work" -w /work` (adjust for node/python/etc.) |
| No image, compiled binary | build it in a stock toolchain image the same way |

Mount dependency caches too when they exist (`-v "$PWD/.m2:/root/.m2"`,
node_modules, pip cache) — the proxy does not intercept package registries by
default, so dependency resolution works normally either way. If the repo
genuinely cannot run containerised (a hardware dependency, a host-only
harness), stop and tell the user; do not fall back to running on the host.

One constraint: the image must not run as uid 14741 (the uid the kernel
redirect exempts for the proxy itself). The CLI refuses with an explanation
if it does; `--proxy-uid` moves the exemption.

### 7. Read the service manuals and prepare the default world

A fresh sandbox starts from the environment's default world, and every
per-run `--environment` sandbox in Phase 1 inherits it — so state the tests
always need is seeded **once, here**, not per run. This preflight also makes
the service-specific contracts available before any tests are planned:

1. `create_sandbox`, poll `get_sandbox` until `ready`.
2. As soon as it is ready, read every service's manual
   (`{control_url}/veris/manual`) fully before planning the smoke test or
   integration tests. The generic testing guide owns sandbox mechanics;
   these manuals own service-specific connection details, credentials, test
   values, error codes, formats, and limitations.
3. If the boot-profile world already fits the tests, delete the sandbox and
   stop here — the default seed is designed to be usable without preparation.
4. Otherwise, seed through `{control_url}/veris/data` / `seed` according to
   the generic testing guide and the service manuals.
5. Verify the world reads back the way the tests expect.
6. `promote_sandbox` — the sandbox's world becomes the environment's
   default; every later `create_sandbox` (including the proxy's per-run
   ones) and `reset_sandbox` starts from it.
7. `delete_sandbox`.

## Phase 1 — Every run

Autonomous once preflight holds.

### 1. The proxy provisions the sandbox

Sandbox provisioning is the proxy's job, always: `--environment <env_id>`
(from `VERIS_ENVIRONMENT_ID` or the user) on the run command makes the proxy
deploy a fresh sandbox of that environment, run against it, and delete it
when the run ends (`--ttl-minutes` bounds a leak if teardown never runs). A
sandbox per run is hermetic, and for webhook tests it is also the safe shape
— two runs sharing a sandbox would overwrite each other's callback
registration. Outside Phase 0's world preparation, never manage a sandbox
yourself; `--sandbox` does not appear in this phase.

State the tests always need is not a reason to leave this default: it lives
in the environment's promoted world (Phase 0, step 7), which every per-run
sandbox starts from. And the run's sandbox is still fully inspectable while
it lives — the proxy logs `sandbox ready sandbox_id=<id>`; `get_sandbox`
with that id yields each service's `url` and `control_url` (`/veris/*`
control endpoints always live on `control_url`) for mid-session seeding and
diagnosis. The lifecycle stays the proxy's.

### 2. Run the tests through the proxy

One command — proxy container, workload container, environment, trust,
receipt, and teardown are all its job:

```bash
veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" \
  --image <your-test-image> \
  -e SOME_CREDENTIAL="..." \
  -- make integration
```

`<your-test-image>` and the test command are whatever Phase 0 step 6 settled
on; the bind-mounted stock-image shape brings its mounts with it (e.g.
`--image maven:3-eclipse-temurin-21 -v "$PWD:/work" -v "$PWD/.m2:/root/.m2"
-w /work -- mvn -q verify`).

- `-v`, `-e`, `-w` pass through to the workload container. Credentials the
  code expects still come from its environment, exactly as in production —
  the sandbox publishes known-good credentials readable at
  `{control_url}/veris/data`; the service's manual
  (`{control_url}/veris/manual`) names where.
- Non-HTTP services are **handed over, not proxied**: a database service's
  connection string arrives in the workload's environment under the exact
  variable the platform names for it (`DATABASE_URL` for Postgres) —
  automatically, in every tier. Do not wire it yourself, and do not treat
  "postgres: not proxied" in the startup log as a gap: it names the variable
  the value went to. An explicit `-e DATABASE_URL=...` of your own still
  wins.
- With no command after `--`, the image's own ENTRYPOINT/CMD run untouched.
- An empty receipt already fails an `--environment` run (exit 3) — that
  assertion is built in. `--require-service <name>[:count]`, repeatable,
  sharpens it: use it when the suite must touch a specific service, or a
  specific number of times; passing any takes over the verdict entirely.
- Exit codes: the command's own status; `3` = the run never proved its
  traffic (empty receipt, or an explicit `--require-service` /
  `--require-callback` unmet); `4` = outcome indeterminate (treat as
  failure, not success).
- By default only mapped hosts are rerouted; everything else (registries,
  telemetry, internal APIs) reaches its real destination. Add `--strict` for
  a run that must prove the code reached nothing but the sandbox — an
  unmapped host then fails with a 502 naming the host, which is information,
  not an obstacle.
- `--keep-proxy` leaves the proxy container up afterwards for inspection.

The command after `--` is arbitrary and the receipt covers whatever ran, so
shape the invocation to the work:

- **One suite**: `-- make integration` (or the repo's own test entrypoint).
- **Several steps in one interception session**: chain them through the
  image's shell — `-- bash -lc 'python seed_fixtures.py && pytest
  tests/integration -x'`. Data generation, setup, and tests all run behind
  the same proxy and land on the same receipt.
- **An open-ended session** — generate data, run a test, read
  `{control_url}/veris/requests`, adjust, run again, as long as you need:
  start the run with a command that stays up (`-- sleep infinity`, or the
  repo's dev entrypoint), leave it running in the background, and exec each
  iteration into the workload container:

  ```bash
  veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" --image <img> ... -- sleep infinity &
  docker exec "$(docker ps -q -f name=veris-workload-)" bash -lc 'pytest tests/integration -x'
  # ...as many exec rounds as the work needs...
  kill %1   # interrupt the run: sandbox deleted, receipt printed
  ```

  Everything exec'd runs behind the same kernel redirect, the sandbox and
  its state persist for the whole session with the lifecycle still the
  proxy's — interrupting the run tears it all down — and the final receipt
  covers the entire session. This keeps one container up rather than one
  command; it never means managing a sandbox yourself. If the session's
  world grows into something every future run should start from, promote it
  before ending the run: `promote_sandbox` with the sandbox id the run
  logged. Promotion copies the world into the environment's default, so the
  teardown that follows loses nothing.

### 3. Receiving webhooks

The proxy routes your code OUT; a webhook comes back IN, and a sandbox in the
cluster cannot reach an app on your laptop. `--expose <port>` (the port your
app listens on) opens a public tunnel and registers it with the sandbox. The
app shares the proxy's port space, and 8080/8081/8443 are the proxy's own
listeners — `--expose 8080` is refused; have the app listen elsewhere
(e.g. 3000).
`--require-callback <path>[:count]` (or `'*'`) asserts delivery the same way
`--require-service` asserts egress — a webhook suite that received nothing
must not pass. Your app is handed `VERIS_PUBLIC_URL` and registers it with
the vendor through the vendor's own API, because that registration call is
also code under test. Combine with `--environment` so concurrent runs cannot
overwrite each other's callback URL.

### 4. Set up cases, force failures, diagnose

- Seed state through `{control_url}/veris/data` / `seed` according to the
  generic testing guide and the already-read service manual.
- Inject faults and latency per the testing guide to force the unhappy paths
  — retries, duplicates, out-of-order deliveries are exactly what the
  stateful twins exist to catch.
- When a test fails, check `{control_url}/veris/requests` **before forming a
  theory**, and reproduce with curl before blaming the sandbox, the proxy, or
  the code. The trace shows the wire exchange; most "sandbox bugs" are
  harness bugs.
- `reset_sandbox` (with the run's logged sandbox id) between suites for a
  fresh coherent world — never mid-test. When ad-hoc seeding produces a
  world every future run should start from, fold it into the environment's
  default with `promote_sandbox` on that same id before the run ends —
  the same move as Phase 0 step 7, made from a live session.

### 5. Teardown

Nothing to do: ending the run is the teardown — the proxy deletes the
sandbox it deployed, and `--ttl-minutes` backstops a run that dies without
one. Just leave nothing running: an interrupted session left in the
background is a sandbox still alive that a later session could accidentally
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
