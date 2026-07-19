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
    -- Drop the global scrolloff=10 / sidescrolloff=8 (configs.lua) the outline
    -- inherits: they leave phantom columns right of the longest symbol and pull
    -- the list out from under the cursor near the panel edges. aerial applies
    -- win_opts by window id on every open, so this survives reopen and new tabs
    -- — unlike a FileType autocmd, see filetree.lua's TreeOpen hook for why.
    -- Scrolling past the last symbol is clamped separately (autocmds.lua).
    win_opts = { scrolloff = 0, sidescrolloff = 0 },
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

-- Keymaps (global — toggles/search should work from any buffer, not just ones
-- aerial has attached to; see on_attach above for the buffer-local ]a/[a).
--
-- The toggles no-op (with a notify) from a non-code buffer — terminal,
-- sidekick CLI — where opening/focusing an outline is never useful. Sidebars
-- are exempted: they swap into each other (pressing <leader>o from the file
-- tree closes it and opens the outline), and pressing <leader>o from inside
-- aerial itself just closes it (normal toggle-off). Asking is_sidebar()
-- rather than naming filetypes keeps a future sidebar exempt automatically.
-- See buffers.lua / GUIDE.md "Non-code buffer exceptions need a shared
-- predicate" for the shared is_special() this is built on.
local buffers = require('buffers')
local function outline_guard()
  return buffers.is_special(0) and not buffers.is_sidebar(0)
end
-- Only one left-edge sidebar at a time: opening the outline closes whichever
-- other sidebar is showing. Guarded on aerial not already being open, so this
-- only fires on the OPEN edge of the toggle — closing the outline never
-- reaches into the others. See GUIDE.md "Left-edge sidebars swap into each
-- other".
vim.keymap.set('n', '<leader>o', function()
  if outline_guard() then
    vim.notify('Outline: not available in this buffer', vim.log.levels.WARN)
    return
  end
  local aerial = require('aerial')
  if not aerial.is_open() then
    buffers.close_other_sidebars('aerial')
  end
  aerial.toggle()
end, { desc = 'Toggle: Outline sidebar (aerial)' })
vim.keymap.set('n', '<leader>O', function()
  if outline_guard() then
    vim.notify('Outline: not available in this buffer', vim.log.levels.WARN)
    return
  end
  vim.cmd('AerialNavToggle')
end, { desc = 'Toggle: Outline nav popup (aerial)' })
-- No dedicated picker key for aerial's symbols — it would overlap <leader>sd
-- (document symbols picker, which also covers fields/variables) and the
-- sidebar/popup above.
