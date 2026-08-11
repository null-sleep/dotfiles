-- Shared harness for the agent-view suites: assert counter, spies, and the
-- sidekick/ai stubs every suite would otherwise reinvent.
local H = {}

-- This file's own path is the only cwd-independent anchor we have: suites are
-- launched by run.sh from anywhere, and `-l` sets no rtp of its own.
H.dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
H.config = vim.fn.fnamemodify(H.dir, ':h:h')
H.lua = H.config .. '/lua'
vim.opt.rtp:prepend(H.config)

-- === assertions =========================================================
local oks, fails = 0, {}

function H.check(name, cond, extra)
  if cond then
    oks = oks + 1
  else
    fails[#fails + 1] = name .. (extra ~= nil and (' :: ' .. tostring(extra)) or '')
  end
end

-- Every suite ends here: one summary line run.sh can parse, exit code is the verdict.
function H.done(suite)
  io.write(('%-8s %d passed, %d failed\n'):format(suite, oks, #fails))
  for _, f in ipairs(fails) do io.write('    FAIL ' .. f .. '\n') end
  io.flush()
  os.exit(#fails == 0 and 0 or 1)
end

-- === spies ==============================================================

-- Replace vim.system with a recorder. `calls` holds argv tables; set
-- `spy.throws` to make it error (the notifier-throws path).
function H.spy_system()
  local spy = { calls = {}, throws = false, real = vim.system }
  vim.system = function(argv)
    if spy.throws then error('spy: notifier exploded') end
    spy.calls[#spy.calls + 1] = argv
    return { wait = function() return { code = 0 } end }
  end
  function spy.take()  -- count since the last take, then reset
    local n = #spy.calls
    spy.calls = {}
    return n
  end
  return spy
end

-- Pretend only the named binaries exist. `have` is live-editable by the caller.
function H.stub_executable(have)
  vim.fn.executable = function(n) return have[n] or 0 end
  return have
end

-- Collect `User AgentSessionEvent` payloads.
function H.event_log()
  local log = {}
  vim.api.nvim_create_autocmd('User', {
    pattern = 'AgentSessionEvent',
    callback = function(a) log[#log + 1] = a.data end,
  })
  function log.flush()
    local out = {}
    for i, e in ipairs(log) do out[i] = e; log[i] = nil end
    return out
  end
  return log
end

-- === driving agent_events ===============================================

-- One hook event, through the real RPC entry point (tmpfile in, '' out).
function H.emit(ev, session, category, message)
  local f = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode({
    session = session, category = category,
    raw = message ~= nil and { message = message } or vim.empty_dict(),
  }) }, f)
  local rv = ev.handle(f)
  vim.fn.delete(f)
  return rv
end

function H.focus(on)
  vim.api.nvim_exec_autocmds(on and 'FocusGained' or 'FocusLost', {})
end

-- Stamp the current window as `name`'s CLI pane — what sidekick does, and the
-- only thing looking_at()/the ack autocmds read.
function H.stamp(name, win)
  vim.w[win or vim.api.nvim_get_current_win()].sidekick_cli = name and { name = name } or nil
end

-- Real terminal-mode is unreachable headless; the FocusGained ack only asks
-- nvim_get_mode(), so stub it for the duration of one call.
function H.with_mode(mode, fn)
  local real = vim.api.nvim_get_mode
  vim.api.nvim_get_mode = function() return { mode = mode, blocking = false } end
  local ok, err = pcall(fn)
  vim.api.nvim_get_mode = real
  if not ok then error(err) end
end

-- === module stubs =======================================================

-- A fake sidekick registry + ai module, enough for agentview to run headless.
-- Returns a controller: :add/:del name sessions, :spawn/:unspawn spawning rows.
function H.stub_sidekick()
  local S = { sessions = {}, ai = nil }

  function S.add(name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'TERMINAL ' .. name })
    local tool = { name = name }
    local term = { buf = buf, id = name, tool = tool, win = nil }
    term.is_open = function(self) return self.win ~= nil end
    term.hide = function(self) self.win = nil end
    S.sessions[#S.sessions + 1] = { tool = tool, terminal = term }
    return term
  end

  function S.reset() S.sessions = {} end

  function S.buf(name)
    for _, s in ipairs(S.sessions) do
      if s.tool.name == name then return s.terminal.buf end
    end
  end

  package.loaded['utils'] = { confirm = function() end }
  package.loaded['stickybuf'] = { unpin = function() end, pin = function() end }
  package.loaded['sidekick.cli'] = { show = function() end, toggle = function() end, hide = function() end }
  package.loaded['sidekick.config'] = { cli = { tools = {}, win = { split = {} } } }
  package.loaded['sidekick.cli.state'] = {
    get = function(o)
      o = o or {}
      local r = {}
      for _, s in ipairs(S.sessions) do
        if not o.name or o.name == s.tool.name then r[#r + 1] = s end
      end
      return r
    end,
  }
  package.loaded['sidekick.cli.terminal'] = {
    sessions = function()
      local r = {}
      for _, s in ipairs(S.sessions) do r[#r + 1] = s.terminal end
      return r
    end,
    get = function(id)
      for _, s in ipairs(S.sessions) do
        if s.terminal.id == id then return s.terminal end
      end
    end,
  }

  local ai = { active = nil, _dynamic = {}, _labels = {} }
  function ai._set_active(n) ai.active = n end
  function ai.display(n) return ai._labels[n] or n end
  function ai.cycle() end
  function ai.rename() end
  function ai.kill() end
  function ai.new_session() end
  package.loaded['ai'] = ai
  S.ai = ai
  return S
end

-- === source extraction ==================================================

-- Load a file-local function (fit, applescript_str, unread_candidates) out of
-- a module's source: several of these are deliberately not exported, and
-- copying them into the test would only assert the copy. `preamble` supplies
-- the upvalues the excerpt needs. Hard-asserts, so a refactor that moves the
-- function fails the suite loudly instead of silently testing nothing.
function H.extract(file, pattern, ret, preamble)
  local src = table.concat(vim.fn.readfile(H.lua .. '/' .. file), '\n')
  local body = src:match(pattern)
  assert(body, ('helpers.extract: %s no longer matches %s'):format(file, pattern))
  local chunk = assert(load((preamble or '') .. '\n' .. body .. '\nreturn ' .. ret))
  return chunk
end

return H
