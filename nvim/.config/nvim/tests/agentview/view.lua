-- Agent view sidebar: render alignment and rows_by_lnum lockstep, the
-- modifiable-restore guard, embed's ack/promote hand-off, the spawning
-- placeholder lifecycle, keymaps, and the PersistenceSavePre sweep.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local check = H.check

vim.system = function() end
vim.fn.executable = function() return 0 end

local S = H.stub_sidekick()
local ai = S.ai
local ev = require('agent_events')
local av = require('agentview')

-- === scaffolding ========================================================
local function settle() vim.wait(80, function() return false end) end
local function win_where(pred)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if pred(w) then return w end
  end
end
local function main_win() return win_where(function(w) return vim.w[w].agentview_main end) end
local function side_win()
  return win_where(function(w)
    return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agentview'
  end)
end
local function main_buf() return vim.api.nvim_win_get_buf(main_win()) end
local function main_line() return (vim.api.nvim_buf_get_lines(main_buf(), 0, 1, false))[1] end
local function side_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(side_win()), 0, -1, false)
end
local function lnum_of(name)
  for i, l in ipairs(side_lines()) do
    if l:match(vim.pesc(name) .. '%s*$') then return i end
  end
end
-- rows() is only read at render time, and renders are event-driven.
local function refresh()
  vim.api.nvim_exec_autocmds('WinEnter', {})
  settle()
end
-- nvim_win_set_cursor does not fire CursorMoved under -l: dispatch it by hand.
local function move_to(lnum)
  vim.api.nvim_set_current_win(side_win())
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', {})
  settle()
end
-- Park the sidebar cursor without previewing (sidebar is not the current window).
local function park_cursor(lnum)
  vim.api.nvim_set_current_win(main_win())
  settle()
  vim.api.nvim_win_set_cursor(side_win(), { lnum, 0 })
end
local function attach(name)
  vim.api.nvim_exec_autocmds('User', { pattern = 'SidekickCliAttach', data = { id = name } })
  settle()
end
local function detach()
  vim.api.nvim_exec_autocmds('User', { pattern = 'SidekickCliDetach', data = {} })
  settle()
end

-- === render: alignment across every row kind ============================
S.add('claude'); S.add('cursor'); S.add('opencode'); S.add('pi')
ev.sessions = {
  claude = { unread = true, attention = 'needs-permission', running = true },  -- urgent  !
  cursor = { unread = true, attention = 'turn-complete' },                     -- unread  ●
  opencode = { running = true },                                               -- running »
  pi = {},                                                                     -- idle    ○
}
ai._labels = { claude = 'a-very-long-label-that-overruns-thirty-columns', cursor = 'リファクタ' }
ai._dynamic = { spawner = 'registered' }
ai.active = 'cursor'
av.open(); settle()

local lines = side_lines()
check('one row per running session plus the spawning row', #lines == 5, vim.inspect(lines))
local aligned, glyphs = true, {}
for _, l in ipairs(lines) do
  glyphs[#glyphs + 1] = vim.fn.strcharpart(l, 1, 1)
  -- The glyph is real text at a fixed column, never right-aligned virt text:
  -- an uncapped label can only overrun rightward, never cover the signal.
  if vim.fn.strdisplaywidth(vim.fn.strcharpart(l, 0, 2)) ~= 2 then aligned = false end
end
check('the glyph column ends at display cell 2 on every row', aligned, vim.inspect(lines))
check('one glyph per status kind, spawning last',
  table.concat(glyphs) == '!●»○…', table.concat(glyphs))
check('an overlong label does not shift the glyph column',
  lines[1]:find('a%-very%-long%-label') ~= nil, lines[1])
check('a CJK label renders without breaking its row',
  lines[2]:find('リファクタ', 1, true) ~= nil, lines[2])

-- Digits are assigned to running rows only, so sidebar N always means <M-N>.
local digits = {}
for i, l in ipairs(lines) do digits[i] = vim.fn.strcharpart(l, 3, 1) end
check('running rows carry digits in name-sorted order',
  table.concat(digits, '') == '1234 ', ('%q'):format(table.concat(digits, '')))
check('a spawning row never holds a number', digits[5] == ' ')

-- rows_by_lnum lockstep: the digit keymaps and <CR> both index by cursor line,
-- so the map must name exactly the session drawn on that line.
local names = { 'claude', 'cursor', 'opencode', 'pi', 'spawner' }
local lockstep = true
for i, n in ipairs(names) do
  if lnum_of(n) ~= i then lockstep = false end
end
check('rows_by_lnum tracks the rendered line order', lockstep, vim.inspect(side_lines()))

-- Highlight segmentation: a labelled spawning row keeps its name dimmed.
local ns = vim.api.nvim_get_namespaces()['agentview']
local sb = vim.api.nvim_win_get_buf(side_win())
local function groups_on(lnum)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(sb, ns,
      { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })) do
    out[#out + 1] = m[4].hl_group
  end
  return out
end
check('a labelled row splits into label + demoted name',
  vim.tbl_contains(groups_on(1), 'AgentviewLabel')
  and vim.tbl_contains(groups_on(1), 'AgentviewName'), vim.inspect(groups_on(1)))
check('the urgent glyph carries AgentviewUrgent',
  vim.tbl_contains(groups_on(1), 'AgentviewUrgent'), vim.inspect(groups_on(1)))
check('the active row is marked', lines[2]:find('▸', 1, true) ~= nil, lines[2])
ai._labels.spawner = 'forked'
refresh()
check('a labelled spawning row dims the name, never AgentviewName',
  vim.tbl_contains(groups_on(5), 'AgentviewSpawning')
  and not vim.tbl_contains(groups_on(5), 'AgentviewName'), vim.inspect(groups_on(5)))
ai._labels.spawner = nil

-- Degrade path: no registry loaded at all -> a glyph-less list, not an error.
local saved = package.loaded['agent_events']
package.loaded['agent_events'] = nil
refresh()
check('renders without agent_events (Phase-1 degrade)',
  side_lines()[1]:find('claude') ~= nil, vim.inspect(side_lines()[1]))
package.loaded['agent_events'] = saved

-- === modifiable is restored when nvim refuses the row text ==============
local notes = {}
local real_notify = vim.notify
vim.notify = function(m) notes[#notes + 1] = m end
local kept = side_lines()[1]
ai._labels.claude = 'bad\nlabel'
refresh()
vim.notify = real_notify
check('a control-char label leaves the sidebar non-modifiable',
  vim.bo[sb].modifiable == false)
check('the failure is reported, not swallowed',
  (notes[#notes] or ''):find('render failed') ~= nil, notes[#notes])
check('the buffer keeps the previous render', side_lines()[1] == kept, side_lines()[1])
ai._labels.claude = 'refactor'
refresh()
check('the next render recovers',
  side_lines()[1]:find('refactor') ~= nil and vim.bo[sb].modifiable == false, side_lines()[1])
ai._labels = {}

-- === embed's ack / promote hand-off =====================================
-- Every swap here is an in-place nvim_win_set_buf, so neither WinLeave nor
-- WinEnter fires: embed() is the only place that can hand the outgoing
-- session's deferred ring over and ack the incoming one.
ai._dynamic = {}
refresh()
vim.api.nvim_set_current_win(main_win())
ev.sessions = {
  claude = { deferred = true, attention = 'turn-complete' },
  pi = { unread = true, attention = 'turn-complete' },
}
H.stamp('claude', main_win())
av.select('pi'); settle()
check('embed promotes the outgoing session deferral',
  ev.sessions.claude.unread == true and ev.sessions.claude.deferred == nil,
  vim.inspect(ev.sessions.claude))
check('embed acks the incoming ring', ev.status('pi') == 'idle', ev.status('pi'))
check('embed re-stamps the main pane',
  (vim.w[main_win()].sidekick_cli or {}).name == 'pi')

-- A sidebar-side preview leaves main_win non-current: looking at a row is not
-- reading it, so nothing is acked.
ev.sessions.claude = { unread = true, attention = 'turn-complete' }
move_to(lnum_of('claude'))
check('a j/k preview acks nothing', ev.status('claude') == 'unread', ev.status('claude'))
check('the preview still swaps the buffer', main_buf() == S.buf('claude'))
check('previewing does not commit the active session', ai.active == 'pi', tostring(ai.active))

-- === keymaps ============================================================
local lhs = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(sb, 'n')) do lhs[m.lhs] = true end
check('<M-u> dismisses a stuck ring', lhs['<M-u>'] == true)
check('q closes the view', lhs.q == true)
check('<Esc> is deliberately NOT a close key', lhs['<Esc>'] == nil)
check('<CR> opens the row under the cursor', lhs['<CR>'] == true)
check('digits 1-9 are bound', lhs['1'] and lhs['9'])

-- === spawning placeholder lifecycle =====================================
av.close(); settle()
S.reset(); S.add('alpha')
ai.active = 'alpha'; ai._dynamic = { beta = 'registered' }
ev.sessions = {}
av.open(); settle()
check('open embeds the active session', main_buf() == S.buf('alpha'), main_buf())

move_to(lnum_of('beta'))
check('previewing a spawning row shows its own placeholder',
  main_line() == 'beta is starting…', main_line())
local ph = main_buf()
check('the placeholder is an unlisted nofile scratch',
  vim.api.nvim_buf_get_name(ph):match('agentview://starting') ~= nil
  and vim.bo[ph].buftype == 'nofile' and vim.bo[ph].buflisted == false
  and vim.bo[ph].modifiable == false and vim.bo[ph].bufhidden == 'hide',
  ('%s/%s/%s'):format(vim.bo[ph].buftype, tostring(vim.bo[ph].buflisted), vim.bo[ph].bufhidden))
check('the placeholder clears stale session stamps',
  vim.w[main_win()].sidekick_cli == nil and vim.w[main_win()].sidekick_session_id == nil)

-- Attach re-embeds via the placeholder tracker (`pending` was never set here).
S.add('beta'); ai._dynamic = {}
attach('beta')
check('attach replaces the placeholder it named', main_buf() == S.buf('beta'), main_line())

-- Attach re-embeds via the cursor row, with no placeholder up.
ai.active = 'alpha'
av.close(); settle()
S.reset(); S.add('alpha'); ai._dynamic = { gamma = 'registered' }
av.open(); settle()
park_cursor(lnum_of('gamma'))
check('parking the cursor does not preview', main_buf() == S.buf('alpha'), main_line())
S.add('gamma'); ai._dynamic = {}
attach('gamma')
check('attach re-embeds the session the cursor names', main_buf() == S.buf('gamma'), main_line())

-- Placeholder up but the cursor has moved off it.
ai._dynamic = { delta = 'registered' }; refresh()
move_to(lnum_of('delta'))
park_cursor(lnum_of('alpha'))
check('the placeholder survives the cursor moving away',
  main_line() == 'delta is starting…', main_line())
S.add('delta'); ai._dynamic = {}
attach('delta')
check('attach clears a placeholder the cursor no longer names',
  main_buf() == S.buf('delta'), main_line())

-- sync() must not swap an unrelated terminal under a spawning row.
ai.active = 'alpha'
ai._dynamic = { eps = 'registered' }; refresh()
move_to(lnum_of('eps'))
detach()
check('a detach sweep respects the spawning cursor row',
  main_line() == 'eps is starting…', main_line())
S.add('eps')
detach()
check('...but embeds once that row has actually started',
  main_buf() == S.buf('eps'), main_line())

ai._dynamic = {}; ai.active = 'alpha'; refresh()
move_to(lnum_of('alpha'))
detach()
check('an ordinary sync re-embeds the active session', main_buf() == S.buf('alpha'), main_line())

S.reset(); ai.active = nil
detach()
check('nothing embeddable falls to the empty state',
  main_line():match('^no agent embedded') ~= nil, main_line())

-- === PersistenceSavePre sweep ===========================================
-- The synthetic named-nofile buffers cannot be session-serialized.
vim.api.nvim_exec_autocmds('User', { pattern = 'PersistenceSavePre' }); settle()
check('the sweep deletes the sidebar buffer', vim.fn.bufnr('agentview://agents') == -1)
check('the sweep deletes the starting scratch', vim.fn.bufnr('agentview://starting') == -1)
check('the sweep deletes the empty scratch', vim.fn.bufnr('agentview://empty') == -1)
check('the sweep leaves no view tab behind', not vim.tbl_contains(
  vim.tbl_map(function(t) return vim.t[t].agentview end, vim.api.nvim_list_tabpages()), true))

S.add('alpha'); ai.active = 'alpha'
av.open(); settle()
check('the view reopens after the sweep, scratch machinery rebuilt',
  vim.fn.bufnr('agentview://agents') ~= -1 and main_buf() == S.buf('alpha'), main_line())

H.done('view')
