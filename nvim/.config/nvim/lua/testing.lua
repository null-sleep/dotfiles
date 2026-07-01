-- neotest: test runner UI. Set up as an extensible framework — Rust now via
-- rustaceanvim's adapter, other languages added by dropping an adapter into the
-- list below (+ its plugin in plugins.lua + the treesitter parser).
--
-- Named testing.lua to avoid shadowing require('neotest'). Requires rustaceanvim
-- to be packadd'd first (lua/rust.lua, required before this in init.lua) so
-- require('rustaceanvim.neotest') is on the runtimepath.

vim.cmd.packadd('nvim-nio')       -- idempotent if debugging.lua already packadd'd it
vim.cmd.packadd('plenary.nvim')
vim.cmd.packadd('neotest')

require('neotest').setup({
  adapters = {
    -- Rust: reuses rust-analyzer runnables + integrates with nvim-dap for debugging.
    require('rustaceanvim.neotest'),
    -- Add more later (each needs its plugin in plugins.lua + a treesitter parser):
    --   require('neotest-golang'),
    --   require('neotest-python'),
  },
})

-- Lazy handle: require('neotest') is cheap after setup, but wrapping keeps the
-- keymap rhs from capturing a stale module reference.
local nt = function() return require('neotest') end
local map = vim.keymap.set

-- <leader>n = Test group (registered in whichkey.lua)
map('n', '<leader>nn', function() nt().run.run() end,                     { desc = 'Test: Run nearest' })
map('n', '<leader>nf', function() nt().run.run(vim.fn.expand('%')) end,   { desc = 'Test: Run file' })
map('n', '<leader>nl', function() nt().run.run_last() end,                { desc = 'Test: Run last' })
map('n', '<leader>nd', function() nt().run.run({ strategy = 'dap' }) end, { desc = 'Test: Debug nearest' })
map('n', '<leader>nS', function() nt().run.stop() end,                    { desc = 'Test: Stop' })
map('n', '<leader>ns', function() nt().summary.toggle() end,             { desc = 'Test: Toggle summary' })
map('n', '<leader>no', function() nt().output.open({ enter = true }) end, { desc = 'Test: Show output' })
map('n', '<leader>nO', function() nt().output_panel.toggle() end,         { desc = 'Test: Toggle output panel' })
