# Phase 1 — Every run

Autonomous once preflight holds.

## 1. The proxy provisions the sandbox

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

## 2. Run the tests through the proxy

One command — proxy container, workload container, environment, trust,
receipt, and teardown are all its job:

```bash
veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" \
  --image <your-test-image> \
  -e SOME_CREDENTIAL="..." \
  -- make integration
```

`<your-test-image>` and the test command are whatever Phase 0 step 6 settled
on — when the repo carries a `Dockerfile.veris`, that is its built image and
the invocation reconstructed from its header comment (see the step 6 rule:
the header is read, never paste-executed); otherwise the bind-mounted
stock-image shape brings its mounts with it (e.g.
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
- **Add `--patch-bundled-cas` up front when the dependency set includes a
  known bundled-CA SDK** — stripe (Python or Ruby), older botocore,
  httplib2. Those SDKs hand their own CA file to the TLS layer and refuse
  the proxy's certificate no matter what the environment says; the flag
  over-mounts each known bundle with a copy that also carries the Veris CA
  (details in
  [troubleshooting.md](troubleshooting.md#sdks-that-bundle-their-own-ca)).
  Do not wait for the failure: it can be quiet — stripe-python surfaces it
  as a generic `APIConnectionError` network error, and if the run's own
  harness traffic completes on the same host, the receipt can look healthy
  while every SDK call dies. The flag is a no-op cost when nothing needs
  patching, and the run logs one line per file it does patch.
- The loud failure modes are built in — no flags needed: an `--environment`
  run whose receipt shows no service traffic exits 3 on its own
  (control-plane reads count separately and cannot stand in), and a mapped
  host whose TLS handshakes were rejected with nothing completed exits 3
  with a diagnostic that names the next action, whatever the SDK or
  language. `--require-service <name>[:count]` stays optional and rarely
  needed: reach for it only when a *specific* service or call count is
  itself the assertion — e.g. a multi-service suite where one service
  flowing must not vouch for another that was silently never called.
  Passing any `--require-*` takes over the verdict entirely.
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
  command; it never means managing a sandbox yourself. Reach for this shape
  the moment a second attempt looks plausible — wiring a repo's integration
  suite into a container rarely works on the first try, and relaunching the
  run command for every attempt redeploys a fresh sandbox and pays the
  provisioning wait per iteration; a session pays it once. If the session's
  world grows into something every future run should start from, promote it
  before ending the run: `promote_sandbox` with the sandbox id the run
  logged. Promotion copies the world into the environment's default, so the
  teardown that follows loses nothing.

## 3. Receiving webhooks

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

## 4. Fixing reported behavior? Reproduce it red first

When the task is a bug report about integration behavior — the code
mishandles a vendor event, a state transition, a callback — do not start
with the fix. Reproduce the report against the sandbox first: seed the
state the report describes, drive the real flow end-to-end **from the
boundary the report names** — the application's endpoint, worker, or job,
not the SDK call inside it — and watch the wrong outcome happen through the
shipping code path. Only then change code, rerun the same flow, and watch
it flip.

While the reproduction is red, use it: probe what the dependency actually
does at the exact condition the report describes — the response to the
replayed request, the state left behind by the failed callback, the error
code on the duplicate. The branch a fix hinges on is routinely one that
only the live dependency reveals, and that no amount of reading the code or
its SDK predicts. A fix designed purely from static reading lands plausible
and wrong precisely on that branch — and its author never notices, because
the tests they write encode the same guess the fix does.

The reproduction is not ceremony; it earns two things nothing else does.
It scopes the fix by *observed* behavior instead of by the first plausible
code path read — vendor state machines routinely have more branches than
the report names (a failure that the vendor treats as retryable, a
cancellation that must be terminal, an event arriving out of order), and
the sandbox's stateful twins surface exactly those branches. And the
red-then-green flip under the proxy, receipt attached, is the only
evidence that the change addressed the reported behavior rather than a
neighboring path — provided the flow ran through the changed code. A flip
measured a layer below the change (the SDK wrapper behaves correctly) or
beside it (a script reimplementing the handler's logic) is the same
fiction with better props. A fix whose validation was never seen red
against the sandbox carries no such evidence, however green its suite.

## 5. Set up cases, force failures

- Seed state through `{control_url}/veris/data` according to the
  generic testing guide and the already-read service manual.
- Inject faults and latency per the testing guide to force the unhappy paths
  — retries, duplicates, out-of-order deliveries are exactly what the
  stateful twins exist to catch.
- When a test fails, read [troubleshooting.md](troubleshooting.md) **before
  forming a theory** about the sandbox, the proxy, or the code.
- `reset_sandbox` (with the run's logged sandbox id) between suites for a
  fresh coherent world — never mid-test. When ad-hoc seeding produces a
  world every future run should start from, fold it into the environment's
  default with `promote_sandbox` on that same id before the run ends —
  the same move as Phase 0 step 7, made from a live session. When it is a
  world only *some* runs want, save it as a named **snapshot** instead
  (Phase 0 step 7) and boot it with `create_sandbox`'s `snapshot_id`;
  promoting it would change what every other suite starts from.
- A sandbox booted from a snapshot (or of a promoted environment) **refuses
  `reset_sandbox` with 409** — its world is an image, and reseeding profiles
  would silently replace it. Delete and recreate to get back to that world.

## 6. Teardown

Nothing to do: ending the run is the teardown — the proxy deletes the
sandbox it deployed, and `--ttl-minutes` backstops a run that dies without
one. Just leave nothing running: an interrupted session left in the
background is a sandbox still alive that a later session could accidentally
trust.
