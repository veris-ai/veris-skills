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
proves the integration works against the sandbox*. Three rules follow.

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
- **The green and the receipt must come from the same run — the run of the
  tests that justify the change.** These halves are easy to earn separately
  and worthless apart. Many repos' integration suites stub their vendors (a
  built-in fake provider, recorded fixtures): such a suite passes under the
  proxy while sending the sandbox nothing. And ad-hoc probes — a few curl
  calls, a driver script poking the vendor API — earn a receipt while
  verifying nothing about the change. A stub-earned green plus a probe-earned
  receipt reads as verification and proves none: the code path that changed
  never met the sandbox. If the tests that validate the change do not
  themselves generate the vendor traffic, extend or write one that exercises
  the real provider path, and run *that* under the proxy with
  `--require-service <name>[:count]` so the verdict and the evidence are one
  run.

- **The receipt proves traffic; it does not prove your change ran.** A run
  can satisfy every rule above — real traffic, valid receipt, same run — while
  exercising a layer *below* the change: a driver that invokes the vendor SDK
  directly produces perfect evidence about the SDK and none about the handler,
  workflow, or state machine above it that the change actually touched.
  Verification starts at the boundary the task names — the application's
  webhook endpoint, its worker, its API route — and the flow must execute the
  changed code on its way to the vendor. If nothing observable distinguishes
  "my diff ran" from "my diff was skipped", add that observation before
  trusting the green: an assertion on state only the new code writes, a log
  line only the new branch emits, or — the strongest form — the
  red-then-green flip of [phases/running.md](phases/running.md) §4, where
  the same flow fails before the change and passes after it, which no flow
  that skips the change can produce.

Do not declare the task done until the tests are green **and** the receipt
shows the sandbox received the traffic the tests were supposed to send —
from the same run, of a flow that executed the changed code.

## The mode: container, always

Everything runs through **`veris-proxy run --image ...`**. The proxy runs in
its own container and your image runs in a second one sharing its network
namespace; an `iptables` redirect moves the traffic in the kernel, below
every library. Nothing in the process under test has to cooperate, so the
*routing* covers **every** runtime: Java, static Go binaries, Apache
HttpClient, aiohttp. (*Trust* is still decided in-process, and an SDK that
ships its own CA bundle decides it alone — see
[phases/troubleshooting.md](phases/troubleshooting.md#sdks-that-bundle-their-own-ca).)
Your image needs no capability, no iptables, no entrypoint change, and no
particular base — distroless and scratch work. All requirements sit on the
proxy's own container.

(The binary also has a host tier — `run` without `--image`, environment
variables only. Do not use it in this skill: it covers only libraries that
honour proxy variables, and its gaps are silent. If the work truly cannot
run in a container, stop and tell the user rather than falling back.)

There is no committed proxy config to maintain. The run names an
`--environment` and the whole routing — which production hostnames map to
which sandbox services — is derived from the control plane plus a routing
table measured against the real vendors and embedded in the binary. Never
write hosts files by hand.

## The phases

Work the skill as two phases plus a failure manual, each in its own file.
Read the file **fully** at the point named — the details there are
load-bearing, not optional:

- **[phases/preflight.md](phases/preflight.md)** — Phase 0, once per
  environment: seven check-first gates (API key, MCP server, testing guide,
  proxy binary, docker, a runnable test image, service manuals + the default
  world). Run through it before the first run against any environment, and
  whenever a prerequisite might have changed.
- **[phases/running.md](phases/running.md)** — Phase 1, every run: the one
  run command and its flags, receipts and `--require-*` assertions, exec
  sessions for iterative work, webhooks via `--expose`,
  reproduce-red-first for bug fixes, seeding and fault injection, teardown.
  Autonomous once preflight holds.
- **[phases/troubleshooting.md](phases/troubleshooting.md)** — the moment
  anything fails or confuses: the evidence-first diagnosis order (receipt,
  then `/veris/requests`, then theories), empty-receipt causes, exit codes,
  and TLS trust failures from SDKs that bundle their own CA. Read it
  **before forming a theory**, not after one collapses.

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
