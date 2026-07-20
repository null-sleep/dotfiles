-- Shared buffer classification: "is this a real code/text buffer, or a
-- special panel/CLI/prompt?" Several features have historically hand-rolled
-- their own version of this check (see GUIDE.md "Non-code buffer exceptions
-- need a shared predicate" for the full survey and why autosave/statusline/
-- satellite deliberately do NOT route through this module — they answer
-- different questions). This module is the canonical home going forward for
-- checks that mean exactly "not a real code buffer".
--
-- It also owns left-edge sidebar coordination (bottom of the file) — the one
-- place that acts on panels rather than classifying them, kept here because
-- `sidebar_filetypes` drives it.
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

-- Left-edge sidebar coordination: every `sidebar_filetypes` panel wants the
-- true left edge, so each toggle closes the others on its OPENING edge. See
-- GUIDE.md "Left-edge sidebars swap into each other".

-- Floats are excluded: aerial's nav popup carries the panel's filetype
-- without owning the edge.
---@param ft string
---@param all_tabs? boolean every tabpage instead of just the current one
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

-- Current tab only, agreeing with aerial's is_open() / nvim-tree's
-- is_visible() — a toggle that disagrees thinks it's opening when it's open.
---@param ft string a `sidebar_filetypes` key
---@return boolean
function M.is_sidebar_visible(ft)
  return #edge_wins(ft) > 0
end

-- Close through each plugin's own API — nvim-tree and aerial desync if their
-- window goes out from under them. `all_tabs` picks the wider call.
local sidebar_closers = {
  NvimTree = function(all_tabs)
    local api = require('nvim-tree.api')
    if all_tabs then api.tree.close_in_all_tabs() else api.tree.close() end
  end,
  aerial = function(all_tabs)
    local aerial = require('aerial')
    if all_tabs then aerial.close_all() else aerial.close() end
  end,
}

-- Sweeps windows after the closer too: one that errors would otherwise leave
-- the sidebar open and silently break the swap. A panel may own several edge
-- windows, so close every match.
---@param keep_ft? string sidebar filetype to leave alone (nil closes all)
---@param all_tabs? boolean every tabpage instead of just the current one
local function close_sidebars(keep_ft, all_tabs)
  for ft in pairs(M.sidebar_filetypes) do
    if ft ~= keep_ft and #edge_wins(ft, all_tabs) > 0 then
      local closer = sidebar_closers[ft]
      if closer then pcall(closer, all_tabs) end
      for _, win in ipairs(edge_wins(ft, all_tabs)) do
        pcall(vim.api.nvim_win_close, win, false)
      end
      -- Still standing = the close really failed (E444 if it's the tabpage's
      -- only window). Say so: the caller is about to open its own panel and
      -- would otherwise just get two stacked sidebars and no explanation.
      local left = #edge_wins(ft, all_tabs)
      if left > 0 then
        vim.notify(('Sidebar: could not close %s (%d window(s) left)'):format(ft, left),
          vim.log.levels.WARN)
      end
    end
  end
end

-- Call only when the caller's own panel is about to OPEN — closing a sidebar
-- must never reach into the others, or the toggles stop being independent.
---@param keep_ft? string sidebar filetype to leave alone
function M.close_other_sidebars(keep_ft)
  close_sidebars(keep_ft, false)
end

-- Every tabpage, for autocmds.lua's quit handler: it counts windows globally,
-- so a current-tab sweep would strand a sidebar alone in another tab.
function M.close_all_sidebars()
  close_sidebars(nil, true)
end

return M
