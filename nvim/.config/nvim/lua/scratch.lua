-- Keymaps for snacks.nvim scratch buffers. The snacks setup itself (scratch
-- + indent + picker module options) lives in picker.lua, which owns the
-- single require('snacks').setup() call.

-- Open to remapping these if <leader>b* stops feeling right.
vim.keymap.set('n', '<leader>bs', function() Snacks.scratch() end,
  { desc = 'Buffer: Toggle scratch' })
vim.keymap.set('n', '<leader>bS', function() Snacks.scratch.select() end,
  { desc = 'Buffer: Select scratch' })
