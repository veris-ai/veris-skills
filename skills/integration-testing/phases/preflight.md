# Phase 0 — Preflight (once per environment)

Work through these gates in order. Each is check-first: if it already holds,
move on silently. Ask before installing anything.

## 1. API key

`VERIS_API_KEY` must be set in the environment. If it is missing, stop and ask
the user for it — it arrives out of band (Veris console or their team) and you
must never write it into any file in the repo. `VERIS_API_BASE` names the
control plane base URL; it defaults to `https://api.veris.ai`, so set it only
when the user's team runs elsewhere.

## 2. Veris MCP server

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

## 3. Generic client testing guide

Once the MCP server is connected, call `get_testing_guide` and read the
returned guide fully before creating a sandbox or planning tests. It is the
client-facing authority on sandbox mechanics: seeding, resets, fault
injection, time control, callbacks, and diagnosis.

## 4. veris-proxy binary

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

## 5. Docker, and the proxy's runner image

Container mode needs `docker` on PATH and a logged-in gcloud
(`gcloud auth login`) — the proxy's own image is pulled automatically from
Veris's registry using that login. If the pull still answers 401, docker is
not wired to gcloud yet: `gcloud auth configure-docker
us-central1-docker.pkg.dev` (once). This goes away when the image becomes
publicly pullable.

If docker is genuinely unavailable (some CI shapes, a machine without a
daemon), stop and tell the user — this skill does not run without the
container tier.

## 6. Make the tests runnable in a container

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

## 7. Read the service manuals and prepare the default world

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
