source /Users/dhruvjauhar/antigen.zsh

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

# antigen bundle ptavares/zsh-direnv
source ~/.zsh-direnv/zsh-direnv.plugin.zsh

# Theme
ZSH_THEME="robbyrussell"
antigen theme robbyrussell

# Antigen configuration ends
antigen apply

# Set limit on the number of open file descriptors
ulimit -n 1024

# Enable alias expansion in completions by pressing tab
zstyle ':completion:*' completer _expand_alias _complete _ignored


# Kubectl
# alias k=kubectl
# autoload -Uz compinit
# compinit
# # cloudplatform: add Shopify clusters to your local kubernetes config
# export KUBECONFIG=${KUBECONFIG:+$KUBECONFIG:}/Users/dhruv/.kube/config:/Users/dhruv/.kube/config.shopify.cloudplatform
# for file in /Users/dhruv/src/github.com/Shopify/cloudplatform/workflow-utils/*.bash; do source ${file}; done
# kubectl-short-aliases
# source <(kubectl completion zsh)
# compdef __start_kubectl k

# Path Updates
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

## Claude env vars
# export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=us-west-2
export AWS_PROFILE=dev

## Go Private
export GOPRIVATE=github.com/lumina-tech/*,github.com/bitgo/*

# Open configs
alias zshrc="cursor ~/.zshrc"
alias zshconf="cursor ~/.zshrc_config.zsh"

# Editor
alias vim=nvim

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

export GIT_BASE_BRANCH="master" # "main"

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
GOPRIVATE=github.com/lumina-tech/*,github.com/bitgo/*

# Colima
colima_start() {
  colima start --cpu 8 --memory 8 --arch aarch64 --vm-type=vz --vz-rosetta
}

colima_check_and_start() {
  if ! colima status 2>&1 | grep -q 'colima is running'; then
    echo "ATTENTION: Colima is not running!!!"
    echo "Please run `colima_start` to start it"
  fi
}

colima_check_and_start

# Supress output and run in background example 
# (&>/dev/null colima_check_and_start &)

# Kill Grafana MCP chrome instance
kill-grafana-chrome() {
  local pids
  pids=(${(f)"$(pgrep -f 'user-data-dir=/Users/'"$USER"'/.grafana_mcp_chrome')"})
  if [[ ${#pids} -eq 0 ]]; then
    echo "No grafana-mcp Chrome instance found."
    return 0
  fi
  echo "Killing grafana-mcp Chrome (PIDs: ${pids[*]})"
  kill "${pids[@]}"
}

# BG Admin
alias bga='/Users/dhruvjauhar/src/bitgo-admin/bin/bgadmin'

# Evals

eval "$(direnv hook zsh)"
eval "$(atlas init zsh)"
