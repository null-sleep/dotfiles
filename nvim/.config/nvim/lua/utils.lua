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

-- Floating yes/no confirm for destructive keymaps (<leader>qq quit-all,
-- <leader>ad kill CLI session).
--
-- Why this exists instead of the built-ins:
--   * vim.fn.confirm() renders at the cmdline (bottom of screen); a centered
--     popup is wanted, with the same single-keypress y/n interlock.
--   * vim.ui.select/telescope rejected: a fuzzy picker preselects an entry
--     and <CR> accepts it — exactly wrong for a destructive confirm, where
--     the default must be No and confirming must be a deliberate 'y'.
--
-- Callback-based (async), not blocking: the destructive action is passed as
-- on_confirm. Default answer is No — n/N/q/<Esc>/<CR> just close, as does
-- focus leaving the float (WinLeave/BufLeave), so it can never linger.
-- keymaps.lua's global <Esc> map closes focusable floats; the buffer-local
-- <Esc> here shadows it inside the float, and the global one closing this
-- float from outside is fine (it's the No path either way).
---@param msg string prompt text ('\n' splits into multiple lines)
---@param on_confirm fun() called only when the user presses y/Y
function M.confirm(msg, on_confirm)
  local lines = vim.split(msg, '\n', { plain = true })
  table.insert(lines, '')
  table.insert(lines, '[y]es  [n]o')

  local width = 0
  for i, l in ipairs(lines) do
    lines[i] = ' ' .. l  -- left padding (style='minimal' has none)
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]) + 1)
  end
  width = math.max(math.min(width, vim.o.columns - 4), 20)

  local buf = vim.api.nvim_create_buf(false, true)  -- unlisted scratch
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {  -- enter=true: keys go here
    relative = 'editor',
    width    = width,
    height   = #lines,
    row      = math.max(math.floor((vim.o.lines - #lines) / 2) - 1, 0),
    col      = math.max(math.floor((vim.o.columns - width) / 2), 0),
    style    = 'minimal',
    border   = 'rounded',  -- match goto-preview/mason floats
  })

  -- Dim the [y]es [n]o hint line.
  local ns = vim.api.nvim_create_namespace('utils_confirm')
  vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, 0, {
    end_col = #lines[#lines], hl_group = 'NonText',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set('n', 'y', function()
    close()
    on_confirm()
  end, { buffer = buf, nowait = true, desc = 'Confirm: Yes' })
  vim.keymap.set('n', 'Y', 'y', { buffer = buf, remap = true, nowait = true, desc = 'Confirm: Yes' })
  for _, key in ipairs({ 'n', 'N', 'q', '<Esc>', '<CR>' }) do
    vim.keymap.set('n', key, close, { buffer = buf, nowait = true, desc = 'Confirm: No (close)' })
  end

  -- Belt and braces: if focus escapes the float by any other route (mouse
  -- click, wincmd, another float stealing focus), treat it as No.
  vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    buffer = buf,
    once = true,
    -- schedule: closing a window from inside WinLeave can error (E242).
    callback = function() vim.schedule(close) end,
  })
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
