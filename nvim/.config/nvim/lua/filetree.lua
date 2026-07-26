-- More configuration ideas: https://github.com/nvim-tree/nvim-tree.lua/wiki/Recipes
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
  -- Filter directory names too, not just file names (default only filters files)
  live_filter = { always_show_folders = false },
  -- Rename/delete confirmations go through vim.ui.select (snacks picker)
  select_prompts = true,
  diagnostics = { enable = false },
  -- Mark buffers with unsaved changes
  modified = { enable = true },
  renderer = {
    -- Highlight file names by git status (green=new, yellow=modified, etc.)
    highlight_git = 'name',
    -- Highlight files with unsaved changes
    highlight_modified = 'name',
    -- Highlight files with an open buffer (any window). Color comes from the
    -- NvimTreeOpenedHL override in themes.lua, not this option.
    highlight_opened_files = 'all',
    -- Indent lines make hierarchy easier to read
    indent_markers = { enable = true },
    icons = {
      -- Uses mini.icons (already mocked as nvim-web-devicons)
      show = { file = true, folder = true, git = true, modified = true, diagnostics = false },
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
    -- H to collapse entire tree (h only closes one level; H resets the whole thing)
    vim.keymap.set('n', 'H', api.tree.collapse_all,          vim.tbl_extend('force', opts, { desc = 'Collapse all' }))
    -- L to open file in vertical split while keeping tree focused (preview mode)
    vim.keymap.set('n', 'L', function()
      local node = api.tree.get_node_under_cursor()
      if node and node.nodes then
        api.node.open.edit()
      else
        api.node.open.vertical()
      end
      api.tree.focus()
    end, vim.tbl_extend('force', opts, { desc = 'Vsplit preview' }))
    -- <CR> opens in the current window (no new tabs)
    vim.keymap.set('n', '<CR>', api.node.open.edit,          vim.tbl_extend('force', opts, { desc = 'Open' }))
    -- Delete/split keys should match the convention
    vim.keymap.set('n', '<C-x>', api.node.buffer.delete,     vim.tbl_extend('force', opts, { desc = 'Close buffer of file under cursor' }))
    vim.keymap.set('n', '<C-s>', api.node.open.horizontal,   vim.tbl_extend('force', opts, { desc = 'Open in horizontal split' }))
  end,
  -- Narrow sidebar width
  -- For adaptive width: view = { width = { min = 35, max = 50 } }
  view = { width = 35 },
})

do
  local api = require('nvim-tree.api')

  -- Auto-open newly created files immediately after `a` in the tree
  api.events.subscribe(api.events.Event.FileCreated, function(file)
    vim.cmd('edit ' .. vim.fn.fnameescape(file.fname))
  end)

  -- Drop the global sidescrolloff=8 / scrolloff=10 (configs.lua) the tree
  -- inherits: they leave phantom columns right of the longest name, and pull the
  -- list out from under the cursor near the panel edges.
  --
  -- Set from TreeOpen, by window id — NOT from a FileType autocmd. nvim-tree
  -- sets the filetype while the buffer is in no window, so FileType fires inside
  -- Neovim's aucmd_win (win_gettype() == 'autocmd') and a vim.wo write there
  -- dies with that scratch window. TreeOpen fires after open_window(), so
  -- api.tree.winid() is the real window. See GUIDE.md "Window options for a
  -- panel must be set by window id".
  --
  -- This does NOT stop scrolling past the last file — scrolloff has no effect at
  -- EOF. That's the scroll clamp in autocmds.lua.
  api.events.subscribe(api.events.Event.TreeOpen, function()
    local win = api.tree.winid()
    if win then
      vim.wo[win].scrolloff = 0
      vim.wo[win].sidescrolloff = 0
    end
  end)
end

-- Event half of nvim-lsp-file-operations — capability half in lsp.lua, keep in
-- sync (grep 'lsp-file-operations'); missing either half silently no-ops, no
-- error. Subscribes to nvim-tree's rename events so an in-tree rename rewrites
-- importers (an external `git mv` can't be caught).
-- Rationale in GUIDE.md "Renaming a file rewrites its imports".
--
-- After nvim-tree.setup() so its event API is loaded. Run-once guarded because
-- api.events.subscribe is append-only — a `:source %` would double-fire it.
if not vim.g._lsp_file_ops_setup then
  vim.g._lsp_file_ops_setup = true
  vim.cmd.packadd('nvim-lsp-file-operations')
  require('lsp-file-operations').setup()
end

-- Auto-quit when only sidebars remain: generalized across all sidebars
-- (nvim-tree, aerial) and lives in autocmds.lua now — see
-- GUIDE.md "Quit nvim when only sidebars remain".
