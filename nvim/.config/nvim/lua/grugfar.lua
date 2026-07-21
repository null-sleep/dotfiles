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
--
-- Fixed instanceName so a repeat press supersedes instead of stacking a new
-- window (default: auto-named, so each open() adds one). Re-check
-- has_instance after kill_instance() — it declines mid-replace/sync, and an
-- unkilled instance would make open() error "already exists".
local INSTANCE_NAME = 'leader_sR'

vim.keymap.set({ 'n', 'x' }, '<leader>sR', function()
  ensure()
  local grug_far = require('grug-far')
  if grug_far.has_instance(INSTANCE_NAME) then
    grug_far.kill_instance(INSTANCE_NAME)
    if grug_far.has_instance(INSTANCE_NAME) then return end
  end
  grug_far.open({ transient = true, instanceName = INSTANCE_NAME })
end, { desc = 'Search: Search & replace (grug-far)' })

-- <localleader>S in the results buffer swaps the Search and Replace inputs.
-- Doubles as a one-key reverse: after applying a→b, swap to b→a and \r to undo
-- it. Same input names on both engines, so it's engine-agnostic. Registered
-- per-buffer via FileType because it's a custom action, not one of grug-far's
-- remappable built-in keys. Reads/writes through grug-far's inputs API rather
-- than scraping buffer lines.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'grug-far',
  desc = 'grug-far: <localleader>S swaps the Search/Replace inputs',
  callback = function(ev)
    vim.keymap.set('n', '<localleader>S', function()
      local inst = require('grug-far').get_instance(0)
      if not inst then return end
      local v = require('grug-far.inputs').getValues(inst._context, inst._buf)
      v.search, v.replacement = v.replacement, v.search
      inst:update_input_values(v, true)
    end, { buffer = ev.buf, desc = 'Search & replace: Swap search/replace (grug-far)' })
  end,
})
