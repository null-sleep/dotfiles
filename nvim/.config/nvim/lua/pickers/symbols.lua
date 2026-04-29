-- pickers/symbols.lua — workspace symbol picker scoped to project root.
--
-- lua_ls + lazydev return library symbols (neovim runtime, mason-installed Lua
-- libs) in workspace/symbol responses, drowning project symbols. When lua_ls is
-- attached, restrict results to files under cwd; other LSPs already scope
-- correctly to the workspace, so the filter is a no-op for them.

local builtin = require('telescope.builtin')

local M = {}

function M.workspace()
  if #vim.lsp.get_clients({ name = 'lua_ls' }) == 0 then
    builtin.lsp_dynamic_workspace_symbols()
    return
  end
  local cwd = vim.uv.cwd()
  local base = require('telescope.make_entry').gen_from_lsp_symbols({})
  builtin.lsp_dynamic_workspace_symbols({
    entry_maker = function(item)
      local entry = base(item)
      if not entry or not entry.filename then return nil end
      if not vim.startswith(entry.filename, cwd) then return nil end
      return entry
    end,
  })
end

return M
