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
failed=0
for name in "${EXTENSIONS[@]}"; do
  src="npm:@narumitw/$name"
  # Match the entry pinned or not; object-form entries carry it in .source.
  # npm-source-only: a git: or local-path install of the same extension won't match.
  rc=0
  jq -e --arg src "$src" '
      (.packages // []) | map(if type == "object" then .source else . end)
      | map(select(type == "string"))
      | any(. == $src or startswith($src + "@"))' "$SETTINGS" >/dev/null || rc=$?
  case "$rc" in
    0)
      echo "Skip: $src already in packages"
      skipped=$((skipped + 1))
      ;;
    1)
      if pi install "$src"; then
        installed=$((installed + 1))
      else
        echo "Warning: pi install $src failed — continuing."
        failed=$((failed + 1))
      fi
      ;;
    *)
      echo "Error: could not read \`packages\` from $SETTINGS"
      exit 1
      ;;
  esac
done

echo
echo "Extensions: $installed installed, $skipped already present, $failed failed."

echo
if [ -e "$STATUSLINE_CFG" ] || [ -L "$STATUSLINE_CFG" ]; then
  echo "Statusline: $STATUSLINE_CFG already exists — left as-is."
else
  # Shaped after this setup's Claude Code status line (model · effort · ctx% ·
  # #msgs · spend): cwd/branch/time are dropped because Ghostty's tab title and
  # nvim's statusline already carry them, and `cost` stands in for Claude's
  # rate-limit cluster, which has no analog on pay-per-token OpenRouter.
  # Machine-local, not stowed: the /statusline menu rewrites this file, which
  # would break a stow symlink. Write to a temp file and mv so a crash mid-write
  # can't leave a broken file that the [ -e ] guard above would then protect
  # forever.
  tmp="$(mktemp "${STATUSLINE_CFG}.XXXXXX")"
  cat >"$tmp" <<'EOF'
{
  "segments": ["model", "thinking", "context", "turn", "cost"]
}
EOF
  mv "$tmp" "$STATUSLINE_CFG"
  echo "Statusline: seeded $STATUSLINE_CFG (Claude-shaped segment set)."
fi

echo
echo "Verify with: pi list    Update later with: pi update --extensions"

[ "$failed" -eq 0 ] || exit 1
