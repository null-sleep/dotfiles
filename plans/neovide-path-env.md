# Plan: Make PATH visible to Neovide GUI launches

When Neovide is launched from Spotlight / Dock / Finder, it inherits env from launchd, not from `.zshrc`. The current `.zshrc_config.zsh` exports `~/.cargo/bin` and similar to PATH, so GUI-launched Neovide can't find rust-analyzer, rustfmt, goimports, or other non-Homebrew binaries. Terminal-launched Neovide is fine because it inherits the parent shell's env.

Goal: GUI-launched Neovide finds the same binaries as terminal-launched.

---

## Requirements

- LSP servers (rust-analyzer) and formatters (rustfmt, goimports) work in GUI-launched Neovide.
- No regression for terminal nvim or for shell sessions.

---

## How zsh startup files load (background)

You do **not** `source` `.zshenv` from `.zshrc`. Zsh sources its startup files
automatically, in a fixed order, for every shell — the rc file never needs to
"know about" the env file:

| File | Runs for |
|------|----------|
| `~/.zshenv` | every zsh — login, interactive, scripts, subshells, and the shell a GUI app spawns to read its env |
| `~/.zprofile` | login shells (macOS runs `/etc/zprofile` → `path_helper` here) |
| `~/.zshrc` | interactive shells (→ this repo's `.zshrc_config.zsh`) |
| `~/.zlogin` | login shells |

`.zshenv` runs **before** `.zshrc`, unconditionally, so its exports are already
in the environment by the time `.zshrc` runs. That is exactly why it fixes GUI
Neovide: a Spotlight/Dock launch never sources `.zshrc`, but it does get
`.zshenv`.

### The macOS `path_helper` gotcha (verified)

`/etc/zprofile` runs `path_helper` for every **login** shell, and it fires
*between* `.zshenv` and `.zshrc`. `path_helper` rebuilds PATH with the system
paths (`/etc/paths`) **first**, shoving any earlier-prepended entries to the
back. Verified on this machine:

```
$ env -i PATH="/opt/homebrew/bin:/Users/dhruv/.cargo/bin:/usr/bin:/bin" /usr/libexec/path_helper -s
PATH="/usr/local/bin:...:/usr/bin:/bin:...:/opt/homebrew/bin:/Users/dhruv/.cargo/bin"
                                                              ^ homebrew + cargo pushed to the END
```

So a *naive* "move the PATH block to `.zshenv`" would **regress the terminal's
ordering**: `~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin` would land
behind `/usr/bin` for login shells. This is the whole reason the PATH block
currently lives in `.zshrc_config.zsh` — that file runs *after* `path_helper`
and re-asserts the right order.

Consequence for the fix: `.zshenv` must be the single source of truth, and
`.zshrc_config.zsh` must **re-assert** the order after `path_helper`.

## Options

### Option A — `.zshenv` as PATH single source of truth, re-asserted in rc (recommended)

Move the **entire** PATH block (not just cargo/local) to `zsh/.zshenv`, and
have `.zshrc_config.zsh` re-source it once to re-assert order after
`path_helper`. `typeset -U` makes the re-source idempotent and prevents PATH
from growing across nested subshells.

Steps:
1. Create `zsh/.zshenv` in the stow package containing:
   - `typeset -U path PATH` (unique array: re-prepending an existing entry
     moves it to the front instead of duplicating — makes re-sourcing safe).
   - The full prepend block, in current order: `/opt/homebrew/bin` →
     `python@3.12/libexec/bin` → `~/.cargo/bin` → `~/.local/bin`.
   - `GOPATH` + `$GOPATH/bin` append (currently at `.zshrc_config.zsh:330-333`).
   - Keep it cheap: no antigen, completions, or prompt.
2. In `.zshrc_config.zsh`, replace the PATH block (lines ~146-157) and the GO
   block (lines ~330-333) with a single `source ~/.zshenv`, commented to
   explain it re-asserts order after `path_helper`.
3. `stow zsh` symlinks `~/.zshenv` (no manual steps). Add nothing to
   `.stow-local-ignore`.
4. Note: `~/.zshrc` (a real home file, **not** stowed) also does
   `export PATH="$PATH:$HOME/.local/bin"` — a redundant low-priority append now
   neutralized by `typeset -U` (the earlier high-priority entry wins). Harmless;
   optionally clean up by hand later.

GUI order caveat: a GUI launch that spawns a *login-but-non-interactive* shell
would hit `path_helper` and skip the `.zshrc` re-assert, so it could get
system-first *ordering*. That is fine for the goal — the binaries are all
**present** (no competing system rust-analyzer/goimports to shadow); precedence
only matters in the interactive terminal, where the re-assert handles it.

### Option B — LaunchAgent calling `launchctl setenv PATH ...`

Sets PATH for all GUI apps, not just Neovide. Survives reboots via `~/Library/LaunchAgents/<id>.plist`.

Pros: works for any GUI app (not just Neovide).
Cons: more machinery, env becomes hidden global state, plist needs to live in dotfiles + a `launchctl load` step.

Skip unless other GUI apps also need this.

### Option C — Always launch Neovide from terminal

`fork = true` is already set, so terminal-launched Neovide survives terminal close. Just don't use Spotlight.

Pros: zero config.
Cons: muscle memory; doesn't fix the underlying issue.

---

## Recommendation

Option A, with the `path_helper` re-assert baked in (see the refined steps
above) — not the naive move the original draft described, which would regress
terminal PATH order. It's the upstream-recommended approach, scoped to zsh, and
stows cleanly.

---

## Verification checklist

- [ ] `which rust-analyzer` works in Neovide opened from Spotlight
- [ ] `:ConformInfo` shows all formatters detected
- [ ] LSP attaches in a `.rs` file opened via Spotlight launch
- [ ] Terminal nvim still works
- [ ] Shell prompt, antigen, direnv still work in iTerm2/kitty

---

## Update README

Add a one-paragraph note in the ZSH section explaining the `.zshenv` vs `.zshrc_config.zsh` split and *why* (GUI launches).
