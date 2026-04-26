-- Note: which-key uses an explicit trigger list (see whichkey.lua). If you add
-- a new single-char group in whichkey.lua's wk.add(), add it to triggers too.

-- Telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', function() require('filterpicker').find_files() end,
  { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', function() require('filterpicker').live_grep() end,
  { desc = 'Search: Grep' })
vim.keymap.set('n', '<leader>sb', builtin.buffers,     { desc = 'Search: Buffers' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', builtin.resume,                      { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sm', builtin.git_status,                  { desc = 'Search: Modified files' })
vim.keymap.set('n', '<leader>ss', builtin.lsp_dynamic_workspace_symbols, { desc = 'Search: Symbols (workspace)' })
vim.keymap.set('n', '<leader>sS', builtin.lsp_document_symbols,          { desc = 'Search: Symbols (document)' })
vim.keymap.set('n', '<leader>so', builtin.oldfiles,                      { desc = 'Search: Recent files' })
vim.keymap.set('n', '<leader>st', function() require('themepicker').open() end,
  { desc = 'Search: Themes' })
vim.keymap.set('n', '<leader>sF', function() require('filterpicker').pick() end,
  { desc = 'Search: Toggle filters' })

-- Clear search highlights
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlights' })

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

-- Quit
vim.api.nvim_create_user_command('Q', 'qa', {})
vim.keymap.set('n', '<leader>qq', '<cmd>qa<CR>', { desc = 'Quit all' })

-- Toggle LSP diagnostics (virtual text + gutter signs).
vim.keymap.set('n', '<leader>td', function()
  local current = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({
    virtual_text = not current,
    signs        = not current,
  })
end, { desc = 'Toggle: Diagnostics' })

-- Show all keybindings
vim.keymap.set('n', '<leader>?', function() require('which-key').show({ global = true }) end,
  { desc = 'Help: All mappings' })
vim.keymap.set('n', '<leader>sk', function() require('keypicker').open() end,
  { desc = 'Search: Keymaps' })

-- Yank helpers (paths, code references, GitHub permalinks)
local yank = require('yank')
vim.keymap.set({'n', 'x'}, 'yp', yank.relative_path,        { desc = 'Yank: Relative path' })
vim.keymap.set({'n', 'x'}, 'yP', yank.absolute_path,        { desc = 'Yank: Absolute path' })
vim.keymap.set({'n', 'x'}, 'yc', yank.claude_ref,           { desc = 'Yank: Claude reference (@path:lines)' })
vim.keymap.set({'n', 'x'}, 'yC', yank.claude_ref_absolute,  { desc = 'Yank: Claude reference (absolute path)' })
vim.keymap.set({'n', 'x'}, 'yu', yank.github_url,           { desc = 'Yank: GitHub permalink' })
