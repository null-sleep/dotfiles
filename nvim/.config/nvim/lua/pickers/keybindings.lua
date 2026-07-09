-- pickers/keybindings.lua — Telescope picker for fuzzy-searching all keybindings.
--
-- USAGE
--   require('pickers.keybindings').open()        (bound to <leader>sk)
--
-- Walks the which-key internal tree to build a flat, searchable list of leaf
-- keybindings. Group labels from ancestor nodes and custom keywords (from
-- whichkey.lua) are included in the search text but not the display.
-- Tags (from whichkey.lua) are rendered as dim +tag pills and also searched.
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

-- Nerd Font glyph per top-level which-key group. Keyed by the leading segment
-- of breadcrumb() output (which joins with ' > '). Missing key = no glyph but
-- breadcrumb text still shows. Covers whichkey.lua groups + common builtins groups.
local group_icons = {
  Search           = '',
  Git              = '󰊢',
  ['Git hunk']     = '󰊢',
  Terminal         = '',
  Toggle           = '󰔡',
  Debug            = '',
  Test             = '󰙨',
  AI               = '󱚦',
  Code             = '',
  Diffview         = '',
  Utilities        = '',
  Peek             = '',
  Refactor         = '',
  ['Session/Quit'] = '󰈆',
  ['Go to']        = '󰈲',
  Previous         = '',
  Next             = '',
}

-- Breadcrumb string → decorated column text with optional icon.
-- bc_label('Git > Rebase') → "󰊢 Git › Rebase ›"
-- bc_label('')             → ""
local function bc_label(bc)
  if not bc or bc == '' then return '' end
  local lead = bc:match('^(.-) > ') or bc
  local icon = group_icons[lead]
  local label = bc:gsub(' > ', ' › ')
  if icon then return icon .. ' ' .. label .. ' ›' end
  return label .. ' ›'
end

-- Tags list → dim pill string.
-- tags_label({'git','diff'}) → "+git +diff"
-- tags_label({})             → ""
local function tags_label(tags)
  if not tags or #tags == 0 then return '' end
  return '+' .. table.concat(tags, ' +')
end

-- Measure display column widths from the full result set.
-- Uses strdisplaywidth (not #) so multi-byte Nerd Font glyphs size correctly.
local function compute_widths(results)
  local key, bc, tags = 0, 0, 0
  for _, r in ipairs(results) do
    key  = math.max(key,  vim.fn.strdisplaywidth(r.keys))
    bc   = math.max(bc,   vim.fn.strdisplaywidth(bc_label(r.bc)))
    tags = math.max(tags, vim.fn.strdisplaywidth(tags_label(r.tags)))
  end
  return {
    key  = math.min(key + 1, 18),
    bc   = math.min(bc, 24),
    tags = tags,   -- 0 when no tags defined → column vanishes
  }
end

-- Creates the entry_display displayer once per picker open (stateful, not per-row).
local function make_displayer(widths)
  return require('telescope.pickers.entry_display').create({
    separator = ' ',
    items = {
      { width = widths.key },
      { width = widths.bc },
      { remaining = true },
      { width = widths.tags },
    },
  })
end

-- Renders one row. Pure — no side effects.
local function make_display(displayer, item)
  return displayer({
    { item.keys,             'TelescopeResultsIdentifier' },
    { bc_label(item.bc),     'Comment' },
    { item.desc },
    { tags_label(item.tags), 'Comment' },
  })
end

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

  local wk_exports = require('whichkey')
  local keywords   = wk_exports.keywords or {}
  local tags_map   = wk_exports.tags or {}
  local results    = {}

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

    local bc   = breadcrumb(node)
    local kw   = keywords[keys] or ''
    local tags = tags_map[keys] or {}
    local tags_str = table.concat(tags, ' ')
    -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
    local ordinal = display_keys .. ' ' .. bc .. ' ' .. desc .. ' ' .. kw .. ' ' .. tags_str

    seen[keys] = true
    table.insert(results, { keys = display_keys, bc = bc, desc = desc, tags = tags, ordinal = ordinal })
  end)

  -- Merge built-in commands not covered by which-key presets (builtins.lua).
  local ok, builtins = pcall(require, 'builtins')
  if ok and builtins then
    for _, entry in ipairs(builtins) do
      -- Normalize to match which-key's internal format (e.g. <C-l> → <C-L>)
      local norm = vim.fn.keytrans(vim.api.nvim_replace_termcodes(entry.lhs, true, true, true))
      if not seen[norm] then
        seen[norm] = true
        local kw   = keywords[entry.lhs] or ''
        local tags = tags_map[entry.lhs] or {}
        local grp  = entry.group or ''
        local tags_str = table.concat(tags, ' ')
        -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
        local ordinal = entry.lhs .. ' ' .. grp .. ' ' .. entry.desc .. ' ' .. kw .. ' ' .. tags_str
        table.insert(results, { keys = entry.lhs, bc = grp, desc = entry.desc, tags = tags, ordinal = ordinal })
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

  local widths    = compute_widths(results)
  local displayer = make_displayer(widths)

  pickers.new({}, {
    prompt_title  = 'Keybindings',
    layout_config = { width = 0.65, height = 0.45 },
    finder = finders.new_table({
      results = results,
      entry_maker = function(item)
        return {
          value   = item,
          display = function(entry) return make_display(displayer, entry.value) end,
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
