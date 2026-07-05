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

-- <leader>v maps — diffview.nvim direct entry points, kept in their own group
-- rather than folded into <leader>g* so Neogit's popups and diffview's views
-- stay visually distinct in which-key. require('diffview') is safe to call
-- top-level here: packadd('diffview.nvim') already ran above.
local dv = require('diffview')

-- Remote-tracking base ref, e.g. 'origin/main' — never hardcode 'main'.
-- Mirrors the zsh git_base_branch() (~/.zshrc_config.zsh) so <leader>vm agrees
-- with the gdm shell alias about what "the base branch" is. Run
-- `git remote set-head origin --auto` once per clone to populate origin/HEAD.
local function base_ref()
  local out = vim.fn.systemlist({ 'git', 'symbolic-ref', 'refs/remotes/origin/HEAD' })
  if vim.v.shell_error == 0 and out[1] then
    return (out[1]:gsub('^refs/remotes/', ''))  -- 'refs/remotes/origin/main' -> 'origin/main'
  end
  vim.notify("diffview: origin/HEAD not set — run 'git remote set-head origin --auto'",
    vim.log.levels.WARN)
  return nil
end

-- Resolve "how many commits back" for the range-based maps below. A count
-- prefix wins (5<leader>vr -> 5); with no count, prompt instead — starting
-- empty rather than defaulting to some arbitrary N. Empty/non-numeric input
-- cancels silently, same spirit as titling.lua's vim.ui.input cancel guard.
local function with_n(cb)
  local n = vim.v.count  -- 0 when no count was typed
  if n > 0 then return cb(n) end
  vim.ui.input({ prompt = 'Commits back: ' }, function(input)
    local num = tonumber(input)
    if not num or num < 1 then return end
    cb(math.floor(num))
  end)
end

vim.keymap.set('n', '<leader>vv', function() dv.open({}) end,
  { desc = 'Diffview: uncommitted changes' })
vim.keymap.set('n', '<leader>vm', function()
  local base = base_ref()
  if base then dv.open({ base .. '...HEAD' }) end
end, { desc = 'Diffview: PR vs base branch' })
vim.keymap.set('n', '<leader>vr', function()
  with_n(function(n) dv.open({ ('HEAD~%d..HEAD'):format(n) }) end)
end, { desc = 'Diffview: last N commits (squashed)' })
vim.keymap.set('n', '<leader>vh', function()
  with_n(function(n) dv.file_history(nil, { ('--range=HEAD~%d..HEAD'):format(n) }) end)
end, { desc = 'Diffview: walk last N commits' })
vim.keymap.set('n', '<leader>vf', function()
  dv.file_history(nil, { vim.fn.expand('%:p') })
end, { desc = 'Diffview: current file history' })
vim.keymap.set('n', '<leader>vq', function() dv.close() end,
  { desc = 'Diffview: close' })
