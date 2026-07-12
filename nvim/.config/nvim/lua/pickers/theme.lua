-- pickers/theme.lua — snacks picker for live theme switching.
--
-- USAGE
--   require('pickers.theme').open()        (bound to <leader>st)
--
-- WHY A CUSTOM PICKER
--   snacks has a built-in colorschemes picker with live preview, but its
--   preview/confirm hardcode vim.cmd.colorscheme() (picker/source/vim.lua +
--   preview.lua). Our themes need the full sequence in themes.apply() —
--   packadd, background, setup(), colorscheme, overrides — so the built-in
--   would preview incorrectly for any theme with a setup() function or
--   background switching (roughly half of them).
--
-- HOW IT WORKS
--   Unlike the telescope version this replaced (which overrode the
--   undocumented set_selection/close_windows picker internals), everything
--   here is public snacks API:
--
--   on_change — fires on every cursor/selection change, including the
--     initial selection when the list first renders, so the preview is
--     correct immediately on open. Applies the highlighted theme live.
--     item can be nil (list filtered down to nothing) — guarded.
--
--   confirm — <CR>: flip need_restore *before* closing (on_close reads it),
--     apply and persist the chosen theme.
--
--   on_close — fires on every close path (cancel, <Esc>, q, focus loss):
--     restores the snapshot taken at open time unless confirm ran.

local themes = require('themes')

local M = {}

function M.open()
  -- Snapshot current state for restore-on-cancel. themes.active is the
  -- variant-level source of truth; vim.g.colors_name would be wrong here —
  -- for virtual variants it holds the underlying colorscheme (e.g. 'gruvbox'
  -- while 'gruvbox-light' is active), so cancelling would restore the dark
  -- base. No background snapshot needed: themes.apply() owns background as
  -- part of its documented sequence.
  local original = themes.active
  local need_restore = true

  return Snacks.picker.pick({
    source = 'themes',
    title = 'Themes',
    items = vim.tbl_map(function(v) return { text = v } end, themes.all_variants()),
    format = 'text',
    -- Compact centered list, no preview pane (the whole UI is the preview).
    layout = { preset = 'select' },
    on_change = function(_, item)
      if item then themes.apply(item.text) end
    end,
    confirm = function(picker, item)
      if not item then return end
      need_restore = false
      picker:close()
      themes.apply(item.text)
      themes.save(item.text)
    end,
    on_close = function()
      if need_restore and original then
        themes.apply(original)
      end
    end,
  })
end

return M
