#!/usr/bin/env bash
# Notify a running nvim instance that a YubiKey touch is needed,
# then delegate to the real pinentry-mac.

REAL_PINENTRY="/opt/homebrew/bin/pinentry-mac"

# nvim sets $NVIM in all child processes when running inside a terminal buffer.
NVIM_SOCKET="${NVIM:-}"

# Fallback: find the most recently modified nvim socket.
if [[ -z "$NVIM_SOCKET" ]]; then
  NVIM_SOCKET=$(ls -t /tmp/nvim.*/0 2>/dev/null | head -1)
fi

if [[ -n "$NVIM_SOCKET" ]]; then
  nvim --server "$NVIM_SOCKET" --remote-expr \
    "luaeval(\"vim.notify('Touch YubiKey ↯', vim.log.levels.WARN)\")" 2>/dev/null || true
fi

exec "$REAL_PINENTRY" "$@"
