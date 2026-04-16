-- Telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', builtin.find_files,  { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep,   { desc = 'Search: Grep' })
vim.keymap.set('n', '<leader>sb', builtin.buffers,     { desc = 'Search: Buffers' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', builtin.resume,                      { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })

-- Toggle LSP diagnostics (virtual text + gutter signs).
-- Note: when gitsigns on_attach keymaps are added, <leader>td will be used
-- for toggle_deleted — at that point rename this to <leader>tv.
vim.keymap.set('n', '<leader>td', function()
  local current = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({
    virtual_text = not current,
    signs        = not current,
  })
end, { desc = 'Toggle: Diagnostics' })
