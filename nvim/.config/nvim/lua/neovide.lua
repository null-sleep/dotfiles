-- Neovide-only configuration. Terminal nvim skips this file entirely.
if not vim.g.neovide then return end

-- Tone down default animations. Defaults feel a bit floaty; shorter durations
-- keep cursor/scroll snappy without disabling animation. Set to 0 to disable.
vim.g.neovide_cursor_animation_length = 0.05
vim.g.neovide_scroll_animation_length = 0.1
vim.g.neovide_position_animation_length = 0.05
vim.g.neovide_cursor_trail_size = 0.3

-- Treat Option as Meta so <M-...> keymaps work (buffer picker rows, telescope
-- <M-q>/<M-d>). Without this, Option types special chars like ¡, ™.
vim.g.neovide_input_macos_option_key_is_meta = 'both'

vim.g.neovide_hide_mouse_when_typing = true
vim.g.neovide_proxy_icon = true
vim.g.neovide_floating_corner_radius = 0.2

-- Cmd+Opt+Left/Right for jumplist navigation (editor-style back/forward
-- through go-to-definition, search jumps, etc.). Terminal nvim can't receive
-- Cmd, which is why this lives in the Neovide-only file.
vim.keymap.set('n', '<D-M-Left>',  '<C-o>', { desc = 'Jumplist: Back' })
vim.keymap.set('n', '<D-M-Right>', '<C-i>', { desc = 'Jumplist: Forward' })

-- Standard macOS clipboard / save shortcuts.
vim.keymap.set('v', '<D-c>', '"+y',          { desc = 'Copy' })
vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<D-v>', '<C-r>+', { desc = 'Paste' })
vim.keymap.set('t', '<D-v>', [[<C-\><C-n>"+pi]],          { desc = 'Paste (terminal)' })
vim.keymap.set({ 'n', 'i', 'v' }, '<D-s>', '<Cmd>w<CR>',   { desc = 'Save' })

-- Cmd+= / Cmd+- to zoom in/out (adjusts scale factor, font stays sharp).
vim.g.neovide_scale_factor = 1.0
local function change_scale(delta)
  vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
end
vim.keymap.set('n', '<D-=>', function() change_scale(1.1) end,   { desc = 'Zoom in' })
vim.keymap.set('n', '<D-->', function() change_scale(1 / 1.1) end, { desc = 'Zoom out' })
vim.keymap.set('n', '<D-0>', function() vim.g.neovide_scale_factor = 1.0 end, { desc = 'Reset zoom' })
