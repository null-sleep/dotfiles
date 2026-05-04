# Plan: Make PATH visible to Neovide GUI launches

When Neovide is launched from Spotlight / Dock / Finder, it inherits env from launchd, not from `.zshrc`. The current `.zshrc_config.zsh` exports `~/.cargo/bin` and similar to PATH, so GUI-launched Neovide can't find rust-analyzer, rustfmt, goimports, or other non-Homebrew binaries. Terminal-launched Neovide is fine because it inherits the parent shell's env.

Goal: GUI-launched Neovide finds the same binaries as terminal-launched.

---

## Requirements

- LSP servers (rust-analyzer) and formatters (rustfmt, goimports) work in GUI-launched Neovide.
- No regression for terminal nvim or for shell sessions.
- Per-machine variations (e.g. `~/.zshrc_work.zsh`) still work.

---

## Options

### Option A — Move PATH exports to `~/.zshenv` (recommended)

`.zshenv` runs for every zsh invocation (login, interactive, non-interactive), so the non-interactive shell Neovide spawns will source it. Recommended in Neovide's FAQ.

Steps:
1. Create `zsh/.zshenv` in the stow package.
2. Move PATH-only exports out of `.zshrc_config.zsh` into `.zshenv`. Specifically:
   - `~/.cargo/bin`
   - `~/go/bin` (if present)
   - `~/.local/bin` (used for `nvim-editor`)
3. Keep `.zshrc_config.zsh` for everything that needs an interactive shell (aliases, prompt, antigen, completions, direnv hook).
4. `stow zsh` will symlink `~/.zshenv` (no manual steps).
5. Verify: launch Neovide from Spotlight, run `:echo $PATH` and `:!which rust-analyzer`.

Edge cases:
- If `.zshenv` runs *too* early (before Homebrew shellenv), order matters. Homebrew's `/opt/homebrew/bin` is already on launchd's default PATH on Apple Silicon, so this is usually fine — but verify.
- `.zshenv` is sourced for *every* zsh, including subshells. Keep it cheap; no antigen, no completions.

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

Option A. It's the upstream-recommended approach, scoped to zsh, and stows cleanly.

---

## Verification checklist

- [ ] `which rust-analyzer` works in Neovide opened from Spotlight
- [ ] `:ConformInfo` shows all formatters detected
- [ ] LSP attaches in a `.rs` file opened via Spotlight launch
- [ ] Terminal nvim still works
- [ ] Shell prompt, antigen, direnv still work in iTerm2/kitty
- [ ] `~/.zshrc_work.zsh` still loads on work machines

---

## Update README

Add a one-paragraph note in the ZSH section explaining the `.zshenv` vs `.zshrc_config.zsh` split and *why* (GUI launches).
