---
name: integration-testing
description: Runs a repository's integration tests against a Veris dependency sandbox through veris-proxy, with the code under test unmodified - the run command from .veris/run.sh, one exec session for iteration, the failure reproduced red before the change and green after it, seeding and fault injection, webhooks via --expose, and a receipt proving the sandbox received the traffic. Use when a change to code that calls an external service needs to be exercised, or a reported integration behaviour needs reproducing.
---

Run this repository's integration tests against a Veris dependency sandbox.

The sandbox is a set of stateful, contract-accurate twins of the services this
code depends on. The code under test is **never modified and never told**: it
keeps its production hostnames, credentials and client stack, and
`veris-proxy` reroutes its outbound HTTP(S) into the sandbox from outside the
process. Your job is to make the failure the task describes happen, change the
code, watch it stop happening — and be able to prove all three.

## Where you are

- No `.veris/run.sh`, or `setting-up-veris`'s `scripts/preflight.sh` fails →
  that skill first. Transport is never improvised here.
- The design is still open, or the task rests on a claim about the vendor you
  have not seen it make — *"the API has no X"*, *"it always returns Y"* →
  `discovering-vendor-behavior` first. Arriving with the design fixed leaves
  the sandbox one question: whether your code works. It will answer that,
  correctly, while the assumption underneath goes unexamined.
- Otherwise: run.

## The run

One command — proxy container, workload container, environment, trust,
receipt and teardown are all its job. `.veris/run.sh` carries it; with no
`run.sh` the shape is:

```bash
veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" --image <test-image> \
  -v "$PWD:/work" -w /work -- <test command>
```

The proxy deploys a fresh sandbox of the environment, runs against it, prints
a **receipt** — what the sandbox received, per service — and deletes the
sandbox. It logs `sandbox ready sandbox_id=<id>`; `get_sandbox` with that id
gives each service's `control_url` for seeding and reading back while the run
lives. Never manage a sandbox of your own for a run.

- An `--environment` run whose receipt shows no service traffic exits 3 on
  its own (control-plane reads count separately and cannot stand in). A
  mapped host whose TLS handshakes were all rejected also exits 3, with a
  diagnostic that names the next action. `4` is indeterminate — a failure,
  never a pass.
- `--require-service <name>[:count]` is optional and rarely needed: only when
  a *specific* service or call count is itself the assertion. Passing any
  `--require-*` takes over the verdict.
- `--strict` fails the run on any unmapped host with a 502 naming it — use
  it when the claim is "the code reached nothing but the sandbox".
- `--patch-bundled-cas` goes on **up front** when the dependency set includes
  stripe (Python or Ruby), older botocore or httplib2; those SDKs refuse the
  proxy's certificate quietly. [reference/trust.md](reference/trust.md).
- `--keep-proxy` leaves the proxy container up for inspection.

## The loop

The twin is a simulator, not a mock: it can put the vendor into the state the
task describes and show you what it recorded afterwards. Every run is one
pass of this loop, and a bug-shaped task starts with a pass that is **red**:

1. **Arrange** — seed exactly the rows the case needs through
   `POST {control_url}/veris/data`, in the shapes `/veris/schema` and the
   manual name. Discover ids from sandbox state; never guess them.
2. **Arm** — the fault for this case: the lost response (`"phase":"after"`),
   the throttle (429 with `Retry-After`, `"remaining":2`), the vanished
   record, the latency. The manual lists the codes you can force; the testing
   guide §4 has the row format; `discovering-vendor-behavior` has the table.
3. **Drive** — the flow from the boundary the task names: the application's
   endpoint, worker, job, or tool handler — not the SDK call inside it — with
   **the call the report describes, unchanged**. A retry that only goes green
   because the caller now passes something new has changed the caller, not
   fixed the code. Use the smallest test that crosses the changed boundary
   and calls the dependency.
4. **Read back** — the receipt; `GET {control_url}/veris/requests` for what
   the client actually sent; `GET {control_url}/veris/data?entity_type=` for
   what the vendor stored. On a failure, read these *before* forming a theory
   ([reference/troubleshooting.md](reference/troubleshooting.md)).
5. **Flip** — the same pass, red before the change and green after it.

While the reproduction is red, use it. Probe what the dependency does at the
exact condition the report describes — the response to the replayed request,
the state left by the failed callback, the code on the duplicate. The branch a
fix hinges on is routinely one that only the live dependency reveals, and a
fix designed from static reading lands plausible and wrong on precisely that
branch; its author never notices, because the tests they write encode the same
guess the fix does.

**Iterate in one session.** Wiring a suite into a container rarely works first
try, and each relaunch redeploys a sandbox. Start the run with `-- sleep
infinity &`, then `docker exec "$(docker ps -q -f name=veris-workload-)" bash
-lc '<one pass>'` as many times as the work needs; `kill %1` ends it and
prints the receipt for the whole session. Several steps in one interception
also chain through the image's shell: `-- bash -lc 'python seed.py && pytest
tests/integration -x'`.

## Done means

- the receipt names the service the tests were supposed to reach;
- that receipt and the green come from **the same run** — a stub-earned
  green and a probe-earned receipt prove nothing together;
- that run executed the changed code on its way to the vendor — an assertion
  on state only the new code writes, a log line only the new branch emits, or
  the red-then-green flip itself;
- nothing in the repo or its environment was pointed at a sandbox.

Write the verification section of the change description from
[reference/evidence.md](reference/evidence.md). What was measured goes under
*verified*; what was not goes under *assuming rather than verifying*, and
the `.veris/MEASUREMENTS.md` ledger, when there is one, is read against the
design before the section is written.

## Reference, when the case calls for it

- [reference/troubleshooting.md](reference/troubleshooting.md) — receipt,
  then `/veris/requests`, then theories; the empty receipt; exit codes.
- [reference/trust.md](reference/trust.md) — SDKs that bundle their own CA,
  the sidecar that never got the handoff, the two-retry loop.
- [reference/worlds.md](reference/worlds.md) — reset, promote, snapshots;
  keeping a world a session built.
- [reference/webhooks.md](reference/webhooks.md) — `--expose`,
  `--require-callback`.
- [reference/evidence.md](reference/evidence.md) — the change-description
  template.

## Reporting back

Keep a running record of anything about the **sandbox** that confused or
blocked you: gaps in its documentation, behaviour that contradicted the docs,
responses that differ from the real vendor, failures you could not attribute.
Include request and response evidence. Give that list to the user verbatim at
the end — it goes back to Veris, and it is how the twins improve.

## Ask before

Installing veris-proxy, registering the MCP server, or sending repo code to a
new external destination. Sandbox lifecycle operations (`create_sandbox`,
`reset_sandbox`, `delete_sandbox`, `promote_sandbox`) are routine and yours.
