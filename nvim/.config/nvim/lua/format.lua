vim.cmd.packadd('conform.nvim')

require('conform').setup({
  formatters_by_ft = {
    lua    = { 'stylua' },
    python = { 'ruff_organize_imports', 'ruff_format' },
    go     = { 'goimports', 'gofmt' },
    rust   = { 'rustfmt', lsp_format = 'fallback' },
    javascript      = { 'prettierd', 'prettier', stop_after_first = true },
    typescript      = { 'prettierd', 'prettier', stop_after_first = true },
    javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    json = { 'prettierd', 'prettier', stop_after_first = true },
    yaml = { 'prettierd', 'prettier', stop_after_first = true },
  },

  default_format_opts = { lsp_format = 'fallback' },

  -- Function form re-evaluates per save so the toggle takes effect immediately.
  -- Returning nil skips formatting for this save.
  -- Polarity follows conform's disable_autoformat convention so their docs/recipes apply directly.
  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    return { timeout_ms = 1000, lsp_format = 'fallback' }
  end,
})

vim.keymap.set({ 'n', 'v' }, '<leader>cf', function()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end, { desc = 'Format buffer' })

vim.keymap.set('n', '<leader>tf', function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify('Format-on-save: ' .. (vim.g.disable_autoformat and 'off' or 'on'))
end, { desc = 'Toggle: Format-on-save' })
