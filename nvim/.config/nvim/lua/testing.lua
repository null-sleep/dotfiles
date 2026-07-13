-- neotest: test runner UI. Set up as an extensible framework — Rust via
-- rustaceanvim's adapter, Go via neotest-golang, other languages added by
-- dropping an adapter into the list below (+ its plugin in plugins.lua + the
-- treesitter parser).
--
-- Named testing.lua to avoid shadowing require('neotest'). Requires rustaceanvim
-- to be packadd'd first (lua/rust.lua, required before this in init.lua) so
-- require('rustaceanvim.neotest') is on the runtimepath.

vim.cmd.packadd('nvim-nio')       -- idempotent if debugging.lua already packadd'd it
vim.cmd.packadd('plenary.nvim')   -- neotest-golang require()s plenary.scandir at load
vim.cmd.packadd('neotest')

local adapters = {
  -- Rust: reuses rust-analyzer runnables + integrates with nvim-dap for debugging.
  require('rustaceanvim.neotest'),
  -- Add more later (each needs its plugin in plugins.lua + a treesitter parser):
  --   require('neotest-python'),
}

-- Go, guarded: neotest-golang is a third-party adapter, and an error while
-- constructing it would propagate out of require('testing') in init.lua and take
-- down neotest entirely (Rust tests included) plus every module loaded after it.
local ok_go, go_adapter = pcall(function()
  vim.cmd.packadd('neotest-golang')
  return require('neotest-golang')({
    runner = 'gotestsum',
    -- dap_mode 'manual' is LOAD-BEARING, not a preference. The default
    -- ('dap-go') re-runs dap-go.setup() on every test debug — and dap-go's
    -- setup APPENDS its 7 configs instead of replacing them, so each debugged
    -- test would permanently grow the <F5> picker by 14 stale entries.
    -- 'manual' makes neotest build its own config and never touch dap-go.
    dap_mode = 'manual',
    -- A FUNCTION, not a table: neotest-golang mutates whatever this returns
    -- (sets .program, table.inserts '-test.run <regex>' into .args). A table
    -- literal here would be that same shared table on every run, so the
    -- -test.run filters would pile up across debug sessions and a stale filter
    -- would silently debug the previous test. A fresh table per call avoids it.
    -- neotest injects program/args/cwd itself.
    dap_manual_config = function()
      return {
        name = 'Neotest Go',
        type = 'go',            -- the adapter dap-go registered in debugging.lua
        request = 'launch',
        mode = 'test',          -- dlv test-binary mode
        -- Without this, the debuggee's stdout (t.Log, fmt.Println) never reaches
        -- dap's output: delve defaults to local mode, and a detached server
        -- adapter can't forward it. dap-go sets 'remote' on all of its own configs.
        outputMode = 'remote',
      }
    end,
  })
end)

if ok_go then
  table.insert(adapters, go_adapter)
else
  vim.notify('neotest-golang failed to load — Go tests disabled', vim.log.levels.WARN)
end

require('neotest').setup({ adapters = adapters })

-- Lazy handle: require('neotest') is cheap after setup, but wrapping keeps the
-- keymap rhs from capturing a stale module reference.
local nt = function() return require('neotest') end
local map = vim.keymap.set

-- <leader>n = Test group (registered in whichkey.lua)
map('n', '<leader>nn', function() nt().run.run() end,                     { desc = 'Test: Run nearest' })
map('n', '<leader>nf', function() nt().run.run(vim.fn.expand('%')) end,   { desc = 'Test: Run file' })
map('n', '<leader>nl', function() nt().run.run_last() end,                { desc = 'Test: Run last' })
map('n', '<leader>nd', function() nt().run.run({ strategy = 'dap' }) end, { desc = 'Test: Debug nearest' })
map('n', '<leader>nq', function() nt().run.stop() end,                    { desc = 'Test: Stop' })
map('n', '<leader>ns', function() nt().summary.toggle() end,             { desc = 'Test: Toggle summary' })
map('n', '<leader>no', function() nt().output.open({ enter = true }) end, { desc = 'Test: Show output' })
map('n', '<leader>nO', function() nt().output_panel.toggle() end,         { desc = 'Test: Toggle output panel' })
