-- Shared buffer classification: "is this a real code/text buffer, or a
-- special panel/CLI/prompt?" Several features have historically hand-rolled
-- their own version of this check (see GUIDE.md "Non-code buffer exceptions
-- need a shared predicate" for the full survey and why autosave/statusline/
-- satellite deliberately do NOT route through this module — they answer
-- different questions). This module is the canonical home going forward for
-- checks that mean exactly "not a real code buffer".
--
-- It also owns left-edge sidebar coordination (bottom of the file) — the one
-- place that acts on panels rather than just classifying them, kept here
-- because it's driven by `sidebar_filetypes` right above it.
local M = {}

-- Canonical registry of non-code panel/CLI filetypes. Membership means "not a
-- real editable code/text buffer". Seeded minimally — add a filetype here
-- when a new panel/terminal plugin needs the same exclusion (see CLAUDE.md
-- "Non-code buffer exceptions").
M.special_filetypes = {
  aerial            = true,  -- outline sidebar
  NvimTree          = true,  -- file tree
  toggleterm        = true,  -- terminal panel/float
  sidekick_terminal = true,  -- sidekick AI CLI
  atone             = true,  -- undo tree panel (tree + diff + help all share it)
}

-- Sidebars: persistent navigation panels docked to a window edge. A STRICT
-- SUBSET of `special_filetypes` that deliberately excludes terminals/CLI/
-- prompt buffers. Consumed by the "quit nvim when only sidebars remain"
-- autocmd (autocmds.lua), which must NOT treat a lone toggleterm as reason to
-- quit — so it can't reuse `is_special()`. Kept as its own list for the same
-- reason autosave/statusline keep theirs (see CLAUDE.md): different question.
M.sidebar_filetypes = {
  NvimTree = true,  -- file tree
  aerial   = true,  -- outline sidebar
  atone    = true,  -- undo tree panel
}

-- True when `buf` is a non-code buffer: a terminal/prompt buftype, or a
-- registered special filetype. `nofile` is deliberately NOT treated as
-- special — it over-matches (dashboards, Neogit/diffview, quickfix, help all
-- use it too); see GUIDE.md for the accepted boundary this leaves. The
-- `prompt` arm is future-proofing — neither current consumer can actually hit
-- it (a normal-mode map can't fire in an insert-mode picker prompt, and a
-- prompt buffer is never the alternate buffer) — but it's cheap and correct.
---@param buf? integer buffer handle, default current (0)
function M.is_special(buf)
  buf = buf or 0
  local bt = vim.bo[buf].buftype
  if bt == 'terminal' or bt == 'prompt' then return true end
  return M.special_filetypes[vim.bo[buf].filetype] == true
end

-- True when `buf` is a docked sidebar (see `sidebar_filetypes`). Narrower than
-- `is_special()`: a terminal or CLI panel is special but not a sidebar.
---@param buf? integer buffer handle, default current (0)
function M.is_sidebar(buf)
  buf = buf or 0
  return M.sidebar_filetypes[vim.bo[buf].filetype] == true
end

-- Left-edge sidebar coordination. Every sidebar in `sidebar_filetypes` wants
-- the true left edge of the tabpage, so only one can be open at a time and
-- each one's toggle closes the others on its OPENING edge.
--
-- This used to be an inlined pairwise check in outline.lua and keymaps.lua,
-- deliberately un-abstracted while it was "a symmetric pair between exactly
-- two plugins". A third sidebar (atone's undo tree) makes that six pairwise
-- checks, which is where the abstraction pays for itself. See GUIDE.md
-- "Left-edge sidebars swap into each other".
--
-- Visibility is answered from windows (uniform, and atone exposes no
-- is_open()), but CLOSING goes through each plugin's own API where one
-- exists. nvim-tree and aerial track their view state internally; closing
-- their window behind their back desyncs it and the next toggle misbehaves.
-- The autocmds.lua quit handler can get away with a raw win_close because
-- nvim is exiting anyway — here the config lives on.

-- Windows showing filetype `ft`, current tabpage by default. Floating windows
-- are excluded deliberately — aerial's nav popup (<leader>O) and atone's `gd`
-- diff float carry their panel's filetype but don't own the edge, so closing
-- them here would make an unrelated float vanish on a sidebar toggle.
---@param ft string
---@param all_tabs? boolean search every tabpage instead of just the current one
---@return integer[]
local function edge_wins(ft, all_tabs)
  local wins = {}
  local scope = all_tabs and vim.api.nvim_list_wins() or vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(scope) do
    if vim.api.nvim_win_get_config(win).relative == ''
      and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      table.insert(wins, win)
    end
  end
  return wins
end

-- Current tabpage only, matching what aerial's is_open() and nvim-tree's
-- is_visible() report — the swap has to agree with the plugins' own idea of
-- "am I showing" or a toggle can decide it's opening when it's already open.
---@param ft string a `sidebar_filetypes` key
---@return boolean true when that sidebar owns an edge window right now
function M.is_sidebar_visible(ft)
  return #edge_wins(ft) > 0
end

-- How to close each sidebar, keyed by the same filetypes as
-- `sidebar_filetypes` above. Kept as its own table because membership ("is
-- this a sidebar", which autocmds.lua also asks) and the close mechanism are
-- separate concerns — and a plugin can join the registry before it has an
-- entry here (the window-close pass below covers it meanwhile).
--
-- Each takes `all_tabs`, because the two callers differ: a swap is a
-- current-tab affair, while the quit handler has to clear every tabpage.
local sidebar_closers = {
  NvimTree = function(all_tabs)
    local api = require('nvim-tree.api')
    if all_tabs then api.tree.close_in_all_tabs() else api.tree.close() end
  end,
  aerial = function(all_tabs)
    local aerial = require('aerial')
    if all_tabs then aerial.close_all() else aerial.close() end
  end,
  -- atone exposes no public Lua API — :Atone is the supported surface. This
  -- entry is load-bearing, not politeness: closing its windows directly makes
  -- atone cascade through its own WinClosed handler and throw out of a
  -- refresh() mid-teardown. Only ever one panel, so `all_tabs` is moot.
  atone = function() vim.cmd('Atone close') end,
}

-- Close registered sidebars, preferring each plugin's own API and sweeping up
-- any window it left behind. That second pass isn't only for panels with no
-- closer: a closer that errors (plugin not loaded, API renamed upstream)
-- would otherwise leave the sidebar open and silently break the swap.
--
-- A panel may own several edge windows — atone stacks its diff split under
-- the tree, both filetype `atone` — so close every match, not the first.
---@param keep_ft? string sidebar filetype to leave alone (nil closes all)
---@param all_tabs? boolean clear every tabpage instead of just the current one
local function close_sidebars(keep_ft, all_tabs)
  for ft in pairs(M.sidebar_filetypes) do
    if ft ~= keep_ft and #edge_wins(ft, all_tabs) > 0 then
      local closer = sidebar_closers[ft]
      if closer then pcall(closer, all_tabs) end
      for _, win in ipairs(edge_wins(ft, all_tabs)) do
        pcall(vim.api.nvim_win_close, win, false)
      end
      -- Anything still standing means the close genuinely failed (E444 when
      -- the sidebar is its tabpage's only window, say). Say so — the caller
      -- is about to open its own panel and would otherwise just end up with
      -- two stacked sidebars and no explanation.
      local left = #edge_wins(ft, all_tabs)
      if left > 0 then
        vim.notify(('Sidebar: could not close %s (%d window(s) left)'):format(ft, left),
          vim.log.levels.WARN)
      end
    end
  end
end

-- Close every left-edge sidebar except `keep_ft`. Call this only when the
-- caller's own panel is about to OPEN — closing a sidebar must never reach
-- into the others, or the toggles stop being independent.
---@param keep_ft? string sidebar filetype to leave alone
function M.close_other_sidebars(keep_ft)
  close_sidebars(keep_ft, false)
end

-- Close every left-edge sidebar in every tabpage. For the auto-quit handler
-- in autocmds.lua, which counts windows globally — a current-tab-only sweep
-- would strand a sidebar sitting alone in another tab, the exact thing that
-- handler exists to prevent.
function M.close_all_sidebars()
  close_sidebars(nil, true)
end

return M
