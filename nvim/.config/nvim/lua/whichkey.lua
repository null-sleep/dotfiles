vim.cmd.packadd('which-key.nvim')

local wk = require('which-key')

wk.setup({
  preset = 'modern',
  delay  = 300,  -- ms after key press before popup appears
  -- Explicit trigger list: which-key only intercepts these keys, never others.
  -- This avoids the modern preset's aggressive interception of operators like
  -- v, d, c, y when single-char groups (g, [, ]) are registered.
  -- When adding a new single-char group in wk.add(), add its trigger here too.
  triggers = {
    { '<leader>', mode = { 'n', 'x' } },
    { 'g',        mode = 'n' },
    { '[',        mode = 'n' },
    { ']',        mode = 'n' },
  },
})

-- Group labels — shown as headings in the which-key popup
-- Note: which-key warns about <gc> overlapping <gcc>. This is expected —
-- gc is Neovim's built-in comment operator (e.g. gcip, gc3j) and gcc is its
-- line shortcut. Not adding gc to triggers intentionally: it would add a 300ms
-- pause on every gcc with no real benefit.
wk.add({
  { '<leader>s',  group = 'Search' },
  { '<leader>b',  group = 'Buffer' },
  { '<leader>q',  group = 'Session/Quit' },
  { '<leader>t',  group = 'Toggle' },
  { '<leader>h',  group = 'Git hunk' },
  { '<leader>G',  group = 'Git' },
  { '<leader>v',  group = 'Diffview' },
  { '<leader>c',  group = 'Code' },
  { '<leader>a',  group = 'AI' },
  { '<leader>u',  group = 'Utilities' },
  { '<leader>d',  group = 'Debug' },
  { '<leader>n',  group = 'Test' },
  { '<leader>p',  group = 'Peek' },
  { 'g',          group = 'Go to' },
  { '[',          group = 'Previous' },
  { ']',          group = 'Next' },

  -- Explorer: <leader>e is a single keymap (no sub-keys), so it doesn't
  -- need a group entry. It appears in <leader>sk via its `desc` string
  -- and the keywords table below.

  -- Spell navigation: register here so ]s / [s appear in the [/] which-key popup.
  { ']s', desc = 'Spell: Next misspelled word' },
  { '[s', desc = 'Spell: Previous misspelled word' },

  -- Outline navigation: register here so ]a / [a appear in the [/] which-key popup.
  { ']a', desc = 'Next: Symbol (aerial outline)' },
  { '[a', desc = 'Previous: Symbol (aerial outline)' },

  -- Yank-prefix descriptions (documentation only — `y` is intentionally not
  -- in `triggers`, so these don't pop up after pressing `y`; they appear in
  -- `<leader>?` global mappings list). Active in normal and visual modes.
  { 'yp',  desc = 'Yank: Relative path',                    mode = { 'n', 'x' } },
  { 'yP',  desc = 'Yank: Absolute path',                    mode = { 'n', 'x' } },
  { 'yc',  desc = 'Yank: Claude reference (@path:lines)',   mode = { 'n', 'x' } },
  { 'yC',  desc = 'Yank: Claude reference (absolute path)', mode = { 'n', 'x' } },
  { 'yu',  desc = 'Yank: GitHub permalink',                 mode = { 'n', 'x' } },
})

-- Extra search keywords for pickers/keybindings.lua — keyed by lhs, value is a
-- space-separated string of aliases that don't appear in the desc.
local keywords = {
  ['K']          = 'peek hover type signature documentation definition lsp float',
  ['<C-o>']      = 'jump back go back previous location history',
  ['<C-i>']      = 'jump forward go forward next location history',
  ['<leader>e']  = 'explorer file tree sidebar nvim-tree toggle reveal',
  ['<leader>o']  = 'outline symbols sidebar tree aerial structure vscode zed panel',
  ['g?']         = 'explorer file tree help keybindings nvim-tree',
  ['<leader>bb'] = 'buffer picker list switch open recent',
  ['<leader>bo'] = 'close others only delete all buffers keep current',
  ['<leader>bd'] = 'close buffer delete bufremove split keep window',
  ['<leader>qq'] = 'quit all exit nvim qa close',
  ['<leader>tz'] = 'spell typo spelling',
  ['<leader>tn'] = 'line numbers relative relativenumber absolute gutter',
  ['<leader>tg'] = 'indent guides scope lines snacks toggle blankline ibl',
  ['<leader>tb'] = 'git blame inline current line toggle gitsigns annotation',
  ['<leader>th'] = 'hover hold auto documentation cursorhold toggle lsp',
  ['<leader>sd'] = 'document symbols outline current buffer lsp functions',
  ['<leader>uo'] = 'open typora markdown gui external app preview',
  ['<leader>O']  = 'outline nav popup aerial miller columns symbols drill',
  ['<leader>sb'] = 'fuzzy search current buffer lines swiper alias',
  [']s']         = 'spell typo spelling',
  ['[s']         = 'spell typo spelling',
  ['zg']         = 'spell typo spelling dictionary add word',
  ['zw']         = 'spell typo spelling wrong',
  ['z=']         = 'spell typo spelling suggest corrections',
  ['1z=']        = 'spell typo spelling fix accept',
  ['<leader>ut'] = 'title rename window tab iterm neovide project name',
  ['<leader>us'] = 'strip whitespace trim trailing spaces clean',
  ['<leader>uc'] = 'clean paste reflow dedent terminal claude format fix',
  ['<leader>uu'] = 'undo history recover deleted restore seq timeline tree',
  ['<leader>uU'] = 'undo tree panel sidebar atone branch history marks bookmark',
  ['<leader>bs'] = 'scratch buffer toggle pad notes temporary snacks',
  ['<leader>bS'] = 'scratch buffer select list snacks delete ctrl-x new ctrl-n',
  ['<leader>db'] = 'breakpoint dap debugger',
  ['<leader>dc'] = 'debug continue start dap run delve go rust',
  ['<leader>du'] = 'dap-ui debugger panel scopes stack watches',
  ['<leader>dR'] = 'debug rust debuggables rustaceanvim go delve targets packages main picker',
  ['<leader>nn'] = 'neotest run test nearest',
  ['<leader>nd'] = 'neotest debug test dap nearest go delve rust',
  ['<leader>ns'] = 'neotest summary test tree panel',
  ['<leader>cR'] = 'run rust runnables cargo rustaceanvim go targets packages main picker',
  ['<leader>cw'] = 'reload workspace rust cargo metadata rust-analyzer stale diagnostics fix refresh',
  ['<leader>pd'] = 'peek definition popup float goto-preview vscode',
  ['<leader>pt'] = 'peek type definition popup float goto-preview',
  ['<leader>pi'] = 'peek implementation popup float goto-preview',
  ['<leader>pr'] = 'peek references usages popup float goto-preview',
  ['<leader>pq'] = 'peek close all windows goto-preview',
  ['<leader>vv'] = 'diffview uncommitted changes diff',
  ['<leader>vp'] = 'diffview pr review merge base branch symmetric difference gdm',
  ['<leader>vn'] = 'diffview last n commits range squashed',
  ['<leader>vh'] = 'diffview file history walk commits log',
  ['<leader>vf'] = 'diffview current file history log',
  ['<leader>vq'] = 'diffview close quit',
}

-- Tag OVERRIDES for the <leader>sk picker (D1). Most tags are derived
-- mechanically by pickers/keybindings.lua from the text before the first
-- ':' in each keymap's desc (e.g. "Git hunk: Stage" -> "git hunk"), so they
-- can't go stale the way the old 28-entry hand-maintained table did (it once
-- tagged a nonexistent <leader>gs and missed 7 real <leader>g* keys added
-- later). This table is kept deliberately slim: only lhs whose desired tag
-- ISN'T the derivable prefix. Entries here are MERGED with the derived tag,
-- never replace it — see resolve_tags() in pickers/keybindings.lua.
local tags = {
  ['<leader>dR'] = { 'rust', 'go' },        -- desc derives 'debug'; Rust debuggables is also rust (was { 'rust' })
  ['<leader>cR'] = { 'rust', 'go', 'run' },
  ['<leader>vv'] = { 'diff' },
  ['<leader>vp'] = { 'diff' },
  ['<leader>vn'] = { 'diff' },
  ['<leader>vh'] = { 'diff' },
  ['<leader>vf'] = { 'diff' },
  ['<leader>vq'] = { 'diff' },
  ['<leader>uu'] = { 'diff' },              -- desc derives 'utilities'; the undo picker previews diffs
  ['<leader>nd'] = { 'debug' },             -- desc derives 'test'; debugging a test is also debug
  ['K']          = { 'lsp' },
  ['<leader>pd'] = { 'lsp' },
  ['<leader>pt'] = { 'lsp' },
  ['<leader>pi'] = { 'lsp' },
  ['<leader>pr'] = { 'lsp' },
  ['<leader>sd'] = { 'lsp' },
  ['<leader>a']  = { 'ai' },
}

-- Exported for pickers/keybindings.lua: `require('whichkey').keywords/tags`
return { keywords = keywords, tags = tags }
