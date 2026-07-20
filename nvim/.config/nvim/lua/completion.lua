vim.cmd.packadd('blink.cmp')

require('blink.cmp').setup({
  keymap = {
    preset = 'none',
    -- Tab priority:
    -- 1. select_next: if blink menu is open, navigate it
    -- 2. snippet_forward: if a snippet session is active, jump to next placeholder
    -- 3. fallback: literal Tab
    --
    -- snippet_forward/backward are explicit even though fallback alone worked
    -- (it reached Neovim's default snippet-aware <Tab> from _defaults.lua) —
    -- explicit entries don't silently break if blink's fallback resolution or
    -- the core default mapping changes. Per LazyVim's supertab recipe.
    ['<Tab>']     = { 'select_next', 'snippet_forward', 'fallback' },
    ['<S-Tab>']   = { 'select_prev', 'snippet_backward', 'fallback' },
    ['<CR>']      = { 'accept', 'fallback' },
    ['<C-u>']     = { 'scroll_documentation_up', 'fallback' },
    ['<C-d>']     = { 'scroll_documentation_down', 'fallback' },
    ['<C-e>']     = { 'cancel', 'fallback' },
    ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
  },

  appearance = {
    nerd_font_variant = 'mono',
  },

  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
  },

  completion = {
    -- auto_show: open docs popup automatically when hovering a completion item
    documentation = { auto_show = true, auto_show_delay_ms = 200 },
    -- preselect: don't auto-highlight the first item so <CR> only accepts when explicitly tabbed to
    list = {
      selection = { preselect = false },
    },
    -- auto_brackets: append () after completing a function and place cursor inside
    accept = { auto_brackets = { enabled = true } },
    -- Ghost text off by choice: with preselect = false above, blink only renders
    -- it once an item is selected (show_without_selection defaults false), by
    -- which point the menu already highlights that item — near-zero value.
    -- Enabling it usefully means also setting show_without_selection = true AND
    -- preselect = true, so <CR> accepts what's previewed. (Previously off to
    -- avoid overlapping Copilot's inline completion, now removed.)
    ghost_text = { enabled = false },
  },

  -- signature: show parameter hints while typing inside a function call
  signature = { enabled = true },

  -- Use Rust fuzzy matcher when binary is available, silently fall back to Lua.
  -- On first launch blink.cmp downloads the binary — prefer_rust avoids a
  -- startup warning before the download completes.
  fuzzy = { implementation = 'prefer_rust' },
})
