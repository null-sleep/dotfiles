#!/bin/bash
# One-time setup: install this repo's chosen pi extensions — the @narumitw
# collection (github.com/narumiruna/pi-extensions).
#
# Run AFTER setup-settings.sh: `pi install` registers each extension in
# ~/.pi/agent/settings.json's `packages` array, so pi and the settings file
# must already exist.
#
# Entries are deliberately UNPINNED (npm:@narumitw/<name>, no @version),
# matching this repo's update convention — a designated owner per package
# manager (brew owns opencode, npm owns pi itself). Here the owner is
# `pi update --extensions`; a pinned entry would be silently skipped by it.
#
# Idempotent: an extension already in `packages` (with or without a version
# suffix, string or object form) is skipped, so a re-run never reinstalls one
# you've since removed the pin from, repinned, or reconfigured. The statusline
# config is seeded create-only — delete it and re-run to reseed.
#
# Usage:
#   bash ~/src/dotfiles/pi/setup-extensions.sh

set -euo pipefail

SETTINGS="$HOME/.pi/agent/settings.json"
STATUSLINE_CFG="$HOME/.pi/agent/pi-statusline.json"

EXTENSIONS=(
  pi-lsp        # lsp_diagnostics/lsp_fix tools; uses servers already on PATH
  pi-subagents  # /subagents — delegate isolated work to child pi processes
  pi-plan-mode  # /plan — read-only planning mode (tool-gated)
  pi-github-pr  # ambient current-branch PR status via gh
  pi-usage      # /usage — OpenRouter per-key spend
  pi-statusline # powerline footer; segments seeded below
  pi-btw        # /btw — ephemeral side questions, main context untouched
)

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}
command -v pi >/dev/null 2>&1 || {
  echo "Error: pi is not on PATH — install it first (README → pi)."
  exit 1
}
[ -f "$SETTINGS" ] || {
  echo "Error: $SETTINGS not found — run setup-settings.sh first."
  exit 1
}

installed=0
skipped=0
for name in "${EXTENSIONS[@]}"; do
  src="npm:@narumitw/$name"
  # Match the entry pinned or not; object-form entries carry it in .source.
  if jq -e --arg src "$src" '
      (.packages // []) | map(if type == "object" then .source else . end)
      | any(. == $src or startswith($src + "@"))' "$SETTINGS" >/dev/null; then
    echo "Skip: $src already in packages"
    skipped=$((skipped + 1))
  else
    pi install "$src"
    installed=$((installed + 1))
  fi
done

echo
echo "Extensions: $installed installed, $skipped already present."

echo
if [ -e "$STATUSLINE_CFG" ]; then
  echo "Statusline: $STATUSLINE_CFG already exists — left as-is."
else
  # pi-statusline's upstream default segments plus `cost` — the one field a
  # pay-per-token OpenRouter setup actually wants. Machine-local, not stowed:
  # the /statusline menu rewrites this file, which would break a stow symlink.
  cat >"$STATUSLINE_CFG" <<'EOF'
{
  "segments": ["model", "thinking", "cwd", "branch", "tools", "context", "cost", "time"]
}
EOF
  echo "Statusline: seeded $STATUSLINE_CFG (default segments + cost)."
fi

echo
echo "Verify with: pi list    Update later with: pi update --extensions"
