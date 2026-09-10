#!/bin/bash
# One-time setup: activate the review-pr skill for this machine. Run after
# `stow claude`.
#
# The repo tracks SKILL.generic.md (provider-neutral), but SKILL.md itself is
# NOT tracked or stowed — this script creates it as a machine-local symlink to
# the tracked variant, so a later `stow -R claude` / `git pull` can never
# overwrite a per-machine choice. On a machine that needs project-specific
# tweaks, drop a private SKILL.*.md next to it and point SKILL.md there instead.
#
# Usage:
#   setup-review-pr.sh

set -euo pipefail

DIR="$HOME/.claude/skills/review-pr"
SOURCE_FILE="$DIR/SKILL.generic.md"

# Don't point SKILL.md at a variant that isn't stowed yet — run `stow claude` first.
if [ ! -e "$SOURCE_FILE" ]; then
  echo "Error: variant file not found at $SOURCE_FILE"
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi

# Refuse to write into $DIR unless it still resolves into this checkout. A skill
# installer can replace the stow symlink at $DIR with a link to a same-named
# third-party skill (see README's "Which review skill wins"); writing blindly
# then creates SKILL.md *inside that other skill* and reports success — the same
# silent failure this script exists to prevent. `stow` guaranteeing the link is
# exactly the assumption such an install falsifies, so verify rather than trust.
SKILL_REAL_DIR="$(cd "$DIR" && pwd -P)"
REPO_SKILL_DIR="$(cd "$(dirname "$0")/.claude/skills/review-pr" && pwd -P)"

if [ "$SKILL_REAL_DIR" != "$REPO_SKILL_DIR" ]; then
  echo "Error: $DIR resolves to $SKILL_REAL_DIR," >&2
  echo "  but this checkout is $REPO_SKILL_DIR." >&2
  echo "Something replaced the stow link. Remove $DIR, re-run" >&2
  echo "'stow --no-folding claude' from the repo root, then re-run this script." >&2
  exit 1
fi

# Relative symlink (not absolute) so it resolves the same on any machine.
# -f replaces an existing link atomically, including a dangling one.
ln -sfn "SKILL.generic.md" "$DIR/SKILL.md"

echo "review-pr -> generic"

# Fan the same skill out to the other agent hosts, mirroring how
# setup-linear-cli.sh shares one vendored copy with every tool. Each host gets a
# symlink to this directory, so all of them load the identical skill and there
# is exactly one file to edit.
#
# ~/.agents/skills is the cross-tool standard path (Cursor, pi, omp, OpenCode
# read it directly); ~/.codex/skills is Codex's own. Both are stowed
# --no-folding / hold machine-local state, so link into them rather than
# replacing the directory.
#
# Each host is pointed at $SKILL_REAL_DIR (the repo path, resolved above) rather
# than at $DIR: $DIR is itself a stow symlink into this repo, so linking
# host -> that link -> repo would leave every other tool's skill dependent on
# Claude's link staying intact.
link_host_skill() {
  local host_dir="$1"
  local host_name="$2"
  [ -d "$host_dir" ] || return 0

  local target="$host_dir/review-pr"

  # Never clobber a real directory that isn't ours — a third-party review-pr
  # skill installed here is what silently shadows this one (see the "Which
  # review skill wins" section in README). Quarantine it instead, but refuse if
  # that would land on an existing quarantine: `mv dir existing_dir` nests
  # rather than replaces (leaving review-pr.disabled/review-pr/), and for files
  # it overwrites outright, either way exiting 0 with a success message. Same
  # "refuse, don't guess" stance as setup-linear-cli.sh.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    if [ -e "$target.disabled" ]; then
      echo "Error: $target is a real path and $target.disabled already exists." >&2
      echo "Move or remove one of them by hand, then re-run." >&2
      exit 1
    fi
    mv "$target" "$target.disabled"
    echo "  $host_name: moved pre-existing review-pr -> review-pr.disabled"
  fi

  # A hijack here is a symlink swap, not a real directory, so the guard above
  # doesn't fire and `ln -sfn` silently repairs it. Say so, otherwise a repair
  # is indistinguishable from a no-op re-run.
  if [ -L "$target" ] && [ "$(readlink "$target")" != "$SKILL_REAL_DIR" ]; then
    echo "  $host_name: repointed hijacked link (was $(readlink "$target"))"
  fi

  ln -sfn "$SKILL_REAL_DIR" "$target"
  echo "  $host_name: review-pr -> $SKILL_REAL_DIR"
}

link_host_skill "$HOME/.agents/skills" "agents (cursor/pi/omp/opencode)"
link_host_skill "$HOME/.codex/skills" "codex"

# omp scopes skills per project rather than globally
# (~/.omp/agent/memories/<slugified-project-path>/skills), so there is no single
# path to link — every existing project dir gets its own link. An omp project
# created later needs a re-run: omp creating that skills dir does not create the
# link, and nothing here watches for new dirs.
#
# The `[ -d ]` test also absorbs the no-match case, where the glob stays literal.
for omp_skills in "$HOME"/.omp/agent/memories/*/skills; do
  [ -d "$omp_skills" ] || continue
  link_host_skill "$omp_skills" "omp $(basename "$(dirname "$omp_skills")")"
done
