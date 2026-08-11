#!/bin/bash
# One-time setup: enable the LSP plugins in ~/.claude/settings.json so Claude
# Code's built-in LSP tool gets code intelligence (go-to-def, find-references,
# hover, call hierarchy) for Lua, Python, Rust, and Go.
#
# The plugins come from the official `claude-plugins-official` marketplace, but
# each is just a thin config wrapper — it does NOT ship the language server
# itself. The server binary must already be on your PATH (see checks below).
# settings.json is stowed with these keys already set. This script validates
# the tracked config and reports the machine-local server binaries.
#
# Prerequisites (install the server binaries first):
#   lua-language-server  brew install lua-language-server
#   pyright-langserver   npm install -g pyright   (needs node — in Brewfile)
#   rust-analyzer        rustup component add rust-analyzer
#   gopls                go install golang.org/x/tools/gopls@latest  (go — in Brewfile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$SCRIPT_DIR/.claude/settings.json"

# plugin-key  ->  server binary that must be on PATH  ->  install hint
PLUGINS=(
  "lua-lsp@claude-plugins-official|lua-language-server|brew install lua-language-server"
  "pyright-lsp@claude-plugins-official|pyright-langserver|npm install -g pyright"
  "rust-analyzer-lsp@claude-plugins-official|rust-analyzer|rustup component add rust-analyzer"
  "gopls-lsp@claude-plugins-official|gopls|go install golang.org/x/tools/gopls@latest"
)

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

"$SCRIPT_DIR/setup-settings.sh" --check

# Merge the plugin keys into .enabledPlugins without disturbing anything else.
patch='{}'
for entry in "${PLUGINS[@]}"; do
  key="${entry%%|*}"
  patch=$(jq -n --argjson p "$patch" --arg k "$key" '$p + {($k): true}')
done

if jq -e --argjson patch "$patch" \
     '(.enabledPlugins // {}) as $cur | $patch | to_entries | all(.[]; $cur[.key] == true)' \
     "$SETTINGS" >/dev/null 2>&1; then
  echo "LSP plugins already configured in $SETTINGS."
else
  echo "Error: one or more LSP plugins are missing from tracked settings: $SETTINGS" >&2
  exit 1
fi

# Report which server binaries are present. A plugin whose binary is missing is
# harmless (the LSP tool just errors for that file type) until you install it.
echo
echo "Language server binaries:"
missing=0
for entry in "${PLUGINS[@]}"; do
  bin="${entry#*|}"; hint="${bin#*|}"; bin="${bin%%|*}"
  if command -v "$bin" >/dev/null 2>&1; then
    printf '  ok      %-20s %s\n' "$bin" "$(command -v "$bin")"
  else
    printf '  MISSING %-20s -> %s\n' "$bin" "$hint"
    missing=1
  fi
done

echo
if [ "$missing" -eq 1 ]; then
  echo "Install the MISSING binaries above, then restart Claude Code."
else
  echo "All servers present. Restart Claude Code to activate the plugins."
fi
