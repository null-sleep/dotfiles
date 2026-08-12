#!/bin/bash
# Link Claude Code's standalone Linear skill to the single vendored Agent Skills
# copy stowed at ~/.agents/skills/linear-cli. Run after `stow --no-folding
# agents claude`; this avoids a marketplace/plugin cache and cannot add an MCP.

set -euo pipefail

SOURCE="$HOME/.agents/skills/linear-cli"
TARGET="$HOME/.claude/skills/linear-cli"

if [ ! -f "$SOURCE/SKILL.md" ]; then
  echo "Error: Linear skill not found at $SOURCE/SKILL.md" >&2
  echo "Run: stow --no-folding agents" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
  echo "Error: $TARGET is a real path; move it aside before linking the shared skill" >&2
  exit 1
fi

ln -sfn "$SOURCE" "$TARGET"
echo "Claude Code Linear skill -> $SOURCE"
