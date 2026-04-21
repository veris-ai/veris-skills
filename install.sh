#!/usr/bin/env bash
# Install the veris-skills agent-integration skill into any supported coding agent.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/veris-ai/veris-skills/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/veris-ai/veris-skills/main/install.sh | bash -s -- --target claude
#   ./install.sh                         # from a local clone
#   ./install.sh --target codex,cursor   # restrict to specific harnesses
#
# Supported targets: claude, codex, cursor, all (default: autodetect)

set -euo pipefail

REPO_URL="https://github.com/veris-ai/veris-skills.git"
SKILL_NAME="agent-integration"

TARGET_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_FLAG="$2"; shift 2 ;;
    --target=*) TARGET_FLAG="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }

detect_harnesses() {
  local found=()
  if command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then
    found+=("claude")
  fi
  if command -v codex >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]]; then
    found+=("codex")
  fi
  if command -v cursor-agent >/dev/null 2>&1 || [[ -d "$HOME/.cursor" ]] \
     || [[ -d "$HOME/Library/Application Support/Cursor" ]] \
     || [[ -d "$HOME/.config/Cursor" ]]; then
    found+=("cursor")
  fi
  printf '%s\n' "${found[@]}"
}

resolve_targets() {
  if [[ -z "$TARGET_FLAG" ]]; then
    local detected
    detected=$(detect_harnesses)
    if [[ -z "$detected" ]]; then
      warn "Could not auto-detect any coding agent. Re-run with --target claude|codex|cursor|all"
      exit 1
    fi
    echo "$detected"
  elif [[ "$TARGET_FLAG" == "all" ]]; then
    printf 'claude\ncodex\ncursor\n'
  else
    tr ',' '\n' <<< "$TARGET_FLAG"
  fi
}

install_dir_for() {
  case "$1" in
    claude) echo "$HOME/.claude/skills/$SKILL_NAME" ;;
    codex)  echo "$HOME/.codex/skills/$SKILL_NAME" ;;
    cursor) echo "$HOME/.cursor/skills/$SKILL_NAME" ;;
    *) echo ""; return 1 ;;
  esac
}

get_source_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [[ -n "$script_dir" && -f "$script_dir/SKILL.md" ]]; then
    echo "$script_dir"
    return
  fi
  local tmp
  tmp=$(mktemp -d)
  log "Cloning $REPO_URL into $tmp"
  git clone --depth 1 "$REPO_URL" "$tmp" >/dev/null
  echo "$tmp"
}

install_one() {
  local harness="$1"
  local src="$2"
  local dest
  dest=$(install_dir_for "$harness") || { warn "unknown target: $harness"; return 1; }

  if [[ -e "$dest" ]]; then
    warn "$dest already exists — removing and reinstalling"
    rm -rf "$dest"
  fi
  mkdir -p "$(dirname "$dest")"

  log "Installing into $dest"
  (cd "$src" && tar cf - \
      SKILL.md agents phases reference templates 2>/dev/null) \
    | (mkdir -p "$dest" && cd "$dest" && tar xf -)

  ok "Installed for $harness"
}

main() {
  local targets
  targets=$(resolve_targets)
  log "Targets: $(echo "$targets" | paste -sd ',' -)"

  local src
  src=$(get_source_dir)

  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    install_one "$t" "$src"
  done <<< "$targets"

  echo
  ok "Done. Invoke the skill with: /agent-integration path/to/agent/repo"
}

main "$@"
