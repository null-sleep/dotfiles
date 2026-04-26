-- filterpicker.lua — Telescope picker for toggling file-type filter presets.
--
-- USAGE
--   require('filterpicker').pick()   open the picker
--   require('filterpicker').get()    returns { names, globs } of enabled presets, or nil
--
-- PRESETS
--   Edit filter_sets below to add or change presets. Each entry has a name,
--   a list of ripgrep-style globs (prefix ! to exclude), and an enabled flag
--   that persists for the lifetime of the Neovim session.
--
-- HOW THE PICKER WORKS
--   Tab toggles the highlighted preset on/off without closing the picker.
--   The finder is rebuilt on each toggle so the [x]/[ ] checkboxes update
--   immediately. The cursor row is saved before the refresh and restored
--   after so it doesn't jump to row 1.
--
--   Enter confirms the current toggle state (which persists in filter_sets).
--   Esc reverts all toggles to the state they were in when the picker opened,
--   using the same need_restore / close_windows override pattern as
--   themepicker.lua.

local pickers      = require('telescope.pickers')
local finders      = require('telescope.finders')
local conf         = require('telescope.config').values
local actions      = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

-- Ordered list of presets. enabled persists across picker opens.
local filter_sets = {
  { name = 'go_src',   globs = { '*.go', '!*_test.go', '!vendor/*' }, enabled = false },
  { name = 'frontend', globs = { '*.ts', '*.tsx', '!*.test.*' },      enabled = false },
  { name = 'protos',   globs = { '*.proto' },                         enabled = false },
}

-- Compute column width once so globs align across all entries.
local max_name = 0
for _, fs in ipairs(filter_sets) do
  if #fs.name > max_name then max_name = #fs.name end
end

-- Build a fresh finder from the current state of filter_sets.
-- entry.value holds a reference to the filter_sets table entry so Tab can
-- flip .enabled directly on the source without searching by name.
local function make_finder()
  return finders.new_table({
    results = filter_sets,
    entry_maker = function(fs)
      local checkbox = fs.enabled and '[x] ' or '[ ] '
      local padding  = string.rep(' ', max_name - #fs.name + 2)
      local display  = checkbox .. fs.name .. padding .. table.concat(fs.globs, '  ')
      return {
        value   = fs,
        display = display,
        ordinal = fs.name,
      }
    end,
  })
end

-- Returns { names = {...}, globs = {...} } for all enabled presets, or nil if none.
function M.get()
  local names = {}
  local globs = {}
  for _, fs in ipairs(filter_sets) do
    if fs.enabled then
      table.insert(names, fs.name)
      for _, g in ipairs(fs.globs) do
        table.insert(globs, g)
      end
    end
  end
  if #names == 0 then return nil end
  return { names = names, globs = globs }
end

-- Opens a Telescope picker to toggle filter presets.
function M.pick()
  -- Snapshot enabled flags so Esc can revert.
  local snapshot = {}
  for i, fs in ipairs(filter_sets) do
    snapshot[i] = fs.enabled
  end
  local need_restore = true

  local picker = pickers.new({}, {
    prompt_title  = 'Filter Presets  (Tab toggle, Enter confirm, Esc revert)',
    finder        = make_finder(),
    sorter        = conf.generic_sorter({}),
    previewer       = false,
    layout_strategy = 'vertical',
    layout_config   = { width = 0.5, height = math.max(#filter_sets, 7) + 4 },  -- +4 for borders/prompt; min 7 visible rows

    attach_mappings = function(prompt_bufnr, map)
      -- Enter: persist current state and close.
      actions.select_default:replace(function()
        need_restore = false
        actions.close(prompt_bufnr)
      end)

      -- Tab: toggle the highlighted entry in-place, rebuild finder, restore row.
      local function toggle()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local p = action_state.get_current_picker(prompt_bufnr)
        local saved_row = p:get_selection_row()
        entry.value.enabled = not entry.value.enabled
        p:refresh(make_finder(), { reset_prompt = false })
        vim.schedule(function() p:set_selection(saved_row) end)
      end

      map('i', '<Tab>', toggle)
      map('n', '<Tab>', toggle)

      return true
    end,
  })

  -- Override close_windows: restore snapshot unless user confirmed with Enter.
  local orig_close_windows = picker.close_windows
  picker.close_windows = function(status)
    orig_close_windows(status)
    if need_restore then
      for i, v in ipairs(snapshot) do
        filter_sets[i].enabled = v
      end
    end
  end

  picker:find()
end

-- Wrappers that apply active filters to Telescope builtins.
-- Used by keymaps.lua so the filter logic stays in this module.

function M.find_files()
  local f = M.get()
  if f then
    -- find_command bypasses Telescope's file_ignore_patterns, so re-exclude .git/ and node_modules/ here.
    local cmd = { 'rg', '--files', '--hidden', '--glob', '!.git/', '--glob', '!node_modules/' }
    for _, g in ipairs(f.globs) do
      table.insert(cmd, '--glob')
      table.insert(cmd, g)
    end
    require('telescope.builtin').find_files({ find_command = cmd })
  else
    require('telescope.builtin').find_files()
  end
end

function M.live_grep()
  local f = M.get()
  if f then
    require('telescope.builtin').live_grep({ glob_pattern = f.globs })
  else
    require('telescope.builtin').live_grep()
  end
end

return M
