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

--- Compact previewless switch-or-kill picker over a small live list: row-index
--- column, <M-1>..<M-9> quick-pick, optional <C-x> kill with in-place refresh.
--- Used by terminal.lua (select_term) and ai.lua (M.switch).
---
--- spec:
---   source, title        — passed through to Snacks.picker.pick
---   finder               — returns the items; must query live state
---                          (re-runs after every kill)
---   format(item, picker) — row chunks after the index column
---   confirm(picker, item)— <CR>; <M-N> quick-pick routes through it
---   kill(item)           — optional <C-x>; must tear down synchronously
---                          (the refresh reads post-kill state)
---   rename(picker, item) — optional <C-r>; unlike kill, owns its own refresh
---                          (it may prompt async, so close-prompt-reopen is
---                          the hook's job)
function M.indexed_select(spec)
  local qp_actions, qp_keys = M.quick_pick_actions()
  local keys = vim.tbl_extend('force', {}, qp_keys)
  local actions = qp_actions
  if spec.kill then
    actions = vim.tbl_extend('force', {
      kill_item = function(picker, item)
        if not item then return end
        spec.kill(item)
        picker:find()  -- refresh the list
      end,
    }, actions)
    -- <C-x> tears the item down (matches the buffer/scratch/marks delete key);
    -- <C-d> stays the global list-scroll.
    keys['<C-x>'] = { 'kill_item', mode = { 'i', 'n' } }
  end
  if spec.rename then
    actions = vim.tbl_extend('force', {
      rename_item = function(picker, item)
        if item then spec.rename(picker, item) end
      end,
    }, actions)
    -- nowait: snacks binds <C-r> as an insert-mode PREFIX (<C-r>%, <C-r><C-w>,
    -- ...), so a bare <C-r> here would sit out 'timeoutlen' on every press.
    -- nowait resolves it immediately, giving up those register-insert chords in
    -- this picker only — no loss in a short switch list. Snacks does the same
    -- for its own <C-r> git_restore.
    keys['<C-r>'] = { 'rename_item', mode = { 'i', 'n' }, nowait = true }
  end
  return Snacks.picker.pick({
    source = spec.source,
    title = spec.title,
    finder = spec.finder,
    format = function(item, picker)
      local ret = { { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' } }
      vim.list_extend(ret, spec.format(item, picker))
      return ret
    end,
    layout = { preset = 'select' },
    confirm = spec.confirm,
    actions = actions,
    win = {
      input = { keys = keys },
      list = { keys = keys },
    },
  })
end

return M
