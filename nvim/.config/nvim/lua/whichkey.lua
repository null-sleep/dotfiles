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
  { '<leader>q',  group = 'Session/Quit' },
  { '<leader>t',  group = 'Toggle' },
  { '<leader>h',  group = 'Git hunk' },
  { '<leader>r',  group = 'Refactor' },
  { '<leader>c',  group = 'Code' },
  { '<leader>a',  group = 'AI' },
  { '<leader>u',  group = 'Utilities' },
  { '<leader>d',  group = 'Debug' },
  { '<leader>n',  group = 'Test' },
  { 'g',          group = 'Go to' },
  { '[',          group = 'Previous' },
  { ']',          group = 'Next' },

  -- Explorer: <leader>e is a single keymap (no sub-keys), so it doesn't
  -- need a group entry. It appears in <leader>sk via its `desc` string
  -- and the keywords table below.

  -- Spell navigation: register here so ]s / [s appear in the [/] which-key popup.
  { ']s', desc = 'Spell: Next misspelled word' },
  { '[s', desc = 'Spell: Previous misspelled word' },

  -- Yank-prefix descriptions (documentation only — `y` is intentionally not
  -- in `triggers`, so these don't pop up after pressing `y`; they appear in
  -- `<leader>?` global mappings list). Active in normal and visual modes.
  { 'yp',  desc = 'Yank: Relative path',                    mode = { 'n', 'x' } },
  { 'yP',  desc = 'Yank: Absolute path',                    mode = { 'n', 'x' } },
  { 'yc',  desc = 'Yank: Claude reference (@path:lines)',   mode = { 'n', 'x' } },
  { 'yC',  desc = 'Yank: Claude reference (absolute path)', mode = { 'n', 'x' } },
  { 'yu',  desc = 'Yank: GitHub permalink',                 mode = { 'n', 'x' } },
})

-- Extra search keywords for pickers/keybindings.lua — keyed by lhs, value is a
-- space-separated string of aliases that don't appear in the desc.
local keywords = {
  ['K']          = 'peek hover type signature documentation definition lsp float',
  ['<C-o>']      = 'jump back go back previous location history',
  ['<C-i>']      = 'jump forward go forward next location history',
  ['<leader>e']  = 'explorer file tree sidebar nvim-tree toggle reveal',
  ['<leader>o']  = 'open typora markdown gui external app preview',
  ['g?']         = 'explorer file tree help keybindings nvim-tree',
  ['<leader>qq'] = 'close buffer delete bd',
  ['<leader>tz'] = 'spell typo spelling',
  ['<leader>tb'] = 'terminal bottom panel vscode toggleterm horizontal dock',
  [']s']         = 'spell typo spelling',
  ['[s']         = 'spell typo spelling',
  ['zg']         = 'spell typo spelling dictionary add word',
  ['zw']         = 'spell typo spelling wrong',
  ['z=']         = 'spell typo spelling suggest corrections',
  ['1z=']        = 'spell typo spelling fix accept',
  ['<leader>us'] = 'strip whitespace trim trailing spaces clean',
  ['<leader>uc'] = 'clean paste reflow dedent terminal claude format fix',
  ['<leader>db'] = 'breakpoint dap debugger',
  ['<leader>dc'] = 'debug continue start dap run',
  ['<leader>du'] = 'dap-ui debugger panel scopes stack watches',
  ['<leader>dR'] = 'debug rust debuggables rustaceanvim',
  ['<leader>nn'] = 'neotest run test nearest',
  ['<leader>nd'] = 'neotest debug test dap nearest',
  ['<leader>ns'] = 'neotest summary test tree panel',
  ['<leader>cR'] = 'rust runnables run cargo rustaceanvim',
}

-- Exported for pickers/keybindings.lua: `require('whichkey').keywords`
return { keywords = keywords }
