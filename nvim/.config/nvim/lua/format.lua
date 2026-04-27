vim.cmd.packadd('conform.nvim')

require('conform').setup({
  -- No `lua` entry: lua_ls handles it via the lsp_format = 'fallback' path below.
  formatters_by_ft = {
    python = { 'ruff_organize_imports', 'ruff_format' },
    go     = { 'goimports', 'gofmt' },
    rust   = { 'rustfmt', lsp_format = 'fallback' },
    -- stop_after_first: prefer prettierd (daemon, ~10x faster); fall through
    -- to prettier only if prettierd is unavailable. Without it, both would run.
    javascript      = { 'prettierd', 'prettier', stop_after_first = true },
    typescript      = { 'prettierd', 'prettier', stop_after_first = true },
    javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    json = { 'prettierd', 'prettier', stop_after_first = true },
    yaml = { 'prettierd', 'prettier', stop_after_first = true },
  },

  default_format_opts = { lsp_format = 'fallback' },

  -- Function form (not a table) so the toggle re-evaluates per save instead of
  -- being baked in at setup. Polarity matches conform's disable_autoformat
  -- convention so upstream docs/recipes apply directly.
  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    return { timeout_ms = 1000, lsp_format = 'fallback' }
  end,
})

-- Manual format. Async (no pending write to block); ignores disable_autoformat
-- so it remains a reliable escape hatch when format-on-save is toggled off.
-- Mapped unconditionally — conform falls back to LSP and no-ops if neither
-- a configured formatter nor an LSP is available.
vim.keymap.set({ 'n', 'v' }, '<leader>cf', function()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end, { desc = 'Format buffer' })

-- Toggles the autosave path only — does not affect manual <leader>cf.
-- Per-buffer override (e.g. for vendored files): :lua vim.b.disable_autoformat = true
vim.keymap.set('n', '<leader>tf', function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify('Format-on-save: ' .. (vim.g.disable_autoformat and 'off' or 'on'))
end, { desc = 'Toggle: Format-on-save' })
