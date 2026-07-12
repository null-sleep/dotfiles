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
--- Note: picker.list:view() is 1-indexed.
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

return M
