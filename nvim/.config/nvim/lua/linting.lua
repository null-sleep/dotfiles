-- NOTE: this file is deliberately named linting.lua, NOT lint.lua. The nvim-lint
-- plugin's main module is `lint`, so a file at lua/lint.lua would shadow it and make
-- the require('lint') below load this file recursively ("loop ... loading module
-- 'lint'"). init.lua requires this as 'linting'.
--
-- IMPORTANT — diagnostics in this config come from TWO subsystems, not just here:
--   1. nvim-lint (this file)  — runs CLI linters on an autocmd (save/read).
--   2. LSP servers (lsp.lua)  — e.g. eslint, pyright, gopls, rust_analyzer (clippy)
--      publish diagnostics themselves; no autocmd, no nvim-lint entry.
-- So the per-language linting picture is split across both files. When adding,
-- removing, or auditing a linter, check lsp.lua too: a language may already be
-- linted by its LSP (which is why lua/rust/js/ts are intentionally absent below),
-- and anything touching diagnostics (clearing, toggling, filtering by namespace)
-- must account for the LSP-delivered ones — they live in "nvim.lsp.*" namespaces,
-- separate from nvim-lint's per-linter namespaces (named after each linter, e.g.
-- "ruff"). See the <leader>tL toggle below for how it clears only the latter.
vim.cmd.packadd('nvim-lint')

local lint = require('lint')

-- Linters that catch what the LSP servers don't. Omitted on purpose:
--   lua    → lua_ls diagnostics
--   rust   → clippy via rust_analyzer (checkOnSave)
--   js/ts  → eslint LSP (see lsp.lua)
--   kotlin → kotlin_language_server (nvim-lint has no ktlint linter; ktlint
--            runs as a formatter via conform instead)
-- credo runs the project's `mix credo`; the rest are installed via mason-tool-installer.
lint.linters_by_ft = {
  python = { 'ruff' },
  go     = { 'golangcilint' },
  elixir = { 'credo' },
  yaml   = { 'yamllint' },
  make   = { 'checkmake' },
}

-- Lint is non-destructive (diagnostics only) and runs independent of the
-- <leader>tf format-on-save toggle. Diagnostics flow into the shared
-- vim.diagnostic config in lsp.lua (underline + float, toggle display with <leader>td).
--
-- Lint on save + read only — not InsertLeave, which would re-run slow linters
-- (e.g. golangci-lint) every time you leave insert mode. <leader>cl lints on demand.
local group = vim.api.nvim_create_augroup('NvimLint', { clear = true })
vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
  group = group,
  callback = function(args)
    -- Gated by the same disable/enable convention as conform (vim.g / vim.b),
    -- so <leader>tL and a per-buffer vim.b.disable_lint silence auto-linting.
    if vim.g.disable_lint or vim.b[args.buf].disable_lint then
      return
    end
    -- try_lint no-ops for filetypes with no configured linter or a missing executable.
    lint.try_lint()
  end,
})

-- Manual lint, mirroring <leader>cf for formatting. Ignores the toggle so it
-- remains a reliable escape hatch when auto-linting is off.
vim.keymap.set('n', '<leader>cl', function()
  lint.try_lint()
end, { desc = 'Code: Lint buffer' })

-- Toggles auto-linting globally. Per-buffer override (e.g. for vendored files):
-- :lua vim.b.disable_lint = true. Clears existing diagnostics when turning off so
-- stale warnings don't linger.
-- nvim-lint names each linter's namespace after the linter itself (e.g. "ruff",
-- "golangcilint" — NOT containing a common "lint" marker), so we clear them via
-- its public lint.get_namespace(name) keyed on the linters_by_ft names. This is
-- authoritative and never touches LSP-delivered diagnostics (those live in the
-- separate "nvim.lsp.*" namespaces). reset() with no bufnr clears all buffers,
-- matching the global scope of the toggle.
vim.keymap.set('n', '<leader>tL', function()
  vim.g.disable_lint = not vim.g.disable_lint
  if vim.g.disable_lint then
    local seen = {}
    for _, names in pairs(lint.linters_by_ft) do
      for _, name in ipairs(names) do
        if not seen[name] then
          seen[name] = true
          vim.diagnostic.reset(lint.get_namespace(name))
        end
      end
    end
  end
  vim.notify('Lint-on-save: ' .. (vim.g.disable_lint and 'off' or 'on'))
end, { desc = 'Toggle: Lint-on-save' })
