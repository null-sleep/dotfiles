#!/bin/bash
# One-time setup: seed this machine's ~/.omp/agent/config.yml with the repo's
# omp defaults — the OpenRouter Sonnet default model role, thinking level,
# quiet startup, and the repo-owned theme/status-line look.
#
# config.yml is deliberately NOT stowed. omp *writes* to it: `/settings` edits,
# migrations, and runtime state land there, so a stowed symlink would send all
# of that straight into this repo — the same split as pi's settings.json. This
# script drives `omp config` instead of editing the YAML directly.
#
# Idempotent: fill-in keys are only set when untouched, so a model or thinking
# level you later change by hand survives a re-run. Untouched-detection:
#   • modelRoles.default — key presence in the record (robust).
#   • defaultThinkingLevel / startup.quiet — current effective value equals the
#     schema default ("high" / false). `omp config get` merges defaults, so an
#     explicit hand-set schema default is indistinguishable from unset and gets
#     our value; accepted tradeoff. Re-runs are no-ops because the seeded
#     values differ from the schema defaults.
# The theme and status-line keys are *forced* (repo-owned, like pi's theme
# slot): a drifted value gets corrected rather than kept.
#
# Usage:
#   bash ~/src/dotfiles/omp/setup-settings.sh

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v omp >/dev/null 2>&1; then
  echo "Warning: omp is not on PATH — install it first:"
  echo "  brew install can1357/tap/omp"
  echo "Nothing to do without the CLI (the config store is YAML, written via"
  echo "\`omp config\`). Re-run this script after installing."
  exit 0
fi

# Run from $HOME so a project-level .omp/config.yml can't shadow the reads
# (writes always go to the global layer, but `config get` is effective-value).
cd "$HOME"

DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-5"

get() { omp config get "$1" --json | jq -r '.value'; }

# Fill-in-only defaults (see header for the untouched-detection rules).
roles="$(omp config get modelRoles --json | jq -c '.value // {}')"
if [ "$(jq -r 'has("default")' <<<"$roles")" = "false" ]; then
  omp config set modelRoles "$(jq -c --arg m "$DEFAULT_MODEL" '. + {default: $m}' <<<"$roles")"
else
  echo "modelRoles.default already set — left as-is."
fi

if [ "$(get defaultThinkingLevel)" = "high" ]; then
  omp config set defaultThinkingLevel medium
else
  echo "defaultThinkingLevel already customized — left as-is."
fi

if [ "$(get startup.quiet)" = "false" ]; then
  omp config set startup.quiet true
else
  echo "startup.quiet already set — left as-is."
fi

# Forced, repo-owned look: dark/light theme pair and the custom status line.
omp config set theme.dark dark-dracula
omp config set theme.light light-catppuccin
omp config set statusLine.preset custom
omp config set statusLine.separator none
omp config set statusLine.transparent true
omp config set statusLine.leftSegments '["model","context_pct","cache_hit"]'
omp config set statusLine.rightSegments '["cost"]'

# Known collision: omp's claude discovery provider merges ~/.claude/settings.json
# over the global config, and its flat `"theme": "custom:active"` (Claude Code's
# theme slot) migrates into theme.dark. The global YAML above is correct; the
# effective value is shadowed until upstream scopes that import.
if [ "$(get theme.dark)" != "dark-dracula" ]; then
  echo
  echo "Warning: effective theme.dark is '$(get theme.dark)', not dark-dracula —"
  echo "shadowed by ~/.claude/settings.json's theme key via omp's claude provider."
fi

echo
echo "Resulting omp config:"
for key in modelRoles defaultThinkingLevel startup.quiet theme.dark theme.light \
  statusLine.preset statusLine.separator statusLine.transparent \
  statusLine.leftSegments statusLine.rightSegments; do
  echo "  $key = $(omp config get "$key" --json | jq -c '.value')"
done

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`omp\`."
