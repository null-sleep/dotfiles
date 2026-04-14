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

-- Enable native treesitter highlighting and folding per buffer
local ts_group = vim.api.nvim_create_augroup('NativeTreesitterSetup', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = ts_group,
  desc = 'Enable native treesitter syntax highlighting',
  pattern = '*',
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
    if not lang then return end
    local ok = pcall(vim.treesitter.start, args.buf, lang)
    if not ok then
      -- Parser not installed, attempt to install it
      pcall(vim.cmd, 'TSInstall ' .. lang)
    end
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  group = ts_group,
  desc = 'Enable native treesitter AST folding',
  pattern = '*',
  callback = function()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldlevel = 99
  end,
})
