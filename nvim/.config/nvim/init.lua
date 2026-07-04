vim.g.mapleader = ' '
require('configs')
require('plugins')
require('treesitter_context')  -- sticky scope header (VS Code-style sticky scroll)
require('outline')             -- outline sidebar + telescope picker (aerial.nvim)
require('structural_select')   -- Helix-style <M-o>/<M-i> expand/shrink selection
require('keymaps')
require('completion')
require('lsp')
require('rust')       -- rustaceanvim (must precede testing: provides rustaceanvim.neotest)
require('debugging')  -- nvim-dap + dap-ui
require('testing')    -- neotest
require('ai')
require('format')
require('linting')
require('statusline')
require('session')
require('gpg_watch')
require('git')
require('gitui')  -- neogit.nvim (Magit-style dashboard) + diffview.nvim
require('terminal')
require('titling')
require('whichkey')
require('autosave')
require('filetree')
require('neovide')

