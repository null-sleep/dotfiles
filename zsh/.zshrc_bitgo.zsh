# BitGo-specific shell configuration
# Sourced conditionally from .zshrc_config.zsh

## AWS / Claude env vars
# export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=us-west-2
export AWS_PROFILE=dev
export CLAUDE_STATUSLINE_MODE=cost

## Go Private modules
export GOPRIVATE=github.com/lumina-tech/*,github.com/bitgo/*

# Disable Harness docs generation
export ENABLE_HARNESS_DOCS=0

## Colima (Docker runtime)
colima_start() {
  colima start --cpu 8 --memory 8 --arch aarch64 --vm-type=vz --vz-rosetta
}

colima_check_and_start() {
  if ! colima list 2>/dev/null | grep -q 'Running'; then
    echo "ATTENTION: Colima is not running!!!"
    echo "Please run \`colima_start\` to start it"
  fi
}

## Kill all MCP Chrome instances (grafana, redash, etc.)
kill-mcp-chrome() {
  local pids
  pids=(${(f)"$(pgrep -f 'user-data-dir=/Users/'"$USER"'/\.[^"]*_mcp_chrome')"})
  if [[ ${#pids} -eq 0 ]]; then
    echo "No MCP Chrome instances found."
    return 0
  fi
  echo "Killing MCP Chrome instances (PIDs: ${pids[*]})"
  kill "${pids[@]}"
}

## yknotify (YubiKey touch notifier)
yknotify_check() {
  if ! launchctl list com.dhruv.yknotify &>/dev/null; then
    echo "ATTENTION: yknotify LaunchAgent is not loaded!"
    echo "Run: bash ~/src/dotfiles/yknotify/setup-yknotify.sh"
  fi
}

# Run the colima/yknotify checks once per boot, not on every shell startup —
# `colima list` alone costs a few hundred ms per new tab/pane. macOS clears
# /tmp at boot (and periodically after ~3 days, which just re-runs the check
# occasionally — fine). The functions stay defined for manual use.
_bitgo_checks_stamp="/tmp/.bitgo-shell-checks-$UID"
if [[ ! -e $_bitgo_checks_stamp ]]; then
  colima_check_and_start
  yknotify_check
  touch "$_bitgo_checks_stamp"
fi
unset _bitgo_checks_stamp

## BG Admin
alias bga='$HOME/src/bitgo-admin/bin/bgadmin'

## Run evals
command -v atlas >/dev/null && eval "$(atlas init zsh)"
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
