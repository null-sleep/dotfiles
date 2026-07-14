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

-- NOTE: no early `return` on dap_ok. <leader>cR (run in a terminal) has nothing
-- to do with dap, so a broken nvim-dap-go must not take it down with it — only
-- <leader>dR is gated below.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  group = vim.api.nvim_create_augroup('UserGoKeys', { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    -- Deliberately the same two keys Rust binds in rust.lua, with the same
    -- meanings: dR = pick a target and debug it, cR = pick a target and run it.
    -- require()d inside the callback so go list/the picker/toggleterm cost
    -- nothing until the key is actually pressed.
    if dap_ok then
      map('<leader>dR', function() require('pickers.gotargets').open('debug') end,
        'Debug: Go debuggables')
    else
      -- Still mapped when dap-go is broken: the startup WARN is long gone by
      -- the time the key is pressed, and a key that silently does nothing
      -- reads as a broken keymap (CLAUDE.md, "Guarding a code-only global
      -- keymap" — same principle, applied to a disabled feature).
      map('<leader>dR', function()
        vim.notify('Go debugging disabled — nvim-dap-go failed to load', vim.log.levels.WARN)
      end, 'Debug: Go debuggables (disabled)')
    end
    map('<leader>cR', function() require('pickers.gotargets').open('run') end,
      'Go: Runnables (run)')
  end,
})
