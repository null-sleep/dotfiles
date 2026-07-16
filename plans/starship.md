# Integrate Starship as the zsh prompt

## Context

Today the shell prompt is a **hand-rolled zsh function** in
`zsh/.zshrc_config.zsh:82-95` (`_zsh_git_prompt` + `PROMPT`), rendering
`➜  <dir> git:(<branch>) ✗`. It surfaces three things: exit status (the
red/green arrow), the cwd basename (`%c`), and git branch + a single dirty
marker. Two properties matter and must be preserved:

1. **Auto-recolor on theme switch.** The palette uses ANSI color *names*
   (`green`, `cyan`, `blue`…), which emit the basic ANSI SGR codes rather than
   truecolor — so the terminal resolves them against its *active* 16-color
   palette. The `theme` script (`zsh/.local/bin/theme`) flips macOS light/dark;
   Ghostty follows natively via `theme = light:Catppuccin Latte,dark:Dracula`
   (`ghostty/.config/ghostty/config:12`), swapping its ANSI palette, so the
   next prompt render recolors with no shell restart. **This only holds while
   the config uses color names, never hex** — hex would emit truecolor and stop
   tracking the theme. Documented at `README.md:1032` and in
   `## Unified theme switching`.
2. **Self-contained.** The prompt renders even if antigen/oh-my-zsh fails to
   load (comment at `zsh/.zshrc_config.zsh:60-71`).

**Why Starship (at this scope):**

- **Cleaner git.** Drops the `git:(…)` robbyrussell wrapper's `git:` prefix for
  a compact `(branch)`, and branch/SHA detection comes from Starship's git2
  modules (no subprocess) instead of hand-rolled `symbolic-ref`/`rev-parse`.
- **Robustness.** Rust, with a `command_timeout` (default 500 ms) bounding every
  command — including the one `git status` the dirty marker runs — so a
  pathological repo degrades (marker just doesn't show) instead of hanging.
- **Maintainability & headroom.** Declarative TOML instead of hand-rolled zsh +
  manual `%F{}` escape juggling, and trivially extensible later (see
  `## Optional additions`) without touching `.zshrc`.

Scope chosen: **minimal — folder + git.** The line is
`<folder>(<branch|sha><dirty>):` — e.g. `dotfiles(main~):`. It's the cwd
basename, the branch in parens (`main`/`master` shown like any other branch —
no `ignore_branches` trick; a short SHA when HEAD is detached), a red `~` when
the worktree is dirty, and a trailing `:` prompt symbol colored green/red by
the last exit status. **No language/tool version modules** (go/node/rust/python/
elixir/docker/k8s/aws are explicitly out). Every color is an ANSI palette *name*
(`cyan`, `purple`, `red`, `green`) — never hardcoded hex — so the whole prompt
recolors when Ghostty flips light/dark.

## Changes

### 1. `Brewfile` — add the dependency

Add `brew "starship"` to the shell tools group (near `brew "zoxide"` /
`brew "direnv"`, the "Core CLI — shell" section).

### 2. `zsh/.zshrc_config.zsh` — swap the prompt for Starship's init

Replace the prompt block (the comment `:60-71`, `setopt PROMPT_SUBST` `:72`,
the `PROMPT_COLOR_*` palette `:74-80`, `_zsh_git_prompt` `:82-93`, and the
`PROMPT=` line `:95`) with:

```zsh
#------------------------------------------------------------------------------
# Prompt — Starship (https://starship.rs). Config in ~/.config/starship.toml
# (stowed from zsh/.config/starship.toml). Styled with ANSI colour *names* so
# it recolours automatically when the `theme` script flips light/dark, same as
# the old hand-rolled prompt did.
#------------------------------------------------------------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  echo "starship not found. Run: brew install starship"
fi
```

Notes:
- Placed here (after `antigen apply`, so zsh-syntax-highlighting is already
  loaded) it composes cleanly with the line-editor plugins.
- Keep the **entire window/tab title system** (`:97-130`) untouched. Starship's
  own title feature is off by default, so it won't fight `_set_term_title` or
  nvim's `titling.lua`.
- `setopt PROMPT_SUBST` is removed with the block — nothing else depends on it
  (the title code uses `print -P`, not `PROMPT`).
- The `command -v` guard preserves the old "prompt still works if the framework
  is missing" property (falls back to zsh's default prompt with a hint).

### 3. New file: `zsh/.config/starship.toml` (stowed → `~/.config/starship.toml`)

Lives inside the existing `zsh` stow package (no new package, no new README
Part-2 top-level section). `stow zsh` links it to `~/.config/starship.toml`,
Starship's default config path — no `STARSHIP_CONFIG` env var needed.

Design — a compact single line, `<folder>(<branch|sha><dirty>):`, e.g.
`dotfiles(main~):`. Folder butts against the branch in parens (no `git:`
prefix, no glyph); a short SHA replaces the branch when HEAD is detached; a red
`~` marks a dirty worktree; the trailing `:` is colored green/red by exit
status. Styled with **ANSI color names** for auto-recolor. The top-level
`format` is the whitelist (unlisted modules don't render), and literal parens
are escaped `\(` `\)` since Starship uses `( )` for conditional groups.

```toml
add_newline = false

# <folder>(<branch|sha><dirty>):   — only these modules render
format = "$directory$git_branch$git_commit${custom.git_dirty}$character"

[directory]              # cwd basename, like the old %c
style = "cyan"
truncation_length = 1
truncate_to_repo = false
truncation_symbol = ""   # basename only — never "…/dotfiles" on deep paths
format = "[$path]($style)"

[git_branch]             # (branch — open paren + name, no glyph, no leading space
style = "purple"
only_attached = true     # hide in detached HEAD so git_commit shows the SHA, not "HEAD"
format = '\([$branch]($style)'
# no `ignore_branches` — main and master are shown like any other branch

[git_commit]             # (sha — short SHA when HEAD is detached (old prompt's fallback)
only_detached = true     # (default) shown only when NOT on a branch
style = "purple"
format = '\([$hash]($style)'

# Red ~ when the worktree is dirty (any staged / unstaged / untracked change),
# then the closing paren. `when` gates on being inside a repo so ")" shows even
# when clean; `command` prints ~ only when dirty. Collapses ALL dirt to one mark,
# where Starship's built-in git_status would emit one marker per change-category.
[custom.git_dirty]
when = "git rev-parse --is-inside-work-tree"
command = "git status --porcelain --ignore-submodules 2>/dev/null | grep -q . && printf '~'"
format = '[$output](red)\)'

[character]              # : prompt symbol, coloured green/red by last exit status
success_symbol = "[:](green)"
error_symbol   = "[:](red)"
```

Renders:

| State | Render |
|---|---|
| Plain dir | `Documents:` |
| Clean repo | `dotfiles(main):` |
| Default branch | `dotfiles(master):` |
| Dirty worktree (any # of change-types) | `dotfiles(main~):` |
| Detached HEAD | `dotfiles(a1b2c3d):` |
| Detached + dirty | `dotfiles(a1b2c3d~):` |
| After a failed command | the trailing `:` turns red |

In a repo, `git_branch`/`git_commit` supply the opening `(` (they're mutually
exclusive — branch when attached, SHA when detached) and `custom.git_dirty`
supplies the closing `)`; outside a repo all three are empty, so plain dirs stay
`Documents:` with no stray parens.

**Trade-off vs. built-in `git_status`.** The custom module gives one dirty mark
for any dirt (vs `git_status`'s per-category `~~`), but costs a `git rev-parse`
+ `git status --porcelain` per prompt — like the old hand-rolled prompt, and
bounded by `command_timeout`. Swap back to native `git_status` (libgit2, no
subprocess) if a huge repo ever drags.

**Theme colors.** `cyan`/`purple`/`red`/`green` are ANSI palette *names*, not
hex — the terminal resolves them against its active scheme (Dracula cyan
`#8be9fd`, Latte `#179299`), so the prompt recolors on the Ghostty theme flip.
Hex would emit truecolor and break that.

### 4. `README.md` — document it (same-change rule)

- New `### Prompt (Starship)` subsection under `## ZSH` (before
  `### Troubleshooting antigen` at `:1013`): what it is, that config lives in
  `zsh/.config/starship.toml`, `brew install starship`, and that `stow zsh`
  links the config. One line: directory + git only, ANSI-name styling.
- Revise the note at `README.md:1032` — the prompt is now Starship, not
  `_zsh_git_prompt`; point at `~/.config/starship.toml` and note ANSI-name
  styling still drives the light/dark recolor.
- Update the **Contents** TOC *Shell* line (`:30`) to add a
  `[prompt](#prompt-starship)` sub-link (mind anchor-link hygiene — `(Starship)`
  has parens, so add an explicit `<a id="prompt-starship"></a>` anchor above the
  heading per the repo's anchor rule).
- In `## Unified theme switching` → `### How each tool switches live` (`:465`),
  add a short entry: Starship recolors via ANSI palette names, so the `theme`
  script needs no change.

## Optional additions (decide before implementing)

Cheap, low-noise things that fit the "folder + branch" spirit without adding
language versions. The base includes the exit-status `❯` and a single `✗` dirty
marker (`custom.git_dirty`), but deliberately **no ahead/behind or stash**. Pick
any subset below; each is a few TOML lines.

**Recommended — richer git, still one line, zero noise when idle:**

- **Ahead/behind + stash.** The single-✗ base drops these (they lived in the
  native `git_status` we swapped out). To get them back without reintroducing
  `✗✗`, add a `git_status` module with the dirty categories left empty and only
  `$ahead_behind` (+ optional `stashed = "*"`) in its `format`, then insert
  `$git_status` in the top-level `format`. Surfaces `⇡2⇣1 *1` only when relevant.
- **`git_state`** — shows `REBASING 1/3`, `MERGING`, `CHERRY-PICKING` etc.
  during an in-progress operation. Renders *only* mid-operation, so it's
  invisible day-to-day but saves confusion when a rebase is half-done.
- **`cmd_duration`** — annotates commands slower than a threshold with their
  elapsed time (`took 4s`). `min_time = 2000` keeps fast commands clean.

**Taste calls (a real choice, not a clear win):**

- **Directory scope.** Keep today's basename-only (`dotfiles`), or switch to
  repo-relative (`truncate_to_repo = true`, drop `truncation_length`) to show
  `dotfiles/nvim/lua` — more orientation in deep trees, at the cost of the
  ultra-minimal look.
- **Blank line between prompts** (`add_newline = true`) — visual breathing room
  between commands. Divisive; easy to try and revert.
- **direnv / mise env indicator.** Given the direnv+mise setup, a subtle marker
  when a project env is active (`$direnv`, off by default) confirms the env
  loaded. Low signal most of the time.
- **`$jobs`** — shows a count when background jobs are suspended/running.

Suggested default: fold in the three **Recommended** items (they never add
noise), leave the taste calls for a follow-up once the base prompt feels right.

## Verification

1. `brew bundle --file=Brewfile` (or `brew install starship`) — installs it.
2. `stow -R zsh` — re-links, creating `~/.config/starship.toml`; confirm the
   symlink: `readlink ~/.config/starship.toml`.
3. `exec zsh` — in a repo the prompt renders `<folder>(<branch>):`. Dirty the
   worktree and confirm a red `~` appears before the `)`.
4. Exit-status color: run `false` then check the trailing `:` is red; run `true`
   then check it's green.
5. Default branch shown: on a `main`/`master` checkout, confirm the branch name
   still appears (it isn't hidden).
6. Detached HEAD: `git checkout HEAD~1` (then `git switch -` to undo) — confirm
   the short SHA shows via `git_commit`, not `(HEAD)`.
7. Minimal in plain dirs: `cd` into a non-git directory and confirm only
   `<folder>:` shows (no parens).
8. Auto-recolor: run `theme light` then `theme dark` and confirm the prompt
   recolors without restarting the shell.
9. Titles intact: `cd` between a git repo and a plain dir, confirm the terminal
   tab title still updates (`_update_term_title` unaffected); `title foo` still
   overrides.
10. Startup cost sane: `time zsh -i -c exit` before/after — Starship's init adds
   little; flag if it regresses noticeably.

## Rollback

The old `_zsh_git_prompt`/`PROMPT` block is preserved in git history — revert
the `zsh/.zshrc_config.zsh` hunk to restore it. Removing `brew "starship"` and
`zsh/.config/starship.toml` fully backs the change out.
