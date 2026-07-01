-- nvim-dap + nvim-dap-ui: the debug engine and its docked UI (scopes, call stack,
-- breakpoints, watches, REPL).
--
-- Named debugging.lua deliberately: NOT dap.lua (would shadow the plugin's
-- require('dap')) and NOT debug.lua (Lua's stdlib pre-populates
-- package.loaded.debug, so require('debug') returns the C debug library, never
-- this file). Same rationale as linting.lua-not-lint.lua.
--
-- Rust adapter/configurations are provided by rustaceanvim (lua/rust.lua), so this
-- module only wires the generic engine + UI + keymaps. A Rust debug session is
-- STARTED via <leader>dR (debuggables), the Debug codelens (grx), or <leader>nd
-- (debug nearest test); the keymaps below then drive the running session.

vim.cmd.packadd('nvim-nio')
vim.cmd.packadd('nvim-dap')
vim.cmd.packadd('nvim-dap-ui')

local dap, dapui = require('dap'), require('dapui')

dapui.setup()

-- Auto open/close the UI with the debug session. dap.listeners.before[event]
-- auto-vivifies the subtable; the `.dapui` key just namespaces our listener.
for _, event in ipairs({ 'launch', 'attach' }) do
  dap.listeners.before[event].dapui = function() dapui.open() end
end
for _, event in ipairs({ 'event_terminated', 'event_exited' }) do
  dap.listeners.before[event].dapui = function() dapui.close() end
end

-- Breakpoint / stopped-line signs (reuse theme-styled diagnostic highlights).
vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError' })
vim.fn.sign_define('DapStopped',    { text = '▶', texthl = 'DiagnosticWarn', linehl = 'Visual' })

local map = vim.keymap.set

-- <leader>d = Debug group (registered in whichkey.lua)
map('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug: Toggle breakpoint' })
map('n', '<leader>dB', function() dap.set_breakpoint(vim.fn.input('Condition: ')) end, { desc = 'Debug: Conditional breakpoint' })
map('n', '<leader>dc', dap.continue,  { desc = 'Debug: Continue / start' })
map('n', '<leader>di', dap.step_into, { desc = 'Debug: Step into' })
map('n', '<leader>do', dap.step_over, { desc = 'Debug: Step over' })
map('n', '<leader>dO', dap.step_out,  { desc = 'Debug: Step out' })
map('n', '<leader>dl', dap.run_last,  { desc = 'Debug: Run last' })
map('n', '<leader>dq', dap.terminate, { desc = 'Debug: Terminate' })
map('n', '<leader>dr', function() dap.repl.toggle() end, { desc = 'Debug: Toggle REPL' })
map('n', '<leader>du', function() dapui.toggle() end,    { desc = 'Debug: Toggle UI' })
map({ 'n', 'v' }, '<leader>de', function() dapui.eval() end, { desc = 'Debug: Eval expression' })

-- VS Code-style function keys (universal debugger muscle memory)
map('n', '<F5>',  dap.continue,         { desc = 'Debug: Continue' })
map('n', '<F9>',  dap.toggle_breakpoint,{ desc = 'Debug: Toggle breakpoint' })
map('n', '<F10>', dap.step_over,        { desc = 'Debug: Step over' })
map('n', '<F11>', dap.step_into,        { desc = 'Debug: Step into' })
map('n', '<F12>', dap.step_out,         { desc = 'Debug: Step out' })
