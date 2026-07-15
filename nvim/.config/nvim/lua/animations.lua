-- Terminal-only animation (smear-cursor + cinnamon). Neovide animates
-- natively (see neovide.lua) — running these on top would double-animate.
if vim.g.neovide then return end

vim.cmd.packadd('smear-cursor.nvim')
require('smear_cursor').setup({})

vim.cmd.packadd('cinnamon.nvim')
require('cinnamon').setup({
  keymaps = { basic = true },
})
