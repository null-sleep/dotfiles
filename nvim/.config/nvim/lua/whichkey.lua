vim.cmd.packadd('which-key.nvim')

local wk = require('which-key')

wk.setup({
  preset = 'modern',
  delay  = 300,  -- ms after key press before popup appears
  -- Explicit trigger list: which-key only intercepts these keys, never others.
  -- This avoids the modern preset's aggressive interception of operators like
  -- v, d, c, y when single-char groups (g, [, ]) are registered.
  -- When adding a new single-char group in wk.add(), add its trigger here too.
  triggers = {
    { '<leader>', mode = { 'n', 'v' } },
    { 'g',        mode = 'n' },
    { '[',        mode = 'n' },
    { ']',        mode = 'n' },
  },
})

-- Group labels — shown as headings in the which-key popup
-- Note: which-key warns about <gc> overlapping <gcc>. This is expected —
-- gc is Neovim's built-in comment operator (e.g. gcip, gc3j) and gcc is its
-- line shortcut. Not adding gc to triggers intentionally: it would add a 300ms
-- pause on every gcc with no real benefit.
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
