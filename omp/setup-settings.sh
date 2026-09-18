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

# Avoid project-level config when reading global settings.
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
  "glm-fast": "openrouter/z-ai/glm-5.3-flash:max",
  "cheap-l": "openrouter/z-ai/glm-5.3:max",
  "dseek": "openrouter/deepseek/deepseek-v4.1-flash:max",
  "kimi": "openrouter/moonshotai/kimi-k3:max"
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
migrated_roles="$(jq -c '
  if (has("dseek") | not) and has("default-cheap") then .dseek = .["default-cheap"] else . end
  | if (has("kimi") | not) and has("cheap-alt") then .kimi = .["cheap-alt"] else . end
  | del(."default-cheap", ."cheap-alt")
' <<<"$roles")"
merged_roles="$(jq -c --argjson defaults "$DEFAULT_ROLES" '$defaults + .' <<<"$migrated_roles")"
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

omp config set cycleOrder '["smol","default","dseek","kimi","slow","oa-m","oa-l","cheap-l","oa-s"]'

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

# Search backends.
omp config set providers.webSearchOrder '["perplexity","public"]'
omp config set providers.webSearchExclude '["anthropic"]'

# Local project summaries.
omp config set memory.backend local
# Pin gopls for workers without the shell PATH.
LSP_CONFIG_DIR="${PI_CONFIG_DIR:-$HOME/.omp/agent}"
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
  defaultThinkingLevel startup.quiet memory.backend \
  hideThinkingBlock \
  theme.dark theme.light statusLine.preset statusLine.separator \
  statusLine.transparent statusLine.compactThinkingLevel statusLine.contextLine \
  statusLine.leftSegments statusLine.rightSegments statusLine.segmentOptions \
  providers.webSearchOrder \
  providers.webSearchExclude; do
  echo "  $key = $(omp config get "$key" --json | jq -c '.value')"
done

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`omp\`."
