-- Undo tree panel (atone.nvim): docked sidebar over the buffer's undo tree,
-- with a live treesitter diff of the selected node and persistent marks. The
-- other half is <leader>uu (Snacks.picker.undo), which searches change
-- *content* but flattens the tree. See GUIDE.md "Undo tree (atone)".
--
-- Named undotree.lua, NOT atone.lua: a wrapper named after the module it
-- requires resolves require() back to itself and recurses (the dropbar.nvim
-- bug).
vim.cmd.packadd('atone.nvim')

require('atone').setup({
  -- atone's own default, stated because it's a decision: the right edge
  -- belongs to the sidekick CLI (ai.lua promotes it to a full-height column),
  -- so the undo tree joins the left-edge swap instead.
  layout = { direction = 'left' },
  -- Stock list is {'fzf-lua','telescope','builtin'}; we run neither of the
  -- first two, so it burns two failed pcalls to reach 'builtin' — which is
  -- vim.ui.select, which snacks owns (picker.lua `ui_select = true`). Same
  -- snacks mark picker either way; this just skips the detour.
  marks = { finders = { 'builtin' } },
  -- auto_attach keeps its defaults. excluded_ft looks like it wants
  -- buffers.lua's registry, but atone's BufEnter gates on `buftype == ''`
  -- first and every panel there is nofile or terminal — so it'd be inert.
})

-- Only one left-edge sidebar at a time; fires on the OPEN edge only. No
-- is_special() guard, matching <leader>uu: undo history is meaningful in any
-- editable buffer.
local buffers = require('buffers')
vim.keymap.set('n', '<leader>uU', function()
  if not buffers.is_sidebar_visible('atone') then
    buffers.close_other_sidebars('atone')
  end
  vim.cmd('Atone toggle')
end, { desc = 'Utilities: Undo tree' })
