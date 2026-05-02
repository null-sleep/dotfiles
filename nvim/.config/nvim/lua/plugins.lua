local gh = require('utils').gh
local themes = require('themes')

-- Register plugins with vim.pack (nvim 0.12 native package manager).
-- Theme sources are appended from themes.lua.
vim.pack.add(vim.list_extend({
  -- Treesitter
  { src = gh('nvim-treesitter/nvim-treesitter'), version = 'main' },

  -- Telescope (fuzzy finder)
  { src = gh('nvim-lua/plenary.nvim') },
  { src = gh('nvim-telescope/telescope.nvim') },
  { src = gh('nvim-telescope/telescope-fzf-native.nvim') },

  -- LSP
  { src = gh('mason-org/mason.nvim') },
  { src = gh('mason-org/mason-lspconfig.nvim') },
  { src = gh('neovim/nvim-lspconfig') },
  { src = gh('folke/lazydev.nvim') },

  -- Completion
  { src = gh('saghen/blink.cmp'), version = vim.version.range('1.*') },

  -- UI
  { src = gh('echasnovski/mini.icons') },
  { src = gh('echasnovski/mini.notify') },
  { src = gh('nvim-lualine/lualine.nvim') },
  { src = gh('lewis6991/satellite.nvim') },
  { src = gh('folke/which-key.nvim') },
  { src = gh('MeanderingProgrammer/render-markdown.nvim') },

  -- Git
  { src = gh('lewis6991/gitsigns.nvim') },

  -- Workflow
  { src = gh('folke/persistence.nvim') },
  { src = gh('okuuva/auto-save.nvim') },
  { src = gh('windwp/nvim-autopairs') },
  { src = gh('stevearc/conform.nvim') },
  { src = gh('akinsho/toggleterm.nvim') },
  -- AI: NES (Copilot LSP) + Claude/Copilot CLI integration.
  -- TODO: flip src back to 'folke/sidekick.nvim' once PR #277 merges
  -- (https://github.com/folke/sidekick.nvim/pull/277).
  {
    src = gh('alvarosevilla95/sidekick.nvim'),
    version = 'fix/nes-missing-request-id',
  },
}, themes.sources))

-- Warn about orphaned plugins (on disk but not in vim.pack.add list)
vim.defer_fn(function()
  local orphans = vim.iter(vim.pack.get(nil, { info = false }))
    :filter(function(x) return not x.active end)
    :map(function(x) return x.spec.name end)
    :totable()
  if #orphans > 0 then
    local quoted = vim.tbl_map(function(n) return '"' .. n .. '"' end, orphans)
    vim.notify(
      'Orphaned plugins — remove with:\n  :lua vim.pack.del({' .. table.concat(quoted, ', ') .. '})\n\n'
        .. table.concat(orphans, '\n'),
      vim.log.levels.WARN
    )
  end
end, 1000)

-------------------------------------------------------------------------------
-- Theme
-------------------------------------------------------------------------------

themes.apply(themes.active)

-------------------------------------------------------------------------------
-- Icons
-------------------------------------------------------------------------------

vim.cmd.packadd('mini.icons')
require('mini.icons').setup()
-- mock_nvim_web_devicons makes mini.icons a drop-in for plugins expecting nvim-web-devicons
require('mini.icons').mock_nvim_web_devicons()

-------------------------------------------------------------------------------
-- Notifications
-------------------------------------------------------------------------------

-- Floating-window notifications that auto-dismiss without stealing focus or
-- triggering hit-enter prompts (default vim.notify echoes to cmdline and
-- prompts on long messages).
vim.cmd.packadd('mini.notify')
-- lsp_progress.enable = false suppresses noisy `$/progress` notifications from
-- language servers (e.g. lua_ls scanning 5000+ workspace files at startup).
require('mini.notify').setup({
  lsp_progress = { enable = false },
})
vim.notify = require('mini.notify').make_notify()

-------------------------------------------------------------------------------
-- Treesitter
-------------------------------------------------------------------------------

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
  'rust', 'elixir', 'markdown', 'json', 'yaml', 'ini', 'graphql',
  'html', 'css', 'bash', 'vim', 'toml',
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

-- Skip treesitter for buffers >50k lines or >1.5MB
local function is_large_buffer(buf)
  if vim.api.nvim_buf_line_count(buf) > 50000 then
    return true
  end
  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
  return ok and stats and stats.size > (1.5 * 1024 * 1024)
end

-- Attach treesitter highlighting; silently no-op if parser isn't installed.
-- For unlisted languages, run `:TSInstall <lang>` once and add to ensure_installed.
local function enable_highlighting(buf)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang then return end
  pcall(vim.treesitter.start, buf, lang)
end

-- Use treesitter AST for code folding (files open fully expanded)
local function enable_folding()
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  vim.wo.foldlevel = 99
end

-- Expand ensure_installed langs into their registered filetypes (e.g. the
-- 'typescript' parser may attach to both 'typescript' and 'typescriptreact').
-- Falls back to the lang name itself when no filetype is registered yet.
local ts_filetypes = vim.iter(ensure_installed)
  :map(function(lang)
    local fts = vim.treesitter.language.get_filetypes(lang)
    return #fts > 0 and fts or { lang }
  end)
  :flatten()
  :totable()

local ts_group = vim.api.nvim_create_augroup('NativeTreesitterSetup', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = ts_group,
  desc = 'Enable native treesitter highlighting and folding',
  pattern = ts_filetypes,
  callback = function(args)
    if is_large_buffer(args.buf) then return end
    enable_highlighting(args.buf)
    enable_folding()
  end,
})

-------------------------------------------------------------------------------
-- Telescope
-------------------------------------------------------------------------------

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

vim.cmd.packadd('plenary.nvim')
vim.cmd.packadd('telescope.nvim')
vim.cmd.packadd('telescope-fzf-native.nvim')

require('telescope').setup({
  defaults = {
    sorting_strategy = 'ascending',
    -- Show the matched filename in the preview window title bar instead of
    -- the static "Preview" label. Makes it easier to see which file is open.
    dynamic_preview_title = true,
    -- wrap_results = true,  -- wrap long result lines instead of truncating
    layout_strategy  = 'flex',
    layout_config = {
      -- flex switches between horizontal (preview right) and vertical
      -- (preview below) based on available width.
      flex        = { flip_columns = 160 },
      horizontal  = { width = 0.9, prompt_position = 'top', preview_cutoff = 0 },
      vertical    = { width = 0.9, prompt_position = 'top', preview_cutoff = 0, preview_height = 0.5 },
    },
    mappings = (function()
      -- After selecting a result, scroll so the cursor lands ~20% from the top.
      -- CURSOR_TOP_RATIO: 0.0 = top of window, 0.5 = center (zz), 1.0 = bottom
      local CURSOR_TOP_RATIO = 0.20
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      local function select_and_scroll(prompt_bufnr)
        actions.select_default(prompt_bufnr)
        local offset = math.floor(vim.api.nvim_win_get_height(0) * CURSOR_TOP_RATIO)
        vim.fn.winrestview({ topline = math.max(1, vim.fn.line('.') - offset) })
      end

      -- Send the picker's current entry (or multi-selection) to the active sidekick CLI
      -- session as space-separated path:line refs. Replicates the snacks-only <a-a>
      -- integration from the sidekick README so we keep telescope as the primary picker.
      local function send_to_sidekick(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local picks = picker:get_multi_selection()
        if vim.tbl_isempty(picks) then
          picks = { action_state.get_selected_entry() }
        end
        local refs = {}
        for _, e in ipairs(picks) do
          if e then
            local path = e.path or e.filename or e.value
            if path then
              table.insert(refs, e.lnum and (path .. ':' .. e.lnum) or path)
            end
          end
        end
        actions.close(prompt_bufnr)
        if not vim.tbl_isempty(refs) then
          require('sidekick.cli').send({ msg = table.concat(refs, ' ') })
        end
      end

      return {
        i = { ['<CR>'] = select_and_scroll, ['<M-a>'] = send_to_sidekick },
        n = { ['<CR>'] = select_and_scroll, ['<M-a>'] = send_to_sidekick },
      }
    end)(),
    file_ignore_patterns = { '%.git/', 'node_modules/' },
    -- path_display options:
    --   'truncate'       — clip from the left, filename always visible
    --   'filename_first' — show filename before path: "file.go  path/to/"
    --   'smart'          — show only enough path to make each result unique
    --   'shorten'        — abbreviate dirs: "p/c/a/file.go"
    --   'tail'           — filename only
    path_display = { 'truncate' },
    git_icons = {
      added     = '+',
      changed   = '~',
      deleted   = '-',
      renamed   = '→',
      unmerged  = '!',
      untracked = '?',
    },
  },
  -- Include hidden files/dirs (e.g. .github/) in search results.
  -- .git/ and node_modules/ are still excluded via file_ignore_patterns above.
  pickers = {
    find_files = {
      hidden = true,
    },
    live_grep = {
      additional_args = { '--hidden' },
    },
  },
})

pcall(require('telescope').load_extension, 'fzf')

-------------------------------------------------------------------------------
-- Render Markdown
-------------------------------------------------------------------------------

vim.cmd.packadd('render-markdown.nvim')
require('render-markdown').setup({})

-------------------------------------------------------------------------------
-- Auto-pairs
-------------------------------------------------------------------------------

vim.cmd.packadd('nvim-autopairs')
-- check_ts: use treesitter to skip pairing inside strings and comments
require('nvim-autopairs').setup({ check_ts = true })
