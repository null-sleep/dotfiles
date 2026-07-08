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

-- Shared terminal-mode nav keymaps for terminal-owning buffers: `jj` exits
-- terminal mode, <C-h/j/k/l> jump splits. opts.esc = true also maps <Esc>
-- to exit — toggleterm buffers want it; sidekick's CLI must NOT set it
-- (Esc is forwarded to Claude for interrupts). Callers add their own
-- buffer-specific extras (<C-]> cycling, <S-CR>) next to their call site.
function M.term_nav_keymaps(buf, opts)
  local o = { buffer = buf }
  if opts and opts.esc then
    vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], o)
  end
  vim.keymap.set('t', 'jj',    [[<C-\><C-n>]], o)
  vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], o)
  vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], o)
  vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], o)
  vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], o)
end

-- Check for newer Neovim version via Homebrew (async, non-blocking).
-- Shows a notification if an update is available.
--
-- Guards: skipped when headless or in claude-nvim throwaway runs (same
-- CLAUDE_NVIM=1 marker plugins.lua honors), and debounced to once per 24h
-- via a stamp file — the stamp is written *before* the async call so
-- parallel launches can't race into duplicate checks. The version compare
-- uses vim.version.cmp, not string equality: a local/dev build newer than
-- brew's stable must not notify, and tostring(vim.version()) carries
-- prerelease/build suffixes that would never equal brew's version string.
function M.check_nvim_update()
  if vim.env.CLAUDE_NVIM == '1' or not M.has_ui() then return end

  local stamp = vim.fs.joinpath(vim.fn.stdpath('cache'), 'nvim-update-check')
  local stat = vim.uv.fs_stat(stamp)
  if stat and os.time() - stat.mtime.sec < 24 * 60 * 60 then return end
  vim.fn.writefile({}, stamp)

  vim.system(
    { 'brew', 'info', '--json=v2', 'neovim' },
    { text = true },
    function(result)
      if result.code ~= 0 then return end
      local ok, info = pcall(vim.json.decode, result.stdout)
      local stable = ok and vim.tbl_get(info, 'formulae', 1, 'versions', 'stable')
      local latest = stable and vim.version.parse(stable)
      if latest and vim.version.cmp(latest, vim.version()) > 0 then
        vim.schedule(function()
          vim.notify(
            ('Neovim update available: %s → %s  (brew upgrade neovim)'):format(
              tostring(vim.version()), stable),
            vim.log.levels.INFO
          )
        end)
      end
    end
  )
end

return M
