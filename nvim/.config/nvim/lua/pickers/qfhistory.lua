-- pickers/qfhistory.lua — pick a list from the quickfix / location-list
-- history stack (Neovim keeps the last 10 of each; :help :chistory).
--
-- USAGE
--   require('pickers.qfhistory').open('quickfix')   (<leader>sQ)
--   require('pickers.qfhistory').open('location')   (<leader>sL)
--
-- WHY A CUSTOM PICKER
--   Neither snacks nor Telescope has a stack overview; bare :colder/:cnewer
--   show one list at a time. This lists all N (title + size) and jumps via
--   :{nr}chistory / :{nr}lhistory. Rows are oldest-first so the index column
--   matches the nr those commands take.
--
--   Location lists are window-local, so capture the origin window at open and
--   run activate+open back in it (the picker steals focus first).

local common = require('pickers.common')

local M = {}

local SPECS = {
  quickfix = {
    label = 'Quickfix',
    get = function(q) return vim.fn.getqflist(q) end,
    hist = 'chistory',
    open = 'botright copen',
  },
  location = {
    label = 'Location-list',
    get = function(q) return vim.fn.getloclist(0, q) end,
    hist = 'lhistory',
    open = 'lopen',
  },
}

function M.open(kind)
  local spec = SPECS[kind]
  local win = vim.api.nvim_get_current_win()
  local total = spec.get({ nr = '$' }).nr
  if total == 0 then
    vim.notify(spec.label .. ' history is empty')
    return
  end
  local cur = spec.get({ nr = 0 }).nr

  return common.indexed_select({
    source = 'qf_history',
    title = spec.label .. ' history',
    finder = function()
      local items = {}
      for i = 1, total do
        local l = spec.get({ nr = i, title = 0, size = 0 })
        items[#items + 1] = {
          idx = i,             -- index column == the nr :{nr}chistory takes
          nr = i,
          size = l.size,
          current = i == cur,
          text = l.title,      -- what the fuzzy matcher sees
        }
      end
      return items
    end,
    format = function(item)
      return {
        { item.current and '● ' or '  ', 'SnacksPickerGitStatusModified' },
        { item.text ~= '' and item.text or '(untitled)', 'SnacksPickerLabel' },
        { (' (%d)'):format(item.size), 'SnacksPickerDimmed' },
      }
    end,
    confirm = function(picker, item)
      if not item then return end
      picker:close()
      -- Window-local for the loclist case; harmless for the global quickfix.
      vim.api.nvim_win_call(win, function()
        vim.cmd(item.nr .. spec.hist)   -- activate list N
        vim.cmd(spec.open)              -- show it
      end)
    end,
  })
end

return M
