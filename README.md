# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Contents

**[Part 1: Essentials](#part-1-essentials)**
- [Quick start (fresh machine)](#quick-start-fresh-machine)
- [Fonts](#fonts)
- [Setup](#setup) · [Stow](#stow)
- [Verify your setup](#verify-your-setup)
- [Languages](#languages) · [Format-on-save tools](#format-on-save-tools)

**[Part 2: Reference](#part-2-reference)**

*AI & Claude tooling*
- [Claude Code](#claude-code) — [Recommended manual settings](#recommended-manual-settings) · [LSP plugins](#lsp-plugins-code-intelligence) · [rtk](#rtk-token-optimizer) · [Theme](#theme)
- [Unified theme switching](#unified-theme-switching)
- [Claude Squad](#claude-squad)

*Editors*
- [Neovim](#neovim)
- [Neovide](#neovide)
- [Typora](#typora)

*Terminals & multiplexing*
- [iTerm2](#iterm2) · [Kitty](#kitty) · [Zellij](#zellij)

*Shell*
- [ZSH](#zsh) — [zoxide](#directory-jumping-zoxide) · [troubleshooting antigen](#troubleshooting-antigen)

*Version control*
- [Git](#git) — [SSH for GitHub](#ssh-for-github)

*Optional / utilities*
- [Colima](#colima) · [rcmd](#rcmd) · [yknotify](#yknotify)


# Part 1: Essentials

<a id="quick-start-fresh-machine"></a>
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
6. **Stow the configs** — `stow nvim zsh rcmd && stow --no-folding claude` (add `kitty`/`zellij` only if you enabled those optional casks) ([Setup](#setup)). First create `zsh/.stow-local-ignore` if this is a personal (non-work) machine — see [Per-machine config](#per-machine-config).
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
stow rcmd                    # needs the rcmd cask
# Optional terminals — only if you uncommented their casks in the Brewfile:
stow kitty                   # needs the kitty cask
stow zellij                  # needs the zellij formula
```

> **Stowing only symlinks configs — it does not install the tools they depend
> on.** Install the [Fonts](#fonts) above first, then work through the per-tool
> dependency steps in [Languages](#languages), [ZSH](#zsh), and [Neovim](#neovim)
> — a fresh machine needs all of them, not just the stow commands above.

Stow reads `.stowrc` in this repo which sets `--target` to `~`, so you don't need to pass `-t ~` manually.

To add a new config (e.g. tmux), mirror the home-relative path:

```
dotfiles/tmux/.config/tmux/tmux.conf
```

Then run `stow tmux`.

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


# Part 2: Reference

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
# Register the rtk token-optimizer hook in ~/.claude/settings.json (one-time)
rtk init -g --auto-patch
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

### Recommended manual settings

A few `~/.claude/settings.json` keys are worth setting by hand on a fresh
machine but aren't worth a `setup-*.sh` script for — either because they're a
single key, or because whether you want them is a judgment call rather than
a fixed default:

- **`env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`** — set to `"1"` to stop
  Claude Code from sending non-essential telemetry (Statsig analytics,
  Sentry error reports). Doesn't affect core inference traffic.
- **`model`** — set to `"opusplan"` to use Opus while in plan mode and fall
  back to the default model otherwise.
- **`effortLevel`** — set to `"high"` for more thorough reasoning on
  supported models.
- **`tui`** — set to `"fullscreen"` for the flicker-free alt-screen renderer
  with virtualized scrollback.

(`statusLine`, `enabledPlugins`, and `theme` are **not** in this list — they're
already handled by `setup-statusline.sh`, `setup-lsp-plugins.sh`, and
`setup-theme.sh` above.)

<a id="lsp-plugins-code-intelligence"></a>
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

<a id="rtk-token-optimizer"></a>
### rtk — token optimizer

[rtk](https://www.rtk-ai.app/) ("Rust Token Killer", `brew "rtk"`) is a CLI proxy that compresses noisy command output (git, grep, ls, test runners, build tools, …) before it reaches the context window — the project claims ~60–90% reduction on common dev commands. It hooks into Claude Code transparently; you don't change how you work.

Enable it once per machine (after `brew bundle` installs the binary):

```bash
rtk init -g --auto-patch
```

That command:

- adds a **`PreToolUse` hook** on the `Bash` matcher to `~/.claude/settings.json` (`"command": "rtk hook claude"`) — every Bash call is rewritten through rtk automatically;
- writes **`~/.claude/RTK.md`** (a short usage cheatsheet) and adds an **`@RTK.md`** reference to **`~/.claude/CLAUDE.md`** so Claude knows the meta-commands;
- backs up the prior settings to `~/.claude/settings.json.bak` and seeds a user filter template at `~/Library/Application Support/rtk/filters.toml`.

`--auto-patch` skips the interactive confirmation (needed when scripting; drop it to review the settings.json edit first). It's idempotent — re-running just re-confirms the hook. None of these files are stowed (all machine-specific `~/.claude` state); the reproducible artifact is the one command above. **Restart Claude Code** afterward so it loads the hook. Check savings with `rtk gain`; remove everything with `rtk init -g --uninstall`.

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

<a id="one-time-iterm2-setup-single-profile-follows-macos"></a>
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

## Neovim

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

> **Keymaps, plugins, and per-feature behavior live in
> [`nvim/.config/nvim/GUIDE.md`](nvim/.config/nvim/GUIDE.md)** — the canonical,
> maintained reference for the nvim config (Architecture, Design Decisions, a
> Keymap index, and per-tool sections, all in `<leader>` notation). This
> README covers only installing and first-launching Neovim.

### GPG commit signing — YubiKey touch notifications (one-time setup)

Optional. If your commits are GPG-signed on a YubiKey, nvim pops a
"Touch YubiKey ↯" / "Signed ✓" notification during `git commit` (the
notification behavior itself is documented in GUIDE.md). Point gpg-agent at
the bundled pinentry wrapper once per machine (not stowed — lives in `~/.gnupg/`):

```bash
echo 'pinentry-program ~/.config/nvim/scripts/pinentry-yubikey-notify.sh' > ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent && gpgconf --launch gpg-agent
```

The wrapper delegates to `/opt/homebrew/bin/pinentry-mac` after notifying nvim,
so normal pinentry behavior is preserved. To revert:

```bash
echo 'pinentry-program /opt/homebrew/bin/pinentry-mac' > ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent && gpgconf --launch gpg-agent
```

## Neovide

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
- **Neovim:** `<leader>uo` (or `:Typora`) opens the current buffer's file in Typora, writing any pending changes first. Discoverable via `<leader>?` and `<leader>sk` (search "typora" or "markdown"). Mirrors the [vscode-open-in-typora](https://github.com/typora/vscode-open-in-typora) extension — `open -a Typora` on macOS, no cursor-position handoff (Typora has no such CLI flag).

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

On a new machine, also run from the **iTerm2** app menu:

- **iTerm2 → Make iTerm2 Default Term** — makes iTerm2 the default terminal app.
- **iTerm2 → Install Shell Integration** — enables shell integration (command status, marks, `it2` utilities).

### Option-as-Meta

For nvim mappings using `<M-...>` (e.g. `<M-1>`..`<M-9>` to jump to a buffer row in the `<leader>m` buffer picker) to work, iTerm2 needs to send Option as Meta instead of typing special characters (`¡`, `™`, etc.):

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

<a id="directory-jumping-zoxide"></a>
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

- **`~/.zshrc_halp.zsh`** — stowed from this repo. Shared per-project tooling. Lives in version control.
- **`~/.zshrc_bitgo.zsh`** — *not* stowed. `zsh/.stow-local-ignore` excludes it so each work machine drops its own copy at `~/.zshrc_bitgo.zsh`. The repo copy is a reference template.

> **Gotcha:** `zsh/.stow-local-ignore` is itself gitignored (see the root `.gitignore`), so it does **not** exist on a fresh clone. Until you create it, `stow zsh` will symlink `.zshrc_bitgo.zsh` into `~` along with everything else — and a non-work machine then runs the BitGo colima/AWS setup on every shell launch. On a personal machine, create it **before** stowing:
>
> ```bash
> printf '.zshrc_bitgo.zsh\n' > zsh/.stow-local-ignore
> ```
>
> On a BitGo work machine, skip this and drop your real `~/.zshrc_bitgo.zsh` in place instead.

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

## Colima

Free container runtime for macOS — a Docker Desktop alternative.

```bash
brew install colima docker

# Apple Silicon
colima start --cpu 8 --memory 8 --arch aarch64 --vm-type=vz --vz-rosetta

# Intel
colima start --cpu 2 --memory 4
```

The `docker` CLI talks to Colima's daemon automatically. The `.zshrc_bitgo.zsh` file includes a `colima_start` helper and an auto-check that warns if Colima isn't running.

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

## rcmd

App/window switcher driven by the Right Command key. Config (assignments, Stages, and settings) is a plain YAML file at `~/.config/rcmd/config.yaml`, managed via stow.

```bash
brew install --cask rcmd
cd ~/src/dotfiles
stow rcmd
```

The app reads `~/.config/rcmd/config.yaml` continuously and picks up edits within a few seconds — hand-edit it, or let rcmd's own settings UI write through the symlink. Run `rcmd config help` for the full settings reference. `~/.config/rcmd/search-cache.yaml` (learned query → app selections) is intentionally not tracked — it's a disposable cache, not a setting.

## yknotify

macOS daemon that watches the system log for YubiKey touch events and fires a
notification. Configured to skip FIDO2 (browser/WebAuthn) and only notify for
OpenPGP touches (GPG signing, SSH, sudo) with a 10-second cooldown.

The stow package places two files:

- `~/yknotify.sh` — wrapper that reads yknotify's NDJSON output and fires notifications
- `~/Library/LaunchAgents/com.user.yknotify.plist` — runs the wrapper as a persistent background agent

**One-time setup:**

```bash
go install github.com/noperator/yknotify@latest
cd ~/src/dotfiles

# Expand $USER placeholder in the plist, then stow
sed -i '' "s/__USER__/$USER/g" yknotify/Library/LaunchAgents/com.user.yknotify.plist
stow --no-folding yknotify

launchctl load ~/Library/LaunchAgents/com.user.yknotify.plist
launchctl start com.user.yknotify
```

> **Note:** The `sed` step above modifies the tracked plist in-place to embed
> your username (launchd requires absolute paths). Commit the change after
> running it so the plist reflects your actual username.

The `.zshrc_bitgo.zsh` `yknotify_check` function warns at shell start if the
LaunchAgent is not loaded.

**Do Not Disturb / Focus mode:** notifications are sent via `terminal-notifier
-ignoreDnD`, but on macOS 14+ this flag alone is not enough to break through
Focus. You must also allowlist `terminal-notifier` explicitly:

> System Settings → Focus → Do Not Disturb → (i) → Apps → Add `terminal-notifier`

Without this, notifications are silently queued in Notification Center and
never shown as banners while Focus is active.
