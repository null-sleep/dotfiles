-- packadd in dependency order: mason → mason-lspconfig → lspconfig
vim.cmd.packadd('mason.nvim')
vim.cmd.packadd('mason-lspconfig.nvim')
vim.cmd.packadd('nvim-lspconfig')

-- mason: server installer UI
require('mason').setup({
  ui = {
    border = 'rounded',
    icons = {
      package_installed   = '✓',
      package_pending     = '➜',
      package_uninstalled = '✗',
    },
  },
})

-- mason-lspconfig: auto-installs servers from ensure_installed on startup
require('mason-lspconfig').setup({
  ensure_installed = {
    'lua_ls',
    'pyright',
    'ts_ls',
    'gopls',
    'rust_analyzer',
    'elixirls',
  },
  automatic_installation = true,
})

-- on_attach: buffer-local keymaps applied when a server attaches to a buffer
local function on_attach(_, buf)
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
  end

  -- gd jumps to where the thing is implemented (function body, struct definition, etc.)
  map('n', 'gd',               vim.lsp.buf.definition,      'LSP: Go to definition')
  -- gD jumps to the declaration (signature without body) — useful in Go (interface)
  -- and Rust (trait). In Python/Elixir there is no distinction so gD behaves like gd.
  map('n', 'gD',               vim.lsp.buf.declaration,     'LSP: Go to declaration')
  map('n', 'gi',               vim.lsp.buf.implementation,  'LSP: Go to implementation')
  map('n', 'gy',               vim.lsp.buf.type_definition, 'LSP: Go to type definition')
  map('n', 'K',                vim.lsp.buf.hover,           'LSP: Hover docs')
  map('n', '<C-s>',            vim.lsp.buf.signature_help,  'LSP: Signature help')
  map('n', '<leader>rn',       vim.lsp.buf.rename,          'LSP: Rename symbol')
  map({'n','v'}, '<leader>ca', vim.lsp.buf.code_action,     'LSP: Code action')
  -- jump = true moves cursor to the exact diagnostic position after opening the float
  map('n', '<leader>e',        function() vim.diagnostic.open_float({ jump = true }) end, 'LSP: Show diagnostic')
  map('n', '[d',               function() vim.diagnostic.jump({ count = -1 }) end, 'LSP: Previous diagnostic')
  map('n', ']d',               function() vim.diagnostic.jump({ count =  1 }) end, 'LSP: Next diagnostic')
  map('n', '<leader>cd',       vim.diagnostic.setloclist,   'LSP: Diagnostic list')

  -- Use telescope for references if available, fallback to plain LSP
  local ok, builtin = pcall(require, 'telescope.builtin')
  map('n', 'gr', ok and builtin.lsp_references or vim.lsp.buf.references, 'LSP: References')
end

-- nvim 0.11+ with vim.lsp.config handles capabilities automatically, so no
-- explicit blink.cmp capabilities merge is required. In older setups (or with
-- nvim-lspconfig v2), you would replace this line with:
--   require('blink.cmp').get_lsp_capabilities(nil, true)
-- which merges blink's completionItem capabilities (snippet support, etc.)
-- on top of vim.lsp.protocol.make_client_capabilities().
local capabilities = vim.lsp.protocol.make_client_capabilities()

-- diagnostic display
-- virtual_text and signs are off by default — toggle with <Space>td.
-- Underline and float remain active so you can still hover to see diagnostics.
vim.diagnostic.config({
  virtual_text     = false,
  signs            = false,
  underline        = true,
  update_in_insert = false,  -- no flicker while typing (matches updatetime = 300)
  severity_sort    = true,
  float            = { border = 'rounded', source = 'always' },
})

-- per-server configuration using vim.lsp.config (nvim-lspconfig v3 / nvim 0.11+)
local base = { on_attach = on_attach, capabilities = capabilities }

vim.lsp.config('lua_ls', vim.tbl_deep_extend('force', base, {
  settings = {
    Lua = {
      runtime     = { version = 'LuaJIT' },
      workspace   = { checkThirdParty = false, library = vim.api.nvim_get_runtime_file('', true) },
      diagnostics = { globals = { 'vim' } },
      telemetry   = { enable = false },
    },
  },
}))

vim.lsp.config('pyright',        base)
vim.lsp.config('ts_ls',          base)

vim.lsp.config('gopls', vim.tbl_deep_extend('force', base, {
  settings = {
    gopls = {
      analyses    = { unusedparams = true, shadow = true },
      staticcheck = true,
      symbolScope = 'workspace',
    },
  },
}))

vim.lsp.config('rust_analyzer', vim.tbl_deep_extend('force', base, {
  settings = { ['rust-analyzer'] = { checkOnSave = { command = 'clippy' } } },
}))

vim.lsp.config('elixirls', base)

vim.lsp.enable({ 'lua_ls', 'pyright', 'ts_ls', 'gopls', 'rust_analyzer', 'elixirls' })
