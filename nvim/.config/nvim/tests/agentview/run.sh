#!/usr/bin/env bash
# Agent-view regression suite. Runnable from any cwd:
#   nvim/.config/nvim/tests/agentview/run.sh
# `env -u NVIM` is mandatory in this config — flatten.nvim would otherwise
# route a bare `nvim` into the live instance and the suite would never run
# standalone (see the nested CLAUDE.md).
set -uo pipefail
cd "$(dirname "$0")" || exit 1

# Suites are self-contained (-l, stubbed deps) unless they need the real
# lualine/ai/themes, which only exist under the full config (-c luafile).
declare -a STANDALONE=(events notify view)
declare -a FULL_CONFIG=(badge)

fails=0
run() {
  local name=$1
  shift
  if ! env -u NVIM nvim --headless "$@"; then
    echo "  ${name}: SUITE ERRORED"
    fails=$((fails + 1))
  fi
}

for s in "${STANDALONE[@]}"; do run "$s" -l "$s.lua"; done
for s in "${FULL_CONFIG[@]}"; do run "$s" -c "luafile $s.lua"; done

if [ "$fails" -ne 0 ]; then
  echo "agentview: $fails suite(s) failed"
  exit 1
fi
echo 'agentview: all suites passed'
