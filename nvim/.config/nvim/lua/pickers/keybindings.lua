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
-- All modes are walked (MODES below), keyed by lhs+desc so a key mapped the same
-- way in several modes collapses into one row.
--
-- Results are rebuilt on every open (cheap: one tree walk + two keymap
-- syscalls). Not cached for the session — which-key's tree is per-buffer, so a
-- session cache froze out buffer-local / LspAttach maps and leaked the
-- first-open buffer's local maps everywhere. which-key already invalidates its
-- own tree on LspAttach/BufEnter, so an external cache only fights that.

local M = {}

-- Icon lookup intentionally empty: breadcrumbs show as plain text only.
local group_icons = {}

-- No 'v'/'s': a `mode = 'v'` keymap registers under both 'x' and 's', so walking
-- them would list it twice.
local MODES = { 'n', 'x', 'o', 'i', 'c', 't' }

-- Only for confirm()'s "press it in X mode" notice. Kept OUT of the search text:
-- a mode word in every row dilutes short fuzzy patterns.
local MODE_NAMES = {
  x = 'visual', o = 'operator-pending',
  i = 'insert', c = 'cmdline', t = 'terminal',
}

-- Plugin plumbing, not keys anyone looks up: nvim-autopairs maps `(`, `{`, `"`…
-- in insert mode, all desc'd "autopairs map key".
local SKIP_DESC = { '^autopairs ' }

local function is_noise(desc)
  for _, pat in ipairs(SKIP_DESC) do
    if desc:match(pat) then return true end
  end
  return false
end

-- Mode letters → dim label. Normal-only rows render blank (they're most rows, so
-- a column of "n"s is noise) — same hide-the-redundant idea as pill_tags() below.
local function modes_label(modes)
  if #modes == 1 and modes[1] == 'n' then return '' end
  return table.concat(modes, ' ')
end

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
  local key, modes, bc, tags = 0, 0, 0, 0
  for _, r in ipairs(results) do
    key   = math.max(key,   vim.fn.strdisplaywidth(r.keys))
    modes = math.max(modes, vim.fn.strdisplaywidth(modes_label(r.modes)))
    bc    = math.max(bc,    vim.fn.strdisplaywidth(bc_label(r.bc)))
    tags  = math.max(tags,  vim.fn.strdisplaywidth(tags_label(r.pills)))
  end
  return {
    key   = math.min(key + 1, 18),
    modes = modes,  -- 0 when every map is normal-only → column vanishes
    bc    = math.min(bc, 24),
    tags  = tags,   -- 0 when no tags defined → column vanishes
  }
end

-- Builds the 5-column snacks format function for one picker open (widths are
-- measured from the full result set, so the closure is per-open, not per-row).
-- Columns: key | modes (dim) | icon+group breadcrumb (dim) | desc | tag pills (dim).
local function make_format(widths)
  local align = function(text, width) return Snacks.picker.util.align(text, width, { truncate = true }) end
  return function(item)
    return {
      { align(item.keys, widths.key),               'SnacksPickerKeymapLhs' },
      { ' ' },
      { align(modes_label(item.modes), widths.modes), 'SnacksPickerKeymapMode' },
      { ' ' },
      { align(bc_label(item.bc), widths.bc),        'Comment' },
      { ' ' },
      { item.desc },
      { ' ' },
      { tags_label(item.pills),                     'Comment' },
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
  local wk_exports = require('whichkey')
  local keywords   = wk_exports.keywords or {}
  local tags_map   = wk_exports.tags or {}

  local results = {}
  local by_row  = {}  -- "lhs\0desc" → result, so one key mapped the same way in
                      -- several modes becomes one row instead of N near-duplicates
  local found_tree = false

  for _, mode in ipairs(MODES) do
    -- update = true forces a fresh rebuild of the current buffer's tree (matches
    -- what <leader>? does internally), so we pick up buffer-local / LspAttach maps
    -- live on each open rather than a stale snapshot.
    local tree = require('which-key.buf').get({ mode = mode, update = true })
    if tree then
      found_tree = true
      -- `return false` prunes the subtree; bare `return` skips just this node
      -- but continues into children.
      tree.tree:walk(function(node)
        if node.hidden then return false end
        local desc = node.desc or ''
        if not node.keymap and desc == '' then return end
        if node.mapping and node.mapping.group and not node.keymap then return end

        local keys = node.keys or ''
        if desc == '' or is_noise(desc) then return end

        local row = by_row[keys .. '\0' .. desc]
        if row then
          row.modes[#row.modes + 1] = mode
          return
        end

        -- Normalize which-key's internal key representations for display:
        -- • <NL> → <C-j>  (Neovim's internal name for Ctrl-J)
        -- • <C-X> → <C-x>  (keytrans uppercases after <C-, but Ctrl flattens
        --   case at the terminal level — <C-h> and <C-H> are the same keypress,
        --   so lowercase is the canonical display form)
        local display_keys = keys:gsub('<NL>', '<C-j>'):gsub('<C%-(%u)>', function(letter)
          return '<C-' .. letter:lower() .. '>'
        end)

        local bc = breadcrumb(node)
        local tags, derived = resolve_tags(keys, desc, tags_map)
        row = {
          keys = display_keys, bc = bc, desc = desc, modes = { mode },
          pills = pill_tags(tags, derived, bc),
          kw = keywords[keys] or '', tags_str = table.concat(tags, ' '),
        }
        by_row[keys .. '\0' .. desc] = row
        results[#results + 1] = row
      end)
    end
  end

  if not found_tree then return nil end

  -- Merge built-in commands not covered by which-key presets (builtins.lua).
  -- All normal-mode; skip any whose lhs a real mapping already claimed.
  local ok, builtins = pcall(require, 'builtins')
  if ok and builtins then
    local mapped = {}
    for _, r in ipairs(results) do
      if vim.tbl_contains(r.modes, 'n') then mapped[r.keys] = true end
    end
    for _, entry in ipairs(builtins) do
      -- Normalize to match which-key's internal format (e.g. <C-l> → <C-L>)
      local norm = vim.fn.keytrans(vim.api.nvim_replace_termcodes(entry.lhs, true, true, true))
      if not mapped[norm] and not mapped[entry.lhs] then
        mapped[entry.lhs] = true
        local tags, derived = resolve_tags(entry.lhs, entry.desc, tags_map)
        local grp = entry.group or ''
        results[#results + 1] = {
          keys = entry.lhs, bc = grp, desc = entry.desc, modes = { 'n' },
          pills = pill_tags(tags, derived, grp),
          kw = keywords[entry.lhs] or '', tags_str = table.concat(tags, ' '),
        }
      end
    end
  end

  -- Keys first so the fuzzy matcher prioritizes the keybinding itself. which-key
  -- names the leader key <Space>, so also search the <leader> spelling this
  -- config documents — otherwise "<leader>gg" finds nothing. Display stays
  -- <Space>: confirm() feeds item.keys to nvim_replace_termcodes, which doesn't
  -- expand <leader>.
  for _, r in ipairs(results) do
    local leader_alias = r.keys:gsub('^<Space>', '<leader>', 1)
    if leader_alias == r.keys then leader_alias = '' end
    r.ordinal = table.concat({
      r.keys, leader_alias, r.bc, r.desc, r.kw, r.tags_str,
    }, ' ')
  end

  -- Normal-mode rows first within a key, so <D-v> (n) sorts above <D-v> (t).
  table.sort(results, function(a, b)
    if a.keys ~= b.keys then return a.keys < b.keys end
    return modes_label(a.modes) < modes_label(b.modes)
  end)
  return results
end

function M.open()
  local results = build_results()
  if not results then
    vim.notify('pickers.keybindings: no keybindings available', vim.log.levels.WARN)
    return
  end

  local widths = compute_widths(results)

  -- The fuzzy matcher searches item.text: keys first, then breadcrumb/
  -- desc/keywords/tags, so typing a key sequence ranks the binding itself
  -- highest.
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
    -- Opt out of picker.lua's global frecency boost: a keymap you keep picking is
    -- one you already know, not one you need to look up. Rank on typed input only.
    matcher = { frecency = false },
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      -- The picker closes back into normal mode, so feeding a visual/insert lhs
      -- would run whatever those keys mean in normal mode. Report, don't misfire.
      if not vim.tbl_contains(item.modes, 'n') then
        local names = vim.tbl_map(function(m) return MODE_NAMES[m] end, item.modes)
        vim.notify(
          ('%s is %s-mode only — press it in %s mode'):format(
            item.keys, table.concat(names, '/'), table.concat(names, ' or ')),
          vim.log.levels.WARN)
        return
      end
      vim.schedule(function()
        local k = vim.api.nvim_replace_termcodes(item.keys, true, true, true)
        -- 'm' = remap keys, 't' = handle as if typed (triggers mappings)
        vim.api.nvim_feedkeys(k, 'mt', false)
      end)
    end,
  })
end

return M
