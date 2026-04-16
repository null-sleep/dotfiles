vim.cmd.packadd('gitsigns.nvim')

require('gitsigns').setup({
  signs = {
    add          = { text = '┃' },
    change       = { text = '┃' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
    untracked    = { text = '┆' },
  },
})

-- Scrollbar with git, diagnostic, search and cursor marks.
-- Gitsigns integration is automatic — satellite detects gitsigns via package.loaded.
vim.cmd.packadd('satellite.nvim')

require('satellite').setup({
  current_only = false,   -- show scrollbar on all windows, not just the focused one
  winblend     = 50,      -- scrollbar transparency (0 = opaque, 100 = invisible)
  width        = 2,
  excluded_filetypes = { 'TelescopePrompt', 'mason', 'lazy' },
  handlers = {
    cursor     = { enable = true },
    search     = { enable = true },
    diagnostic = { enable = true },
    gitsigns   = { enable = true },
    marks      = { enable = false },  -- marks off by default, enable if you use vim marks
    quickfix   = { enable = true },
  },
})
