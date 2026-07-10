-- Disable unused providers to suppress checkhealth warnings
vim.g.loaded_python3_provider = 0

local opt = vim.opt

opt.number = true                      -- show line numbers; toggle relative with <leader>tn
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
opt.cmdheight = 0                      -- hide command line when not in use (appears on demand)
opt.autoread = true                    -- auto reload files changed outside nvim
-- FocusGained:  terminal regains focus (e.g. alt-tab back)
-- BufEnter:     switching to a buffer (e.g. changing splits/tabs)
-- CursorHold:   cursor idle for 'updatetime' ms in normal mode
-- CursorHoldI:  same but in insert mode
-- clear = true: wipe any existing autocmds in this group so re-sourcing
-- this file doesn't create duplicates.
local checktime_group = vim.api.nvim_create_augroup('UserChecktime', { clear = true })
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  group = checktime_group,
  desc = 'Reload files changed outside Neovim',
  command = 'checktime',
})
-- Poll for external changes every 500ms (catches edits when nvim has no focus).
-- Checks ALL open buffers against disk; reloads silently when 'autoread' is set.
-- Only fires in normal mode to avoid disrupting insert/visual/cmdline edits.
-- Stored on _G so re-sourcing stops the old timer before creating a new one
-- (close() too — a stopped-but-unclosed uv handle leaks).
if _G._checktime_timer then
  _G._checktime_timer:stop()
  _G._checktime_timer:close()
end
_G._checktime_timer = assert(vim.uv.new_timer())
_G._checktime_timer:start(500, 500, vim.schedule_wrap(function()
  if vim.api.nvim_get_mode().mode == 'n' then
    vim.cmd('checktime')
  end
end))

opt.whichwrap:append('<,>,[,],h,l')    -- cursor wraps to next/prev line at end/start
opt.wrap = true                        -- wrap long lines
opt.splitright = true                  -- vertical splits open to the right
opt.splitbelow = true                  -- horizontal splits open below

-- Better diff alignment. linematch:60 pairs up similar lines within a hunk so
-- a one-token edit reads as a change instead of a delete+add block; the
-- histogram algorithm produces more stable, less jumpy hunks than the default
-- Myers. Append (don't assign) so the built-in defaults — internal, filler,
-- closeoff — survive. Visible everywhere diffs render: diffview.nvim, Neogit,
-- gitsigns hunk previews, `nvim -d`.
opt.diffopt:append('linematch:60')
opt.diffopt:append('algorithm:histogram')

opt.spell = false                      -- spell checking off by default; toggle with <leader>tz
opt.spelllang = 'en_us'                -- language: US English
-- Explicit path so zg additions land in the stowed dotfiles folder and can
-- be committed. nvim creates the file on first zg if it doesn't exist.
opt.spellfile = vim.fn.stdpath('config') .. '/spell/en.utf-8.add'

opt.backup = false                     -- no permanent backup files
opt.writebackup = false                -- no temporary backup during write
opt.swapfile = false                   -- no swap files (undofile handles recovery)

-- justfile detection: map justfiles to the 'just' filetype so the treesitter
-- parser and conform's just formatter attach. Covers the common spellings in
-- case the running Neovim doesn't ship just detection natively.
vim.filetype.add({
  filename = {
    justfile = 'just',
    Justfile = 'just',
    ['.justfile'] = 'just',
  },
  pattern = {
    ['.*%.just'] = 'just',
  },
})

require('utils').check_nvim_update()

