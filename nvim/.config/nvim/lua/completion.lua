vim.cmd.packadd('blink.cmp')

require('blink.cmp').setup({
  keymap = {
    preset = 'none',
    ['<Tab>']     = { 'select_next', 'fallback' },
    ['<S-Tab>']   = { 'select_prev', 'fallback' },
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
    documentation = { auto_show = true, auto_show_delay_ms = 200 },
  },

  signature = { enabled = true },

  -- Use Rust fuzzy matcher when binary is available, silently fall back to Lua.
  -- On first launch blink.cmp downloads the binary — prefer_rust avoids a
  -- startup warning before the download completes.
  fuzzy = { implementation = 'prefer_rust' },
})
