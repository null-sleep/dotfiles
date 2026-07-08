-- pickers/keybindings.lua — Telescope picker for fuzzy-searching all keybindings.
--
-- USAGE
--   require('pickers.keybindings').open()        (bound to <leader>sk)
--
-- Walks the which-key internal tree to build a flat, searchable list of leaf
-- keybindings. Group labels from ancestor nodes and custom keywords (from
-- whichkey.lua) are included in the search text but not the display.
--
-- Results are rebuilt on every open (cheap: one tree walk + two keymap
-- syscalls). Not cached for the session — which-key's tree is per-buffer, so a
-- session cache froze out buffer-local / LspAttach maps and leaked the
-- first-open buffer's local maps everywhere. which-key already invalidates its
-- own tree on LspAttach/BufEnter, so an external cache only fights that.

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

local function build_results()
  -- update = true forces a fresh rebuild of the current buffer's tree (matches
  -- what <leader>? does internally), so we pick up buffer-local / LspAttach maps
  -- live on each open rather than a stale snapshot.
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

    -- Normalize which-key's internal key representations for display:
    -- • <NL> → <C-j>  (Neovim's internal name for Ctrl-J)
    -- • <C-X> → <C-x>  (keytrans uppercases after <C-, but Ctrl flattens
    --   case at the terminal level — <C-h> and <C-H> are the same keypress,
    --   so lowercase is the canonical display form)
    local display_keys = keys:gsub('<NL>', '<C-j>'):gsub('<C%-(%u)>', function(letter)
      return '<C-' .. letter:lower() .. '>'
    end)

    local bc = breadcrumb(node)
    local kw = keywords[keys] or ''
    -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
    local ordinal = display_keys .. ' ' .. bc .. ' ' .. desc .. ' ' .. kw

    seen[keys] = true
    table.insert(results, { keys = display_keys, desc = desc, ordinal = ordinal })
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
        -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
        local ordinal = entry.lhs .. ' ' .. grp .. ' ' .. entry.desc .. ' ' .. kw
        table.insert(results, { keys = entry.lhs, desc = entry.desc, ordinal = ordinal })
      end
    end
  end

  table.sort(results, function(a, b) return a.keys < b.keys end)
  return results
end

function M.open()
  local results = build_results()
  if not results then
    vim.notify('pickers.keybindings: no keybindings available', vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title  = 'Keybindings',
    layout_config = { width = 0.6, height = 0.4 },
    finder = finders.new_table({
      results = results,
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
