#!/bin/bash
# One-time setup: select which review-pr skill variant is active for this
# machine. Run after `stow claude`.
#
# The repo tracks two variants — SKILL.generic.md (provider-neutral) and
# SKILL.work.md (Work/services specifics: gh-stack, Linear, generated
# code paths). SKILL.md itself is NOT tracked or stowed — this script creates
# it as a machine-local symlink to the chosen variant, so a later
# `stow -R claude` / `git pull` can never overwrite the per-machine choice.
#
# Usage:
#   setup-review-pr.sh            # auto-detect (see below)
#   setup-review-pr.sh generic    # force the provider-neutral variant
#   setup-review-pr.sh work      # force the Work variant

set -euo pipefail

DIR="$HOME/.claude/skills/review-pr"
VARIANT="${1:-}"
REASON="explicit"

if [ -z "$VARIANT" ]; then
  # Auto-detect using the same work-machine marker zsh/.zshrc_config.zsh
  # already keys off (`[[ -f ~/.zshrc_work.zsh ]] && source ...`, see
  # README's "~/.zshrc_work.zsh" entry). That file is dropped by hand on a
  # Work machine, so its presence is a deliberate, explicit signal — unlike
  # e.g. `git config user.email`, which reads this repo's own (gmail) address
  # on every machine, Work included.
  if [ -f "$HOME/.zshrc_work.zsh" ]; then
    VARIANT="work"
    REASON="auto: ~/.zshrc_work.zsh present"
  else
    VARIANT="generic"
    REASON="auto: ~/.zshrc_work.zsh absent"
  fi
fi

if [ "$VARIANT" != "generic" ] && [ "$VARIANT" != "work" ]; then
  echo "Error: variant must be 'generic' or 'work', got '$VARIANT'"
  exit 1
fi

SOURCE_FILE="$DIR/SKILL.$VARIANT.md"

# Don't point SKILL.md at a variant that isn't stowed yet — run `stow claude` first.
if [ ! -e "$SOURCE_FILE" ]; then
  echo "Error: variant file not found at $SOURCE_FILE"
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi

# Relative symlink (not absolute) so it resolves the same on any machine.
# -f replaces an existing link atomically, including a dangling one left over
# from before the tracked SKILL.md was split into variants.
ln -sfn "SKILL.$VARIANT.md" "$DIR/SKILL.md"

echo "review-pr -> $VARIANT ($REASON)"
