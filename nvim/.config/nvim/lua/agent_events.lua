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

-- name -> { unread, attention, deferred, running, last = { category, at, raw } }
--   unread:    the ring; cleared only by ack (turn-complete, or any tier when
--              forced) or real interaction (prompt-submit / session-end)
--   attention: 'needs-permission'|'needs-input'|'turn-complete'|nil
--   deferred:  a turn-complete that landed while you were looking at that
--              pane — held back, not dropped; promoted to unread when you
--              leave (WinLeave/FocusLost), cleared by ack or prompt-submit
--   running:   between prompt-submit and the turn's end
M.sessions = {}

local augroup = vim.api.nvim_create_augroup('UserAgentEvents', { clear = true })

-- OS-level focus, for the focused-pane deferral below (cmux's rule, minus its
-- bug: an event for the pane you're looking at is held, not discarded).
local focused = true
-- No ack here: alt-tabbing back is presence, not reading — acking on
-- FocusGained destroyed the ring the same frame you could first see it.
-- Ack now rides real interaction (the ModeChanged/WinEnter handlers below).
vim.api.nvim_create_autocmd('FocusGained', {
  group = augroup, desc = 'Agent events: track OS focus',
  callback = function() focused = true end,
})

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
local TRANSITIONS = {
  ['prompt-submit'] = function(s)
    -- Real interaction — the only thing that clears an urgent ring.
    s.running, s.unread, s.attention, s.deferred = true, false, nil, nil
  end,
  ['needs-permission'] = function(s)
    s.running, s.unread, s.attention, s.deferred = true, true, 'needs-permission', nil
  end,
  ['needs-input'] = function(s)
    s.running, s.unread, s.attention, s.deferred = false, true, 'needs-input', nil
  end,
  ['turn-complete'] = function(s, session)
    s.running, s.attention = false, 'turn-complete'
    -- Defer, never drop: silent while you sit in that pane, but it rings the
    -- moment you walk away without having interacted (promote() below).
    local suppress = focused and looking_at(session)
    s.unread, s.deferred = not suppress, suppress or nil
  end,
  ['session-end'] = function(s)
    -- /clear, /resume, exit — bookkeeping SidekickCliDetach can't see.
    s.running, s.unread, s.attention, s.deferred = false, false, nil, nil
  end,
}

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
  s.last = { category = event.category, at = os.time(), raw = event.raw }
  fire(event.session, 'event', event.category)
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

-- Short phrases for the notify consumers (<leader>aj's landing notify).
local PHRASES = {
  ['needs-permission'] = 'wants permission',
  ['needs-input'] = 'needs input',
  ['turn-complete'] = 'finished a turn',
  ['prompt-submit'] = 'working',
  ['session-end'] = 'ended',
}
local MSG_CHARS = 100

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
    elseif vim.fn.strchars(msg) > MSG_CHARS then
      msg = vim.fn.strcharpart(msg, 0, MSG_CHARS - 1) .. '…'
    end
  else
    msg = nil
  end
  return PHRASES[last.category], msg
end

-- Unread session names, most recent event first (<leader>aj, badge).
function M.unread_sessions()
  local names = {}
  for name, s in pairs(M.sessions) do
    if s.unread then names[#names + 1] = name end
  end
  table.sort(names, function(a, b)
    return (M.sessions[a].last and M.sessions[a].last.at or 0)
         > (M.sessions[b].last and M.sessions[b].last.at or 0)
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
function M.ack(name, opts)
  local s = M.sessions[name]
  if not (s and (s.unread or s.deferred)) then return end
  if not ((opts and opts.force) or s.attention == 'turn-complete') then return end
  s.unread, s.deferred = false, nil
  fire(name, 'ack')
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

-- Deferred → unread: you left without interacting, so the turn-complete held
-- back while you sat there rings after all. WinLeave still has the window
-- being left as current; FocusLost sweeps all (nvim itself went away).
local function promote(name)
  local s = M.sessions[name]
  if not (s and s.deferred) then return end
  s.deferred = nil
  if s.unread then return end
  s.unread = true
  fire(name, 'promote')
end
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
