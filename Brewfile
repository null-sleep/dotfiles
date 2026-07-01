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
brew "fzf"             # fuzzy finder (zsh keybindings + nvim telescope)
brew "ripgrep"         # rg — telescope live-grep
brew "fd"              # fast find — telescope file finding
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
# brew "elixir"        # runtime for the elixir-ls LSP (includes Erlang)
