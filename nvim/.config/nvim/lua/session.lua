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

-- A synthetic (no-file) window can't be session-serialized: mksession has no
-- filename to record, so a restored session shows a blank `enew` scratch split
-- where the panel was. The general fix is to close such windows before the
-- session is written, keeping that junk out of the saved layout; you reopen the
-- panel on demand (as with the nvim-tree explorer, which also isn't restored).
-- We deliberately don't persist "was it open?" to auto-reopen — that would need
-- `sessionoptions+=globals`, a footgun that bakes unrelated globals into every
-- session. See GUIDE.md "Synthetic sidebar buffers can't be session-serialized".
--
-- Aerial's outline (outline.lua) is the one such panel in this config today.
-- Safe to close in PersistenceSavePre: it only fires from persistence's
-- VimLeavePre hook, i.e. nvim is already quitting.
vim.api.nvim_create_autocmd('User', {
  pattern = 'PersistenceSavePre',
  desc = 'Session: close synthetic-buffer panels (aerial) before mksession so they leave no blank scratch window',
  callback = function()
    require('aerial').close_all()
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
