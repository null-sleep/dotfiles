vim.cmd.packadd('which-key.nvim')

local wk = require('which-key')

wk.setup({
  preset = 'modern',
  delay  = 300,  -- ms after key press before popup appears
})

-- Group labels — shown as headings in the which-key popup
wk.add({
  { '<leader>s',  group = 'Search' },
  { '<leader>q',  group = 'Session' },
  { '<leader>t',  group = 'Toggle' },
  { '<leader>h',  group = 'Git hunk' },
  { '<leader>y',  group = 'Yank' },
  { '<leader>r',  group = 'Refactor' },
  { '<leader>c',  group = 'Code' },
  { 'g',          group = 'Go to' },
  { '[',          group = 'Previous' },
  { ']',          group = 'Next' },
})
