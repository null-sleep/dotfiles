#!/bin/bash
# Link Claude Code's legacy skill location to canonical Agent Skills.
# Run after `stow --no-folding agents claude`. It deliberately refuses to
# overwrite a real or foreign symlink so local skills are never silently lost.

set -euo pipefail

CANONICAL_SKILLS="$HOME/.agents/skills"
CLAUDE_SKILLS="$HOME/.claude/skills"

if [ ! -d "$CANONICAL_SKILLS" ]; then
  echo "Error: canonical skill directory not found at $CANONICAL_SKILLS" >&2
  echo "Run 'stow --no-folding agents' from the repo root first." >&2
  exit 1
fi

mkdir -p "$CLAUDE_SKILLS"

for source in "$CANONICAL_SKILLS"/*; do
  [ -d "$source" ] || continue
  name="${source##*/}"

  # review-pr has a machine-selected SKILL.md managed by setup-review-pr.sh.
  # Quarantined installer payloads are intentionally not exposed to Claude.
  case "$name" in
    review-pr|*.disabled) continue ;;
  esac

  if [ ! -f "$source/SKILL.md" ] && [ ! -f "$source/skill.md" ]; then
    continue
  fi

  target="$CLAUDE_SKILLS/$name"
  if [ -L "$target" ]; then
    if [ -e "$target" ] && [ "$(realpath "$target")" = "$(realpath "$source")" ]; then
      continue
    fi
    echo "Error: $target is a foreign or dangling symlink; refusing to replace it." >&2
    exit 1
  fi
  if [ -e "$target" ]; then
    echo "Error: $target is a real path; refusing to replace it." >&2
    exit 1
  fi

  ln -s "$source" "$target"
  echo "Claude Code $name skill -> $source"
done
