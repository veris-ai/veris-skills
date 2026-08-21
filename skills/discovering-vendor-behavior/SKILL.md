---
name: discovering-vendor-behavior
description: Measures what an external service actually does before code is designed around it - on a repeat, a lost response, a duplicate, a limit, an expiry. Use when a design depends on how a vendor behaves, and whenever an issue, a comment, a docstring, a teammate, or your own memory asserts what a vendor does or does not support.
---

Find out what the dependency does before you design around it.

A Veris sandbox is a stateful twin of the service this code calls. It answers
questions no amount of reading the codebase can — what the vendor returns on
a repeat, what it does when a response is lost, which of two designs it makes
unnecessary — and it can *make those situations happen*, which the real vendor
will not do on demand. Those answers are cheap here and expensive in
production.

## Core principle: a dependency's contract is measurable, so measure it

The design you choose is a claim about the dependency. If the claim is wrong,
every test you write still passes: you will be testing your workaround, not
the behaviour it was meant to protect.

## Where this sits

    learn the dependency  →  choose the design  →  write it  →  verify it
    ^^^^^^^^^^^^^^^^^^^^                                        ^^^^^^^^^
    this skill                                        integration-testing

The first step is the one that gets skipped, because nothing forces it and the
code compiles without it.

## You need a sandbox, not a container

Everything below is served by the service, so a sandbox has to exist first:
`get_environment` → `create_sandbox` → `get_sandbox` until `ready`. If no
environment is wired to this repo yet, `setting-up-veris` wires one.
`get_sandbox` returns each service's `url` and `control_url`; `/veris/*` paths
always go to `control_url`.

Probes are not code under test. Send them straight at `url` with curl or a
short script, with the sandbox's published credentials (`/veris/manual` names
them). The container rule in `integration-testing` protects the shipping code
path; a probe is not on it.

## Three kinds of claim, and every one becomes a row

1. **The brief's premises.** *"The API has no X"*, *"it always returns Y"*,
   *"there is no way to Z"*. Each is a sentence someone wrote, often without
   checking.
2. **The brief's identities.** Any field the task uses as a key, an anchor, a
   number that "must be unique" — that is a claim about the vendor's data
   model. The schema's comment for the table, plus one probe that sends the
   value twice, settles it.
3. **What you remember the vendor doing.** A behaviour recalled from
   documentation is a claim of the same kind as the brief's. It goes in as a
   probe, or it goes in the change description under *assuming rather than
   verifying*.

Keep the ledger as you go, in `.veris/MEASUREMENTS.md`, one row per probe:

| claim | request | response | rules in / rules out |
|---|---|---|---|

A finding becomes a row the moment it is found. The design cites rows. A
design that contradicts a row in its own ledger is visible; one that
contradicts a measurement eighty tool calls back is not.

## The ladder — stop at the first rung that answers

| rung | what it answers |
|---|---|
| `GET {control_url}/veris/manual` | the vendor's own contract: what makes a repeated write safe, API version, credentials, which errors you can inject |
| `GET {control_url}/veris/schema` | what the vendor stores, table by table, each in its own words — including the rule that governs a table |
| a probe | everything else: send it twice, exceed the limit, exhaust the page, and read what came back |
| **make the failure happen** | what the failure this task is about *looks like*. Arm a fault row through `POST {control_url}/veris/data` and drive the real call through it |
| **read it back** | `GET {control_url}/veris/requests` — what your client actually sent, header and path; `GET {control_url}/veris/data?entity_type=<name>` — what the vendor stored |

The fault shapes that cover most reports (the testing guide §4 has the full
contract):

| the report says | the fault row |
|---|---|
| the response never came back, but the write happened | `"outcome":"hang"` (or an `error` with a 5xx) with `"phase":"after"` |
| we got throttled | `"outcome":"error","error":{"status":429,"code":"<listed-code>","headers":{"Retry-After":"2"}},"remaining":2` |
| the record vanished mid-flow | `"outcome":"error","error":{"status":404,...},"remaining":1` |
| it was slow enough to time out | `"latency_ms": <n>` |

Match on the request the task names (`"method"`, `"path"`, and `"match"` on
body or query fields); copy the path from `/veris/requests` when an SDK hides
it; `"remaining":1` consumes the fault once.

A probe beats every document, including the vendor's. Documents describe
intent; the sandbox is the behaviour. Read the two documents first anyway —
they are one call each and routinely answer the question outright.

## Then carry it

Write the measured answer into the design decision and into the change
description — *"verified against the dependency: a repeat returns the first
response"* — with the ledger row it came from. A reviewer can check a
measurement. A reviewer cannot check an assumption, and neither can you six
months later.

## Common mistakes

- **Designing first, then reaching for the sandbox to confirm.** By then the
  only question left is "does my code work", and the sandbox answers it —
  correctly, and uselessly.
- **Finding the answer and not acting on it.** A line in the manual that
  contradicts the brief is a probe to run now, not a note for the pull
  request.
- **Reading the vendor's public docs instead of running it.** Docs omit,
  drift, and describe the general case. The failure you care about is
  specific.
- **Treating the brief's premise as the problem statement.** It is part of the
  proposal, and proposals contain assumptions.

**NEXT:** once the change exists, `integration-testing` verifies it against the
sandbox with proof the traffic arrived, through the same failure you made
happen here.
