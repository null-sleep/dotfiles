-- Prune stale on-disk state: undo, sessions, shada leftovers, oversized logs.
-- `:Cleanup` runs it interactively; a weekly sweep fires 2min after startup
-- (configs.lua). See GUIDE.md "On-disk state".
--
-- Rules are mtime-based on purpose. "Delete undo whose source file is gone" is
-- unimplementable: nvim encodes the path by replacing / with % without escaping
-- an existing %, so /a/b%c/d and /a/b/c/d share one undo file. Age can't be
-- fooled that way, and collects orphans anyway.

local M = {}

local DAY = 24 * 60 * 60

-- Sessions expire faster than undo: they're a clutter problem (<leader>qS), not
-- a disk one. Dead-branch sessions go sooner still — at 30d the general rule
-- would already have caught them.
local UNDO_AGE        = 90 * DAY
local SESSION_AGE     = 30 * DAY
local DEAD_BRANCH_AGE = 7 * DAY
local SHADA_TMP_AGE   = 1 * DAY
local LOG_MAX_BYTES   = 5 * 1024 * 1024

local function state(name)
  return vim.fs.joinpath(vim.fn.stdpath('state'), name)
end

local function older_than(stat, age)
  return os.time() - stat.mtime.sec > age
end

-- Plain files in `dir`, stat'd; a missing dir is not an error.
local function entries(dir)
  local out = {}
  if not vim.uv.fs_stat(dir) then return out end
  for name, kind in vim.fs.dir(dir) do
    if kind == 'file' then
      local path = vim.fs.joinpath(dir, name)
      local stat = vim.uv.fs_stat(path)
      if stat then out[#out + 1] = { name = name, path = path, stat = stat } end
    end
  end
  return out
end

local function human(bytes)
  if bytes >= 1024 * 1024 then return ('%.1fMB'):format(bytes / 1024 / 1024) end
  if bytes >= 1024 then return ('%.0fKB'):format(bytes / 1024) end
  return ('%dB'):format(bytes)
end

--- Live branches, normalized the way persistence writes them. nil when git
--- can't answer (not a repo, detached HEAD) — callers treat that as "keep".
local function live_branches(dir)
  local res = vim.system(
    { 'git', '-C', dir, 'for-each-ref', '--format=%(refname:short)', 'refs/heads' },
    { text = true }
  ):wait()
  if res.code ~= 0 then return nil end

  local set = {}
  for _, ref in ipairs(vim.split(res.stdout or '', '\n', { plain = true, trimempty = true })) do
    -- persistence/init.lua:17 writes branches through this same gsub, so
    -- `feature/foo` is on disk as `feature%foo`; comparing raw deletes it.
    set[(ref:gsub('[\\/:]+', '%%'))] = true
  end
  return set
end

--- Split `<cwd>%%<branch>.vim`, on the *last* `%%` since a cwd may contain one.
--- Branch is nil when untagged: persistence skips main/master, non-repos have none.
local function decode_session(name)
  local stem = name:gsub('%.vim$', '')
  local sep, from = nil, 1
  while true do
    local at = stem:find('%%%%', from)
    if not at then break end
    sep, from = at, at + 1
  end
  if not sep then return (stem:gsub('%%', '/')), nil end
  return (stem:sub(1, sep - 1):gsub('%%', '/')), stem:sub(sep + 2)
end

local function undo_task()
  -- Read the option rather than rebuilding the default path, so an override
  -- to `undodir` can't silently desync.
  local dir = vim.split(vim.o.undodir, ',', { plain = true })[1]
  dir = vim.fn.expand((dir:gsub('/+$', '')))

  local items = {}
  for _, e in ipairs(entries(dir)) do
    if older_than(e.stat, UNDO_AGE) then
      items[#items + 1] = { path = e.path, bytes = e.stat.size }
    end
  end
  return {
    label = ('Undo history untouched for %dd'):format(UNDO_AGE / DAY),
    action = 'delete',
    items = items,
  }
end

local function session_tasks()
  local dir = state('sessions')  -- persistence's default; session.lua doesn't override it
  local stale, dead, tmp = {}, {}, {}
  local branches = {}  -- cwd -> set of live branches, or false when git couldn't answer
  local utils = require('utils')

  for _, e in ipairs(entries(dir)) do
    if e.name:match('%.vim$') then
      local cwd, branch = decode_session(e.name)
      -- Decoding is ambiguous (a cwd may contain a literal %), so nothing here
      -- deletes on "decoded path doesn't exist". A temp root is the safe
      -- exception: a collision can't fabricate a /private/tmp prefix.
      if cwd and utils.is_tmp_path(cwd) and older_than(e.stat, DEAD_BRANCH_AGE) then
        tmp[#tmp + 1] = { path = e.path, bytes = e.stat.size }
      elseif older_than(e.stat, SESSION_AGE) then
        stale[#stale + 1] = { path = e.path, bytes = e.stat.size }
      elseif branch and older_than(e.stat, DEAD_BRANCH_AGE) and vim.fn.isdirectory(cwd) == 1 then
        if branches[cwd] == nil then branches[cwd] = live_branches(cwd) or false end
        if branches[cwd] and not branches[cwd][branch] then
          dead[#dead + 1] = { path = e.path, bytes = e.stat.size }
        end
      end
    end
  end

  return {
    label = ('Sessions untouched for %dd'):format(SESSION_AGE / DAY),
    action = 'delete',
    items = stale,
  }, {
    label = ('Sessions whose branch is gone (%dd)'):format(DEAD_BRANCH_AGE / DAY),
    action = 'delete',
    items = dead,
  }, {
    label = ('Sessions for temp directories (%dd)'):format(DEAD_BRANCH_AGE / DAY),
    action = 'delete',
    items = tmp,
  }
end

local function shada_task()
  local items = {}
  -- Left behind when nvim is killed mid-write; a live instance's is minutes
  -- old at most, so the age gate keeps us off one still in use.
  for _, e in ipairs(entries(state('shada'))) do
    if e.name:match('^main%.shada%.tmp%.') and older_than(e.stat, SHADA_TMP_AGE) then
      items[#items + 1] = { path = e.path, bytes = e.stat.size }
    end
  end
  return { label = 'Leftover shada temp files', action = 'delete', items = items }
end

local function log_task()
  local items = {}
  for _, e in ipairs(entries(vim.fn.stdpath('state'))) do
    if e.name:match('%.log$') and e.stat.size > LOG_MAX_BYTES then
      items[#items + 1] = { path = e.path, bytes = e.stat.size }
    end
  end
  -- A periodic trim, not a bound. Safe with a client attached: lsp/log.lua
  -- opens 'a+' (O_APPEND), so the next write recomputes its offset.
  return {
    label = ('Logs over %dMB (truncated, not deleted)'):format(LOG_MAX_BYTES / 1024 / 1024),
    action = 'truncate',
    items = items,
  }
end

--- Everything the sweep would act on. Dry-run, confirm preview and the sweep
--- itself all read this one list, so they can't diverge.
function M.plan()
  local stale_sessions, dead_branch_sessions, tmp_sessions = session_tasks()
  return {
    undo_task(),
    stale_sessions,
    dead_branch_sessions,
    tmp_sessions,
    shada_task(),
    log_task(),
  }
end

local function totals(plan)
  local n, bytes = 0, 0
  for _, task in ipairs(plan) do
    for _, item in ipairs(task.items) do
      n, bytes = n + 1, bytes + item.bytes
    end
  end
  return n, bytes
end

local function execute(plan)
  local done, freed, failed = 0, 0, 0
  for _, task in ipairs(plan) do
    for _, item in ipairs(task.items) do
      local ok
      if task.action == 'truncate' then
        local fd = vim.uv.fs_open(item.path, 'w', tonumber('644', 8))
        if fd then
          vim.uv.fs_close(fd)
          ok = true
        end
      else
        -- Another instance may have swept it first — a no-op, not a failure.
        local called, result = pcall(vim.uv.fs_unlink, item.path)
        ok = called and result ~= nil
      end
      if ok then
        done, freed = done + 1, freed + item.bytes
      else
        failed = failed + 1
      end
    end
  end
  return done, freed, failed
end

local function summary(verb, done, freed, failed)
  return ('Cleanup: %s %d file%s, freed %s%s'):format(
    verb, done, done == 1 and '' or 's', human(freed),
    failed > 0 and (' (%d failed)'):format(failed) or '')
end

local function report(plan)
  local lines = {}
  for _, task in ipairs(plan) do
    lines[#lines + 1] = ('%s — %d'):format(task.label, #task.items)
    for _, item in ipairs(task.items) do
      lines[#lines + 1] = ('  %s  (%s)'):format(vim.fs.basename(item.path), human(item.bytes))
    end
    lines[#lines + 1] = ''
  end
  local n, bytes = totals(plan)
  lines[#lines + 1] = ('Total: %d file%s, %s'):format(n, n == 1 and '' or 's', human(bytes))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('botright split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.min(#lines, math.floor(vim.o.lines / 2)))
  vim.keymap.set('n', 'q', '<cmd>close<cr>',
    { buffer = buf, nowait = true, desc = 'Cleanup: Close report' })
end

--- Interactive entry point. The list goes in a split and only a one-line
--- summary through utils.confirm, which sizes its float to the message with no
--- clamp against vim.o.lines (utils.lua:132).
function M.run(dry)
  local plan = M.plan()
  local n, bytes = totals(plan)
  if n == 0 then
    vim.notify('Cleanup: nothing to remove')
    return
  end

  report(plan)
  if dry then return end

  require('utils').confirm(
    ('Remove %d file%s (%s)?'):format(n, n == 1 and '' or 's', human(bytes)),
    function()
      vim.notify(summary('removed', execute(plan)))
    end)
end

--- Weekly unattended sweep, called from configs.lua's deferred startup work.
function M.auto()
  if vim.env.CLAUDE_NVIM == '1' or not require('utils').has_ui() then return end

  -- Stamp idiom from utils.check_nvim_update (utils.lua:192), inlined until a
  -- third call site earns extraction. Written *after* the sweep, unlike there:
  -- an error mid-sweep should retry next launch, not skip a silent week.
  local stamp = vim.fs.joinpath(vim.fn.stdpath('cache'), 'nvim-cleanup')
  local stat = vim.uv.fs_stat(stamp)
  if stat and os.time() - stat.mtime.sec < 7 * DAY then return end

  local plan = M.plan()
  local n = totals(plan)
  local done, freed, failed = execute(plan)
  vim.fn.writefile({}, stamp)

  -- Notify even on a no-op: a quiet week must look different from a broken one.
  vim.notify(n == 0 and 'Cleanup: weekly sweep found nothing to remove'
    or summary('weekly sweep removed', done, freed, failed))
end

vim.api.nvim_create_user_command('Cleanup', function(opts)
  if opts.args ~= '' and opts.args ~= 'dry' then
    vim.notify(('Cleanup: unknown argument %q (expected `dry`)'):format(opts.args),
      vim.log.levels.ERROR)
    return
  end
  M.run(opts.args == 'dry')
end, {
  nargs = '?',
  desc = 'Prune stale on-disk state (undo, sessions, shada temps, logs); `dry` previews only',
})

return M
