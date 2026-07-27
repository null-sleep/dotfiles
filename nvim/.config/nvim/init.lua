vim.g.mapleader = ' '
require('configs')
require('autocmds')  -- general editor autocmds (mkdir-on-save, cursor restore, yank hl, ...)
require('plugins')
require('picker')              -- snacks.nvim setup: picker (fuzzy finder) + scratch + indent modules
require('treesitter_context')  -- sticky scope header (VS Code-style sticky scroll)
require('outline')             -- outline sidebar + nav popup (aerial.nvim)
require('quickfix')            -- quicker.nvim: editable, styled quickfix/loclist window
require('structural_select')   -- Helix-style <M-o>/<M-i> expand/shrink selection
require('keymaps')
require('completion')
require('lsp')
require('rust')       -- rustaceanvim (must precede testing: provides rustaceanvim.neotest)
require('debugging')  -- nvim-dap + dap-ui
require('golang')     -- nvim-dap-go (delve adapter) + Go ft keymaps (must follow debugging: needs nvim-dap on the rtp)
require('testing')    -- neotest
require('ai')
require('format')
require('linting')
require('statusline')
require('session')
require('git')
require('gitui')  -- neogit.nvim (Magit-style dashboard) + diffview.nvim
require('terminal')
require('scratch')  -- snacks.nvim scratch buffer keymaps (setup lives in picker.lua)
require('grugfar')  -- grug-far.nvim: project-wide find & replace (<leader>sR)
require('titling')
require('whichkey')
require('autosave')
require('filetree')
require('animations')
require('neovide')
require('cleanup')  -- :Cleanup + the weekly on-disk-state sweep (armed in configs.lua)

