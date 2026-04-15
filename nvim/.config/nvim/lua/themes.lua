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
}

return M
