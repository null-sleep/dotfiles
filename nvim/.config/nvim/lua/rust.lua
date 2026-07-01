-- rustaceanvim: Rust IDE layer on top of rust-analyzer. It registers the
-- client-side rust-analyzer.runSingle/debugSingle command handlers (so the
-- Run/Debug codelens actually execute under `grx`), auto-wires the codelldb DAP
-- adapter, and provides a neotest adapter (see lua/testing.lua).
--
-- Named rust.lua — no collision (rustaceanvim's Lua module is `rustaceanvim`).
-- vim.g.rustaceanvim is set BEFORE packadd: rustaceanvim reads the global when it
-- initializes (lazily, on the first `rust` FileType — it ships only ftplugin/, no
-- eager plugin/ dir), so setting it first is the safe, self-consistent order. The
-- one hard rule from the docs is: never set it from after/ftplugin/rust.lua.

vim.g.rustaceanvim = {
  server = {
    -- Use the rustup proxy explicitly instead of a bare 'rust-analyzer'.
    --
    -- PATH ORDERING GOTCHA: Mason prepends ~/.local/share/nvim/mason/bin to PATH,
    -- and that dir sorts BEFORE ~/.cargo/bin. So a bare `rust-analyzer` (or
    -- rustaceanvim's default detection) would resolve to Mason's copy, which can
    -- drift from the active rustup toolchain and cause proc-macro/version noise.
    -- ~/.cargo/bin/rust-analyzer is a rustup proxy: toolchain-matched, and it
    -- honors per-project rust-toolchain.toml / the default toolchain automatically.
    -- rust_analyzer was removed from Mason's ensure_installed in lua/lsp.lua to match.
    cmd = { vim.fn.expand('~/.cargo/bin/rust-analyzer') },
    default_settings = {
      -- Moved here from the deleted vim.lsp.config('rust_analyzer', ...) in lsp.lua.
      ['rust-analyzer'] = {
        checkOnSave = true,
        check = { command = 'clippy' },
      },
    },
  },
  -- dap = {} accepts rustaceanvim's default adapter, which auto-detects Mason's
  -- codelldb. If a debug session dies instantly on Apple Silicon (a liblldb pairing
  -- error in :messages), replace {} with an explicit adapter:
  --   adapter = require('rustaceanvim.config').get_codelldb_adapter(
  --     vim.fn.expand('~/.local/share/nvim/mason/packages/codelldb/extension/adapter/codelldb'),
  --     vim.fn.expand('~/.local/share/nvim/mason/packages/codelldb/extension/lldb/lib/liblldb.dylib'))
  dap = {},
}

vim.cmd.packadd('rustaceanvim')

-- Rust-specific keymaps (buffer-local, rust filetype only). These are :RustLsp
-- actions plain LSP can't provide. K and <leader>ca override the global LSP maps
-- from lsp.lua with richer rustaceanvim variants — but only in Rust buffers.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'rust',
  group = vim.api.nvim_create_augroup('UserRustKeys', { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map('K',          function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust: Hover actions')
    map('<leader>ca', function() vim.cmd.RustLsp('codeAction') end,           'Rust: Code action (grouped)')
    map('<leader>cR', function() vim.cmd.RustLsp('runnables') end,            'Rust: Runnables (run)')
    map('<leader>cm', function() vim.cmd.RustLsp('expandMacro') end,          'Rust: Expand macro')
    map('<leader>cC', function() vim.cmd.RustLsp('openCargo') end,            'Rust: Open Cargo.toml')
    map('<leader>dR', function() vim.cmd.RustLsp('debuggables') end,          'Debug: Rust debuggables')
  end,
})
