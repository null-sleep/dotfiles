-- Note: which-key uses an explicit trigger list (see whichkey.lua). If you add
-- a new single-char group in whichkey.lua's wk.add(), add it to triggers too.

-- Telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep,  { desc = 'Search: Grep' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', builtin.resume,                      { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sb', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sm', function() require('pickers.gitstatus').open() end,
  { desc = 'Search: Modified files' })
vim.keymap.set('n', '<leader>ss', function() require('pickers.symbols').workspace() end,
  { desc = 'Search: Symbols (workspace)' })
vim.keymap.set('n', '<leader>sd', function() require('pickers.symbols').document() end,
  { desc = 'Search: Symbols (document)' })
vim.keymap.set('n', '<leader>so', builtin.oldfiles,                      { desc = 'Search: Recent files' })
vim.keymap.set('n', '<leader>st', function() require('pickers.theme').open() end,
  { desc = 'Search: Themes' })

-- Clear search highlights and close any floating windows (hover, diagnostics, etc.)
-- Sets b:hover_suppressed so CursorHold hover doesn't immediately reopen the float.
-- The flag is cleared on the next CursorMoved (see autocmd below).
vim.keymap.set('n', '<Esc>', function()
  local closed_any = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      -- focusable == false marks passive helper floats (satellite scrollbar,
      -- treesitter-context header) — closing those just makes them vanish
      -- until their next redraw. Only user-facing floats (hover, peek,
      -- diagnostics) should close.
      if cfg.relative ~= '' and cfg.focusable ~= false then
        pcall(vim.api.nvim_win_close, win, true)
        closed_any = true
      end
    end
  end
  if closed_any then
    vim.b.hover_suppressed = true
  end
  vim.cmd('nohlsearch')
end, { desc = 'Clear search highlights and close floats' })

vim.api.nvim_create_autocmd('CursorMoved', {
  group = vim.api.nvim_create_augroup('ClearHoverSuppression', { clear = true }),
  callback = function() vim.b.hover_suppressed = false end,
})

-- Exit insert mode without reaching for Escape. Both map to the same rhs:
-- jj is the double-tap muscle memory, jk a two-finger inward roll some
-- find faster — mapping both costs nothing since the timeout starts on
-- the shared j prefix either way.
vim.keymap.set('i', 'jj', '<Esc>', { desc = 'Exit insert mode' })
vim.keymap.set('i', 'jk', '<Esc>', { desc = 'Exit insert mode' })

-- Yank to system clipboard (dd, x, c stay in Neovim register).
-- Uses expr mapping so that explicit register prefixes ("a, "b, etc.) are
-- honoured — only bare y/Y without a register prefix go to clipboard.
vim.keymap.set({'n', 'x'}, 'y', function()
  if vim.v.register ~= '"' then return 'y' end
  return '"+y'
end, { expr = true, desc = 'Yank to system clipboard (unless register specified)' })

vim.keymap.set('n', 'Y', function()
  if vim.v.register ~= '"' then return 'Y' end
  return '"+Y'
end, { expr = true, desc = 'Yank line to system clipboard (unless register specified)' })

-- Stay in visual mode after indent/dedent
vim.keymap.set('x', '<', '<gv', { desc = 'Dedent and reselect' })
vim.keymap.set('x', '>', '>gv', { desc = 'Indent and reselect' })

-- Paste over selection without clobbering the register.
-- 'x' (visual-only), never 'v' (visual+select): blink.cmp drops snippet
-- placeholders in select mode, where typing should insert literal text —
-- a 'v' mapping here would hijack that keystroke into a paste instead.
vim.keymap.set('x', 'p', '"_dP', { desc = 'Paste without yanking replaced text' })

-- Split navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move to left split' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move to split below' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move to split above' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move to right split' })

-- Split resizing. Each is a no-op unless a boundary exists on that axis (e.g.
-- <A-j>/<A-k> do nothing between two side-by-side vertical splits, since both
-- already span full height) — same <C-w> resize commands, just repeatable
-- without re-pressing the <C-w> prefix each time.
-- Speculative: unclear yet if these get reached for vs. the mouse/existing
-- <C-w> commands. May remap to something else later if they go unused.
vim.keymap.set('n', '<A-h>', '<cmd>vertical resize -2<CR>', { desc = 'Split: narrower' })
vim.keymap.set('n', '<A-j>', '<cmd>resize -2<CR>',          { desc = 'Split: shorter' })
vim.keymap.set('n', '<A-k>', '<cmd>resize +2<CR>',          { desc = 'Split: taller' })
vim.keymap.set('n', '<A-l>', '<cmd>vertical resize +2<CR>', { desc = 'Split: wider' })

-- Buffer navigation
vim.keymap.set('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<CR>',     { desc = 'Next buffer' })

-- Mouse back/forward buttons → jumplist (browser-style navigation).
-- Works in Neovide directly. In iTerm2, requires "Report mouse clicks & drags"
-- to be on (default) and the focused app to use mouse mode — nvim enables it
-- via `mouse=a` (see configs.lua).
vim.keymap.set({ 'n', 'x' }, '<X1Mouse>', '<C-o>', { desc = 'Jumplist: back (mouse back button)' })
vim.keymap.set({ 'n', 'x' }, '<X2Mouse>', '<C-i>', { desc = 'Jumplist: forward (mouse forward button)' })

-- Ctrl + LeftClick → LSP go-to-definition (VS Code-style). The <LeftMouse>
-- feedkeys places the cursor under the pointer before the LSP call, so the
-- jump targets the word actually clicked. Use <C-o>/<C-i> (or the side-button
-- mappings above) to jump back/forward.
vim.keymap.set('n', '<C-LeftMouse>', function()
  local keys = vim.api.nvim_replace_termcodes('<LeftMouse>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'nx', false)
  vim.lsp.buf.definition()
end, { desc = 'LSP: Go to definition (Ctrl+click)' })
-- Skip non-code buffers (terminals, sidekick's CLI, aerial, nvim-tree) as
-- alternate-buffer targets — landing on one of these via '#' is never useful
-- and stickybuf doesn't guard this direction (it only protects a pinned
-- window from foreign buffers, not the reverse). Uses the shared
-- buffers.is_special() predicate — see GUIDE.md "Non-code buffer exceptions
-- need a shared predicate".
local buffers = require('buffers')
vim.keymap.set('n', '<leader><leader>', function()
  local alt = vim.fn.bufnr('#')
  if alt == -1 or not vim.api.nvim_buf_is_valid(alt) then
    vim.notify('No alternate buffer', vim.log.levels.WARN)
    return
  end
  if buffers.is_special(alt) then
    -- Silently declining with no feedback reads as a broken keymap; say why.
    vim.notify('Alternate buffer is a terminal/panel — skipped', vim.log.levels.WARN)
    return
  end
  vim.cmd('buffer #')
end, { desc = 'Toggle alternate buffer' })
vim.keymap.set('n', '<leader>bb', function() require('pickers.buffer').open() end,
  { desc = 'Buffer: Picker' })
-- Kept as a permanent alias: one keystroke shorter, and predates <leader>bb
-- (added so the Buffer group tells the whole picker+close+scratch+only story).
vim.keymap.set('n', '<leader>m', function() require('pickers.buffer').open() end,
  { desc = 'Buffer: Picker (alias of <leader>bb)' })

-- Close every listed buffer except the current one. Skips modified buffers
-- (would lose unsaved changes silently) and special/non-code buffers (via
-- buffers.is_special() — closing a terminal or sidebar this way is never
-- what "close other buffers" means) so it only ever touches plain file
-- buffers, then reports what happened instead of silently doing partial work.
vim.keymap.set('n', '<leader>bo', function()
  local current = vim.api.nvim_get_current_buf()
  local closed, skipped_modified = 0, 0
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= current then
      if info.changed == 1 then
        skipped_modified = skipped_modified + 1
      elseif not buffers.is_special(info.bufnr) then
        require('mini.bufremove').delete(info.bufnr, false)
        closed = closed + 1
      end
    end
  end
  local msg = ('Closed %d other buffer(s)'):format(closed)
  if skipped_modified > 0 then
    msg = msg .. (' (%d skipped: unsaved changes)'):format(skipped_modified)
  end
  vim.notify(msg)
end, { desc = 'Buffer: Close others' })

-- File tree: opens and reveals current file, or closes if already open.
-- Only one left-edge sidebar at a time: opening the tree closes the outline
-- first if it's showing (symmetric with outline.lua's <leader>o, which closes
-- the tree before opening the outline). Checked via is_visible()/is_open(),
-- not before/after state, so this only fires on the OPEN edge of the toggle —
-- closing the tree never touches the outline.
vim.keymap.set('n', '<leader>e', function()
  local nvim_tree_api = require('nvim-tree.api')
  if not nvim_tree_api.tree.is_visible() then
    local ok, aerial = pcall(require, 'aerial')
    if ok and aerial.is_open() then
      aerial.close()
    end
  end
  vim.cmd('NvimTreeFindFileToggle')
end, { desc = 'Explorer: Toggle' })

-- Open the current file in Typora (macOS GUI markdown editor). Works on any
-- buffer — Typora opens plain text fine too — so it's a global mapping plus a
-- :Typora command. Writes pending changes first so Typora sees the latest
-- content from disk.
local function open_in_typora()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    vim.notify('No file name for this buffer', vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then vim.cmd('write') end
  vim.system({ 'open', '-a', 'Typora', path })
end
vim.api.nvim_create_user_command('Typora', open_in_typora, { desc = 'Open current file in Typora' })
vim.keymap.set('n', '<leader>uo', open_in_typora, { desc = 'Utilities: Open in Typora' })

-- Quit
vim.api.nvim_create_user_command('Q', 'qa', {})
-- Close buffer without closing the window/pane. mini.bufremove picks a
-- replacement buffer for every window showing it (alternate, then most
-- recent, then a scratch buffer) so all splits stay open.
-- <leader>bd matches the common convention (LazyVim, bufdelete.nvim, etc.) and
-- is the only close-buffer key -- <leader>qq below is Session/Quit, not Buffer.
local close_buffer = function()
  require('mini.bufremove').delete(0, false)
end
vim.keymap.set('n', '<leader>bd', close_buffer, { desc = 'Buffer: Close' })

-- <leader>qq: quit nvim entirely (what its letters actually suggest). The
-- floating confirm popup (utils.confirm — y confirms, anything else is No)
-- guards against ACCIDENTALLY quitting the whole session -- losing window
-- layout, terminal state, a running CLI -- not against data loss (plain :qa
-- already aborts with E37 on modified buffers). Matches the q-closes-the-thing
-- convention used by every other namespace (gq/vq/pq/dq/nq).
vim.keymap.set('n', '<leader>qq', function()
  require('utils').confirm('Quit Neovim?', function() vim.cmd('qa') end)
end, { desc = 'Session: Quit all (confirm)' })

-- Toggle spell checking
vim.keymap.set('n', '<leader>tz', function()
  vim.opt.spell = not vim.opt.spell:get()
end, { desc = 'Toggle: Spell check' })

-- Toggle line numbers: absolute (default) <-> relative.
vim.keymap.set('n', '<leader>tn', function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = 'Toggle: Relative line numbers' })

-- Toggle indent guides + current-scope highlight (snacks.indent).
vim.keymap.set('n', '<leader>tg', function()
  if Snacks.indent.enabled then Snacks.indent.disable() else Snacks.indent.enable() end
end, { desc = 'Toggle: Indent guides' })

-- Add word to dictionary, skipping duplicates
vim.keymap.set('n', 'zg', require('spell').add_word, { desc = 'Spell: Add word to dictionary' })

-- Toggle LSP diagnostics (virtual text + gutter signs).
vim.keymap.set('n', '<leader>td', function()
  local current = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({
    virtual_text = not current,
    signs        = not current,
  })
end, { desc = 'Toggle: Diagnostics' })

-- Toggle all AI autocompletions globally (inline ghost text + NES).
-- Inline completion: omitting bufnr toggles for all buffers.
-- NES: vim.g.sidekick_nes is checked by sidekick's enabled callback.
vim.keymap.set('n', '<leader>ta', function()
  local enabling = not vim.lsp.inline_completion.is_enabled()
  vim.lsp.inline_completion.enable(enabling)
  vim.g.sidekick_nes = enabling
  vim.notify('AI completions ' .. (enabling and 'ON' or 'OFF'))
end, { desc = 'Toggle: AI completions (inline + NES)' })

-- Toggle <leader>ss scope: multi-LSP fan-out (default) ↔ buffer-attached only.
vim.keymap.set('n', '<leader>ts',
  function() require('pickers.symbols').toggle_buffer_only() end,
  { desc = 'Toggle: Symbol search scope (all LSPs ↔ buffer)' })

-- Show all keybindings
vim.keymap.set('n', '<leader>?', function() require('which-key').show({ global = true }) end,
  { desc = 'Help: All mappings' })
vim.keymap.set('n', '<leader>sk', function() require('pickers.keybindings').open() end,
  { desc = 'Search: Keymaps' })

-- Yank helpers (paths, code references, GitHub permalinks)
local yank = require('yank')
vim.keymap.set({'n', 'x'}, 'yp', yank.relative_path,        { desc = 'Yank: Relative path' })
vim.keymap.set({'n', 'x'}, 'yP', yank.absolute_path,        { desc = 'Yank: Absolute path' })
vim.keymap.set({'n', 'x'}, 'yc', yank.claude_ref,           { desc = 'Yank: Claude reference (@path:lines)' })
vim.keymap.set({'n', 'x'}, 'yC', yank.claude_ref_absolute,  { desc = 'Yank: Claude reference (absolute path)' })
vim.keymap.set({'n', 'x'}, 'yu', yank.github_url,           { desc = 'Yank: GitHub permalink' })

-- AI (sidekick.nvim): NES + Claude/Copilot CLI
-- These are the *outside* entry points. Keymaps that act *inside* the CLI window
-- go in the cli.win.keys table in ai.lua, not here.
-- <Tab> in normal mode jumps to or applies the next NES suggestion; falls
-- through to a literal <Tab> when none is active. blink.cmp's <Tab> is insert-
-- mode only, so there's no conflict. Telescope's <Tab> (multi-select) is
-- buffer-local to the picker prompt, so it shadows this global binding inside
-- pickers — no conflict there either.
vim.keymap.set('n', '<Tab>', function()
  if not require('sidekick').nes_jump_or_apply() then
    return '<Tab>'
  end
end, { expr = true, desc = 'AI: NES jump or apply' })

-- Focus the sidekick CLI split from any mode.
-- NOTE: <C-.> requires a terminal that sends CSI u sequences (kitty, iTerm2
-- with CSI u, WezTerm, Ghostty). macOS Terminal.app and some others do not
-- transmit <C-.> — <leader>ai is the cross-terminal fallback.
vim.keymap.set({ 'n', 't', 'i', 'x' }, '<C-.>',
  function() require('ai').focus() end, { desc = 'AI: Focus active CLI' })
vim.keymap.set('n', '<leader>ai',
  function() require('ai').focus() end, { desc = 'AI: Focus active CLI (fallback for <C-.>)' })

vim.keymap.set('n', '<leader>aa',
  function() require('ai').toggle_active() end,
  { desc = 'AI: Toggle active CLI session' })
vim.keymap.set('n', '<leader>an',
  function() require('ai').new_session() end,
  { desc = 'AI: New Claude session' })
vim.keymap.set('n', '<leader>al',
  function() require('ai').switch() end,
  { desc = 'AI: Switch/kill running CLI session' })   -- <CR> switch, <C-d> kill
vim.keymap.set('n', '<leader>as',
  function() require('sidekick.cli').select() end, { desc = 'AI: Select CLI tool' })
-- close() kills the terminal process, deletes the buffer, and detaches the
-- session. This is not "hide" — it's "tear down." Use <leader>aa (toggle) to
-- show/hide without losing state. Guarded with a floating confirm popup
-- (utils.confirm — y confirms, anything else is No): <leader>ad sits one key
-- from <leader>aa/<leader>as, so a typo shouldn't be able to silently discard
-- a running Claude conversation.
vim.keymap.set('n', '<leader>ad', function()
  require('utils').confirm('Kill active CLI session? (Tears down the terminal and session state)',
    function() require('ai').kill_active() end)
end, { desc = 'AI: Kill active CLI session' })
vim.keymap.set('n', '<leader>ao', function()
  require('sidekick.cli').prompt({ cb = function(_, text)
    if text then require('ai').send({ text = text }) end
  end })
end, { desc = 'AI: Select prompt' })

-- Send-context bindings. Each forwards a sidekick template variable to the
-- active CLI (see sidekick's cli/context/init.lua for the full var list).
-- {this} covers both cases:
--   normal mode → {position}; visual mode → {selection}
-- so a separate {selection} binding isn't needed.
vim.keymap.set({ 'n', 'x' }, '<leader>at',
  function() require('ai').send({ msg = '{this}' }) end,
  { desc = 'AI: Send this (position or selection)' })
-- {file} on <leader>ap — p = path, matching the `yp`/`yP` yank convention.
vim.keymap.set('n', '<leader>ap',
  function() require('ai').send({ msg = '{file}' }) end,
  { desc = 'AI: Send file (path)' })
-- {function}/{class} need nvim-treesitter-textobjects (packadd'd in plugins.lua).
-- They send a position reference (type + name + file:line) for the textobject
-- at the cursor; outside any function/class the send is a benign no-op.
vim.keymap.set('n', '<leader>af',
  function() require('ai').send({ msg = '{function}' }) end,
  { desc = 'AI: Send enclosing function' })
vim.keymap.set('n', '<leader>ac',
  function() require('ai').send({ msg = '{class}' }) end,
  { desc = 'AI: Send enclosing class' })
-- {diagnostics} on <leader>ae — e = diagnostic, mirroring <leader>ce.
vim.keymap.set('n', '<leader>ae',
  function() require('ai').send({ msg = '{diagnostics}' }) end,
  { desc = 'AI: Send buffer diagnostics' })
vim.keymap.set('n', '<leader>ab',
  function() require('ai').send({ msg = '{buffers}' }) end,
  { desc = 'AI: Send open buffers' })
vim.keymap.set('n', '<leader>aq',
  function() require('ai').send({ msg = '{quickfix}' }) end,
  { desc = 'AI: Send quickfix list' })

-- Editing utilities (<leader>u)
local edit = require('edit')

-- x (visual only, not select mode) — using a :cmd RHS so '</'> marks are
-- set correctly before the substitution runs.
vim.keymap.set('x', '<leader>us', [[:s/\s\+$//e<CR>]],
  { desc = 'Utilities: Strip trailing whitespace (selection)', silent = true })

vim.keymap.set('n', '<leader>us', function()
  edit.strip_trailing_ws(1, vim.fn.line('$'))
end, { desc = 'Utilities: Strip trailing whitespace (file)' })

vim.api.nvim_create_user_command('StripWS', function(opts)
  edit.strip_trailing_ws(opts.line1, opts.line2)
end, { range = '%', desc = 'Strip trailing whitespace (range or whole file)' })

-- :'<,'>CleanPaste — reflow pasted Claude/terminal text: strip indent,
-- normalize NBSP, strip ⏺ markers, join soft-wrapped continuation lines.
-- The ':' prefix in the x-mode RHS exits visual mode first, which updates
-- the '< '> marks before the range is evaluated. Do NOT change to <cmd>.
vim.keymap.set('x', '<leader>uc', [[:CleanPaste<CR>]],
  { desc = 'Utilities: Clean pasted terminal text (reflow)', silent = true })

vim.api.nvim_create_user_command('CleanPaste', function(opts)
  require('edit').clean_pasted(opts.line1, opts.line2)
end, { range = '%', desc = 'Reflow pasted Claude/terminal text (range or whole buffer)' })
