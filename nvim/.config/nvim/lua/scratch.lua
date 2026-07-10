vim.cmd.packadd('snacks.nvim')

-- Only enabling the scratch and indent modules; every other snacks.nvim
-- module (dashboard, notifier, picker, etc.) stays off — this config
-- already has its own equivalents (mini.notify, telescope, ...).
require('snacks').setup({
  scratch = {
    win = {
      width = 100,
      height = 30,
      border = 'rounded',  -- match toggleterm's curved float style (nvim_open_win vocabulary differs)
    },
  },
  -- Indent guides off by default; toggle on with <leader>tg. `enabled = false`
  -- survives snacks' auto-enable (setup only forces enabled=true when it's nil),
  -- so the module never activates on BufReadPost and Snacks.indent.enabled stays
  -- false until the first toggle. char/scope/animate are still registered here,
  -- so enable() picks them up when it fires.
  indent = {
    enabled  = false,
    indent   = { char = '▏' },
    scope    = { char = '▏' },
    animate  = { enabled = false },
  },
})

-- Open to remapping these if <leader>b* stops feeling right.
vim.keymap.set('n', '<leader>bs', function() Snacks.scratch() end,
  { desc = 'Buffer: Toggle scratch' })
vim.keymap.set('n', '<leader>bS', function() Snacks.scratch.select() end,
  { desc = 'Buffer: Select scratch' })
