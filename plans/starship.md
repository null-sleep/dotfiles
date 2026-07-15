# Integrate Starship as the zsh prompt

## Context

Today the shell prompt is a **hand-rolled zsh function** in
`zsh/.zshrc_config.zsh:82-95` (`_zsh_git_prompt` + `PROMPT`), rendering
`➜  <dir> git:(<branch>) ✗`. It surfaces only three things: exit status (the
red/green arrow), the cwd basename (`%c`), and git branch + a single dirty
marker. Two properties matter and must be preserved:

1. **Auto-recolor on theme switch.** The palette uses ANSI color *names*
   (`green`, `cyan`, `blue`…), so the prompt recolors for free when the
   `theme` script (`zsh/.local/bin/theme`) flips macOS/Ghostty/iTerm2 between
   Catppuccin-Latte (light) and Dracula (dark). This is documented at
   `README.md:1032` and in `## Unified theme switching`.
2. **Self-contained.** The prompt renders even if antigen/oh-my-zsh fails to
   load (comment at `zsh/.zshrc_config.zsh:60-71`).

**Why Starship, and the benefits:**

- **Contextual language/tool signal.** The stack has go, node, rust, python,
  elixir, docker/podman/colima, kubernetes, aws, direnv, mise — every one has
  a first-class Starship module. Modules render *only when you're in a
  relevant project*, so plain dirs stay as minimal as today, but a Rust repo
  shows the toolchain version, a k8s context shows the cluster, etc. The
  current prompt shows none of this.
- **Richer git for free.** Starship's `git_status`/`git_state` add
  ahead/behind counts, staged vs unstaged, stash, and merge/rebase/cherry-pick
  state — the current prompt collapses all of that into one `✗`.
- **`cmd_duration`** — slow commands annotate themselves with elapsed time.
- **Performance / robustness.** Rust, with a `command_timeout` (default
  500 ms) and bounded git scanning, so it won't stall the prompt in a huge
  repo the way the current synchronous `git status --porcelain` can.
- **Maintainability.** Declarative TOML instead of hand-rolled zsh + manual
  `%F{}` escape juggling.

Scope chosen: **minimal + contextual** — match today's clean single-line look,
add high-signal modules that appear only when relevant. Auto-recolor is
preserved by styling the Starship config with ANSI palette names, not hex.

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

Design — reproduce `➜  <dir> git:(<branch>) ✗` and add contextual modules,
all styled with **ANSI color names** to keep auto-recolor. Starting point (to
iterate on during implementation):

```toml
# Single line; arrow-first like robbyrussell, cursor after the git/module seg.
format = """
$character\
$directory\
$git_branch$git_status$git_state\
$golang$nodejs$rust$python$elixir\
$docker_context$kubernetes$aws\
$cmd_duration """

add_newline = false

[character]              # the ➜ arrow, colored by last exit status
success_symbol = "[➜](green)"
error_symbol   = "[➜](red)"

[directory]              # basename only, like the old %c
style = "cyan"
truncation_length = 1
truncate_to_repo = false
format = " [$path]($style) "

[git_branch]             # git:(branch) — blue wrapper, red branch
style = "red"
format = "[git:(](blue)[$branch]($style)[)](blue)"

[git_status]             # ✗ when dirty, plus ahead/behind/stash extras
style = "yellow"
format = "[$all_status$ahead_behind]($style)"
conflicted = "✗"
modified = "✗"
untracked = "✗"
staged = "✗"

# Language modules: contextual, only render inside a matching project.
[golang]  format = "[ $version](cyan) "
[nodejs]  format = "[ $version](green) "
[rust]    format = "[ $version](red) "
[python]  format = "[ $version](yellow) "
[elixir]  format = "[ $version](purple) "

[docker_context] format = "[ $context](blue) "
[kubernetes]     disabled = false          # off by default in Starship
[aws]            format = "[ $profile]($style) "

[cmd_duration]
min_time = 2000
format = "[took $duration](yellow) "
```

Styles use bare ANSI names (`green`, `cyan`, `red`, `blue`, `yellow`,
`purple`) that map to the terminal's active 16-color palette → recolors on
theme switch. Explicitly **no hex** anywhere.

### 4. `README.md` — document it (same-change rule)

- New `### Prompt (Starship)` subsection under `## ZSH` (before
  `### Troubleshooting antigen` at `:1013`): what it is, that config lives in
  `zsh/.config/starship.toml`, `brew install starship`, and that `stow zsh`
  links the config. One line on the modules that appear contextually.
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

## Verification

1. `brew bundle --file=Brewfile` (or `brew install starship`) — installs it.
2. `stow -R zsh` — re-links, creating `~/.config/starship.toml`; confirm the
   symlink: `readlink ~/.config/starship.toml`.
3. `exec zsh` — prompt renders `➜  <dir> git:(<branch>)` with dirty marker.
4. Exit-status color: run `false` then check the arrow is red; run `true` then
   check it's green.
5. Contextual modules: `cd` into the repo's `fixtures/` per-language demo dirs
   (rust/go/node/python/elixir) and confirm each toolchain version appears; in
   a plain dir confirm the prompt stays minimal (no modules).
6. Auto-recolor: run `theme light` then `theme dark` and confirm the prompt
   recolors without restarting the shell.
7. Titles intact: `cd` between a git repo and a plain dir, confirm the terminal
   tab title still updates (`_update_term_title` unaffected); `title foo` still
   overrides.
8. Startup cost sane: `time zsh -i -c exit` before/after — Starship's init adds
   little; flag if it regresses noticeably.

## Rollback

The old `_zsh_git_prompt`/`PROMPT` block is preserved in git history — revert
the `zsh/.zshrc_config.zsh` hunk to restore it. Removing `brew "starship"` and
`zsh/.config/starship.toml` fully backs the change out.
