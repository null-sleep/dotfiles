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

-- mason-tool-installer: installs/updates every Mason package this config uses —
-- LSP servers (mason-lspconfig below only enables them) and formatter/linter/
-- debug-adapter CLIs. Excludes mix_format/credo (per-project Elixir mix deps,
-- not Mason packages) and xmllint/just (system/user-provided CLIs).
-- auto_update + debounce_hours: re-checks for updates at most once/24h on
-- startup; notifies per-package itself (:help mason-tool-installer-auto_update).
-- start_delay: the check is pure maintenance (installed tools work either
-- way), so push it well past startup instead of racing session restore and
-- the async LSP storm (rust-analyzer indexing alone can run 10s+ on a real
-- Rust repo) -- 30s clears that tail; the value isn't sensitive (30-60s fine).
vim.cmd.packadd('mason-tool-installer.nvim')
require('mason-tool-installer').setup({
  auto_update = true,
  debounce_hours = 24,
  start_delay = 30000,   -- 30_000 ms
  ensure_installed = {
    -- LSP servers (lspconfig names; mapped to Mason package names via the
    -- mason-lspconfig integration). rust_analyzer omitted: rustaceanvim
    -- (rust.lua) manages it via rustup, not Mason.
    'lua_ls',
    'pyright',
    'ts_ls',
    'gopls',
    'elixirls',
    'kotlin_language_server',
    'eslint',
    'copilot',
    -- formatter/linter/debug-adapter CLIs
    'stylua',         -- lua formatter
    'ruff',           -- python formatter + linter
    'prettierd',      -- js/ts/json/yaml formatter
    'goimports',      -- go formatter
    'golangci-lint',  -- go linter
    'ktlint',         -- kotlin formatter
    'taplo',          -- toml formatter
    'yamllint',       -- yaml linter
    'checkmake',      -- makefile linter
    'codelldb',       -- rust/c/c++ debug adapter (consumed by nvim-dap via rustaceanvim)
  },
})

-- mason-lspconfig: install/update is owned by mason-tool-installer above;
-- this only enables servers. automatic_enable = false keeps vim.lsp.enable()
-- below as the single source of truth for which servers are active.
require('mason-lspconfig').setup({
  automatic_enable = false,
})

-- goto-preview: VS Code-style scrollable float into the target file. Peek maps
-- (<leader>p*, set on LspAttach below) mirror the gd/gy/gri/grr jump maps but show
-- a popup instead of navigating. See lua/plugins.lua for the plugin spec.
vim.cmd.packadd('goto-preview')
require('goto-preview').setup({
  border = 'rounded',        -- match Mason/other floats
  focus_on_open = true,      -- jump into the float so you can scroll immediately
  dismiss_on_move = false,   -- stay open while you scroll around
  default_mappings = false,  -- we define our own below (under <leader>p)
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
    -- <leader>ca, etc.) are harmless — Copilot doesn't implement those methods.

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
      map('n', '<leader>ti', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
      end, 'Toggle: Inlay hints')
    end

    -- Hover on CursorHold: show the same float as pressing K, after updatetime ms idle.
    -- Off by default — use K for on-demand hover, <leader>th to toggle auto-hover.
    -- Future: Neovim may add MouseMove events (neovim/neovim#9152), which would
    -- enable VS Code-style hover-on-mouse (or even mouse-click-triggered hover) —
    -- revisit this when that lands.
    if client:supports_method('textDocument/hover') then
      local hover_group = 'LspHoverOnHold_' .. buf
      local function enable_hover()
        local group = vim.api.nvim_create_augroup(hover_group, { clear = true })
        vim.api.nvim_create_autocmd('CursorHold', {
          group = group, buffer = buf,
          -- focus = false: float appears without stealing cursor (passive display).
          -- silent = true: suppresses "No information available" when cursor is over
          --   non-symbol text (nvim 0.11+ native option; no vim.notify monkey-patching needed).
          -- max_height = 20: prevents full-screen docstring popups.
          callback = function()
            if vim.b.hover_suppressed then return end
            vim.lsp.buf.hover({ focus = false, silent = true, max_height = 20 })
          end,
        })
      end
      -- Create the augroup but don't register the autocmd — starts disabled.
      vim.api.nvim_create_augroup(hover_group, { clear = true })
      map('n', '<leader>th', function()
        local ok = pcall(vim.api.nvim_get_augroup_by_name, hover_group)
        -- augroup exists but may be empty after a previous toggle-off; check for autocmds
        local active = ok and #vim.api.nvim_get_autocmds({ group = hover_group }) > 0
        if active then
          vim.api.nvim_clear_autocmds({ group = hover_group })
          vim.notify('Hover on hold: off', vim.log.levels.INFO)
        else
          enable_hover()
          vim.notify('Hover on hold: on', vim.log.levels.INFO)
        end
      end, 'Toggle: Hover on hold')
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

    -- LspDetach cleanup: clear the CursorHold augroups registered above when the
    -- last client supporting each method detaches. Without this, the autocmds keep
    -- firing against a buffer with no attached client (e.g. after :LspStop or restart).
    -- Per-buffer augroup (clear = true) so re-attaching a client re-registers cleanly.
    vim.api.nvim_create_autocmd('LspDetach', {
      group = vim.api.nvim_create_augroup('LspDetachCleanup_' .. buf, { clear = true }),
      buffer = buf,
      callback = function(detach_ev)
        local remaining = vim.lsp.get_clients({ bufnr = buf })
        -- The detaching client is still in the list; exclude it.
        remaining = vim.tbl_filter(function(c)
          return c.id ~= detach_ev.data.client_id
        end, remaining)

        local function any_supports(method)
          for _, c in ipairs(remaining) do
            if c:supports_method(method) then return true end
          end
          return false
        end

        if not any_supports('textDocument/hover') then
          pcall(vim.api.nvim_del_augroup_by_name, 'LspHoverOnHold_' .. buf)
        end
        if not any_supports('textDocument/documentHighlight') then
          pcall(vim.api.nvim_del_augroup_by_name, 'LspDocumentHighlight_' .. buf)
          pcall(vim.lsp.buf.clear_references)
        end
      end,
    })

    -- Codelens: virtual text annotations (run tests, implement interface, etc.)
    -- grx (nvim 0.12 default) runs the codelens under cursor.
    -- enable() handles refresh on BufEnter/BufWritePost automatically.
    if client:supports_method('textDocument/codeLens') then
      vim.lsp.codelens.enable(true, { bufnr = buf })
    end

    -- Copilot inline completion: ghost-text suggestions while typing in insert mode.
    -- Separate from NES (sidekick), which shows follow-on edit diffs in normal mode.
    -- <Tab> accepts (handled in completion.lua's blink keymap chain).
    -- Enabled by default; <leader>ta toggles globally (all buffers, both features).
    if client:supports_method(vim.lsp.protocol.Methods.textDocument_inlineCompletion, buf) then
      vim.lsp.inline_completion.enable(true, { bufnr = buf })
    end

    -- snacks pickers for LSP jumps that can return multiple results
    -- (gd/gy/gri/grr below) — without this, nvim's default handler dumps
    -- multiple results into the quickfix list instead of showing a picker.
    -- The sources have auto_confirm, so a single result still jumps straight
    -- there (through the global confirm, landing ~20% from the top like
    -- every other picker jump — see picker.lua).
    local ok = pcall(require, 'snacks')

    -- gd jumps to where the thing is implemented (function body, struct definition, etc.).
    -- Can resolve to multiple targets (e.g. a trait method with several impls).
    map('n', 'gd', ok and function() Snacks.picker.lsp_definitions() end or vim.lsp.buf.definition, 'LSP: Go to definition')
    -- gD jumps to the declaration (signature without body) — useful in Rust (trait).
    -- Not supported by all LSPs: gopls and pyright don't implement textDocument/declaration
    -- since Go/Python have no separate declaration concept (declaration == definition).
    if client:supports_method('textDocument/declaration') then
      map('n', 'gD', ok and function() Snacks.picker.lsp_declarations() end or vim.lsp.buf.declaration, 'LSP: Go to declaration')
    end
    -- gy: rust-analyzer often resolves this to several targets (trait bounds,
    -- generics), so route through a picker rather than the default quickfix
    -- dump. A single result still jumps straight there.
    if client:supports_method('textDocument/typeDefinition') then
      map('n', 'gy', ok and function() Snacks.picker.lsp_type_definitions() end or vim.lsp.buf.type_definition, 'LSP: Go to type definition')
    end
    -- <leader>p*: peek the same targets as gd/gy/gri/grr, but in a scrollable float
    -- (the real file) instead of jumping. <leader>pq closes all open peeks.
    local gp = require('goto-preview')
    map('n', '<leader>pd', gp.goto_preview_definition,        'Peek: Definition')
    if client:supports_method('textDocument/typeDefinition') then
      map('n', '<leader>pt', gp.goto_preview_type_definition, 'Peek: Type definition')
    end
    if client:supports_method('textDocument/implementation') then
      map('n', '<leader>pi', gp.goto_preview_implementation,  'Peek: Implementation')
    end
    map('n', '<leader>pr', gp.goto_preview_references,        'Peek: References')
    map('n', '<leader>pq', gp.close_all_win,                  'Peek: Close all')
    -- K: peek the symbol under the cursor — its type, function signature, and
    -- doc comment — in a float, without leaving the line (no jump, unlike gd/gy).
    -- Press K again to enter the float and scroll; any cursor move dismisses it.
    -- Overrides the 0.12 default purely to cap the float at max_height=20 lines.
    -- [d/]d (diagnostic jump) left as defaults; those support count (3]d = jump 3).
    map('n', 'K', function() vim.lsp.buf.hover({ max_height = 20 }) end, 'LSP: Hover (peek type/signature/docs)')
    -- <C-s> may be captured by terminal as XOFF (flow control freeze) in bash/zsh.
    -- If the terminal hangs after pressing it, run `stty -ixon` in your shell rc.
    map({ 'n', 'i' }, '<C-s>',   vim.lsp.buf.signature_help,  'LSP: Signature help')
    -- Rename intentionally has no <leader>r map: nvim 0.11+ core already binds
    -- grn (rename) alongside gra/grr/gri/grt/grx, so a <leader>rn alias would
    -- just duplicate a built-in for the cost of an entire top-level leader group.
    map({'n','x'}, '<leader>ca', vim.lsp.buf.code_action,     'LSP: Code action')

    -- Re-bind the core defaults we keep (same functions, unchanged behavior) purely
    -- to give them a desc: nvim sets them without one, so which-key and <leader>sk
    -- label them with their raw callee ("vim.lsp.buf.rename()") and file them under
    -- no group — worst for exactly the keys this config tells you to reach for.
    map('n', 'grn',        vim.lsp.buf.rename,          'LSP: Rename symbol')
    map({'n','x'}, 'gra',  vim.lsp.buf.code_action,     'LSP: Code action')
    map('n', 'grt',        vim.lsp.buf.type_definition, 'LSP: Go to type definition')
    map('n', 'grx',        vim.lsp.codelens.run,        'LSP: Run codelens')
    map('n', 'gO',         vim.lsp.buf.document_symbol, 'LSP: Document symbols')
    -- Show the diagnostic under the cursor in a float, without moving (moving
    -- to next/prev is [d/]d's job). scope = 'cursor' limits it to the cursor's
    -- diagnostic rather than every one on the line (open_float's default).
    map('n', '<leader>ce',       function() vim.diagnostic.open_float({ scope = 'cursor' }) end, 'LSP: Show diagnostic')
    map('n', '<leader>cd',       vim.diagnostic.setloclist,   'LSP: Diagnostic list')

    -- Override nvim 0.12's grr/gri defaults with snacks pickers for a
    -- multi-result UI. Uses the gr* convention so the rest of the prefix group
    -- (grn, gra, grt, grx) keeps working and vim's gi (last insert) is preserved.
    map('n', 'grr', ok and function() Snacks.picker.lsp_references() end or vim.lsp.buf.references, 'LSP: References')
    if client:supports_method('textDocument/implementation') then
      map('n', 'gri', ok and function() Snacks.picker.lsp_implementations() end or vim.lsp.buf.implementation, 'LSP: Go to implementation')
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
  -- After a [d/]d jump, auto-open a cursor-scoped float so the message is
  -- visible without another keypress. Matters here because virtual_text and
  -- signs are both off (low-noise default) — otherwise a jump lands on a
  -- diagnostic you can't actually read. Inherits the `float` opts above
  -- (rounded border, source = if_many). `focus = false` keeps the cursor in
  -- the buffer on repeated jumps WITHOUT setting the window non-focusable —
  -- so it stays `focusable`, which is what the <Esc> close-floats handler in
  -- keymaps.lua keys off to dismiss it (a focusable=false float would be
  -- treated as a passive helper and left open). Matches nvim's own jump.float.
  jump             = {
    on_jump = function(diagnostic, bufnr)
      if not diagnostic then return end
      vim.diagnostic.open_float({ bufnr = bufnr, scope = 'cursor', focus = false })
    end,
  },
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

-- rust_analyzer is configured by rustaceanvim (lua/rust.lua via vim.g.rustaceanvim),
-- not here — it must not be started by the native vim.lsp path too (double-attach).
-- The clippy-on-save setting lives in vim.g.rustaceanvim.server.default_settings.

-- Explicit root markers ensure Maven projects get a workspace root (not single-file mode).
vim.lsp.config('kotlin_language_server', {
  root_markers = { 'pom.xml', 'settings.gradle', 'settings.gradle.kts', 'build.gradle', 'build.gradle.kts', '.git' },
})

vim.lsp.config('copilot', {
  settings = {
    copilot = { telemetryLevel = 'off' },
  },
})

-- eslint: JS/TS linting as an LSP — diagnostics plus code actions (fix-all available
-- via <leader>ca). lspconfig's default config supplies root markers (.eslintrc*,
-- eslint.config.js) and the on_attach that registers the EslintFixAll command.
-- Diagnostics-only by design: no fix-on-save autocmd, to avoid fighting the
-- <leader>tf format-on-save toggle.
--
-- NOTE: eslint is a LINTER delivered as an LSP, not via nvim-lint. Several tools
-- here double as linters/formatters this way (eslint lints JS/TS; rust_analyzer
-- runs clippy; gopls/pyright/lua_ls publish diagnostics; servers can also format
-- via conform's lsp_format = 'fallback'). So the linting/formatting story is split
-- across THIS file and lint.lua / format.lua — when changing a linter or formatter,
-- account for the LSP-delivered ones here too, don't assume everything is an autocmd.
vim.lsp.config('eslint', {})

-- Capability half of nvim-lsp-file-operations — event half in filetree.lua,
-- keep in sync (grep 'lsp-file-operations'). Advertises willRename/didRename to
-- every server so an in-tree rename rewrites importers. Rationale in GUIDE.md
-- "Renaming a file rewrites its imports".
--
-- Must stay a '*' deep-merge, NOT `capabilities = ...` on a named server:
-- blink.cmp registers its completion caps on '*' too, and a plain assignment
-- would clobber them. Disjoint subtrees, so the merge keeps both.
vim.cmd.packadd('nvim-lsp-file-operations')
vim.lsp.config('*', {
  capabilities = require('lsp-file-operations').default_capabilities(),
})

-- rust_analyzer omitted: started by rustaceanvim, not the native vim.lsp path.
vim.lsp.enable({ 'lua_ls', 'pyright', 'ts_ls', 'gopls', 'elixirls', 'kotlin_language_server', 'eslint', 'copilot' })
