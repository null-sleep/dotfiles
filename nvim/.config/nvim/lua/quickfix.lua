-- quickfix.lua — quicker.nvim: an editable, better-styled quickfix/loclist
-- window. The <leader>tq/<leader>tl toggles (keymaps.lua) route through it;
-- browsing/filtering still goes through the snacks pickers (<leader>sq/<leader>sQ,
-- see picker.lua / pickers/qfhistory.lua). See GUIDE.md "Quickfix & location lists".
--
-- Editable buffer (edit.enabled): the window is modifiable — edit an item's
-- text + :w writes the change back to the source file (a visual :cdo).
-- autosave = 'unmodified' auto-writes a touched file only when it has no
-- unsaved changes elsewhere, so a bulk edit never clobbers a buffer you're
-- mid-edit in.
--
-- Named quickfix.lua, not quicker.lua, so require('quicker') below resolves to
-- the plugin and not back to this module (house convention; cf. filetree.lua).

vim.cmd.packadd('quicker.nvim')

-- One-gesture entry deletion. quicker maps each list line to its qf item via an
-- extmark; deleting the line(s) and writing drops those entries (its BufWriteCmd
-- reconciles — no file is touched). This bundles the documented `dd` + `:w` into
-- a single keystroke. Normal: the current line; visual: the selected range.
local function delete_entries()
  local m = vim.fn.mode()
  local a, b
  if m == 'v' or m == 'V' or m == '\22' then
    a, b = vim.fn.line('v'), vim.fn.line('.')
    if a > b then a, b = b, a end
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)  -- leave visual before mutating
  else
    a = vim.fn.line('.')
    b = math.min(a + vim.v.count1 - 1, vim.fn.line('$'))  -- honor a count (2dd)
  end
  vim.api.nvim_buf_set_lines(0, a - 1, b, false, {})
  vim.cmd('silent write')
end

require('quicker').setup({
  edit = {
    enabled = true,
    autosave = 'unmodified',
  },
  -- Keep the list's highlight synced to the cursor's nearest entry (and scroll
  -- it into view), so the window shows where you are in the result set.
  follow = { enabled = true },
  -- Buffer-local to the quicker window.
  keys = {
    -- >/< show/hide N context lines around each match, so you can review
    -- results without jumping out of the list.
    {
      '>',
      function() require('quicker').expand({ before = 2, after = 2, add_to_existing = true }) end,
      desc = 'Expand quickfix context',
    },
    {
      '<',
      function() require('quicker').collapse() end,
      desc = 'Collapse quickfix context',
    },
    -- dd / visual d prune entries from the list (see delete_entries above).
    { 'dd', delete_entries, desc = 'Delete quickfix entry' },
    { 'd', delete_entries, mode = 'x', desc = 'Delete quickfix entries' },
  },
})
