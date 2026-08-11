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
- [Herdr](#herdr)
- [Cursor CLI (cursor-agent)](#cursor-cli-cursor-agent)
- [OpenRouter](#openrouter) — the model gateway behind the two agents below
- [opencode](#opencode) — [Theme](#opencode-theme)
- [pi](#pi) — [Theme](#pi-theme) · [Extensions](#pi-extensions)

*Editors*
- [Neovim](#neovim)
- [Neovide](#neovide)
- [Typora](#typora)
- [RustRover](#rustrover) — [Claude Code plugin](#claude-code-plugin)

*Terminals & multiplexing*
- [Ghostty](#ghostty) · [Zellij](#zellij)

*Shell*
- [ZSH](#zsh) — [prompt (Starship)](#prompt-starship) · [zoxide](#directory-jumping-zoxide) · [troubleshooting antigen](#troubleshooting-antigen)

*Version control*
- [Git](#git) — [SSH for GitHub](#ssh-for-github)

*Optional / utilities*
- [Colima](#colima) · [macos](#macos) · [rcmd](#rcmd) · [ripgrep](#ripgrep) · [Tabularis](#tabularis) — [MCP integration](#mcp-integration) · [viu](#viu) · [yknotify](#yknotify)


# Part 1: Essentials

<a id="quick-start-fresh-machine"></a>
## Quick start (fresh machine)

Ordered path for a brand-new macOS machine. Each step links to its detailed
section below; the rest of this README is reference material for individual tools.

1. **Homebrew** — `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. **Xcode Command Line Tools** (C compiler for treesitter) — `xcode-select --install`
3. **Clone this repo** to `~/src/dotfiles` (HTTPS for now — the [Git](#git) step later rewrites GitHub to SSH):
   ```bash
   mkdir -p ~/src && git clone https://github.com/null-sleep/dotfiles.git ~/src/dotfiles
   ```
4. **Install everything from the [`Brewfile`](Brewfile)** — `cd ~/src/dotfiles && brew bundle`. Installs every core CLI, font, runtime, and GUI app in one shot — idempotent, safe to re-run (a few situational tools are left commented in the Brewfile). The SF Mono Square tap is marked `trusted: true` so `brew bundle` installs it without a prompt. Then finish the [Fonts](#fonts) step — SF Mono Square needs a manual symlink into `~/Library/Fonts`.
5. **Rust** — not in the Brewfile; install via rustup ([Languages](#languages)).
6. **Stow the configs** — `stow nvim zsh ghostty rcmd ripgrep && stow --no-folding claude cursor opencode pi herdr` (add `zellij` only if you enabled that optional formula) ([Setup](#setup)).
7. **Per-tool setup:** antigen + zsh-direnv + `~/.zshrc` ([ZSH](#zsh)); git identity + SSH key/config ([Git](#git)); Claude Code setup scripts ([Claude Code](#claude-code)); Cursor CLI statusline setup ([Cursor CLI](#cursor-cli-cursor-agent)); `setup-zshenv.sh` + `OPENROUTER_API_KEY` in `~/.zshenv` ([OpenRouter](#openrouter)); pi npm install + `setup-settings.sh` + `setup-extensions.sh` ([pi](#pi)); `herdr/setup-herdr.sh` ([Herdr](#herdr)); Neovide config symlink ([Neovide](#neovide)).
8. **Open a new shell** (`exec zsh`). First launch clones antigen bundles (~20s); first `nvim` clones plugins + Mason servers (~1 min).
9. **[Verify your setup](#verify-your-setup)** with the smoke test.

## Fonts

Install these **first** — they are prerequisites for the terminal (Ghostty)
and editors (nvim, Neovide) configured here. Without a Nerd Font, icons
and glyphs render as tofu boxes (▯).

```bash
# Hack Nerd Font (used by Ghostty, nvim, Neovide for icons and glyphs)
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
stow --no-folding cursor     # needs cursor-agent installed — see the Cursor CLI section
stow --no-folding opencode   # needs the opencode formula — see the opencode section
stow --no-folding pi         # themes + minimal footer extension — see the pi section
stow ghostty                 # needs the ghostty cask — the primary terminal
stow rcmd                    # needs the rcmd cask
stow --no-folding herdr      # needs the herdr formula — see the Herdr section
# Optional — only if you uncommented its formula in the Brewfile:
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
| Open a new shell | [Starship](#prompt-starship) prompt renders `<dir>(<branch>):`, not the macOS `… %` default |
| `command -v starship` | resolves (prompt falls back to a hint if missing) |
| `z foo` / `zi` | jumps by frecency / opens an fzf picker ([zoxide](#directory-jumping-zoxide)) |
| `command -v rg fd fzf zoxide direnv stow` | all resolve |
| `python3 --version` | 3.12.x (not the system 3.9) |
| `rustc --version` && `cargo --version` | both resolve (rustup) |
| `ssh -T git@github.com` | `Hi <username>!` ([SSH for GitHub](#ssh-for-github)) |
| Terminal glyphs | file-tree / git icons render, not tofu boxes (▯) — fonts installed |
| `~/.local/bin/claude-nvim check` | prints `startup-ok` (nvim config loads clean) |
| `nvim` → `:Mason` | LSP servers/tools show installed, not failed ([Languages](#languages)) |
| `nvim` → `:checkhealth` | treesitter, snacks, lsp, blink.cmp all green |
| Claude Code | statusline renders; theme is Catppuccin Latte ([Claude Code](#claude-code)) |
| `cursor-agent` | statusline renders (model / ctx% / CH% / growth bars) ([Cursor CLI](#cursor-cli-cursor-agent)) |
| `printenv OPENROUTER_API_KEY` | prints a key ([OpenRouter](#openrouter)) |
| `opencode run "say ok"` | answers via OpenRouter ([opencode](#opencode)) |
| `pi -p "say ok"` | answers via OpenRouter ([pi](#pi)) |
| `command -v herdr` | resolves ([Herdr](#herdr)) |
| `herdr integration status --outdated-only` | empty output |

If the prompt shows the macOS default instead of the Starship line, either `starship` isn't installed (`brew install starship`) or antigen didn't load — see [Prompt (Starship)](#prompt-starship) and [Troubleshooting antigen](#troubleshooting-antigen). If `:Mason` shows failures, a language runtime is missing — see the callout in [Languages](#languages).

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
>
> **Want a newly added tool *now*? Run `:MasonToolsUpdate`, not
> `:MasonToolsInstall`.** The config sets `debounce_hours = 24`, which gates the
> whole install check — and the automatic startup run refreshes that timestamp
> on every launch, so for the next 24h `:MasonToolsInstall` **silently does
> nothing**. `:MasonToolsUpdate` forces past the debounce. Either way, packages
> built from source (`delve`, `gotestsum`) take minutes with no output — watch
> `:Mason`, not the notifications.

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

The `claude` stow package manages the status line script — a custom status bar that displays model name (with a fast-mode/effort flag), context window %, cache-hit rate, message count, per-message context growth bars, and a right-aligned 5h/7d rate-limit cluster with reset countdown (set `CLAUDE_STATUSLINE_MODE=cost` for session/monthly cost instead). On narrow terminals it drops whole low-priority segments instead of clipping the rate-limit cluster; `bash ~/.claude/statusline-command.sh --status` explains payload resolution, widths, and shedding using piped input or the last reduced payload. The package also provides a custom **Catppuccin Latte** color theme.

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
# Activate the review-pr skill for this machine (one-time)
bash ~/src/dotfiles/claude/setup-review-pr.sh
# Register the rtk token-optimizer hook in ~/.claude/settings.json (one-time)
rtk init -g --auto-patch
```

The `--no-folding` flag is important: it keeps `~/.claude/themes/`,
`~/.claude/skills/`, and `~/.claude/hooks/` as **real directories** with only
the repo's individual files symlinked in, so any machine-local themes, skills,
or hooks already there coexist untouched. Without it, stow would replace a
non-existent `~/.claude/themes/` with a single directory symlink (a "fold"),
which can't hold local files alongside the synced ones.

All four setup scripts are idempotent; re-running any of them when already configured is a no-op. `setup-statusline.sh`, `setup-theme.sh`, and `setup-lsp-plugins.sh` use `jq` to edit `settings.json`: `setup-statusline.sh` adds the `statusLine` config (and rewrites a hardcoded path to `$HOME` if present); `setup-theme.sh` sets `"theme": "custom:active"` and seeds `~/.claude/themes/active.json` so the unified `theme` switcher (see [Unified theme switching](#unified-theme-switching)) can swap dark/light live; `setup-lsp-plugins.sh` enables the LSP plugins (see [LSP plugins](#lsp-plugins-code-intelligence) below). `setup-review-pr.sh` doesn't touch `settings.json` — it symlinks `~/.claude/skills/review-pr/SKILL.md` to the tracked `SKILL.generic.md` (see [What's managed](#whats-managed) below).

<a id="whats-managed"></a>
### What's managed

| File | Method |
|---|---|
| `~/.claude/statusline-command.sh` | Symlinked via stow |
| `~/.claude/themes/*.json` (10 themes, incl. the `catppuccin-latte`/`dracula` pair the `theme` switcher uses) | Symlinked via stow (`--no-folding`) |
| `~/.claude/skills/nvim-theme-to-claude/SKILL.md` | Symlinked via stow (`--no-folding`) |
| `~/.claude/skills/review-pr/SKILL.generic.md` | Symlinked via stow (`--no-folding`) |
| `~/.claude/skills/review-pr/SKILL.md` | **Not** stowed — machine-local symlink to `SKILL.generic.md` above, created by `setup-review-pr.sh` |
| `~/.claude/skills/keymap-audit/SKILL.md` | Symlinked via stow (`--no-folding`) |
| `~/.claude/keybindings.json` | Symlinked via stow — pins `chat:undo` to its default Ctrl+_, which nvim's sidekick `u` keymap forwards (see GUIDE.md's AI section) |
| `~/.claude/settings.json` | Symlinked via stow — global preferences (statusLine, theme, LSP plugins, model/effort/tui, hooks) |
| `~/.claude/hooks/sidekick-notify.sh` | Symlinked via stow (`--no-folding`) — Claude-hook → nvim RPC bridge for the agent view's attention glyphs (registered in `settings.json`; no-ops outside a sidekick-managed nvim, see the nvim GUIDE's AI section) |

`~/.claude/hooks/sidekick-notify.sh` depends on `jq` and coreutils' `timeout` — both no-op-guard-checked at the top of the script, so a machine missing either just gets no agent-view attention glyphs rather than a broken hook; `jq` and `coreutils` are both in the Brewfile.

`settings.json` **is stowed** (adopted 2026-08 so the sidekick hook registrations sync across machines — see the nvim GUIDE's AI section). Anything genuinely per-machine belongs in `~/.claude/settings.local.json`, which stays unmanaged. The three `jq`-based `setup-*.sh` scripts still merge their keys idempotently — they resolve the symlink first and write through it (a plain `mv` onto the link path would silently de-adopt the file) — so they're no-ops on a stowed machine and still bootstrap an unstowed one. `setup-theme.sh`'s real remaining job is seeding `~/.claude/themes/active.json`; `setup-lsp-plugins.sh`'s is the server-binary checks.

**`review-pr`'s machine-local `SKILL.md`:** the repo tracks `SKILL.generic.md` (provider-neutral), but `SKILL.md` — the file Claude actually loads — is deliberately left untracked so stow can never overwrite a per-machine choice. `setup-review-pr.sh` creates `SKILL.md` as a symlink to `SKILL.generic.md`; re-running is idempotent. On a machine that needs project-specific tweaks, drop a private `SKILL.*.md` next to it and point `SKILL.md` there instead.

### Recommended manual settings

Most preference keys (`model`, `effortLevel`, `tui`, `statusLine`, `theme`,
`enabledPlugins`) now arrive with the stowed `settings.json` — override any of
them per machine in `~/.claude/settings.local.json` rather than editing the
stowed file locally. Notably, the stowed file pins `model` (currently
`opus[1m]`), so a fresh machine inherits that model choice too; override it in
`settings.local.json` if a machine should default to something else. One key
stays a deliberate judgment call and is *not* in the stowed file:

- **`env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`** — set to `"1"` to stop
  Claude Code from sending non-essential telemetry (Statsig analytics,
  Sentry error reports). Doesn't affect core inference traffic. **Tradeoff:**
  this same flag also disables [artifact
  publishing](https://code.claude.com/docs/en/artifacts) with no override — set
  it, and Claude writes a local HTML file instead of publishing to a
  `claude.ai/code/artifact/…` URL. Leave it unset (the default) to keep
  artifacts working; only set it on a machine where you'd rather suppress
  telemetry than publish artifacts.

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

`--auto-patch` skips the interactive confirmation (needed when scripting; drop it to review the settings.json edit first). It's idempotent — re-running just re-confirms the hook. The hook itself now rides in the **stowed** `settings.json`, so on a stowed machine there's usually nothing to patch; `RTK.md`, the `CLAUDE.md` reference, and `filters.toml` stay machine-local, seeded by the one command above. If `rtk init` does rewrite `settings.json`, check afterward that `~/.claude/settings.json` is still a symlink — external tools that replace-by-rename silently de-adopt stowed files, and once that happens a plain `stow --no-folding claude` won't fix it: stow sees a real file already at the target and aborts rather than overwriting it. Recover with `rm ~/.claude/settings.json && stow --no-folding claude`. **Restart Claude Code** afterward so it loads the hook. Check savings with `rtk gain`; remove everything with `rtk init -g --uninstall`.

<a id="theme"></a>
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
- **`--no-folding`** keeps `~/.claude/themes/`, `~/.claude/skills/`, and
  `~/.claude/hooks/` as real directories, so the existing folders and any
  machine-local files in them are preserved.
- **Non-destructive**: if that machine already has a real `catppuccin-latte.json`
  or its own `nvim-theme-to-claude/` skill, stow aborts without touching
  anything. To merge instead, move the local file aside, or run
  `stow --adopt --no-folding claude` to pull the existing file into the repo
  (then `git checkout -- <file>` if you want the repo's version to win).

For the skill only, skip the `setup-theme.sh` step — `git pull`,
`stow -R --no-folding claude`, restart. The skill then lives at
`~/.claude/skills/nvim-theme-to-claude/` and is invokable from any project.

**`review-pr` needs one more step**, because its `SKILL.md` is machine-local
(see [What's managed](#whats-managed) above) rather than stowed: after
`stow -R --no-folding claude`, run `bash ~/src/dotfiles/claude/setup-review-pr.sh`
to (re)create the `SKILL.md` symlink. This is required, not optional — restow
alone never creates `SKILL.md` (it's untracked), so
`~/.claude/skills/review-pr/SKILL.md` stays absent or **dangling** until you
run the script.

## Unified theme switching

One command flips **Claude Code, Neovim, pi, and the macOS system appearance**
between a predefined dark and light theme at once. **The terminal isn't driven
by the script at all**: Ghostty follows the macOS appearance natively (see
below), so flipping the system appearance recolors every window — new *and*
existing. [opencode](#opencode) rides along the same way.

Claude Code, Neovim, and pi all switch **live, no restarts** (see [How each
tool switches live](#how-each-tool-switches-live)).

```bash
theme            # toggle dark/light (pins, like dark/light below)
theme dark       # PIN dark everywhere (turns macOS Auto OFF)
theme light      # PIN light everywhere (turns macOS Auto OFF)
theme auto       # hand control back to macOS Auto (sunset/sunrise); everything follows
theme follow     # match Claude+nvim+pi to current macOS appearance (don't set macOS)
theme watch      # daemon loop used by the auto-follow LaunchAgent (see below)
theme status     # show appearance, macOS mode (auto/pinned), and follower state
```

**Three modes — `dark` · `light` · `auto`:**

- **`dark` / `light`** *pin* that appearance everywhere at once: macOS Auto is
  switched **off**, the macOS appearance is set to the fixed value, and
  Claude + nvim + pi are swapped to match. It stays put until you change it
  again — exactly like choosing Light or Dark in **System Settings → Appearance**.
- **`auto`** hands the wheel back to macOS: it re-enables native **Auto**
  (sunset/sunrise), and Claude + nvim + pi follow via the [watch
  LaunchAgent](#auto-follow-on-macos-appearance-changes). One caveat — the macOS
  Auto flag governs *future* evaluations, so macOS applies the schedule at the
  next sunrise/sunset (or when you next click **Auto** in System Settings); it
  doesn't retroactively repaint the current desktop. `theme auto` syncs
  Claude + nvim + pi to the present appearance immediately so nothing is out of
  step meanwhile.

The predefined pair (edit the `LIGHT`/`DARK` arrays at the top of
`zsh/.local/bin/theme` to change it):

| Mode  | Claude theme       | nvim variant       | pi theme           | macOS appearance |
|-------|--------------------|--------------------|--------------------|------------------|
| light | `catppuccin-latte` | `catppuccin-latte` | `catppuccin-latte` | light (pinned)   |
| dark  | `dracula`          | `dracula`          | `dracula`          | dark (pinned)    |
| auto  | follows macOS      | follows macOS      | follows macOS      | Auto (schedule)  |

Ghostty, opencode, and Herdr aren't in the table because the script never
touches them — each follows the macOS/host-terminal appearance directly
instead. Herdr's own `auto_switch` config does the following, matched to this
same `dracula`/`catppuccin-latte` pair (see [Herdr](#herdr)).

### Ghostty setup (none needed)

Ghostty's config carries the light/dark pair in one line —
`theme = light:Catppuccin Latte,dark:Dracula` — so `stow ghostty` is the entire
setup. It recolors all windows the moment macOS switches.

### How each tool switches live

- **macOS** — `osascript` sets the system appearance. This is the hinge the
  whole design turns on; everything else either follows it (Ghostty) or is
  switched alongside it (Claude, nvim).
- **Ghostty** — not driven by the script. Its `theme = light:…,dark:…` config
  line (see [Ghostty](#ghostty)) makes it track the macOS appearance natively,
  recoloring every window including ones opened after the switch.
- **Shell prompt (Starship)** — not driven by the script either. It rides on
  Ghostty's palette swap: the prompt is styled with ANSI color *names*, which
  the terminal resolves against its active 16-color scheme, so the next prompt
  after a theme flip recolors on its own. No `theme`-script change needed. (See
  [Prompt (Starship)](#prompt-starship).)
- **Claude Code** — Claude hot-reloads theme *files* but not the `theme`
  *setting*, so `settings.json` pins the fixed slug `custom:active` and the
  script overwrites `~/.claude/themes/active.json` with the chosen palette.
  Running sessions recolor instantly. (See [Claude Code → Theme](#theme).)
- **opencode** — not driven by the script either, for the same reason as
  Starship: its `system` theme derives its colors from the terminal's
  background and ANSI palette, so Ghostty's swap recolors it for free. It reads
  the background once at startup (an OSC 11 query), so already-open sessions
  keep the colors they launched with; new ones are correct. (See
  [opencode](#opencode).)
- **pi** — the same active-slot indirection as Claude Code. `settings.json`
  pins the fixed theme name `active`, and the script overwrites
  `~/.pi/agent/themes/active.json` with the chosen palette; pi hot-reloads the
  active theme file, so running sessions recolor. The palettes are ports of the
  pair above, tracked in this repo (`pi/.pi/agent/themes/`). (See
  [pi](#pi).)
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
toggle. Ghostty follows those native flips automatically, but nothing would tell
Claude, nvim, or pi. The **theme-follow LaunchAgent** closes that gap: it keeps
`theme watch` running, which polls the macOS appearance and runs `theme follow`
on every flip — so Claude + nvim + pi track macOS no matter *who* changed it.
This is what makes `theme auto` "follow macOS everywhere."

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
→ Ghostty recolors natively, and the follower repaints Claude + nvim + pi to
match.

- **No Automation prompt, no loop.** `watch`/`follow` read the appearance with
  `defaults read -g AppleInterfaceStyle` (not `osascript`), so the agent runs
  unattended; and `follow` only touches Claude + nvim + pi — it never writes the
  macOS appearance back, so it can't fight Auto mode or ping-pong with the watcher.
- **Reload the agent after editing the `theme` script.** The watcher is a
  long-running `bash` process, and bash parses the whole loop into memory before
  running it — so a live agent keeps executing the copy it started with,
  however many times you edit the file underneath it. Found the hard way on
  2026-08-07: the follower had been up for 30 days and was still running a
  script that predated pi support, so a sunset flip would have switched Claude
  and nvim and silently left pi behind. After any edit:
  ```bash
  launchctl kickstart -k "gui/$(id -u)/com.dhruv.theme-follow"
  ```
  `ps -o lstart -p "$(pgrep -f 'theme watch')"` tells you how stale the running
  copy is.
- **Portable plist.** `com.dhruv.theme-follow.plist` runs
  `zsh -c 'exec "$HOME/.local/bin/theme" watch'`, so `$HOME` expands at launch —
  the same stowed file works on any machine, no path rewriting.
- **Tuning / disabling.** The poll interval is `THEME_WATCH_INTERVAL` seconds
  (default `2`), set in the plist's `EnvironmentVariables` — launchd doesn't
  inherit your shell env, so edit it *there* (then re-run `setup-theme-follow.sh`
  to reload), not in `.zshrc`. `theme status` reports whether the follower is
  loaded; logs are at `/tmp/theme-follow.{out,err}.log` (chosen over
  `~/Library/Logs` because a plist log path can't expand `$HOME` and we keep the
  plist portable). **A missing log file doesn't mean the agent is idle** —
  macOS prunes `/tmp`, and launchd goes on writing to the unlinked file, so the
  log silently stops appearing. Check the process, not the log. Disable with
  `launchctl bootout gui/$(id -u)/com.dhruv.theme-follow`.

`macos/setup-theme-follow.sh` is `.stow-local-ignore`d (like the `claude/setup-*`
scripts), so `stow macos` only links the plist, not the bootstrap script.

## Claude Squad

Terminal app for running multiple AI coding agents (Claude Code, Codex, Gemini, Aider) in parallel. Each session gets an isolated [git worktree](https://git-scm.com/docs/git-worktree) and its own [tmux](https://github.com/tmux/tmux) session — no branch conflicts, and tasks keep running in the background. See [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad). See also [Herdr](#herdr), a persistent agent multiplexer covering similar ground with a different design center (agent lifecycle/state detection vs. worktree/session management).

### Setup

```bash
# Prerequisites
brew install tmux gh

# Install claude-squad and symlink as `cs`
brew install claude-squad
ln -s "$(brew --prefix)/bin/claude-squad" "$(brew --prefix)/bin/cs"
```

Pushing branches from sessions needs `gh auth login` — one-time per machine,
see [Git](#git) if not already done.

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

## Herdr

[Herdr](https://github.com/herdrdev/herdr) is a persistent-server terminal
multiplexer built for coding agents: panes survive lid-close, network drops,
and machine restarts, and each is classified `working`/`blocked`/`idle`/`done`
by screen detection. It runs Claude Code, pi, and others without wrapping them,
and exposes a CLI + socket API agents can drive themselves (`herdr --skill`
installs the agent-facing skill; see below).

This sits alongside [Claude Squad](#claude-squad) and (optional) [Zellij](#zellij)
as this repo's third multiplexer-shaped tool — Herdr is the one built
specifically around agent lifecycle (state detection, session restore,
cross-agent orchestration) rather than general session/window management.
It's also the **outside-nvim** counterpart to
[sidekick's in-nvim agent terminals](plans/sidekick-agent-view.md): sidekick
owns agent panes living beside your code inside Neovim; Herdr owns durable
agent sessions detached from any editor, reattachable over SSH.

```bash
brew install herdr
cd ~/src/dotfiles
stow --no-folding herdr    # --no-folding: see below
bash herdr/setup-herdr.sh  # Claude Code + pi integrations, agent skill
```

### Usage

Run `herdr` bare to launch or reattach to the persistent session — it starts a
background server on first run and every later `herdr` just attaches to it, so
closing the terminal (or losing the network) never kills what's running
inside. `herdr --remote <ssh-target>` attaches to a server running on another
machine the same way. Layout nests **workspace → tab → pane** (a workspace is
roughly tmux's session — one per project/worktree; tabs and panes work like
tmux windows/splits).

Default keymaps use a `ctrl+b` prefix (edit `[keys]` in `config.toml` to
change it; `herdr config reset-keys` restores the defaults) — like tmux, every
`prefix X` binding below is a **two-step chord, not held together**: press
and release `Ctrl+B` first (Herdr silently enters prefix mode and waits
briefly for one more key), *then* press the second key on its own:

| Key | Action |
|---|---|
| `Ctrl+B`, then `?` | Help |
| `Ctrl+B`, then `w` | Workspace picker |
| `Ctrl+B`, then `Shift+N` | New workspace |
| `Ctrl+B`, then `Shift+G` | New workspace from a git worktree |
| `Ctrl+B`, then `c` | New tab |
| `Ctrl+B`, then `n` / `Ctrl+B`, then `p` | Next / previous tab |
| `Ctrl+B`, then `v` / `Ctrl+B`, then `-` | Split pane vertically / horizontally |
| `Ctrl+B`, then `h`/`j`/`k`/`l` | Focus pane left/down/up/right |
| `Ctrl+B`, then `z` | Zoom pane |
| `Ctrl+B`, then `x` | Close pane |
| `Ctrl+B`, then `b` | Toggle sidebar — collapses to `sidebar_collapsed_mode` (`"hidden"` here, see `config.toml`) |
| `Ctrl+B`, then `q` | Detach (server keeps running) |

Panes running a supported agent (Claude Code, pi, …) show their
`working`/`blocked`/`idle`/`done` state in the sidebar without any extra
config — that's screen detection, not the integrations above. The sidebar is
fixed on the left (no left/right placement option in v0.8.0's `[ui]` config —
checked `herdr --default-config`); `Ctrl+B`, then `b` above is the only lever,
useful when nvim is running in an adjacent pane and you want the width back.

A few CLI entry points worth knowing beyond the keymaps: `herdr agent list` /
`herdr agent wait --until done` (block until a sibling agent finishes —
useful for orchestrating one agent from another), `herdr pane run <cmd>`
(run a command in a new pane without stealing focus), and
`herdr worktree create` (open a git worktree as its own workspace). Full
CLI reference: `herdr --help` and each subcommand's own `--help`.

**Agents driving Herdr themselves** (not just running inside it) is a
separate surface: `herdr --skill` prints a bundled skill teaching an agent
the CLI, installed to `~/.claude/skills/herdr/SKILL.md` by
`setup-herdr.sh`. It gates itself on `HERDR_ENV=1` (only set inside a
Herdr-managed pane), so it only activates for an agent actually running
inside Herdr, not just because a task could use a background terminal.

**Why `--no-folding`:** `~/.config/herdr/` holds both the stowed `config.toml`
*and* runtime state Herdr writes itself (`herdr.sock`, `herdr.log`,
`session.json`, `sessions/<name>/`). Folding would symlink the whole
directory into the repo, putting that state under git.

**Stow before first launch.** If `herdr` already ran once, it will have
written a real `~/.config/herdr/config.toml`, and `stow --no-folding herdr`
aborts with a conflict rather than overwriting it. Recover the same way as the
[rtk de-adoption case](#claude-code) above:

```bash
rm ~/.config/herdr/config.toml && stow --no-folding herdr
```

<a id="herdr-whats-managed"></a>
### What's managed

| File | Method |
|---|---|
| `~/.config/herdr/config.toml` | Symlinked via stow (`--no-folding`) |
| `~/.claude/hooks/herdr-agent-state.sh` | Written by `herdr integration install claude`; machine-local |
| `~/.pi/agent/extensions/herdr-agent-state.ts` | Written by `herdr integration install pi`; machine-local |
| `~/.claude/skills/herdr/SKILL.md` | Written by `herdr --skill`; machine-local |

The last three are release-matched to the installed `herdr` binary, so
`setup-herdr.sh` regenerates them unconditionally — **always re-run it after
`brew upgrade herdr`** (never `herdr update`, which is disabled for
Homebrew installs).

**The Claude Code hook is tracked, with a guard.** `herdr integration install
claude` adds a `SessionStart` hook entry to the stow-symlinked
`claude/.claude/settings.json` — verified to write through the symlink rather
than replacing it, unlike the [de-adoption hazard](#claude-code) rtk can hit.
`setup-herdr.sh` then wraps the command in
`if command -v herdr >/dev/null 2>&1; then …; fi`,
matching the existing [rtk](#claude-code) hook, so a machine with the repo
stowed but no `herdr` binary doesn't get a failing Claude Code hook. Two
things follow from that:

- `herdr integration status` may report the Claude entry as needing attention
  since the tracked command no longer matches what a fresh install would
  write — that's expected, don't "fix" it by re-running the installer by hand.
  Always go through `setup-herdr.sh`, which checks for an existing entry
  first; calling `herdr integration install claude` directly once a guarded
  entry is in place appends a **duplicate**, unwrapped entry instead of
  recognizing it.
- The hook's command hardcodes `/Users/<you>/.claude/hooks/herdr-agent-state.sh`
  as an absolute path (herdr's installer writes it that way, unlike the
  `$HOME`-relative style the other hooks in this file use) — fine as long as
  this repo lives under the same home directory, which it always does here.

**What the hook actually buys:** session-identity reporting for restore
(`claude --resume <id>` after a Herdr server restart), not pane state — Herdr
classifies Claude panes by screen detection either way, with or without the
hook installed.

**Other gotchas:**
- Herdr's Claude hook coexists with this repo's `sidekick-notify.sh` hooks;
  Claude Code runs every matching hook per event, so both fire.
- The `[experimental] pane_history` config key (off by default, left
  unset here) replays recent pane output across a server restart — the docs
  warn it can capture secrets and tokens, so leave it off unless you've
  thought about that.
- `herdr integration uninstall <agent>` removes the extension/hook file, but
  the hand-guarded `settings.json` entry likely won't match and needs
  removing by hand.

<a id="cursor-cli-cursor-agent"></a>
## Cursor CLI (cursor-agent)

Cursor's terminal coding agent — a peer to the Claude Code CLI. Installed here as
the second agent in the Neovim /
[sidekick.nvim](https://github.com/folke/sidekick.nvim) integration — spawn one
with `<leader>an`; keymaps in the nvim config's GUIDE.md, "AI (sidekick.nvim)",
design history in
[plans/sidekick-cursor-support.md](plans/sidekick-cursor-support.md). Also
usable standalone as `cursor-agent`.

**Install** — not on Homebrew; use Cursor's install script (canonical at
<https://cursor.com/cli>):

```bash
curl https://cursor.com/install -fsS | bash
```

This installs the agent under `~/.local/share/cursor-agent/versions/<stamped>/`
and drops `agent`, `cursor`, and `cursor-agent` shims into `~/.local/bin`. It
**self-updates** — a new versioned directory plus repointed symlinks on each
update — so those shims are **not** tracked or stowed by this repo (they're
gitignored; see `.gitignore`). The install command above is the
reproducible-on-a-new-machine record, in place of checked-in files.

**`cli-config.json` is deliberately not stowed.** `~/.cursor/cli-config.json`
mixes durable `/config` choices with caches and account identifiers, and
Cursor's own managed `~/.cursor/.gitignore` ignores it — only `rules/`,
`commands/`, and `skills/` are treated as versionable user content. The
`cursor` stow package (below) symlinks only the statusline **script**;
`cli-config.json` itself stays machine-local, with just its `statusLine`
block injected by `setup-statusline.sh` — the same split as Claude's
`settings.json`. (Also confirmed 2026-07-22: no copy-on-select setting exists
in the config schema — but the TUI doesn't grab the mouse, so the terminal's
native select-to-copy works as-is.)

### Status line

`cursor-agent` gets a custom status line matching the Claude Code one for the
fields Cursor's payload provides — model name (with the same `Name (1M context)`
→ `Name [1M]` compaction), context %, cache-hit rate, message count, and a
per-message context-growth sparkline. Cache hit rate uses the same
`cache_read / (input + cache_read + cache_creation)` formula as Claude. It uses
Cursor's `render_width_chars` to drop whole low-priority segments on narrow
terminals (`bars → messages → cache → model`; ctx is retained). No branch
(dropped 2026-07-22, matching the Claude line) and no cost, fast/effort, or
rate-limit segments (absent from Cursor's stdin payload); the script is a
trimmed fork of `claude/.claude/statusline-command.sh`. Run `bash
~/.cursor/statusline-command.sh --status` with a piped payload, or after a
normal render to replay its reduced cached payload, for field and width
diagnostics.

```bash
stow --no-folding cursor    # --no-folding: never fold a pre-existing ~/.cursor/
bash ~/src/dotfiles/cursor/setup-statusline.sh
```

`setup-statusline.sh` is idempotent (re-running when already configured is a
no-op) and uses `jq` to merge only the `statusLine` block into
`~/.cursor/cli-config.json`, preserving every other key. If a later `/config`
change ever drops the block, re-run the script to restore it.

| File / config | How it's managed |
|---|---|
| `~/.cursor/statusline-command.sh` | Symlinked via stow |
| `~/.cursor/cli-config.json` `statusLine` block | Injected by `setup-statusline.sh` |
| `~/.cursor/cli-config.json` itself | **Not** stowed — machine-local (auth, model prefs) |

### Agent-view rings — no cursor-side config

cursor-agent merges hook registrations from `~/.claude/settings.json`,
mapping `UserPromptSubmit` → `beforeSubmitPrompt`, `Stop` → `stop`, and
`SessionEnd` → `sessionEnd` (`Notification` is deliberately not merged).
So inside an nvim sidekick terminal, cursor sessions get running (`»`) and
turn-complete (`●`) glyphs in the agent view through the already-stowed
Claude hook script, with **zero** cursor-specific files — no
`~/.cursor/hooks.json` needed. There is no urgent (`!`) tier for cursor:
no needs-input hook exists in its vocabulary. Verified 2026-08-10 against
2026.08.04-aaa8809: the merge invokes the script with `$NVIM` and
`$SIDEKICK_SESSION` intact in the hook's env.

The Cursor **IDE** (separate from this CLI) is the `cursor` cask in the
[`Brewfile`](Brewfile).

## OpenRouter

[OpenRouter](https://openrouter.ai) is the model gateway behind the two
non-subscription agents here — [opencode](#opencode) and [pi](#pi). Both treat
it as a first-class built-in provider and read the same environment variable,
so one key powers both and neither needs a custom base URL or provider block.

**Put the key in `~/.zshenv`** — a file this repo deliberately does **not**
track, because it holds a live credential. `bash ~/src/dotfiles/zsh/setup-zshenv.sh`
creates it with an empty key if it doesn't already exist (idempotent — leaves
an existing file alone), then fill in the value by hand:

```bash
bash ~/src/dotfiles/zsh/setup-zshenv.sh
```

```bash
# ~/.zshenv — not stowed, never committed
export OPENROUTER_API_KEY="sk-or-v1-…"   # key from https://openrouter.ai/keys
```

`~/.zshenv` rather than the stowed [`zsh`](#zsh) config: it's the one startup
file zsh reads for **every** invocation — scripts, `nvim` terminals, `zellij`
panes — not just interactive shells like `.zshrc_config.zsh`, so an agent
launched from anywhere sees the key. Keeping it a separate untracked file also
means the secret has no path into this repo at all.

The gap: apps launched from Finder or launchd don't inherit a shell's
environment. There, use the tool's own credential flow — `/connect` in
opencode, `/login openrouter` in pi — which stores the key in that tool's auth
file.

Verify with `printenv OPENROUTER_API_KEY` in a **new** shell. Neither agent
lists any models until the key resolves — that empty list is the usual symptom
of a missing or unexported key.

## opencode

[opencode](https://github.com/anomalyco/opencode) — a terminal AI coding agent,
run as `opencode` (TUI) or `opencode run "<prompt>"` (one-shot). Pointed at
[OpenRouter](#openrouter) rather than a per-lab subscription.

```bash
brew tap anomalyco/tap
brew install opencode
cd ~/src/dotfiles
stow --no-folding opencode
```

Both are in the [`Brewfile`](Brewfile), so `brew bundle` covers the install on
a fresh machine.

<a id="opencode-whats-managed"></a>
### What's managed

| File | Method |
|---|---|
| `~/.config/opencode/opencode.json` | Symlinked via stow (`--no-folding`) |
| `~/.config/opencode/tui.json` | Symlinked via stow (`--no-folding`) |
| `~/.config/opencode/plugins/nvim-notify.ts` | Symlinked via stow (`--no-folding`) |
| `~/.local/share/opencode/auth.json` | **Not** tracked — credentials, written by `/connect` |

`--no-folding` matters here for the same reason it does for
[Claude Code](#claude-code): opencode also writes `agent/`, `command/`, and
`plugin/` subdirectories into `~/.config/opencode/`. Without the flag stow
would replace the whole directory with one symlink into this repo, and
everything opencode wrote afterwards would land in `~/src/dotfiles`.

`opencode.json` sets the OpenRouter model, wires the API key through
opencode's `{env:VAR}` substitution, and pins `autoupdate` to `false` — the
binary is Homebrew-managed, so `brew upgrade opencode` owns the version rather
than having opencode replace it underneath Homebrew.

`plugins/nvim-notify.ts` is the agent-view attention bridge: when opencode
runs inside an nvim sidekick terminal, it forwards prompt/turn-end/
permission/question events to nvim's agent dashboard (nvim GUIDE.md → the
`## AI (sidekick.nvim)` section). Outside sidekick it's a no-op, so the same
config is safe in a plain terminal.

<a id="opencode-theme"></a>
### Theme

`tui.json` sets the **`system`** theme (also opencode's default — pinned here so
it's a deliberate choice rather than whatever the default becomes). It derives
its greys from the terminal's background color and takes its accents from ANSI
0-15, instead of carrying fixed hex colors. Since Ghostty supplies both, and
Ghostty already flips between Catppuccin Latte and Dracula with the system
appearance, opencode tracks the switch for free — the same free ride Starship
gets, and why opencode needs no entry in the `theme` script ([Unified theme
switching](#unified-theme-switching)).

It reads as Latte in light and Dracula in dark because those are the palettes
it's drawing from; it isn't a pixel-exact port of either.

Two things worth knowing, both established by testing on 1.18.10:

- **Only built-in theme names work.** Custom theme files under
  `~/.config/opencode/themes/*.json` are not picked up, in either the
  `defs`/`theme` shape the docs describe or the `light`/`dark` palette shape the
  binary uses internally. An unknown name — including a flavor like
  `catppuccin-latte` — **silently falls back** to the default theme with no
  warning, so a typo looks like "the theme just didn't apply". Valid names
  include `system`, `opencode`, `catppuccin`, `dracula`, `tokyonight`,
  `gruvbox`, `everforest`, `nord`, `rosepine`, `one-dark`.
- **The appearance is read once, at startup**, via an OSC 11 terminal-background
  query. Sessions already open when you flip keep their colors; new ones are
  correct. `/theme` switches a running session by hand.

The bare `catppuccin` theme is a true-color alternative — it carries both
palettes and adapts the same way — but its dark side is Catppuccin Mocha rather
than the Dracula the rest of this setup uses.

**Stow before the first `opencode` run.** Started with no config present,
opencode writes an empty `~/.config/opencode/opencode.jsonc` stub — and
`.jsonc` **takes precedence over** the tracked `opencode.json` (verified
2026-08-06: a `model` set in the stub wins). It won't recreate the stub once
`opencode.json` exists, so if a machine grew one, delete it — the tracked
`.json` should be the only config. Confirm what actually resolved with:

```bash
opencode debug config | jq '{model, autoupdate}'
```

Useful commands: `opencode models` lists what the configured providers expose
(empty output means the key isn't resolving), `/models` switches model inside
the TUI, and `/connect` stores a key in opencode's own auth file if you'd
rather not use the environment variable.

## pi

[pi](https://pi.dev) — a minimal agent harness, run as `pi` (TUI) or
`pi -p "<prompt>"` (non-interactive). Also pointed at
[OpenRouter](#openrouter).

**Install** — not on Homebrew; npm global, using pi's own recommended flags
(`node` comes from the [`Brewfile`](Brewfile)):

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
cd ~/src/dotfiles
stow --no-folding pi         # themes + minimal footer extension — see below
# Seed ~/.pi/agent/settings.json + themes/active.json (one-time)
bash ~/src/dotfiles/pi/setup-settings.sh
# Install the extension set (one-time; needs settings.json, so run it after
# setup-settings.sh) — see Extensions below
bash ~/src/dotfiles/pi/setup-extensions.sh
```

The binary lands in `$(npm prefix -g)/bin` — `/opt/homebrew/bin` with the
brewed `node` — so unlike [cursor-agent](#cursor-cli-cursor-agent) it never
touches the stow-managed `~/.local/bin` and needs no gitignore entry. Update
with `npm update -g @earendil-works/pi-coding-agent` (`pi update` also works,
but let npm own a package npm installed).

<a id="pi-whats-managed"></a>
### What's managed

The `pi` package stows the theme palettes and the repo-owned extensions.
Pi-written settings and extension install state stay machine-local.

| File | Method |
|---|---|
| `~/.pi/agent/themes/catppuccin-latte.json`, `dracula.json` | Symlinked via stow (`--no-folding`) |
| `~/.pi/agent/extensions/claude-footer.ts` | Symlinked via stow; minimal Claude-shaped footer |
| `~/.pi/agent/extensions/nvim-notify.ts` | Symlinked via stow; agent-view attention bridge |
| `~/.pi/agent/themes/active.json` | Written by the [`theme`](#unified-theme-switching) switcher; not tracked |
| `~/.pi/agent/settings.json` | Seeded by `setup-settings.sh`; machine-local |
| `~/.pi/agent/npm/` | **Not** tracked — extension installs, owned by `pi install` |
| `~/.pi/agent/auth.json` | **Not** tracked — credentials, written by `/login` |
| `~/.pi/agent/trust.json` | **Not** tracked — per-project trust decisions |
| `~/.pi/agent/extensions/herdr-agent-state.ts` | Written by `herdr integration install pi` ([Herdr](#herdr)); not tracked |

**Why `settings.json` isn't stowed:** pi *writes* to it — it stamps
`lastChangelogVersion` after an update, and `/settings` edits land there.
Through a stow symlink that would be written straight into this repo. So the
file stays machine-local and `setup-settings.sh` merges in only the keys this
repo cares about, the same split already used for `~/.claude/settings.json` and
`~/.cursor/cli-config.json`.

The script is **fill-in-only** for the model keys (`jq '$defaults * .'`): it
sets what's missing and leaves anything you've since changed alone, so
re-running won't stomp a model you picked by hand. `theme` is the one exception
— it's forced back to `active`, since that's the slot the switcher writes into
and pointing it at a real theme name would break the switch.

`models.json` — pi's custom-provider mechanism — is deliberately absent:
OpenRouter is a built-in provider, so it's only needed for OpenAI-compatible
endpoints pi doesn't already know about.

<a id="pi-theme"></a>
### Theme

pi switches **live**, using the same indirection as [Claude Code's
theme](#theme): `settings.json` pins the fixed theme name `active`, and
`theme dark|light` overwrites `~/.pi/agent/themes/active.json` with the chosen
palette. pi hot-reloads the active theme file when it changes, so running
sessions recolor without a restart ([Unified theme
switching](#unified-theme-switching)).

The two palettes are ports of this setup's pair, written against pi's theme
schema (51 required color tokens) and tracked in `pi/.pi/agent/themes/`. They
keep their real names in that directory so they stay individually selectable in
pi's `/settings` picker; the switcher rewrites `name` to `active` as it copies,
because pi requires theme names to be unique.

`setup-settings.sh` seeds `active.json` from the **current** macOS appearance,
so a machine set up in dark mode starts on Dracula rather than defaulting to
light and staying there until the first flip.

Sanity check: `pi --list-models` — empty output means the key isn't
resolving.

<a id="pi-extensions"></a>
### Extensions

Six extensions from the [@narumitw
collection](https://github.com/narumiruna/pi-extensions), plus two repo-owned
extensions stowed with the `pi` package: `claude-footer.ts` (the minimal
footer) and `nvim-notify.ts` — the agent-view attention bridge, which forwards
prompt/turn-end events to nvim's agent dashboard when pi runs inside a
sidekick terminal (no-op elsewhere, including inside pi-subagents children;
needs pi >= 0.80.5 for the `agent_settled` event it listens on). A ninth
extension, `herdr-agent-state.ts`, is written by [Herdr's](#herdr) pi
integration (`herdr/setup-herdr.sh`), not by this repo. The npm extensions
are installed by
[`pi/setup-extensions.sh`](pi/setup-extensions.sh) (run it **after**
`setup-settings.sh` — `pi install` registers each one in `settings.json`'s
`packages` array, so the file must exist). Idempotent: extensions already in
`packages` are skipped, so a re-run won't reinstall or un-pin anything you've
since changed. Entries are deliberately **unpinned**; `pi update --extensions`
owns updates, the same designated-owner convention as brew for
[opencode](#opencode) and npm for pi itself.

- **pi-lsp** — `lsp_diagnostics` / `lsp_fix` tools plus a `/lsp` status
  command. Installs no language servers: it uses whatever's already on PATH
  (here: `gopls`, `rust-analyzer`, `lua-language-server`) and silently skips
  the rest. To cover more languages, point a custom `~/.pi/agent/pi-lsp.json`
  at mason's binaries — note a custom config *replaces* the default catalog.
- **pi-subagents** — `/subagents` and a family of `subagent*` tools:
  delegate isolated work to child `pi -p` processes (single, parallel,
  chained, or detached), inheriting the OpenRouter setup. Built-in agents
  (`scout`, `planner`, `reviewer`, `worker`) only; custom definitions would
  go in `~/.pi/agent/agents/*.md`.
- **pi-plan-mode** — `/plan` (or `pi --plan`): a read-only planning mode
  enforced by real tool gating — edit/write blocked, bash run through a
  fail-closed read-only parser. Extension tools (including subagents) are
  disabled while planning unless opted in via `/plan tools`.
- **pi-github-pr** — ambient statusline entry for the current branch's PR
  (state, checks, reviews), refreshed via the authenticated `gh` CLI; needs
  `gh auth login` done ([Git](#git)), no extra scopes.
- **pi-usage** — `/usage` plus a statusline entry showing OpenRouter
  **per-key spend** (today/week/month/all-time — not account credit balance;
  that endpoint needs a management key). Reads pi's own resolved credential;
  zero config.
- **claude-footer.ts** — a repo-owned, stowed extension that replaces pi's
  footer with the same minimal visual grammar as [Claude Code](#claude-code):
  plain `model · effort · ctx% · CH% · #turn` text on the left and session cost
  flush-right. It deliberately has no powerline blocks, lead glyph, emoji,
  provider-spend row, cwd, or branch. Actionable extension state (plan,
  subagents, PR) appears only when present on a dim second line; the persistent
  pi-usage status is hidden because `/usage` remains available on demand.
  `setup-extensions.sh` removes the superseded `pi-statusline` package and its
  machine-local config so two extensions never compete for the footer.
- **pi-btw** — `/btw`: ask a quick side question in an ephemeral thread that
  snapshots the conversation without appending to it, keeping the main
  context clean. Uses the session's current model.

### Terminal setup for pi

pi needs the terminal to report `Shift+Enter` and `Option+Backspace` as
distinct keys ([upstream
docs](https://pi.dev/docs/latest/terminal-setup)). Two changes in this repo
cover it:

- **Ghostty** — `alt+backspace=text:\x1b\x7f` added, and the old
  `shift+enter=text:\n` mapping removed so pi can see the chord at all. See
  the [`## Ghostty`](#ghostty) section.
- **JetBrains embedded terminal** — `.zshrc_config.zsh` exports
  `PI_HARDWARE_CURSOR=1` when `$TERMINAL_EMULATOR` is `JetBrains-JediTerm`,
  since pi hides the hardware cursor by default and JediTerm then shows no
  caret. `Shift+Enter` is unfixable there; use Ghostty for multi-line input.

Terminal.app needs no config (pi falls back to reading macOS modifier state,
though not over SSH), and the VS Code/Cursor case is documented in
`docs/pi.md` → *Terminal setup*.

New to pi or the extensions, or want to use them well? See the
example-heavy guide at [`docs/pi.md`](docs/pi.md) — core-TUI basics,
managing extensions, per-extension usage (plan mode, subagents, `/btw`,
LSP tools, the footer), terminal setup, and a gotchas cheat-sheet.

## Neovim

Requires Neovim >= 0.12 (uses `vim.pack`, `vim.lsp.config`, native treesitter API).

```bash
brew install nvim rg fzf fd tree-sitter-cli curl git
```

Then stow and launch:

```bash
cd ~/src/dotfiles
stow nvim
nvim
```

On first launch nvim will:
1. Download all plugins via `vim.pack` (native package manager)
2. Install treesitter parsers for configured languages
3. Download the `blink.cmp` fuzzy binary (pre-built, requires `curl`)
4. Install LSP servers via mason (requires internet)

> **Keymaps, plugins, and per-feature behavior live in
> [`nvim/.config/nvim/GUIDE.md`](nvim/.config/nvim/GUIDE.md)** — the canonical,
> maintained reference for the nvim config (Architecture, Design Decisions, a
> Keymap index, and per-tool sections, all in `<leader>` notation). This
> README covers only installing and first-launching Neovim.

<a id="go-debugging-delve"></a>
### Go debugging — delve first run (one-time setup)

Mason installs `delve` (`dlv`) and `gotestsum` automatically, both built from
source with `go install` — so the Go toolchain must be present first (see
[Languages](#languages)). On macOS, delve can require a one-time codesigning /
developer-mode approval the first time it attaches to a process. Get that out of
the way in a shell, where the prompt is legible, rather than inside nvim:

```bash
cd ~/src/some-go-module   # any real module — delve needs a go.mod, not a bare .go file
dlv debug                 # approve the prompt if one appears, then :q
```

Then restart nvim once after Mason's first install finishes (~30s into the first
launch): if `gotestsum` wasn't on `PATH` when a test first ran, neotest falls back
to plain `go test` for the rest of that session. Keymaps and troubleshooting are
in [GUIDE.md → Go](nvim/.config/nvim/GUIDE.md#go).

<a id="agent-desktop-notifications"></a>
### Agent-view desktop notifications

When an agent gets blocked on you while nvim doesn't have OS focus, nvim pops
a macOS notification (the behavior itself is documented in
[GUIDE.md → Agent view](nvim/.config/nvim/GUIDE.md#agent-view)). It prefers
`terminal-notifier` (already in the Brewfile) with `-ignoreDnD`, which needs
the same one-time Focus allowlisting as [yknotify](#yknotify) to break through
Do Not Disturb. Without it installed, nvim falls back to `osascript` — that
path additionally needs Script Editor enabled under System Settings →
Notifications, and is silently dropped during Focus. Install
`terminal-notifier` rather than fighting the fallback.

### Agent-view regression suite

```bash
nvim/.config/nvim/tests/agentview/run.sh   # runnable from any cwd
```

Headless assertions for the agent attention ring: the `agent_events` state
machine, the desktop-notification gate, the statusline badge, and the agent
view's sidebar. Self-contained — no notifications fire, no agents run. Run it
before and after touching `lua/agent_events.lua`, `lua/agentview.lua`, or the
statusline badge; a red suite means ring semantics changed, intended or not.

<a id="gpg-yubikey-notifications"></a>
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

- **`nvim/.config/nvim/neovide.toml`** — startup settings Neovide reads before nvim launches: `frame = "transparent"` + `title-hidden = true` (chrome blends with the editor), font (Hack Nerd Font Mono 15pt). `maximized` is commented out so window size is restored from `neovide-settings.json`. It also sets `fork = true`, but the zsh function below passes `--fork` explicitly rather than relying on it.
- **`nvim/.config/nvim/lua/neovide.lua`** — runtime `vim.g.neovide_*` vars and keymaps. Gated by `if not vim.g.neovide then return end`, so terminal nvim skips it. Contains animation tuning (cursor/scroll/position lengths, cursor trail), `option_key_is_meta = 'both'` (so `<M-1>`..`<M-9>` keymaps work), proxy icon, hide-mouse-when-typing, floating corner radius, and the keymaps below.

```bash
brew install --cask neovide-app
```

Neovide looks for its config at `~/Library/Application Support/neovide/config.toml` on macOS, so symlink that path to the stowed file once per machine:

```bash
ln -s ~/.config/nvim/neovide.toml "$HOME/Library/Application Support/neovide/config.toml"
```

This works for both terminal and GUI launches (Spotlight, dock) — unlike the `$NEOVIDE_CONFIG` env var, which only propagates to terminal-launched processes.

### Launching from the terminal

The [`zsh`](#zsh) package wraps `neovide` in a function that runs the app bundle's real executable, resolved dynamically (`whence -p` for a `PATH`-only lookup, `:A` to follow the symlink):

```zsh
neovide() {
  local bin=$(whence -p neovide)
  command "${bin:A}" --fork "$@"
}
```

Two shorthands come with it: `neo` (same thing) and `neok`, which also closes the terminal session it was launched from.

Why the real path: Homebrew's `/opt/homebrew/bin/neovide` is a symlink *into* the bundle, and exec'ing it never registers the process with LaunchServices — so app switchers ([`rcmd`](#rcmd)) can't see or focus the window. The real path registers it while still inheriting the shell's cwd and `PATH`.

`--fork` detaches the GUI (double-forked, so it survives the terminal closing) and returns the shell immediately. Two ways to silently break it:

- **Don't redirect stdout.** Neovide only forks when stdout is a tty, so `neovide --fork >/dev/null` becomes a blocking launch.
- **Don't background it** (`nohup … &`, `&!`). That orphans it to PPID 1, which Neovide reads as a Finder launch — it then runs nvim via `/usr/bin/login`, which chdirs to `$HOME`, losing your working directory. Let `--fork` do the detaching.

`open -a Neovide` registers too, but runs under launchd and inherits neither: it lands in `~`, and non-Homebrew LSPs/formatters (rust-analyzer, goimports) fall off `PATH`. `open -a Neovide .` fixes the directory at the cost of a directory buffer, which nvim-tree hijacks — see `GUIDE.md` → "Neovide".

Keymaps and runtime behavior (Cmd+C/V/S, zoom, jumplist keys, Force Click)
are documented in the nvim config's own reference:
`nvim/.config/nvim/GUIDE.md` → "Neovide".

## Typora

GUI markdown editor with live (WYSIWYG) rendering — handy for reading or heavy editing of `.md` files.

```bash
brew install --cask typora
```

Two ways to open a file in it:

- **Shell:** `typora notes.md` — alias for `open -a Typora` (in `.zshrc_config.zsh`).
- **Neovim:** `<leader>uo` (or `:Typora`) — documented in
  `nvim/.config/nvim/GUIDE.md` → Keymap index → Global keymaps.

## RustRover

JetBrains' Rust IDE — used for Rust work that benefits from a full IDE
(debugger, refactoring tools) beyond what nvim's LSP setup covers.

```bash
brew install --cask rustrover
```

No stow-managed config: IDE settings live in JetBrains' own config
directory, not this repo.

### Claude Code plugin

The [Claude Code plugin (beta)](https://plugins.jetbrains.com/plugin/27310-claude-code-beta-)
bridges RustRover to the `claude` CLI already installed via this repo's
Brewfile — `Cmd+Esc` quick launch, diffs shown in RustRover's own diff
viewer, current selection/open file and inspection diagnostics shared with
Claude automatically, `Cmd+Option+K` to insert `@file#L1-99` references.

```bash
rustrover installPlugins com.anthropic.code.plugin   # requires RustRover to be quit first
```

`com.anthropic.code.plugin` is the plugin's internal xmlId (not the
`27310` marketplace URL id — that one is rejected by `installPlugins`).
Restart RustRover after installing. Not stow-managed, same reasoning as
the rest of RustRover's config above.

## Ghostty

The **primary terminal** — GPU-accelerated and a native macOS app (real Cocoa
tabs and window management). Its whole config is one plain-text, stow-managed
file, so there is no binary export to import and no theme picker to run.

```bash
brew install --cask ghostty
cd ~/src/dotfiles
stow ghostty
```

Settings: **Hack Nerd Font Mono 14pt**, a 125×25 window, and a blinking bar
cursor. Option is sent as Meta on **both** left and right keys
(`macos-option-as-alt = true`), so nvim's `<M-...>` mappings work — and so do
the Option chords every agent CLI here relies on (Claude Code's `Option+P`
model switch, opencode's `Alt+B`/`Alt+F` word nav, `Option+Backspace`
everywhere). Tabs sit in the titlebar row next to the traffic
lights (`macos-titlebar-style = tabs`), and window layout is restored on every
relaunch (`window-save-state = always`) — see
[ghostty-followups.md](plans/ghostty-followups.md) §2.4/§2.8.

**The theme follows macOS on its own.** One line does it —

```ini
theme = light:Catppuccin Latte,dark:Dracula
```

— see [Unified theme switching](#unified-theme-switching): the `theme` script
only flips the macOS appearance, and Ghostty recolors every window, new and
already-open, by itself. Both themes are Ghostty built-ins; nothing is
vendored into this repo.

**Gotcha — stale app-support config shadows the stowed one.** If Ghostty ignores
`~/.config/ghostty/config` and shows the wrong theme, check for a legacy file at
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`. Delete it
and reload (`Cmd+Shift+,`).

### Keymaps

These are Ghostty's **macOS defaults**, so the config sets **no keybinds for
any of them**.

| Shortcut | Action |
|---|---|
| `Cmd+D` | Split right |
| `Cmd+Shift+D` | Split down |
| `Cmd+[` / `Cmd+]` | Focus previous / next split |
| `Cmd+Option+Arrow` | Focus the split in that direction |
| `Cmd+Ctrl+Arrow` | Resize the split in that direction |
| `Cmd+T` | New tab |
| `Cmd+W` | Close the current split/tab |
| `Cmd+1-8` | Jump to tab by number |
| `Cmd+9` | Jump to the **last** tab (not tab 9) |
| `Cmd+Shift+[` / `Cmd+Shift+]` | Previous / next tab |
| `Ctrl+Shift+Tab` / `Ctrl+Tab` | Previous / next tab (same actions, second binding) |
| `Cmd+Shift+,` | Reload the Ghostty config |

Either tab-cycling pair is safe alongside nvim. `Cmd+*` is never sent to the
TTY on macOS, so `Cmd+Shift+[`/`]` structurally can't reach nvim; `Ctrl+Tab`
and `Ctrl+Shift+Tab` are swallowed by Ghostty before the shell sees them, and
the only Tab-modifier mapping in this repo's nvim config is blink's insert-mode
`<S-Tab>` (`nvim/.config/nvim/lua/completion.lua`), a different key.

The config adds exactly **two** bindings — `Option+Backspace`, which sends the
legacy `ESC DEL` bytes so pi deletes a word backwards (under the kitty keyboard
protocol Ghostty otherwise reports the chord as a CSI u sequence pi doesn't
read), and `Cmd+Ctrl+T`, a system-wide show/hide toggle for every Ghostty
window (needs macOS Accessibility permission granted to Ghostty on first load).

There is deliberately **no** `Shift+Enter` binding. An earlier
`keybind = shift+enter=text:\n` (ported from the iTerm2 profile) swallowed the
chord and handed the app a bare linefeed, so pi and Claude Code could never see
Shift+Enter as a distinct key; both read it natively via CSI u, as does nvim's
terminal-mode `<S-CR>` map. Only re-add that mapping if you start using tmux.
Both rules come from [pi's terminal-setup
docs](https://pi.dev/docs/latest/terminal-setup).

**This table is mirrored into nvim's `<leader>sk` keymap picker**, as rows
scoped `ghostty` — since nvim always runs inside Ghostty, that's the quickest
place to look a chord up. The mirror lives in
`nvim/.config/nvim/lua/builtins.lua`; this table is canonical, so edit it first
and update those rows in the same change.

### Commands

| Command | Description |
|---|---|
| `ghostty +list-themes` | Browse the built-in themes |
| `ghostty +show-config` | Print the merged config — use it to check for parse errors |
| `ghostty +show-config --default` | Print every setting's default value |

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
curl -L https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh > ~/.antigen/antigen.zsh

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

<a id="prompt-starship"></a>
### Prompt (Starship)

The prompt is [Starship](https://starship.rs) — a single Rust binary. Config lives in `zsh/.config/starship.toml`; `stow zsh` links it to `~/.config/starship.toml` (Starship's default path, so no `STARSHIP_CONFIG` needed). `.zshrc_config.zsh` runs `eval "$(starship init zsh)"` behind a `command -v starship` guard, so if the binary is missing the shell prints a one-line hint instead of breaking.

```bash
brew install starship        # included in the Brewfile
```

Scope is deliberately lean — **directory + git only**, rendering `❯ <folder>(<branch>)`, e.g. `❯ dotfiles(main~)`:

- **`❯`** — green after a success, red after a non-zero exit.
- **folder** (`cyan`) — the cwd basename, like the old `%c`.
- **branch** (`purple`) — in parens, no glyph; `main`/`master` shown like any branch. Detached HEAD falls back to the short SHA.
- **dirty** (`red`) — a single `~` for any staged/unstaged/untracked change, via a `custom.git_dirty` module gated on `git status --porcelain` (one mark for all dirt, not Starship's per-category markers).

No language/tool version modules — the top-level `format` lists only these, so nothing else renders. Colors are ANSI palette **names**, not hex, so the prompt recolors when Ghostty flips light/dark (see [Unified theme switching](#unified-theme-switching)). Tweak it in `zsh/.config/starship.toml`.

<a id="directory-jumping-zoxide"></a>
### Directory jumping (zoxide)

`z <partial-dir>` jumps to the most "frecent" (frequency + recency) directory matching the term; `zi <partial-dir>` opens an fzf picker. This is provided by [zoxide](https://github.com/ajeetdsouza/zoxide), a Rust binary — **not** an antigen bundle. `.zshrc_config.zsh` initializes it after the plugins load:

```zsh
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
```

So the only per-machine step is `brew install zoxide` (included in the deps above). The database lives at `~/.local/share/zoxide/` and fills in as you `cd` around. zoxide replaced the old `antigen bundle z` line — oh-my-zsh ships no `z` plugin, so that bundle was a silent no-op.

### nvim-editor

`nvim-editor` is a small script (stowed to `~/.local/bin/nvim-editor`) set as `$EDITOR`, `$GIT_EDITOR`, and `$KUBE_EDITOR`. The script itself is just `exec nvim "$@"` — the routing lives in **flatten.nvim** inside the host editor:

- **Inside a toggleterm or nvim-spawned terminal** (`$NVIM` is set): flatten.nvim intercepts the child nvim and opens the buffer in the parent instance, blocking for `gitcommit`/`gitrebase` buffers so git waits for the edit (see GUIDE.md → Design Decisions → "Nested nvim routes into the parent").
- **Standalone terminal** (Ghostty, etc.): just a fresh `nvim` process.

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

Note: the shell **prompt** does not depend on any of this — it's [Starship](#prompt-starship), initialized in `.zshrc_config.zsh` behind a `command -v starship` guard, so it renders `<dir>(<branch>):` even if oh-my-zsh fails to load (and prints a hint if `starship` itself isn't installed). Restyle it in `~/.config/starship.toml`.

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

`gh`, the GitHub CLI (`brew "gh"` in the [`Brewfile`](Brewfile)), also needs a
one-time auth per machine:

```bash
gh auth login
```

Used by [Claude Squad](#claude-squad) (pushing session branches) and pi's
[pi-github-pr extension](#pi-extensions) (ambient PR status) — no extra scopes needed
beyond the defaults `gh auth login` grants.

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

The `docker` CLI talks to Colima's daemon automatically.

<a id="colima-default-config"></a>
### Default config (so `colima start` needs no flags)

Instead of passing flags every time, bake the defaults into a template that
Colima applies to any **newly created** profile. A plain `colima start` then
picks up the same CPU/memory/arch/vz config as the flag-laden `colima start`
commands above.

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

## macos

Stow package for machine-level macOS launchd agents. It currently holds the
theme-follow agent:

- `~/Library/LaunchAgents/com.dhruv.theme-follow.plist` — runs `theme watch`
  so Claude Code and Neovim follow macOS appearance changes.
- `macos/setup-theme-follow.sh` — loads the agent (`.stow-local-ignore`d, run
  from the repo).

```bash
cd ~/src/dotfiles
stow --no-folding macos
bash macos/setup-theme-follow.sh
```

The mechanics (why the agent exists, how `theme watch` works) are documented
in [Unified theme switching](#unified-theme-switching) → "Auto-follow on
macOS appearance changes" — this section is just the package-level setup.

## rcmd

App/window switcher driven by the Right Command key. Config (assignments, Stages, and settings) is a plain YAML file at `~/.config/rcmd/config.yaml`, managed via stow.

```bash
brew install --cask rcmd
cd ~/src/dotfiles
stow rcmd
```

The app reads `~/.config/rcmd/config.yaml` continuously and picks up edits within a few seconds — hand-edit it, or let rcmd's own settings UI write through the symlink. Run `rcmd config help` for the full settings reference. `~/.config/rcmd/search-cache.yaml` (learned query → app selections) is intentionally not tracked — it's a disposable cache, not a setting.

The `rcmd config …` CLI is bundled inside the app but isn't on `PATH` by default. The [`zsh`](#zsh) package exposes it by symlinking `~/.local/bin/rcmd` → `/Applications/rcmd.app/Contents/SharedSupport/rcmdCLI` (tracked as `zsh/.local/bin/rcmd`), so `rcmd config help` / `rcmd config get …` work from any shell once `rcmd.app` is installed. If the app isn't installed the symlink simply dangles — harmless.

## ripgrep

A stow-managed global ripgrep config at `~/.config/ripgrep/ripgreprc` (pointed to by `$RIPGREP_CONFIG_PATH`, exported in [`zsh`](#zsh)) that registers custom [file types](https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#file-types). It contains **only** `--type-add` definitions — no search-behavior flags — because the same file is read by every `rg` invocation, including the ones the Neovim snacks pickers shell out to.

```bash
cd ~/src/dotfiles
stow ripgrep
```

What it defines:

- **`rs`** — an alias for the built-in `rust` type, so `-trs` works like `-tgo` / `-tlua` / `-tpy` (ripgrep names the Rust type `rust`, not `rs`).
- **Per-language test types** — `gotest`, `rusttest`, `pytest`, `jstest`, `tstest`, `extest`, `kttest`, `luatest`, each matching that language's test-file naming, plus an umbrella **`test`** type unioning them all.

Use them anywhere `rg` runs — the shell, or a picker's ripgrep-args prompt:

```bash
rg -trs 'unwrap'            # search only Rust files
rg 'handleRequest' -Ttest  # everything except test files
rg 'TODO' -ttest           # only test files, any language
```

ripgrep type globs match the file *name* only, so directory conventions (Rust's `tests/`, Go's `testdata/`) and Rust's inline `#[cfg(test)]` unit tests aren't captured — see the comments in [`ripgrep/.config/ripgrep/ripgreprc`](ripgrep/.config/ripgrep/ripgreprc). List every type (built-in + custom) with `rg --type-list`.

New to ripgrep, or want to use it well? See the example-heavy guide at [`docs/ripgrep.md`](docs/ripgrep.md) — search basics, regex, file types (and defining your own), glob anchoring, and a task cookbook.

## Tabularis

**Under testing** — evaluating as a database GUI client. No config of its own;
the only tracked piece is a `PATH` shim in the [`zsh`](#zsh) package (see
[MCP integration](#mcp-integration) below).

```bash
brew tap TabularisDB/tabularis
brew install --cask tabularis
```

[Tauri/Rust](https://tabularis.dev) desktop client. PostgreSQL,
MySQL/MariaDB, and SQLite are built in; Redis and others (ClickHouse,
DuckDB, Firestore, …) ship as bundled plugins — no separate install.
SQL editor, data grid, notebooks, visual query builder/EXPLAIN, schema/ER
diagrams, an AI SQL assistant, SSH/Kubernetes tunneling, and an MCP server
mode. Credentials live in the OS keychain, not on disk.

### MCP integration

Tabularis ships its own MCP server — an AI client launches `tabularis --mcp`
directly (stdio JSON-RPC, no network port), so there's no separate service
to run.

The cask installs no `PATH` entry, so — as with [`rcmd`](#rcmd) — the
[`zsh`](#zsh) package symlinks `~/.local/bin/tabularis` →
`/Applications/tabularis.app/Contents/MacOS/tabularis` (tracked as
`zsh/.local/bin/tabularis`). That keeps the bundle path out of every client's
config; if the app isn't installed the symlink just dangles. Register it with
Claude Code once per machine:

```bash
stow zsh                                            # if not already stowed
claude mcp add --scope user tabularis tabularis -- --mcp
claude mcp list                                     # expect: tabularis ✔ Connected
```

`--scope user` writes to `~/.claude.json` (machine-local state, not tracked
here), so it's a per-machine step. Other clients can be pointed at the same
shim, or use Settings → MCP → Install Config to auto-patch them:

```json
{
  "mcpServers": {
    "tabularis": { "command": "tabularis", "args": ["--mcp"] }
  }
}
```

Clients that don't inherit a login shell's `PATH` (GUI apps launched from
Finder) need the full bundle path there instead.

Exposes read-only connection/schema resources plus `list_tables`,
`describe_table`, and `run_query` (capped at 100 rows) tools, with an audit
log, read-only mode, and approval gates as safety knobs. See
[tabularis.dev/wiki/mcp-server](https://tabularis.dev/wiki/mcp-server) for
more.

## viu

```bash
brew install viu
```

Terminal image viewer — no config, not a stow package. Renders images (PNG, JPEG, GIF, etc.) directly in terminals with graphics support, including Ghostty: `viu path/to/image.png`.

## yknotify

macOS daemon that watches the system log for YubiKey touch events and fires a
notification. Configured to skip FIDO2 (browser/WebAuthn) and only notify for
OpenPGP touches (GPG signing, SSH, sudo) with a 10-second cooldown.

The stow package places two files:

- `~/.local/bin/yknotify-watch` — wrapper that reads yknotify's NDJSON output and fires notifications
- `~/Library/LaunchAgents/com.dhruv.yknotify.plist` — runs the wrapper as a
  persistent background agent. Portable on purpose: it execs
  `"$HOME/.local/bin/yknotify-watch"` via `/bin/bash -c`, so no username is
  baked into the plist (same pattern as the theme-follow agent).

**One-time setup:**

```bash
go install github.com/noperator/yknotify@latest
brew install terminal-notifier   # already in the Brewfile
cd ~/src/dotfiles
stow --no-folding yknotify
bash yknotify/setup-yknotify.sh
```

The setup script bootstraps the agent into your GUI session (bootout +
bootstrap, idempotent — re-run after editing the plist), and also boots out
the legacy `com.user.yknotify` label if a machine still has the package's old
layout loaded. Logs land in `/tmp/yknotify.{out,err}.log`; if a required
binary is missing the watcher exits with a clear message there instead of
silently respawn-looping.

**Do Not Disturb / Focus mode:** notifications are sent via `terminal-notifier
-ignoreDnD`, but on macOS 14+ this flag alone is not enough to break through
Focus. You must also allowlist `terminal-notifier` explicitly:

> System Settings → Focus → Do Not Disturb → (i) → Apps → Add `terminal-notifier`

Without this, notifications are silently queued in Notification Center and
never shown as banners while Focus is active.
