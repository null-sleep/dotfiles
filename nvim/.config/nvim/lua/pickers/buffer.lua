-- pickers/buffer.lua — snacks buffer picker with number-jump quick-pick.
--
-- USAGE
--   require('pickers.buffer').open()        (bound to <leader>bb / <leader>m)
--
-- WHY A CUSTOM FORMAT
--   snacks' builtin `buffers` format shows vim's bufnr in the first column.
--   We want a row index there instead, since <M-1>..<M-9> jumps to row N —
--   the bufnr is then redundant noise.
--
--   The row index is item.idx (finder order), so the visible "1", "2" prefix
--   matches the rows while the prompt is empty. Filtering reorders rows but
--   keeps indices stuck to items — fine, because <M-N> is for the unfiltered
--   "open and pounce" path.
--
--   sort_lastused is disabled for stable bufnr row ordering (the MRU
--   default would reshuffle row numbers on every open and defeat the
--   muscle-memory point of <M-N>).

local common = require('pickers.common')

local M = {}

function M.open()
  local listed = #vim.tbl_filter(function(b) return vim.fn.buflisted(b) == 1 end,
    vim.api.nvim_list_bufs())
  local idx_width = math.max(1, #tostring(listed))

  -- <C-x> deletes the highlighted buffer (or all multi-selected) without
  -- closing the picker — the buffers source's own default, left in place so it
  -- matches every other delete-capable picker (scratch/marks/git branches) and
  -- keeps <C-d> as the global list-scroll. See GUIDE "Inside a picker".
  local qp_actions, qp_keys = common.quick_pick_actions()
  local keys = qp_keys

  Snacks.picker.buffers({
    sort_lastused = false,
    actions = qp_actions,
    transform = function(item)
      -- Jump to the buffer's live cursor line (info.lnum), not the `"` mark
      -- snacks defaults to: the mark is only written on unload and can point
      -- past EOF after a file shrank, which crashes the jump's
      -- nvim_win_set_cursor.
      local lnum = item.info and item.info.lnum or 0
      item.pos = lnum > 0 and { lnum, 0 } or nil
      return item
    end,
    format = function(item, picker)
      local ret = {}  ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), idx_width), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      -- icon + truncated path + :lnum (filename renders item.pos itself)
      vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
      return ret
    end,
    win = {
      input = { keys = keys },
      list = { keys = keys },
    },
  })
end

return M
