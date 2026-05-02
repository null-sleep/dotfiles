-- packadd in dependency order: mason → mason-lspconfig → lspconfig
vim.cmd.packadd('mason.nvim')
vim.cmd.packadd('mason-lspconfig.nvim')
vim.cmd.packadd('nvim-lspconfig')

-- lazydev: dynamically provides Neovim API type annotations to lua_ls,
-- replacing the static workspace.library + diagnostics.globals config.
vim.cmd.packadd('lazydev.nvim')
require('lazydev').setup()

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
    'copilot',
  },
  -- Disable automatic_enable so our explicit vim.lsp.enable() below is the
  -- single source of truth for which servers are active.
  automatic_enable = false,
})

-- LspAttach: buffer-local keymaps and features applied when any LSP server
-- attaches. Runs once per client-buffer pair, no per-server base config needed.
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspAttach', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then return end

    -- Note: Copilot LSP triggers this callback too. Most features are gated by
    -- :supports_method() so they're filtered out. Ungated keymaps (gd, <C-s>,
    -- <leader>rn, etc.) are harmless — Copilot doesn't implement those methods.

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    -- Enable inlay hints (parameter names, inferred types) — useful for Rust/Go/TS.
    -- Toggle with <leader>ti when they get noisy.
    -- If they feel too distracting buffer-wide, alternatives are:
    --   1. Insert mode only — auto-enable on InsertEnter, disable on InsertLeave
    --   2. Disable noisy categories per-LSP (e.g. keep parameterNames, drop
    --      assignVariableTypes/compositeLiteralTypes which add the most clutter)
    if client:supports_method('textDocument/inlayHint') then
      vim.lsp.inlay_hint.enable(true, { bufnr = buf })
      map('n', '<leader>ti', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
      end, 'Toggle: Inlay hints')
    end

    -- Document highlight: when cursor pauses on a symbol, highlight other occurrences
    -- in the buffer. Uses LspReferenceText/Read/Write highlight groups (theme-styled).
    -- Triggers on CursorHold (300ms idle, see updatetime), clears on CursorMoved.
    if client:supports_method('textDocument/documentHighlight') then
      local group = vim.api.nvim_create_augroup('LspDocumentHighlight_' .. buf, { clear = true })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        group = group, buffer = buf, callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = group, buffer = buf, callback = vim.lsp.buf.clear_references,
      })
    end

    -- Codelens: virtual text annotations (run tests, implement interface, etc.)
    -- grx (nvim 0.12 default) runs the codelens under cursor.
    -- enable() handles refresh on BufEnter/BufWritePost automatically.
    if client:supports_method('textDocument/codeLens') then
      vim.lsp.codelens.enable(true, { bufnr = buf })
    end

    -- gd jumps to where the thing is implemented (function body, struct definition, etc.)
    map('n', 'gd',               vim.lsp.buf.definition,      'LSP: Go to definition')
    -- gD jumps to the declaration (signature without body) — useful in Rust (trait).
    -- Not supported by all LSPs: gopls and pyright don't implement textDocument/declaration
    -- since Go/Python have no separate declaration concept (declaration == definition).
    if client:supports_method('textDocument/declaration') then
      map('n', 'gD',             vim.lsp.buf.declaration,     'LSP: Go to declaration')
    end
    if client:supports_method('textDocument/typeDefinition') then
      map('n', 'gy',             vim.lsp.buf.type_definition, 'LSP: Go to type definition')
    end
    -- K (hover), [d/]d (diagnostic jump) are nvim 0.12 defaults — not remapped here.
    -- The defaults also support count: 3]d jumps 3 diagnostics forward.
    -- <C-s> may be captured by terminal as XOFF (flow control freeze) in bash/zsh.
    -- If the terminal hangs after pressing it, run `stty -ixon` in your shell rc.
    map('n', '<C-s>',            vim.lsp.buf.signature_help,  'LSP: Signature help')
    map('n', '<leader>rn',       vim.lsp.buf.rename,          'LSP: Rename symbol')
    map({'n','v'}, '<leader>ca', vim.lsp.buf.code_action,     'LSP: Code action')
    -- jump = true moves cursor to the exact diagnostic position after opening the float
    map('n', '<leader>e',        function() vim.diagnostic.open_float({ jump = true }) end, 'LSP: Show diagnostic')
    map('n', '<leader>cd',       vim.diagnostic.setloclist,   'LSP: Diagnostic list')

    -- Override nvim 0.12's grr/gri defaults with telescope pickers for a
    -- multi-result UI. Uses the gr* convention so the rest of the prefix group
    -- (grn, gra, grt, grx) keeps working and vim's gi (last insert) is preserved.
    local ok, builtin = pcall(require, 'telescope.builtin')
    map('n', 'grr', ok and builtin.lsp_references      or vim.lsp.buf.references,     'LSP: References')
    if client:supports_method('textDocument/implementation') then
      map('n', 'gri', ok and builtin.lsp_implementations or vim.lsp.buf.implementation, 'LSP: Go to implementation')
    end
  end,
})

-- diagnostic display
-- virtual_text and signs are off by default — toggle with <Space>td.
-- Underline and float remain active so you can still hover to see diagnostics.
vim.diagnostic.config({
  virtual_text     = false,
  signs            = false,
  underline        = true,
  update_in_insert = false,  -- no flicker while typing (matches updatetime = 300)
  severity_sort    = true,
  -- source = 'if_many': only show the diagnostic source label (eg. pyright, eslint)
  -- when multiple sources produce diagnostics on the same line
  float            = { border = 'rounded', source = 'if_many' },
})

-- per-server configuration using vim.lsp.config (nvim-lspconfig v3 / nvim 0.11+)

vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      runtime   = { version = 'LuaJIT' },
      -- Suppress "Apply <framework> library?" prompts (LÖVE, OpenResty, etc.)
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})

vim.lsp.config('gopls', {
  settings = {
    gopls = {
      analyses    = { unusedparams = true, shadow = true },
      staticcheck = true,
      symbolScope = 'workspace',
      -- Inlay hints — gopls has these all disabled by default
      hints = {
        assignVariableTypes    = true,
        compositeLiteralFields = true,
        compositeLiteralTypes  = true,
        constantValues         = true,
        functionTypeParameters = true,
        parameterNames         = true,
        rangeVariableTypes     = true,
      },
    },
  },
})

vim.lsp.config('rust_analyzer', {
  settings = { ['rust-analyzer'] = { checkOnSave = { command = 'clippy' } } },
})

vim.lsp.config('copilot', {
  settings = {
    copilot = { telemetryLevel = 'off' },
  },
})

vim.lsp.enable({ 'lua_ls', 'pyright', 'ts_ls', 'gopls', 'rust_analyzer', 'elixirls', 'copilot' })
