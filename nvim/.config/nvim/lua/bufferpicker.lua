-- bufferpicker.lua — Telescope picker for buffers with number-jump quick-pick.
--
-- USAGE
--   require('bufferpicker').open()        (bound to <leader>m)
--
-- WHY A CUSTOM PICKER
--   Telescope's builtin.buffers shows vim's bufnr in the first column. We
--   want a row index there instead, since <M-1>..<M-9> jumps to row N — the
--   bufnr is then redundant noise. We also want flag/icon/path columns to
--   match the default look so the picker stays familiar.
--
-- HOW IT WORKS
--   Calls builtin.buffers with a custom entry_maker. The entry data is built
--   by telescope's own gen_from_buffer (so default open/delete/preview
--   actions still work), but entry.display is replaced with a 4-column
--   displayer: row idx | flags | icon | path:lnum. attach_mappings binds
--   <M-1>..<M-9> to set_selection + select_default for that row.
--
--   The row index is captured at finder build time, so the visible "1", "2"
--   prefix matches the initial row order. Filtering reorders rows but keeps
--   indices stuck to entries — fine, because <M-N> is for the unfiltered
--   "open and pounce" path.

local M = {}

function M.open()
  local builtin       = require('telescope.builtin')
  local make_entry    = require('telescope.make_entry')
  local entry_display = require('telescope.pickers.entry_display')
  local utils         = require('telescope.utils')
  local strings       = require('plenary.strings')
  local actions       = require('telescope.actions')
  local action_state  = require('telescope.actions.state')

  -- Icon column width: match telescope's default behaviour by sampling a
  -- representative devicon.
  local icon_w = 0
  local sample = utils.get_devicons('fname', false)
  if sample then icon_w = strings.strdisplaywidth(sample) end

  local listed = vim.tbl_filter(function(b) return vim.fn.buflisted(b) == 1 end,
    vim.api.nvim_list_bufs())
  local idx_width = math.max(1, #tostring(#listed))

  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = idx_width },  -- row index (replaces bufnr)
      { width = icon_w },     -- filetype icon
      { remaining = true },   -- path:lnum
    },
  }

  -- bufnr_width must be non-nil for gen_from_buffer's internal displayer to
  -- construct successfully, even though we never call its display function.
  local base = make_entry.gen_from_buffer({ bufnr_width = idx_width })
  local idx = 0

  builtin.buffers({
    layout_config = { height = 0.4 },
    entry_maker = function(buf)
      idx = idx + 1
      local entry = base(buf)
      if not entry then return nil end
      local n = idx
      entry.display = function(e)
        local name = e.filename or '[No Name]'
        local path_style
        if e.filename then
          name, path_style = utils.transform_path({}, e.filename)
        end
        if e.lnum and e.lnum > 0 then
          name = name .. ':' .. e.lnum
        end
        local icon, hl = utils.get_devicons(e.filename or '', false)
        return displayer {
          { tostring(n), 'TelescopeResultsNumber' },
          { icon, hl },
          { name, function() return path_style end },
        }
      end
      return entry
    end,
    attach_mappings = function(_, map)
      local function pick(n)
        return function(prompt_bufnr)
          action_state.get_current_picker(prompt_bufnr):set_selection(n - 1)
          actions.select_default(prompt_bufnr)
        end
      end
      for i = 1, 9 do
        map({ 'i', 'n' }, '<M-' .. i .. '>', pick(i))
      end
      return true
    end,
  })
end

return M
