-- pickers/theme.lua — Telescope picker for live theme switching.
--
-- USAGE
--   require('pickers.theme').open()        (bound to <leader>st)
--
-- WHY A CUSTOM PICKER
--   Telescope has a built-in colorscheme picker (builtin.colorscheme with
--   enable_preview = true) that supports a custom list via opts.colors.
--   However, its preview hardcodes vim.cmd.colorscheme() in four places
--   (builtin/__internal.lua lines 1115, 1127, 1140, 1155) with no callback
--   or hook to inject custom apply logic. Our themes need the full sequence
--   in themes.apply() — packadd, background, setup(), colorscheme, overrides —
--   so the built-in picker would preview incorrectly for any theme with a
--   setup() function or background switching (roughly half of them).
--
--   This picker reuses Telescope's public API (pickers, finders, sorters,
--   actions, action_state) but replaces the apply step with themes.apply().
--   The method-override pattern below is taken from how the built-in picker
--   itself implements live preview — not a hack, but the established idiom.
--
-- MAINTENANCE
--   This relies on Telescope internals (set_selection, close_windows) that
--   are not part of the documented public API. After upgrading Telescope,
--   compare against builtin/__internal.lua's colorscheme picker to check
--   whether the method signatures or lifecycle have changed. If Telescope
--   ever adds a configurable apply callback (e.g. opts.on_preview), this
--   file can be replaced with a call to builtin.colorscheme().
--
-- HOW IT WORKS
--   Builds a sorted list of every variant name from themes.lua and shows them
--   in a Telescope picker. Live preview is achieved by overriding two methods
--   on the picker instance (the same pattern Telescope's own colorscheme picker
--   uses in builtin/__internal.lua):
--
--   picker.set_selection — called on every selection change (j/k, mouse, filter
--     narrowing). We call the original, then apply the newly selected theme via
--     themes.apply(). This is more reliable than CursorMoved autocmds because
--     it fires for all selection-change paths in one place.
--
--   picker.close_windows — called on any close (confirm, cancel, <Esc>, q).
--     A `need_restore` flag controls whether the original theme is restored:
--       <CR>  sets need_restore=false, so the previewed theme sticks and is saved.
--       Any other close path leaves need_restore=true, restoring the original.
--
--   on_complete — picker callback that fires once the initial results are
--     rendered. We apply the first selected entry here so the preview is
--     correct immediately on open (before any cursor movement).

local themes = require('themes')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

function M.open()
  -- Snapshot current state for restore-on-cancel. themes.active is the
  -- variant-level source of truth; vim.g.colors_name would be wrong here —
  -- for virtual variants it holds the underlying colorscheme (e.g. 'gruvbox'
  -- while 'gruvbox-light' is active), so cancelling would restore the dark
  -- base. No background snapshot needed: themes.apply() owns background as
  -- part of its documented sequence.
  local original = themes.active

  local variants = themes.all_variants()
  local need_restore = true

  local picker = pickers.new({}, {
    prompt_title = 'Themes',
    finder = finders.new_table({ results = variants }),
    sorter = conf.generic_sorter({}),
    layout_strategy = 'vertical',
    layout_config = { width = 0.3, height = 0.5 },

    attach_mappings = function(prompt_bufnr)
      -- <CR>: confirm — keep the previewed theme, persist it, don't restore.
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        need_restore = false
        actions.close(prompt_bufnr)
        themes.apply(entry[1])
        themes.save(entry[1])
      end)
      return true
    end,

    -- Apply the initial selection so preview is correct on open.
    on_complete = {
      function()
        local entry = action_state.get_selected_entry()
        if entry then themes.apply(entry[1]) end
      end,
    },
  })

  -- Override set_selection: apply theme on every selection change.
  local orig_set_selection = picker.set_selection
  picker.set_selection = function(self, row)
    orig_set_selection(self, row)
    local entry = action_state.get_selected_entry()
    if entry then themes.apply(entry[1]) end
  end

  -- Override close_windows: restore original theme unless user confirmed.
  local orig_close_windows = picker.close_windows
  picker.close_windows = function(status)
    orig_close_windows(status)
    if need_restore and original then
      themes.apply(original)
    end
  end

  picker:find()
end

return M
