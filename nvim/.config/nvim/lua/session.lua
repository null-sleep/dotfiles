vim.cmd.packadd('persistence.nvim')

require('persistence').setup({
  -- Sessions saved per directory + git branch, so switching branches gives
  -- you a clean slate without losing the other branch's open files.
  branch = true,
})

-- Keep terminals out of saved sessions. Restoring a terminal only re-spawns a
-- fresh shell (no scrollback, no in-session command history — that lives in the
-- shell's own histfile) into a window, so there's nothing to gain. Worse, the
-- restored sidekick CLI buffer isn't in sidekick's runtime registry, so
-- <leader>aa toggle can no longer manage it (it tracks the pre-warmed instance).
-- Dropping this flag makes mksession omit terminal *windows* entirely from the
-- saved layout (verified: no empty-split placeholder is left behind), so this
-- one line is the whole fix.
vim.opt.sessionoptions:remove('terminal')

-- Aerial's outline sidebar (outline.lua) has no backing file — its buffer is
-- synthetic, so mksession can't serialize "what's shown" in that window like
-- it does for a real file. Left alone, the saved session restores that window
-- as a bare `enew` scratch buffer instead of the outline (verified by
-- inspecting the generated session file), which is what "restoring a session
-- doesn't bring the outline panel back" actually is.
--
-- Fix: close aerial before the session is written (safe — save only runs
-- from persistence's VimLeavePre hook, i.e. nvim is already quitting) and
-- remember whether it was open via a session-local global (`sessionoptions
-- +=globals` makes `let g:...` lines for capitalized globals get written into
-- the session file itself — but ONLY for String/Number values; a Lua
-- boolean becomes v:true/v:false, which mksession silently drops, so this
-- is stored as 0/1). Reopen it, unfocused, once the session file has
-- finished restoring everything else.
vim.opt.sessionoptions:append('globals')

local function aerial_is_open()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'aerial' then
      return true
    end
  end
  return false
end

vim.api.nvim_create_autocmd('User', {
  pattern = 'PersistenceSavePre',
  desc = 'Session: close aerial before mksession (its buffer can\'t be serialized)',
  callback = function()
    vim.g.AerialWasOpen = aerial_is_open() and 1 or 0
    require('aerial').close_all()
  end,
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'PersistenceLoadPost',
  desc = 'Session: reopen aerial if it was open when the session was saved',
  callback = function()
    if vim.g.AerialWasOpen == 1 then
      require('aerial').open({ focus = false })
    end
  end,
})

-- Restore session for the current directory (most common)
vim.keymap.set('n', '<leader>qs', function() require('persistence').load() end,
  { desc = 'Session: Restore' })

-- Pick from all saved sessions
vim.keymap.set('n', '<leader>qS', function() require('persistence').select() end,
  { desc = 'Session: Select' })

-- Restore the last session regardless of directory
vim.keymap.set('n', '<leader>ql', function() require('persistence').load({ last = true }) end,
  { desc = 'Session: Restore last' })

-- Stop saving — useful when you want to quit without persisting current state
vim.keymap.set('n', '<leader>qd', function() require('persistence').stop() end,
  { desc = 'Session: Stop saving' })
