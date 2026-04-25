# Halp-specific shell configuration
# Sourced conditionally from .zshrc_config.zsh

# mise: per-project tool versions (elixir, python, node, …)
# Activates mise's shims directory on $PATH and installs a chpwd hook that
# loads [env] blocks from .mise.toml as you cd into worktrees.
command -v mise >/dev/null && eval "$(mise activate zsh)"
