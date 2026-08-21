# The verification section of a change description

Fill every heading. A heading with nothing under it is information too.

```markdown
## What I verified, and how

<For each claim the change rests on: the run that showed it, the receipt line
(`<service> <n> requests`), and where the evidence is — a ledger row in
.veris/MEASUREMENTS.md, a request in /veris/requests, a row in /veris/data.>

- **The failure, reproduced:** <the fault armed, the flow driven, the wrong
  outcome observed — before any code changed>
- **The fix, through the shipping path:** <the same flow, green, from the
  boundary the task names; receipt from that run>
- **What the vendor recorded:** <the /veris/data or /veris/requests read-back
  that shows the change did what it claims, not a layer below it>

## What I am assuming rather than verifying

<Every behaviour the design relies on that has no measurement behind it —
including anything remembered from vendor documentation — and why it is
acceptable to assume it. A measurement in the ledger that points the other
way belongs here, stated, not omitted.>

## Limitations and risks

<What the change does not cover; what a caller could still do wrong; what
depends on a vendor setting this sandbox could not exercise.>
```

Before writing it, read `.veris/MEASUREMENTS.md` against the design. A row
that contradicts a design decision is either a decision to revisit or a line
under *assuming rather than verifying* — never silence.
