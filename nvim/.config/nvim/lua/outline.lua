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

  -- Highlight the symbol in the source buffer while browsing the sidebar
  -- (reverse direction of highlight_closest, which is already on by default
  -- and highlights the sidebar's row matching the source cursor).
  highlight_on_hover = true,

  -- AerialNavToggle (<leader>O)'s popup shows a live code preview next to the
  -- symbol list for leaf symbols (no children), instead of just names.
  --
  -- min_width (not max_width) is the lever that actually grows the columns:
  -- aerial sizes each of the 3 panels (list/list/preview) to its own content
  -- width, then clamps DOWN to max_width and UP to min_width — it never
  -- stretches a panel that's already narrower than max_width. The preview
  -- column's "content width" when showing code is a fixed internal default
  -- (80 cols), so max_width alone (previous attempt) never grew it. Setting
  -- min_width as "at least 30% of editor width, or 40 cols" forces all three
  -- panels — including the preview — to grow together on wide terminals.
  nav = {
    preview    = true,
    min_width  = { 40, 0.3 },
    max_width  = 0.9,
    max_height = 0.9,
    -- Arrow-key aliases for the default h/l column motions (up/down already
    -- work as ordinary line motions with no extra binding needed). Merged
    -- with aerial's defaults, not replacing them — <CR>/<C-v>/<C-s>/<C-c>
    -- keep working.
    keymaps = {
      ['<Left>']  = 'actions.left',
      ['<Right>'] = 'actions.right',
    },
  },

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
