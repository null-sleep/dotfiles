-- Structural (tree-sitter) selection — Helix-style expand/shrink selection.
-- <M-o> grows the visual selection to the smallest syntax node that STRICTLY
-- contains it (climbing the tree); <M-i> shrinks back to the previous node.
-- The nvim-treesitter `main`-branch rewrite removed the built-in
-- incremental_selection module, so this is a small self-contained reimpl on top
-- of the core `vim.treesitter` API (no extra plugin).
--
-- State: a buffer-local stack of node ranges (b:structural_select_stack). Grow
-- pushes the newly selected range; shrink pops back. The stack resets whenever a
-- grow starts from a selection that doesn't match the stack top (fresh selection
-- or the cursor moved elsewhere), so it can never go stale.

local M = {}

local STACK = 'structural_select_stack'

-- TS ranges are {start_row, start_col, end_row, end_col}: 0-indexed rows,
-- 0-indexed byte cols, exclusive end col.

local function ranges_equal(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

-- True when `outer` contains `inner` and is strictly larger.
local function strictly_contains(outer, inner)
  local starts_before = outer[1] < inner[1] or (outer[1] == inner[1] and outer[2] <= inner[2])
  local ends_after    = outer[3] > inner[3] or (outer[3] == inner[3] and outer[4] >= inner[4])
  return starts_before and ends_after and not ranges_equal(outer, inner)
end

-- Current selection as a 0-indexed, end-exclusive TS range. Visual mode reads
-- the live endpoints ('v' = the other end, '.' = cursor); normal mode returns a
-- zero-width range at the cursor so a fresh grow selects the node under it.
local function current_range()
  if vim.fn.mode():match('[vV\22]') then  -- v / V / <C-v> (\22 = 0x16)
    local s = vim.fn.getpos('v')  -- {bufnr, lnum(1), col(1), off}
    local e = vim.fn.getpos('.')
    local sr, sc = s[2] - 1, s[3] - 1
    local er, ec = e[2] - 1, e[3] - 1
    if sr > er or (sr == er and sc > ec) then  -- normalize start <= end
      sr, sc, er, ec = er, ec, sr, sc
    end
    return { sr, sc, er, ec + 1 }  -- inclusive mark col -> exclusive TS col
  end
  local c = vim.api.nvim_win_get_cursor(0)  -- {lnum(1), col(0)}
  return { c[1] - 1, c[2], c[1] - 1, c[2] }
end

-- Set the charwise visual selection to a 0-indexed, end-exclusive TS range.
-- We drive getpos('v')/getpos('.') rather than the '<'/'>' marks, so a
-- <Cmd>-style callback (which never updates those marks) is fine.
local function select_range(range)
  local sr, sc, er, ec = range[1], range[2], range[3], range[4]
  local end_row, end_col
  if ec == 0 then
    -- Selection ends at column 0 -> last byte is the end of the previous line.
    end_row = er - 1
    local prev = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ''
    end_col = math.max(#prev - 1, 0)
  else
    end_row, end_col = er, ec - 1  -- exclusive end col -> inclusive cursor col
  end
  if vim.fn.mode():match('[vV\22]') then
    vim.cmd('normal! \27')  -- <Esc>: start from a clean charwise selection
  end
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
end

-- Grow: select the smallest node strictly containing the current selection.
function M.grow()
  if not pcall(vim.treesitter.get_parser, 0) then return end  -- no parser -> no-op

  local cur = current_range()
  local stack = vim.b[STACK]
  if not stack or #stack == 0 or not ranges_equal(stack[#stack], cur) then
    stack = { cur }  -- fresh / stale selection -> reset the stack to this base
  end
  cur = stack[#stack]

  local node = vim.treesitter.get_node({ bufnr = 0, pos = { cur[1], cur[2] } })
  while node and not strictly_contains({ node:range() }, cur) do
    node = node:parent()
  end
  if not node then return end  -- already at the outermost node -> clamp

  local nr = { node:range() }
  table.insert(stack, nr)
  vim.b[STACK] = stack
  select_range(nr)
end

-- Shrink: pop the stack and reselect the previous range.
function M.shrink()
  local stack = vim.b[STACK]
  if not stack or #stack <= 1 then return end  -- at/below the initial selection
  table.remove(stack)
  vim.b[STACK] = stack
  local prev = stack[#stack]
  if prev[1] == prev[3] and prev[2] == prev[4] then
    -- Base was a bare cursor (grow started from normal mode) -> leave visual mode.
    if vim.fn.mode():match('[vV\22]') then vim.cmd('normal! \27') end
    vim.api.nvim_win_set_cursor(0, { prev[1] + 1, prev[2] })
  else
    select_range(prev)
  end
end

-- <M-o>/<M-i> in normal and visual mode. Grow from normal mode starts a
-- selection. which-key ignores <M-…> (see whichkey.lua's trigger list), so no
-- registration is needed. Uses `x` (visual, not select) mode like keymaps.lua.
vim.keymap.set({ 'n', 'x' }, '<M-o>', M.grow,   { desc = 'Structural select: grow' })
vim.keymap.set({ 'n', 'x' }, '<M-i>', M.shrink, { desc = 'Structural select: shrink' })

return M
