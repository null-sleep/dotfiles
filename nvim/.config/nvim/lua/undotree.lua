-- Undo tree panel (atone.nvim): a docked sidebar over the current buffer's
-- undo tree, with a live treesitter-highlighted diff of the selected node and
-- persistent, named bookmarks on states worth coming back to.
--
-- The other half of the undo story is <leader>uu (Snacks.picker.undo) — a
-- fuzzy search over the *content* of each change. The picker flattens branch
-- topology and has no marks; this shows the shape. See GUIDE.md "Undo tree
-- (atone)" and Picker -> "Undo history".
--
-- Named undotree.lua, NOT atone.lua: a wrapper file named after the module it
-- requires (require('atone')) would resolve require() back to itself and
-- recurse — the same bug that broke the earlier dropbar.nvim attempt.
vim.cmd.packadd('atone.nvim')

require('atone').setup({
  -- Left, against atone's own default of... left — stated explicitly because
  -- it's a decision, not an accepted default. The right edge is owned by the
  -- sidekick CLI (ai.lua promotes it to a full-height column via wincmd L),
  -- so the undo tree joins the left-edge swap with the file tree and outline
  -- instead. See GUIDE.md "Left-edge sidebars swap into each other".
  layout = { direction = 'left' },
  marks = {
    -- fzf-lua and telescope aren't installed, so the stock finder list
    -- ({'fzf-lua','telescope','builtin'}) just burns two failed pcalls before
    -- landing on 'builtin' — which is vim.ui.select, which snacks owns
    -- (picker.lua `ui_select = true`). The mark picker comes out as a snacks
    -- picker either way; this states that directly instead of arriving there.
    finders = { 'builtin' },
  },
  -- auto_attach keeps its defaults: excluded_ft looks redundant next to
  -- buffers.lua's registry, but atone's own BufEnter handler already gates on
  -- `buftype == ''` before consulting it, and every panel in that registry is
  -- nofile or terminal — so wiring it up would be inert config.
})

local buffers = require('buffers')

-- Only one left-edge sidebar at a time. Guarded on the panel not already
-- being visible, so this fires on the OPEN edge only — closing the undo tree
-- never reaches into the other sidebars.
--
-- Deliberately no is_special() guard (matching <leader>uu): undo history is
-- meaningful in any editable buffer.
vim.keymap.set('n', '<leader>uU', function()
  if not buffers.is_sidebar_visible('atone') then
    buffers.close_other_sidebars('atone')
  end
  vim.cmd('Atone toggle')
end, { desc = 'Utilities: Undo tree' })
