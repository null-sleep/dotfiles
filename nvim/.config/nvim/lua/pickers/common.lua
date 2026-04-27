-- pickers/common.lua — shared utilities for custom Telescope pickers.

local actions      = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

--- Bind <M-1>..<M-9> quick-pick keys inside attach_mappings.
--- Each <M-N> jumps to row N and immediately opens it.
---
--- @param map function  the `map` arg from attach_mappings(prompt_bufnr, map)
function M.bind_quick_pick(map)
  for i = 1, 9 do
    map({ 'i', 'n' }, '<M-' .. i .. '>', function(prompt_bufnr)
      action_state.get_current_picker(prompt_bufnr):set_selection(i - 1)
      actions.select_default(prompt_bufnr)
    end)
  end
end

return M
