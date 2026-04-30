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
    -- auto_show: open docs popup automatically when hovering a completion item
    documentation = { auto_show = true, auto_show_delay_ms = 200 },
    -- preselect: don't auto-highlight the first item so <CR> only accepts when explicitly tabbed to
    list = {
      selection = { preselect = false },
    },
    -- auto_brackets: append () after completing a function and place cursor inside
    accept = { auto_brackets = { enabled = true } },
    -- ghost_text: shows top completion suggestion faded inline as you type; accept with <Right>
    -- Tab/Shift-Tab still navigate the dropdown as usual
    ghost_text = { enabled = true },
  },

  -- signature: show parameter hints while typing inside a function call
  signature = { enabled = true },

  -- Use Rust fuzzy matcher when binary is available, silently fall back to Lua.
  -- On first launch blink.cmp downloads the binary — prefer_rust avoids a
  -- startup warning before the download completes.
  fuzzy = { implementation = 'prefer_rust' },
})
