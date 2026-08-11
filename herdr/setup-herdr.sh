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
# Claude integration: `herdr integration install claude` writes
# ~/.claude/hooks/herdr-agent-state.sh (machine-local, not tracked) and adds a
# SessionStart hook entry to ~/.claude/settings.json. That file is stowed
# (symlinked into this repo), and herdr writes through the symlink rather than
# replacing it — verified safe. What herdr's own re-run does NOT do is
# recognize an already-*guarded* entry as installed, so calling it again after
# we've wrapped the command would append a duplicate, unwrapped entry. This
# script guards against that itself: it only calls the installer when no
# herdr SessionStart hook exists yet, then wraps whatever command it wrote in
# `if command -v herdr …` — matching this repo's existing rtk hook — so a
# machine with the repo stowed but no herdr binary doesn't get a failing
# Claude Code hook. (Running `herdr integration install claude` directly,
# bypassing this script, after that guard is in place WILL append a duplicate
# entry — always come back through this script instead, including after
# upgrades.)
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

SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  echo "Error: no settings.json found at $SETTINGS."
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi
if [ ! -d "$HOME/.pi/agent" ]; then
  echo "Error: $HOME/.pi/agent not found."
  echo "Run 'stow --no-folding pi' from the repo root first, then re-run this script."
  exit 1
fi

# settings.json is stowed (a symlink into the repo): write through the link.
# `mv tmp` onto the link path would replace the LINK with a plain file,
# silently de-adopting the stowed copy. Needs macOS >= 12.3's readlink -f
# (stock older macOS lacks the flag). Same idiom as setup-statusline.sh /
# setup-theme.sh / setup-lsp-plugins.sh.
SETTINGS="$(readlink -f "$SETTINGS")"

# --- Claude integration ------------------------------------------------
herdr_hook_count() {
  jq '[.hooks.SessionStart[]?.hooks[]?.command // empty | select(contains("herdr-agent-state.sh"))] | length' "$SETTINGS"
}

if [ "$(herdr_hook_count)" = "0" ]; then
  echo "Installing herdr Claude Code integration..."
  herdr integration install claude
else
  echo "herdr Claude Code hook already present in $SETTINGS — not re-running the installer (see script header)."
fi

# Guard the hook command so a stowed-but-herdr-less machine doesn't get a
# failing SessionStart hook. Skips entries already wrapped, so this is a
# no-op on a second run.
jq '
  .hooks.SessionStart = ((.hooks.SessionStart // []) | map(
    if (.hooks[0].command // "" | contains("herdr-agent-state.sh"))
       and ((.hooks[0].command // "") | startswith("if command -v herdr") | not)
    then .hooks[0].command |= "if command -v herdr >/dev/null 2>&1; then " + . + "; fi"
    else .
    end
  ))
' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"

if [ ! -L "$HOME/.claude/settings.json" ]; then
  echo "WARNING: $HOME/.claude/settings.json is no longer a symlink — something"
  echo "de-adopted the stowed copy. Recover with:"
  echo "  rm ~/.claude/settings.json && stow --no-folding claude"
  exit 1
fi

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
echo "If the Claude hook entry above changed shape, review the diff in"
echo "claude/.claude/settings.json before committing."
