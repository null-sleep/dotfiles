-- Attention registry for agent CLI sessions (the cmux "two signals" model:
-- activity + unread attention). Claude-hook subprocesses RPC in via
-- `nvim --server $NVIM --remote-expr "v:lua.require('agent_events').handle(...)"`
-- (claude/.claude/hooks/sidekick-notify.sh; transport designed in
-- plans/sidekick-agent-event-pipeline.md). Purely event-driven — no timers,
-- no polling, no UI knowledge: consumers (agentview sidebar, statusline
-- badge, <leader>aj) subscribe to `User AgentSessionEvent`. Loaded from
-- init.lua BEFORE ai.lua so the focus/ack autocmds exist before the
-- pre-warmed claude can emit anything.
local M = {}

-- name -> { unread, attention, deferred, running, notified,
--           last = { category, at, seq, raw } }
--   unread:    the ring; cleared only by ack (turn-complete, or any tier when
--              forced) or real interaction (prompt-submit / session-end)
--   attention: 'needs-permission'|'needs-input'|'turn-complete'|nil
--   deferred:  a turn-complete that landed while you were looking at that
--              pane — held back, not dropped; promoted to unread when you
--              leave (WinLeave/FocusLost), cleared by ack or prompt-submit
--   running:   between prompt-submit and the turn's end
--   notified:  a desktop popup already fired for the current unanswered
--              state — one per blocked episode, cleared when you engage
M.sessions = {}

local augroup = vim.api.nvim_create_augroup('UserAgentEvents', { clear = true })

-- OS-level focus, for the focused-pane deferral below (cmux's rule, minus its
-- bug: an event for the pane you're looking at is held, not discarded). The
-- FocusGained/FocusLost pair lives further down, beside the ack/promote
-- helpers they also drive.
local focused = true

-- Is `name` the session in the currently-focused window? Resolved through
-- the sidekick window stamp — which the agent view re-stamps onto its main
-- pane, so suppression and ack work identically there.
local function looking_at(name)
  local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
  return tool ~= nil and tool.name == name
end

local function fire(session, kind, category)
  local s = M.sessions[session] or {}
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'AgentSessionEvent',
    data = {
      session = session, kind = kind, category = category,
      unread = s.unread or false, running = s.running or false,
    },
  })
end

-- Transition table. Hooks arrive in temporal order; last-writer-wins.
-- needs-permission keeps running=true — the turn is blocked, not over.
-- turn-complete is the only category subject to focused-pane deferral:
-- urgent events always ring (a block is a block wherever you're looking),
-- and an urgent supersedes a pending deferral.
-- `notified` (the desktop-popup episode flag) is cleared by exactly the
-- categories that end a blocked period; the urgent ones deliberately don't,
-- so a tier flip (needs-permission → Claude's ~60s idle needs-input re-ask
-- for the same unanswered block) can't pop a second time.
local TRANSITIONS = {
  ['prompt-submit'] = function(s)
    -- Real interaction — the only thing that clears an urgent ring.
    s.running, s.unread, s.attention, s.deferred = true, false, nil, nil
    s.notified = nil
  end,
  ['needs-permission'] = function(s)
    s.running, s.unread, s.attention, s.deferred = true, true, 'needs-permission', nil
  end,
  ['needs-input'] = function(s)
    s.running, s.unread, s.attention, s.deferred = false, true, 'needs-input', nil
  end,
  ['turn-complete'] = function(s, session)
    s.running, s.attention, s.notified = false, 'turn-complete', nil
    -- Defer, never drop: silent while you sit in that pane, but it rings the
    -- moment you walk away without having interacted (promote() below).
    local suppress = focused and looking_at(session)
    s.unread, s.deferred = not suppress, suppress or nil
  end,
  ['session-end'] = function(s)
    -- /clear, /resume, exit — bookkeeping SidekickCliDetach can't see.
    s.running, s.unread, s.attention, s.deferred = false, false, nil, nil
    s.notified = nil
  end,
}

-- Event counter, the authoritative "most recent" key. `last.at` is os.time(),
-- i.e. whole seconds, and table.sort is unstable — six sessions ringing in the
-- same second sorted differently on every call, which is visible now that the
-- badge names one of them. Monotonic, never reset.
local seq = 0

-- AppleScript string literal: control chars flattened first (a newline would
-- end the `-e` line), then the two characters the literal itself can't carry.
local function applescript_str(s)
  return '"' .. s:gsub('%c', ' '):gsub('[\\"]', '\\%0') .. '"'
end

-- argv, never a shell string: this text is agent-authored, so the only
-- interpreter it must not escape into is the notifier's own arg parsing.
-- terminal-notifier (Brewfile) is preferred — plain argv, no AppleScript
-- quoting, and -ignoreDnD gets through Focus, which the osascript path can't
-- (see README → Neovim). Its one quirk: a value starting with '-' is read as
-- the next flag, so pad it. nil = no notifier on this machine.
local function notify_argv(title, body)
  if vim.fn.executable('terminal-notifier') == 1 then
    if body:sub(1, 1) == '-' then body = ' ' .. body end
    return { 'terminal-notifier', '-title', title, '-message', body, '-ignoreDnD' }
  end
  if vim.fn.executable('osascript') == 0 then return nil end
  return { 'osascript', '-e', ('display notification %s with title %s')
    :format(applescript_str(body), applescript_str(title)) }
end

-- The one case no glyph can reach: an urgent ring raised while nvim doesn't
-- have OS focus (you alt-tabbed away — exactly what the ring exists for).
-- Urgent-only by design: a popup per turn-complete across four agents trains
-- you to dismiss them. Body is the agent's own text when it sent one — the
-- phrase would only restate it ("wants permission: Claude needs your
-- permission to use Bash"), and the title already names the session.
-- macOS-only; silently absent elsewhere. Returns true when a popup fired —
-- that, not the attempt, is what arms the episode flag.
local function notify_desktop(session)
  if focused then return false end
  local phrase, msg = M.summary(session)
  local ai = package.loaded['ai']
  local argv = notify_argv(ai and ai.display(session) or session,
    msg or phrase or 'needs you')
  if not argv then return false end
  vim.system(argv)
  return true
end

-- RPC entry point. Takes only the hook script's mktemp path (session names
-- carry free user text and are never interpolated into the remote expr).
-- Returns '' — --remote-expr serializes the return value, and a table/nil
-- would error on the caller's side. pcall-armored: an error here would
-- surface in the hook's (discarded) stderr and lose the event silently.
function M.handle(tmpfile)
  local ok, event = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(tmpfile), '\n'))
  end)
  if not ok or type(event) ~= 'table'
     or type(event.session) ~= 'string' or type(event.category) ~= 'string' then
    return ''
  end
  local transition = TRANSITIONS[event.category]
  if not transition then return '' end
  local s = M.sessions[event.session] or {}
  M.sessions[event.session] = s
  transition(s, event.session)
  seq = seq + 1
  s.last = { category = event.category, at = os.time(), seq = seq, raw = event.raw }
  fire(event.session, 'event', event.category)
  -- One popup per blocked episode, not per tier: approving a permission
  -- prompt emits no hook, so `attention` would still read 'needs-permission'
  -- and silence every later ask that turn — while the same block's idle
  -- re-ask under a different tier would pop twice. Flag means "already
  -- popped for the current unanswered state"; the transitions above clear it.
  -- After fire() and pcall'd: a notifier throw must never cost the repaint.
  if M.status(event.session) == 'urgent' and not s.notified then
    local ok_n, fired = pcall(notify_desktop, event.session)
    if ok_n and fired then s.notified = true end
  end
  return ''
end

---@return 'urgent'|'unread'|'running'|'idle'|'none'
function M.status(name)
  local s = M.sessions[name]
  if not s then return 'none' end
  if s.unread then
    return s.attention == 'turn-complete' and 'unread' or 'urgent'
  end
  if s.running then return 'running' end
  return 'idle'
end

-- Short phrases for the notify consumers (<leader>aj's landing notify, the
-- desktop notification above).
local PHRASES = {
  ['needs-permission'] = 'wants permission',
  ['needs-input'] = 'needs input',
  ['turn-complete'] = 'finished a turn',
  ['prompt-submit'] = 'working',
  ['session-end'] = 'ended',
}
local MSG_CELLS = 100  -- cells, not chars: 100 CJK chars is a 200-column line

-- Trim to a display-cell budget (statusline's fit(), different budget). Start
-- at `budget` chars: no char is narrower than a cell, so a longer cut can
-- never fit and walking down from a 5000-char message is pure O(n²).
local function fit_cells(s, budget)
  if vim.fn.strdisplaywidth(s) <= budget then return s end
  local n = math.min(vim.fn.strchars(s), budget)
  while n > 1 do
    n = n - 1
    local cut = vim.fn.strcharpart(s, 0, n)
    if vim.fn.strdisplaywidth(cut) <= budget - 1 then return cut .. '…' end
  end
  return '…'
end

-- Phrase + the agent's own notification text for `name`'s last event, both
-- nil-able. `raw` is the hook's stdin verbatim, so `message` is only present
-- for the agents/events that send one — flattened to one truncated line.
function M.summary(name)
  local last = M.sessions[name] and M.sessions[name].last
  if not last then return nil, nil end
  local msg = type(last.raw) == 'table' and last.raw.message or nil
  if type(msg) == 'string' then
    msg = vim.trim((msg:gsub('%s+', ' ')))
    if msg == '' then
      msg = nil
    else
      msg = fit_cells(msg, MSG_CELLS)
    end
  else
    msg = nil
  end
  return PHRASES[last.category], msg
end

-- Unread session names, most recent event first. Ordered by `last.seq`, not
-- `last.at` — see the counter above. Raw list; the consumers (<leader>aj, the
-- badge) share ai.unread_candidates() to filter it identically.
function M.unread_sessions()
  local names = {}
  for name, s in pairs(M.sessions) do
    if s.unread then names[#names + 1] = name end
  end
  table.sort(names, function(a, b)
    return (M.sessions[a].last and M.sessions[a].last.seq or 0)
         > (M.sessions[b].last and M.sessions[b].last.seq or 0)
  end)
  return names
end

-- Acknowledge by looking: clears a turn-complete ring ONLY. Urgent states
-- (needs-permission/input) survive focus and clear on real progress —
-- prompt-submit, or the turn's next event superseding them.
-- `opts.force` (the sidebar's <M-u>) clears any tier: a stuck `!` — prompt
-- answered but the turn errors, an <Esc>'d prompt, a dropped Stop RPC — is
-- otherwise permanent, and traps <leader>aj on itself forever.
-- Also drops a pending deferral: you've now seen the turn, so leaving the
-- window later must not resurrect it as a ring.
-- Returns true when something was actually dismissed, so the force callers can
-- notify instead of declining silently.
function M.ack(name, opts)
  local force = (opts and opts.force) or false
  local s = M.sessions[name]
  if not (s and (s.unread or s.deferred)) then return false end
  if not (force or s.attention == 'turn-complete') then return false end
  s.unread, s.deferred = false, nil
  -- Force clears the state behind the ring too: needs-permission holds
  -- running=true (blocked, not over), so dropping only `unread` would swap a
  -- stuck `!` for a permanent `»`. Dismissing ends the episode, so the next
  -- urgent event is allowed its own popup.
  if force then s.attention, s.running, s.notified = nil, false, nil end
  fire(name, 'ack')
  return true
end

-- Lifecycle GC (kills, detach sweep): a reused name must not inherit the
-- previous process's state.
function M.clear(name)
  if not M.sessions[name] then return end
  M.sessions[name] = nil
  fire(name, 'clear')
end

-- Interaction, not presence, acks: entering the pane, and typing in it.
-- The ModeChanged half covers re-reading a session you never left (no
-- WinEnter fires there) and is the replacement for the old FocusGained ack.
-- The agent view re-stamps its main pane, so both cover the view too;
-- agentview.embed() acks the third path (in-view buffer swaps, no WinEnter).
local function ack_current_win()
  local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
  if tool and tool.name then M.ack(tool.name) end
end
vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  desc = 'Agent events: ack turn-complete rings on entering the pane',
  callback = ack_current_win,
})
vim.api.nvim_create_autocmd('ModeChanged', {
  group = augroup, pattern = '*:t*',
  desc = 'Agent events: ack turn-complete rings on entering terminal mode',
  callback = ack_current_win,
})
-- Refocus is presence, not reading — a blanket FocusGained ack destroyed the
-- ring the same frame you could first see it. One narrow exception: you left
-- nvim parked in terminal mode in that very pane, i.e. sitting in its input
-- box, which is engagement no other signal will ever fire for (no WinEnter, no
-- ModeChanged on return). Normal-mode sitting still keeps the ring.
vim.api.nvim_create_autocmd('FocusGained', {
  group = augroup,
  desc = 'Agent events: track OS focus, ack the pane parked in terminal mode',
  callback = function()
    focused = true
    if vim.api.nvim_get_mode().mode:find('^t') then ack_current_win() end
  end,
})

-- Deferred → unread: you left without interacting, so the turn-complete held
-- back while you sat there rings after all. WinLeave still has the window
-- being left as current; FocusLost sweeps all (nvim itself went away).
-- Exported because the agent view stops showing a session without any window
-- changing (in-place nvim_win_set_buf swaps, tabclose) — those paths promote
-- by hand or the held ring dies with the pane.
local function promote(name)
  local s = M.sessions[name]
  if not (s and s.deferred) then return end
  s.deferred = nil
  if s.unread then return end
  s.unread = true
  fire(name, 'promote')
end
M.promote = promote
vim.api.nvim_create_autocmd('WinLeave', {
  group = augroup,
  desc = 'Agent events: promote deferred rings on leaving the pane',
  callback = function()
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then promote(tool.name) end
  end,
})
vim.api.nvim_create_autocmd('FocusLost', {
  group = augroup, desc = 'Agent events: track OS focus, promote deferred rings',
  callback = function()
    focused = false
    for name in pairs(M.sessions) do promote(name) end
  end,
})

return M
