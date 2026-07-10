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
