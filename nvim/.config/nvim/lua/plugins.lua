local gh = require('utils').gh
local themes = require('themes')

vim.pack.add(vim.list_extend({
  {
    src = gh('nvim-treesitter/nvim-treesitter'),
    version = 'main', -- Required for nvim 0.12 compatibility
  },
  {
    src = gh('nvim-tree/nvim-web-devicons'),
  },
  {
    src = gh('nvim-lua/plenary.nvim'),
  },
  {
    src = gh('nvim-telescope/telescope.nvim'),
  },
  {
    src = gh('nvim-telescope/telescope-fzf-native.nvim'),
  },
  { src = gh('mason-org/mason.nvim') },
  { src = gh('mason-org/mason-lspconfig.nvim') },
  { src = gh('neovim/nvim-lspconfig') },
  { src = gh('saghen/blink.cmp'), version = vim.version.range('1.*') },
}, themes.sources))

-- Apply colorscheme — must be after vim.pack.add so the plugin is on the runtimepath.
-- M.active may be a variant name (e.g. 'catppuccin-latte'); resolve back to the plugin
-- name for packadd and setup(), then apply the variant name as the colorscheme.
local active_plugin = themes.plugin[themes.active] or themes.active
vim.cmd.packadd(active_plugin)
if themes.setup[active_plugin] then themes.setup[active_plugin]() end
vim.cmd.colorscheme(themes.active)

-- Apply highlight overrides — global first, then per-theme on top.
-- Must run after colorscheme so they are not clobbered by the theme.
local function apply_overrides(overrides)
  for group, attrs in pairs(overrides) do
    vim.api.nvim_set_hl(0, group, attrs)
  end
end
apply_overrides(themes.overrides.global)
if themes.overrides[active_plugin] then
  apply_overrides(themes.overrides[active_plugin])
end

vim.cmd.packadd('nvim-web-devicons')
require('nvim-web-devicons').setup()

-- Re-compile parsers automatically when nvim-treesitter is updated
local pack_group = vim.api.nvim_create_augroup('NativePackHooks', { clear = true })
vim.api.nvim_create_autocmd('PackChanged', {
  group = pack_group,
  desc = 'Recompile treesitter parsers after plugin update',
  callback = function(ev)
    if ev.data.spec.name == 'nvim-treesitter' and ev.data.kind == 'update' then
      if not ev.data.active then
        vim.cmd.packadd('nvim-treesitter')
      end
      vim.notify('Triggering TSUpdate...', vim.log.levels.INFO)
      pcall(vim.cmd, 'TSUpdate')
    end
  end,
})

-- Compile fzf-native after install or update
vim.api.nvim_create_autocmd('PackChanged', {
  group = pack_group,
  desc = 'Compile fzf-native after install or update',
  callback = function(ev)
    if ev.data.spec.name == 'telescope-fzf-native.nvim' and ev.data.kind == 'update' then
      local plugin_path = vim.fn.stdpath('data') .. '/site/pack/core/opt/telescope-fzf-native.nvim'
      vim.fn.system({ 'make', '-C', plugin_path })
    end
  end,
})

-- Compile fzf-native on first install if not already built
pcall(function()
  local fzf_path = vim.fn.stdpath('data') .. '/site/pack/core/opt/telescope-fzf-native.nvim'
  local so_path = fzf_path .. '/build/libfzf.so'
  local dylib_path = fzf_path .. '/build/libfzf.dylib'
  if not vim.uv.fs_stat(so_path) and not vim.uv.fs_stat(dylib_path) then
    vim.fn.system({ 'make', '-C', fzf_path })
  end
end)

-- Install any missing parsers from the ensure_installed list
local ensure_installed = {
  'lua', 'python', 'javascript', 'typescript', 'go',
  'rust', 'markdown', 'json', 'yaml', 'ini', 'graphql',
}

pcall(function()
  vim.cmd.packadd('nvim-treesitter')
  local already_installed = require('nvim-treesitter.config').get_installed()
  local to_install = vim.iter(ensure_installed)
    :filter(function(p) return not vim.tbl_contains(already_installed, p) end)
    :totable()
  if #to_install > 0 then
    require('nvim-treesitter').install(to_install)
  end
end)

-- Load telescope and fzf-native
vim.cmd.packadd('plenary.nvim')
vim.cmd.packadd('telescope.nvim')
vim.cmd.packadd('telescope-fzf-native.nvim')

require('telescope').setup({
  defaults = {
    layout_strategy = 'horizontal',
    file_ignore_patterns = { '%.git/', 'node_modules/' },
  },
})

pcall(require('telescope').load_extension, 'fzf')

-- Returns true if the buffer is too large for treesitter to handle safely
local function is_large_buffer(buf)
  if vim.api.nvim_buf_line_count(buf) > 50000 then
    return true
  end
  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
  return ok and stats and stats.size > (1.5 * 1024 * 1024)
end

-- Attach treesitter highlighting, auto-installing the parser if missing
local function enable_highlighting(buf)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang then return end
  local ok = pcall(vim.treesitter.start, buf, lang)
  if not ok then
    pcall(vim.cmd, 'TSInstall ' .. lang)
  end
end

-- Use treesitter AST for code folding (files open fully expanded)
local function enable_folding()
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  vim.wo.foldlevel = 99
end

local ts_group = vim.api.nvim_create_augroup('NativeTreesitterSetup', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = ts_group,
  desc = 'Enable native treesitter highlighting and folding',
  pattern = '*',
  callback = function(args)
    if is_large_buffer(args.buf) then return end
    enable_highlighting(args.buf)
    enable_folding()
  end,
})
