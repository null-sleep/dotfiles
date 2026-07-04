-- gitui.lua — Neogit, a Magit-style git operations dashboard.
--
-- Named gitui.lua rather than neogit.lua: the plugin's own Lua module is also
-- called `neogit`, so a topic module named the same would shadow it and make
-- `require('neogit')` below recurse into itself (E5113 "loop ... loading
-- module 'neogit'"). Same reasoning as outline.lua wrapping aerial.nvim and
-- filetree.lua wrapping nvim-tree.lua under a descriptive, non-colliding name.
--
-- This is a transient, on-demand status buffer (open, stage/commit/push, close),
-- NOT an always-on window — the persistent gutter signs stay owned by gitsigns
-- (lua/git.lua). disable_signs below keeps Neogit from drawing its own gutter
-- signs on top of gitsigns'.
--
-- Deps already satisfied elsewhere: plenary.nvim (plugins.lua) and telescope.nvim
-- (plugins.lua) for the selection menus; mini.icons mocks nvim-web-devicons
-- (init.lua) for file icons. diffview.nvim is the one new dependency, added
-- purely for its rich side-by-side diff view via integrations.diffview.
vim.cmd.packadd('diffview.nvim')
vim.cmd.packadd('neogit')

require('neogit').setup({
  kind = 'tab',                 -- own tab page; per-view, so commit/log keep their own defaults.
                                 -- Never disturbs nvim-tree/aerial sidebars, toggleterm floats,
                                 -- or sidekick splits — closing restores the prior layout.
  -- kind = 'floating',         -- ALT (disabled): centered floating overlay instead of a tab
  graph_style = 'unicode',      -- portable pretty commit graph (no kitty graphics protocol needed)
  disable_signs = true,         -- gitsigns owns the gutter (see git.lua)
  integrations = {
    telescope = true,           -- telescope-backed selection menus (branches, commits, ...)
    diffview  = true,           -- rich diffs via diffview.nvim instead of Neogit's inline-only view
  },
})

-- <leader>g maps — mnemonics mirror the zsh git aliases (~/.zshrc_config.zsh) so
-- muscle memory transfers: gc/gp/gu/gl/gd/gb/gr/gw. open({}) opens the status
-- buffer; open({ '<popup>' }) opens a popup directly (verified against Neogit
-- source: the name is used verbatim as the neogit.popups.<name> module — no
-- alias table, no '_popup' suffix).
local function nmap(lhs, arg, desc)
  vim.keymap.set('n', lhs, function() require('neogit').open(arg) end, { desc = desc })
end
nmap('<leader>gg', {},             'Git: Neogit status')
nmap('<leader>gc', { 'commit' },   'Git: commit')     -- ≈ gc
nmap('<leader>gp', { 'push' },     'Git: push')       -- ≈ gp
nmap('<leader>gu', { 'pull' },     'Git: pull')       -- ≈ gu (shell: gu=pull, gp=push)
nmap('<leader>gl', { 'log' },      'Git: log')        -- ≈ gl
nmap('<leader>gd', { 'diff' },     'Git: diff')       -- ≈ gd
nmap('<leader>gb', { 'branch' },   'Git: branch')     -- ≈ gcb / gnb
nmap('<leader>gr', { 'rebase' },   'Git: rebase')     -- ≈ grb
nmap('<leader>gw', { 'worktree' }, 'Git: worktree')   -- ≈ gw

-- Not mapped but reachable by one keystroke inside the status buffer:
-- s stage, u unstage, x discard, Z stash, P push, ? help, etc.

-- ALT (disabled): open the status buffer in a floating overlay without changing
-- the default tab binding. open() accepts a per-call `kind` (verified vs source).
-- Uncomment to enable a floating opener alongside <leader>gg.
-- nmap('<leader>gG', { kind = 'floating' }, 'Git: status (floating)')
