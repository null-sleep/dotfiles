-- Window/tab title: defaults to the project name (git toplevel, else cwd),
-- manually overridable with :Title <name> or <leader>ut (empty input reverts
-- to automatic). Neovim's 'titlestring' is a single mechanism that reaches
-- both surfaces this dotfiles setup cares about — iTerm2's tab/window title
-- (via the escape sequences the TUI emits) and Neovide's OS window title
-- (via the same `set_title` UI event, since Neovide is a standard Neovim UI
-- client) — so one option here drives both. Mirrors the shell's own
-- auto/override `title` function (see zsh/.zshrc_config.zsh) so cwd and nvim
-- agree when nvim isn't running.

local M = {}

local project_name

local function compute_project_name()
  local root = vim.fs.root(0, '.git')
  return vim.fs.basename(root or vim.uv.cwd())
end

local function refresh_project_name()
  project_name = compute_project_name()
end

-- Returned string becomes the literal titlestring — %t/%m style codes are
-- NOT re-expanded inside the result of a %{} expression item, so filename
-- and modified-flag are built here in Lua rather than left for vim to parse.
function M.titlestring()
  if vim.g.custom_title and vim.g.custom_title ~= '' then
    return vim.g.custom_title
  end
  local file = vim.fn.expand('%:t')
  if file == '' then file = '[No Name]' end
  local modified = vim.bo.modified and ' [+]' or ''
  return ('%s — %s%s'):format(project_name or '', file, modified)
end

refresh_project_name()

vim.api.nvim_create_autocmd('DirChanged', {
  group = vim.api.nvim_create_augroup('TitlingProjectName', { clear = true }),
  callback = refresh_project_name,
})

vim.o.title = true
vim.o.titlestring = '%{%v:lua.require("titling").titlestring()%}'

vim.api.nvim_create_user_command('Title', function(opts)
  vim.g.custom_title = opts.args ~= '' and opts.args or nil
end, { nargs = '?', desc = 'Set a custom window/tab title (empty clears override)' })

vim.keymap.set('n', '<leader>ut', function()
  vim.ui.input({ prompt = 'Window title (empty = auto): ', default = vim.g.custom_title or '' }, function(input)
    if input == nil then return end
    vim.g.custom_title = input ~= '' and input or nil
  end)
end, { desc = 'Set window/tab title' })

return M
