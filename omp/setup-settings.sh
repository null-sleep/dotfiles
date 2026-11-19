#!/bin/bash
# Seed OMP's machine-local config and gopls LSP command.
# Preserves user overrides; forced settings are repo-owned.
# Usage: bash ~/src/dotfiles/omp/setup-settings.sh

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "Error: ruby is required to write extension-owned status-line segment ids."
  exit 1
fi

if ! command -v omp >/dev/null 2>&1; then
  echo "Warning: omp is not on PATH — install it first:"
  echo "  brew install can1357/tap/omp"
  echo "Nothing to do without the CLI (the config store is YAML, written via"
  echo "\`omp config\`). Re-run this script after installing."
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Avoid project-level config when reading global settings.
cd "$(mktemp -d)"

# `fable` is the direct Anthropic subscription model on purpose: OpenRouter's
# Fable is excluded by this account's Zero Data Retention setting (kept on).
# `fable-sub` duplicates it so the "X sub" name stays predictable for per-call
# model selection. See agents/.agents/skills/omp-models-sync/SKILL.md.
DEFAULT_ROLES='{
  "default": "openrouter/openai/gpt-6.1-terra:high",
  "haiku": "openrouter/anthropic/claude-haiku-5.5:medium",
  "terra": "openrouter/openai/gpt-6.1-terra:high",
  "sol": "openrouter/openai/gpt-6.2-sol:xhigh",
  "smol": "@haiku",
  "tiny": "@haiku",
  "slow": "@sol",
  "sonnet": "openrouter/anthropic/claude-sonnet-5.5:high",
  "opus": "openrouter/anthropic/claude-opus-5.5:high",
  "neon": "openrouter/google/gemini-4-neon:xhigh",
  "hydrogen": "openrouter/google/gemini-4-hydrogen:high",
  "fable": "anthropic/claude-fable-5-2:high",
  "auto-code": "openrouter/openrouter/auto-code",
  "vision": "openrouter/openai/gpt-6.1-terra:high",
  "plan": "openrouter/anthropic/claude-opus-5.5:high",
  "commit": "openrouter/anthropic/claude-haiku-5.5:medium",
  "task": "openrouter/openai/gpt-6.1-terra:high",
  "advisor": "openrouter/anthropic/claude-haiku-5.5:high",
  "med-vision": "openrouter/openai/gpt-6.1-terra:high",
  "oa-m": "openai-codex/gpt-6.1-terra:high",
  "oa-l": "openai-codex/gpt-6.2-sol:xhigh",
  "sonnet-sub": "anthropic/claude-sonnet-5-5:high",
  "opus-sub": "anthropic/claude-opus-5-5:high",
  "haiku-sub": "anthropic/claude-haiku-5-5:medium",
  "fable-sub": "anthropic/claude-fable-5-2:high"
}'
DEFAULT_MODEL_TAGS='{
  "med-vision": {"name": "med-vision"},
  "oa-m": {"name": "oa-m"},
  "oa-l": {"name": "oa-l"},
  "sonnet": {"name": "sonnet"},
  "opus": {"name": "opus"},
  "neon": {"name": "neon"},
  "hydrogen": {"name": "hydrogen"},
  "fable": {"name": "fable"},
  "auto-code": {"name": "auto-code"}
}'
DEFAULT_FALLBACK_CHAINS='{
  "openrouter/openrouter/auto-code": [],
  "anthropic/claude-fable-5-2": [
    "openrouter/anthropic/claude-opus-5.5:high"
  ],
  "openrouter/openai/gpt-6.1-terra": [
    "openai-codex/gpt-6.1-terra:high",
    "openai-codex/gpt-6.2-sol:xhigh"
  ],
  "openrouter/openai/gpt-6.2-sol": [
    "openai-codex/gpt-6.2-sol:xhigh",
    "openai-codex/gpt-6.1-terra:high"
  ]
}'

get() { omp config get "$1" --json | jq -r '.value'; }

# OMP 18.2 validates `config set` segment arrays against built-ins even though
# runtime rendering accepts extension-registered ids. Update only these two
# arrays under the same lock and atomic-rename discipline as OMP's own writer.
set_status_line_segments() {
  local config_dir
  config_dir="$(omp config path)"
  ruby -ryaml -e '
    dir = ARGV.fetch(0)
    yml = File.join(dir, "config.yml")
    yaml = File.join(dir, "config.yaml")
    path = File.exist?(yml) || !File.exist?(yaml) ? yml : yaml
    left = %w[model context_pct cache_hit turn_count]
    right = %w[cwd_name cost]

    File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      source = File.exist?(path) ? File.read(path) : ""
      data = source.empty? ? {} : YAML.safe_load(source, permitted_classes: [], aliases: false)
      raise "#{path}: expected a YAML mapping" unless data.is_a?(Hash)

      status = data["statusLine"]
      raise "#{path}: statusLine must be a YAML mapping" unless status.nil? || status.is_a?(Hash)
      status ||= {}
      if status["leftSegments"] == left && status["rightSegments"] == right
        puts "statusLine extension segments already set — left as-is."
        next
      end

      status["leftSegments"] = left
      status["rightSegments"] = right
      data["statusLine"] = status
      serialized = YAML.dump(data).delete_prefix("---\n")
      mode = File.exist?(path) ? File.stat(path).mode & 0o777 : 0o600
      tmp = "#{path}.tmp.#{$$}"
      begin
        File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
          file.write(serialized)
          file.flush
          file.fsync
        end
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
      puts "✔ Set statusLine extension segments"
    end
  ' "$config_dir"
}

roles="$(omp config get modelRoles --json | jq -c '.value // {}')"
# The cycle uses model-named roles. On the first run, move the old slow
# selector to sol and copy the old default to terra (default itself is left
# alone), and alias the built-in smol/tiny/slow roles to the new names so
# background features keep a cheap or strong model.
# Roles use only the cycle's models. Selectors naming a retired provider
# (DeepSeek, Moonshot/Kimi, Z.AI/GLM) or a model dropped from the cycle (GPT-6
# Luna, GPT-6.x Astra, Gemini 4 Carbon) are matched in role values, chain keys
# and chain steps.
RETIRED_RE='deepseek|moonshotai|z-ai/|gpt-6-luna|gpt-6(\.[0-9]+)?-astra|gemini-4-carbon'
# OpenRouter Fable is hidden by the ZDR setting, so a machine still carrying the
# dead OpenRouter `fable` id is moved onto the subscription model below.
migrated_roles="$(jq -c --arg re "$RETIRED_RE" '
  del(."default-cheap", ."cheap-alt", .dseek, .kimi, ."glm-l", ."glm-fast", ."cheap-l", .luna, ."oa-s", .astra, .carbon, ."oa-xl")
  | if has("terra") then . else
      (if has("slow") then .sol = .slow else . end)
      | (if has("default") then .terra = .default else . end)
      | .smol = "@haiku" | .tiny = "@haiku" | .slow = "@sol"
    end
  | del(.argon)
  | if .fable == "openrouter/anthropic/claude-fable-5.2:high" then .fable = "anthropic/claude-fable-5-2:high" else . end
  | if ((.advisor // "") | tostring | test($re)) then .advisor = "openrouter/anthropic/claude-haiku-5.5:high" else . end
  | if ((.commit // "") | tostring | test($re)) then .commit = "openrouter/anthropic/claude-haiku-5.5:medium" else . end
' <<<"$roles")"
# Search preferences moved from providers.webSearch* to the web model role.
# Keep these two entries repo-owned while preserving other roles and chains.
merged_roles="$(jq -c --argjson defaults "$DEFAULT_ROLES" '$defaults + . + {web: "web/perplexity"}' <<<"$migrated_roles")"
if [ "$merged_roles" != "$roles" ]; then
  omp config set modelRoles "$merged_roles"
else
  echo "modelRoles presets already set — left as-is."
fi

tags="$(omp config get modelTags --json | jq -c '.value // {}')"
merged_tags="$(jq -c --argjson defaults "$DEFAULT_MODEL_TAGS" '$defaults + . | del(.argon, ."glm-l", ."glm-fast", ."oa-s", .astra, .carbon)' <<<"$tags")"
if [ "$merged_tags" != "$tags" ]; then
  omp config set modelTags "$merged_tags"
else
  echo "modelTags presets already set — left as-is."
fi

fallback_chains="$(omp config get retry.fallbackChains --json | jq -c '.value // {}')"
# Retain the remaining non-hosted default engines after Public Web. Hosted
# search is omitted because it can use the active Anthropic model.
# Drop every chain key and string step naming a retired selector (RETIRED_RE,
# any version or thinking suffix); non-string entries are kept.
merged_fallback_chains="$(jq -c --arg re "$RETIRED_RE" --argjson defaults "$DEFAULT_FALLBACK_CHAINS" '
  def retired: type == "string" and test($re);
  $defaults + . + {web: ["web/public", "web/parallel", "web/exa", "web/firecrawl", "web/searxng", "web/startpage", "web/duckduckgo", "web/ecosia", "web/google", "web/mojeek"]}
  | with_entries(select(.key | retired | not))
  | map_values(if type == "array" then map(select(retired | not)) else . end)
' <<<"$fallback_chains")"
if [ "$merged_fallback_chains" != "$fallback_chains" ]; then
  omp config set retry.fallbackChains "$merged_fallback_chains"
else
  echo "retry.fallbackChains presets already set — left as-is."
fi

CYCLE_ORDER='["haiku","default","hydrogen","sol","sonnet","neon","opus","fable","auto-code"]'
# Direct Anthropic subscription twins of cycle models: selectable per call
# ("use the sonnet sub model"), kept out of the Ctrl+P/Alt+O cycle.
SUB_ROLES='["sonnet-sub","opus-sub","haiku-sub","fable-sub"]'
omp config set cycleOrder "$CYCLE_ORDER"
# Per-call subagent models: the cycle's models plus their subscription twins,
# at any thinking level. Entries are canonical provider/id (no :level, no
# globs), derived from the roles so the lists cannot drift.
per_call_allow="$(jq -c --argjson cycle "$CYCLE_ORDER" --argjson sub "$SUB_ROLES" '
  # A role value is a string, comma list, or array; `@alias` entries are skipped.
  def entries: (if type == "array" then .[] else . end) | tostring | split(",")[] | gsub("^\\s+|\\s+$"; "");
  [ ($cycle + $sub)[] as $r | .[$r] // empty | entries
    | select(length > 0 and (startswith("@") | not))
    | sub(":(off|minimal|low|medium|high|xhigh|max|auto|inherit)$"; "") ] | unique
' <<<"$merged_roles")"
omp config set task.perCallModelAllow "$per_call_allow"
bash "$SCRIPT_DIR/setup-auto-code.sh"

bash "$SCRIPT_DIR/setup-zed-models.sh"

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

# Repo-owned display, theme, and status line.
omp config set theme.dark dark-dracula
# Keep reasoning summaries available to Ctrl+T, but hidden until requested.
omp config set hideThinkingBlock true
# Let a task call pick its subagent's model ("spawn a scout on opus").
omp config set task.perCallModel on

omp config set theme.light light-catppuccin
omp config set statusLine.preset custom
omp config set statusLine.separator none
omp config set statusLine.transparent true
omp config set statusLine.compactThinkingLevel true
omp config set statusLine.contextLine percentage
# `turn_count` and `cwd_name` are registered by stowed extensions.
set_status_line_segments
# Keep the thinking indicator compact.
omp config set statusLine.segmentOptions '{"model":{"showThinkingLevel":true}}'

# Local project summaries.
omp config set memory.backend local
# Pin gopls for workers without the shell PATH.
LSP_CONFIG_DIR="$(omp config path)"
LSP_CONFIG="$LSP_CONFIG_DIR/lsp.json"
if gopls_path="$(command -v gopls 2>/dev/null)"; then
  mkdir -p "$LSP_CONFIG_DIR"
  if [[ -e "$LSP_CONFIG" && ! -f "$LSP_CONFIG" ]]; then
    echo "Warning: $LSP_CONFIG is not a regular file — gopls LSP override left unchanged." >&2
  elif [[ -f "$LSP_CONFIG" ]] && ! jq -e 'type == "object"' "$LSP_CONFIG" >/dev/null; then
    echo "Warning: $LSP_CONFIG is not a JSON object — gopls LSP override left unchanged." >&2
  elif [[ -f "$LSP_CONFIG" ]] \
    && jq -e 'has("servers") and ((.servers | type) != "object" or (.servers.gopls? != null and (.servers.gopls | type) != "object"))' "$LSP_CONFIG" >/dev/null; then
    echo "Warning: $LSP_CONFIG has an invalid gopls server entry — left unchanged." >&2
  else
    if [[ -f "$LSP_CONFIG" ]] \
      && jq -e 'if has("servers") then (.servers.gopls.command? // "") else (.gopls.command? // "") end | strings | length > 0' "$LSP_CONFIG" >/dev/null; then
      echo "gopls LSP command already configured in $LSP_CONFIG — left as-is."
    else
      lsp_tmp="$(mktemp "${LSP_CONFIG}.XXXXXX")"
      if [[ -f "$LSP_CONFIG" ]] && jq -e 'has("servers")' "$LSP_CONFIG" >/dev/null; then
        jq --arg command "$gopls_path" '.servers.gopls = ((.servers.gopls // {}) + {command: $command})' \
          "$LSP_CONFIG" >"$lsp_tmp"
      elif [[ -f "$LSP_CONFIG" ]]; then
        jq --arg command "$gopls_path" '.gopls = ((.gopls // {}) + {command: $command})' \
          "$LSP_CONFIG" >"$lsp_tmp"
      else
        jq -n --arg command "$gopls_path" '{servers: {gopls: {command: $command}}}' >"$lsp_tmp"
      fi
      mv "$lsp_tmp" "$LSP_CONFIG"
      echo "Configured OMP gopls command: $gopls_path"
    fi
  fi
else
  echo "Warning: gopls is not on PATH — install it with: go install golang.org/x/tools/gopls@latest" >&2
fi

echo
echo "Resulting omp config:"
for key in modelRoles modelTags retry.fallbackChains cycleOrder \
  task.perCallModel task.perCallModelAllow \
  defaultThinkingLevel startup.quiet memory.backend \
  hideThinkingBlock \
  theme.dark theme.light statusLine.preset statusLine.separator \
  statusLine.transparent statusLine.compactThinkingLevel statusLine.contextLine \
  statusLine.leftSegments statusLine.rightSegments statusLine.segmentOptions; do
  echo "  $key = $(omp config get "$key" --json | jq -c '.value')"
done

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`omp\`."
