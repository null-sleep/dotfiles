-- pickers/gitstatus.lua — Telescope git-status picker with number-jump quick-pick.
--
-- USAGE
--   require('pickers.gitstatus').open()        (bound to <leader>sm)
--
-- WHY A CUSTOM PICKER
--   Telescope's builtin.git_status shows only the XY status and path. We want
--   a row index in the first column so <M-1>..<M-9> can jump to row N, matching
--   the pattern established by pickers/buffer.lua (<leader>m).
--
-- HOW IT WORKS
--   Builds a custom picker modeled on Telescope's stock git.status
--   (telescope.nvim/lua/telescope/builtin/__git.lua, git.status function) and
--   its entry maker gen_from_git_status (telescope.nvim/lua/telescope/make_entry.lua).
--   The entry_maker prepends a row index column while keeping the rest of the
--   display (XY status icons, path) identical to stock. attach_mappings merges
--   the staging-toggle (<tab>) from the original picker with <M-1>..<M-9>
--   quick-pick bindings via common.bind_quick_pick.

local pickers       = require('telescope.pickers')
local finders       = require('telescope.finders')
local conf          = require('telescope.config').values
local entry_display = require('telescope.pickers.entry_display')
local utils         = require('telescope.utils')
local actions       = require('telescope.actions')
local action_state  = require('telescope.actions.state')
local previewers    = require('telescope.previewers')
local Path          = require('plenary.path')
local common        = require('pickers.common')

local M = {}

function M.open()
  -- Resolve git toplevel
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 or not git_root then
    vim.notify('Not a git repository', vim.log.levels.WARN)
    return
  end

  local opts = { cwd = git_root }

  -- Build the git command
  local git_cmd = { 'git', '-C', git_root, 'status', '-z', '-uall', '--', '.' }

  -- Git XY status → icon + highlight. Mirrors the git_abbrev table in
  -- telescope.nvim/lua/telescope/make_entry.lua (gen_from_git_status).
  -- If upstream icons/highlights change, update this table to match.
  local git_abbrev = {
    ['A'] = { icon = '+', hl = 'TelescopeResultsDiffAdd' },
    ['U'] = { icon = '‡', hl = 'TelescopeResultsDiffAdd' },
    ['M'] = { icon = '~', hl = 'TelescopeResultsDiffChange' },
    ['C'] = { icon = '>', hl = 'TelescopeResultsDiffChange' },
    ['R'] = { icon = '➡', hl = 'TelescopeResultsDiffChange' },
    ['D'] = { icon = '-', hl = 'TelescopeResultsDiffDelete' },
    ['?'] = { icon = '?', hl = 'TelescopeResultsDiffUntracked' },
  }

  local col_width = 2  -- single-char icon + padding

  -- Returns an entry_maker that parses raw `git status -z` lines and prepends
  -- a row index. Each call returns a fresh maker with its own counter, so the
  -- index resets when the finder is rebuilt (e.g. after staging toggle).
  local function make_indexed_entry_maker()
    local idx = 0

    local displayer = entry_display.create {
      separator = ' ',
      items = {
        { width = 2 },          -- row index
        { width = col_width },   -- staged status icon
        { width = col_width },   -- unstaged status icon
        { remaining = true },    -- path
      },
    }

    return function(entry)
      if entry == '' then return nil end

      local mod, file = entry:match('^(..) (.+)$')
      if not mod then return nil end

      idx = idx + 1
      local n = idx

      return {
        value   = file,
        status  = mod,
        ordinal = entry,
        path    = Path:new({ git_root, file }):absolute(),
        display = function(e)
          local x = string.sub(e.status, 1, 1)
          local y = string.sub(e.status, -1)
          local status_x = git_abbrev[x] or {}
          local status_y = git_abbrev[y] or {}

          local display_path, path_style = utils.transform_path(opts, e.path)

          local empty = ' '
          return displayer {
            { tostring(n), 'TelescopeResultsNumber' },
            { status_x.icon or empty, status_x.hl },
            { status_y.icon or empty, status_y.hl },
            { display_path, function() return path_style end },
          }
        end,
      }
    end
  end

  -- Creates a oneshot finder that runs `git status` and feeds results through
  -- the indexed entry maker. Called on initial open and again after each
  -- staging toggle to refresh the list.
  local function gen_new_finder()
    return finders.new_oneshot_job(git_cmd, {
      entry_maker = make_indexed_entry_maker(),
      cwd         = git_root,
      split_char  = '\0',
    })
  end

  local initial_finder = gen_new_finder()
  if not initial_finder then return end

  pickers
    .new(opts, {
      prompt_title  = 'Git Status',
      finder        = initial_finder,
      previewer     = previewers.git_file_diff.new(opts),
      sorter        = conf.file_sorter(opts),
      on_complete   = {
        function(self)
          local prompt = action_state.get_current_line()
          local count = 0
          for _, entry in pairs(self.finder.results) do
            if entry and entry.valid ~= false then
              count = count + 1
            end
          end
          if count == 0 and prompt == '' then
            vim.notify('No changes found', vim.log.levels.INFO)
          end
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        -- Staging toggle: stages/unstages the selected file, then rebuilds
        -- the finder to reflect the new status while preserving cursor position.
        actions.git_staging_toggle:enhance {
          post = function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local selection = picker:get_selection_row()
            local callbacks = { unpack(picker._completion_callbacks) }
            picker:register_completion_callback(function(self)
              self:set_selection(selection)
              self._completion_callbacks = callbacks
            end)
            picker:refresh(gen_new_finder(), { reset_prompt = false })
          end,
        }
        map({ 'i', 'n' }, '<tab>', actions.git_staging_toggle)

        -- Number quick-pick: <M-N> jumps to row N and opens the file.
        common.bind_quick_pick(map)

        return true
      end,
    })
    :find()
end

return M
