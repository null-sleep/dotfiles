vim.cmd.packadd('gitsigns.nvim')

require('gitsigns').setup({
  attach_to_untracked = true,
  signs = {
    add          = { text = '▎' },
    change       = { text = '▎' },
    delete       = { text = '▂' },
    topdelete    = { text = '▔' },
    changedelete = { text = '▎' },
    untracked    = { text = '░' },
  },
  on_attach = function(buf)
    local gs = require('gitsigns')
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    map('n', '<leader>hb', function() gs.blame_line({ full = true }) end, 'Git hunk: Blame line')
    map('n', '<leader>tb', gs.toggle_current_line_blame,                  'Toggle: Inline blame')
  end,
})

-- Scrollbar with git, diagnostic, search and cursor marks.
-- Gitsigns integration is automatic — satellite detects gitsigns via package.loaded.
vim.cmd.packadd('satellite.nvim')

require('satellite').setup({
  current_only = true,    -- show scrollbar only on the focused window
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
