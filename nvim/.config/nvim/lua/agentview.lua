-- Agent view: cmux-style dashboard for the sidekick CLI sessions. <leader>av
-- (or <M-v> inside a CLI) toggles a dedicated tabpage — a 30-col sidebar
-- listing every session, with the selected session's real terminal buffer
-- embedded beside it. While the view tab is current, ai.lua's show/focus/
-- toggle paths delegate here (see the `is_active()` checks there): the view
-- owns all display, sidekick owns zero windows — embedded terminals are
-- shown via nvim_win_set_buf, never cli.show, so `term.win` stays nil and
-- closing the view leaves every job running for the normal right-column
-- flows. Lazy-required (no init.lua entry); degrades to a glyph-less list
-- when agent_events isn't loaded. See plans/sidekick-agent-view.md.
local M = {}

local utils = require('utils')

local tab, main_win, sidebar_win, origin_tab
local sidebar_buf, empty_buf
local pending          -- name spawned from the view; embedded on first attach
local restore_solo     -- origin tab had a CLI column at open → re-show on close
local rows_by_lnum = {}
local scheduled = false
local ns = vim.api.nvim_create_namespace('agentview')
local augroup = vim.api.nvim_create_augroup('UserAgentview', { clear = true })

-- Status → { glyph, hlgroup }. Distinct shapes, not just colors: urgent vs
-- unread must survive a colorblind glance. Groups link in themes.lua.
local GLYPHS = {
  urgent  = { '!', 'AgentviewUrgent' },
  unread  = { '●', 'AgentviewUnread' },
  running = { '»', 'AgentviewRunning' },
  idle    = { '○', 'AgentviewIdle' },
  none    = { '·', 'AgentviewNoSignal' },
}

-- The view tab is found by its marker, never by cached handle alone, so a
-- re-source (locals reset) or a stray :q can always be recovered from.
local function find_tab()
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.t[t].agentview then return t end
  end
end

-- Rebuild the window handles from the tab's own stamps. False = structure
-- broken (a window was :q'd) — callers rebuild rather than limp along.
local function adopt(t)
  tab, main_win, sidebar_win = t, nil, nil
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
    if vim.w[w].agentview_main then
      main_win = w
    elseif vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agentview' then
      sidebar_win = w
    end
  end
  return main_win ~= nil and sidebar_win ~= nil
end

-- The delegate gate: true only when the view tab is CURRENT and intact —
-- working in tab 1 while the view idles in tab 2 must use the normal
-- right-column paths.
function M.is_active()
  local t = vim.api.nvim_get_current_tabpage()
  if not vim.t[t].agentview then return false end
  if t == tab and main_win and vim.api.nvim_win_is_valid(main_win)
     and sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    return true
  end
  return adopt(t)
end

-- Running sessions name-sorted (cycle()'s comparator, so row order == cycle
-- order == digit order), then in-flight spawns. Digits are assigned to
-- running rows only — a spawning row never holds a number, so sidebar `N`
-- always means the same session as <M-N>.
local function rows()
  local sessions = require('sidekick.cli.state').get({ started = true })
  table.sort(sessions, function(a, b) return a.tool.name < b.tool.name end)
  local out, seen = {}, {}
  for i, s in ipairs(sessions) do
    out[#out + 1] = { name = s.tool.name, index = i <= 9 and i or nil }
    seen[s.tool.name] = true
  end
  local spawning = {}
  for name, phase in pairs(require('ai')._dynamic) do
    if phase == 'registered' and not seen[name] then spawning[#spawning + 1] = name end
  end
  table.sort(spawning)
  for _, name in ipairs(spawning) do
    out[#out + 1] = { name = name, spawning = true }
  end
  return out
end

local function status_of(name)
  local ev = package.loaded['agent_events']  -- absent → Phase-1 degrade, no glyph
  return ev and GLYPHS[ev.status(name)] or nil
end

-- Build one line from {text, hl?} segments, returning byte-offset marks.
local function compose(segments)
  local line, marks, col = '', {}, 0
  for _, seg in ipairs(segments) do
    if seg[2] then marks[#marks + 1] = { col, col + #seg[1], seg[2] } end
    line = line .. seg[1]
    col = col + #seg[1]
  end
  return line, marks
end

local function render()
  if not (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then return end
  local ai = require('ai')
  local rs = rows()
  rows_by_lnum = {}
  local lines, all_marks, glyphs = {}, {}, {}
  if #rs == 0 then
    lines = { ' (no running agents)', '', ' n  new session', ' q  close' }
    for i = 1, #lines do all_marks[i] = { { 0, #lines[i], 'Comment' } } end
  else
    for i, r in ipairs(rs) do
      rows_by_lnum[i] = r
      local label = ai._labels[r.name]
      local segs = {
        { ' ' },
        { r.index and tostring(r.index) or ' ', 'NonText' },
        { ' ' },
        { r.name == ai.active and '▸' or ' ', 'AgentviewActive' },
        { ' ' },
      }
      if label then
        vim.list_extend(segs, { { label, 'AgentviewLabel' }, { '  ' }, { r.name, 'AgentviewName' } })
      else
        segs[#segs + 1] = { r.name, r.spawning and 'AgentviewSpawning' or nil }
      end
      lines[i], all_marks[i] = compose(segs)
      glyphs[i] = r.spawning and { '…', 'AgentviewSpawning' } or status_of(r.name)
    end
  end
  vim.bo[sidebar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
  vim.bo[sidebar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(sidebar_buf, ns, 0, -1)
  for i, marks in pairs(all_marks) do
    for _, m in ipairs(marks) do
      vim.api.nvim_buf_set_extmark(sidebar_buf, ns, i - 1, m[1],
        { end_col = m[2], hl_group = m[3] })
    end
    if glyphs[i] then
      vim.api.nvim_buf_set_extmark(sidebar_buf, ns, i - 1, 0,
        { virt_text = { { glyphs[i][1] .. ' ', glyphs[i][2] } }, virt_text_pos = 'right_align' })
    end
  end
  -- Snap the sidebar cursor to the active row — but never while the user is
  -- browsing inside the sidebar (that would yank j/k out from under them).
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)
     and vim.api.nvim_get_current_win() ~= sidebar_win then
    for lnum, r in pairs(rows_by_lnum) do
      if r.name == ai.active then
        pcall(vim.api.nvim_win_set_cursor, sidebar_win, { lnum, 0 })
        break
      end
    end
  end
end

-- One scheduled render per burst of events (Attach + Detach + WinEnter can
-- all land in the same tick). Hidden view (no tab) renders lazily on open.
local function schedule_render()
  if scheduled then return end
  scheduled = true
  vim.schedule(function()
    scheduled = false
    if find_tab() then render() end
  end)
end

-- Scratch shown in the main pane when nothing is embeddable. Unpin first:
-- stickybuf pinned the window to sidekick_terminal by filetype at embed
-- time, and would bounce a non-CLI buffer right back out.
local function empty_state()
  if not (main_win and vim.api.nvim_win_is_valid(main_win)) then return end
  if not (empty_buf and vim.api.nvim_buf_is_valid(empty_buf)) then
    local existing = vim.fn.bufnr('agentview://empty')
    if existing ~= -1 then
      empty_buf = existing
    else
      empty_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(empty_buf, 'agentview://empty')
      vim.api.nvim_buf_set_lines(empty_buf, 0, -1, false,
        { 'no agent embedded — press n in the sidebar to start one' })
      vim.bo[empty_buf].modifiable = false
      vim.bo[empty_buf].bufhidden = 'hide'
    end
  end
  pcall(require('stickybuf').unpin, main_win)
  vim.api.nvim_win_set_buf(main_win, empty_buf)
  vim.w[main_win].sidekick_cli = nil          -- clear stale session stamps —
  vim.w[main_win].sidekick_session_id = nil   -- WinEnter tracking reads them
end

-- Show `name`'s terminal buffer in the main pane. hide() first so sidekick
-- owns no window while the view owns display (term.win goes nil; the job and
-- buffer live on). Then re-stamp the window: WinEnter active-tracking, the
-- WinClosed width memory, and the byte-forward keys (u/p/<C-u>…) all resolve
-- the session through these window vars, which died with the hidden window.
-- False when the session has no live terminal yet (not started).
local function embed(name)
  if not (main_win and vim.api.nvim_win_is_valid(main_win)) then return false end
  local s = require('sidekick.cli.state').get({ name = name, started = true })[1]
  local t = s and s.terminal
  if not (t and t.buf and vim.api.nvim_buf_is_valid(t.buf)) then return false end
  -- Before the already-shown short-circuit: a window for this session can be
  -- open elsewhere (e.g. re-embedding after <leader>aa opened it in another
  -- tab) even while it's already the main pane's buffer here — reclaim it.
  if t:is_open() then t:hide() end
  if vim.api.nvim_win_get_buf(main_win) == t.buf then return true end  -- already shown
  vim.api.nvim_win_set_buf(main_win, t.buf)
  vim.w[main_win].sidekick_cli = t.tool
  vim.w[main_win].sidekick_session_id = t.id
  vim.w[main_win].agentview_main = true
  for opt, v in pairs({ scrolloff = 0, sidescrolloff = 0 }) do
    vim.api.nvim_set_option_value(opt, v, { win = main_win })
  end
  return true
end

-- Re-embed the active session (or fall to the empty state) and redraw.
local function sync()
  if not embed(require('ai').active) then empty_state() end
  render()
end

local function enter_main()
  if not (main_win and vim.api.nvim_win_is_valid(main_win)) then return end
  vim.api.nvim_set_current_win(main_win)
  if vim.bo[vim.api.nvim_win_get_buf(main_win)].buftype == 'terminal' then
    vim.cmd('startinsert')
  end
end
M.enter_main = enter_main  -- ai.jump_unread lands in the main pane in-view

-- The show_solo delegate target: switch the embedded session in place. A
-- name with no terminal yet (fresh create_session) is the one sanctioned
-- cli.show: auto-start hidden-from-focus, marked pending — the Attach
-- handler below hides the transient split and embeds it.
function M.select(name)
  require('ai')._set_active(name)
  if not embed(name) then
    pending = name
    pcall(require('sidekick.cli').show, { name = name, focus = false })
  end
  schedule_render()
end

-- <C-.> / <leader>ai inside the view: bounce main pane ↔ sidebar (mirrors
-- cli.focus's focus/blur toggle).
function M.focus_main()
  if not M.is_active() then return end
  if vim.api.nvim_get_current_win() == main_win then
    vim.api.nvim_set_current_win(sidebar_win)
  else
    enter_main()
  end
end

-- 0 (current window), not sidebar_win: these keymaps are buffer-local, so
-- they can fire in any window showing agentview://agents — a stale cached
-- handle would read the wrong cursor.
local function row_under_cursor()
  return rows_by_lnum[vim.api.nvim_win_get_cursor(0)[1]]
end

local function activate(r)
  if not r then return end
  if r.spawning then
    return vim.notify(('agent view: %s is still starting'):format(r.name), vim.log.levels.INFO)
  end
  M.select(r.name)
  enter_main()
end

local function sidebar_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map('<CR>', function() activate(row_under_cursor()) end, 'AI: Open session under cursor')
  for i = 1, 9 do
    map(tostring(i), function()
      for _, r in pairs(rows_by_lnum) do
        if r.index == i then return activate(r) end
      end
    end, 'AI: Open session ' .. i)
  end
  map('<M-]>', function() require('ai').cycle(1) end, 'AI: Next CLI session')
  map('<M-[>', function() require('ai').cycle(-1) end, 'AI: Previous CLI session')
  map('n', function() require('ai').new_session() end, 'AI: New agent session')
  map('r', function()
    local r = row_under_cursor()
    if r then require('ai').rename(r.name, schedule_render) end
  end, 'AI: Label session under cursor')
  map('x', function()
    local r = row_under_cursor()
    if not r or r.spawning then return end
    utils.confirm(('Kill session %s?'):format(r.name), function()
      require('ai').kill(r.name)
      -- render()'s cursor-snap self-skips while the sidebar is current (j/k
      -- browsing must not be yanked) — but a kill is a commit, not a browse.
      -- Schedule past the Detach handler's own render (kill's State.detach
      -- queues that event via vim.schedule too, ahead of this one).
      vim.schedule(function()
        if not (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) then return end
        local active = require('ai').active
        for lnum, row in pairs(rows_by_lnum) do
          if row.name == active then
            pcall(vim.api.nvim_win_set_cursor, sidebar_win, { lnum, 0 })
            break
          end
        end
      end)
    end)
  end, 'AI: Kill session under cursor')
  map('q', function() M.close() end, 'AI: Close agent view')
  map('<Esc>', function() M.close() end, 'AI: Close agent view')
end

-- One scratch sidebar buffer, reused across open/close and re-sources
-- (looked up by name — module locals don't survive a re-source, the buffer
-- does). Keymaps re-apply on every lookup so their closures always belong to
-- the live module instance. filetype LAST: stickybuf/clamp arm on FileType.
local function ensure_sidebar_buf()
  if not (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then
    local existing = vim.fn.bufnr('agentview://agents')
    if existing ~= -1 then
      sidebar_buf = existing
    else
      sidebar_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(sidebar_buf, 'agentview://agents')
      vim.bo[sidebar_buf].buftype = 'nofile'
      vim.bo[sidebar_buf].bufhidden = 'hide'
      vim.bo[sidebar_buf].swapfile = false
      vim.bo[sidebar_buf].modifiable = false
    end
  end
  sidebar_keymaps(sidebar_buf)
  if vim.bo[sidebar_buf].filetype ~= 'agentview' then
    vim.bo[sidebar_buf].filetype = 'agentview'
  end
  return sidebar_buf
end

local function build_tab()
  vim.cmd('tabnew')
  tab = vim.api.nvim_get_current_tabpage()
  vim.t[tab].agentview = true
  main_win = vim.api.nvim_get_current_win()
  vim.w[main_win].agentview_main = true
  local tabnew_buf = vim.api.nvim_win_get_buf(main_win)
  vim.cmd('topleft 30vsplit')
  sidebar_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(sidebar_win, ensure_sidebar_buf())
  for opt, v in pairs({
    number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0',
    winfixwidth = true, cursorline = true, wrap = false,
    scrolloff = 0, sidescrolloff = 0, list = false, spell = false,
  }) do
    vim.api.nvim_set_option_value(opt, v, { win = sidebar_win })
  end
  empty_state()  -- main pane placeholder until sync() embeds
  -- Drop tabnew's empty no-name buffer — it would linger listed forever.
  if vim.api.nvim_buf_is_valid(tabnew_buf)
     and vim.api.nvim_buf_get_name(tabnew_buf) == ''
     and not vim.bo[tabnew_buf].modified then
    pcall(vim.api.nvim_buf_delete, tabnew_buf, {})
  end
end

-- Was a solo CLI column open in `tabpage`? Splits only (`relative == ''`) —
-- the pre-warm hidden float is is_open() too and must not count.
local function solo_open_in(tabpage)
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t:is_open() and vim.api.nvim_win_get_config(t.win).relative == ''
       and vim.api.nvim_win_get_tabpage(t.win) == tabpage then
      return true
    end
  end
  return false
end

function M.open()
  -- Embedding hides the active session's window wherever it is — including
  -- an open <leader>aa column in this tab. Remember that it was open so
  -- close() can put it back instead of leaving the working tab column-less.
  -- `or` keeps an already-true flag alive: re-entering the view from its own
  -- origin tab, the column the first open() hid is gone, so this would
  -- otherwise recompute false and close() would lose the restore.
  restore_solo = restore_solo or solo_open_in(vim.api.nvim_get_current_tabpage())
  local t = find_tab()
  if t then
    if adopt(t) then
      if vim.api.nvim_get_current_tabpage() ~= t then
        origin_tab = vim.api.nvim_get_current_tabpage()
        vim.api.nvim_set_current_tabpage(t)
      end
      sync()
      return
    end
    -- Structure broken (a window was :q'd): close the remnant, rebuild.
    origin_tab = vim.api.nvim_get_current_tabpage() ~= t
      and vim.api.nvim_get_current_tabpage() or origin_tab
    if not pcall(vim.cmd, vim.api.nvim_tabpage_get_number(t) .. 'tabclose') then
      -- Only tab left, tabclose refused: strip the marker so find_tab()
      -- doesn't hand back this broken remnant forever.
      vim.t[t].agentview = nil
    end
  else
    origin_tab = vim.api.nvim_get_current_tabpage()
  end
  build_tab()
  sync()
  vim.api.nvim_set_current_win(sidebar_win)
end

function M.close()
  local t = find_tab()
  if not t then return end
  pending = nil  -- an abandoned mid-spawn name must not auto-embed on a later reuse
  if #vim.api.nvim_list_tabpages() == 1 then vim.cmd('tabnew') end
  pcall(vim.cmd, vim.api.nvim_tabpage_get_number(t) .. 'tabclose')
  if origin_tab and vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
    -- Restore the column the open-time embed hid: re-show the ACTIVE
    -- session (it may have changed in the view — one visible CLI = active,
    -- same as show_solo), unfocused, at the remembered width. No promote
    -- reflow: SidekickCliAttach fires once per lifetime, and re-shows land
    -- full-height on their own (see ai.lua's promote comment).
    if restore_solo then
      restore_solo = nil
      local ai = require('ai')
      if #require('sidekick.cli.state').get({ name = ai.active, started = true }) > 0 then
        pcall(require('sidekick.cli').show, { name = ai.active, focus = false })
      end
    end
  end
end

function M.toggle()
  local t = find_tab()
  if t and vim.api.nvim_get_current_tabpage() == t then
    M.close()
  else
    M.open()
  end
end

vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'SidekickCliAttach',
  desc = 'Agent view: hide transient spawn windows, embed pending session',
  callback = function(args)
    if not M.is_active() then return schedule_render() end
    local id = args.data.id
    -- Emitted synchronously from inside Session.attach — state.lua's
    -- M.attach hasn't called terminal:show() yet at this point, it does so
    -- right after Session.attach returns. Hiding the window here (pre-show)
    -- would just make that unconditional show() open a fresh split. Defer
    -- everything to after it, re-resolving state fresh since a scheduled
    -- tick can land after the view itself closed.
    vim.schedule(function()
      if not M.is_active() then return end
      local term = require('sidekick.cli.terminal').get(id)
      -- Any sidekick window materializing in the view tab (spawn split, a late
      -- pre-warm float) violates "the view owns display" — hide it. The job is
      -- untouched; ai.lua's promote already skipped this tab (its agentview
      -- guard), so nothing was reflowed.
      if term and term.win and vim.api.nvim_win_is_valid(term.win)
         and term.win ~= main_win
         and vim.api.nvim_win_get_tabpage(term.win) == tab then
        term:hide()
      end
      if term and term.tool and term.tool.name == pending then
        pending = nil
        embed(term.tool.name)
      end
      schedule_render()
    end)
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'SidekickCliDetach',
  desc = 'Agent view: re-embed after a session dies',
  callback = function()
    if not find_tab() then return end
    -- Only re-embed when the view tab is actually current: a session dying
    -- while the view idles in a background tab must not yank the focused
    -- tab's CLI column out from under the user (embed() would hide it).
    if not M.is_active() then return schedule_render() end
    -- ai.lua's detach sweep (same event, registered earlier) already
    -- repointed M.active to a survivor.
    sync()
  end,
})

vim.api.nvim_create_autocmd({ 'WinEnter' }, {
  group = augroup,
  desc = 'Agent view: track the ▸ active marker',
  callback = schedule_render,
})

-- Live preview: browsing the sidebar with j/k swaps the row's terminal into
-- the main pane immediately — no <CR> needed to *see* a session. A pure
-- buffer swap (embed), NOT a commit: M.active/M._last (the <C-]> alt-tab
-- pair) only change on <CR>/digits or on entering the pane (whose re-stamp
-- makes the WinEnter tracker commit what you're looking at). The ▸ marker
-- keeps showing the committed active session while previewing.
vim.api.nvim_create_autocmd('CursorMoved', {
  group = augroup,
  desc = 'Agent view: preview the session under the cursor',
  callback = function()
    if not (sidebar_buf and vim.api.nvim_get_current_buf() == sidebar_buf) then return end
    if not M.is_active() then return end
    local r = rows_by_lnum[vim.api.nvim_win_get_cursor(0)[1]]
    if r and not r.spawning then embed(r.name) end
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'AgentSessionEvent',
  desc = 'Agent view: refresh status glyphs',
  callback = schedule_render,
})

-- The sidebar is a synthetic named-nofile buffer — it can't be
-- session-serialized (same class of problem as session.lua's grug-far
-- sweep, handled feature-locally here instead of growing that list).
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'PersistenceSavePre',
  desc = 'Agent view: close before session save',
  callback = function()
    -- Not M.close(): a save must not change the recorded current tab or
    -- open/close any other window (origin_tab switch, restore_solo re-show).
    -- Just remove the view tab so it isn't serialized.
    local t = find_tab()
    if t then
      if #vim.api.nvim_list_tabpages() == 1 then vim.cmd('tabnew') end
      pcall(vim.cmd, vim.api.nvim_tabpage_get_number(t) .. 'tabclose')
    end
    restore_solo, pending = nil, nil
    for _, b in ipairs({ sidebar_buf, empty_buf }) do
      if b and vim.api.nvim_buf_is_valid(b) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    sidebar_buf, empty_buf = nil, nil
  end,
})

return M
