-- Outline sidebar (aerial.nvim) — persistent, collapsible symbol tree for the
-- current buffer, like VS Code's / Zed's outline panel. Treesitter-first so it
-- works even with no LSP attached; aerial falls through to the LSP backend when
-- treesitter has no parser OR no aerial outline query for the language (see
-- aerial's own is_supported check). Complements the sticky-scroll header
-- (treesitter_context.lua) and the symbol pickers (pickers/symbols.lua): those
-- jump/pin, this stays docked as a map.
--
-- Named outline.lua, NOT aerial.lua: a wrapper file named after the module it
-- requires (require('aerial')) would resolve require() back to itself and
-- recurse — the same bug that broke the earlier dropbar.nvim attempt.
vim.cmd.packadd('aerial.nvim')

require('aerial').setup({
  -- Aerial's own default order (treesitter first, LSP fallback). Stated
  -- explicitly to document the no-LSP-required intent.
  backends = { 'treesitter', 'lsp', 'markdown', 'asciidoc', 'man' },
  layout = {
    default_direction = 'prefer_left', -- dock on the left (aerial's default is 'prefer_right')
    min_width = 25,
  },
  attach_mode = 'window',        -- outline tracks the window it was opened from
  close_automatic_events = {},   -- persistent panel: never auto-close
  -- filter_kind left at default = structural symbols only (Class/Function/
  -- Method/Interface/Struct/Enum/Module/Constructor). Set `filter_kind = false`
  -- to also show variables/fields/constants.
  show_guides = true,            -- draw the ├─ └─ tree guide lines (default is false)
})

-- Telescope fuzzy picker over aerial's symbols (works without LSP via treesitter).
-- telescope is packadd'd + setup() in plugins.lua (init.lua requires 'plugins'
-- before 'outline'), so the extension is safe to load here. pcall-guarded to
-- match the existing extension loads in plugins.lua: an unguarded failure here
-- would abort the rest of init.lua (keymaps, lsp, everything after).
pcall(require('telescope').load_extension, 'aerial')

-- Keymaps
vim.keymap.set('n', '<leader>to', '<cmd>AerialToggle<CR>',     { desc = 'Toggle: Outline sidebar (aerial)' })
vim.keymap.set('n', '<leader>tO', '<cmd>AerialNavToggle<CR>',  { desc = 'Toggle: Outline nav popup (aerial)' })
vim.keymap.set('n', '<leader>sb', '<cmd>Telescope aerial<CR>', { desc = 'Search: Outline symbols (aerial)' })
vim.keymap.set('n', ']a',         '<cmd>AerialNext<CR>',       { desc = 'Next: Symbol (aerial)' })
vim.keymap.set('n', '[a',         '<cmd>AerialPrev<CR>',       { desc = 'Previous: Symbol (aerial)' })
