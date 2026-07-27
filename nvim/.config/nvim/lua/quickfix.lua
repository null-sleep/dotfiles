-- quickfix.lua — quicker.nvim: an editable, better-styled quickfix/loclist
-- window. The <leader>tq/<leader>tl toggles (keymaps.lua) route through it;
-- browsing/filtering still goes through the snacks pickers (<leader>sq/<leader>sQ,
-- see picker.lua / pickers/qfhistory.lua). See GUIDE.md "Quickfix & location lists".
--
-- Editable buffer (edit.enabled): the window is modifiable — delete a line + :w
-- prunes that entry from the list (no file touched); edit an item's text + :w
-- writes the change back to the source file (a visual :cdo). autosave =
-- 'unmodified' auto-writes a touched file only when it has no unsaved changes
-- elsewhere, so a bulk edit never clobbers a buffer you're mid-edit in.
--
-- Named quickfix.lua, not quicker.lua, so require('quicker') below resolves to
-- the plugin and not back to this module (house convention; cf. filetree.lua).

vim.cmd.packadd('quicker.nvim')

require('quicker').setup({
  edit = {
    enabled = true,
    autosave = 'unmodified',
  },
  -- Buffer-local to the qf window: >/< show/hide N context lines around each
  -- match, so you can review results without jumping out of the list.
  keys = {
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
  },
})
