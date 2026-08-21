# Troubleshooting

Read this before forming any theory about a failure. Most "sandbox bugs" are
harness bugs, and the evidence to tell them apart is already recorded.

## First moves, in order

1. **Read the receipt.** It says what the sandbox actually received, per
   service. A green suite with an empty receipt is not a pass; a red suite
   whose receipt shows the traffic arrived is a real integration finding.
   Current proxies list `/veris/*` control-plane reads on their own line,
   excluded from the service counts; on older proxies they fold into the
   service counts, so a receipt can be entirely your own harness — confirm
   the paths in `{control_url}/veris/requests` before trusting it.
2. **Read `{control_url}/veris/requests`** for the run's sandbox — the wire
   trace of every request and response. Check it **before forming a
   theory**, and reproduce the failing exchange with curl before blaming the
   sandbox, the proxy, or the code.
3. **Read `{control_url}/veris/data?entity_type=<name>`** for what the vendor
   actually stored — the row your create produced, the replay the vendor
   recorded, the state the callback left.
4. Only then reason about the code under test.

## An empty receipt

The run exits 3 on its own when an `--environment` run sent the sandbox
nothing — deploying a sandbox for a suite that never called it is a failure,
not a pass. Causes worth checking, in order: the suite genuinely never calls
its dependency (mocks still active, tests filtered out); the traffic went to
the real vendor because the host is not in the environment's service map; or
TLS trust failed inside the workload ([trust.md](trust.md)) so no request ever
completed.

## Exit codes

- The command's own status: the tests' verdict, trustworthy only alongside
  the receipt.
- `3`: the run never proved its traffic — empty receipt, an unmet
  `--require-service` / `--require-callback`, or a mapped host whose TLS
  handshakes were all rejected ([trust.md](trust.md)).
- `4`: outcome indeterminate. Treat as failure, never as success.

## Vendor-shaped errors

- A vendor-shaped `4xx`: read the response and `/veris/requests`. It is
  usually the real error for the request you sent.
- `501` from a vendor path: a sandbox coverage gap. Record it for the user;
  do not change correct production client behaviour to work around it.
- A bare `500`: capture the request and the trace as a sandbox defect.
- Widespread `502`: check sandbox status and expiry.
- A timeout: check armed faults, whether the request reached the trace, and
  the client's per-request timeout — an error path can be much slower than a
  success path.
