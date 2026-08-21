# Receiving webhooks

The proxy routes your code OUT; a webhook comes back IN, and a sandbox in the
cluster cannot reach an app on your laptop. `--expose <port>` (the port your
app listens on) opens a public tunnel and registers it with the sandbox. The
app shares the proxy's port space, and 8080/8081/8443 are the proxy's own
listeners — `--expose 8080` is refused; have the app listen elsewhere
(e.g. 3000).

`--require-callback <path>[:count]` (or `'*'`) asserts delivery the same way
`--require-service` asserts egress — a webhook suite that received nothing
must not pass. Your app is handed `VERIS_PUBLIC_URL` and registers it with
the vendor through the vendor's own API, because that registration call is
also code under test. Combine with `--environment` so concurrent runs cannot
overwrite each other's callback URL.

When inbound HTTP is unavailable, the sandbox still records what it would have
sent: read `deliveries` and `delivery_attempts` through `/veris/data`, and add
`delivery_rules` before the triggering action to suppress or delay delivery.
