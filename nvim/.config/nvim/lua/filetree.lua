vim.cmd.packadd('nvim-tree.lua')

-- Disable netrw (nvim-tree's recommendation)
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

require('nvim-tree').setup({
  -- Show git status decorations on files/dirs
  git = { enable = true },
  -- Keep the tree in sync with the current buffer's file
  update_focused_file = { enable = true },
  -- Show hidden files (dotfiles) by default; hide common clutter (toggle with U)
  filters = {
    dotfiles = false,
    custom = { '.git', '.DS_Store', 'node_modules' },
  },
  -- Rename/delete confirmations go through vim.ui.select (telescope-ui-select)
  select_prompts = true,
  -- LSP diagnostics icons next to files (error/warn/info/hint)
  diagnostics = {
    enable = true,
    show_on_dirs = true,
  },
  -- Mark buffers with unsaved changes
  modified = { enable = true },
  renderer = {
    -- Highlight file names by git status (green=new, yellow=modified, etc.)
    highlight_git = 'name',
    -- Highlight files with unsaved changes
    highlight_modified = 'name',
    -- Indent lines make hierarchy easier to read
    indent_markers = { enable = true },
    icons = {
      -- Uses mini.icons (already mocked as nvim-web-devicons)
      show = { file = true, folder = true, git = true, modified = true, diagnostics = true },
      -- VS Code style: small letter on the right instead of icon glyphs
      git_placement = 'right_align',
      glyphs = {
        git = {
          unstaged  = 'M',
          staged    = 'S',
          unmerged  = 'U',
          renamed   = 'R',
          untracked = 'U',
          deleted   = 'D',
          ignored   = '',
        },
      },
    },
  },
  -- Sort uppercase files separately (matches ls / most file explorers)
  sort = { sorter = 'case_sensitive' },
  -- `D` in the tree sends files to macOS trash instead of permanent deletion.
  -- `d` remains permanent delete. macOS ships /usr/bin/trash natively.
  trash = { cmd = 'trash' },
  -- File nesting (e.g. package-lock.json under package.json) is not supported
  -- by nvim-tree. Use neo-tree.nvim if this is important.
  on_attach = function(bufnr)
    local api = require('nvim-tree.api')
    -- Start with default mappings
    api.config.mappings.default_on_attach(bufnr)
    local opts = { buffer = bufnr, nowait = true }
    -- l/h to open/collapse (mirrors Zed/VS Code Enter behaviour)
    vim.keymap.set('n', 'l', api.node.open.edit,             vim.tbl_extend('force', opts, { desc = 'Open / expand' }))
    vim.keymap.set('n', 'h', api.node.navigate.parent_close, vim.tbl_extend('force', opts, { desc = 'Collapse dir' }))
  end,
  -- Narrow sidebar width
  -- For adaptive width: view = { width = { min = 35, max = 50 } }
  view = { width = 35 },
})

-- Auto-close nvim when the tree is the last window open
vim.api.nvim_create_autocmd('QuitPre', {
  group = vim.api.nvim_create_augroup('NvimTreeAutoClose', { clear = true }),
  desc = 'Close nvim-tree when it is the last window',
  callback = function()
    local tree_wins = {}
    local floating_wins = {}
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
      if bufname:match('NvimTree_') then
        table.insert(tree_wins, w)
      end
      if vim.api.nvim_win_get_config(w).relative ~= '' then
        table.insert(floating_wins, w)
      end
    end
    -- If the only non-floating windows left are nvim-tree windows, close them
    if #wins - #floating_wins - #tree_wins == 1 then
      for _, w in ipairs(tree_wins) do
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end,
})
