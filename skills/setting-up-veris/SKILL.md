---
name: setting-up-veris
description: Wires a repository to a Veris dependency sandbox so its tests can run under veris-proxy - checks the credential, MCP server, binary and docker, derives a test image, records the run command in .veris/run.sh and .veris/setup.json, and proves the wiring with one smoke run whose receipt is non-empty. Use when a repo has no .veris/ directory, when .veris/setup.json no longer matches the repo, or when another skill needs a sandbox and none is wired yet.
---

Wire this repository to a Veris dependency sandbox, once.

The sandbox is a set of stateful twins of the services this code calls. The
code is **never modified and never told**: it keeps its production hostnames,
credentials and client stack, and `veris-proxy` reroutes its outbound HTTP(S)
into the sandbox from outside the process. This skill builds the things that
make that one command work and leaves them in the tree, so no later session
re-derives them:

| artifact | what it records |
|---|---|
| `.veris/run.sh` | the exact `veris-proxy run` invocation — the correct command is a file, not a composition |
| `.veris/setup.json` | the same facts as data: environment id, image tag, workdir, mounts, test command |
| `Dockerfile.veris` | how the tests build into an image, only when deriving that took real work |

**Check first.** Run `scripts/preflight.sh`. If it exits 0 and `.veris/run.sh`
exists, setup is done — say so and stop. Re-run a step only when what it
produced no longer matches the repo (a new runtime, a new system dependency,
a different environment).

## 1. Fix what preflight names

`scripts/preflight.sh` names one missing precondition at a time, with the fix
in the same line. Do exactly that one thing, then run it again. Two of its
answers need the user: the credential (`VERIS_API_KEY` arrives out of band and
never goes into the repo; if the `veris` MCP server is registered, it is that
server's `X-API-Key` header) and which environment to test against. Installing
the binary is the one-line installer it names — ask first, and never reinstall
over a working one.

When a precondition cannot be met, stop. No base URL pointed at a sandbox, no
hand-authored `--config`, no tunnel or interception of your own, no run
without `--image`: each turns a missing precondition into a passing suite
whose code path is not the one that ships.

## 2. The MCP server and the testing guide

Sandbox **state** is driven through the `veris` MCP tools: `get_testing_guide`,
`get_environment`, `create_sandbox`, `get_sandbox`, `reset_sandbox`,
`promote_sandbox`, `delete_sandbox`. If they are not available, give the user
this line and stop — a server registered mid-session is not loaded into it,
and raw HTTP against the control plane is not a substitute:

```bash
claude mcp add veris --transport http "$VERIS_API_BASE/mcp" \
  --header "X-API-Key: $VERIS_API_KEY"
```

Once connected, call `get_testing_guide` and read it fully. It is the
authority on sandbox state: seeding, faults, the clock, callbacks, diagnosis.
It is not the authority on transport — where it speaks of replacing base URLs
or setting a variable to a service `url`, the proxy supersedes it.

## 3. Make the tests runnable in a container

Every run uses `--image`, so the tests must run inside one. The image needs
nothing Veris-specific; this is ordinary dockerization and usually no work at
all. [reference/transport.md](reference/transport.md) has the decision table,
the `Dockerfile.veris` rules, and the one uid constraint.

## 4. Record the invocation

Write `.veris/run.sh` — `#!/usr/bin/env sh`, `set -eu`, and one `exec
veris-proxy run --environment "${VERIS_ENVIRONMENT_ID:?}" --image <tag>
<mounts> "$@" -- <test command>`, so extra flags pass through — and
`.veris/setup.json` with `environment_id`, `image`, `dockerfile`, `workdir`,
`mounts`, `test_command`. Both are repo content: a later session reads them
before running them and holds every flag to what this skill would derive
(mount sources under the repo tree or a known dependency cache; nothing that
widens privileges). Tell the user they exist and are worth committing; whether
they enter history is the user's call.

## 5. One smoke run

Run `.veris/run.sh -- <the smallest test that calls the dependency>`. The
proxy prints a **receipt** — what the sandbox received, per service — and an
`--environment` run whose receipt is empty exits 3 on its own.

**Setup is complete when the receipt names the environment's services.** A
connection or certificate error against a mapped host on this run is the one
transport failure that survives a correct setup: an SDK that bundles its own
CA. `integration-testing` carries the diagnosis and the two-retry fix.

## Not here

Seeding or promoting a world. What the tests need is discovered by writing
them; worlds are kept from live runs, in `integration-testing`.

## Ask before

Installing the binary, registering the MCP server, or sending repo code to a
new external destination.
