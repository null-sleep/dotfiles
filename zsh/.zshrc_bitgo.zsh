# BitGo-specific shell configuration
# Sourced conditionally from .zshrc_config.zsh

## AWS / Claude env vars
# export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=us-west-2
export AWS_PROFILE=dev

## Go Private modules
export GOPRIVATE=github.com/lumina-tech/*,github.com/bitgo/*

## Git base branch override (BitGo uses master)
export GIT_BASE_BRANCH="master"

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

colima_check_and_start

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

## BG Admin
alias bga='/Users/dhruvjauhar/src/bitgo-admin/bin/bgadmin'

## Atlas
eval "$(atlas init zsh)"
