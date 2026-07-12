if [[ -f ~/.antigen/antigen.zsh ]]; then
  # Export OMZ paths before antigen runs so they get baked correctly into
  # ~/.antigen/init.zsh (otherwise antigen can cache empty values, breaking
  # plugins like docker that write completions to /completions/_docker).
  # IMPORTANT: only export here — do NOT `mkdir` the cache dir yet. Creating
  # $ZSH before antigen clones oh-my-zsh makes antigen's directory-existence
  # check think OMZ is "already cloned" and silently skip the clone, leaving an
  # empty bundle (no theme, no plugins). The mkdir is deferred to after
  # `antigen apply` below, once OMZ actually exists on disk.
  export ZSH="$HOME/.antigen/bundles/robbyrussell/oh-my-zsh"
  export ZSH_CACHE_DIR="$ZSH/cache"

  # oh-my-zsh core (lib/termsupport.zsh) auto-titles the tab/window on every
  # precmd/preexec (job name, then "%~"), fighting our own auto/override
  # `title` below — which redefines the `title` function these hooks call.
  # Without this, every prompt or command re-triggers the (now-ours) `title`
  # with omz's args, stomping our override. The hooks stay registered but
  # no-op once this is set.
  export DISABLE_AUTO_TITLE=true

  source ~/.antigen/antigen.zsh

  antigen use oh-my-zsh

  # Prefix a command with sudo by double-tapping ESC
  # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/sudo
  # antigen bundle sudo

  # Directory-jump (`z`/`zi`) is provided by zoxide, a binary initialized
  # below after antigen — not an antigen bundle. oh-my-zsh ships no `z` plugin.
  antigen bundle git
  antigen bundle brew
  antigen bundle macos
  antigen bundle mise
  antigen bundle iterm2
  antigen bundle docker
  antigen bundle podman
  antigen bundle kubectl
  antigen bundle command-not-found
  antigen bundle zsh-users/zsh-autosuggestions

  # Syntax highlighting must be loaded after all other plugins (especially
  # zsh-autosuggestions) so it can wrap their widgets correctly.
  antigen bundle zsh-users/zsh-syntax-highlighting

  # Prompt is defined below (see "Prompt"), self-contained and independent of
  # oh-my-zsh themes — so it renders even when OMZ/antigen state is broken.

  # Antigen configuration ends
  antigen apply

  # oh-my-zsh is cloned now — safe to create its completions cache dir (some
  # plugins, e.g. docker, write completions here). Deferred until after apply so
  # it can't pre-create $ZSH and sabotage antigen's clone (see IMPORTANT above).
  mkdir -p "$ZSH_CACHE_DIR/completions"
else
  echo "Antigen not found. Run: mkdir -p ~/.antigen && curl -L https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh > ~/.antigen/antigen.zsh"
fi

#------------------------------------------------------------------------------
# Prompt — self-contained, no oh-my-zsh theme dependency.
# Renders like:  ➜  <dir> git:(<branch>) ✗
#   • arrow: green on success, red after a non-zero exit  ( %(?...) )
#   • %c:    basename of the current directory
#   • git:   branch (or short SHA when detached) plus a ✗ when the worktree is
#            dirty — staged, unstaged, OR untracked (matches robbyrussell)
# Colours below are ANSI *names* (not RGB), so they follow the terminal's active
# colour scheme (iTerm2 profile / .itermcolors) rather than being hardcoded —
# switch themes and the prompt recolours. `command git` sidesteps the git
# aliases/functions defined later; %F{} escapes need no oh-my-zsh colour lib.
#------------------------------------------------------------------------------
setopt PROMPT_SUBST

# Prompt palette — recolour the whole prompt by editing these in one place.
PROMPT_COLOR_OK=green       # arrow — last command succeeded
PROMPT_COLOR_ERR=red        # arrow — last command failed
PROMPT_COLOR_DIR=cyan       # current directory
PROMPT_COLOR_GIT=blue       # git:( … ) wrapper
PROMPT_COLOR_BRANCH=red     # branch name / short SHA
PROMPT_COLOR_DIRTY=yellow   # ✗ dirty marker

_zsh_git_prompt() {
  local ref
  ref=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) \
    || ref=$(command git rev-parse --short HEAD 2>/dev/null) \
    || return 0
  # Dirty = any staged, unstaged, or untracked change (git status --porcelain),
  # matching robbyrussell's default dirty semantics.
  local dirty=''
  [[ -n $(command git status --porcelain --ignore-submodules 2>/dev/null) ]] \
    && dirty=" %F{$PROMPT_COLOR_DIRTY}✗%f"
  print -rn -- " %F{$PROMPT_COLOR_GIT}git:(%F{$PROMPT_COLOR_BRANCH}${ref}%F{$PROMPT_COLOR_GIT})%f${dirty}"
}

PROMPT='%(?:%F{$PROMPT_COLOR_OK}➜:%F{$PROMPT_COLOR_ERR}➜)%f  %F{$PROMPT_COLOR_DIR}%c%f$(_zsh_git_prompt) '

#------------------------------------------------------------------------------
# Window/tab title (iTerm2) — defaults to the project name (git toplevel,
# else cwd basename), manually overridable with `title <name>`; bare `title`
# reverts to automatic. Mirrors nvim's own auto/override :Title (see
# nvim/.config/nvim/lua/titling.lua) so shell and editor titles agree — nvim
# inherits whatever title escape codes are already in the terminal on launch
# and restores them on exit, so the two never fight over the tab title.
#------------------------------------------------------------------------------
typeset -g _TITLE_OVERRIDE=

_set_term_title() {
  # \e]1;...\a sets the tab title, \e]2;...\a the window title — set both so
  # neither is left showing the old value.
  print -Pn "\e]1;$1\a\e]2;$1\a"
}

_auto_title() {
  local root
  root=$(command git rev-parse --show-toplevel 2>/dev/null)
  [[ -n "$root" ]] && print -rn -- "${root:t}" || print -rn -- "${PWD:t}"
}

_update_term_title() {
  _set_term_title "${_TITLE_OVERRIDE:-$(_auto_title)}"
}

title() {
  _TITLE_OVERRIDE="$*"
  _update_term_title
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _update_term_title
_update_term_title

# antigen bundle ptavares/zsh-direnv
[[ -f ~/.zsh-direnv/zsh-direnv.plugin.zsh ]] && source ~/.zsh-direnv/zsh-direnv.plugin.zsh

# Raise open file descriptor limit if below 10240 (some older macOS defaults
# to 256). The `unlimited` guard matters: in zsh arithmetic the bare word
# resolves as a (zero-valued) variable, so without it `unlimited < 10240`
# would be "true" and we'd LOWER the limit.
_nofile=$(ulimit -n)
[[ $_nofile != unlimited && $_nofile -lt 10240 ]] && ulimit -n 10240
unset _nofile

# Enable alias expansion in completions by pressing tab
zstyle ':completion:*' completer _expand_alias _complete _ignored

# Path Updates — last prepend wins, so ~/.local/bin stays at the END of this
# block: user-local scripts (theme, claude-nvim, nvim-editor) must shadow any
# same-named homebrew/cargo binary, not the other way around.
# Homebrew: Apple Silicon uses /opt/homebrew, Intel uses /usr/local (already in PATH by default)
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"
# Prefer Homebrew's python@3.12 (unversioned python3/pip3) over macOS's outdated
# system python3 (3.9). brew installs it keg-only, exposing the unversioned
# binaries here. Guarded so it's a harmless no-op where the formula isn't present.
[[ -d /opt/homebrew/opt/python@3.12/libexec/bin ]] && export PATH="/opt/homebrew/opt/python@3.12/libexec/bin:$PATH"
# Rust
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Open configs
alias zshrc="nvim ~/.zshrc"
alias zshconf="nvim ~/.zshrc_config.zsh"

# Editor
alias vim=nvim
alias vi=nvim
# Run the bundle's real executable, not the Homebrew shim that symlinks into it: a
# symlinked exec never registers with LaunchServices, so rcmd can't see the window.
# whence -p skips this function; :A resolves the symlink.
#
# --fork detaches (double-forks, survives the terminal closing). Do NOT redirect its
# stdout: Neovide gates forking on `is_tty()`, so `>/dev/null` silently turns --fork
# into a blocking launch. Don't background it with nohup/`&!` either — that orphans it
# to PPID 1, which Neovide's macOS heuristic reads as a Finder launch and routes nvim
# through `/usr/bin/login`, landing you in $HOME instead of the cwd.
neovide() {
  local bin=$(whence -p neovide)
  command "${bin:A}" --fork "$@"
}
alias neo=neovide
# Same, but close the calling terminal session afterwards.
neok() {
  neovide "$@" && exit
}
# Typora — open a markdown file in the Typora app
alias typora="open -a Typora"
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
    # nvim-editor is a plain `exec nvim "$@"` shim — the reuse-the-parent
    # behavior lives in flatten.nvim inside the HOST nvim: when $EDITOR runs
    # in an nvim-owned terminal, flatten intercepts the child and opens the
    # buffer in the parent instead, blocking for gitcommit/gitrebase so git
    # waits for :w. Standalone shells just get a normal nvim.
    export EDITOR="nvim-editor"
    export GIT_EDITOR="nvim-editor"
    export KUBE_EDITOR="nvim-editor"
fi

# FZF
command -v fzf >/dev/null && source <(fzf --zsh)

# zoxide — smarter `cd`. Provides `z <partial>` (jump by frecency) and `zi`
# (interactive fzf pick). Must init after plugins/compinit. `brew install zoxide`.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# ripgrep — point rg at the stow-managed global config, which registers custom
# file types (e.g. `-trs` for Rust, and per-language `-Ttest` test-file
# exclusions). Also picked up by the snacks nvim pickers, since
# they shell out to rg. Guarded on the file existing so an unstowed `ripgrep`
# package doesn't make every rg call warn about a missing config.
# See ripgrep/.config/ripgrep/ripgreprc.
[[ -f "$HOME/.config/ripgrep/ripgreprc" ]] \
  && export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/ripgreprc"


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

# Delete all local branches that have been merged into the current branch.
# Safe by default: skips trunk branches, the current branch, and any branch
# checked out in another worktree (git branch -d would error on those anyway).
# Uses -d (not -D) so unmerged branches are always refused.
gclean() {
  # Branches checked out in any worktree — deleting these would error.
  local worktree_branches
  worktree_branches=$(git worktree list --porcelain \
    | awk '/^branch / { sub("refs/heads/", "", $2); print $2 }')

  git branch --merged \
    | grep -v '^\*' \
    | grep -vE '^\s*(master|main|hotfix)\s*$' \
    | sed 's/^[[:space:]]*//' \
    | grep -Fxv "$worktree_branches" \
    | xargs -r git branch -d
}

## Git Aliases
alias g=git
alias gt=git  # NOTE: shadows the Graphite CLI's `gt` — remove this line if you adopt Graphite
alias ga='git add'
alias gcmp='git checkout $(git_base_branch) && git pull'
alias gcb='git checkout $(git branch | fzf)'
alias gbd='git branch | grep -v "^\*" | grep -vE "^\s*(master|main|hotfix)\s*$" | fzf -m | xargs git branch -D'
alias gdm='git diff $(git_base_branch)...'
alias gs='git status'
alias gl='git log'
alias glg='git log --oneline --graph --decorate --all'
# gp = push (with push.autoSetupRemote + remote.pushDefault=origin from
# ~/.gitconfig, plain `git push` sets upstream automatically). gu = pull.
alias gp='git push'
alias gu='git pull'
gcop() { git checkout "$1" && git pull; }
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

# Keep the laptop awake while plugged in (-s only applies on AC power).
# Runs in the foreground; Ctrl-C to release.
awake() {
  echo "Keeping the laptop awake (display, idle, disk, system-on-AC, user-active)."
  echo "Press Ctrl-C to stop."
  caffeinate -dimsu
}

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
