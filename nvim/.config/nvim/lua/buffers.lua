-- Shared buffer classification: "is this a real code/text buffer, or a
-- special panel/CLI/prompt?" Several features have historically hand-rolled
-- their own version of this check (see GUIDE.md "Non-code buffer exceptions
-- need a shared predicate" for the full survey and why autosave/statusline/
-- satellite deliberately do NOT route through this module — they answer
-- different questions). This module is the canonical home going forward for
-- checks that mean exactly "not a real code buffer".
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

return M
