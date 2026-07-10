-- General editor autocmds that aren't owned by a specific feature module.
-- (Feature-local autocmds still live with their feature: checktime in
-- configs.lua, QuitPre in filetree.lua, lint-on-save in linting.lua, etc.)
-- One augroup, cleared on re-source so `:source %` never duplicates handlers
-- (see GUIDE.md "Re-source safety").
local augroup = vim.api.nvim_create_augroup('UserAutocmds', { clear = true })

-- Auto-create missing parent directories when writing a file, so
-- `:e src/new/deep/file.lua` followed by `:w` doesn't fail with "no such
-- file or directory" — nvim writes the intervening dirs for you.
-- Guarded to skip URL-style buffer names (`fugitive://`, `oil://`, etc.):
-- those aren't real filesystem paths and must never be mkdir'd.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = augroup,
  desc = 'Create missing parent dirs on save',
  callback = function(args)
    if args.match:match('^%w+://') then return end
    local dir = vim.fs.dirname(vim.fs.abspath(args.match))
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end,
})

-- Restore the cursor to its last position when reopening a file. Neovim core
-- still does NOT do this (verified against 0.12.4's `_defaults.lua`). Reads
-- the `"` mark (last cursor position, persisted in the shada file) on
-- BufReadPost and jumps there.
--
-- NOTE FOR FUTURE WORK — this handler fires on `BufReadPost`, which runs for
-- every file *read from disk*. It is deliberately NOT guarded by
-- buftype/`is_special()`, and that's safe because:
--   * synthetic panels (nvim-tree, aerial, sidekick, `:terminal`) are built
--     in memory and never fire BufReadPost, so they can't reach this code;
--   * snacks scratch buffers are disk-backed and MAY fire it, but restoring
--     their cursor is harmless (desirable, even);
--   * the only real disk files we must skip are gitcommit/gitrebase (you
--     always want line 1 there) — handled by the filetype check below.
-- If some future plugin abuses BufReadPost on a synthetic buffer and this
-- misbehaves, the fix is a `vim.bo[args.buf].buftype == ''` guard here — not
-- needed today. See GUIDE.md "Cursor-restore rides BufReadPost".
vim.api.nvim_create_autocmd('BufReadPost', {
  group = augroup,
  desc = 'Restore last cursor position',
  callback = function(args)
    -- Run at most once per buffer — BufReadPost can fire again on a later `:e`.
    if vim.b[args.buf].last_loc_restored then return end
    vim.b[args.buf].last_loc_restored = true
    local ft = vim.bo[args.buf].filetype
    if ft == 'gitcommit' or ft == 'gitrebase' then return end
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(args.buf)
    -- Only jump if the saved line is still within the (possibly shrunk) file.
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Briefly flash yanked text so you can see exactly what landed in the
-- register. Extra useful here because of the split-clipboard maps (`y` yanks
-- to the system clipboard, `dd`/`x`/`c` stay in the default register — see
-- keymaps.lua): the flash confirms which characters/lines were captured.
vim.api.nvim_create_autocmd('TextYankPost', {
  group = augroup,
  desc = 'Highlight yanked text',
  callback = function() vim.hl.on_yank() end,
})
