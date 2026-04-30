-- Note: which-key uses an explicit trigger list (see whichkey.lua). If you add
-- a new single-char group in whichkey.lua's wk.add(), add it to triggers too.

-- Telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', function() require('pickers.filter').find_files() end,
  { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', function() require('pickers.filter').live_grep() end,
  { desc = 'Search: Grep' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', builtin.resume,                      { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sm', function() require('pickers.gitstatus').open() end,
  { desc = 'Search: Modified files' })
vim.keymap.set('n', '<leader>ss', function() require('pickers.symbols').workspace() end,
  { desc = 'Search: Symbols (workspace)' })
vim.keymap.set('n', '<leader>sS', function() require('pickers.symbols').document() end,
  { desc = 'Search: Symbols (document)' })
vim.keymap.set('n', '<leader>so', builtin.oldfiles,                      { desc = 'Search: Recent files' })
vim.keymap.set('n', '<leader>st', function() require('pickers.theme').open() end,
  { desc = 'Search: Themes' })
vim.keymap.set('n', '<leader>sF', function() require('pickers.filter').pick() end,
  { desc = 'Search: Toggle filters' })

-- Clear search highlights
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlights' })

-- Exit insert mode without reaching for Escape
vim.keymap.set('i', 'jk', '<Esc>', { desc = 'Exit insert mode' })

-- Yank to system clipboard (dd, x, c stay in Neovim register).
-- Uses expr mapping so that explicit register prefixes ("a, "b, etc.) are
-- honoured — only bare y/Y without a register prefix go to clipboard.
vim.keymap.set({'n', 'v'}, 'y', function()
  if vim.v.register ~= '"' then return 'y' end
  return '"+y'
end, { expr = true, desc = 'Yank to system clipboard (unless register specified)' })

vim.keymap.set('n', 'Y', function()
  if vim.v.register ~= '"' then return 'Y' end
  return '"+Y'
end, { expr = true, desc = 'Yank line to system clipboard (unless register specified)' })

-- Stay in visual mode after indent/dedent
vim.keymap.set('v', '<', '<gv', { desc = 'Dedent and reselect' })
vim.keymap.set('v', '>', '>gv', { desc = 'Indent and reselect' })

-- Paste over selection without clobbering the register
vim.keymap.set('v', 'p', '"_dP', { desc = 'Paste without yanking replaced text' })

-- Split navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move to left split' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move to split below' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move to split above' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move to right split' })

-- Buffer navigation
vim.keymap.set('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<CR>',     { desc = 'Next buffer' })
vim.keymap.set('n', '<leader><leader>', '<C-^>',   { desc = 'Toggle alternate buffer' })
vim.keymap.set('n', '<leader>m', function() require('pickers.buffer').open() end,
  { desc = 'Buffer picker' })

-- Quit
vim.api.nvim_create_user_command('Q', 'qa', {})
vim.keymap.set('n', '<leader>qq', '<cmd>qa<CR>', { desc = 'Quit all' })

-- Toggle spell checking
vim.keymap.set('n', '<leader>tz', function()
  vim.opt.spell = not vim.opt.spell:get()
end, { desc = 'Toggle: Spell check' })

-- Add word to dictionary, skipping duplicates
vim.keymap.set('n', 'zg', require('spell').add_word, { desc = 'Spell: Add word to dictionary' })

-- Toggle LSP diagnostics (virtual text + gutter signs).
vim.keymap.set('n', '<leader>td', function()
  local current = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({
    virtual_text = not current,
    signs        = not current,
  })
end, { desc = 'Toggle: Diagnostics' })

-- Toggle <leader>ss scope: multi-LSP fan-out (default) ↔ buffer-attached only.
vim.keymap.set('n', '<leader>ts',
  function() require('pickers.symbols').toggle_buffer_only() end,
  { desc = 'Toggle: Symbol search scope (all LSPs ↔ buffer)' })

-- Show all keybindings
vim.keymap.set('n', '<leader>?', function() require('which-key').show({ global = true }) end,
  { desc = 'Help: All mappings' })
vim.keymap.set('n', '<leader>sk', function() require('pickers.keybindings').open() end,
  { desc = 'Search: Keymaps' })

-- Yank helpers (paths, code references, GitHub permalinks)
local yank = require('yank')
vim.keymap.set({'n', 'x'}, 'yp', yank.relative_path,        { desc = 'Yank: Relative path' })
vim.keymap.set({'n', 'x'}, 'yP', yank.absolute_path,        { desc = 'Yank: Absolute path' })
vim.keymap.set({'n', 'x'}, 'yc', yank.claude_ref,           { desc = 'Yank: Claude reference (@path:lines)' })
vim.keymap.set({'n', 'x'}, 'yC', yank.claude_ref_absolute,  { desc = 'Yank: Claude reference (absolute path)' })
vim.keymap.set({'n', 'x'}, 'yu', yank.github_url,           { desc = 'Yank: GitHub permalink' })
