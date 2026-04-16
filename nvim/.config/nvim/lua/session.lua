vim.cmd.packadd('persistence.nvim')

require('persistence').setup({
  -- Sessions saved per directory + git branch, so switching branches gives
  -- you a clean slate without losing the other branch's open files.
  branch = true,
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
