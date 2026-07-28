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

-- `cargo run` output for runnables — a bottom-split terminal buffer via
-- utils.split_terminal_action, shared with Go's <leader>cR (gotargets.lua).
-- `q` hides it. `require`s are inside the builder: it runs at runnable time,
-- after the packadd below puts rustaceanvim (an opt package) on the
-- runtimepath.
local run_output = require('utils').split_terminal_action(function(command, args, cwd, opts)
  return {
    cmd = require('rustaceanvim.shell').make_command_from_args(command, args),
    dir = cwd,
    env = opts and opts.env,
  }
end)

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
  tools = {
    -- Route <leader>cR runnables to the bottom-split buffer above instead of
    -- the default executor. test_executor stays at its default (neotest), so
    -- `cargo test` runnables still go to the test UI, not this split.
    executor = { execute_command = run_output },
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

-- Auto-reload workaround for rust-analyzer's stale-diagnostics gap. See
-- GUIDE.md "Automatic workspace reload".
local RELOAD_COOLDOWN = 5000 -- ms; cooldown starts when a reload FINISHES
local last_sig, last_reload, in_flight = '', 0, false

-- logs/HEAD, not .git/HEAD (which only moves on a branch switch, missing a
-- same-branch pull/rebase/commit). Handles .git-as-a-file via its gitdir: line.
local function git_head_log_path(root)
  local git_root = vim.fs.root(root, '.git')
  if not git_root then
    return nil
  end
  local dotgit = git_root .. '/.git'
  local stat = vim.uv.fs_stat(dotgit)
  if not stat then
    return nil
  end
  if stat.type == 'directory' then
    return dotgit .. '/logs/HEAD'
  end
  -- .git is a file: read its "gitdir: <path>" pointer.
  local fd = io.open(dotgit, 'r')
  if not fd then
    return nil
  end
  local line = fd:read('*l')
  fd:close()
  local gitdir = line and line:match('^gitdir:%s*(.+)$')
  if not gitdir then
    return nil
  end
  if not vim.startswith(gitdir, '/') then
    gitdir = git_root .. '/' .. gitdir
  end
  return gitdir .. '/logs/HEAD'
end

-- '' = nothing to watch (no client, or a standalone .rs file). Combines
-- every attached client's root, but reload() only dispatches to one — a
-- multi-workspace reload can land on the wrong project (<leader>cw there
-- directly is the fallback).
local function current_signature()
  local clients = vim.lsp.get_clients({ name = 'rust-analyzer' })
  if #clients == 0 then
    return ''
  end
  local parts, seen_roots = {}, {}
  for _, client in ipairs(clients) do
    local root = client.config.root_dir
    if root and not seen_roots[root] then
      seen_roots[root] = true
      for _, rel in ipairs({ 'Cargo.toml', 'Cargo.lock' }) do
        local stat = vim.uv.fs_stat(root .. '/' .. rel)
        if stat then
          table.insert(parts, stat.mtime.sec .. '.' .. stat.mtime.nsec)
        end
      end
      local head_log = git_head_log_path(root)
      local head_stat = head_log and vim.uv.fs_stat(head_log)
      if head_stat then
        table.insert(parts, head_stat.mtime.sec .. '.' .. head_stat.mtime.nsec)
      end
    end
  end
  return table.concat(parts, '|')
end

-- Shared by <leader>cw and the autocmd below, so a manual reload also feeds
-- the throttle (keyed on completion, not dispatch — "5s" means 5s after the
-- last reload finished).
--
-- Neovim never times out a pending LSP request or flushes a hung server's
-- callback, so RELOAD_TIMEOUT force-resets state (+ warns) if rust-analyzer
-- hangs; `resolved` keeps the real response and the timeout mutually exclusive.
local RELOAD_TIMEOUT = 30000 -- ms; cancelled on completion, so generous costs nothing
local function reload(opts)
  opts = opts or {}
  in_flight = true
  local resolved = false
  local timer = assert(vim.uv.new_timer())
  if not opts.silent then
    vim.notify('Reloading Cargo workspace…')
  end
  local function finish(err, timed_out)
    if resolved then
      return
    end
    resolved = true
    timer:stop()
    timer:close()
    in_flight = false
    last_reload = vim.uv.now()
    if not timed_out then
      -- Only on a REAL completion — on timeout nothing was actually
      -- reloaded, so leaving last_sig stale makes the next event retry.
      last_sig = current_signature()
    end
    if timed_out then
      -- Surfaced even on the silent auto path — a hang is worth knowing about.
      vim.notify('Cargo workspace reload timed out — rust-analyzer may be unresponsive', vim.log.levels.WARN)
    elseif not opts.silent then
      vim.notify(err and tostring(err) or 'Cargo workspace reloaded', err and vim.log.levels.ERROR or vim.log.levels.INFO)
    end
  end
  -- Armed BEFORE the request call, so a synchronous throw from
  -- any_buf_request still resets in_flight instead of sticking forever.
  -- schedule_wrap keeps finish() (and its timer:close()) on the main loop,
  -- off the timer's own fast-context callback.
  timer:start(RELOAD_TIMEOUT, 0, vim.schedule_wrap(function()
    finish(nil, true)
  end))
  require('rustaceanvim.rust_analyzer').any_buf_request('rust-analyzer/reloadWorkspace', nil, function(err)
    finish(err, false)
  end)
end

-- Same events as configs.lua's checktime — leaving an embedded terminal is
-- the dominant trigger (git/cargo run there, not under FocusGained). Global,
-- not buffer-local; current_signature() no-ops when no client is attached.
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
  group = vim.api.nvim_create_augroup('UserRustReload', { clear = true }),
  desc = 'Auto-reload rust-analyzer workspace when the crate graph changed',
  callback = function()
    local sig = current_signature()
    if sig == '' then
      return -- no rust-analyzer client attached
    end
    if last_sig == '' then
      -- First observation since attach: adopt as baseline, don't reload.
      last_sig = sig
      return
    end
    if sig == last_sig or in_flight then
      return
    end
    if vim.uv.now() - last_reload < RELOAD_COOLDOWN then
      -- Cooling down; don't update last_sig so the next event past the
      -- cooldown still sees this change and fires.
      return
    end
    reload({ silent = true })
  end,
})

-- Batch-apply every machine-applicable clippy fix across the whole workspace
-- in one shot (rustc's Applicability::MachineApplicable set — ambiguous/
-- semantics-changing suggestions are skipped, same as running it by hand).
-- See plans/rustrover-nvim-parity.md §1. Fixed id 102 (see utils.lua's
-- float_terminal_action — same high-id convention as terminal.lua's bottom
-- panel, id 100); the helper also guarantees a re-press never kills a fix
-- still in progress, which matters here since --fix rewrites source files
-- on disk.
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
-- client name): lsp.lua rebinds these same keys on every attach, and more than
-- one client can attach here. rust.lua loads after
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
    -- Re-run the last runnable in the split, no picker (bang = execute_last_-
    -- runnable; falls back to the picker if nothing's run yet). Re-run, not
    -- re-show — a dismissed finished run's buffer is gone.
    -- See GUIDE.md "Run output can't be re-shown, only re-run".
    map('<leader>co', function() vim.cmd('RustLsp! run') end,
      'Rust: Re-run last runnable (no picker)')
    map('<leader>cm', function() vim.cmd.RustLsp('expandMacro') end,          'Rust: Expand macro')
    map('<leader>cC', function() vim.cmd.RustLsp('openCargo') end,            'Rust: Open Cargo.toml')
    -- Manual escape hatch: bypasses the automatic reload's gate/cooldown above.
    map('<leader>cw', function() reload({ silent = false }) end,             'Rust: Reload workspace (re-run cargo metadata)')
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
