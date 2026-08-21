#!/usr/bin/env bash
# Asserts the preconditions for `veris-proxy run`, one per line, and exits 2
# at the first one that fails. Written by the setting-up-veris skill; run it
# before every session rather than trusting that setup still holds.
#
#   scripts/preflight.sh            # uses VERIS_ENVIRONMENT_ID and .veris/setup.json
#   scripts/preflight.sh <env-id>   # checks a different environment
set -u

fail() { printf 'preflight: %s — %s\n' "$1" "$2" >&2; exit 2; }
ok()   { printf 'preflight: %-12s ok%s\n' "$1" "${2:+ ($2)}"; }

base="${VERIS_API_BASE:-https://api.veris.ai}"
base="${base%/}"

[ -n "${VERIS_API_KEY:-}" ] \
  || fail credential "export VERIS_API_KEY (if the veris MCP server is registered, it is that server's X-API-Key header value)"
ok credential

command -v veris-proxy >/dev/null 2>&1 && veris-proxy version >/dev/null 2>&1 \
  || fail binary "veris-proxy is not on PATH or does not run"
ok binary "$(veris-proxy version 2>/dev/null | head -1)"

docker version >/dev/null 2>&1 \
  || fail docker "no docker daemon answers; the container tier is the only tier this skill uses"
ok docker

env_id="${1:-${VERIS_ENVIRONMENT_ID:-}}"
[ -n "$env_id" ] \
  || fail environment "export VERIS_ENVIRONMENT_ID or pass an environment id"
body="$(curl -sS -m 20 -H "Authorization: Bearer $VERIS_API_KEY" "$base/v1/environments/$env_id")" \
  || fail environment "control plane $base unreachable"
case "$body" in
  *'"id"'*) ;;
  *) fail environment "control plane refused the key or does not know $env_id: ${body:0:120}" ;;
esac
case "$body" in
  *'"baseline"'*'"image"'*) ok environment "$env_id, promoted world" ;;
  *) ok environment "$env_id, no promoted world — every sandbox boots the stock profile" ;;
esac

if [ -f .veris/setup.json ]; then
  image="$(sed -n 's/.*"image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .veris/setup.json | head -1)"
  if [ -n "$image" ]; then
    docker image inspect "$image" >/dev/null 2>&1 \
      || fail image "$image (named by .veris/setup.json) is not built; docker build -f Dockerfile.veris -t $image ."
    ok image "$image"
  fi
fi
