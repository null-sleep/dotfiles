-- Note: which-key uses an explicit trigger list (see whichkey.lua). If you add
-- a new single-char group in whichkey.lua's wk.add(), add it to triggers too.

-- Pickers (snacks.picker; setup in picker.lua)
-- <leader>sg is live grep: every keystroke is a ripgrep regex, and raw rg
-- flags pass through after ` -- ` (e.g. `handleRequest -- -tgo`). <c-g> in
-- the prompt buffers results into the fuzzy matcher (fzf-style operators).
vim.keymap.set('n', '<leader>sf', function() Snacks.picker.files() end, { desc = 'Search: Files' })
vim.keymap.set('n', '<leader>sg', function() Snacks.picker.grep() end,  { desc = 'Search: Grep' })
-- <leader>sw greps the word under the cursor (visual: the selection) —
-- picker:word() covers both — with --word-regexp, so it's not fuzzy: an
-- exact-match jump straight to every real usage, skipping the sg-then-type step.
vim.keymap.set({ 'n', 'x' }, '<leader>sw', function() Snacks.picker.grep_word() end,
  { desc = 'Search: Grep word under cursor' })
-- Visual-only: grep the selection literally, multi-line included — snacks'
-- grep source can't render multi-line matches. See pickers/grepselection.lua.
vim.keymap.set('x', '<leader>ss', function() require('pickers.grepselection').search() end,
  { desc = 'Search: Grep selection (literal, multi-line)' })
vim.keymap.set('n', '<leader>sh', function() Snacks.picker.help() end,  { desc = 'Search: Help tags' })
vim.keymap.set('n', '<leader>sr', function() Snacks.picker.resume() end, { desc = 'Search: Resume last' })
vim.keymap.set('n', '<leader>s/', function() Snacks.picker.lines() end, { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sb', function() Snacks.picker.lines() end, { desc = 'Search: Current buffer' })
vim.keymap.set('n', '<leader>sm', function() require('pickers.gitstatus').open() end,
  { desc = 'Search: Modified files (count = last N commits)' })
vim.keymap.set('n', '<leader>ss', function() require('pickers.symbols').workspace() end,
  { desc = 'Search: Symbols (workspace)' })
vim.keymap.set('n', '<leader>sd', function() require('pickers.symbols').document() end,
  { desc = 'Search: Symbols (document)' })
vim.keymap.set('n', '<leader>so', function() Snacks.picker.recent() end, { desc = 'Search: Recent files' })
vim.keymap.set('n', '<leader>st', function() require('pickers.theme').open() end,
  { desc = 'Search: Themes' })
-- <C-q> from a picker fills these lists; these read them back with fuzzy
-- filter + preview. Raw window: <leader>tq. See GUIDE.md "Quickfix & location lists".
vim.keymap.set('n', '<leader>sq', function() Snacks.picker.qflist() end,
  { desc = 'Search: Quickfix list' })
vim.keymap.set('n', '<leader>sl', function() Snacks.picker.loclist() end,
  { desc = 'Search: Location list' })
-- sQ/sL pick a whole list from the history stack (]Q/[Q step it one at a
-- time). See GUIDE.md "Quickfix & location lists".
vim.keymap.set('n', '<leader>sQ', function() require('pickers.qfhistory').open('quickfix') end,
  { desc = 'Search: Quickfix history' })
vim.keymap.set('n', '<leader>sL', function() require('pickers.qfhistory').open('location') end,
  { desc = 'Search: Location-list history' })

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

-- Option+Left/Right word-jump. The terminal (Ghostty/iTerm2, both configured
-- with macos-option-as-alt for nvim's <M-...> maps) rewrites Option+Arrow
-- into literal Meta+letter — readline's own word-jump convention (<M-b>/
-- <M-f> = backward/forward-word) — rather than <M-Left>/<M-Right>; confirmed
-- via i_CTRL-V capture. Vim's 'b'/'w' are the equivalent motions; <C-o> runs
-- one Normal-mode command from Insert mode without leaving it. Without this,
-- <M-f> in Normal mode falls through (via 'ttimeoutlen') to Vim's own 'f' —
-- "find character", not word-forward — which is why Option-Right looked
-- broken while Option-Left (falling through to 'b', word-back) looked like
-- it worked by coincidence.
vim.keymap.set({ 'n', 'x' }, '<M-b>', 'b', { desc = 'Word: back' })
vim.keymap.set({ 'n', 'x' }, '<M-f>', 'w', { desc = 'Word: forward' })
vim.keymap.set('i', '<M-b>', '<C-o>b', { desc = 'Word: back' })
vim.keymap.set('i', '<M-f>', '<C-o>w', { desc = 'Word: forward' })
vim.keymap.set('i', '<M-BS>', '<C-w>', { desc = 'Word: delete back' })
vim.keymap.set('i', '<M-d>', '<C-o>dw', { desc = 'Word: delete forward' })

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
vim.keymap.set('n', 'gb', function()
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
end, { desc = 'Buffer: toggle alternate' })

-- Frecency-ranked buffers + recent + files in one list (snacks `smart`),
-- scoped to the cwd so it doesn't surface files from unrelated repos. The
-- alternate file is flagged '#' and usually near the top, but frecency blends
-- frequency with recency so it isn't reliably row 1 — the deterministic
-- one-key jump-to-previous is `gb` above; this is "take me to something I've
-- been in lately". See plans/telescope-vs-snacks-picker.md.
vim.keymap.set('n', '<leader><leader>', function() Snacks.picker.smart({ filter = { cwd = true } }) end,
  { desc = 'Search: Smart (frecency: buffers + recent + files, cwd-scoped)' })
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
-- Only one left-edge sidebar at a time (symmetric with outline.lua's
-- <leader>o). Guarded on the tree not already being visible, so this fires on
-- the OPEN edge only. GUIDE.md "Left-edge sidebars swap into each other".
vim.keymap.set('n', '<leader>e', function()
  local nvim_tree_api = require('nvim-tree.api')
  if not nvim_tree_api.tree.is_visible() then
    require('buffers').close_other_sidebars('NvimTree')
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

-- Toggle the quickfix window; winid == 0 means "not open" (:help getqflist()).
-- Empty-list guard: :copen would open a blank split. botright matches the
-- window snacks' own <C-q> action opens, so both keys land the same split.
vim.keymap.set('n', '<leader>tq', function()
  if vim.fn.getqflist({ winid = 0 }).winid ~= 0 then
    vim.cmd('cclose')
  elseif vim.fn.getqflist({ size = 0 }).size == 0 then
    vim.notify('Quickfix list is empty')
  else
    vim.cmd('botright copen')
  end
end, { desc = 'Toggle: Quickfix window' })

-- Loclist twin of <leader>tq, on the current window's list. No botright:
-- a loclist window is window-scoped, unlike the full-width quickfix split.
vim.keymap.set('n', '<leader>tl', function()
  if vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 then
    vim.cmd('lclose')
  elseif vim.fn.getloclist(0, { size = 0 }).size == 0 then
    vim.notify('Location list is empty')
  else
    vim.cmd('lopen')
  end
end, { desc = 'Toggle: Location list window' })

-- ]q/[q walk the quickfix list, ]l/[l the location list. Honors a count
-- (3]q → :3cnext) like the built-in defaults these shadow. Wraparound: pcall
-- swallows the end-of-list error (E553) so cfirst/clast loop around; the size
-- guard turns an empty list into a notify, not a raw E42.
local function list_nav(size, move, wrap, empty_msg)
  return function()
    if size() == 0 then
      vim.notify(empty_msg)
    elseif not pcall(vim.cmd, vim.v.count1 .. move) then
      vim.cmd(wrap)
    end
  end
end
local qf_size = function() return vim.fn.getqflist({ size = 0 }).size end
local ll_size = function() return vim.fn.getloclist(0, { size = 0 }).size end
vim.keymap.set('n', ']q', list_nav(qf_size, 'cnext', 'cfirst', 'Quickfix list is empty'),
  { desc = 'Quickfix: next entry' })
vim.keymap.set('n', '[q', list_nav(qf_size, 'cprev', 'clast', 'Quickfix list is empty'),
  { desc = 'Quickfix: previous entry' })
vim.keymap.set('n', ']l', list_nav(ll_size, 'lnext', 'lfirst', 'Location list is empty'),
  { desc = 'Location list: next entry' })
vim.keymap.set('n', '[l', list_nav(ll_size, 'lprev', 'llast', 'Location list is empty'),
  { desc = 'Location list: previous entry' })

-- ]Q/[Q, ]L/[L step the history stack (newer/older whole lists). :{n}chistory
-- takes an absolute index, so compute the wrapped target ourselves and notify
-- the landed list — the switch is otherwise silent. dir: ] = +1, [ = -1.
local function stack_nav(get, hist, label, dir)
  return function()
    local total = get({ nr = '$' }).nr
    if total == 0 then
      vim.notify(label .. ' history is empty')
      return
    end
    local cur = get({ nr = 0 }).nr
    local target = (cur - 1 + dir) % total + 1  -- 1-based wraparound
    vim.cmd(target .. hist)
    local l = get({ nr = target, title = 0, size = 0 })
    vim.notify(('%s list %d/%d: %s (%d)')
      :format(label, target, total, l.title ~= '' and l.title or '(untitled)', l.size))
  end
end
local qf_get = function(q) return vim.fn.getqflist(q) end
local ll_get = function(q) return vim.fn.getloclist(0, q) end
vim.keymap.set('n', ']Q', stack_nav(qf_get, 'chistory', 'Quickfix', 1),
  { desc = 'Quickfix: newer list (history)' })
vim.keymap.set('n', '[Q', stack_nav(qf_get, 'chistory', 'Quickfix', -1),
  { desc = 'Quickfix: older list (history)' })
vim.keymap.set('n', ']L', stack_nav(ll_get, 'lhistory', 'Location', 1),
  { desc = 'Location list: newer list (history)' })
vim.keymap.set('n', '[L', stack_nav(ll_get, 'lhistory', 'Location', -1),
  { desc = 'Location list: older list (history)' })

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

-- AI (sidekick.nvim): agent CLIs (Claude primary, Cursor secondary)
-- These are the *outside* entry points. Keymaps that act *inside* the CLI window
-- go in the cli.win.keys table in ai.lua, not here.

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
  { desc = 'AI: New agent session (claude/cursor picker)' })
vim.keymap.set('n', '<leader>al',
  function() require('ai').switch() end,
  { desc = 'AI: Switch/kill running CLI session' })   -- <CR> switch, <C-d> kill
-- No NORMAL-mode <leader>as (sidekick's tool launcher), even with two agents
-- in cli.tools: <leader>an's picker is the single creation door, and a
-- per-agent summon key would break the flat-pool symmetry
-- (plans/sidekick-cursor-support.md, Decision 2). The visual-mode <leader>as
-- below is separate — this reservation is normal-mode only.
-- close() kills the terminal process, deletes the buffer, and detaches the
-- session. This is not "hide" — it's "tear down." Use <leader>aa (toggle) to
-- show/hide without losing state. Guarded with a floating confirm popup
-- (utils.confirm — y confirms, anything else is No): <leader>ad sits one key
-- from <leader>aa, so a typo shouldn't be able to silently discard a running
-- agent conversation.
vim.keymap.set('n', '<leader>ad', function()
  require('utils').confirm('Kill active CLI session? (Tears down the terminal and session state)',
    function() require('ai').kill_active() end)
end, { desc = 'AI: Kill active CLI session' })
vim.keymap.set('n', '<leader>ao', function()
  require('sidekick.cli').prompt({ cb = function(_, text)
    if text then require('ai').send({ text = text }) end
  end })
end, { desc = 'AI: Select prompt' })

-- Send-context bindings. The positional template vars ({position},
-- {function}, {class}) route through ai_context.lua's cli.context overrides
-- (wired in ai.lua's setup), which emit Claude-native `@file#L<n>` /
-- `@file#L<a>-<b>` mentions — see ai_context.lua's header for why.
-- {this} → cursor-line ref (normal) or line-range ref (visual), so no
-- separate reference binding for selections is needed (<leader>as below
-- sends the literal text instead).
vim.keymap.set({ 'n', 'x' }, '<leader>at',
  function() require('ai').send({ msg = '{this}' }) end,
  { desc = 'AI: Send this (position or selection)' })
-- {file} on <leader>ap — p = path, matching the `yp`/`yP` yank convention.
vim.keymap.set('n', '<leader>ap',
  function() require('ai').send({ msg = '{file}' }) end,
  { desc = 'AI: Send file (path)' })
-- {function}/{class} need nvim-treesitter-textobjects (packadd'd in
-- plugins.lua): a `@file#L<start>-<end>` ref for the enclosing textobject;
-- outside one the send is a benign "Nothing to send." no-op.
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
-- {diagnostics_all} on <leader>aE — workspace-wide ae (capital = wider scope).
vim.keymap.set('n', '<leader>aE',
  function() require('ai').send({ msg = '{diagnostics_all}' }) end,
  { desc = 'AI: Send workspace diagnostics' })
vim.keymap.set('n', '<leader>ab',
  function() require('pickers.aibuffers').open() end,
  { desc = 'AI: Send open buffers (picker)' })
-- Visual-only: the literal selected TEXT (visual <leader>at sends a line-range
-- ref instead) — for non-file buffers or when the exact snippet matters.
vim.keymap.set('x', '<leader>as',
  function() require('ai').send({ msg = '{selection}' }) end,
  { desc = 'AI: Send selection text (literal code)' })
vim.keymap.set('n', '<leader>aq',
  function() require('ai').send({ msg = '{quickfix}' }) end,
  { desc = 'AI: Send quickfix list' })

-- Editing utilities (<leader>u)
local edit = require('edit')

-- Bound here rather than with the other pickers under <leader>s*: reaching for
-- undo history is editing recovery, not search. See GUIDE.md "Undo history".
vim.keymap.set('n', '<leader>uu', function() Snacks.picker.undo() end,
  { desc = 'Utilities: Undo history' })

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
