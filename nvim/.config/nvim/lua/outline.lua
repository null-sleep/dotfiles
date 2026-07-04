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

-- Rust's default aerial naming for impl blocks (kind "Class") is `Bird` for a
-- bare `impl Bird` and `Bird > Animal` for `impl Animal for Bird` — the bare
-- case is textually identical to the struct `Bird` it's attached to, so the
-- two are indistinguishable except by icon. Renaming to match rust-analyzer's
-- own naming (`impl Bird` / `impl Animal for Bird`, the same text Telescope's
-- LSP-backed symbols picker already shows) kills that collision outright.
-- extensions.lua keys its postprocess table per-language (M.rust, M.go, M.zig,
-- ...), so replacing M.rust here can't affect any other language's symbols.
-- require() caches the module table, so mutating the entry returned here is
-- the same live table aerial's treesitter backend looks up on every parse —
-- same monkeypatch style as the zh highlight_on_hover toggle below. Could
-- break on an aerial internals refactor; low risk given how small and stable
-- this table is.
require('aerial.backends.treesitter.extensions').rust.postprocess = function(bufnr, item, match)
  if item.kind ~= 'Class' then return end
  local trait_node = ((match or {}).trait or {}).node
  local type_node = ((match or {}).rust_type or {}).node
  if not type_node then return end
  local type_name = vim.treesitter.get_node_text(type_node, bufnr) or '<parse error>'
  if trait_node then
    local trait_name = vim.treesitter.get_node_text(trait_node, bufnr) or '<parse error>'
    item.name = string.format('impl %s for %s', trait_name, type_name)
  else
    item.name = string.format('impl %s', type_name)
  end
end

require('aerial').setup({
  -- Aerial's own default order (treesitter first, LSP fallback). Stated
  -- explicitly to document the no-LSP-required intent.
  backends = { 'treesitter', 'lsp', 'markdown', 'asciidoc', 'man' },
  layout = {
    -- 'left' (not 'prefer_left'): the 'prefer_*' variants flip to the other
    -- side whenever they judge something to be "in the way" on the preferred
    -- side — verified this flips aerial to the right when e.g. nvim-tree is
    -- open, or even when an unrelated right-side split exists, depending on
    -- which window has focus at open-time. Plain 'left' has no flip logic:
    -- always left, full stop.
    default_direction = 'left',
    -- 'edge' (not the default 'window'): anchors aerial to the true left
    -- edge of the whole tabpage, not relative to whichever window currently
    -- has focus — this is what makes placement independent of which buffer
    -- <leader>o was pressed from. Left is reserved for outline/explorer
    -- (nvim-tree), right for sidekick (ai.lua's own edge-promotion trick).
    placement = 'edge',
    min_width = 25,
  },
  -- 'global' (not 'window'): the single sidebar always mirrors whichever
  -- window currently has focus anywhere in the tabpage — VS Code/Zed-style
  -- outline-follows-active-editor — rather than staying pinned to the one
  -- window it happened to be opened from.
  attach_mode = 'global',
  close_automatic_events = {},   -- persistent panel: never auto-close
  -- filter_kind left at default = structural symbols only (Class/Function/
  -- Method/Interface/Struct/Enum/Module/Constructor). Set `filter_kind = false`
  -- to also show variables/fields/constants.
  show_guides = true,            -- draw the ├─ └─ tree guide lines (default is false)

  -- Highlight the symbol in the source buffer while browsing the sidebar
  -- (reverse direction of highlight_closest, which is already on by default
  -- and highlights the sidebar's row matching the source cursor). Off by
  -- default — toggle on with zh below when wanted.
  highlight_on_hover = false,

  -- Sidebar-local toggle for highlight_on_hover (zh, alongside aerial's own
  -- z*-prefixed fold toggles: za/zo/zc/zA/zO/zC/zr/zR/zm/zM/zx/zX). Dips into
  -- aerial internals (require('aerial.config') is a plain mutable table —
  -- every setup() option becomes a live top-level field on it, read fresh on
  -- every event, not cached — and require('aerial.render').clear_highlights
  -- is a small public util) since aerial has no built-in toggle command for
  -- this option. Could break on an aerial internals refactor; low risk given
  -- how small/stable these two pieces are.
  keymaps = {
    ['zh'] = {
      callback = function()
        local cfg = require('aerial.config')
        cfg.highlight_on_hover = not cfg.highlight_on_hover
        if cfg.highlight_on_hover then
          -- Aerial only wires the highlight autocmds when the sidebar buffer
          -- is first created, gated on the flag at that moment — flipping it
          -- here doesn't retroactively attach them. The sidebar buffer also
          -- survives a plain close+open (aerial caches and reuses it), so
          -- force-delete it first to make aerial recreate it from scratch,
          -- this time with the autocmds registered.
          local aer_buf = vim.api.nvim_get_current_buf()
          require('aerial').close()
          if vim.api.nvim_buf_is_valid(aer_buf) then
            vim.api.nvim_buf_delete(aer_buf, { force = true })
          end
          require('aerial').open()
        else
          -- Flipping the flag off doesn't retroactively clear an
          -- already-highlighted source line — do it manually so it
          -- doesn't linger until the next unrelated redraw.
          local source_buf = vim.b.source_buffer
          if source_buf then
            require('aerial.render').clear_highlights(source_buf)
          end
        end
        vim.notify('Aerial: highlight-on-hover ' .. (cfg.highlight_on_hover and 'ON' or 'OFF'))
      end,
      desc = 'Toggle: highlight-on-hover (source buffer)',
    },
  },

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
