-- Note: which-key uses an explicit trigger list (see whichkey.lua). If you add
-- a new single-char group in whichkey.lua's wk.add(), add it to triggers too.

-- Telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', function() require('pickers.filter').find_files() end,
  { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', function() require('pickers.filter').live_grep() end,
  { desc = 'Search: Grep' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', builtin.resume,                      { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', builtin.current_buffer_fuzzy_find,   { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sm', function() require('pickers.gitstatus').open() end,
  { desc = 'Search: Modified files' })
vim.keymap.set('n', '<leader>ss', function() require('pickers.symbols').workspace() end,
  { desc = 'Search: Symbols (workspace)' })
vim.keymap.set('n', '<leader>sS', function() require('pickers.symbols').document() end,
  { desc = 'Search: Symbols (document)' })
vim.keymap.set('n', '<leader>so', builtin.oldfiles,                      { desc = 'Search: Recent files' })
vim.keymap.set('n', '<leader>st', function() require('pickers.theme').open() end,
  { desc = 'Search: Themes' })
vim.keymap.set('n', '<leader>sF', function() require('pickers.filter').pick() end,
  { desc = 'Search: Toggle filters' })

-- Clear search highlights and close any floating windows (hover, diagnostics, etc.)
-- Sets b:hover_suppressed so CursorHold hover doesn't immediately reopen the float.
-- The flag is cleared on the next CursorMoved (see autocmd below).
vim.keymap.set('n', '<Esc>', function()
  local closed_any = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
      pcall(vim.api.nvim_win_close, win, true)
      closed_any = true
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

-- Exit insert mode without reaching for Escape
vim.keymap.set('i', 'jj', '<Esc>', { desc = 'Exit insert mode' })

-- Yank to system clipboard (dd, x, c stay in Neovim register).
-- Uses expr mapping so that explicit register prefixes ("a, "b, etc.) are
-- honoured — only bare y/Y without a register prefix go to clipboard.
vim.keymap.set({'n', 'v'}, 'y', function()
  if vim.v.register ~= '"' then return 'y' end
  return '"+y'
end, { expr = true, desc = 'Yank to system clipboard (unless register specified)' })

vim.keymap.set('n', 'Y', function()
  if vim.v.register ~= '"' then return 'Y' end
  return '"+Y'
end, { expr = true, desc = 'Yank line to system clipboard (unless register specified)' })

-- Stay in visual mode after indent/dedent
vim.keymap.set('v', '<', '<gv', { desc = 'Dedent and reselect' })
vim.keymap.set('v', '>', '>gv', { desc = 'Indent and reselect' })

-- Paste over selection without clobbering the register
vim.keymap.set('v', 'p', '"_dP', { desc = 'Paste without yanking replaced text' })

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
vim.keymap.set({ 'n', 'v' }, '<X1Mouse>', '<C-o>', { desc = 'Jumplist: back (mouse back button)' })
vim.keymap.set({ 'n', 'v' }, '<X2Mouse>', '<C-i>', { desc = 'Jumplist: forward (mouse forward button)' })

-- Ctrl + LeftClick → LSP go-to-definition (VS Code-style). The <LeftMouse>
-- feedkeys places the cursor under the pointer before the LSP call, so the
-- jump targets the word actually clicked. Use <C-o>/<C-i> (or the side-button
-- mappings above) to jump back/forward.
vim.keymap.set('n', '<C-LeftMouse>', function()
  local keys = vim.api.nvim_replace_termcodes('<LeftMouse>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'nx', false)
  vim.lsp.buf.definition()
end, { desc = 'LSP: Go to definition (Ctrl+click)' })
-- Skip terminal buffers (toggleterm, sidekick's CLI) and special panel
-- filetypes (aerial, nvim-tree) as alternate-buffer targets — landing on one
-- of these via '#' is never useful and stickybuf doesn't guard this direction
-- (it only protects a pinned window from foreign buffers, not the reverse).
local alt_buffer_skip_filetypes = { aerial = true, NvimTree = true }
vim.keymap.set('n', '<leader><leader>', function()
  local alt = vim.fn.bufnr('#')
  if alt == -1 or not vim.api.nvim_buf_is_valid(alt) then
    vim.notify('No alternate buffer', vim.log.levels.WARN)
    return
  end
  if vim.bo[alt].buftype == 'terminal' or alt_buffer_skip_filetypes[vim.bo[alt].filetype] then
    -- Silently declining with no feedback reads as a broken keymap; say why.
    vim.notify('Alternate buffer is a terminal/panel — skipped', vim.log.levels.WARN)
    return
  end
  vim.cmd('buffer #')
end, { desc = 'Toggle alternate buffer' })
vim.keymap.set('n', '<leader>m', function() require('pickers.buffer').open() end,
  { desc = 'Buffer picker' })

-- File tree: opens and reveals current file, or closes if already open
vim.keymap.set('n', '<leader>e', '<cmd>NvimTreeFindFileToggle<CR>', { desc = 'Explorer: Toggle' })

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
vim.keymap.set('n', '<leader>uo', open_in_typora, { desc = 'Open in Typora' })

-- Quit
vim.api.nvim_create_user_command('Q', 'qa', {})
-- Close buffer without closing the window/pane. mini.bufremove picks a
-- replacement buffer for every window showing it (alternate, then most
-- recent, then a scratch buffer) so all splits stay open.
-- <leader>bd matches the common convention (LazyVim, bufdelete.nvim, etc.);
-- <leader>qq kept as an alias for existing muscle memory.
local close_buffer = function()
  require('mini.bufremove').delete(0, false)
end
vim.keymap.set('n', '<leader>bd', close_buffer, { desc = 'Close buffer' })
vim.keymap.set('n', '<leader>qq', close_buffer, { desc = 'Close buffer' })

-- Toggle spell checking
vim.keymap.set('n', '<leader>tz', function()
  vim.opt.spell = not vim.opt.spell:get()
end, { desc = 'Toggle: Spell check' })

-- Toggle line numbers: absolute (default) <-> relative.
vim.keymap.set('n', '<leader>tn', function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = 'Toggle: Relative line numbers' })

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

-- Toggle comment on current line / selection — remap to reach Neovim's
-- built-in gcc/gc (not a raw keystroke passthrough, since gcc is itself a
-- mapping registered by core; noremap would bypass it).
vim.keymap.set('n', '<leader>tc', 'gcc', { remap = true, desc = 'Toggle: Comment (line)' })
vim.keymap.set('x', '<leader>tc', 'gc', { remap = true, desc = 'Toggle: Comment (selection)' })

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
  function() require('sidekick.cli').focus() end, { desc = 'AI: Focus CLI' })
vim.keymap.set('n', '<leader>ai',
  function() require('sidekick.cli').focus() end, { desc = 'AI: Focus CLI (fallback for <C-.>)' })

vim.keymap.set('n', '<leader>aa',
  function() require('sidekick.cli').toggle({ name = 'claude', focus = true }) end,
  { desc = 'AI: Toggle Claude CLI' })
vim.keymap.set('n', '<leader>as',
  function() require('sidekick.cli').select() end, { desc = 'AI: Select CLI tool' })
-- close() kills the terminal process, deletes the buffer, and detaches the
-- session. This is not "hide" — it's "tear down." Use <leader>aa (toggle) to
-- show/hide without losing state.
vim.keymap.set('n', '<leader>ad',
  function() require('sidekick.cli').close() end, { desc = 'AI: Kill CLI session' })
vim.keymap.set('n', '<leader>ap',
  function() require('sidekick.cli').prompt() end, { desc = 'AI: Select prompt' })
-- Sidekick template variables (see reference table in this plan):
--   {this}      → {position} in normal mode, {selection} in visual mode
--   {file}      → relative file path
--   {selection} → visual selection text (equivalent to {this} in visual mode)
-- This single binding covers both cases, so a separate <leader>av is not needed.
vim.keymap.set({ 'n', 'x' }, '<leader>at',
  function() require('sidekick.cli').send({ msg = '{this}' }) end,
  { desc = 'AI: Send this (position or selection)' })
vim.keymap.set('n', '<leader>af',
  function() require('sidekick.cli').send({ msg = '{file}' }) end,
  { desc = 'AI: Send file' })

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
