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
