#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SETTINGS="$ROOT/claude/.claude/settings.json"

jq -e '
  .model == "opusplan"
  and .statusLine == {
    "type": "command",
    "command": "bash $HOME/.claude/statusline-command.sh"
  }
  and .theme == "custom:active"
  and .skipDangerousModePermissionPrompt == false
  and .skipAutoPermissionPrompt == false
  and .enabledPlugins["lua-lsp@claude-plugins-official"] == true
  and .enabledPlugins["pyright-lsp@claude-plugins-official"] == true
  and .enabledPlugins["rust-analyzer-lsp@claude-plugins-official"] == true
  and .enabledPlugins["gopls-lsp@claude-plugins-official"] == true
  and ([.hooks.PreToolUse[]?.hooks[]?.command
    | select(contains("rtk hook claude"))]
    | length == 1 and all(contains("if command -v rtk")))
  and ([.hooks.SessionStart[]?
    | select(any(.hooks[]?; .command | contains("herdr-agent-state.sh")))]
    | length == 1 and all(.matcher == "*"))
  and ([.hooks.SessionStart[]?.hooks[]?
    | select(.command | contains("herdr-agent-state.sh"))]
    | length == 1 and all(.timeout == 10
      and (.command | contains("if command -v herdr") and contains("$HOME"))))
  and ([.hooks[]?[]?.hooks[]?.command
    | select(contains("sidekick-notify.sh"))] | length) == 5
  and ([.hooks[]?[]?.hooks[]?.command, .statusLine.command]
    | all(contains("/Users/") | not))
  and ((.permissions.allow // [] | length) == (.permissions.allow // [] | unique | length))
  and ((.permissions.deny // [] | length) == (.permissions.deny // [] | unique | length))
' "$SETTINGS" >/dev/null

printf 'settings invariants tests: ok\n'
