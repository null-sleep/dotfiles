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
        -- workspace/symbol (<leader>ss) defaults to only_types; include
        -- functions/methods/consts too. Fields and impl blocks still never
        -- appear — rust-analyzer doesn't index them for this request.
        workspace = { symbol = { search = { kind = 'all_symbols' } } },
      },
    },
    -- Standalone .rs files with no Cargo project up the tree (e.g. the fixtures/
    -- demo files) start rust-analyzer in detached mode. There, clippy-on-save
    -- shells out to `cargo check` on a lone file — which cargo (1.85+) treats as
    -- a nightly-only single-file *script* (`-Zscript`/frontmatter) and refuses on
    -- stable — dumping a screenful of cargo backtrace into mini.notify on every
    -- open. Turn checkOnSave off when there's no Cargo.toml ancestor: the file
    -- still gets hover/goto/outline (the reason fixtures exist), minus the noise.
    -- Real Cargo projects (Cargo.toml found) keep full clippy-on-save.
    -- rustaceanvim calls this with the resolved root_dir, which in detached mode
    -- is just the file's own directory, so probe for Cargo.toml rather than nil.
    settings = function(project_root, default_settings)
      local settings = vim.deepcopy(default_settings)
      -- rust-project.json alongside Cargo.toml: a non-Cargo project is still a
      -- real project where clippy-on-save should stay on — only a truly
      -- detached file (neither marker up the tree) gets checkOnSave disabled.
      if not (project_root and vim.fs.root(project_root, { 'Cargo.toml', 'rust-project.json' })) then
        settings['rust-analyzer'].checkOnSave = false
      end
      return settings
    end,
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

-- Batch-apply every machine-applicable clippy fix across the whole workspace
-- in one shot (rustc's Applicability::MachineApplicable set — ambiguous/
-- semantics-changing suggestions are skipped, same as running it by hand).
-- See plans/rustrover-nvim-parity.md §1. Fixed id 102 (see utils.lua's
-- float_terminal_action — same convention as terminal.lua (100) /
-- gotargets.lua's run terminal (101)); it also guarantees a re-press never
-- kills a fix still in progress, which matters here since --fix rewrites
-- source files on disk (unlike gotargets.lua's `go run`, which has no
-- on-disk side effects to corrupt).
local clippy_fix_action = require('utils').float_terminal_action(102, function()
  local root = vim.fs.root(0, { 'Cargo.toml' })
  if not root then
    vim.notify('No Cargo.toml found up the tree', vim.log.levels.WARN)
    return nil
  end
  return { cmd = 'cargo clippy --fix --workspace --allow-dirty --allow-staged', dir = root }
end)

-- Rust-specific keymaps. These are :RustLsp actions plain LSP can't provide;
-- K and <leader>ca override the global LSP maps from lsp.lua — but only in
-- Rust buffers.
--
-- Fires on LspAttach, filtered by buffer filetype (not FileType, not the
-- client name): lsp.lua rebinds these same keys on every attach, and two
-- clients attach here — rust-analyzer, then copilot. rust.lua loads after
-- lsp.lua (Load order), so this always registers, and fires, last. Full
-- story: Design Decisions → "Rust keymaps fire on LspAttach, not FileType".
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserRustKeys', { clear = true }),
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= 'rust' then
      return
    end
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map('K',          function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust: Hover actions')
    map('<leader>ca', function() vim.cmd.RustLsp('codeAction') end,           'Rust: Code action (grouped)')
    -- actions-preview can't render rustaceanvim's grouped list (two separate
    -- pickers over the same request) — Rust keeps both keys instead of one.
    -- See plans/rustrover-nvim-parity.md §2.
    map('<leader>cp', function() require('actions-preview').code_actions() end,
      'Rust: Code action preview (diff, ungrouped)')
    map('<leader>cR', function() vim.cmd.RustLsp('runnables') end,            'Rust: Runnables (run)')
    map('<leader>cm', function() vim.cmd.RustLsp('expandMacro') end,          'Rust: Expand macro')
    map('<leader>cC', function() vim.cmd.RustLsp('openCargo') end,            'Rust: Open Cargo.toml')
    map('<leader>dR', function() vim.cmd.RustLsp('debuggables') end,          'Debug: Rust debuggables')

    -- rust-analyzer's own semantic SSR (experimental/ssr), whole-workspace and
    -- name-resolution-aware — not just AST-shape matching. No query arg: the
    -- 'ssr' command's impl (rustaceanvim/commands/ssr.lua) already prompts via
    -- vim.ui.input when called with none. See plans/rustrover-nvim-parity.md
    -- §1 — this was the "already there, just needs wiring" RustRover-parity item.
    map('<leader>cs', function() vim.cmd.RustLsp('ssr') end, 'Rust: Structural search & replace (SSR)')

    -- Visual-mode counterpart, scoped to the selection (rustaceanvim's
    -- ssr_visual): needs the command string form, NOT a Lua function — Vim
    -- auto-prepends the '<,'> range when ':' is pressed from Visual mode
    -- (:help v_:), which is what makes :RustLsp see opts.range and dispatch
    -- to ssr_visual instead of the whole-workspace ssr. A Lua-function rhs
    -- (like the normal-mode map above) has no such range to forward.
    vim.keymap.set('x', '<leader>cs', ':RustLsp ssr<CR>',
      { buffer = ev.buf, desc = 'Rust: Structural search & replace (SSR, selection)' })

    map('<leader>cF', clippy_fix_action, 'Rust: Batch-fix clippy lints (workspace)')
  end,
})
