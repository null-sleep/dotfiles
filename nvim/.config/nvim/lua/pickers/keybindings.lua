-- pickers/keybindings.lua — snacks picker for fuzzy-searching all keybindings.
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

local M = {}

-- Icon lookup intentionally empty: breadcrumbs show as plain text only.
local group_icons = {}

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

-- D1: derive a keymap's primary tag mechanically from its desc, instead of a
-- hand-maintained per-lhs table that inevitably drifts (see whichkey.lua's
-- `tags` doc comment). "Git hunk: Stage" -> "git hunk"; a desc with no
-- "Group: Action" colon (most builtins.lua entries) yields no derived tag.
local function derive_tag(desc)
  local prefix = desc:match('^([^:]+):')
  return prefix and prefix:lower() or nil
end

-- Merge the derived tag with whichkey.lua's slim override table (only for
-- tags that aren't mechanically derivable, e.g. cross-references like
-- 'rust'/'diff'/'debug'/'lsp'/'ai') — additive, never replacing the derived
-- tag, and skipping the override when it duplicates what was already derived.
-- Returns the merged list plus the derived tag itself (pill_tags below needs
-- to know which entry is the derived one).
local function resolve_tags(lhs, desc, overrides)
  local tags = {}
  local derived = derive_tag(desc)
  if derived then tags[#tags + 1] = derived end
  for _, extra in ipairs(overrides[lhs] or {}) do
    if extra ~= derived then tags[#tags + 1] = extra end
  end
  return tags, derived
end

-- Display-only filter: the derived tag usually just repeats the row's own
-- which-key group breadcrumb (e.g. <leader>vv shows "Diffview ›" AND would
-- show "+diffview"), so rendering it as a pill is redundant and widens the
-- tags column for nothing. Hide it from the PILLS when it case-insensitively
-- equals the breadcrumb — but the full tag list still goes into the search
-- ordinal, so typing the group name keeps matching. Override tags (the
-- non-derivable extras) always render.
local function pill_tags(tags, derived, bc)
  if not derived or bc:lower() ~= derived then return tags end
  return vim.tbl_filter(function(t) return t ~= derived end, tags)
end

-- Measure display column widths from the full result set.
-- Uses strdisplaywidth (not #) so multi-byte Nerd Font glyphs size correctly.
local function compute_widths(results)
  local key, bc, tags = 0, 0, 0
  for _, r in ipairs(results) do
    key  = math.max(key,  vim.fn.strdisplaywidth(r.keys))
    bc   = math.max(bc,   vim.fn.strdisplaywidth(bc_label(r.bc)))
    tags = math.max(tags, vim.fn.strdisplaywidth(tags_label(r.pills)))
  end
  return {
    key  = math.min(key + 1, 18),
    bc   = math.min(bc, 24),
    tags = tags,   -- 0 when no tags defined → column vanishes
  }
end

-- Builds the 4-column snacks format function for one picker open (widths are
-- measured from the full result set, so the closure is per-open, not per-row).
-- Columns: key | icon+group breadcrumb (dim) | desc | tag pills (dim).
local function make_format(widths)
  local align = function(text, width) return Snacks.picker.util.align(text, width, { truncate = true }) end
  return function(item)
    return {
      { align(item.keys, widths.key),         'SnacksPickerKeymapLhs' },
      { ' ' },
      { align(bc_label(item.bc), widths.bc),  'Comment' },
      { ' ' },
      { item.desc },
      { ' ' },
      { tags_label(item.pills),               'Comment' },
    }
  end
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
    local tags, derived = resolve_tags(keys, desc, tags_map)
    local tags_str = table.concat(tags, ' ')
    -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
    local ordinal = display_keys .. ' ' .. bc .. ' ' .. desc .. ' ' .. kw .. ' ' .. tags_str

    seen[keys] = true
    table.insert(results, {
      keys = display_keys, bc = bc, desc = desc,
      pills = pill_tags(tags, derived, bc), ordinal = ordinal,
    })
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
        local tags, derived = resolve_tags(entry.lhs, entry.desc, tags_map)
        local grp  = entry.group or ''
        local tags_str = table.concat(tags, ' ')
        -- Keys first so Telescope's fuzzy matcher prioritizes the keybinding itself.
        local ordinal = entry.lhs .. ' ' .. grp .. ' ' .. entry.desc .. ' ' .. kw .. ' ' .. tags_str
        table.insert(results, {
          keys = entry.lhs, bc = grp, desc = entry.desc,
          pills = pill_tags(tags, derived, grp), ordinal = ordinal,
        })
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

  local widths = compute_widths(results)

  -- The fuzzy matcher searches item.text (= the old telescope ordinal: keys
  -- first, then breadcrumb/desc/keywords/tags, so typing a key sequence
  -- still ranks the binding itself highest).
  local items = {}
  for _, r in ipairs(results) do
    r.text = r.ordinal
    items[#items + 1] = r
  end

  return Snacks.picker.pick({
    source = 'keybindings',
    title = 'Keybindings',
    items = items,
    format = make_format(widths),
    layout = { preset = 'select' },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          local k = vim.api.nvim_replace_termcodes(item.keys, true, true, true)
          -- 'm' = remap keys, 't' = handle as if typed (triggers mappings)
          vim.api.nvim_feedkeys(k, 'mt', false)
        end)
      end
    end,
  })
end

return M
