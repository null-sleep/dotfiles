if [[ -f ~/.antigen/antigen.zsh ]]; then
  source ~/.antigen/antigen.zsh

  antigen use oh-my-zsh

  # Install autocompletion for ripgrep
  # https://github.com/odefault_bundhmyzsh/ohmyzsh/tree/master/plugins/ripgrep
  antigen bundle ripgrep

  # Prefix a command with sudo by double-tapping ESC
  # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/sudo
  # antigen bundle sudo

  # Syntax highlighting on the prompt as you type commands
  antigen bundle zsh-users/zsh-syntax-highlighting

  antigen bundle z
  antigen bundle git
  antigen bundle brew
  antigen bundle macos
  antigen bundle iterm2
  antigen bundle themes
  antigen bundle docker
  antigen bundle podman
  antigen bundle kubectl
  antigen bundle command-not-found
  antigen bundle zsh-users/zsh-autosuggestions

  # Theme
  ZSH_THEME="robbyrussell"
  antigen theme robbyrussell

  # Antigen configuration ends
  antigen apply

  # Remove git alias set by oh-my-zsh git plugin to allow git function definitions
  unalias git 2>/dev/null
else
  echo "Antigen not found. Run: mkdir -p ~/.antigen && curl -L git.io/antigen > ~/.antigen/antigen.zsh"
fi

# antigen bundle ptavares/zsh-direnv
[[ -f ~/.zsh-direnv/zsh-direnv.plugin.zsh ]] && source ~/.zsh-direnv/zsh-direnv.plugin.zsh

# Set limit on the number of open file descriptors
ulimit -n 1024

# Enable alias expansion in completions by pressing tab
zstyle ':completion:*' completer _expand_alias _complete _ignored

# Path Updates
export PATH="$HOME/.local/bin:$PATH"
# Homebrew: Apple Silicon uses /opt/homebrew, Intel uses /usr/local (already in PATH by default)
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"
# Rust
export PATH="$HOME/.cargo/bin:$PATH"

# Open configs
alias zshrc="nvim ~/.zshrc"
alias zshconf="nvim ~/.zshrc_config.zsh"

# Editor
alias vim=nvim
alias vi=nvim

# Set editor based on terminal context
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    # Distinguish between Cursor and VS Code
    if [[ -n "$CURSOR_TRACE_ID" ]]; then
        export EDITOR="cursor -w"
        export GIT_EDITOR="cursor -w"
        export KUBE_EDITOR="cursor -w"
    else
        export EDITOR="code -w"
        export GIT_EDITOR="code -w"
        export KUBE_EDITOR="code -w"
    fi
else
    # Default to nvim for all other terminals (GoLand, iTerm, etc.)
    export EDITOR="nvim"
    export GIT_EDITOR="nvim"
    export KUBE_EDITOR="nvim"
fi

# FZF
source <(fzf --zsh)


# Git

export GIT_BASE_BRANCH="main"

## Git Aliases
alias g=git
alias gt=git
alias ga='git add'
alias gcmp='git checkout $GIT_BASE_BRANCH && git pull'
alias gcb='git checkout $(git branch | fzf)'
alias gbd='git branch | grep -v "^\*" | grep -vE "^\s*(master|main|hotfix)\s*$" | fzf -m | xargs git branch -D'
alias gdm='git diff $GIT_BASE_BRANCH...'
alias gs='git status'
alias gl='git log'
alias glg='git log --oneline --graph --decorate --all'
alias gpf='git push --force-with-lease'
alias gc='git commit'
alias gca='git commit --amend'
# alias gca='git commit --amend --no-edit'
alias gco='git checkout'
alias gcaa='git commit -a --amend --no-edit'
alias gaa='git add --all'
alias gau='git add -u' # Add only tracked files
alias yolo='gcaa && gpf'
alias gnb='git checkout -b'
alias grb='git fetch origin &&  git rebase origin/$GIT_BASE_BRANCH'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'

# Git Functions

# Remove alias from `antigen bundle git` if it exists to allow function definition
unalias gd 2>/dev/null
# Show git diff for last n commits, default 1
gd() {
  if [ -z "$1" ]; then
    git diff
  else
    git diff HEAD~$1
  fi
}

# Remove alias from `antigen bundle git` if it exists to allow function definition
unalias gds 2>/dev/null
# Show git diff (including staged changes) for last n commits, default 1
gds() {
  if [ -z "$1" ]; then
    git diff --staged
  else
    git diff --staged HEAD~$1
  fi
}

# Claude Alias
alias c=claude

# Make a basic function called disable_dock_bounce
fix_dock() {
  defaults write com.apple.dock no-bouncing -bool TRUE
  defaults write com.apple.systempreferences AttentionPrefBundleIDs 0
  killall Dock
}

# Create cache and completions dir and add to $fpath
if [[ -n "$ZSH_CACHE_DIR" ]]; then
  mkdir -p "$ZSH_CACHE_DIR/completions"
  (( ${fpath[(Ie)"$ZSH_CACHE_DIR/completions"]} )) || fpath=("$ZSH_CACHE_DIR/completions" $fpath)
fi

# GO environment
# GO111MODULE=on
export GOPATH=$HOME/go
export PATH=$PATH:$(go env GOPATH)/bin

# Source company-specific config if present
[[ -f ~/.zshrc_bitgo.zsh ]] && source ~/.zshrc_bitgo.zsh
