local gh = require('utils').gh
local themes = require('themes')

-- Register plugins with vim.pack (nvim 0.12 native package manager).
-- Theme sources are appended from themes.lua.
vim.pack.add(vim.list_extend({
  -- Treesitter
  { src = gh('nvim-treesitter/nvim-treesitter'), version = 'main' },
  { src = gh('nvim-treesitter/nvim-treesitter-context') },
  -- Textobject queries on the runtimepath — sidekick's {function}/{class}
  -- context vars resolve via these (see ai.lua). main branch matches the
  -- nvim-treesitter rewrite.
  { src = gh('nvim-treesitter/nvim-treesitter-textobjects'), version = 'main' },

  -- Lua utility library — required by nvim-lsp-file-operations and Neogit.
  -- (The fuzzy finder is snacks.picker, configured in picker.lua; snacks
  -- itself is declared under Workflow below.)
  { src = gh('nvim-lua/plenary.nvim') },

  -- LSP
  { src = gh('mason-org/mason.nvim') },
  { src = gh('mason-org/mason-lspconfig.nvim') },
  { src = gh('neovim/nvim-lspconfig') },
  { src = gh('folke/lazydev.nvim') },
  -- Rewrite imports when a file is renamed inside nvim-tree. Wiring is split in
  -- two halves (grep 'lsp-file-operations'): capability in lsp.lua, event
  -- subscription in filetree.lua. Uses plenary (above).
  { src = gh('antosha417/nvim-lsp-file-operations') },

  -- Completion
  { src = gh('saghen/blink.cmp'), version = vim.version.range('1.*') },

  -- UI
  { src = gh('echasnovski/mini.icons') },
  { src = gh('echasnovski/mini.notify') },
  { src = gh('echasnovski/mini.bufremove') },
  { src = gh('nvim-lualine/lualine.nvim') },
  { src = gh('lewis6991/satellite.nvim') },
  { src = gh('folke/which-key.nvim') },
  { src = gh('MeanderingProgrammer/render-markdown.nvim') },
  -- Interactive project-wide find & replace (setup in grugfar.lua).
  { src = gh('MagicDuck/grug-far.nvim') },
  -- Terminal-only Neovide-style cursor/scroll animation; see animations.lua
  { src = gh('sphamba/smear-cursor.nvim') },
  { src = gh('declancm/cinnamon.nvim') },
  -- VS Code / GoLand-style "Peek": a scrollable floating window showing the real
  -- target file at a definition/reference, without moving the main window.
  -- (pcall-requires an optional logger.nvim; falls back to a bundled logger.)
  { src = gh('rmagatti/goto-preview') },
  -- Diff preview before a code action applies. No version tags upstream —
  -- left unpinned, same as nvim-dap-go below.
  { src = gh('aznhe21/actions-preview.nvim') },
  -- Zed/VS Code-style outline sidebar: collapsible symbol tree for the current
  -- buffer, treesitter-first so it works with no LSP attached.
  { src = gh('stevearc/aerial.nvim') },
  -- Pins special windows (nvim-tree, aerial, toggleterm, neotest, quickfix...)
  -- so a stray :e/buffer-jump can't hijack them and load an unrelated file.
  { src = gh('stevearc/stickybuf.nvim') },

  -- Git
  { src = gh('lewis6991/gitsigns.nvim') },
  { src = gh('NeogitOrg/neogit') },
  { src = gh('sindrets/diffview.nvim') },

  -- File tree
  { src = gh('nvim-tree/nvim-tree.lua') },

  -- Workflow
  { src = gh('folke/persistence.nvim') },
  { src = gh('okuuva/auto-save.nvim') },
  -- Scratch buffers: floating, persistent scratchpads keyed by cwd/branch/count.
  { src = gh('folke/snacks.nvim') },
  { src = gh('windwp/nvim-autopairs') },
  { src = gh('stevearc/conform.nvim') },
  { src = gh('mfussenegger/nvim-lint') },
  { src = gh('WhoIsSethDaniel/mason-tool-installer.nvim') },
  { src = gh('akinsho/toggleterm.nvim') },
  { src = gh('willothy/flatten.nvim') },

  -- Debug / Test / Language support
  -- rustaceanvim pinned to ^9: fast-moving repo that ships breaking majors and
  -- tracks latest Neovim — an unpinned jump to v10 could break the vim.g.rustaceanvim
  -- schema. (Same rationale as blink.cmp's 1.* pin above.)
  { src = gh('mrcjkb/rustaceanvim'), version = vim.version.range('^9') },
  { src = gh('mfussenegger/nvim-dap') },
  { src = gh('rcarriga/nvim-dap-ui') },
  { src = gh('theHamsta/nvim-dap-virtual-text') },
  { src = gh('nvim-neotest/nvim-nio') },
  { src = gh('nvim-neotest/neotest') },
  -- nvim-dap-go publishes no git tags at all, so it cannot be pinned; leave it bare.
  { src = gh('leoluz/nvim-dap-go') },
  -- neotest-golang pinned to ^2: ships breaking majors (v1->v2 changed the
  -- treesitter requirement out from under users) — same rationale as the
  -- rustaceanvim ^9 pin above.
  { src = gh('fredrikaverpil/neotest-golang'), version = vim.version.range('^2') },
  -- AI: Claude CLI integration.
  { src = gh('folke/sidekick.nvim') },
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

-- Live theme sync: pick up external switches (the `theme` shell command) and
-- cross-instance picker changes. Skipped under claude-nvim's throwaway headless
-- runs (CLAUDE_NVIM=1) — they +qa immediately and need no watcher.
if vim.env.CLAUDE_NVIM ~= '1' then
  themes.watch()
end

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
vim.notify = require('mini.notify').make_notify({
  -- Keep WARN/ERROR notifications visible longer (default is ~3s).
  -- INFO stays short; WARN/ERROR linger until dismissed or timeout.
  ERROR = { duration = 10000 },
  WARN  = { duration = 10000 },
})
-- :Notifications — view dismissed notifications (like :messages but for mini.notify)
vim.api.nvim_create_user_command('Notifications', function()
  require('mini.notify').show_history()
end, {})

-------------------------------------------------------------------------------
-- Buffer removal (delete a buffer without collapsing its window/split)
-------------------------------------------------------------------------------

vim.cmd.packadd('mini.bufremove')
require('mini.bufremove').setup()

-------------------------------------------------------------------------------
-- Flatten (route nested nvim launches into the parent instance)
-------------------------------------------------------------------------------
-- vim.schedule() pattern: any toggleterm t:open() / t:close() called from
-- inside a buffer lifecycle callback (flatten hooks, BufDelete autocmds, etc.)
-- must be deferred via vim.schedule(). Calling them synchronously while a
-- buffer is being opened or closed raises E1159 "Cannot open a float when
-- closing the buffer". schedule() defers to the next event loop tick, after
-- the triggering operation has fully completed.

vim.cmd.packadd('flatten.nvim')

local _flatten_hidden = {}

require('flatten').setup({
  window = {
    open = 'smart',  -- skips floating windows; lands in a real window after pre_open closes the float
  },
  block_for = {
    gitcommit = true,
    gitrebase = true,
    hgcommit  = true,
  },
  nest_if_no_args = false,
  hooks = {
    should_nest = function()
      return vim.env.NVIM_NEST == '1'
    end,
    pre_open = function()
      -- Snapshot which toggleterm floats are currently open; close them after
      -- the current event loop tick. Closing a float synchronously during
      -- pre_open (while flatten is mid-buffer-open) triggers E1159.
      _flatten_hidden = {}
      local ok, term_mod = pcall(require, 'toggleterm.terminal')
      if not ok then return end
      for _, t in ipairs(term_mod.get_all(true)) do
        if t:is_open() then
          table.insert(_flatten_hidden, t.id)
        end
      end
      vim.schedule(function()
        local ok2, term_mod2 = pcall(require, 'toggleterm.terminal')
        if not ok2 then return end
        for _, id in ipairs(_flatten_hidden) do
          local t = term_mod2.get(id)
          if t and t:is_open() then t:close() end
        end
      end)
    end,
    post_open = function(opts)
      if opts.is_blocking then
        vim.g._flatten_blocking = true
        -- Restore terminals when the blocking buffer is deleted (unblocks the guest).
        vim.api.nvim_create_autocmd('BufDelete', {
          buffer   = opts.bufnr,
          once     = true,
          callback = function()
            vim.g._flatten_blocking = false
            -- Defer: t:open() during BufDelete also triggers E1159.
            vim.schedule(function()
              local ok, term_mod = pcall(require, 'toggleterm.terminal')
              if not ok then return end
              for _, id in ipairs(_flatten_hidden) do
                local t = term_mod.get(id)
                if t then t:open() end
              end
              _flatten_hidden = {}
            end)
          end,
        })
      else
        -- Non-blocking guest (e.g. plain `nvim somefile`): restore immediately.
        vim.schedule(function()
          local ok, term_mod = pcall(require, 'toggleterm.terminal')
          if ok then
            for _, id in ipairs(_flatten_hidden) do
              local t = term_mod.get(id)
              if t then t:open() end
            end
            _flatten_hidden = {}
          end
        end)
      end
    end,
  },
})

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
  'rust', 'elixir', 'kotlin', 'markdown', 'json', 'yaml', 'ini', 'graphql',
  'html', 'css', 'bash', 'vim', 'toml', 'make', 'xml', 'just', 'diff',
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

-- Put nvim-treesitter-textobjects' `queries/<lang>/textobjects.scm` on the
-- runtimepath so sidekick's {function}/{class} context vars resolve
-- (context/textobject.lua looks them up via vim.treesitter.query.get). No
-- setup() needed — that only configures move/select/swap keymaps we don't use.
pcall(vim.cmd.packadd, 'nvim-treesitter-textobjects')

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
-- Plenary (Lua utility library: nvim-lsp-file-operations, Neogit)
-------------------------------------------------------------------------------

vim.cmd.packadd('plenary.nvim')

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

-------------------------------------------------------------------------------
-- Stickybuf
-------------------------------------------------------------------------------

-- Prevents a stray :e / buffer-jump from hijacking a special window (e.g. the
-- nvim-tree or aerial sidebar) and loading an unrelated file into it. Zero
-- config needed: nvim-tree, aerial, toggleterm, and neotest are all in its
-- built-in supported-filetype list already. See GUIDE.md "Design Decisions"
-- for the general pattern this covers.
--
-- sidekick's CLI buffer (filetype `sidekick_terminal`) isn't in stickybuf's
-- built-in list, so it's added here on top of the defaults.
vim.cmd.packadd('stickybuf.nvim')
require('stickybuf').setup({
  get_auto_pin = function(bufnr)
    if vim.bo[bufnr].filetype == 'sidekick_terminal' then
      return 'filetype'
    end
    if vim.bo[bufnr].filetype == 'grug-far' then
      return 'filetype'
    end
    return require('stickybuf').should_auto_pin(bufnr)
  end,
})
