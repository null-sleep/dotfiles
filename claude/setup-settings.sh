#!/bin/bash
# Validate or safely migrate ~/.claude/settings.json to this checkout's Stow
# package. Divergent files require the SHA-256 observed during manual review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPECTED="$SCRIPT_DIR/.claude/settings.json"
SETTINGS="$HOME/.claude/settings.json"
MODE="${1:-migrate}"
REVIEWED_SHA="${2:-}"

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage:
  setup-settings.sh
  setup-settings.sh --check
  setup-settings.sh --replace-if-sha256 <sha256>
EOF
  exit 2
}

for command in jq readlink shasum stow; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

case "$MODE" in
  migrate|--check)
    [ -z "$REVIEWED_SHA" ] || usage
    ;;
  --replace-if-sha256)
    [ -n "$REVIEWED_SHA" ] || usage
    [ "$#" -eq 2 ] || usage
    ;;
  *) usage ;;
esac

jq empty "$EXPECTED" >/dev/null 2>&1 || die "tracked settings are invalid JSON: $EXPECTED"

check_link() {
  [ -L "$SETTINGS" ] || die "$SETTINGS is not a symlink; reconcile it with $EXPECTED first"
  [ -e "$SETTINGS" ] || die "$SETTINGS is a dangling symlink"

  local resolved
  resolved="$(readlink -f "$SETTINGS")"
  [ "$resolved" = "$EXPECTED" ] || die "$SETTINGS belongs to another checkout: $resolved"
  jq empty "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is invalid JSON"
}

if [ "$MODE" = "--check" ]; then
  check_link
  echo "Claude settings are stowed from $EXPECTED."
  exit 0
fi

if [ -L "$SETTINGS" ]; then
  check_link
  echo "Claude settings are already stowed from $EXPECTED."
  exit 0
fi

if [ -e "$SETTINGS" ] && [ ! -f "$SETTINGS" ]; then
  die "$SETTINGS exists but is not a regular file"
fi

backup=""
backup_dir=""
live_sha=""
if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is invalid JSON"
  live_sha="$(shasum -a 256 "$SETTINGS" | cut -d ' ' -f 1)"

  if [ "$MODE" = "--replace-if-sha256" ]; then
    [ "$live_sha" = "$REVIEWED_SHA" ] || die "settings changed since review (expected $REVIEWED_SHA, found $live_sha)"
  elif ! jq --slurpfile expected "$EXPECTED" '$expected[0] == .' "$SETTINGS" | grep -qx true; then
    echo "Error: $SETTINGS differs from the tracked settings." >&2
    echo "Review and merge it first, then run:" >&2
    echo "  $0 --replace-if-sha256 $live_sha" >&2
    exit 1
  fi

  backup_dir="$HOME/.claude/backups"
  mkdir -p "$backup_dir"
  backup="$backup_dir/settings.pre-stow.$(date +%Y%m%dT%H%M%S).${live_sha:0:12}.json"
  [ ! -e "$backup" ] || die "backup already exists: $backup"
fi

rollback() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$backup" ] && [ -f "$backup" ]; then
    if [ -e "$SETTINGS" ] || [ -L "$SETTINGS" ]; then
      collision="$backup_dir/settings.concurrent.$(date +%Y%m%dT%H%M%S).json"
      mv "$SETTINGS" "$collision"
      echo "Preserved a concurrently created settings file at $collision." >&2
    fi
    mv "$backup" "$SETTINGS"
    echo "Migration failed; restored $SETTINGS." >&2
  fi
  exit "$status"
}
trap rollback EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$backup" ]; then
  mv "$SETTINGS" "$backup"
  moved_sha="$(shasum -a 256 "$backup" | cut -d ' ' -f 1)"
  [ "$moved_sha" = "$live_sha" ] \
    || die "settings changed during migration (expected $live_sha, moved $moved_sha)"
fi

mkdir -p "$HOME/.claude"
stow --no-folding --target "$HOME" --dir "$ROOT" claude
check_link

trap - EXIT HUP INT TERM
if [ -n "$backup" ]; then
  echo "Claude settings are now stowed from $EXPECTED."
  echo "Previous settings retained at $backup."
else
  echo "Claude settings are now stowed from $EXPECTED."
fi
