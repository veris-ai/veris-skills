# Troubleshooting

Read this before forming any theory about a failure. Most "sandbox bugs"
are harness bugs, and the evidence to tell them apart is already recorded.

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
   theory**, and reproduce the failing exchange with curl before blaming
   the sandbox, the proxy, or the code.
3. Only then reason about the code under test.

## An empty receipt

The run exits 3 on its own when an `--environment` run sent the sandbox
nothing — deploying a sandbox for a suite that never called it is a failure,
not a pass. Causes worth checking, in order: the suite genuinely never calls
its dependency (mocks still active, tests filtered out); the traffic went to
the real vendor because the host is not in the environment's service map;
or TLS trust failed inside the workload (next section) so no request ever
completed.

## Exit codes

- The command's own status: the tests' verdict, trustworthy only alongside
  the receipt.
- `3`: the run never proved its traffic — empty receipt, an unmet
  `--require-service` / `--require-callback`, or a mapped host whose TLS
  handshakes were all rejected (next section).
- `4`: outcome indeterminate. Treat as failure, never as success.

## SDKs that bundle their own CA

The kernel redirect moves the *traffic* below every library, but *trust* is
still decided inside the process: an SDK that ships its own CA bundle and
hands it straight to the TLS layer (stripe-python and stripe-ruby, older
botocore, httplib2) reads none of the trust environment and refuses the
proxy's certificate even though routing worked.

- **The symptom**: `CERTIFICATE_VERIFY_FAILED` / `SSLError` / "unable to get
  local issuer certificate" against a *mapped* host, in container mode, while
  other services intercept fine. **stripe-python hides the cause**: it wraps
  the TLS failure as `APIConnectionError` ("Network error: A ConnectError
  was raised" / "Could not verify Stripe's SSL certificate") — none of the
  usual certificate strings, so treat any connection-shaped SDK error against
  a mapped host as possibly this. The proxy prints "N TLS handshakes
  rejected … after the certificate was minted" for the host; that line
  **is** the diagnosis — it is not a sandbox bug, not a routing bug, and no
  amount of re-running changes it.
- **The absence of that line is NOT evidence against a trust failure.** On
  proxy versions before the mixed-traffic fix, any completed request on the
  host — including your own `/veris/*` control-plane reads, which honour
  `SSL_CERT_FILE` and so trust the proxy fine — suppressed the diagnostic
  *and* counted toward `--require-service`, so a run whose every SDK call
  failed TLS could still print a healthy receipt and exit 0. Current
  versions count `/veris/*` reads apart from service traffic and print the
  rejection even beside completed requests. Either way: when the SDK
  reports a connection error but the receipt shows traffic, check whether
  that traffic is your harness (`{control_url}/veris/requests` shows the
  paths) before concluding the network is at fault.
- **The fix, for a known SDK: `--patch-bundled-cas`.** Add the flag to the
  `veris-proxy run` command — and when the dependency set names one of the
  offenders, add it **up front** rather than after a failure (the running
  phase says the same). It scans the image and your `-v` mounts for the
  bundled CA files the common offenders ship — certifi, pip's vendored
  certifi, botocore, stripe (Python and Ruby), httplib2 — appends the Veris
  CA to a copy of each, and over-mounts the copy read-only over its own path.
  The SDK keeps loading its own bundle through its own code path; the file
  just carries one more root. The run logs one line per file it patched, and
  a bundle it finds but cannot read fails the run loudly rather than shipping
  it unpatched. The flag is experimental and its scan list is deliberately
  narrow, so it is the first thing to try, not a guarantee of coverage.
- **The fallback, for an SDK it does not know: over-mount by hand.** Same
  move, done yourself. Locate the SDK's bundled CA file — in the image or in
  the bind-mounted venv/node_modules — copy it out, append
  `~/.veris/ca/veris-ca.pem`, and mount the copy back over the original by
  adding `-v "$PWD/.veris-trust/patched.crt:/exact/container/path:ro"` to the
  run command. Keep the patched copy under the repo tree (`.veris-trust/`,
  gitignored or committed as the team prefers) so a persisted invocation
  stays inside the mount sources preflight step 6 allows. (Appending, never
  replacing: a file holding only the Veris CA breaks the SDK's real-vendor
  trust for every passthrough host.) It is trust data, never code — which is
  why both forms are legitimate and the in-code alternatives below are not.
- **Never reach for the in-code alternatives** — setting the SDK's CA/verify
  options in test code, monkey-patching `ssl`, or disabling verification.
  Each one modifies the code path under test, which is the line this skill
  never crosses.
- **Hard pinning is a boundary, not a puzzle.** An SDK that pins SPKI hashes
  or certificate fingerprints (OkHttp `CertificatePinner`, curl
  `--pinnedpubkey`, aiohttp `fingerprint=`, urllib3 `assert_fingerprint`)
  runs a second comparison after chain validation that no added root can
  satisfy. Stop and report it to the user rather than fighting it.
