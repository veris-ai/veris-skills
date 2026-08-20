---
name: discovering-vendor-behavior
description: Use when designing or changing code whose correctness depends on how an external service behaves — retries, duplicate writes, concurrency, error responses, rate limits, pagination, webhooks — and before writing code that works around a limitation of that service. Use when an issue, a comment, a docstring or a teammate asserts what a vendor does or does not support.
---

Find out what the dependency does before you design around it.

A Veris sandbox is a stateful twin of the service this code calls. It answers
questions no amount of reading the codebase can: what the vendor returns on a
repeat, what it does when a response is lost, which of two designs it makes
unnecessary. Those answers are cheap here and expensive in production.

## Core principle: a dependency's contract is measurable, so measure it

The design you choose is a claim about the dependency. If the claim is wrong,
every test you write still passes — you will be testing your workaround, not
the behaviour it was meant to protect.

## Answer these before the design is fixed

**1. What does the vendor already offer for this?**
Retry safety, conditional writes, cursors, filters, batch endpoints, webhook
replay — vendors carry more than their client libraries expose. A guard you
hand-roll around a missing capability is worse than the capability, and you
own it forever.

**2. What does the vendor actually do in the failure this change is about?**
Not what it should do. Run it: send the duplicate, lose the response, exhaust
the page, expire the token. Faults exist so the failure is observable rather
than imagined.

**3. Which assertions about the vendor am I inheriting?**
Issues, comments and docstrings carry sentences like *"the API has no X"*,
*"it always returns Y"*, *"there is no way to Z"*. Each one is a claim someone
made, often without checking. One probe settles it. Inheriting it wrong
constrains the whole change.

## Where this sits

    learn the dependency  →  choose the design  →  write it  →  verify it
    ^^^^^^^^^^^^^^^^^^^^                                        ^^^^^^^^^
    this skill                                        integration-testing

The first step is the one that gets skipped, because nothing forces it and the
code compiles without it.

## The ladder — stop at the first rung that answers

Everything below is served **by the service**, so a sandbox has to exist
first. That is three calls and a poll, and it is the whole reason this gets
put off until "verification time" — do it now anyway, at the start, where the
answers can still change the design:

    get_environment → create_sandbox → get_sandbox (poll to ready)

`get_sandbox` returns each service's `url` and `control_url`. Use
`control_url` for every `/veris/*` path.

| rung | what it answers |
|---|---|
| `GET {control_url}/veris/manual` | the vendor's own contract: what makes a repeated write safe, API version, credentials, which errors you can inject |
| `GET {control_url}/veris/schema` | what the vendor stores, table by table and column by column, each in its own words — including the rule that governs a table |
| a probe against that sandbox | everything else: send the request twice, lose a response, exhaust the page, and read what came back |

A probe beats every document, including the vendor's. Documents describe
intent; the sandbox is the behaviour. But read the two documents first — they
are one HTTP call each against a sandbox you now have, and they routinely
answer the question outright.

## Then carry it

Write the measured answer into the design decision and into the change
description: *"verified against the dependency: a repeat returns the first
response"*. A reviewer can check a measurement. A reviewer cannot check an
assumption, and neither can you six months later.

## Common mistakes

- **Designing first, then reaching for the sandbox to confirm.** By then the
  only question left is "does my code work", and the sandbox answers it —
  correctly, and uselessly.
- **Reading the vendor's public docs instead of running it.** Docs omit,
  drift, and describe the general case. The failure you care about is specific.
- **Treating the brief's premise as the problem statement.** It is part of the
  proposal, and proposals contain assumptions.

**NEXT PHASE:** once the change exists, use `integration-testing` to verify it
against the sandbox with proof the traffic arrived.
