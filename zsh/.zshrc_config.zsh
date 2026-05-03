if [[ -f ~/.antigen/antigen.zsh ]]; then
  # Set OMZ paths explicitly before antigen runs so they get baked correctly
  # into ~/.antigen/init.zsh. Otherwise antigen can cache empty values, which
  # breaks plugins like docker (writes completions to /completions/_docker)
  # and the robbyrussell theme (prompt_subst never gets enabled).
  export ZSH="$HOME/.antigen/bundles/robbyrussell/oh-my-zsh"
  export ZSH_CACHE_DIR="$ZSH/cache"
  mkdir -p "$ZSH_CACHE_DIR/completions"

  source ~/.antigen/antigen.zsh

  antigen use oh-my-zsh

  # Prefix a command with sudo by double-tapping ESC
  # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/sudo
  # antigen bundle sudo

  antigen bundle z
  antigen bundle git
  antigen bundle brew
  antigen bundle macos
  antigen bundle mise
  antigen bundle iterm2
  antigen bundle themes
  antigen bundle docker
  antigen bundle podman
  antigen bundle kubectl
  antigen bundle command-not-found
  antigen bundle zsh-users/zsh-autosuggestions

  # Syntax highlighting must be loaded after all other plugins (especially
  # zsh-autosuggestions) so it can wrap their widgets correctly.
  antigen bundle zsh-users/zsh-syntax-highlighting

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

# Raise open file descriptor limit if below 10240 (some older macOS defaults to 256)
[[ $(ulimit -n) -lt 10240 ]] && ulimit -n 10240

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
    # Default to nvim for all other terminals (GoLand, iTerm, etc.).
    # nvim-editor reuses the existing nvim instance when $NVIM is set (i.e.
    # inside a toggleterm or any nvim-spawned terminal), falling back to a
    # fresh nvim process otherwise. --remote-wait blocks until the buffer is
    # closed, which is required for git commit, kubectl edit, etc.
    export EDITOR="nvim-editor"
    export GIT_EDITOR="nvim-editor"
    export KUBE_EDITOR="nvim-editor"
fi

# FZF
command -v fzf >/dev/null && source <(fzf --zsh)


# Git

## Dynamically detect the default branch (main/master) from the remote.
## Fast path uses local ref; slow path hits the network. Run
## `git remote set-head origin --auto` once per clone to populate the local ref.
git_base_branch() {
  local branch
  branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  if [[ -n "$branch" ]]; then
    echo "$branch"
    return
  fi
  echo "warning: refs/remotes/origin/HEAD not set — run 'git remote set-head origin --auto'" >&2
  git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}' \
    || echo "main"
}

## Git Aliases
alias g=git
alias gt=git
alias ga='git add'
alias gcmp='git checkout $(git_base_branch) && git pull'
alias gcb='git checkout $(git branch | fzf)'
alias gbd='git branch | grep -v "^\*" | grep -vE "^\s*(master|main|hotfix)\s*$" | fzf -m | xargs git branch -D'
alias gdm='git diff $(git_base_branch)...'
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
alias grb='git fetch origin && git rebase origin/$(git_base_branch)'
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

# Show diff of only the Nth commit (default: last commit)
gdn() {
  local n="${1:-1}"
  git diff HEAD~$n HEAD~$(($n - 1))
}

# Switch to a git worktree via fzf
gw() {
  local target
  target=$(git worktree list | fzf --prompt="worktree> " | awk '{print $1}')
  [[ -n "$target" ]] && cd "$target"
}

# Claude Alias
alias c=claude

# Make a basic function called disable_dock_bounce
fix_dock() {
  defaults write com.apple.dock no-bouncing -bool TRUE
  defaults write com.apple.systempreferences AttentionPrefBundleIDs 0
  killall Dock
}

# GO environment
# GO111MODULE=on
export GOPATH=$HOME/go
export PATH="$PATH:$GOPATH/bin"

# Source company-specific config if present
[[ -f ~/.zshrc_work.zsh ]] && source ~/.zshrc_work.zsh
[[ -f ~/.zshrc_shared.zsh ]] && source ~/.zshrc_shared.zsh
