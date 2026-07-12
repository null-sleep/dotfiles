-- Neovide-only configuration. Terminal nvim skips this file entirely.
if not vim.g.neovide then return end

-- Tone down default animations. Defaults feel a bit floaty; shorter durations
-- keep cursor/scroll snappy without disabling animation. Set to 0 to disable.
vim.g.neovide_cursor_animation_length = 0.05
vim.g.neovide_scroll_animation_length = 0.1
vim.g.neovide_position_animation_length = 0.05
vim.g.neovide_cursor_trail_size = 0.3

-- Treat Option as Meta so <M-...> keymaps work (buffer picker rows, picker
-- <M-q>/<M-d>). Without this, Option types special chars like ¡, ™.
vim.g.neovide_input_macos_option_key_is_meta = 'both'

vim.g.neovide_hide_mouse_when_typing = true
vim.g.neovide_proxy_icon = true
vim.g.neovide_floating_corner_radius = 0.2

-- Breathing room between the window edge and the text — Neovide defaults to
-- 0, which puts sidebar/gutter content flush against the edge; iTerm2 pads
-- its panes by roughly this much. Top is left at 0: the titlebar already
-- separates content vertically.
vim.g.neovide_padding_left = 4
vim.g.neovide_padding_right = 4
vim.g.neovide_padding_bottom = 4
vim.g.neovide_padding_top = 0

-- Neovide draws a drop shadow around floating windows by default; a terminal like
-- iTerm2 can't, so floats look flatter there. Disable it so floats (toggleterm,
-- pickers, etc.) render with clean flat edges that match terminal nvim.
vim.g.neovide_floating_shadow = false

-- Keep the 'Neovide:' desc prefix on every keymap below: <leader>sk derives its
-- tag pill from the text before the first ':', so they show up as +neovide.

-- Cmd+Opt+Left/Right for jumplist navigation (editor-style back/forward
-- through go-to-definition, search jumps, etc.). Terminal nvim can't receive
-- Cmd, which is why this lives in the Neovide-only file.
vim.keymap.set('n', '<D-M-Left>',  '<C-o>', { desc = 'Neovide: Jumplist back' })
vim.keymap.set('n', '<D-M-Right>', '<C-i>', { desc = 'Neovide: Jumplist forward' })

-- Standard macOS clipboard / save shortcuts.
-- <C-r>+ is only a paste in insert/cmdline mode — in normal mode <C-r> is
-- redo, so n/v need real put commands. Visual uses "_d"+P (delete selection
-- into the black hole, put from clipboard) to match the register-preserving
-- v-mode `p` mapping in keymaps.lua.
vim.keymap.set('x', '<D-c>', '"+y',          { desc = 'Neovide: Copy' })
vim.keymap.set('n', '<D-v>', '"+p',              { desc = 'Neovide: Paste' })
vim.keymap.set('x', '<D-v>', '"_d"+P',           { desc = 'Neovide: Paste over selection' })
vim.keymap.set({ 'i', 'c' }, '<D-v>', '<C-r>+',  { desc = 'Neovide: Paste' })
vim.keymap.set('t', '<D-v>', [[<C-\><C-n>"+pi]],          { desc = 'Neovide: Paste (terminal)' })
vim.keymap.set({ 'n', 'i', 'x' }, '<D-s>', '<Cmd>w<CR>',   { desc = 'Neovide: Save' })

-- Cmd+= / Cmd+- to zoom in/out (adjusts scale factor, font stays sharp).
vim.g.neovide_scale_factor = 1.0
local function change_scale(delta)
  vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
end
vim.keymap.set('n', '<D-=>', function() change_scale(1.1) end,   { desc = 'Neovide: Zoom in' })
vim.keymap.set('n', '<D-->', function() change_scale(1 / 1.1) end, { desc = 'Neovide: Zoom out' })
vim.keymap.set('n', '<D-0>', function() vim.g.neovide_scale_factor = 1.0 end, { desc = 'Neovide: Reset zoom' })
