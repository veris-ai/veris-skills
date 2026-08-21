# Worlds: the sandbox per run, reset, promote, snapshots

## The sandbox is the proxy's

`--environment <env_id>` makes the proxy deploy a fresh sandbox, run against
it, and delete it when the run ends; `--ttl-minutes` backstops a run that dies
without one. A sandbox per run is hermetic, and for webhook tests it is also
the safe shape — two runs sharing a sandbox would overwrite each other's
callback registration. Ending the run is the teardown. Leave nothing running:
an interrupted session left in the background is a sandbox still alive that a
later session could accidentally trust.

## Reset

`reset_sandbox` (with the run's logged sandbox id) between suites for a fresh
coherent world — never mid-test. It atomically restores every service and the
shared clock; snapshot `/veris/requests` first, because every reset replaces
request history. A direct `POST {control_url}/veris/reset` resets only that
service: `{"profile":"default"}` restores its packaged data, `{"data":{...}}`
loads exact rows, and a body with neither may produce an empty dataset.

A sandbox booted from an image — a promoted environment's baseline, or a
snapshot — **refuses `reset_sandbox` with 409**: reseeding profiles would
silently replace that world. Delete and recreate it instead.

## Keeping a world a session built

What the tests need is discovered by writing them, so the world worth keeping
usually exists only at the end of a live session. Two ways to keep it, chosen
by who should start from it:

- **Every future run** → `promote_sandbox` with the run's sandbox id, before
  the run ends. Promotion copies the world into the environment's default;
  every later `create_sandbox`, including the proxy's per-run ones, starts
  from it, so the teardown that follows loses nothing. The capture is a
  boundary — the sandbox is left frozen and scrubbed — so it is the last
  thing done with it.
- **Only some runs** — an empty account and a populated one, a trial and an
  expired trial — → a named **snapshot**. Promoting one of them would
  silently change what every other suite starts from.

  ```sh
  # after seeding + verifying a world, from the same live sandbox
  curl -X POST "$VERIS_API_BASE/v1/environments/$VERIS_ENVIRONMENT_ID/snapshots" \
    -H "X-API-Key: $VERIS_API_KEY" -H 'Content-Type: application/json' \
    -d '{"sandbox_id":"'"$SANDBOX_ID"'","name":"expired-trial"}'
  curl -s "$VERIS_API_BASE/v1/environments/$VERIS_ENVIRONMENT_ID/snapshots" -H "X-API-Key: $VERIS_API_KEY"
  ```

  Many snapshots per environment; the default boot is unchanged.
  `create_sandbox` takes an optional `snapshot_id`, and an explicit snapshot
  beats the environment's baseline pin. Snapshot management — create, list,
  delete — is HTTP-only; only the boot side is on MCP. A snapshot cannot be
  deleted while a sandbox booted from it is alive; that delete answers 409
  until the sandbox is gone.

Either way: read every service's manual, seed per the manual and
`/veris/schema`, **verify the world reads back the way the tests expect**,
and only then keep it. A kept world that was seeded wrongly is worse than
none, because every later boot inherits it.
