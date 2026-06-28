-- IMPORTANT — formatting in this config comes from TWO subsystems, not just here:
--   1. conform.nvim (this file) — runs CLI formatters via format_on_save / <leader>cf.
--   2. LSP servers (lsp.lua)    — some servers format via textDocument/formatting.
-- conform's lsp_format = 'fallback' ties them together: a configured CLI formatter
-- wins, and conform delegates to the LSP only when no CLI formatter runs for the ft
-- — e.g. rust falls back to rust_analyzer if rustfmt is missing (see the rust entry),
-- and any filetype with no entry below is formatted by its LSP if the server supports
-- it. So the full formatting picture is split across both files — when adding,
-- removing, or auditing a formatter, check lsp.lua too, and remember an ft with no
-- entry below may still be formatted by its LSP. (Same split applies to linting —
-- see lint.lua.)
vim.cmd.packadd('conform.nvim')

-- Format-on-save off by default — it rewrites the buffer on every :w which
-- clears NES suggestions (sidekick) and inline completions (Copilot) mid-flow.
-- Toggle on with <leader>tf, or format manually with <leader>cf.
vim.g.disable_autoformat = true

require('conform').setup({
  formatters_by_ft = {
    lua    = { 'stylua' },
    python = { 'ruff_organize_imports', 'ruff_format' },
    go     = { 'goimports', 'gofmt' },
    rust   = { 'rustfmt', lsp_format = 'fallback' },
    elixir = { 'mix_format' },
    kotlin = { 'ktlint' },
    -- stop_after_first: prefer prettierd (daemon, ~10x faster); fall through
    -- to prettier only if prettierd is unavailable. Without it, both would run.
    javascript      = { 'prettierd', 'prettier', stop_after_first = true },
    typescript      = { 'prettierd', 'prettier', stop_after_first = true },
    javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    json = { 'prettierd', 'prettier', stop_after_first = true },
    yaml = { 'prettierd', 'prettier', stop_after_first = true },
    toml = { 'taplo' },
    -- Custom formatters (defined below). Both depend on external CLIs (system
    -- xmllint, user-installed just) — conform no-ops the ft if absent.
    xml  = { 'xmllint' },
    just = { 'just' },
  },

  -- Custom formatter definitions for tools conform doesn't ship.
  formatters = {
    -- xmllint ships with libxml2 (preinstalled on macOS). --format pretty-prints
    -- from stdin; XMLLINT_INDENT controls indentation (two spaces).
    xmllint = {
      command = 'xmllint',
      args = { '--format', '-' },
      stdin = true,
      env = { XMLLINT_INDENT = '  ' },
    },
    -- `just --fmt` rewrites a justfile in place, so it can't stream stdin →
    -- stdout. Run against the real file (stdin = false); --unstable is still
    -- required for the formatter as of just 1.x.
    just = {
      command = 'just',
      args = { '--fmt', '--unstable', '--justfile', '$FILENAME' },
      stdin = false,
    },
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
