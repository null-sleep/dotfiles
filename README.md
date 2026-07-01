# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick start (fresh machine)

Ordered path for a brand-new macOS machine. Each step links to its detailed
section below; the rest of this README is reference material for individual tools.

1. **Homebrew** — `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. **Xcode Command Line Tools** (C compiler for treesitter / fzf-native) — `xcode-select --install`
3. **Clone this repo** to `~/src/dotfiles` (HTTPS for now — the [Git](#git) step later rewrites GitHub to SSH):
   ```bash
   mkdir -p ~/src && git clone https://github.com/null-sleep/dotfiles.git ~/src/dotfiles
   ```
4. **Install everything from the [`Brewfile`](Brewfile)** — `cd ~/src/dotfiles && brew bundle`. Installs every core CLI, font, runtime, and GUI app in one shot — idempotent, safe to re-run (a few situational tools like iTerm2 are left commented in the Brewfile). The SF Mono Square tap is marked `trusted: true` so `brew bundle` installs it without a prompt. Then finish the [Fonts](#fonts) step — SF Mono Square needs a manual symlink into `~/Library/Fonts`.
5. **Rust** — not in the Brewfile; install via rustup ([Languages](#languages)).
6. **Stow the configs** — `stow nvim zsh && stow --no-folding claude` (add `kitty`/`zellij` only if you enabled those optional casks) ([Setup](#setup)). First create `zsh/.stow-local-ignore` if this is a personal (non-work) machine — see [Per-machine config](#per-machine-config).
7. **Per-tool setup:** antigen + zsh-direnv + `~/.zshrc` ([ZSH](#zsh)); git identity + SSH key/config ([Git](#git)); Claude Code setup scripts ([Claude Code](#claude-code)); Neovide config symlink ([Neovide](#neovide)).
8. **Open a new shell** (`exec zsh`). First launch clones antigen bundles (~20s); first `nvim` clones plugins + Mason servers (~1 min).
9. **[Verify your setup](#verify-your-setup)** with the smoke test.

## Fonts

Install these **first** — they are prerequisites for the terminals (iTerm2, kitty)
and editors (nvim, Neovide) configured here. Without a Nerd Font, icons and glyphs
render as tofu boxes (▯), and iTerm2 won't render the exported profiles correctly.

```bash
# Hack Nerd Font (used by iTerm2, kitty, nvim, Neovide for icons and glyphs)
brew install font-hack-nerd-font

# SF Mono Square (SF Mono patched with Nerd Font glyphs and square CJK characters)
brew tap delphinus/sfmono-square
# Newer Homebrew refuses to load formulae from untrusted third-party taps;
# trust this one before installing (otherwise the install errors out).
brew trust delphinus/sfmono-square
brew install sfmono-square
```

`font-hack-nerd-font` is a **cask** — it installs straight into `~/Library/Fonts`.
`sfmono-square` is a **formula** — it only *builds* the `.otf` files into its
Cellar and does **not** install them where apps can see them, so symlink them in:

```bash
mkdir -p ~/Library/Fonts
for f in "$(brew --prefix)"/opt/sfmono-square/share/fonts/*.otf; do
  ln -sfn "$f" ~/Library/Fonts/"$(basename "$f")"
done
```

Restart any running terminal afterwards so it picks up the newly installed fonts.

## Setup

```bash
brew install stow            # if you skipped `brew bundle`; stow itself is required
cd ~/src/dotfiles
stow nvim
stow zsh
stow --no-folding claude     # --no-folding: see the Claude Code section
# Optional terminals — only if you uncommented their casks in the Brewfile:
stow kitty                   # needs the kitty cask
stow zellij                  # needs the zellij formula
```

> **Stowing only symlinks configs — it does not install the tools they depend
> on.** Install the [Fonts](#fonts) above first, then work through the per-tool
> dependency steps in [Languages](#languages), [ZSH](#zsh), and [Neo Vim](#neo-vim)
> — a fresh machine needs all of them, not just the stow commands above.

Stow reads `.stowrc` in this repo which sets `--target` to `~`, so you don't need to pass `-t ~` manually.

To add a new config (e.g. tmux), mirror the home-relative path:

```
dotfiles/tmux/.config/tmux/tmux.conf
```

Then run `stow tmux`.

## Verify your setup

After working through [Quick start](#quick-start-fresh-machine), smoke-test each piece:

| Check | Expected |
|---|---|
| Open a new shell | Prompt renders `➜ <dir> git:(<branch>) ✗`, not the macOS `… %` default |
| `z foo` / `zi` | jumps by frecency / opens an fzf picker ([zoxide](#directory-jumping-zoxide)) |
| `command -v rg fd fzf zoxide direnv stow` | all resolve |
| `python3 --version` | 3.12.x (not the system 3.9) |
| `rustc --version` && `cargo --version` | both resolve (rustup) |
| `ssh -T git@github.com` | `Hi <username>!` ([SSH for GitHub](#ssh-for-github)) |
| Terminal glyphs | file-tree / git icons render, not tofu boxes (▯) — fonts installed |
| `~/.local/bin/claude-nvim check` | prints `startup-ok` (nvim config loads clean) |
| `nvim` → `:Mason` | LSP servers/tools show installed, not failed ([Languages](#languages)) |
| `nvim` → `:checkhealth` | treesitter, telescope, lsp, blink.cmp all green |
| Claude Code | statusline renders; theme is Catppuccin Latte ([Claude Code](#claude-code)) |

If the prompt shows the macOS default instead of `➜`, see [Troubleshooting antigen](#troubleshooting-antigen). If `:Mason` shows failures, a language runtime is missing — see the callout in [Languages](#languages).

## Languages

Language runtimes required by nvim LSP servers and treesitter.

```bash
# Go
brew install go

# Node (for ts_ls)
brew install node

# Python (pyright LSP + yamllint linter). Mason needs python ≥ 3.10; macOS's
# system python3 is 3.9, too old. python@3.12 is keg-only, so .zshrc_config.zsh
# prepends its libexec/bin to PATH — that makes the unversioned `python3`/`pip3`
# resolve to 3.12 instead of /usr/bin/python3.
brew install python@3.12

# Elixir (includes Erlang)
brew install elixir

# Rust (via rustup — do not use brew install rust)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup component add clippy rustfmt rust-analyzer rust-src

# Extra cargo subcommands (built from source via cargo install)
cargo install cargo-nextest --locked   # --locked is required by nextest
cargo install cargo-audit
```

Rust tools installed by rustup: `cargo`, `rustc`, `clippy`, `rustfmt`, `rust-analyzer`, `rust-src`. The `~/.cargo/bin` PATH entry in `.zshrc_config.zsh` makes them available in the shell.

Additional cargo subcommands installed via `cargo install`: `cargo-nextest` (faster, better test runner — `cargo nextest run`) and `cargo-audit` (scans `Cargo.lock` for crates with known security advisories — `cargo audit`).

> **Install these runtimes *before* first launching nvim.** On startup, Mason
> installs the LSP servers, formatters, and linters from its `ensure_installed`
> lists by shelling out to `npm`, `go`, `pip`, etc. If a runtime isn't on
> `$PATH`, that package fails with `Failed to spawn process … ENOENT` or a
> version error (e.g. yamllint needs python ≥ 3.10) — visible in `:Mason` and
> `:MasonLog`. Prebuilt-binary packages (stylua, ruff, taplo, rust-analyzer,
> golangci-lint, lua_ls, etc.) still install fine. To recover, install the missing
> runtime and **relaunch nvim** — the `ensure_installed` lists retry on startup
> — or reinstall the package from the `:Mason` UI.

### Format-on-save tools

conform.nvim runs CLI formatters; install as needed per language. Files
in unconfigured languages (or with missing binaries) fall back to LSP
formatting where supported, or no-op cleanly.

```bash
brew install ruff                                           # Python
go install golang.org/x/tools/cmd/goimports@latest          # Go imports (gofmt ships with go)
npm install -g @fsouza/prettierd                            # JS, TS, JSON, YAML (daemon-mode)
# rustfmt ships with rustup
# Lua: formatted by lua_ls (LSP fallback) — no extra install
```

Run `:ConformInfo` inside Neovim to see which formatters are configured
per filetype and which binaries are detected on `$PATH`.

## Colima

Free container runtime for macOS — a Docker Desktop alternative.

```bash
brew install colima docker

# Apple Silicon
colima start --cpu 8 --memory 8 --arch aarch64 --vm-type=vz --vz-rosetta

# Intel
colima start --cpu 2 --memory 4
```

The `docker` CLI talks to Colima's daemon automatically. The `.zshrc_work.zsh` file includes a `colima_start` helper and an auto-check that warns if Colima isn't running.

### Default config (so `colima start` needs no flags)

Instead of passing flags every time, bake the defaults into a template that
Colima applies to any **newly created** profile. A plain `colima start` then
picks up the same CPU/memory/arch/vz config as the `colima_start` helper.

```bash
# Generate the default template at ~/.colima/_templates/default.yaml,
# pre-filled with all keys and their defaults, then open it for editing.
colima template
```

Set these keys for the Apple Silicon config:

```yaml
cpu: 8
memory: 8
arch: aarch64
vmType: vz
rosetta: true
```

The template only applies at VM *creation*. If a profile already exists, edit
its live config with `colima start --edit` (or re-create with
`colima delete && colima start`) — `arch` and `vmType` in particular cannot
change after the VM is built.

## Claude Code

The `claude` stow package manages the status line script — a custom status bar that displays model name, git branch, context window %, session/monthly cost, and per-message context growth bars — plus a custom **Catppuccin Latte** color theme.

### Setup

```bash
cd ~/src/dotfiles
stow --no-folding claude
# Inject the statusLine block into ~/.claude/settings.json (one-time)
bash ~/src/dotfiles/claude/setup-statusline.sh
# Point Claude at the "active" theme slot in ~/.claude/settings.json (one-time)
bash ~/src/dotfiles/claude/setup-theme.sh
# Enable the LSP plugins (Lua/Python/Rust/Go) in ~/.claude/settings.json (one-time)
bash ~/src/dotfiles/claude/setup-lsp-plugins.sh
```

The `--no-folding` flag is important: it keeps `~/.claude/themes/` and
`~/.claude/skills/` as **real directories** with only the repo's individual
files symlinked in, so any machine-local themes or skills already there coexist
untouched. Without it, stow would replace a non-existent `~/.claude/themes/`
with a single directory symlink (a "fold"), which can't hold local files
alongside the synced ones.

All three setup scripts use `jq` to edit `settings.json` idempotently. `setup-statusline.sh` adds the `statusLine` config (and rewrites a hardcoded path to `$HOME` if present); `setup-theme.sh` sets `"theme": "custom:active"` and seeds `~/.claude/themes/active.json` so the unified `theme` switcher (see [Unified theme switching](#unified-theme-switching)) can swap dark/light live; `setup-lsp-plugins.sh` enables the LSP plugins (see [LSP plugins](#lsp-plugins-code-intelligence) below). Re-running any of them when already configured is a no-op.

### What's managed

| File | Method |
|---|---|
| `~/.claude/statusline-command.sh` | Symlinked via stow |
| `~/.claude/themes/catppuccin-latte.json` | Symlinked via stow (`--no-folding`) |
| `~/.claude/skills/nvim-theme-to-claude/SKILL.md` | Symlinked via stow (`--no-folding`) |
| `~/.claude/settings.json` statusLine block | Injected by `setup-statusline.sh` |
| `~/.claude/settings.json` theme key | Injected by `setup-theme.sh` |
| `~/.claude/settings.json` `enabledPlugins` (LSP) | Injected by `setup-lsp-plugins.sh` |

`settings.json` itself is **not** stowed — it contains machine-specific content (plugins, hooks, MCP servers, permissions). The three `setup-*.sh` scripts merge just their own keys into it idempotently with `jq`, so re-running any of them is a no-op.

### LSP plugins (code intelligence)

Claude Code has a built-in **LSP tool** (go-to-definition, find-references, hover, call hierarchy) that works per file type only when the matching language-server plugin is enabled **and** its server binary is on `PATH`. This repo enables four, via `setup-lsp-plugins.sh`:

| Plugin (`@claude-plugins-official`) | Files | Server binary | Install |
|---|---|---|---|
| `lua-lsp` | `.lua` | `lua-language-server` | `brew install lua-language-server` (in Brewfile) |
| `pyright-lsp` | `.py` `.pyi` | `pyright-langserver` | `npm install -g pyright` |
| `rust-analyzer-lsp` | `.rs` | `rust-analyzer` | `rustup component add rust-analyzer` |
| `gopls-lsp` | `.go` | `gopls` | `go install golang.org/x/tools/gopls@latest` |

**The plugins do not ship the server** — each is a thin config wrapper that shells out to the binary by name, resolved against `PATH`. `setup-lsp-plugins.sh` enables the plugins and then prints which of the four binaries are present vs. missing (with the install hint), so a fresh machine gets a clear checklist. A missing binary is harmless — the LSP tool just errors for that one file type until you install it. **Restart Claude Code** after enabling, so it discovers the plugins.

> **Lua server vs. Mason.** `lua-language-server` is installed **twice, deliberately**: the Homebrew copy (`/opt/homebrew/bin`, on `PATH`) is what Claude Code uses, and nvim uses its own **Mason** copy (`~/.local/share/nvim/mason/bin`, *not* on `PATH`, launched by absolute path). They're independent installs in separate prefixes — they don't collide, share config, or update together (`brew upgrade` vs. `:MasonUpdate`). The brew copy is required because Claude resolves the binary via `PATH` and Mason's bin dir isn't on it. The other three servers (`pyright`, `rust-analyzer`, `gopls`) are global by nature, so both tools share the single PATH copy.

### Theme

`catppuccin-latte.json` is a custom Claude Code theme (requires Claude Code v2.1.118+) whose palette matches the Neovim `catppuccin-latte` colorscheme, including nvim's exact diff-blend values.

`settings.json` doesn't name a specific theme directly — it pins the fixed slug `"theme": "custom:active"`, which resolves to `~/.claude/themes/active.json`. The [unified `theme` switcher](#unified-theme-switching) overwrites that file with the dark or light palette, and because Claude hot-reloads theme **files** (not the `theme` setting) the change applies to running sessions with no restart. To switch by hand instead, just pick a theme in `/theme`.

**Adding more synced themes/skills:** drop the file into `claude/.claude/themes/`
or `claude/.claude/skills/` in the repo and re-run `stow --no-folding claude`.
Stow is non-destructive — it links the new file alongside whatever is already in
the target directory and **never overwrites** a real file; if a real file of the
same name already exists it aborts the whole operation rather than clobbering it
(pass `--adopt` to pull that pre-existing file into the repo instead). Themes you
create locally via `/theme` land as real files in `~/.claude/themes/` and stay
local until you move them into the repo and re-stow.

To build another theme matching a different Neovim colorscheme, use the **`nvim-theme-to-claude`** skill (`claude/.claude/skills/`, synced to `~/.claude/skills/` via stow). It reads the nvim palette, maps it to Claude Code's color tokens, and reproduces nvim's exact diff-blend math — invoke it with something like "make a Claude theme matching my tokyonight nvim theme".

### Syncing to another machine

To pull the theme and skill onto a machine that already has a `~/.claude/`
directory (and possibly an older checkout of this repo):

```bash
# 1. push from the machine where you made the changes
git -C ~/src/dotfiles push

# 2. on the other machine
cd ~/src/dotfiles
git pull
stow -R --no-folding claude            # the key command — see below
bash ~/src/dotfiles/claude/setup-theme.sh   # optional: pin custom:active + seed active.json
```

Then **restart Claude Code** so it discovers the new skill and theme.

Use `stow -R --no-folding claude` (not a plain `stow claude`):

- **`-R` (restow)** removes any stale links from the older checkout first. If
  that machine has `~/.claude/themes` as an old folded directory symlink (from a
  previous `stow claude`), `-R` unfolds it into a real directory before
  relinking. It works whether the target is currently a real dir, a folded
  symlink, or was never stowed.
- **`--no-folding`** keeps `~/.claude/themes/` and `~/.claude/skills/` as real
  directories, so the existing folders and any machine-local files in them are
  preserved.
- **Non-destructive**: if that machine already has a real `catppuccin-latte.json`
  or its own `nvim-theme-to-claude/` skill, stow aborts without touching
  anything. To merge instead, move the local file aside, or run
  `stow --adopt --no-folding claude` to pull the existing file into the repo
  (then `git checkout -- <file>` if you want the repo's version to win).

For the skill only, skip the `setup-theme.sh` step — `git pull`,
`stow -R --no-folding claude`, restart. The skill then lives at
`~/.claude/skills/nvim-theme-to-claude/` and is invokable from any project.

## Unified theme switching

One command flips **Claude Code, Neovim, and the macOS system appearance**
between a predefined dark and light theme at once — live, no restarts. **iTerm2
isn't driven by the script at all**: a single profile follows macOS appearance
natively (see one-time setup below), so flipping the system appearance recolors
every iTerm window — new *and* existing.

```bash
theme            # toggle dark/light (pins, like dark/light below)
theme dark       # PIN dark everywhere (turns macOS Auto OFF)
theme light      # PIN light everywhere (turns macOS Auto OFF)
theme auto       # hand control back to macOS Auto (sunset/sunrise); everything follows
theme follow     # match Claude+nvim to current macOS appearance (don't set macOS)
theme watch      # daemon loop used by the auto-follow LaunchAgent (see below)
theme status     # show appearance, macOS mode (auto/pinned), and follower state
```

**Three modes — `dark` · `light` · `auto`:**

- **`dark` / `light`** *pin* that appearance everywhere at once: macOS Auto is
  switched **off**, the macOS appearance is set to the fixed value, and Claude +
  nvim are swapped to match. It stays put until you change it again — exactly like
  choosing Light or Dark in **System Settings → Appearance**.
- **`auto`** hands the wheel back to macOS: it re-enables native **Auto**
  (sunset/sunrise), and Claude + nvim follow via the [watch
  LaunchAgent](#auto-follow-on-macos-appearance-changes). One caveat — the macOS
  Auto flag governs *future* evaluations, so macOS applies the schedule at the
  next sunrise/sunset (or when you next click **Auto** in System Settings); it
  doesn't retroactively repaint the current desktop. `theme auto` syncs Claude +
  nvim to the present appearance immediately so nothing is out of step meanwhile.

The predefined pair (edit the `LIGHT`/`DARK` arrays at the top of
`zsh/.local/bin/theme` to change it):

| Mode  | Claude theme       | nvim variant       | macOS appearance |
|-------|--------------------|--------------------|------------------|
| light | `catppuccin-latte` | `catppuccin-latte` | light (pinned)   |
| dark  | `dracula`          | `dracula`          | dark (pinned)    |
| auto  | follows macOS      | follows macOS      | Auto (schedule)  |

### One-time iTerm2 setup (single profile, follows macOS)

**iTerm2 follows macOS appearance natively** — no script, daemon, or escape
codes involved. Since 3.4, a profile can store *two* color sets and iTerm swaps
between them the instant the system switches between Light and Dark mode. We lean
entirely on that: the `theme` command only flips the macOS appearance (step 1
below in [How each tool switches live](#how-each-tool-switches-live)), and iTerm
recolors **every window, new and already-open, by itself**.

So instead of two separate profiles, one profile carries **separate colors for
light and dark mode**. In **Settings → Profiles → Colors** for your default
profile:

1. Enable **"Use separate colors for light and dark mode"** (stored as the
   `Use Separate Colors for Light and Dark Mode` profile key).
2. With the **Light** mode tab selected: **Color Presets → Import** →
   `iterm2/catppuccin-latte.itermcolors`, then select it.
3. With the **Dark** mode tab selected: **Color Presets → Import** →
   `iterm2/Dracula.itermcolors`, then select it.
4. Make sure this profile is the default (**Other Actions → Set as Default**).

A second `Default Dark`/`Default Light` profile is then redundant. After this,
iTerm needs nothing from the `theme` script — it follows `macOS` directly.

### How each tool switches live

- **macOS** — `osascript` sets the system appearance. This is the hinge the
  whole design turns on; everything else either follows it (iTerm2) or is
  switched alongside it (Claude, nvim).
- **iTerm2** — not driven by the script. Its native per-profile "separate colors
  for light and dark mode" (see [setup above](#one-time-iterm2-setup-single-profile-follows-macos))
  reacts to the macOS appearance change on its own, recoloring all windows
  including ones opened *after* the switch. (An earlier version wrote the
  `SetProfile` escape code to each open session's tty — that couldn't reach
  windows that didn't exist yet, which is exactly what the native feature fixes.)
- **Claude Code** — Claude hot-reloads theme *files* but not the `theme`
  *setting*, so `settings.json` pins the fixed slug `custom:active` and the
  script overwrites `~/.claude/themes/active.json` with the chosen palette.
  Running sessions recolor instantly. (See [Claude Code → Theme](#theme).)
- **Neovim** — the script writes the variant to nvim's theme state file
  (`~/.local/share/nvim/theme.txt`); every running instance live-applies it via
  the `fs_event` watcher in `themes.lua` (`M.watch()`, armed from `plugins.lua`).
  New instances read the same file at startup. This also means confirming a theme
  in the `<leader>st` picker syncs every open Neovim. The throwaway `claude-nvim`
  headless runs skip the watcher (`CLAUDE_NVIM=1`).

The `theme` script is stowed via the `zsh` package (`~/.local/bin` → repo), so
it's on `PATH` automatically. macOS will prompt once for Automation access to
control System Events (to set the appearance) — grant it.

### Auto-follow on macOS appearance changes

`theme dark|light` *pin* a fixed appearance. `theme auto` (or **System Settings →
Appearance → Auto**) hands control back to macOS, which then flips its appearance
**on its own** — dark at sunset, light at sunrise — or via a Control Center
toggle. iTerm2 follows those native flips automatically, but nothing would tell
Claude or nvim. The **theme-follow LaunchAgent** closes that gap: it keeps `theme
watch` running, which polls the macOS appearance and runs `theme follow` on every
flip — so Claude + nvim track macOS no matter *who* changed it. This is what makes
`theme auto` "follow macOS everywhere."

```bash
stow --no-folding macos             # symlink the plist into ~/Library/LaunchAgents/
bash ~/src/dotfiles/macos/setup-theme-follow.sh   # load + start the agent
# then (optional): System Settings → Appearance → Auto
```

`--no-folding` matters here for the same reason as the `claude` package: on a
fresh machine `~/Library/LaunchAgents/` may not exist yet, and a plain `stow
macos` would *fold* — symlinking the whole directory into the repo, so every
other app's plist would then land in your dotfiles. `--no-folding` makes stow
create the real directory and link only the plist file.

After this the whole chain is automatic: macOS flips (on a schedule or by hand)
→ iTerm2 recolors natively, and the follower repaints Claude + nvim to match.

- **No Automation prompt, no loop.** `watch`/`follow` read the appearance with
  `defaults read -g AppleInterfaceStyle` (not `osascript`), so the agent runs
  unattended; and `follow` only touches Claude + nvim — it never writes the macOS
  appearance back, so it can't fight Auto mode or ping-pong with the watcher.
- **Portable plist.** `com.dhruv.theme-follow.plist` runs
  `zsh -c 'exec "$HOME/.local/bin/theme" watch'`, so `$HOME` expands at launch —
  the same stowed file works on any machine, no path rewriting.
- **Tuning / disabling.** The poll interval is `THEME_WATCH_INTERVAL` seconds
  (default `2`), set in the plist's `EnvironmentVariables` — launchd doesn't
  inherit your shell env, so edit it *there* (then re-run `setup-theme-follow.sh`
  to reload), not in `.zshrc`. `theme status` reports whether the follower is
  loaded; logs are at `/tmp/theme-follow.{out,err}.log` (chosen over
  `~/Library/Logs` because a plist log path can't expand `$HOME` and we keep the
  plist portable). Disable with
  `launchctl bootout gui/$(id -u)/com.dhruv.theme-follow`.

`macos/setup-theme-follow.sh` is `.stow-local-ignore`d (like the `claude/setup-*`
scripts), so `stow macos` only links the plist, not the bootstrap script.

## Claude Squad

Terminal app for running multiple AI coding agents (Claude Code, Codex, Gemini, Aider) in parallel. Each session gets an isolated [git worktree](https://git-scm.com/docs/git-worktree) and its own [tmux](https://github.com/tmux/tmux) session — no branch conflicts, and tasks keep running in the background. See [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad).

### Setup

```bash
# Prerequisites
brew install tmux gh

# Install claude-squad and symlink as `cs`
brew install claude-squad
ln -s "$(brew --prefix)/bin/claude-squad" "$(brew --prefix)/bin/cs"

# Auth for `gh` (push branches from sessions)
gh auth login
```

### Keymaps

**Sessions:**

| Key | Action |
|---|---|
| `n` | New session |
| `N` | New session with a starting prompt |
| `D` | Kill (delete) selected session |
| `↑`/`k`, `↓`/`j` | Navigate sessions |

**Actions:**

| Key | Action |
|---|---|
| `↵` / `o` | Attach to selected session (re-prompt) |
| `Ctrl+q` | Detach from session |
| `p` | Commit and push branch to GitHub |
| `c` | Checkout — commits changes and pauses the session |
| `r` | Resume a paused session |
| `?` | Help menu |

**Navigation:**

| Key | Action |
|---|---|
| `tab` | Switch between preview and diff tabs |
| `Shift+↑` / `Shift+↓` | Scroll diff view |
| `q` | Quit |

### Commands

| Command | Description |
|---|---|
| `cs debug` | Print config and data paths |
| `cs reset` | Wipe all stored sessions (use if state gets corrupted) |
| `cs version` | Print version |

### Tips

- **Background work**: detach with `Ctrl+q` and the agent keeps running. Come back later with `↵`/`o`.
- **Review before pushing**: hit `tab` to see the diff, then `s` to commit + push or `c` to checkout the branch locally.
- **Failed to start session**: if you see `timed out waiting for tmux session`, update the underlying agent (`claude`, `codex`, etc.) — the error is almost always a stale binary.

## Neo Vim

Requires Neovim >= 0.12 (uses `vim.pack`, `vim.lsp.config`, native treesitter API).

```bash
brew install nvim rg fzf fd tree-sitter-cli curl git
```

Compile tools: `telescope-fzf-native` needs `make` (ships with Xcode Command Line Tools — run `xcode-select --install` if missing).

Then stow and launch:

```bash
cd ~/src/dotfiles
stow nvim
nvim
```

On first launch nvim will:
1. Download all plugins via `vim.pack` (native package manager)
2. Compile `telescope-fzf-native` via `make`
3. Install treesitter parsers for configured languages
4. Download the `blink.cmp` fuzzy binary (pre-built, requires `curl`)
5. Install LSP servers via mason (requires internet)

### Treesitter

Treesitter is configured using nvim 0.12's native API — no plugin config table needed.
The `nvim-treesitter` plugin is registered via `vim.pack` (nvim's built-in package manager)
and is used solely for parser management (installing/updating parsers).

Highlighting and folding are handled natively:
- **Highlighting**: `vim.treesitter.start()` is attached per buffer via a `FileType` autocmd
- **Folding**: AST-based folding via `vim.treesitter.foldexpr()` (files open fully expanded)
- **Large files**: treesitter is skipped for buffers >50k lines or >1.5MB to prevent UI lag
- **Auto-install on startup**: missing parsers from `ensure_installed` are installed automatically on startup
- **Auto-install on open**: if a file is opened and its parser isn't installed, `TSInstall` is triggered automatically
- **Auto-recompile on update**: a `PackChanged` autocmd detects when `nvim-treesitter` is updated and re-runs `TSUpdate` to recompile parsers

Parsers are locked in `nvim-pack-lock.json` — commit this file to pin versions across machines.

**Commands:**

| Command | Description |
|---|---|
| `:TSUpdate` | Update all installed parsers |
| `:TSUpdate <lang>` | Update a specific parser |
| `:TSInstall <lang>` | Install a parser manually |
| `:InspectTree` | View the parsed AST for the current buffer |
| `:Inspect` | Show highlight groups under the cursor |
| `:checkhealth nvim-treesitter` | Verify installed parsers and requirements |

### Telescope

Fuzzy finder for files, text search, buffers, and help. Uses `telescope-fzf-native` (compiled C extension) for faster sorting. Leader key is `<Space>`.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<Space>sf` | Find files by name |
| `<Space>sg` | Live grep (search file contents) |
| `<Space>m` | Buffer picker (numbered rows; `<M-1>`..`<M-9>` jumps to that row) |
| `<Space>sh` | Search help tags |
| `<Space>sr` | Resume last search |
| `<Space>s/` | Fuzzy search inside current buffer |
| `<Space>so` | Recent files |
| `<Space>sm` | Modified files (git status) |
| `<Space>ss` | Symbols (workspace) — fans query to all active LSPs; type `name path` to also filter by file |
| `<Space>sS` | Symbols (document) — columns: icon, name, kind; type `function` / `variable` to filter by kind |
| `<Space>st` | Theme picker (live preview) |
| `<Space>sk` | Keymap picker (fuzzy-search all mappings, including built-in motions) |
| `<Space>sF` | Toggle file-type filter presets (scopes `<Space>sf` and `<Space>sg`) |

**Inside the telescope window:**

| Key | Action |
|---|---|
| Type anything | Fuzzy filter results |
| `<C-n>` / `<C-p>` | Move down / up |
| `<CR>` | Open highlighted entry (or all multi-selected entries) |
| `<C-v>` | Open in vertical split |
| `<C-x>` | Open in horizontal split |
| `<C-t>` | Open in new tab |
| `<Tab>` / `<S-Tab>` | Toggle multi-select on the current row, move down / up |
| `<C-q>` | Send all current results to the quickfix list and open it |
| `<M-q>` | Send only multi-selected entries to the quickfix list and open it |
| `<M-d>` | In the buffer picker (`<Space>m`): delete the highlighted buffer (or all multi-selected) |
| `<Esc>` | Close |

**Multi-select workflows:**
- `<Tab>` marks an entry (a `+` appears in the gutter) and moves the cursor down; `<S-Tab>` marks and moves up. Repeat to build up a set.
- With a multi-selection: `<CR>` opens them all (first into the current window, the rest as buffers); `<C-v>`/`<C-x>`/`<C-t>` fan them into splits or tabs; `<M-q>` sends just the selected entries to the quickfix list.
- `<C-q>` ignores tab marks and dumps the entire result list into qflist — handy after a grep when you want every match.
- Common pattern: `<Space>sg` → search → `<Tab>` the matches you want → `<M-q>` → `:cdo s/old/new/g | update`.

**Per-picker notes:**
- `<Space>sf` / `<Space>sg` (find files / live grep) — default `<Tab>` multi-select works as above.
- `<Space>m` (buffer picker) — default `<Tab>` multi-select works. Tab a few buffers and press `<M-d>` to bulk-close them; the picker stays open.
- `<Space>sm` (gitstatus) — `<Tab>` is **overridden** to stage / unstage the file under the cursor (no multi-select in this picker).
- `<Space>sF` (filter presets) — `<Tab>` toggles the highlighted preset on/off (also a custom override).

**Tips:**
- Both file search and live grep include hidden files/directories (e.g. `.github/`). The `.git/` directory and `node_modules/` are excluded via `file_ignore_patterns`.
- In `<Space>sg` (live grep), type a space after your search term to filter by filename, e.g. `vim.pack plugins` searches for `vim.pack` only in files matching `plugins`
- `<Space>sr` reopens the last search with the same query — useful when you close telescope and want to get back
- `<Space>sF` opens a preset picker (Tab to toggle on/off). Active presets pre-filter the file set that `<Space>sf` and `<Space>sg` operate over — e.g. enable `go_src` to limit results to non-test, non-vendor Go files. Presets are defined in `lua/pickers/filter.lua` and toggle state lasts until you quit nvim. Composes with the space-suffix trick above: presets narrow the files, the space-filter narrows the result list.
- `<Space>ss` uses a two-token prompt: the first word is the symbol name query sent to the LSP; everything after the first space narrows results by file path. E.g. `render utils` finds symbols named "render" in files matching "utils". By default the query fans out to every active LSP client in the session (not just the current buffer's). `<Space>ts` toggles to buffer-only mode.

**Commands:**

| Command | Description |
|---|---|
| `:checkhealth telescope` | Verify telescope and fzf-native are working |

### LSP (Language Server Protocol)

IDE features powered by nvim's built-in LSP client. Four plugins work together:
- **mason.nvim** — installs and manages language servers (`:Mason` to open UI)
- **mason-lspconfig.nvim** — bridges mason and lspconfig, auto-installs servers on startup
- **nvim-lspconfig** — pre-configured setups for each language server
- **lazydev.nvim** — provides Neovim API type annotations to lua_ls (no manual workspace config needed)

Configured servers: `lua_ls`, `pyright`, `ts_ls`, `gopls`, `rust_analyzer`, `elixirls`

To add a new server: add it to `ensure_installed` in `lua/lsp.lua` and add a `vim.lsp.config()` call.

**Mason commands:**

| Command | Description |
|---|---|
| `:Mason` | Open mason UI to install/update/remove servers |
| `:MasonInstall <server>` | Install a specific server |
| `:MasonUninstall <server>` | Remove a server |
| `:MasonUpdate` | Update all installed servers |

**LSP keymaps** (active only in buffers with an attached server):

| Keymap | Action |
|---|---|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gri` | Go to implementation (opens in telescope) |
| `gy` | Go to type definition |
| `grr` | References (opens in telescope) |
| `grx` | Run codelens under cursor |
| `K` | Hover docs |
| `<C-s>` | Signature help |
| `<Space>rn` | Rename symbol |
| `<Space>ca` | Code actions |
| `<Space>cf` | Format buffer or selection |
| `[d` / `]d` | Jump to previous / next diagnostic |
| `<Space>cd` | Send diagnostics to location list |

**Diagnostic commands:**

| Command | Description |
|---|---|
| `:checkhealth lsp` | Verify LSP health and active clients |
| `:lua print(vim.inspect(vim.lsp.get_clients()))` | Show all active LSP clients |

**Diagnostic toggles:**

Diagnostic virtual text and gutter signs are **off by default** — underlines remain active
so diagnostics are still visible on hover (`K` or `<Space>e`).

**LSP features** (enabled automatically when the server supports them):

- **Inlay hints** — parameter names, inferred types (useful for Rust/Go/TS). Toggle with `<Space>ti` when noisy.
- **Document highlight** — when cursor pauses on a symbol (~300ms), other occurrences in the buffer are highlighted.
- **Codelens** — virtual text annotations (run tests, implement interface, etc.). `grx` runs the codelens under cursor.

| Keymap | Action |
|---|---|
| `<Space>td` | Toggle diagnostic virtual text and gutter signs on/off |
| `<Space>ti` | Toggle inlay hints on/off |
| `<Space>tb` | Toggle inline git blame |
| `<Space>ts` | Toggle symbol search scope (all active LSPs ↔ buffer LSP only) |

### Autocompletion (blink.cmp)

Completion engine written in Rust — faster than nvim-cmp with better fuzzy matching.
Installed via `vim.pack` pinned to the latest `v1.x.x` release tag.

On first launch, blink.cmp automatically downloads a pre-built Rust binary for fuzzy matching
(requires `curl` and `git`). You'll see a notification while it downloads. No manual steps needed.

**Sources:** LSP, file paths, snippets, buffer words

**Keymaps (inside completion menu):**

| Key | Action |
|---|---|
| `<Tab>` | Next item (falls back to normal Tab when menu is closed) |
| `<S-Tab>` | Previous item |
| `<CR>` | Accept selected item (falls back to normal Enter) |
| `<C-u>` / `<C-d>` | Scroll documentation popup up / down |
| `<C-space>` | Manually trigger completion |
| `<C-e>` | Cancel / close completion menu |

**Signature help** is enabled automatically — shows function parameter hints when typing inside `()`.

**If the binary fails to download** (no internet, corporate proxy, etc.), blink.cmp silently falls
back to a pure Lua implementation with no action required. To force a re-download:
```
:lua require('blink.cmp.fuzzy.download').ensure_downloaded(function() end)
```

**Commands:**

| Command | Description |
|---|---|
| `:checkhealth blink.cmp` | Verify blink.cmp and fuzzy binary status |

### Git Signs and Scrollbar (gitsigns.nvim + satellite.nvim)

**gitsigns.nvim** shows changed, added, and deleted lines in the gutter next to line numbers:

| Sign | Meaning |
|---|---|
| `▎` | Added line |
| `▎` | Changed line |
| `▂` / `▔` | Deleted line (below / above) |
| `▎` | Changed and deleted |
| `░` | Untracked file |

**Git hunk keymaps:**

| Keymap | Action |
|---|---|
| `]c` / `[c` | Jump to next / previous hunk |
| `<Space>hs` | Stage hunk |
| `<Space>hr` | Reset hunk |
| `<Space>hu` | Undo stage hunk |
| `<Space>hp` | Preview hunk |
| `<Space>hb` | Blame line (full commit info) |

**satellite.nvim** adds a scrollbar on the right edge of the focused window with colour-coded marks showing where things are across the whole file:

- Git changes (add/change/delete) — matches gitsigns colours
- LSP diagnostics (error/warn/info/hint)
- Search results
- Quickfix list items

Useful for navigating large files — you can see at a glance where modified code, errors, and search matches are without scrolling.

**Commands:**

| Command | Description |
|---|---|
| `:SatelliteRefresh` | Force refresh scrollbar if out of sync |
| `:SatelliteDisable` / `:SatelliteEnable` | Toggle scrollbar |

### Session Management (persistence.nvim)

Automatically saves and restores open buffers per directory. Sessions are saved on quit and
can be restored on next launch. With `branch = true`, each git branch gets its own session —
switching branches won't mix up your open files.

**Sessions are saved automatically on quit.** To restore, use the keymaps below after opening
nvim in the same directory.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<Space>qs` | Restore session for the current directory |
| `<Space>qS` | Pick from all saved sessions |
| `<Space>ql` | Restore the last session (regardless of directory) |
| `<Space>qd` | Stop saving — quit without persisting current state |


### Auto-save (auto-save.nvim)

Buffers are saved automatically on focus loss, leaving insert mode, and after text changes (1s debounce).
Special buffers (telescope, mason, gitcommit) are excluded. No keymaps — it just works in the background.

### Terminal (toggleterm.nvim)

A togglable floating terminal that persists state across hides.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<C-\>` | Toggle terminal (normal, insert, or terminal mode) |
| `<Space>tt` | Toggle terminal (discoverable via which-key) |
| `<Esc>` (in terminal) | Exit terminal mode → normal mode |
| `<C-h/j/k/l>` (in terminal) | Navigate to adjacent splits |
| `<C-]>` (in terminal) | Cycle to next terminal |
| `<C-[>` (in terminal) | Cycle to previous terminal |

**Tips:**

- **Hide vs close**: `<C-\>` hides the terminal (state persists). `<C-d>` sends EOF to the shell and closes it entirely — faster than typing `exit`.
- **Multiple terminals**: prefix `<C-\>` with a count — `2<C-\>` opens terminal #2, `3<C-\>` opens #3. Each is independent.
- **Cycle between terminals**: `<C-]>` / `<C-[>` cycle next/previous through open terminals (wrap around). Works in both terminal and normal mode within the terminal buffer.
- **Switch between terminals**: `:TermSelect` opens a picker over all open terminals.
- **Run a command**: `:TermExec cmd="make test"` — runs the command in terminal #1 and returns focus to your buffer.
- **Override direction ad-hoc**: `:ToggleTerm direction=horizontal` opens a split instead of a float for that toggle.
- **`<Esc>` caveat**: the `<Esc>` mapping exits terminal mode in all terminal buffers. TUI programs opened inside the terminal (e.g. `vim`, `htop`, `fzf`) also need `<Esc>` for their own UI — use `<C-\><C-n>` manually in those cases, or add a filetype guard in `lua/terminal.lua`.

### Auto-pairs (nvim-autopairs)

Automatically closes brackets, quotes, and other pairs. Treesitter-aware — won't auto-pair inside
strings or comments where it would be wrong.

### Notifications (mini.notify)

Floating notification windows that auto-dismiss. Replaces vim's default `vim.notify` which echoes
to the command line and prompts on long messages. LSP progress notifications are suppressed to
avoid noise from language servers scanning the workspace.

### Markdown Rendering (render-markdown.nvim)

Renders markdown files in the buffer with formatted headings, bold, italic, code blocks, and lists.
Active automatically when opening `.md` files.

### Git Editor Buffers (gitcommit / gitrebase)

When `git commit` or `git rebase -i` opens a buffer in the existing nvim instance (via `nvim-editor` — see ZSH section), these buffer-local keymaps are active:

| Keymap | Action |
|---|---|
| **`<Space>w`** | **Save and close buffer** — writes the file and closes the buffer, signalling git to proceed |
| **`<Space>x`** | **Discard and close** — quits with a non-zero exit code (`:cq`), signalling git to abort; nvim server stays running |

The underlying commands if you prefer typing them: `:w | bd` to confirm, `:cq` to abort. Note: `:wq` and `:q` would quit the whole nvim session — avoid them here.

These keymaps are only active in `gitcommit` and `gitrebase` buffers.

### General Keymaps

| Keymap | Action |
|---|---|
| `:Q` | Quit all |
| `<Space>qq` | Close buffer |
| `<Space>o` / `:Typora` | Open current file in the Typora app (writes pending changes first) |
| `y` / `Y` | Yank to system clipboard (dd, x, c stay in Neovim register) |
| `p` (visual) | Paste without clobbering register |
| `<` / `>` (visual) | Indent/dedent and stay in visual mode |
| `Ctrl+h/j/k/l` | Navigate between splits |
| `H` / `L` | Previous / next buffer |
| `<Space><Space>` | Switch to alternate buffer (`<C-^>`) |
| `<Esc>` | Clear search highlights |
| `<Space>?` | Show all keymaps (which-key popup) |
| `<Space>sk` | Fuzzy-search all keymaps (Telescope picker, includes built-in motions) |
| `yp` | Yank relative file path |
| `yP` | Yank absolute file path |
| `yc` | Yank Claude @-reference with line numbers |
| `yC` | Yank Claude @-reference (absolute path) |
| `yu` | Yank GitHub permalink |

### File Explorer (nvim-tree)

Sidebar file tree. `<Space>e` opens the tree and reveals the current file, or closes it if already open.

**Features:**
- Git status decorations on files and directories (added, modified, untracked, etc.)
- LSP diagnostics icons (error/warn/info/hint) next to files, including parent dirs
- Modified indicator on buffers with unsaved changes
- `D` sends files to macOS trash (recoverable); `d` is permanent delete
- Auto-closes when it's the last window open

**Keymaps (inside the tree):**

| Key | Action |
|---|---|
| `l` or `<CR>` | Open file / expand directory |
| `h` | Collapse directory |
| `a` | Create file or directory (append `/` for dir) |
| `d` | Delete (permanent) |
| `D` | Trash (sends to macOS trash) |
| `r` | Rename |
| `x` | Cut |
| `c` | Copy |
| `p` | Paste |
| `f` | Live filter (type to narrow tree to matches) |
| `F` | Clear filter |
| `W` | Collapse all |
| `I` | Toggle dotfiles |
| `H` | Toggle git-ignored files |
| `R` | Refresh |
| `q` | Close tree |
| `g?` | Show all nvim-tree keybindings |

**Tips:**
- Use the tree for **spatial orientation** (seeing where files sit relative to each other), not for search — `<Space>sf` and `<Space>sg` are faster for finding files and text.
- `<Space>e` always reveals the current file when opening, so it doubles as "where am I?" after jumping to a file via Telescope.
- Press `f` to narrow a big tree — type part of a filename and only matches are shown. `F` clears the filter. This is tree-scoped, not project-wide.

### Spell Checking

Built into Neovim — no plugin needed. Off by default. Toggle with `<Space>tz`.

| Key | Action |
|---|---|
| `]s` / `[s` | Next / previous misspelled word |
| `1z=` | Accept top suggestion instantly (no menu) |
| `z=` | Open correction menu for word under cursor |
| `zg` | Add word to personal dictionary |
| `zw` | Mark word as misspelled |

Personal dictionary lives at `nvim/.config/nvim/spell/en.utf-8.add` inside the
dotfiles repo. Commit it to persist custom words across machines — `zg` appends
to it automatically.

`]s`/`[s` appear in the `[`/`]` which-key popup. `zg`, `z=`, `1z=`, and `zw`
are searchable via `<Space>sk` — type "spell", "typo", or "spelling".

### Keymap Discovery (which-key.nvim)

Press `<Space>` and wait — a popup appears showing all available keymaps for that prefix,
grouped by category. Helps discover keymaps without needing to remember them all.

For fuzzy search instead of hierarchical browsing, use `<Space>sk` — opens a Telescope picker
over all mappings (which-key entries plus built-in normal-mode commands curated in `lua/builtins.lua`).

| Prefix | Group |
|---|---|
| `<Space>s` | Search |
| `<Space>q` | Session/Quit |
| `<Space>t` | Toggle |
| `<Space>h` | Git hunk |
| `<Space>r` | Refactor |
| `<Space>c` | Code |
| `g` | Go to |
| `[` / `]` | Previous / Next |

Dismiss the popup with `<Esc>`. The popup appears after 300ms by default.

### Statusline (lualine.nvim)

Statusline that automatically matches the active colorscheme. Shows mode, filename, git branch,
diff counts, diagnostics, LSP status, search count, progress, and cursor position.

**Layout:**

```
| mode | filename | branch diff diagnostics | ... | lsp_status | searchcount progress | line:col |
```

- **LSP status** — only visible when a language server is attached to the current buffer
- **Search count** — only visible while a `/` search is active
- Theme updates automatically when you switch themes (via `<Space>st` or `lua/themes.lua`)

### Themes

All themes are configured in `lua/themes.lua`. Switch themes interactively with `<Space>st` (live preview as you scroll), or edit `M.active` directly:

```lua
M.active = 'catppuccin'        -- default dark
M.active = 'catppuccin-latte'  -- light variant
M.active = 'tokyonight-day'    -- light variant
M.active = 'rose-pine-dawn'    -- light variant
```

The active theme is persisted to `~/.local/share/nvim/theme.txt` and restored on next launch. The theme picker (`<Space>st`) saves automatically on selection.

See `M.variants` in `lua/themes.lua` for all available colorscheme names with descriptions.

To customise a theme, edit its `setup` function or `overrides` table in `lua/themes.lua`.

**Tip:** position the cursor on any UI element and run `:Inspect` to find its highlight group name for overrides.

**Installed themes:** catppuccin, tokyonight, gruvbox, rose-pine, kanagawa, nightfox, cyberdream, dracula, solarized,
github-nvim-theme, zenbones, oxocarbon, modus-themes, midnight, onedark, vscode, everforest, nordic.

### Navigation

**Scrolling:**

| Key | Action |
|---|---|
| `Ctrl+d` | Scroll down half page |
| `Ctrl+u` | Scroll up half page |
| `Ctrl+f` | Scroll down full page |
| `Ctrl+b` | Scroll up full page |

**Jumping:**

| Key | Action |
|---|---|
| `gg` | Top of file |
| `G` | Bottom of file |
| `{number}G` | Jump to line number |
| `%` | Jump to matching bracket |
| `{` / `}` | Previous / next blank line |

**Jumplist (navigate location history):**

| Key | Action |
|---|---|
| `Ctrl+o` | Jump back to previous location |
| `Ctrl+i` | Jump forward to next location |

Large moves (`gd`, Telescope selection, `gg`, `G`, `/search`) save your position to the jumplist. `<C-o>`/`<C-i>` walk that history. `:jumps` shows the full list. Both are searchable via `<Space>sk` — type "jump", "back", or "forward".

**Viewport (move screen, cursor stays):**

| Key | Action |
|---|---|
| `zz` | Center current line on screen |
| `zt` | Current line to top |
| `zb` | Current line to bottom |

**Search:**

| Key | Action |
|---|---|
| `/term` | Search forward |
| `n` / `N` | Next / previous match |
| `*` / `#` | Next / previous occurrence of word under cursor |

**Remaps not yet configured** — listed here for reference when customising `keymaps.lua`:

| Remap | What it does | Why |
|---|---|---|
| `J` in visual → move lines down | Move selected lines down | More intuitive than `:m '>+1` |
| `K` in visual → move lines up | Move selected lines up | More intuitive than `:m '<-2` |
| `n` → `nzzzv` | Center screen after search jump | Keeps match in the middle of the viewport |

### Neovide

GUI frontend for Neovim. Two config files split by mechanism:

- **`nvim/.config/nvim/neovide.toml`** — startup settings Neovide reads before nvim launches: `fork = true` (detach from launching terminal), `frame = "transparent"` + `title-hidden = true` (chrome blends with the editor), font (Hack Nerd Font Mono 15pt to match iTerm2/kitty). `maximized` is commented out so window size is restored from `neovide-settings.json`.
- **`nvim/.config/nvim/lua/neovide.lua`** — runtime `vim.g.neovide_*` vars and keymaps. Gated by `if not vim.g.neovide then return end`, so terminal nvim skips it. Contains animation tuning (cursor/scroll/position lengths, cursor trail), `option_key_is_meta = 'both'` (so `<M-1>`..`<M-9>` keymaps work), proxy icon, hide-mouse-when-typing, floating corner radius, and the keymaps below.

```bash
brew install --cask neovide-app
```

Neovide looks for its config at `~/Library/Application Support/neovide/config.toml` on macOS, so symlink that path to the stowed file once per machine:

```bash
ln -s ~/.config/nvim/neovide.toml "$HOME/Library/Application Support/neovide/config.toml"
```

This works for both terminal and GUI launches (Spotlight, dock) — unlike the `$NEOVIDE_CONFIG` env var, which only propagates to terminal-launched processes.

**macOS-style keymaps** (Neovide-only — terminal nvim can't receive `<D-...>`):

| Keymap | Action |
|---|---|
| `Cmd+C` (visual) | Copy to system clipboard |
| `Cmd+V` (any mode) | Paste from system clipboard |
| `Cmd+S` | Save (`:w`) |
| `Cmd+=` / `Cmd+-` | Zoom in / out (`neovide_scale_factor`) |
| `Cmd+0` | Reset zoom to 1.0 |
| `Cmd+Opt+Left` / `Cmd+Opt+Right` | Jumplist back / forward |

**Force Click** on the trackpad triggers `:NeovideForceClick` automatically — shows the macOS "Look Up" popover for text and Quick Look previews for file paths/URLs under the cursor. No setup needed.

## Typora

GUI markdown editor with live (WYSIWYG) rendering — handy for reading or heavy editing of `.md` files.

```bash
brew install --cask typora
```

Two ways to open a file in it:

- **Shell:** `typora notes.md` — alias for `open -a Typora` (in `.zshrc_config.zsh`).
- **Neovim:** `<Space>o` (or `:Typora`) opens the current buffer's file in Typora, writing any pending changes first. Discoverable via `<Space>?` and `<Space>sk` (search "typora" or "markdown"). Mirrors the [vscode-open-in-typora](https://github.com/typora/vscode-open-in-typora) extension — `open -a Typora` on macOS, no cursor-position handoff (Typora has no such CLI flag).

## iTerm2

### Setup

Color themes (Dracula, Nord, Catppuccin Latte) and an exported settings snapshot are stored in `iterm2/`.

To sync settings automatically across machines:

1. **iTerm2 → Settings → General → Preferences**
2. Check **"Load preferences from a custom folder or URL"**
3. Set path to `~/src/dotfiles/iterm2`
4. Check **"Save changes to folder when iTerm2 quits"**

This writes a `com.googlecode.iterm2.plist` to the folder. On a new machine, clone the repo and point iTerm2 to the same path — all profiles, keybindings, and appearance settings will load automatically.

To import color themes manually: **iTerm2 → Settings → Profiles → Colors → Color Presets → Import** and select the `.itermcolors` files.

### Option-as-Meta

For nvim mappings using `<M-...>` (e.g. `<M-1>`..`<M-9>` to jump to a buffer in `<Space>sb`) to work, iTerm2 needs to send Option as Meta instead of typing special characters (`¡`, `™`, etc.):

**iTerm2 → Settings → Profiles → Keys → General → Left Option key: `Esc+`**

Set Right Option to `Esc+` too if you use it. Verify by pressing `Option+1` in nvim insert mode — it should do nothing (or show as `<M-1>` in `:map`) rather than insert `¡`.

### Panes

**Splitting:**

| Shortcut | Action |
|---|---|
| `Cmd+D` | Split vertically (side by side) |
| `Cmd+Shift+D` | Split horizontally (top/bottom) |

**Switching panes:**

| Shortcut | Action |
|---|---|
| `Cmd+[` / `Cmd+]` | Cycle through panes |
| `Cmd+Option+Arrow` | Move to pane in that direction |

**Tabs:**

| Shortcut | Action |
|---|---|
| `Cmd+T` | New tab |
| `Cmd+W` | Close current pane/tab |
| `Cmd+1-9` | Jump to tab by number |
| `Cmd+Left/Right` | Previous/next tab |

**Resizing panes:**

| Shortcut | Action |
|---|---|
| `Cmd+Ctrl+Arrow` | Resize pane in that direction |

## Kitty

GPU-accelerated terminal emulator. Config is managed via stow.

```bash
brew install --cask kitty
cd ~/src/dotfiles
stow kitty
```

Settings are ported from the iTerm2 profile (Hack Nerd Font Mono 15pt, 125×25 window, bar cursor). To pick a color theme interactively:

```bash
kitten themes
```

This writes `~/.config/kitty/current-theme.conf` which kitty auto-includes. The config lives at `~/.config/kitty/kitty.conf` (symlinked by stow).

### Keymaps

| Shortcut | Action |
|---|---|
| `Cmd+N` | New window |
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab/window |
| `Cmd+Enter` | New OS window |
| `Cmd+D` | No built-in split — use tabs or launch a second window |
| `Cmd+1-9` | Jump to tab by number |
| `Cmd+Shift+]` / `Cmd+Shift+[` | Next / previous tab |
| `Ctrl+Shift+Enter` | New window (split within tab, requires layout change) |
| `Ctrl+Shift+]` / `Ctrl+Shift+[` | Next / previous window in tab |

**Layouts** (cycle with `Ctrl+Shift+L`): tall, fat, grid, horizontal, vertical, stack.

### Commands

| Command | Description |
|---|---|
| `kitten themes` | Browse and apply color themes |
| `kitten diff file1 file2` | Side-by-side diff |
| `kitten ssh host` | SSH with full kitty features on remote |
| `kitty +kitten icat image.png` | Display image in terminal |

## Zellij

Terminal multiplexer — split panes, tabs, and persistent sessions. Config is
managed via stow (`stow zellij`). Theme is catppuccin-mocha to match nvim.

```bash
zellij            # start a new session
zellij attach     # reattach to the last session
zellij ls         # list running sessions
zellij kill-all-sessions  # clean up all sessions
```

The status bar at the bottom shows available keys for the current mode.
Press `Esc` or `Ctrl+g` to return to normal mode from any mode.

### Panes

| Key | Action |
|---|---|
| `Ctrl+p` | Enter Pane mode |
| `d` | Split pane down |
| `r` | Split pane right |
| `x` | Close pane |
| `z` | Toggle pane zoom (fullscreen) |
| `f` | Toggle floating pane |
| `w` | Show/hide all floating panes |
| `e` | Embed floating pane / make pane floating |
| `Alt+arrow` | Move focus between panes (without entering Pane mode) |

### Floating terminal

Zellij supports floating panes — panes that hover over the layout. Use one as
a scratch terminal you can summon and dismiss without losing your place:

1. `Ctrl+p` → `f` — open a new floating pane
2. Do your work (run a command, check a log, etc.)
3. `Ctrl+p` → `w` — hide all floating panes (they stay alive in the background)
4. `Ctrl+p` → `w` again — bring them back

The floating pane persists for the session. Unlike toggleterm in nvim, it's
not bound to a single key by default — `Ctrl+p w` is the toggle.

### Tabs

| Key | Action |
|---|---|
| `Ctrl+t` | Enter Tab mode |
| `n` | New tab |
| `x` | Close tab |
| `r` | Rename tab |
| `1`–`9` | Jump to tab by number |
| `Arrow` | Move to next/previous tab |

### Sessions

| Key | Action |
|---|---|
| `Ctrl+o` | Enter Session mode |
| `d` | Detach (session keeps running in background) |
| `w` | Open session manager (switch/kill sessions) |

Sessions are auto-saved on exit and restored on next launch (`session_serialization true`). Closing the last client **quits** the session rather than detaching — no ghost sessions left behind (`on_force_close "quit"`).

### Scrolling

| Key | Action |
|---|---|
| `Ctrl+s` | Enter Scroll mode |
| `Arrow` / `j`/`k` | Scroll line by line |
| `Ctrl+d` / `Ctrl+u` | Scroll half page |
| `Ctrl+f` / `Ctrl+b` | Scroll full page |
| `e` | Open scroll buffer in `$EDITOR` |
| `s` | Search in scroll buffer |
| `Esc` | Exit Scroll mode |

Mouse scroll also works directly without entering Scroll mode.

### Plugins

| Key | Action |
|---|---|
| `Ctrl+?` | Open zellij-forgot — floating keybinding cheatsheet |

zellij-forgot downloads its wasm binary from GitHub releases on first use.

## ZSH

```bash
# Dependencies
brew install fzf ripgrep direnv zoxide

# Install Antigen (zsh plugin manager). Antigen will clone oh-my-zsh and all
# configured plugins into ~/.antigen/bundles on first shell launch — no need
# to install oh-my-zsh separately.
mkdir -p ~/.antigen
curl -L git.io/antigen > ~/.antigen/antigen.zsh

# Install zsh-direnv plugin
git clone https://github.com/ptavares/zsh-direnv.git ~/.zsh-direnv
```

Then stow and create your `~/.zshrc`:

```bash
cd ~/src/dotfiles
stow zsh

# Create ~/.zshrc if it doesn't exist
echo 'source ~/.zshrc_config.zsh' >> ~/.zshrc
```

Open a new shell. On the first launch antigen clones every bundle (takes ~20s) and writes a cached loader to `~/.antigen/init.zsh`. Subsequent launches just source the cache.

### Directory jumping (zoxide)

`z <partial-dir>` jumps to the most "frecent" (frequency + recency) directory matching the term; `zi <partial-dir>` opens an fzf picker. This is provided by [zoxide](https://github.com/ajeetdsouza/zoxide), a Rust binary — **not** an antigen bundle. `.zshrc_config.zsh` initializes it after the plugins load:

```zsh
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
```

So the only per-machine step is `brew install zoxide` (included in the deps above). The database lives at `~/.local/share/zoxide/` and fills in as you `cd` around. zoxide replaced the old `antigen bundle z` line — oh-my-zsh ships no `z` plugin, so that bundle was a silent no-op.

### nvim-editor

`nvim-editor` is a small script (stowed to `~/.local/bin/nvim-editor`) set as `$EDITOR`, `$GIT_EDITOR`, and `$KUBE_EDITOR`. It routes editor calls through the existing nvim instance when available:

- **Inside a toggleterm or nvim-spawned terminal** (`$NVIM` is set): opens the file in the parent nvim via `--remote-wait`, blocking until the buffer is closed.
- **Standalone terminal** (iTerm, Kitty, etc.): falls back to a fresh `nvim` process.

This means `git commit`, `git rebase -i`, `kubectl edit`, and any other `$EDITOR` caller automatically use your existing nvim session when you're working inside one.

The script is included in the `zsh` stow package. On a new machine, `stow zsh` symlinks it into `~/.local/bin/` (already on `$PATH`).

### claude-nvim

`claude-nvim` (stowed to `~/.local/bin/claude-nvim`) is the **opposite** of `nvim-editor`: it runs this repo's real Neovim config in a throwaway, fully **isolated** headless instance — for *testing* config changes, not editing files.

Why it exists: when Claude Code (or any tool) runs inside an nvim-hosted terminal, its shells inherit `$NVIM` (the host's RPC socket). A bare `nvim …` from there is intercepted by `flatten.nvim` and executed against the **live** editor — including `+qa`, which quits the host and kills the session running inside it. `claude-nvim` strips `$NVIM` so the child boots as an independent process that can't touch — or crash — the host. It also runs from a temp cwd, disables persistence session-save, and uses `-n -i NONE` so it never clobbers the host's swap/shada/session state.

```sh
claude-nvim check              # load the full config headless; surface startup errors
claude-nvim theme <variant>    # apply a colorscheme variant; prints "OK <name>" or "ERROR: …"
claude-nvim lua '<code>'       # run lua against the real config; output to stdout
claude-nvim -- <raw nvim args> # escape hatch
```

Best-effort timeout via coreutils `timeout`/`gtimeout` (`brew install coreutils` on macOS); without it the trailing `+qa` still quits. The script is in the `zsh` stow package.

**Rule of thumb:** if `echo $NVIM` is non-empty, never call bare `nvim` from a script/tool — use `claude-nvim` (isolated) or `nvim-editor` (routes into the host, for `$EDITOR` use).

### Per-machine config

`.zshrc_config.zsh` conditionally sources two optional files:

- **`~/.zshrc_shared.zsh`** — stowed from this repo. Shared per-project tooling. Lives in version control.
- **`~/.zshrc_work.zsh`** — *not* stowed. `zsh/.stow-local-ignore` excludes it so each work machine drops its own copy at `~/.zshrc_work.zsh`. The repo copy is a reference template.

> **Gotcha:** `zsh/.stow-local-ignore` is itself gitignored (see the root `.gitignore`), so it does **not** exist on a fresh clone. Until you create it, `stow zsh` will symlink `.zshrc_work.zsh` into `~` along with everything else — and a non-work machine then runs the Work colima/AWS setup on every shell launch. On a personal machine, create it **before** stowing:
>
> ```bash
> printf '.zshrc_work.zsh\n' > zsh/.stow-local-ignore
> ```
>
> On a Work work machine, skip this and drop your real `~/.zshrc_work.zsh` in place instead.

Secrets go in `~/.zshenv`, which is not managed by stow.

### Troubleshooting antigen

**Stale cache** — if you see `tee: /completions/_docker: No such file or directory` on shell startup, antigen has cached an empty `$ZSH` / `$ZSH_CACHE_DIR`. Wipe and rebuild the cache:

```bash
rm -f ~/.antigen/init.zsh ~/.antigen/init.zsh.zwc ~/.antigen/.zcompdump ~/.antigen/.zcompdump.zwc
exec zsh
```

`.zshrc_config.zsh` exports those vars explicitly before `antigen apply` so the regenerated cache captures the right paths.

**oh-my-zsh never cloned** — symptom: completions/aliases from OMZ plugins (brew, docker, kubectl, …) don't work, and `~/.antigen/bundles/robbyrussell/oh-my-zsh/` contains only a `cache/` dir (no `oh-my-zsh.sh`). Antigen decides whether to clone a bundle by a bare directory-existence check, so if anything pre-creates that dir before antigen runs, it logs "already cloned" and silently skips the clone. `.zshrc_config.zsh` guards against this by deferring its `mkdir -p "$ZSH_CACHE_DIR/completions"` until *after* `antigen apply`. To repair a machine already in this state:

```bash
rm -rf ~/.antigen/bundles/robbyrussell
rm -f ~/.antigen/init.zsh ~/.antigen/init.zsh.zwc
exec zsh   # antigen re-clones oh-my-zsh for real
```

Note: the shell **prompt** does not depend on any of this — it's defined self-contained in `.zshrc_config.zsh` (the `_zsh_git_prompt` function + `PROMPT`), so it renders `➜ <dir> git:(<branch>) ✗` even if oh-my-zsh fails to load. Recolor it via the `PROMPT_COLOR_*` palette there.

## Git

One-time global setup for a new machine:

```bash
# Identity
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Default branch name
git config --global init.defaultBranch main

# Pull strategy — rebase instead of merge
git config --global pull.rebase true

# Reuse recorded resolutions — automatically reapplies conflict resolutions you've made before
git config --global rerere.enabled true

# Better diff output — shows moved lines in a different color
git config --global diff.colorMoved dimmed-zebra

# Editor — fallback when $GIT_EDITOR/$EDITOR are unset (the shell sets
# GIT_EDITOR=nvim-editor, which takes precedence; see the ZSH section)
git config --global core.editor nvim

# Always talk to GitHub over SSH, even for https:// remotes (see SSH note below)
git config --global url."git@github.com:".insteadOf "https://github.com/"

# On first push of a new branch, auto-create its upstream instead of erroring
git config --global push.autoSetupRemote true

# Default the push remote to origin
git config --global remote.pushDefault origin
```

### SSH for GitHub

The `url.…insteadOf` rewrite above sends **all** GitHub traffic — including clones of `https://github.com/…` URLs — over SSH, so an SSH key registered with your GitHub account is required. If the key isn't a default name (`~/.ssh/id_ed25519`), SSH won't present it automatically: add a `~/.ssh/config` entry so `git@github.com` uses the right key.

```sshconfig
# ~/.ssh/config  (chmod 600)
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github   # path to your private key
  IdentitiesOnly yes
  AddKeysToAgent yes
```

Verify with `ssh -T git@github.com` — a successful run prints `Hi <username>!`. `~/.gitconfig` and `~/.ssh/config` are per-machine and **not** managed by stow.

## Stow

To exclude files or folders from being symlinked, create a `.stow-local-ignore` file in the package directory (e.g. `nvim/.stow-local-ignore`):

```
node_modules
*.zwc
```

Patterns are Perl-style regex, one per line. Note: adding this file overrides stow's default ignore list (which skips `.git`, `README.*`, etc.), so include those if needed. See `man stow` under "IGNORE LISTS" for the full defaults.

If stow already created symlinks before you added the ignore (e.g. `node_modules` was already symlinked), restow the package to pick up the change:

```bash
cd ~/src/dotfiles
stow -R nvim
```

`-R` (restow) unstows and re-stows, recreating symlinks while respecting the updated `.stow-local-ignore`.
