#!/bin/bash
# One-time setup: register herdr's Claude Code and pi integrations, and drop
# the release-matched herdr agent skill into ~/.claude/skills/. Run after
# `stow --no-folding herdr` and `brew install herdr`.
#
# Idempotent — safe to re-run any time, and REQUIRED after every
# `brew upgrade herdr` (the skill and the integration hook script are
# release-matched but deliberately not tracked in this repo — see the Herdr
# README section's "What's managed").
#
# Claude integration: the portable SessionStart registration is tracked in
# the stowed settings file. Herdr's release-matched hook script is generated
# under an isolated temporary HOME, then installed into the real ~/.claude.
# This keeps the external installer away from the git-tracked settings file.
#
# pi integration: `herdr integration install pi` only writes
# ~/.pi/agent/extensions/herdr-agent-state.ts (no settings.json edit — same as
# this repo's stowed claude-footer.ts / nvim-notify.ts extensions, which also
# load without a `packages` entry). Machine-local, not tracked.

set -euo pipefail

if ! command -v herdr >/dev/null 2>&1; then
  echo "Error: herdr not found. Run 'brew install herdr' (see Brewfile) first."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$ROOT/claude/.claude/settings.json"
"$ROOT/claude/setup-settings.sh" --check

if [ ! -d "$HOME/.pi/agent" ]; then
  echo "Error: $HOME/.pi/agent not found."
  echo "Run 'stow --no-folding pi' from the repo root first, then re-run this script."
  exit 1
fi

# --- Claude integration ------------------------------------------------
HERDR_COMMAND='if command -v herdr >/dev/null 2>&1; then bash $HOME/.claude/hooks/herdr-agent-state.sh session; fi'
if ! jq -e --arg command "$HERDR_COMMAND" '
  ([.hooks.SessionStart[]?.hooks[]?
    | select((.command // "") | contains("herdr-agent-state.sh"))] | length) == 1
  and
  ([.hooks.SessionStart[]?
    | select(.matcher == "*" and .timeout == null)
    | .hooks[]?
    | select(.type == "command" and .command == $command and .timeout == 10)] | length) == 1
' "$SETTINGS" >/dev/null; then
  echo "Error: tracked settings must contain exactly one canonical Herdr SessionStart hook." >&2
  exit 1
fi

echo "Generating the release-matched Herdr Claude hook in an isolated HOME..."
TMP_HOME="$(mktemp -d)"
cleanup() { rm -rf "$TMP_HOME"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_HOME/.claude"
HOME="$TMP_HOME" CLAUDE_CONFIG_DIR="$TMP_HOME/.claude" herdr integration install claude
GENERATED_HOOK="$TMP_HOME/.claude/hooks/herdr-agent-state.sh"
if [ ! -f "$GENERATED_HOOK" ]; then
  echo "Error: Herdr did not generate $GENERATED_HOOK" >&2
  exit 1
fi
if grep -Fq "$TMP_HOME" "$GENERATED_HOOK"; then
  echo "Error: generated Herdr hook embeds its temporary HOME; refusing to install it." >&2
  exit 1
fi
mkdir -p "$HOME/.claude/hooks"
install -m 755 "$GENERATED_HOOK" "$HOME/.claude/hooks/herdr-agent-state.sh"
cleanup
trap - EXIT HUP INT TERM

# --- pi integration ------------------------------------------------------
echo "Installing herdr pi integration..."
herdr integration install pi

# --- Agent skill -----------------------------------------------------------
# Regenerated unconditionally (single fast command) so it can't drift from the
# installed herdr release across upgrades.
mkdir -p "$HOME/.claude/skills/herdr"
herdr --skill > "$HOME/.claude/skills/herdr/SKILL.md"
if ! head -1 "$HOME/.claude/skills/herdr/SKILL.md" | grep -q '^---$'; then
  echo "WARNING: herdr --skill output has no YAML frontmatter — the skill" >&2
  echo "may not load. Check 'herdr --skill' output for this release." >&2
fi

echo
echo "Done. herdr integration status:"
herdr integration status | grep -E '^(claude|pi):'
echo
echo "The tracked Claude settings were validated but not modified."
