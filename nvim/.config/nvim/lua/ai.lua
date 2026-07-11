-- Exported module. Defined ABOVE the packadd pcall so the method stubs below
-- survive the first-launch race (where the plugin is still downloading and the
-- real definitions at the bottom never run). `active` defaults to 'claude' so
-- everything works before any session is entered; `_dynamic` maps names we
-- registered → 'registered' | 'started' (only these are ever removed from
-- cli.tools).
local M = { active = 'claude', _dynamic = {} }

-- Stub the public methods so a keypress during the first-launch packadd race
-- notifies instead of throwing "attempt to call a nil value". The real
-- definitions below overwrite these once sidekick has loaded.
-- Vararg signature (not `()`) so LuaLS doesn't infer a 0-arg type for the
-- routed methods below and flag every `ai.send({...})` call site as passing a
-- redundant parameter. The real definitions further down carry the true types.
local function not_ready(...)
  vim.notify('sidekick.nvim still loading — retry after restart', vim.log.levels.WARN)
end
M.toggle_active, M.new_session, M.switch, M.kill_active, M.focus, M.send =
  not_ready, not_ready, not_ready, not_ready, not_ready, not_ready

-- pcall: on first launch vim.pack is still downloading the plugin in the
-- background, so packadd/require will fail. Silently skip — next restart
-- picks it up once the clone finishes.
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return M end

local utils = require('utils')

-- Set by the pre-warm flow below; captured here so the cleanup step can
-- restore the instance's open_win without walking sidekick's session tables.
local prewarm_term ---@type any?

require('sidekick').setup({
  cli = {
    -- Use telescope for cli.select() (tool list) and cli.prompt() (prompt library)
    -- so the sidekick UI matches the rest of the config.
    picker = 'telescope',
    win = {
      layout = 'right',  -- CLI opens as a right split; switch to 'float' if preferred
      -- global scrolloff=10 pins terminal view to bottom; 0 lets it scroll freely
      wo = { scrolloff = 0 },
      -- In-window CLI keymaps (merged over sidekick's defaults).
      -- <C-\> is intentionally NOT bound here so it falls through to the global
      -- toggleterm mapping, allowing toggleterm floats to be opened from sidekick.
      -- Use <leader>aa to hide sidekick.
      keys = {},
      -- Pre-warm hook: while __sidekick_prewarm is set, swap this instance's
      -- open_win for one that creates a hidden float instead of a visible
      -- split. See the pre-warm block at the bottom of this file.
      config = function(term)
        if _G.__sidekick_prewarm then
          prewarm_term = term
          term.open_win = function(self)
            if self:is_open() or not self.buf then return end
            self.win = vim.api.nvim_open_win(self.buf, false, {
              relative = 'editor', row = 0, col = 0,
              width = 80, height = math.max(20, vim.o.lines),
              style = 'minimal', hide = true, focusable = false,
            })
            vim.w[self.win].sidekick_cli = self.tool
            vim.w[self.win].sidekick_session_id = self.id
            self:wo()
          end
        end
      end,
    },
    -- mux: leave disabled. Enable with backend = 'tmux' or 'zellij' if you want
    -- sessions to persist across nvim restarts.
  },
  nes = {
    -- defaults are good: enabled = true, debounce = 100, diff.inline = 'words'
  },
})

-- Promote the sidekick CLI to a full-height edge column on every show.
-- Without this, opening sidekick while the bottom panel (or any non-editor
-- window) has focus splits *that* window — the CLI ends up as a short column
-- inside the panel row instead of spanning the editor's full height. `wincmd
-- L` mirrors nvim-tree's reposition trick and lets Neovim reflow everything
-- else around the new column. SidekickCliAttach fires ONCE per session
-- lifetime — at first attach (emit at session/init.lua:194, behind the
-- already-attached early return at :171); it does NOT fire on re-shows
-- (terminal hide() never detaches). Promoting the first show is all this has
-- ever done; re-shows land full-height on their own (verification step 10).
-- clear = true so a re-source doesn't register duplicate handlers (the
-- config's standard re-source guard, see configs.lua).
local augroup = vim.api.nvim_create_augroup('UserSidekick', { clear = true })

vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'SidekickCliAttach',
  desc = 'Sidekick CLI: promote to full-height edge column',
  callback = function(args)
    -- During pre-warm the CLI lives in a deliberately hidden float. Promoting
    -- it (wincmd L) converts that float into a *visible* split — which the
    -- pre-warm's Guard 2 then mistakes for a user-opened CLI and leaves on
    -- screen instead of hiding. The hidden float needs no promotion, so skip
    -- it while pre-warming.
    if _G.__sidekick_prewarm then return end
    local term = require('sidekick.cli.terminal').get(args.data.id)
    -- First attach completed → let the detach sweep know this spawn is live.
    if term and term.tool and M._dynamic[term.tool.name] == 'registered' then
      M._dynamic[term.tool.name] = 'started'
    end
    -- Silent-surface tripwire: WinEnter active-tracking reads the sidekick_cli
    -- window stamp (terminal.lua:385) — the one internal whose loss fails
    -- SILENTLY (sends mis-route to a stale M.active with no error). A first
    -- attach means a CLI window just opened, so the stamp should be present;
    -- if it isn't, warn loud once per nvim run.
    if not _G.__sidekick_stamp_ok and term and term.win
       and vim.api.nvim_win_is_valid(term.win)
       and vim.w[term.win].sidekick_cli == nil then
      vim.notify('sidekick: CLI window stamp (sidekick_cli) missing — active-session tracking is broken, sends may mis-route',
        vim.log.levels.ERROR)
      _G.__sidekick_stamp_ok = true   -- fire once per nvim run, not per attach
    end
    local layout = require('sidekick.config').cli.win.layout
    local side = layout == 'right' and 'right' or layout == 'left' and 'left' or nil
    if not side then return end -- float / top / bottom layouts don't need promoting
    if term then utils.promote_to_full_height(term.win, side) end
  end,
})

-- Part b: track the active session on WinEnter. Sidekick stamps CLI windows at
-- open (terminal.lua:385); the pre-warm float is focusable=false and never
-- entered, so no pre-warm guard is needed. This is the ONLY reliable
-- active-session signal (SidekickCliAttach fires once per lifetime, not on
-- switches — see the promote handler above).
vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  desc = 'Sidekick: track active CLI session',
  callback = function()
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then M.active = tool.name end
  end,
})

-- Part d: the detach sweep. The SidekickCliDetach event is emitted
-- post-removal via vim.schedule (session/init.lua:163), so State.get reads
-- post-detach state here.
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'SidekickCliDetach',
  desc = 'Sidekick: GC dynamic tool names, reset active session',
  callback = function()
    local State = require('sidekick.cli.state')
    -- Sweep names with no running session. 'started' names GC once their
    -- session is gone. A 'registered' name normally stays (its first attach
    -- may be in flight — a few scheduled hops), BUT a spawn that never
    -- attaches (missing binary, jobstart failure) would otherwise leak the
    -- name forever and M.active would keep auto-respawning a failing terminal
    -- under it. So also forget a 'registered' name once it has neither a
    -- started session nor a terminal — the terminal check preserves genuinely
    -- in-flight spawns.
    for name, phase in pairs(M._dynamic) do
      if #State.get({ name = name, started = true }) == 0
         and (phase == 'started' or #State.get({ name = name, terminal = true }) == 0) then
        M._forget(name)
      end
    end
    -- Active session died (self-exit, <C-d>, <leader>ad) → fall back to #1.
    if M.active ~= 'claude' and #State.get({ name = M.active, started = true }) == 0 then
      M.active = 'claude'
    end
  end,
})

-- Terminal-nav keymaps for sidekick CLI buffers. terminal.lua's generic
-- TermOpen autocmd skips sidekick_terminal so sidekick can own its own
-- keymaps; this restores the shared nav set WITHOUT <Esc> (esc = false —
-- the CLI needs Esc forwarded to Claude for interrupts).
vim.api.nvim_create_autocmd('FileType', {
  group = augroup,
  pattern = 'sidekick_terminal',
  desc = 'Sidekick CLI: keymaps for terminal and normal mode',
  callback = function(args)
    utils.term_nav_keymaps(args.buf, { esc = false })

    -- <C-\> opens the toggleterm float from the sidekick CLI. Needed because
    -- toggleterm's terminal-mode toggle is buffer-local to its own terminals, so
    -- in this (sidekick) terminal there's otherwise no <C-\> mapping at all. The
    -- normal-mode global toggleterm mapping already handles <count><C-\>; from
    -- terminal mode a count isn't possible (digits go to Claude), so it opens the
    -- default float. v:count1 still lets a normal-mode count flow through here.
    vim.keymap.set({ 't', 'n' }, [[<C-\>]], function()
      vim.cmd(vim.v.count1 .. 'ToggleTerm')
    end, { buffer = args.buf, desc = 'Open toggleterm float' })

    -- In normal mode, forward keys to Claude's job channel so its TUI scrolls.
    local function send_to_claude(seq)
      return function()
        local session_id = vim.w[vim.api.nvim_get_current_win()].sidekick_session_id
        local Terminal = require('sidekick.cli.terminal')
        local term = session_id and Terminal.get(session_id)
        if term and term.job then
          vim.api.nvim_chan_send(term.job, seq)
        end
      end
    end
    vim.keymap.set('n', '<C-u>', send_to_claude('\27[5~'), { buffer = args.buf })
    vim.keymap.set('n', '<C-d>', send_to_claude('\27[6~'), { buffer = args.buf })
  end,
})

-- Pre-warm strategy: the first <leader>aa freezes the editor for ~1–2s while
-- claude boots, so we pay that cost during nvim startup instead. Sidekick's
-- start() always opens a visible window, but `nvim_open_win` accepts
-- `hide = true` for floats (Neovim 0.10+) and `jobstart{ term = true }` only
-- needs the buffer to be shown in *some* current window — visibility doesn't
-- matter. So we use sidekick's per-instance `win.config` callback (above) to
-- swap in a hidden-float open_win, run cli.show, then close the hidden float
-- (cli.hide leaves the job alive) and restore the default — no flicker, no
-- cold-start freeze.
--
-- The global flag bridges cli.show's two `vim.schedule_wrap` hops so the
-- override is still in place when win.config eventually runs. If claude is
-- missing the pcall + nil guards make this a no-op rather than a wedged
-- editor. Gated on a `.git` ancestor (using vim.fs.root so it works for git
-- worktrees, where .git is a file rather than a directory) so we don't spawn
-- claude when nvim opens a single file outside a project.
local PREWARM_DELAY = 3000 -- ms; see PersistenceLoadPre/Post below for why not a fixed defer_fn

-- Guard 1 + the show/hide dance, factored out so the timer and the
-- persistence reschedule below share it.
local function do_prewarm()
  -- Headless skip (the PersistenceLoadPost reschedule path isn't otherwise
  -- has_ui-gated, unlike the initial trigger below): don't spawn claude with
  -- no UI to warm for.
  if not utils.has_ui() then return end
  -- Project skip: only the initial trigger below is `.git`-gated, but the
  -- PersistenceLoadPost reschedule path lands here too -- re-check at fire time
  -- (evaluated against the restored buffers) so we don't spawn claude for a
  -- session/dir outside a project.
  if not vim.fs.root(0, '.git') then return end
  -- Guard 1: a *claude* CLI already exists (user opened it during the wait, or
  -- a restore surfaced one) -> don't double-spawn. Match the claude tool
  -- specifically via sidekick's live terminal registry, NOT the
  -- `sidekick_terminal` filetype -- other tools (codex/aider via <leader>as)
  -- share that filetype and must not suppress the claude pre-warm.
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.tool and t.tool.name == 'claude' and t:buf_valid() then
      return
    end
  end
  local cli = require('sidekick.cli')
  _G.__sidekick_prewarm = true
  pcall(cli.show, { name = 'claude', focus = false })
  vim.defer_fn(function()
    _G.__sidekick_prewarm = nil
    if prewarm_term then
      prewarm_term.open_win = nil
      prewarm_term = nil
    end
    -- Guard 2: if a *visible* claude CLI appeared during the show->hide window
    -- (user hit <leader>aa), skip the hide so we don't yank it away. Match the
    -- claude tool specifically (registry, not filetype) so a visible *other*
    -- tool doesn't suppress our hide. Our own pre-warm float stays hidden
    -- (hide=true; promotion is skipped while pre-warming), so it's excluded.
    for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
      if t.tool and t.tool.name == 'claude' and t:win_valid()
         and not vim.api.nvim_win_get_config(t.win).hide then
        return
      end
    end
    pcall(cli.hide, { name = 'claude' })
  end, 300)
end

-- Re-schedulable one-shot timer so PersistenceLoadPre/Post (below) can push
-- the spawn past a <leader>qs restore. Follows configs.lua's `_G`
-- stop-before-create re-source guard, and additionally closes its own handle
-- once it fires (repeat = 0, one-shot) so it doesn't leak until the next
-- re-source.
local function schedule_prewarm()
  if _G._sidekick_prewarm_timer then
    _G._sidekick_prewarm_timer:stop()
    _G._sidekick_prewarm_timer:close()
  end
  local timer = assert(vim.uv.new_timer())
  _G._sidekick_prewarm_timer = timer
  timer:start(PREWARM_DELAY, 0, vim.schedule_wrap(function()
    -- Identity guard: the uv fire and this callback are a main-loop hop
    -- apart. If <leader>qs lands in that gap, PersistenceLoadPre/Post
    -- (below) close this timer and arm a fresh one — this callback is then
    -- stale, and without the check it would close the *new* timer and run
    -- the pre-warm right at restore-end (the exact collision the reschedule
    -- exists to avoid). Stale → do nothing; the re-armed timer owns the fire.
    if _G._sidekick_prewarm_timer ~= timer then return end
    _G._sidekick_prewarm_timer = nil
    timer:close()
    do_prewarm()
  end))
end

-- persistence.nvim fires these around <leader>qs restore (verified in
-- persistence.nvim source: LoadPre/:source session/LoadPost). Pre: stop the
-- timer so claude doesn't spawn mid-restore, competing with rust-analyzer/
-- LSP/treesitter for the main thread. Post: reschedule so it fires
-- PREWARM_DELAY *after* restore completes instead of racing it.
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'PersistenceLoadPre',
  desc = 'Sidekick pre-warm: pause claude spawn during session restore',
  callback = function()
    if _G._sidekick_prewarm_timer then
      _G._sidekick_prewarm_timer:stop()
      _G._sidekick_prewarm_timer:close()
      _G._sidekick_prewarm_timer = nil
    end
  end,
})
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'PersistenceLoadPost',
  desc = 'Sidekick pre-warm: reschedule claude spawn after restore completes',
  callback = schedule_prewarm,
})

if vim.fs.root(0, '.git') and utils.has_ui() then -- skip pre-warm when headless (see above)
  schedule_prewarm()
end

-- ---------------------------------------------------------------------------
-- Multi-session helpers (part e). These overwrite the race-safe stubs from the
-- top of the file now that sidekick has loaded.
-- ---------------------------------------------------------------------------

-- Warn loud at load if upstream reshapes the claude preset: the clone in
-- create_session silently drops format/resume/continue otherwise (see "clone
-- the preset"), so context sends to sessions 2+ would quietly degrade to raw
-- text with no error. A red ERROR notify surfaces that at startup — but does
-- NOT hard-error: an assert here would throw before this file's `return M`,
-- so require('ai') would fail and take *every* AI keymap down over what is
-- only a formatting regression on extra sessions. Notify-and-continue keeps
-- the keymaps live; the fault stays contained.
if type(require('sidekick.cli.tool').get('claude').config.format) ~= 'function' then
  vim.notify('sidekick: claude preset reshaped — dynamic-session clone will drop format; sends to sessions 2+ may lose context formatting',
    vim.log.levels.ERROR)
end

function M._next_auto_name()
  local tools = require('sidekick.config').cli.tools
  local n = 2
  while tools['claude ' .. n] do n = n + 1 end
  return 'claude ' .. n
end

-- Register a dynamic claude tool (if new) and show it. Re-registering an
-- existing name is a no-op → labels re-attach (see "Labels are reusable").
-- show (not toggle): re-entering the label of a *visible* session must
-- focus it, not hide it. show auto-starts unstarted registered names via
-- the same select-auto path (state.lua:159).
-- Enforce a single visible CLI window. sidekick shows each session in its own
-- window, so <leader>an / <leader>al would otherwise stack a second split next
-- to the one already open. Hide every OTHER shown session, then show the target.
--
-- Hide SYNCHRONOUSLY via the terminal objects (terminal:hide() acts inline and
-- self-guards on is_open) rather than cli.hide: cli.hide defers its work two
-- vim.schedule hops while cli.show defers one, so routing hides through cli.hide
-- would actually run show-BEFORE-hide and leave the invariant riding on
-- sidekick's internal hop ordering. Iterating terminal objects (not filtering
-- by name through cli.hide) also dodges the same-name-in-two-cwds disambiguation
-- picker. hide (not close) keeps each hidden session's job alive — switching
-- back re-shows the same conversation.
local function show_solo(name)
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.tool and t.tool.name ~= name then t:hide() end   -- no-op if not shown
  end
  require('sidekick.cli').show({ name = name, focus = true })
end

local function create_session(name)
  local cfg = require('sidekick.config')
  if not cfg.cli.tools[name] then
    -- Clone claude's resolved preset (cmd + format + resume/continue), not a
    -- bare { cmd = {'claude'} } — see plan "clone the preset".
    cfg.cli.tools[name] = vim.deepcopy(require('sidekick.cli.tool').get('claude').config)
    M._dynamic[name] = 'registered'   -- 'started' once the first attach fires
  end
  M.active = name  -- eager; WinEnter confirms once the window is entered
  show_solo(name)
end

-- Drop a dynamically-registered name from cli.tools. Never touches built-ins
-- (claude/copilot/…) — only names we added via create_session.
function M._forget(name)
  if not M._dynamic[name] then return end
  require('sidekick.config').cli.tools[name] = nil
  M._dynamic[name] = nil
  if M.active == name then M.active = 'claude' end
end

function M.new_session()
  vim.ui.input({ prompt = 'New Claude session (blank = auto): ' }, function(input)
    if input == nil then return end                       -- <Esc> cancels
    local name = input ~= '' and ('claude: ' .. input) or M._next_auto_name()
    if #name >= 16 then
      -- sid's cwd-hash slice is empty at >=16 chars (session/init.lua:107):
      -- reusing this label from another project dir in this nvim run would
      -- silently reattach to this session. Warn, don't reject.
      vim.notify(('Long label (%d chars): reusing "%s" from another project dir will reattach to this session'):format(#name, name),
        vim.log.levels.WARN)
    end
    create_session(name)
  end)
end

function M.toggle_active()
  require('sidekick.cli').toggle({ name = M.active, focus = true })
end

-- <leader>ad target: tear down the active session specifically (avoids the
-- unfiltered cli.close() → disambiguation-picker behaviour with 2+ sessions).
-- Reset M.active synchronously (cli.close is async — two scheduled hops); the
-- detach sweep still GCs the dynamic name after close's detach event fires.
function M.kill_active()
  local name = M.active
  M.active = 'claude'
  require('sidekick.cli').close({ name = name })
end

-- Routing wrappers: every send/focus targets the active session, so a second
-- running session never turns sends into a pick-a-target flow (state.lua:165).
-- Normalize a bare string like cli.send does, so a stray send('{selection}')
-- can't blow up tbl_extend.
function M.send(opts)
  opts = type(opts) == 'string' and { msg = opts } or opts or {}
  require('sidekick.cli').send(vim.tbl_extend('force', opts, { name = M.active }))
end

function M.focus()
  require('sidekick.cli').focus({ name = M.active })
end

-- <leader>al: custom telescope picker over running sidekick sessions.
-- <CR> shows/focuses (making it active); <C-d> tears down the highlighted one.
function M.switch()
  local State          = require('sidekick.cli.state')
  local pickers        = require('telescope.pickers')
  local finders        = require('telescope.finders')
  local conf           = require('telescope.config').values
  local actions        = require('telescope.actions')
  local action_state   = require('telescope.actions.state')

  local function finder()
    return finders.new_table({
      results = State.get({ started = true }),      -- running sessions only
      entry_maker = function(s)
        local name = s.tool.name
        -- cwd in the display: same-named sessions in two cwds are otherwise
        -- indistinguishable (see Known edges).
        local cwd = s.session and vim.fn.fnamemodify(s.session.cwd, ':~') or ''
        return { value = s, display = name .. '  ' .. cwd, ordinal = name .. ' ' .. cwd }
      end,
    })
  end

  pickers.new({}, {
    prompt_title = 'Sidekick sessions',
    finder = finder(),
    sorter = conf.generic_sorter({}),
    -- Compact, previewless picker — it's a short "name  cwd" list, not a file
    -- search (same vertical strategy pickers/theme.lua uses for its short list).
    -- Wide enough that ':~'-shortened cwds aren't truncated on a narrow term.
    layout_strategy = 'vertical',
    layout_config = { width = 0.6, height = 0.4 },
    previewer = false,
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        if entry then
          M.active = entry.value.tool.name  -- eager; WinEnter confirms on focus
          show_solo(entry.value.tool.name)  -- replace the open window, don't stack
        end
      end)
      map({ 'i', 'n' }, '<C-d>', function(pbuf)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local name = entry.value.tool.name
        -- Synchronous teardown: State.detach → terminal:close() removes the
        -- session inline (only the Detach *event* is scheduled), so the
        -- refresh below reads post-kill state. cli.close() would be two
        -- vim.schedule hops too late (state.lua:145,148) and refresh would
        -- show the killed entry.
        --
        -- Reset active + GC the name synchronously here too, not only in the
        -- detach sweep: the sweep is scheduled, and a send landing in the gap
        -- before it runs would re-route to this dead-but-still-registered name
        -- → select({auto=true}) → a *fresh* session respawns under it (the
        -- exact surprise the sweep exists to prevent). _forget is a no-op on
        -- built-ins, so <C-d> on the default `claude` won't unregister it.
        if M.active == name then M.active = 'claude' end
        State.detach(entry.value)
        M._forget(name)
        action_state.get_current_picker(pbuf):refresh(finder(), { reset_prompt = false })
      end)
      return true
    end,
  }):find()
end

return M
