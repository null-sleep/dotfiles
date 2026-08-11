-- Desktop-notification gate: one popup per blocked episode, argv shapes for
-- both notifiers, AppleScript escaping, and summary()'s cell truncation.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local ev = require('agent_events')
local check = H.check

local real_exec = vim.fn.executable
local spy = H.spy_system()
local have = H.stub_executable({ ['terminal-notifier'] = 1, osascript = 1 })
local log = H.event_log()
local function emit(s, c, m) return H.emit(ev, s, c, m) end

-- === episode matrix =====================================================
-- The flag means "already popped for the current unanswered state"; only the
-- categories that end a blocked period clear it.
emit('claude', 'needs-permission', 'may I run Bash')      -- focused: never pops
check('focused urgent does not pop', spy.take() == 0)
check('focused urgent leaves the episode unflagged', ev.sessions.claude.notified == nil)
check('focused urgent still rings in-editor', ev.status('claude') == 'urgent', ev.status('claude'))

H.focus(false)
emit('claude', 'needs-permission', 'may I run rm')
check('unfocused urgent pops once', spy.take() == 1)
check('the pop arms the episode flag', ev.sessions.claude.notified == true)
emit('claude', 'needs-permission', 'may I run curl')
check('same tier again is silent', spy.take() == 0)
emit('claude', 'needs-input', 'still waiting')
check('a tier flip on the same block is silent', spy.take() == 0)

for _, ender in ipairs({ 'prompt-submit', 'turn-complete', 'session-end' }) do
  emit('claude', ender)
  check(ender .. ' clears the episode flag', ev.sessions.claude.notified == nil)
  spy.take()
  emit('claude', 'needs-permission', 'again')
  check('urgent after ' .. ender .. ' pops again', spy.take() == 1)
end

emit('zed', 'needs-permission', 'hi')
check('force-ack clears the episode flag',
  spy.take() == 1 and ev.ack('zed', { force = true }) == true and ev.sessions.zed.notified == nil)
emit('zed', 'needs-permission', 'hi again')
check('urgent after a force-ack pops again', spy.take() == 1)

emit('pi', 'turn-complete', 'done')
check('turn-complete never pops (a popup per turn trains you to dismiss)', spy.take() == 0)

-- === argv shapes ========================================================
emit('argv1', 'needs-permission', 'Claude needs your permission to use Bash')
local a = spy.calls[1]
check('terminal-notifier is preferred over osascript', a and a[1] == 'terminal-notifier', vim.inspect(a))
check('argv: -title <session>', a[2] == '-title' and a[3] == 'argv1', vim.inspect(a))
check('argv: -message is the agent text alone (title already names the session)',
  a[4] == '-message' and a[5] == 'Claude needs your permission to use Bash', vim.inspect(a))
check('argv: -ignoreDnD gets through Focus', a[6] == '-ignoreDnD', vim.inspect(a))
spy.take()

emit('argv2', 'needs-permission', '-rf please')
check('a leading-dash body is padded (terminal-notifier reads it as a flag)',
  spy.calls[1][5] == ' -rf please', vim.inspect(spy.calls[1]))
spy.take()

emit('argv3', 'needs-input')
check('no agent message falls back to the phrase', spy.calls[1][5] == 'needs input', vim.inspect(spy.calls[1]))
spy.take()

-- === osascript fallback + escaping =====================================
have['terminal-notifier'] = nil
emit('argv4', 'needs-permission', 'run "rm -rf /" \\ now\nsecond line')
local o = spy.calls[1]
check('falls back to osascript -e', o and o[1] == 'osascript' and o[2] == '-e' and #o == 3, vim.inspect(o))
check('control chars flattened, quote and backslash escaped',
  o[3] == 'display notification "run \\"rm -rf /\\" \\\\ now second line" with title "argv4"', o[3])
spy.take()

have.osascript = nil
emit('argv5', 'needs-permission', 'x')
check('no notifier on this machine: no call, flag stays clear',
  spy.take() == 0 and ev.sessions.argv5.notified == nil)
check('registry still updates without a notifier', ev.status('argv5') == 'urgent', ev.status('argv5'))
have['terminal-notifier'], have.osascript = 1, 1

-- === a throwing notifier must not cost the repaint =====================
spy.throws = true
log.flush()
emit('boomy', 'needs-permission', 'kaboom')
spy.throws = false
local fired = log.flush()
check('fire() is reached when the notifier throws',
  #fired == 1 and fired[1].session == 'boomy' and fired[1].unread == true, vim.inspect(fired))
check('a throw leaves the flag unset so the next event retries',
  ev.sessions.boomy.notified == nil)

-- === summary() / fit_cells ==============================================
check('summary of an unknown session is nil, nil', select('#', ev.summary('ghost')) == 2
  and ev.summary('ghost') == nil)
emit('short', 'needs-permission', '  hello   world  ')
local phrase, m = ev.summary('short')
check('whitespace flattened and trimmed, phrase alongside',
  m == 'hello world' and phrase == 'wants permission', tostring(m))
emit('nomsg', 'turn-complete')
local p2, m2 = ev.summary('nomsg')
check('no message -> phrase only', p2 == 'finished a turn' and m2 == nil, tostring(m2))
ev.sessions.weird = { last = { category = 'needs-input', raw = { message = 42 } } }
check('a non-string message is dropped', select(2, ev.summary('weird')) == nil)

emit('ascii', 'needs-permission', string.rep('a', 200))
check('a 200-char ASCII message trims to exactly 100 cells',
  vim.fn.strdisplaywidth((select(2, ev.summary('ascii')))) == 100,
  vim.fn.strdisplaywidth((select(2, ev.summary('ascii')))))
emit('cjk', 'needs-permission', string.rep('漢', 200))
local _, cjk = ev.summary('cjk')
check('CJK trims by cells, not chars', vim.fn.strdisplaywidth(cjk) <= 100
  and vim.fn.strchars(cjk) == 50, vim.fn.strchars(cjk))
check('a truncated message ends in an ellipsis', cjk:sub(-3) == '…', cjk:sub(-6))
emit('exact', 'needs-permission', string.rep('b', 100))
check('a message exactly at the budget is untouched',
  select(2, ev.summary('exact')) == string.rep('b', 100))

-- === the escaper against a real AppleScript parser ======================
-- `return`, never `display notification`: this must never raise a real popup.
local applescript_str = H.extract('agent_events.lua',
  '(local function applescript_str.-\nend)', 'applescript_str')()
if real_exec('osascript') == 1 then
  local nasty = {
    'run "rm -rf /" now', 'path C:\\Users\\dhruv', 'ends with a backslash \\',
    '" & (do shell script "touch /tmp/PWNED") & "', 'x" with title "evil',
    'café — naïve 日本語 🎉', 'a\tb\rc', '100%s %d %q',
  }
  local bad = {}
  for _, s in ipairs(nasty) do
    local r = spy.real({ 'osascript', '-e', 'return ' .. applescript_str(s) },
      { text = true }):wait()
    local got = (r.stdout or ''):gsub('\n$', '')
    if r.code ~= 0 or got ~= (s:gsub('%c', ' ')) then
      bad[#bad + 1] = ('%q -> code=%d %q'):format(s, r.code, got)
    end
  end
  check('AppleScript round-trips every hostile literal verbatim', #bad == 0, vim.inspect(bad))
else
  check('AppleScript round-trip skipped (no osascript)', true)
end

H.done('notify')
