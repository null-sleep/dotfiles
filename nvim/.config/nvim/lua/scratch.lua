vim.cmd.packadd('snacks.nvim')

-- Only enabling the scratch module; every other snacks.nvim module
-- (dashboard, notifier, picker, etc.) stays off — this config already has
-- its own equivalents (mini.notify, telescope, ...).
require('snacks').setup({
  scratch = {
    win = {
      width = 100,
      height = 30,
      border = 'rounded',  -- match toggleterm's curved float style (nvim_open_win vocabulary differs)
    },
  },
})

-- Open to remapping these if <leader>b* stops feeling right.
vim.keymap.set('n', '<leader>bs', function() Snacks.scratch() end,
  { desc = 'Buffer: Toggle scratch' })
vim.keymap.set('n', '<leader>bS', function() Snacks.scratch.select() end,
  { desc = 'Buffer: Select scratch' })
