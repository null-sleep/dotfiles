-- keypicker.lua — Telescope picker for fuzzy-searching all keybindings.
--
-- Walks the which-key internal tree to build a flat, searchable list of leaf
-- keybindings. Group labels from ancestor nodes and custom keywords (from
-- whichkey.lua) are included in the search text but not the display.
--
-- Results are computed once on first open and cached for the session.

local pickers      = require('telescope.pickers')
local finders      = require('telescope.finders')
local conf         = require('telescope.config').values
local actions      = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

-- Build group breadcrumb by walking parent chain.
-- Returns e.g. "Search" for <leader>sg, "Session/Quit" for <leader>qs.
local function breadcrumb(node)
  local parts = {}
  local n = node.parent
  while n and n.keys ~= '' do
    if n.mapping and n.mapping.group and n.mapping.desc then
      table.insert(parts, 1, n.mapping.desc)
    end
    n = n.parent
  end
  return table.concat(parts, ' > ')
end

-- Cache: computed once on first open, reused for the session.
local cached_results

local function build_results()
  -- update = true forces a fresh tree rebuild (matches what <leader>? does
  -- internally) so we get all keymaps, not a potentially stale cache.
  local mode = require('which-key.buf').get({ mode = 'n', update = true })
  if not mode then return nil end

  local keywords = require('whichkey').keywords or {}
  local results = {}

  local seen = {}  -- track lhs to deduplicate across sources (case-sensitive)

  -- `return false` prunes the subtree; bare `return` skips just this node
  -- but continues into children.
  mode.tree:walk(function(node)
    if node.hidden then return false end
    local desc = node.desc or ''
    if not node.keymap and desc == '' then return end
    if node.mapping and node.mapping.group and not node.keymap then return end

    local keys = node.keys or ''
    if desc == '' then return end

    local bc = breadcrumb(node)
    local kw = keywords[keys] or ''
    local ordinal = bc .. ' ' .. desc .. ' ' .. kw .. ' ' .. keys

    seen[keys] = true
    table.insert(results, { keys = keys, desc = desc, ordinal = ordinal })
  end)

  -- Merge built-in commands not covered by which-key presets (builtins.lua).
  local ok, builtins = pcall(require, 'builtins')
  if ok and builtins then
    for _, entry in ipairs(builtins) do
      -- Normalize to match which-key's internal format (e.g. <C-l> → <C-L>)
      local norm = vim.fn.keytrans(vim.api.nvim_replace_termcodes(entry.lhs, true, true, true))
      if not seen[norm] then
        seen[norm] = true
        local kw = keywords[entry.lhs] or ''
        local grp = entry.group or ''
        local ordinal = grp .. ' ' .. entry.desc .. ' ' .. kw .. ' ' .. entry.lhs
        table.insert(results, { keys = entry.lhs, desc = entry.desc, ordinal = ordinal })
      end
    end
  end

  table.sort(results, function(a, b) return a.keys < b.keys end)
  return results
end

function M.open()
  if not cached_results then
    cached_results = build_results()
  end
  if not cached_results then
    vim.notify('keypicker: no keybindings available', vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = 'Keybindings',
    finder = finders.new_table({
      results = cached_results,
      entry_maker = function(item)
        local display = string.format('%-20s %s', item.keys, item.desc)
        return {
          value   = item,
          display = display,
          ordinal = item.ordinal,
        }
      end,
    }),
    sorter    = conf.generic_sorter({}),
    previewer = false,

    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          vim.schedule(function()
            local k = vim.api.nvim_replace_termcodes(entry.value.keys, true, true, true)
            -- 'm' = remap keys, 't' = handle as if typed (triggers mappings)
            vim.api.nvim_feedkeys(k, 'mt', false)
          end)
        end
      end)
      return true
    end,
  }):find()
end

return M
