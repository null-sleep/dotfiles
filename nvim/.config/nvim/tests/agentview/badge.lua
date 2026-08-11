-- Statusline agent badge, rendered by the real lualine under the real config:
-- candidate sharing with <leader>aj, +N, fit() boundaries, colour agreement,
-- and the view-tab blackout. Needs the full config (lualine + ai + themes),
-- so run.sh drives this one with -c luafile, not -l.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local check = H.check
local ev = require('agent_events')
local ai = require('ai')

vim.system = function() end
vim.fn.executable = function() return 0 end
vim.o.columns = 200                     -- room for the badge before lualine elides

-- ai's running() predicate goes through sidekick's live registry; ALIVE is the
-- only thing standing between this suite and a real agent process.
local ALIVE = {}
require('sidekick.cli.state').get = function(opts)
  opts = opts or {}
  if opts.name then return ALIVE[opts.name] and { { tool = { name = opts.name } } } or {} end
  local l = {}
  for n in pairs(ALIVE) do l[#l + 1] = { tool = { name = n } } end
  table.sort(l, function(a, b) return a.tool.name < b.tool.name end)
  return l
end
require('sidekick.cli').show = function() end
require('sidekick.cli.terminal').sessions = function() return {} end

local function emit(s, c) return H.emit(ev, s, c) end
local function reset()
  for n in pairs(ev.sessions) do ev.clear(n) end
  ai._labels = {}
  H.stamp(nil)
end
local function statusline() return require('lualine').statusline(true) end
local function badge()
  return vim.trim((statusline():gsub('%%#[^#]*#', ''):gsub('%%[<=*]', '')))
end
local function shows(s) return badge():find(s, 1, true) ~= nil end
local function silent() return not shows('●') and not shows('!') end

-- === the badge names exactly what <leader>aj would route to =============
reset()
check('no sessions: the badge is silent', silent(), badge())

ALIVE = { claude = true, cursor = true, opencode = true }
emit('claude', 'turn-complete')
check('a lone unread is named with the ● glyph', shows('● claude'), badge())
emit('cursor', 'turn-complete')
check('a second unread adds +1, naming the most recent',
  shows('● cursor +1'), badge())
emit('opencode', 'needs-permission')     -- urgent, and the most recent
check('the most recent urgent wins the glyph and the name',
  shows('! opencode'), badge())
check('+N counts the rest', shows('+2'), badge())
check('the badge names unread_candidates[1]',
  ai.unread_candidates()[1] == 'opencode', vim.inspect(ai.unread_candidates()))

-- An urgent outranks a *newer* plain unread: triage, not recency.
emit('claude', 'turn-complete')          -- claude is now the most recent event
check('a newer plain unread does not displace an urgent',
  shows('! opencode'), badge())

-- Sitting in the ringing pane: the shared candidate list drops it, so the
-- badge can never name a session the jump then refuses to route to.
H.stamp('opencode')
local cand = ai.unread_candidates()
check('the pane you are sitting in leaves the candidate list',
  not vim.tbl_contains(cand, 'opencode'), vim.inspect(cand))
check('the badge drops it too', not shows('opencode'), badge())
check('the badge falls to the next candidate',
  shows('● ' .. cand[1]) and shows('+1'), badge())
check('and stops claiming urgency', not shows('!'), badge())

-- The only ring is the pane in front of you -> nothing worth interrupting for.
ev.clear('claude'); ev.clear('cursor')
check('sole ring in the current pane: badge silent, jump declines',
  #ai.unread_candidates() == 0 and silent(), badge())
H.stamp(nil)

-- A stopped session rings in the registry but is not routable.
reset()
ALIVE = { opencode = true }
emit('claude', 'needs-input')            -- unread, but not running
emit('opencode', 'turn-complete')
check('a stopped session is excluded from the candidates',
  not vim.tbl_contains(ai.unread_candidates(), 'claude'), vim.inspect(ai.unread_candidates()))
check('a stopped session never reaches the badge', not shows('claude'), badge())

-- Deferred (held, not ringing) stays out of both.
reset()
ALIVE = { claude = true }
H.stamp('claude')
emit('claude', 'turn-complete')          -- looking at it: deferred
check('a deferred turn-complete is silent',
  ev.sessions.claude.deferred == true and silent(), badge())
H.stamp(nil)

-- === jump_unread lands where the badge pointed ==========================
reset()
ALIVE = { claude = true, opencode = true }
emit('claude', 'turn-complete')
emit('opencode', 'needs-permission')
local target = ai.unread_candidates()[1]
local notes = {}
local real_notify = vim.notify
vim.notify = function(m) notes[#notes + 1] = m end
ai.jump_unread()
vim.notify = real_notify
check('jump_unread lands on the badge target',
  target == 'opencode' and (notes[1] or ''):find('opencode', 1, true) ~= nil, notes[1])
check('the landing notify carries the phrase',
  (notes[1] or ''):find('wants permission', 1, true) ~= nil, notes[1])
check('the landing notify is one line', not (notes[1] or ''):find('\n'), notes[1])

reset()
notes = {}
vim.notify = function(m) notes[#notes + 1] = m end
ai.jump_unread()
vim.notify = real_notify
check('jump_unread declines when the badge is silent',
  (notes[1] or ''):find('no unread') ~= nil and silent(), notes[1])

-- === labels, truncation, the view tab ===================================
reset()
ALIVE = { ['claude 2'] = true }
emit('claude 2', 'needs-permission')
ai._labels['claude 2'] = 'auth-refactor-long-label'
check('a long label is trimmed into the badge budget',
  shows('!') and not shows('auth-refactor-long-label') and shows('…'), badge())
ai._labels['claude 2'] = 'short'
check('a short label is shown whole', shows('! short'), badge())
ai._labels = {}
check('with no label the badge falls back to the session name',
  shows('! claude 2'), badge())

vim.cmd('tabnew')
vim.t.agentview = true
check('the badge is blank inside the view tab (the sidebar says it better)',
  silent(), badge())
vim.cmd('tabprevious')
check('and returns outside it', shows('! claude 2'), badge())
vim.cmd('tabnext'); vim.cmd('tabclose')

-- === colour follows the status group ====================================
-- The component stashes its group for the colour fn (one compute per draw);
-- prove the two tiers resolve to different foregrounds.
local function badge_fg()
  local g = statusline():match('%%#([%w_]+)#[^%%]*[●!]')
  if not g then return nil end
  local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
  return hl.fg and ('#%06x'):format(hl.fg) or 'nofg'
end
reset()
ALIVE = { cursor = true }
emit('cursor', 'turn-complete')
local c_unread = badge_fg()
emit('cursor', 'needs-permission')
local c_urgent = badge_fg()
check('unread and urgent draw in different colours',
  c_unread and c_urgent and c_unread ~= c_urgent,
  tostring(c_unread) .. '/' .. tostring(c_urgent))
check('the AgentviewUrgent/Unread groups are themed',
  vim.fn.hlexists('AgentviewUrgent') == 1 and vim.fn.hlexists('AgentviewUnread') == 1)
check('the AgentSessionEvent repaint path does not throw',
  pcall(vim.api.nvim_exec_autocmds, 'User', { pattern = 'AgentSessionEvent', data = {} }))
reset()

-- === fit(): the 12-cell budget ==========================================
-- fit is file-local to statusline.lua on purpose; load it out of the source
-- rather than asserting against a copy.
local fit = H.extract('statusline.lua', '(local BADGE_CELLS.-\nend\n)', 'fit')()
check('under budget is untouched', fit('refactor') == 'refactor', fit('refactor'))
check('exactly 12 cells is untouched', fit('abcdefghijkl') == 'abcdefghijkl', fit('abcdefghijkl'))
check('13 cells trims to 11 + ellipsis', fit('abcdefghijklm') == 'abcdefghijk…', fit('abcdefghijklm'))
check('6 CJK chars are exactly 12 cells, untouched',
  fit('一二三四五六') == '一二三四五六', fit('一二三四五六'))
check('7 CJK chars trim by cells, not chars',
  fit('一二三四五六七') == '一二三四五…', fit('一二三四五六七'))
check('empty in, empty out', fit('') == '')
check('one wide char fits', fit('一') == '一')

local widest = 0
for _, s in ipairs({ '', 'a', 'claude', 'abcdefghijk', 'abcdefghijkl', 'abcdefghijklm',
                     'abcdefghijklmnopqrstuvwxyz', '日本語', '日本語日本語日本',
                     'a日本語b日本語c日本語d', 'émigré-refactoring-branch',
                     '…………………………', string.rep('x', 5000), string.rep('日', 2000) }) do
  widest = math.max(widest, vim.fn.strdisplaywidth(fit(s)))
end
check('no input can push the badge past 12 cells', widest <= 12, widest)

-- Loose threshold: fit() starts at BADGE_CELLS chars instead of #s, so a
-- pathological label is O(budget), not O(n²). Generous so it cannot flake.
local big = string.rep('x', 5000)
fit(big)                                  -- warm
local t0 = vim.uv.hrtime()
fit(big)
local ms = (vim.uv.hrtime() - t0) / 1e6
check('fit() on a 5000-char label stays under 5ms', ms < 5, ('%.3f ms'):format(ms))

H.done('badge')
