local gh = require('utils').gh

-- Install treesitter parsers via vim.pack
vim.pack.add({
  {
    src = gh('nvim-treesitter/nvim-treesitter'),
    version = 'main', -- Required for nvim 0.12 compatibility
  },
})

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
