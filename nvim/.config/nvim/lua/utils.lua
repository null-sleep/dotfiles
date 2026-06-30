local M = {}

-- Build a GitHub URL from a "owner/repo" string
function M.gh(repo)
  return 'https://github.com/' .. repo
end

-- True when a UI is attached (false in `--headless` runs). Guard startup
-- side-effects like terminal pre-warms that would otherwise keep headless alive.
function M.has_ui()
  return #vim.api.nvim_list_uis() > 0
end

-- Promote a window to a full-height edge column (the nvim-tree trick). When a
-- plugin opens a side split via nvim_open_win with split='right'/'left', the
-- split inherits the current window's geometry — so opening sidekick while the
-- bottom panel is focused yields a short column inside the panel row instead
-- of a full-height column. `wincmd L`/`H` repositions the window to span the
-- full editor height at the screen edge, and Neovim reflows the other windows
-- around it. See nvim-tree's view.lua:reposition_window for the reference.
---@param win integer window handle
---@param side? 'left'|'right' default 'right'
function M.promote_to_full_height(win, side)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local cmd = side == 'left' and 'wincmd H' or 'wincmd L'
  vim.api.nvim_win_call(win, function() vim.cmd(cmd) end)
end

-- Check for newer Neovim version via Homebrew (async, non-blocking).
-- Shows a notification if an update is available.
function M.check_nvim_update()
  vim.system(
    { 'brew', 'info', '--json=v2', 'neovim' },
    { text = true },
    function(result)
      if result.code ~= 0 then return end
      local ok, info = pcall(vim.json.decode, result.stdout)
      if not ok or not info.formulae or not info.formulae[1] then return end
      local latest = info.formulae[1].versions.stable
      if not latest then return end
      local current = tostring(vim.version())
      if latest ~= current then
        vim.schedule(function()
          vim.notify(
            ('Neovim update available: %s → %s  (brew upgrade neovim)'):format(current, latest),
            vim.log.levels.INFO
          )
        end)
      end
    end
  )
end

return M
