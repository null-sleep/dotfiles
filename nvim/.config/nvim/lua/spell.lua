local M = {}

-- Add word under cursor to the personal dictionary, skipping duplicates.
-- Wraps the built-in zg to prevent the spellfile accumulating repeated entries.
function M.add_word()
  local word = vim.fn.expand('<cword>')
  local spellfile = vim.opt.spellfile:get()[1]
  local ok, lines = pcall(vim.fn.readfile, spellfile)
  if ok then
    for _, line in ipairs(lines) do
      if line == word then
        vim.notify('"' .. word .. '" already in dictionary', vim.log.levels.INFO)
        return
      end
    end
  end
  vim.cmd('normal! zg')
end

return M
