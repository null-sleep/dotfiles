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

  -- Buffer-local next/prev-symbol jump, scoped to buffers aerial has actually
  -- attached to — same pattern as gitsigns' ]c/[c in git.lua. Aerial's own
  -- README suggests {/} for this, but those are vim's paragraph motions; we
  -- use ]a/[a instead to match this config's ]c/[c, ]s/[s "next/prev thing"
  -- convention.
  on_attach = function(bufnr)
    vim.keymap.set('n', ']a', '<cmd>AerialNext<CR>', { buffer = bufnr, desc = 'Next: Symbol (aerial)' })
    vim.keymap.set('n', '[a', '<cmd>AerialPrev<CR>', { buffer = bufnr, desc = 'Previous: Symbol (aerial)' })
  end,
})

-- Telescope fuzzy picker over aerial's symbols (works without LSP via treesitter).
-- telescope is packadd'd + setup() in plugins.lua (init.lua requires 'plugins'
-- before 'outline'), so the extension is safe to load here. pcall-guarded to
-- match the existing extension loads in plugins.lua: an unguarded failure here
-- would abort the rest of init.lua (keymaps, lsp, everything after).
pcall(require('telescope').load_extension, 'aerial')

-- Keymaps (global — toggles/search should work from any buffer, not just ones
-- aerial has attached to; see on_attach above for the buffer-local ]a/[a).
vim.keymap.set('n', '<leader>o',  '<cmd>AerialToggle<CR>',     { desc = 'Toggle: Outline sidebar (aerial)' })
vim.keymap.set('n', '<leader>O',  '<cmd>AerialNavToggle<CR>',  { desc = 'Toggle: Outline nav popup (aerial)' })
vim.keymap.set('n', '<leader>sb', '<cmd>Telescope aerial<CR>', { desc = 'Search: Outline symbols (aerial)' })
