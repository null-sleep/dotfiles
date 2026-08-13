#!/bin/bash
# One-time setup: seed this machine's ~/.omp/agent/config.yml with the repo's
# omp defaults — the OpenRouter Sonnet default model role, thinking level,
# quiet startup, local memory, and the repo-owned theme/status-line look.
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
# The memory backend, theme, status-line, and web-search keys are *forced*
# (repo-owned, like pi's theme slot): drifted values are corrected.
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

# Run from an empty dir so nothing shadows the effective-value reads: a
# project-level .omp/config.yml would, and $HOME is worse — there omp's claude
# provider merges ~/.claude/settings.json as project-level config (its flat
# `theme` key shadows theme.dark). Writes always go to the global layer.
cd "$(mktemp -d)"

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
# Thinking level rides the model segment. omp defaults it on (the check is
# `!== false`), so pin it: the forced block should own the look, not a default.
omp config set statusLine.segmentOptions '{"model":{"showThinkingLevel":true}}'

# Forced web-search policy: anonymous Perplexity first, then the keyless
# aggregate tier; never the Anthropic OAuth backend, even as a fallback.
omp config set providers.webSearchOrder '["perplexity","public"]'
omp config set providers.webSearchExclude '["anthropic"]'

# Forced memory policy: keep cross-session knowledge in inspectable,
# project-scoped summaries rather than a retrieval database or remote service.
omp config set memory.backend local

echo
echo "Resulting omp config:"
for key in modelRoles defaultThinkingLevel startup.quiet memory.backend \
  theme.dark theme.light statusLine.preset statusLine.separator \
  statusLine.transparent statusLine.leftSegments statusLine.rightSegments \
  statusLine.segmentOptions \
  providers.webSearchOrder providers.webSearchExclude; do
  echo "  $key = $(omp config get "$key" --json | jq -c '.value')"
done

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`omp\`."
