vim.g.mapleader = ' '
require('configs')
require('plugins')
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
require('git')
require('terminal')
require('whichkey')
require('autosave')
require('filetree')
require('neovide')

