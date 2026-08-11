-- agent_events state machine: every transition, the defer/promote matrix,
-- force-ack, seq ordering determinism, and urgent-survives-everything.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local ev = require('agent_events')
local check = H.check

vim.system = function() end          -- no notifier ever fires from this suite
vim.fn.executable = function() return 0 end

local function emit(s, c, m) return H.emit(ev, s, c, m) end
local function st(n) return ev.status(n) end
local log = H.event_log()

-- === transitions ========================================================
emit('claude', 'prompt-submit')
check('prompt-submit -> running', st('claude') == 'running', st('claude'))

emit('claude', 'needs-permission')
check('needs-permission -> urgent', st('claude') == 'urgent', st('claude'))
check('needs-permission keeps running (blocked, not over)', ev.sessions.claude.running == true)

ev.ack('claude')
check('plain ack cannot clear urgent', st('claude') == 'urgent', st('claude'))

emit('claude', 'prompt-submit')
check('prompt-submit clears urgent', st('claude') == 'running', st('claude'))

emit('claude', 'turn-complete')      -- no stamped window here: no suppression
check('turn-complete -> unread', st('claude') == 'unread', st('claude'))
check('ack clears turn-complete', ev.ack('claude') == true and st('claude') == 'idle', st('claude'))
check('ack on an already-clean session declines', ev.ack('claude') == false)

emit('other', 'needs-input')
check('needs-input -> urgent', st('other') == 'urgent', st('other'))
check('needs-input stops running', ev.sessions.other.running == false)

emit('other', 'session-end')
check('session-end -> idle, entry kept', st('other') == 'idle' and ev.sessions.other ~= nil)
ev.clear('other')
check('clear -> none', st('other') == 'none')

-- === handle() is inert on garbage ======================================
check('handle returns the empty string', emit('claude', 'turn-complete') == '')
check('missing tmpfile is inert', ev.handle('/nonexistent/agentview-test') == '')
local bad = vim.fn.tempname()
vim.fn.writefile({ 'not json' }, bad)
check('malformed json is inert', ev.handle(bad) == '')
vim.fn.delete(bad)
local before = st('claude')
local unknown = vim.fn.tempname()
vim.fn.writefile({ vim.json.encode({ session = 'claude', category = 'mystery' }) }, unknown)
ev.handle(unknown)
vim.fn.delete(unknown)
check('unknown category is inert', st('claude') == before, st('claude'))
ev.clear('claude')

-- === fire() payload =====================================================
log.flush()
emit('sig', 'needs-permission')
local e = log.flush()[1]
check('fire payload shape', e and e.session == 'sig' and e.kind == 'event'
  and e.category == 'needs-permission' and e.unread == true and e.running == true,
  vim.inspect(e))
ev.clear('sig')

-- === defer / promote matrix ============================================
-- Two stamped "CLI panes" plus a plain code window.
vim.cmd('vsplit')
local wA = vim.api.nvim_get_current_win()
H.stamp('A', wA)
vim.cmd('vsplit')
local wB = vim.api.nvim_get_current_win()
H.stamp('B', wB)
local wCode
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if w ~= wA and w ~= wB then wCode = w end
end

vim.api.nvim_set_current_win(wA)
log.flush()
emit('A', 'turn-complete')
check('turn-complete while looking defers, never rings',
  ev.sessions.A.deferred == true and ev.sessions.A.unread == false and st('A') == 'idle', st('A'))

vim.api.nvim_set_current_win(wCode)  -- WinLeave A
check('leaving the pane promotes the deferral',
  ev.sessions.A.unread == true and ev.sessions.A.deferred == nil and st('A') == 'unread', st('A'))
local kinds = {}
for _, d in ipairs(log.flush()) do kinds[#kinds + 1] = d.kind end
check('promote fires its own event', vim.tbl_contains(kinds, 'promote'), vim.inspect(kinds))

vim.api.nvim_set_current_win(wA)     -- WinEnter A
check('entering the pane acks the ring', st('A') == 'idle', st('A'))

-- Urgent supersedes a pending deferral, and survives the later WinLeave.
emit('A', 'turn-complete')           -- looking at A -> deferred
check('re-deferred', ev.sessions.A.deferred == true)
emit('A', 'needs-permission')
check('urgent supersedes the deferral',
  ev.sessions.A.deferred == nil and st('A') == 'urgent', st('A'))
log.flush()
vim.api.nvim_set_current_win(wCode)
check('WinLeave does not re-promote a superseded deferral', st('A') == 'urgent', st('A'))
check('urgent survives leaving the pane', ev.sessions.A.unread == true)

-- turn-complete while looking clears an existing urgent ring (defers it).
H.stamp('D', wCode)
emit('D', 'needs-permission')        -- current win is D's now, but urgent still rings
check('urgent rings even in the pane you are looking at', st('D') == 'urgent', st('D'))
emit('D', 'turn-complete')
check('turn-complete while looking downgrades urgent to a deferral',
  st('D') == 'idle' and ev.sessions.D.deferred == true, st('D'))

-- prompt-submit clears a deferral.
H.stamp('E', wCode)
emit('E', 'turn-complete')
check('E deferred', ev.sessions.E.deferred == true)
emit('E', 'prompt-submit')
check('prompt-submit clears the deferral',
  ev.sessions.E.deferred == nil and st('E') == 'running', st('E'))

-- FocusLost sweeps every deferral; clear()ed sessions do not come back.
H.stamp('F', wCode)
emit('F', 'turn-complete')
check('F deferred', ev.sessions.F.deferred == true)
ev.clear('F')
H.focus(false)
check('FocusLost promotes D', st('D') == 'unread', st('D'))
check('cleared session is not resurrected by the sweep', st('F') == 'none', st('F'))
H.focus(true)

-- M.promote is exported for agentview's in-place buffer swaps.
check('M.promote is exported', type(ev.promote) == 'function')
emit('G', 'needs-input')
ev.promote('G')
check('promote is a no-op on a non-deferred session', st('G') == 'urgent', st('G'))
check('promote is a no-op on an unknown session', pcall(ev.promote, 'nosuch'))

-- === force-ack ==========================================================
check('force-ack on a stuck urgent returns true', ev.ack('G', { force = true }) == true)
check('force-ack clears the whole state, not just the ring',
  st('G') == 'idle' and ev.sessions.G.attention == nil and ev.sessions.G.running == false, st('G'))
check('force-ack on an unknown session declines, never throws',
  select(2, pcall(ev.ack, 'nosuch', { force = true })) == false)
emit('H', 'prompt-submit')
check('force-ack on a running-but-quiet session declines',
  ev.ack('H', { force = true }) == false, st('H'))
H.stamp('I', wCode)
emit('I', 'turn-complete')           -- deferred, not unread
check('force-ack reaches a deferral too', ev.ack('I', { force = true }) == true)
check('force-acked deferral cannot be promoted later',
  ev.sessions.I.deferred == nil and st('I') == 'idle', st('I'))
H.stamp(nil, wCode)

-- === the narrow FocusGained ack ========================================
-- Refocus is presence, not reading — only the pane parked in terminal mode acks.
vim.api.nvim_set_current_win(wA)
emit('A', 'session-end')
emit('A', 'turn-complete')
ev.sessions.A.unread, ev.sessions.A.deferred = true, nil   -- ring is up and visible
H.with_mode('n', function() H.focus(true) end)
check('FocusGained in normal mode keeps the ring', st('A') == 'unread', st('A'))
H.with_mode('t', function() H.focus(true) end)
check('FocusGained parked in terminal mode acks', st('A') == 'idle', st('A'))

-- === seq ordering =======================================================
-- table.sort is unstable and last.at is whole seconds: six sessions ringing in
-- the same second must still sort identically on every call.
for name in pairs(ev.sessions) do ev.clear(name) end
vim.api.nvim_set_current_win(wCode)
for i = 1, 6 do emit('claude ' .. i, 'needs-input') end
local ats = {}
for i = 1, 6 do ats[i] = ev.sessions['claude ' .. i].last.at end
check('the six rings share one os.time() second', ats[1] == ats[6], vim.inspect(ats))
local first = table.concat(ev.unread_sessions(), ',')
check('unread_sessions is most-recent-first',
  first == 'claude 6,claude 5,claude 4,claude 3,claude 2,claude 1', first)
local stable = true
for _ = 1, 200 do
  if table.concat(ev.unread_sessions(), ',') ~= first then stable = false end
end
check('unread_sessions order is deterministic over 200 sorts', stable)
check('seq is monotonic across sessions',
  ev.sessions['claude 6'].last.seq > ev.sessions['claude 1'].last.seq)

H.done('events')
