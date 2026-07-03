-- GPG signing watcher: fires a "Signed ✓" notification after a gitcommit
-- buffer is confirmed. The "Touch YubiKey ↯" prompt is shown by the pinentry
-- wrapper script (scripts/pinentry-yubikey-notify.sh) via nvim --server RPC.

local M = {}

-- Call immediately after closing a gitcommit buffer. Fires "Signed ✓" ~3s
-- later — enough time for YubiKey touch + GPG signing to complete.
function M.after_commit()
  local timer = vim.uv.new_timer()
  timer:start(3000, 0, vim.schedule_wrap(function()
    timer:close()
    vim.notify('\n  ✓  Signed  \n', vim.log.levels.INFO)
  end))
end

return M
