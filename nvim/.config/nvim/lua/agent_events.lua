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

-- name -> { unread, attention, running, last = { category, at, raw } }
--   unread:    the ring; cleared only by ack (turn-complete) or real
--              interaction (prompt-submit / session-end)
--   attention: 'needs-permission'|'needs-input'|'turn-complete'|nil
--   running:   between prompt-submit and the turn's end
M.sessions = {}

local augroup = vim.api.nvim_create_augroup('UserAgentEvents', { clear = true })

-- OS-level focus, for the focused-pane suppression below (cmux's rule: an
-- event for the pane you're looking at doesn't ring).
local focused = true
vim.api.nvim_create_autocmd('FocusGained', {
  group = augroup, desc = 'Agent events: track OS focus',
  callback = function()
    focused = true
    -- Also ack here, not just WinEnter: a turn-complete ring raised while
    -- nvim was OS-backgrounded is otherwise stuck unread forever if you're
    -- already sitting in that session's window on return — no WinEnter fires.
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then M.ack(tool.name) end
  end,
})
vim.api.nvim_create_autocmd('FocusLost', {
  group = augroup, desc = 'Agent events: track OS focus',
  callback = function() focused = false end,
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
-- turn-complete is the only category subject to focused-pane suppression:
-- urgent events always ring (a block is a block wherever you're looking).
local TRANSITIONS = {
  ['prompt-submit'] = function(s)
    -- Real interaction — the only thing that clears an urgent ring.
    s.running, s.unread, s.attention = true, false, nil
  end,
  ['needs-permission'] = function(s)
    s.running, s.unread, s.attention = true, true, 'needs-permission'
  end,
  ['needs-input'] = function(s)
    s.running, s.unread, s.attention = false, true, 'needs-input'
  end,
  ['turn-complete'] = function(s, session)
    s.running, s.attention = false, 'turn-complete'
    s.unread = not (focused and looking_at(session))
  end,
  ['session-end'] = function(s)
    -- /clear, /resume, exit — bookkeeping SidekickCliDetach can't see.
    s.running, s.unread, s.attention = false, false, nil
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
function M.ack(name)
  local s = M.sessions[name]
  if not (s and s.unread and s.attention == 'turn-complete') then return end
  s.unread = false
  fire(name, 'ack')
end

-- Lifecycle GC (kills, detach sweep): a reused name must not inherit the
-- previous process's state.
function M.clear(name)
  if not M.sessions[name] then return end
  M.sessions[name] = nil
  fire(name, 'clear')
end

-- The one focus-ack path: entering a window whose stamp names a session
-- with a turn-complete ring acknowledges it (the agent view re-stamps its
-- main pane, so this covers both the solo column and the view).
vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  desc = 'Agent events: focus-ack turn-complete rings',
  callback = function()
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then M.ack(tool.name) end
  end,
})

return M
