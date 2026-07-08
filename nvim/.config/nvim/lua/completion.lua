vim.cmd.packadd('blink.cmp')

require('blink.cmp').setup({
  keymap = {
    preset = 'none',
    -- Tab priority (matches VS Code / Zed): completion menu wins over ghost text.
    -- 1. select_next: if blink menu is open, navigate it
    -- 2. inline completion: if Copilot ghost text is showing, accept it
    -- 3. fallback: literal Tab
    ['<Tab>']     = {
      'select_next',
      function()
        -- get() both applies the pending ghost text and returns whether one
        -- existed (there is no separate accept() in the 0.12 API).
        if vim.lsp.inline_completion.is_enabled({ bufnr = 0 })
            and vim.lsp.inline_completion.get() then
          return true
        end
      end,
      'fallback',
    },
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
    -- Disable blink ghost text — Copilot inline completion provides its own ghost
    -- text via vim.lsp.inline_completion. Both use virt_text_pos='inline' and would
    -- overlap if both were active.
    ghost_text = { enabled = false },
  },

  -- signature: show parameter hints while typing inside a function call
  signature = { enabled = true },

  -- Use Rust fuzzy matcher when binary is available, silently fall back to Lua.
  -- On first launch blink.cmp downloads the binary — prefer_rust avoids a
  -- startup warning before the download completes.
  fuzzy = { implementation = 'prefer_rust' },
})
