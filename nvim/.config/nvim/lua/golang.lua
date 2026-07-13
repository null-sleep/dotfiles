-- golang.lua — Go's language module: the delve adapter registration plus the
-- buffer-local Go keymaps. The mirror of rust.lua (which owns rustaceanvim +
-- the Rust ft keymaps), so debugging.lua can stay a generic engine.
--
-- Named golang.lua, NOT go.lua: `require('go')` is ray-x/go.nvim's module name,
-- and that plugin is a live follow-up (plans/go-run-debug-test.md). Same rule as
-- debugging.lua-not-dap.lua. Editing/formatting/linting for Go stay where they
-- are (gopls in lsp.lua, goimports in format.lua, golangci-lint in linting.lua).

-- Go's adapter: registers dap.adapters.go + 7 dap.configurations.go for the `go`
-- filetype, which is what makes a cold-start <F5>/<leader>dc work in a Go buffer.
--
-- Guarded, unlike the core packadds in debugging.lua: nvim-dap-go publishes no
-- git tags, so it tracks main and can break under us. This file is require()d
-- from init.lua with no pcall around it, so an uncaught error here would abort
-- every module after it — a broken Go plugin must not cost you Rust debugging,
-- testing.lua, or half the config.
local dap_ok = pcall(function()
  vim.cmd.packadd('nvim-dap-go')
  require('dap-go').setup()
end)

if not dap_ok then
  vim.notify('nvim-dap-go failed to load — Go debugging disabled', vim.log.levels.WARN)
end

-- NOTE: no early `return` on dap_ok. The autocmd below must still register
-- regardless of whether dap-go loaded; only the dap-dependent keymap is gated
-- on dap_ok.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  group = vim.api.nvim_create_augroup('UserGoDebug', { clear = true }),
  callback = function(ev)
    if dap_ok then
      -- <leader>dR in a Go buffer = "start a debug session by picking one", the
      -- same thing the key means in a Rust buffer (rust.lua maps it to
      -- rustaceanvim's debuggables). Go has no target provider, so here it's
      -- just dap.continue(): with no session running that opens the
      -- launch-config picker (via vim.ui.select -> snacks). Identical to
      -- <F5>/<leader>dc — it exists so the "pick something to debug" muscle
      -- memory carries across languages instead of being a Rust-only habit.
      -- Buffer-local, like Rust's, so the key stays free elsewhere.
      vim.keymap.set('n', '<leader>dR', function() require('dap').continue() end,
        { buffer = ev.buf, desc = 'Debug: Go launch configs (picker)' })
    end
  end,
})
