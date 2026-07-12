# Brewfile — Homebrew manifest for this dotfiles setup.
#
# Install everything below in one shot:
#     cd ~/src/dotfiles && brew bundle
#
# `brew bundle` is idempotent: it skips anything already installed, so it is
# safe to re-run after editing this file. `brew bundle check` reports what is
# missing without installing. The per-section `brew install …` commands in
# README.md remain as documentation of *why* each tool is here.
#
# NOT covered here (installed by other means — see README):
#   • rustup / cargo subcommands  — curl + `cargo install` (Languages section)
#   • antigen, zsh-direnv         — curl + git clone (ZSH section)
#   • nvim LSP servers/formatters — Mason, inside nvim (Languages section)

#-----------------------------------------------------------------------------
# Taps
#-----------------------------------------------------------------------------
tap "delphinus/sfmono-square", trusted: true   # SF Mono Square font. `trusted: true`
                                               # lets `brew bundle` install from this
                                               # third-party tap without a separate
                                               # `brew trust` (newer Homebrew gates these).

#-----------------------------------------------------------------------------
# Core CLI — shell, search, dotfiles management
#-----------------------------------------------------------------------------
brew "stow"            # symlink dotfiles into $HOME
brew "git"
brew "gh"              # GitHub CLI
brew "fzf"             # fuzzy finder (zsh keybindings)
brew "ripgrep"         # rg — nvim snacks picker live-grep
brew "fd"              # fast find — nvim snacks picker file finding
brew "zoxide"          # z / zi directory jumping
brew "direnv"          # per-directory environment
brew "coreutils"       # provides gtimeout, used by claude-nvim
brew "jq"              # used by claude/setup-*.sh (macOS 15+ ships one too)

#-----------------------------------------------------------------------------
# Editor — Neovim + build tooling
#-----------------------------------------------------------------------------
brew "neovim"
brew "tree-sitter-cli" # builds treesitter parsers
# LSP servers, formatters, and linters are installed by Mason inside nvim.

#-----------------------------------------------------------------------------
# Language runtimes — needed by nvim LSP/treesitter.
# Install these BEFORE first launching nvim, or Mason's installs fail (ENOENT).
#-----------------------------------------------------------------------------
brew "go"
brew "node"
brew "python@3.12"     # keg-only; .zshrc_config.zsh prepends it to PATH
brew "elixir"          # runtime for elixirls (lsp.lua ensure_installed) — Mason's
                       # install fails on every launch without it; includes Erlang
brew "ruff"            # python format-on-save (README → "Format-on-save tools");
                       # Mason installs a separate copy for nvim — this one is for
                       # shell/pre-commit use

#-----------------------------------------------------------------------------
# Claude Code LSP servers — needed on PATH by Claude Code's LSP plugins (see
# README → "Claude Code"). These are SEPARATE from nvim's Mason copies, which
# live in ~/.local/share/nvim/mason/bin (NOT on PATH). Only lua fits the brew
# idiom; the other three install via their language toolchains:
#   pyright        npm install -g pyright                       (needs node, above)
#   gopls          go install golang.org/x/tools/gopls@latest   (needs go, above)
#   rust-analyzer  rustup component add rust-analyzer           (Languages section)
#-----------------------------------------------------------------------------
brew "lua-language-server"

#-----------------------------------------------------------------------------
# Claude Code CLI. The @latest cask tracks newer builds than the stable
# `claude-code` cask (which can lag behind by several releases). `claude update`
# is a no-op on the @latest cask; run `brew upgrade --cask claude-code@latest`.
#-----------------------------------------------------------------------------
cask "claude-code@latest"

#-----------------------------------------------------------------------------
# Claude Code token optimizer — rtk (Rust Token Killer) compresses Bash command
# output before it hits the context window via a PreToolUse hook. Enable with
# `rtk init -g --auto-patch` after install (see README → "Claude Code").
#-----------------------------------------------------------------------------
brew "rtk"

#-----------------------------------------------------------------------------
# Fonts
#-----------------------------------------------------------------------------
cask "font-hack-nerd-font"
brew "delphinus/sfmono-square/sfmono-square"  # formula: symlink its .otf into
                                              # ~/Library/Fonts (see Fonts section)

#-----------------------------------------------------------------------------
# GUI apps
#-----------------------------------------------------------------------------
cask "neovide-app"     # Neovim GUI
cask "typora"          # markdown editor (`typora` shell alias)
cask "signal"
cask "vlc"             # media player
cask "rcmd"            # app/window switcher; config in rcmd/  (then `stow rcmd`)

#-----------------------------------------------------------------------------
# Utilities
#-----------------------------------------------------------------------------
brew "terminal-notifier"  # macOS notification helper; used by yknotify (YubiKey touch alerts)
brew "watch"              # repeat a command and watch output (not in macOS base);
                          # e.g. watching `ps` for the nvim claude pre-warm spawn

#-----------------------------------------------------------------------------
# Containers — Docker Desktop alternative (comment out if you don't use Docker)
#-----------------------------------------------------------------------------
brew "colima"
brew "docker"

#-----------------------------------------------------------------------------
# Optional / situational — uncomment per machine as needed. The configs for
# these live in the repo and are stowed only if you opt in (see Setup).
#-----------------------------------------------------------------------------
# cask "iterm2"        # terminal (if not already installed); profiles imported in iterm2/
# cask "kitty"         # GPU-accelerated terminal; config in kitty/  (then `stow kitty`)
# brew "zellij"        # terminal multiplexer; config in zellij/     (then `stow zellij`)
# brew "tmux"          # required by claude-squad
# brew "claude-squad"  # `cs` AI session manager — plain core formula, no tap (see Claude Squad section)
# brew "gnupg"         # GPG commit signing via YubiKey (README → "GPG commit signing")
# brew "pinentry-mac"  # pinentry the YubiKey touch-notify wrapper delegates to
#                      # (nvim/.config/nvim/scripts/pinentry-yubikey-notify.sh)
