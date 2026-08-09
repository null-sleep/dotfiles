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
# you've since removed the pin from, repinned, or reconfigured. The old
# pi-statusline package is removed because the stowed claude-footer extension
# now owns the footer; two setFooter() extensions would race.
#
# Usage:
#   bash ~/src/dotfiles/pi/setup-extensions.sh

set -euo pipefail

SETTINGS="$HOME/.pi/agent/settings.json"

EXTENSIONS=(
  pi-lsp        # lsp_diagnostics/lsp_fix tools; uses servers already on PATH
  pi-subagents  # /subagents — delegate isolated work to child pi processes
  pi-plan-mode  # /plan — read-only planning mode (tool-gated)
  pi-github-pr  # ambient current-branch PR status via gh
  pi-usage      # /usage — OpenRouter per-key spend
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

# Migrate machines configured before the repo-owned minimal footer replaced the
# third-party powerline. Match pinned and object-form package entries too.
if jq -e '
    (.packages // []) | map(if type == "object" then .source else . end)
    | map(select(type == "string"))
    | any(. == "npm:@narumitw/pi-statusline" or startswith("npm:@narumitw/pi-statusline@"))
  ' "$SETTINGS" >/dev/null; then
  echo
  echo "Removing pi-statusline (replaced by stowed claude-footer.ts)..."
  pi remove npm:@narumitw/pi-statusline
fi
rm -f "$HOME/.pi/agent/pi-statusline.json"

echo
echo "Verify with: pi list    Update later with: pi update --extensions"

[ "$failed" -eq 0 ] || exit 1
