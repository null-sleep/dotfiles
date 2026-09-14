#!/bin/bash
# One-time setup: activate the provider-neutral review-pr skill for this
# machine. Run after `stow --no-folding agents`.
#
# The `agents` package tracks SKILL.generic.md, but SKILL.md itself is NOT
# tracked or stowed. This script creates it as a machine-local symlink to the
# tracked variant, so a later restow or pull cannot overwrite that choice.
#
# Usage:
#   setup-review-pr.sh

set -euo pipefail

DIR="$HOME/.agents/skills/review-pr"
SOURCE_FILE="$DIR/SKILL.generic.md"
REPO_SKILL_DIR="$(cd "$(dirname "$0")/../agents/.agents/skills/review-pr" && pwd -P)"
REPO_SOURCE_FILE="$REPO_SKILL_DIR/SKILL.generic.md"

if [ ! -e "$SOURCE_FILE" ]; then
  echo "Error: variant file not found at $SOURCE_FILE"
  echo "Run 'stow --no-folding agents' from the repo root first, then re-run this script."
  exit 1
fi

# `--no-folding` keeps this target directory real, so verify the tracked
# variant's symlink rather than trusting that the containing directory belongs
# to this checkout.
if [ "$(realpath "$SOURCE_FILE")" != "$REPO_SOURCE_FILE" ]; then
  echo "Error: $SOURCE_FILE does not resolve to this checkout's variant." >&2
  echo "Expected: $REPO_SOURCE_FILE" >&2
  echo "Re-run 'stow -R --no-folding agents' from the repo root." >&2
  exit 1
fi

ln -sfn "SKILL.generic.md" "$DIR/SKILL.md"
echo "review-pr -> generic"

SKILL_REAL_DIR="$DIR"

# Link the canonical home skill into hosts that use their own documented skill
# directories. Cursor, pi, omp, and OpenCode read ~/.agents/skills directly.
link_host_skill() {
  local host_dir="$1"
  local host_name="$2"
  mkdir -p "$host_dir"

  local target="$host_dir/review-pr"

  # Preserve an independently installed skill rather than overwriting it.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    if [ -e "$target.disabled" ]; then
      echo "Error: $target is a real path and $target.disabled already exists." >&2
      echo "Move or remove one of them by hand, then re-run." >&2
      exit 1
    fi
    mv "$target" "$target.disabled"
    echo "  $host_name: moved pre-existing review-pr -> review-pr.disabled"
  fi

  if [ -L "$target" ] && [ "$(readlink "$target")" != "$SKILL_REAL_DIR" ]; then
    echo "  $host_name: repointed hijacked link (was $(readlink "$target"))"
  fi

  ln -sfn "$SKILL_REAL_DIR" "$target"
  echo "  $host_name: review-pr -> $SKILL_REAL_DIR"
}

link_host_skill "$HOME/.claude/skills" "claude"
link_host_skill "$HOME/.codex/skills" "codex"
