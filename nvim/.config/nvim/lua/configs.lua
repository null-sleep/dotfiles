local opt = vim.opt

opt.number = true                      -- show line numbers
-- opt.relativenumber = true              -- relative line numbers (current line stays absolute)
opt.ignorecase = true                  -- case-insensitive search...
opt.smartcase = true                   -- ...unless you type a capital
opt.expandtab = true                   -- use spaces instead of tabs
opt.shiftwidth = 4                     -- indent by 4 spaces
opt.undofile = true                    -- undo changes for a closed file
opt.undolevels = 10000                 -- increase undo history (default 1000)
-- Use system clipboard locally, but disable it over SSH where clipboard
-- access is unavailable or slow. SSH_TTY is set when connected via SSH.
opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus"
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
-- Uncomment to use nicer fill characters for folds, diffs, and end-of-buffer.
-- Replaces default ASCII characters (+, -, ~) with cleaner unicode glyphs.
-- opt.fillchars = {
--   foldopen = "",                    -- icon for open folds
--   foldclose = "",                   -- icon for closed folds
--   fold = " ",                       -- fill character for fold lines
--   foldsep = " ",                    -- separator between fold columns
--   diff = "╱",                       -- deleted lines in diff mode
--   eob = " ",                        -- hides ~ tildes after end of file
-- }
opt.autoread = true                    -- auto reload files changed outside nvim
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
  command = 'checktime',
})

opt.backup = false                     -- no permanent backup files
opt.writebackup = false                -- no temporary backup during write
opt.swapfile = false                   -- no swap files (undofile handles recovery)
