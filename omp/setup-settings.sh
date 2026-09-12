#!/bin/bash
# One-time setup: seed this machine's ~/.omp/agent/config.yml with the repo's
# OpenRouter and OpenAI Codex model presets, GLM rate-limit fallback chains,
# fallback thinking level, quiet startup, local memory, and the repo-owned theme/status-line look.
#
# config.yml is deliberately NOT stowed. omp *writes* to it: `/settings` edits,
# migrations, and runtime state land there, so a stowed symlink would send all
# of that straight into this repo — the same split as pi's settings.json. This
# script drives `omp config` instead of editing the YAML directly.
#
# Idempotent: fill-in keys are only set when untouched, so assignments or
# settings you later change by hand survive a re-run.
# Untouched-detection:
#   • modelRoles / modelTags / retry.fallbackChains — each missing key is
#     seeded; existing values win.
#   • defaultThinkingLevel / startup.quiet — current effective value equals the
#     schema default ("high" / false). `omp config get` merges defaults, so an
#     explicit hand-set schema default is indistinguishable from unset and gets
#     our value; accepted tradeoff. Re-runs are no-ops after seeding.
# The model cycle, memory backend, theme, status-line, and web-search keys are
# *forced* (repo-owned, like pi's theme slot): drifted values are corrected.
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

DEFAULT_ROLES='{
  "default": "openrouter/openai/gpt-5.6-terra:high",
  "smol": "openrouter/openai/gpt-5.6-luna:xhigh",
  "slow": "openrouter/openai/gpt-5.6-sol:xhigh",
  "vision": "openrouter/openai/gpt-5.6-terra:high",
  "plan": "openrouter/openai/gpt-5.6-sol:high",
  "commit": "openrouter/openai/gpt-5.6-luna:medium",
  "tiny": "openrouter/openai/gpt-5.6-luna:low",
  "task": "openrouter/openai/gpt-5.6-terra:medium",
  "advisor": "openrouter/openai/gpt-5.6-luna:medium",
  "med-vision": "openrouter/openai/gpt-5.6-terra:high",
  "oa-s": "openai-codex/gpt-5.6-luna:high",
  "oa-m": "openai-codex/gpt-5.6-terra:high",
  "oa-l": "openai-codex/gpt-5.6-sol:xhigh",
  "glm-l": "openrouter/z-ai/glm-5.3:max",
  "glm-fast": "openrouter/z-ai/glm-5.3-flash:max"
}'
DEFAULT_MODEL_TAGS='{
  "med-vision": {"name": "med-vision"},
  "oa-s": {"name": "oa-s"},
  "oa-m": {"name": "oa-m"},
  "oa-l": {"name": "oa-l"},
  "glm-l": {"name": "glm-l"},
  "glm-fast": {"name": "glm-fast"}
}'

DEFAULT_FALLBACK_CHAINS='{
  "openrouter/z-ai/glm-5.3": [
    "openrouter/deepseek/deepseek-v4-pro-0813:max",
    "openrouter/qwen/qwen3.8-max:xhigh",
    "openai-codex/gpt-5.6-terra:high"
  ],
  "openrouter/z-ai/glm-5.3-flash": [
    "openrouter/deepseek/deepseek-v4-flash-0731:max",
    "openrouter/qwen/qwen3.8-flash:high",
    "openai-codex/gpt-5.6-luna:high"
  ]
}'

get() { omp config get "$1" --json | jq -r '.value'; }

# Fill-in-only defaults (see header for the untouched-detection rules).
roles="$(omp config get modelRoles --json | jq -c '.value // {}')"
merged_roles="$(jq -c --argjson defaults "$DEFAULT_ROLES" '$defaults + .' <<<"$roles")"
if [ "$merged_roles" != "$roles" ]; then
  omp config set modelRoles "$merged_roles"
else
  echo "modelRoles presets already set — left as-is."
fi

tags="$(omp config get modelTags --json | jq -c '.value // {}')"
merged_tags="$(jq -c --argjson defaults "$DEFAULT_MODEL_TAGS" '$defaults + .' <<<"$tags")"
if [ "$merged_tags" != "$tags" ]; then
  omp config set modelTags "$merged_tags"
else
  echo "modelTags presets already set — left as-is."
fi

fallback_chains="$(omp config get retry.fallbackChains --json | jq -c '.value // {}')"
merged_fallback_chains="$(jq -c --argjson defaults "$DEFAULT_FALLBACK_CHAINS" '$defaults + .' <<<"$fallback_chains")"
if [ "$merged_fallback_chains" != "$fallback_chains" ]; then
  omp config set retry.fallbackChains "$merged_fallback_chains"
else
  echo "retry.fallbackChains presets already set — left as-is."
fi

# Forced model-switcher policy. Alt+O opens a fuzzy picker over this list.
omp config set cycleOrder '["smol","default","slow","tiny","med-vision","oa-s","oa-m","oa-l","glm-l","glm-fast"]'

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
omp config set statusLine.compactThinkingLevel false
# turn_count is not a built-in segment: the stowed turn-count.ts extension
# registers it in the live SEGMENTS record. Without the extension the unknown
# id renders invisible — no error.
omp config set statusLine.leftSegments '["model","context_pct","cache_hit","turn_count"]'
# cwd_name is extension-registered too (cwd-name.ts): launch-folder basename,
# right side, only when omp runs outside an nvim sidekick terminal.
omp config set statusLine.rightSegments '["cwd_name","cost"]'
# Thinking level rides the model segment. Pin both its visibility and expanded
# form so omp version/default changes cannot collapse ` · <level>` into the
# leading model icon.
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
for key in modelRoles modelTags retry.fallbackChains cycleOrder \
  defaultThinkingLevel startup.quiet memory.backend \
  theme.dark theme.light statusLine.preset statusLine.separator \
  statusLine.transparent statusLine.compactThinkingLevel \
  statusLine.leftSegments statusLine.rightSegments statusLine.segmentOptions \
  providers.webSearchOrder \
  providers.webSearchExclude; do
  echo "  $key = $(omp config get "$key" --json | jq -c '.value')"
done

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`omp\`."
