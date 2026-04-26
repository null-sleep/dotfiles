vim.g.mapleader = ' '

-- Disable unused providers to suppress checkhealth warnings
vim.g.loaded_python3_provider = 0

local opt = vim.opt

opt.number = true                      -- show line numbers
-- opt.relativenumber = true              -- relative line numbers (current line stays absolute)
opt.ignorecase = true                  -- case-insensitive search...
opt.smartcase = true                   -- ...unless you type a capital
opt.expandtab = true                   -- use spaces instead of tabs
opt.tabstop = 4                        -- Tab key inserts 4 spaces (default 8)
opt.shiftwidth = 4                     -- indent by 4 spaces
opt.undofile = true                    -- undo changes for a closed file
opt.undolevels = 10000                 -- increase undo history (default 1000)
-- Clipboard: y yanks to system clipboard (see keymaps.lua), but dd/x/c
-- stay in Neovim's default register so they don't clobber the clipboard.
opt.cursorline = true                  -- highlight current line
opt.updatetime = 300                   -- faster CursorHold and swap writes (default 4000ms)
opt.autowrite = true                   -- auto save when switching buffers or running commands
-- Minimum lines to keep visible above and below the cursor when scrolling
-- vertically. Prevents the cursor from reaching the screen edge, so you
-- always have context around the line you're editing.
opt.scrolloff = 10                     -- keep 10 lines above/below cursor
-- Same as scrolloff but for horizontal scrolling. Keeps columns visible
-- to the left and right of the cursor when side-scrolling long lines.
opt.sidescrolloff = 8                  -- keep 8 columns left/right of cursor
opt.fillchars = {
  foldopen  = '▾',                    -- icon for open folds
  foldclose = '▸',                    -- icon for closed folds
  fold      = ' ',                    -- fill character for fold lines
  foldsep   = ' ',                    -- separator between fold columns
  diff      = '╱',                    -- deleted lines in diff mode
  eob       = ' ',                    -- hides ~ tildes after end of file
}
opt.autoread = true                    -- auto reload files changed outside nvim
-- FocusGained:  terminal regains focus (e.g. alt-tab back)
-- BufEnter:     switching to a buffer (e.g. changing splits/tabs)
-- CursorHold:   cursor idle for 'updatetime' ms in normal mode
-- CursorHoldI:  same but in insert mode
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  command = 'checktime',
})
-- Poll for external changes every 1s (catches edits when nvim has no focus)
local timer = assert(vim.uv.new_timer())
timer:start(1000, 1000, vim.schedule_wrap(function()
  if vim.api.nvim_get_mode().mode == 'n' then
    vim.cmd('checktime')
  end
end))

opt.whichwrap:append('<,>,[,],h,l')    -- cursor wraps to next/prev line at end/start
opt.splitright = true                  -- vertical splits open to the right
opt.splitbelow = true                  -- horizontal splits open below

opt.backup = false                     -- no permanent backup files
opt.writebackup = false                -- no temporary backup during write
opt.swapfile = false                   -- no swap files (undofile handles recovery)

