-- pickers/common.lua — shared utilities for custom pickers.

local M = {}

--- <M-1>..<M-9> quick-pick for snacks pickers: each <M-N> moves to display
--- row N and immediately confirms it. Returns two table fragments to merge
--- into a picker spec: `actions` (named quick_pick_N actions) and `keys`
--- (for win.input.keys / win.list.keys).
---
--- Row N is the Nth *display* row — matches the visible index column while
--- the prompt is empty (finder order); after filtering the indices stay
--- stuck to their items, so quick-pick is for the "open and pounce" path.
--- Note: picker.list:view() is 1-indexed (telescope's set_selection was 0-indexed).
function M.quick_pick_actions()
  local actions, keys = {}, {}
  for i = 1, 9 do
    local name = 'quick_pick_' .. i
    actions[name] = function(picker)
      picker.list:view(i)
      picker:action('confirm')
    end
    keys[('<M-%d>'):format(i)] = { name, mode = { 'i', 'n' } }
  end
  return actions, keys
end

--- Telescope variant of the above, bound inside attach_mappings.
--- Still used by pickers/gitstatus.lua until its snacks port lands; removed
--- together with telescope at the end of the migration
--- (plans/telescope-vs-snacks-picker.md).
---
--- @param map function  the `map` arg from attach_mappings(prompt_bufnr, map)
function M.bind_quick_pick(map)
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  for i = 1, 9 do
    map({ 'i', 'n' }, '<M-' .. i .. '>', function(prompt_bufnr)
      action_state.get_current_picker(prompt_bufnr):set_selection(i - 1)
      actions.select_default(prompt_bufnr)
    end)
  end
end

return M
