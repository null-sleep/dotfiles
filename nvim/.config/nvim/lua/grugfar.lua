-- grug-far.nvim — interactive project-wide find & replace: the editable
-- counterpart to the read-only snacks grep pickers (<leader>s*). In-buffer keys
-- use <localleader> (\): \r apply, \e engine, \s sync, \t history, \x Lua.
--
-- Lazy: the <leader>sR keymap is eager; packadd + setup() run on first press
-- (memoized). vim.pack sources grug-far's plugin/ at startup regardless, so
-- :GrugFar always exists — only the require()/setup() work is deferred.
local loaded = false
local function ensure()
  if loaded then return end
  loaded = true
  vim.cmd.packadd('grug-far.nvim')
  require('grug-far').setup({
    keymaps = { close = { n = 'q' } },  -- close with q, not \c (:q works too)
  })
end

-- open() auto-prefills a visual selection as a --fixed-strings search (the
-- recommended lua-fn usage, not with_visual_selection()). transient = unlisted
-- buffer wiped on close; history persists separately (\t).
vim.keymap.set({ 'n', 'x' }, '<leader>sR', function()
  ensure()
  require('grug-far').open({ transient = true })
end, { desc = 'Search: Search & replace (grug-far)' })
