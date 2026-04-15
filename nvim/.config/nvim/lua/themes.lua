local gh = require('utils').gh

-- Active theme — change this to switch colorscheme
local M = {}

M.active = 'catppuccin'

-- Plugin sources — all registered with vim.pack, only the active one is used at runtime
M.sources = {
  { src = gh('catppuccin/nvim'),           name = 'catppuccin' },
  { src = gh('folke/tokyonight.nvim') },
  { src = gh('ellisonleao/gruvbox.nvim') },
  { src = gh('rose-pine/neovim'),          name = 'rose-pine' },
  { src = gh('rebelot/kanagawa.nvim') },
  { src = gh('Mofiqul/dracula.nvim') },
}

-- Per-theme setup() calls — run before colorscheme is applied.
-- Only the active theme's setup (if any) is called.
M.setup = {
  dracula = function()
    require('dracula').setup({
      italic_comment = true,
    })
  end,
}

return M
