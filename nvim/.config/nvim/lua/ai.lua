-- The closed agent set: each entry is a static sidekick preset in cli.tools
-- AND the leading token of every session name ('cursor 2', 'claude: foo') —
-- the name carries the agent, the agent picks the binary (create_session).
-- AGENTS[1] is the primary/home base: pre-warmed, teardown fallback (the
-- <leader>an picker ranks independently — see new_session).
local AGENTS = { 'claude', 'cursor', 'opencode', 'pi' }
local PRIMARY = AGENTS[1]
-- Binary per agent, only where it differs from the name. Everything else about
-- an agent is derived from AGENTS, so a fifth entry needs a line here only if
-- its executable is named differently.
local EXE = { cursor = 'cursor-agent' }

-- Name → agent (the name is a session's only identity — no agent field).
-- Strictly anchored: the next char must be ' ' or ':' so
-- 'claude: cursor-migration' parses as claude, never cursor. nil for names
-- outside the invariant — callers must refuse, not default.
local function agent_of(name)
  if not name then return end
  for _, a in ipairs(AGENTS) do
    if name == a or name:find('^' .. vim.pesc(a) .. '[ :]') then return a end
  end
end

-- Exported module. Defined ABOVE the packadd pcall so the method stubs below
-- survive the first-launch race (where the plugin is still downloading and the
-- real definitions at the bottom never run). `active` defaults to the primary
-- agent so everything works before any session is entered; `_dynamic` maps
-- names we registered → 'registered' | 'started' (only these are ever removed
-- from cli.tools). `_labels` maps a session name → its cosmetic display label
-- (see M.rename); like _dynamic, per-nvim-run state, lost on a re-source.
local M = { active = PRIMARY, _dynamic = {}, _labels = {} }

-- Change the active session and remember the one we left, so <C-]> can toggle
-- back to it. Every user-driven switch routes through this.
local function set_active(name)
  if name and name ~= M.active then M._last = M.active end
  M.active = name
end
-- Exported for agentview's show_solo delegate — external switches must keep
-- the _last bookkeeping, so the view routes through this, never M.active=.
M._set_active = set_active

-- Any session running under this tool name? The module's liveness predicate —
-- name-keyed, like all session state here.
local function running(name)
  return name ~= nil
    and #require('sidekick.cli.state').get({ name = name, started = true }) > 0
end

-- Pick the session M.active should fall back to after a teardown, so a summon
-- (<leader>aa / send / focus) reattaches to a surviving instance instead of
-- spawning a fresh one. Prefer the alt-tab target (M._last) so you land back on
-- the session you were just on; else the name-sorted first running session;
-- else the primary agent when nothing is alive (toggle then spawns fresh).
-- `exclude` drops the session being torn down: cli.close is async, so in
-- kill_active the killed session is still started=true when we choose here.
-- Note: the name-sort surfaces the primary 'claude' (possibly an unused
-- pre-warm) ahead of numbered forks when M._last is gone — accepted as sane
-- "home base" behaviour; it still reuses a live instance, never spawns new.
-- Keyed by tool name (not session id), like the rest of this module — a
-- same-name session in another cwd is excluded/picked by name, not disambiguated.
local function fallback_active(exclude)
  if M._last ~= exclude and running(M._last) then return M._last end
  local sessions = require('sidekick.cli.state').get({ started = true })
  table.sort(sessions, function(a, b) return a.tool.name < b.tool.name end)
  for _, s in ipairs(sessions) do
    if s.tool.name ~= exclude then return s.tool.name end
  end
  return PRIMARY
end

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
M.cycle, M.new_auto, M.toggle_last, M.rename = not_ready, not_ready, not_ready, not_ready
M.kill, M.open_index, M.jump_unread = not_ready, not_ready, not_ready

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
    -- Use snacks for cli.select() (tool list) and cli.prompt() (prompt library)
    -- so the sidekick UI matches the rest of the config.
    picker = 'snacks',
    win = {
      layout = 'right',  -- CLI opens as a right split; switch to 'float' if preferred
      -- Zero both, same as filetree.lua/outline.lua's panels (GUIDE.md
      -- "Panels stop at their last entry") — the dead-space fix itself is
      -- the WinScrolled clamp in autocmds.lua.
      wo = { scrolloff = 0, sidescrolloff = 0 },
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
    -- Tag every base agent's job env with its own name: hook subprocesses
    -- inherit it, which is how agent_events attributes an event to a session
    -- (the pipeline's join key). Deep-merged onto the built-in presets by
    -- name (sidekick tool.lua), so cmd/format/resume survive. Dynamic names
    -- get their own value in create_session — this covers the bare spawns
    -- (pre-warm, <leader>aa) that never pass through there.
    tools = (function()
      local env_tools = {}
      for _, a in ipairs(AGENTS) do
        env_tools[a] = { env = {
          SIDEKICK_SESSION = a,
          -- false = unset (sidekick terminal.lua), not omit: nvim's own job env
          -- inherits vim.uv.os_environ(), so if nvim itself was launched from
          -- inside a claude session, CLAUDE_CODE_EXECPATH would otherwise leak
          -- into this job's env. Hook subprocesses use inherited
          -- CLAUDE_CODE_EXECPATH to detect a NESTED claude (e.g. `claude -p`
          -- from a Bash tool) — Claude Code injects it into tool-subprocess
          -- envs but not hook envs (verified empirically 2026-08-10) — a leaked
          -- value here would make every real event look nested and get
          -- wrongly suppressed.
          CLAUDE_CODE_EXECPATH = false,
        } }
      end
      return env_tools
    end)(),
    -- mux: leave disabled. Enable with backend = 'tmux' or 'zellij' if you want
    -- sessions to persist across nvim restarts.
    -- Claude-native @file#L context refs — overrides sidekick's built-in
    -- position/function/class renderers (Config.cli.context is checked before
    -- built-ins, context/init.lua M.fn). See lua/ai_context.lua for why.
    context = require('ai_context').overrides,
  },
  -- NES (Copilot next-edit suggestions) removed — unused. `enabled = false`, not
  -- `vim.g.sidekick_nes = false`: only the literal false here makes config.lua
  -- skip nes.enable(), which otherwise registers 7 autocmds and a per-keystroke
  -- vim.on_key handler for a dead feature. Deleting the block re-enables it
  -- (sidekick's default is `vim.g.sidekick_nes ~= false`).
  nes = { enabled = false },
})

-- Kill the shell-out session backends. State.get() runs EVERY registered
-- backend's sessions() synchronously on the UI thread, and two of them shell
-- out: opencode (`lsof -iTCP -sTCP:LISTEN`, 40ms) and tmux/zellij (a full `ps`
-- scan, +22ms). Neither was asked for — opencode registers its scanner as a
-- *load side-effect* of its tool spec, and Session.setup() registers
-- tmux/zellij on `executable(name)==1` alone, NOT on cli.mux.enabled. So
-- State.get cost 40.8ms and the detach sweep below (9 of them with 3 forked
-- sessions) froze nvim for ~370ms. Now 0.05ms. See GUIDE.md "Sidekick's
-- session backends shell out on every lookup".
-- Still stubbed now that opencode is an agent: it only drops discovery of
-- opencode servers started *outside* nvim. Ours spawn through the terminal
-- backend like every other agent.
--
-- Three constraints, each learned the hard way:
--   * Stub sessions(), don't nil the backend — Session.new asserts it exists.
--     This only disables discovery of *externally started* sessions.
--   * Call Session.setup() first (it's normally lazy). Registering before we
--     stub also warms tool.lua's dofile cache, so the spec can't reload and
--     quietly restore the real sessions().
--   * Skip tmux/zellij when mux IS enabled — there, discovery is the feature.
local Session = require('sidekick.cli.session')
Session.setup()
local no_sessions = function() return {} end
local no_discovery = { 'opencode' }
if not require('sidekick.config').cli.mux.enabled then
  vim.list_extend(no_discovery, { 'tmux', 'zellij' })
end
for _, name in ipairs(no_discovery) do
  local backend = Session.backends[name]
  if backend then backend.sessions = no_sessions end
end

-- Keep only AGENTS' presets: no other spec is ever dofile'd (opencode proved a
-- spec can register a scanner on load) and State.get's per-call tool loop
-- shrinks from 12 entries to 4. cursor/pi are safe to keep — bare
-- cmd/is_proc/url, no sessions() scanner. Must run *after* the stub above —
-- pruning first leaves the dofile cache cold, so a later tool.get('opencode')
-- would re-register the real 40ms sessions(). The tool launcher (formerly
-- <leader>as) stays unbound however many tools there are — see keymaps.lua.
local tools = require('sidekick.config').cli.tools
for name in pairs(tools) do
  if not vim.tbl_contains(AGENTS, name) then tools[name] = nil end
end

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
    -- Tripwire: WinEnter active-tracking reads the sidekick_cli window stamp —
    -- the one internal whose loss fails silently (sends mis-route to a stale
    -- M.active). A first attach means a window just opened, so warn once if the
    -- stamp is missing.
    if not _G.__sidekick_stamp_ok and term and term.win
       and vim.api.nvim_win_is_valid(term.win)
       and vim.w[term.win].sidekick_cli == nil then
      vim.notify('sidekick: CLI window stamp (sidekick_cli) missing — active-session tracking is broken, sends may mis-route',
        vim.log.levels.ERROR)
      _G.__sidekick_stamp_ok = true   -- fire once per nvim run, not per attach
    end
    -- Agent view owns its tab's layout: no promote (wincmd L would reflow the
    -- view into three columns). The view's own Attach handler hides/embeds.
    if vim.t[vim.api.nvim_get_current_tabpage()].agentview then return end
    local cfg = require('sidekick.config').cli.win
    local layout = cfg.layout
    local side = layout == 'right' and 'right' or layout == 'left' and 'left' or nil
    if not side then return end -- float / top / bottom layouts don't need promoting
    if term and vim.api.nvim_win_is_valid(term.win) then
      utils.promote_to_full_height(term.win, side)
      -- wincmd L equalizes the split to ~50% (equalalways, ignores winfixwidth),
      -- so restore the width. Read term.opts.split.width (kept in sync by
      -- remember_width) so a promote never stomps the user's width.
      local split = (term.opts and term.opts.split) or cfg.split
      local w = split and split.width
      if w and w > 0 then
        vim.api.nvim_win_set_width(term.win, w <= 1 and math.floor(vim.o.columns * w) or w)
      end
    end
  end,
})

-- Track the active session on WinEnter (via sidekick's sidekick_cli stamp) —
-- the only reliable signal, since SidekickCliAttach fires once per lifetime,
-- not on switches. The pre-warm float is focusable=false, so never entered.
vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  desc = 'Sidekick: track active CLI session',
  callback = function()
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then set_active(tool.name) end
  end,
})

-- Apply a user-set CLI width globally, so every session (aa/an/al) opens at the
-- same width. open_win reads each terminal's opts.split.width and new terminals
-- deepcopy Config at init, so write both: live terminals and the config template.
local function remember_width(w)
  if not (w and w > 0) then return end
  require('sidekick.config').cli.win.split.width = w
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.opts and t.opts.split then t.opts.split.width = w end
  end
end

-- Capture on WinClosed (hide/switch-away) — never during promote's wincmd L, so
-- no transient ~50% width. Skip teardown (terminal.get nil) and the last-window
-- case (full-screen width, not user-chosen).
vim.api.nvim_create_autocmd('WinClosed', {
  group = augroup,
  desc = 'Sidekick: remember CLI width for a consistent width across sessions',
  callback = function(args)
    local win = tonumber(args.match)
    if not (win and vim.api.nvim_win_is_valid(win)) then return end
    -- The agent view's main pane carries the session stamps too (embed
    -- re-stamps it), but its near-fullscreen width is not a CLI column width.
    if vim.w[win].agentview_main then return end
    if #vim.api.nvim_list_wins() == 1 then return end
    local sid = vim.w[win].sidekick_session_id
    local term = sid and require('sidekick.cli.terminal').get(sid)
    if not term then return end
    remember_width(vim.api.nvim_win_get_width(win))
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
      if not running(name)
         and (phase == 'started' or #State.get({ name = name, terminal = true }) == 0) then
        M._forget(name)
      end
    end
    -- Same sweep for labels, minus the phase check (M.rename only labels a
    -- running session, so none is in flight). Here and not in _forget, which
    -- skips built-ins — a label on the bare `claude` would otherwise outlive
    -- its session and re-attach to the next one.
    for name in pairs(M._labels) do
      if not running(name) then M._labels[name] = nil end
    end
    -- And for the attention registry — same built-in reasoning: _forget's
    -- clear never fires for a dying bare `claude`.
    local ev = package.loaded['agent_events']
    if ev then
      for name in pairs(ev.sessions) do
        if not running(name) then ev.clear(name) end
      end
    end
    -- Active session died (self-exit, <C-x> in the picker, <leader>ax) → repoint to a
    -- survivor so a summon reattaches instead of spawning fresh. No
    -- `~= 'claude'` guard: a dying built-in `claude` is a no-op in _forget
    -- above (it only GCs dynamic names), so this branch is the *only* place a
    -- dead built-in `claude` gets repointed to a survivor — the guard used to
    -- suppress exactly that. When _forget already moved active to a live
    -- survivor, the started==0 check below is false, so no redundant repoint.
    if not running(M.active) then
      M.active = fallback_active(M.active)
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

    -- Session switching in place (single-window model), without leaving terminal
    -- mode (vs jj/jk then <leader>al): <M-]>/<M-[> cycle next/prev (nvim's ]/[
    -- next/prev idiom), <C-]> toggles the last-used session (a raw control byte,
    -- reliable with no CSI-u dependency), <M-n> forks an auto-named session of
    -- the active session's agent (bare-first, then numbered).
    vim.keymap.set({ 't', 'n' }, '<M-]>', function() require('ai').cycle(1) end,
      { buffer = args.buf, desc = 'AI: Next CLI session' })
    vim.keymap.set({ 't', 'n' }, '<M-[>', function() require('ai').cycle(-1) end,
      { buffer = args.buf, desc = 'AI: Previous CLI session' })
    vim.keymap.set({ 't', 'n' }, '<C-]>', function() require('ai').toggle_last() end,
      { buffer = args.buf, desc = 'AI: Toggle last-used CLI session' })
    vim.keymap.set({ 't', 'n' }, '<M-n>', function() require('ai').new_auto() end,
      { buffer = args.buf, desc = 'AI: Fork active agent, auto-named (in place)' })

    -- <M-1>..<M-9>: jump straight to session N (name-sorted — the order
    -- <M-]> cycles and the agent-view sidebar numbers its rows).
    for i = 1, 9 do
      vim.keymap.set({ 't', 'n' }, '<M-' .. i .. '>', function() require('ai').open_index(i) end,
        { buffer = args.buf, desc = 'AI: Jump to CLI session ' .. i })
    end

    -- <M-a> hides the panel in place (the <leader>aa toggle) without first
    -- escaping terminal mode via jj/jk — the common "stash the chat" action.
    -- toggle_active targets M.active, which the WinEnter stamp keeps equal to
    -- the focused session, so this hides the one you're in. Kill stays on the
    -- deliberate <leader>ax path (confirm-guarded) — no fast in-panel teardown.
    -- (Buffer-local to this CLI terminal; the picker's send-to-sidekick action
    -- is a separate key, <C-CR>, so there's no <M-a> collision to worry about.)
    vim.keymap.set({ 't', 'n' }, '<M-a>', function() require('ai').toggle_active() end,
      { buffer = args.buf, desc = 'AI: Hide CLI panel (toggle)' })

    -- <M-l> opens the session picker (the <leader>al switch/kill picker) in
    -- place, so you can jump to or tear down another session without the
    -- jj/jk -> <leader>al round-trip. Same in-panel ergonomic as <M-]>/<M-n>.
    vim.keymap.set({ 't', 'n' }, '<M-l>', function() require('ai').switch() end,
      { buffer = args.buf, desc = 'AI: Switch/kill/label CLI session picker' })

    -- <M-v> toggles the agent view in place — same family as <M-a>/<M-l>.
    vim.keymap.set({ 't', 'n' }, '<M-v>', function() require('agentview').toggle() end,
      { buffer = args.buf, desc = 'AI: Agent view (toggle)' })

    -- <M-r> labels the session you're in (the <leader>ar prompt), same family
    -- as <M-n>/<M-l>. Not <C-r> — that's the picker's rename key, and reusing
    -- it here would read as one binding. Deliberately not mirrored into
    -- toggleterm's <M-*> set: toggleterm has its own _display_name().
    vim.keymap.set({ 't', 'n' }, '<M-r>', function()
      local ai = require('ai')
      ai.rename(ai.active)
    end, { buffer = args.buf, desc = 'AI: Label the active CLI session' })

    -- In normal mode, forward raw bytes to the session's job channel. Named for
    -- claude but agent-neutral — only `u` below branches per agent.
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
    vim.keymap.set('n', '<C-u>', send_to_claude('\27[5~'),
      { buffer = args.buf, desc = 'AI: Scroll CLI TUI up' })
    vim.keymap.set('n', '<C-d>', send_to_claude('\27[6~'),
      { buffer = args.buf, desc = 'AI: Scroll CLI TUI down' })

    -- u: input-undo (vim's own would E21 in an unmodifiable terminal buffer).
    -- An allowlist, never a denylist — cursor showed what an unverified TUI
    -- does with a guessed byte: 0x1F cycles its model, and it has no undo at
    -- all (binary-inspected 2026-07-22). 0x1F covers the other three because
    -- it IS ctrl+- on the wire (0x5F & 0x1F), their stock undo key.
    -- Trap: do NOT send Ctrl+Z to opencode — that's its terminal_suspend; only
    -- its Windows build reuses ctrl+z for undo.
    local UNDO_SEQ = {
      claude   = '\31',  -- ctrl+_, pinned in the stowed claude keybindings.json
      pi       = '\31',  -- stock: tui.editor.undo = ctrl+-
      opencode = '\31',  -- stock: input_undo = "ctrl+-,super+z"
    }
    -- Unverified agents fall back to Ctrl+U (kill line back): safe, but
    -- unrecoverable and one line per press. Undo only applies while the input
    -- box has focus. <C-r> stays unmapped — no agent has a redo to forward.
    vim.keymap.set('n', 'u', function()
      local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
      send_to_claude(UNDO_SEQ[tool and agent_of(tool.name)] or '\21')()
    end, { buffer = args.buf, desc = 'AI: Undo prompt input (per-agent sequence)' })

    -- p/P (identical here — no before/after-line in a prompt): bracketed-paste
    -- v:register ("ap pastes @a; default unnamed) into the agent's input;
    -- bracketing makes embedded newlines insert instead of submitting.
    local function paste_to_claude()
      local text = vim.fn.getreg(vim.v.register)
      if text == '' then return end
      send_to_claude('\27[200~' .. text .. '\27[201~')()
    end
    vim.keymap.set('n', 'p', paste_to_claude,
      { buffer = args.buf, desc = 'AI: Paste register into prompt (bracketed)' })
    vim.keymap.set('n', 'P', paste_to_claude,
      { buffer = args.buf, desc = 'AI: Paste register into prompt (bracketed)' })
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
  -- Guard 1: a *primary* (claude) CLI already exists (user opened it during
  -- the wait, or a restore surfaced one) -> don't double-spawn. Match the
  -- primary tool specifically via sidekick's live terminal registry, NOT the
  -- `sidekick_terminal` filetype -- every sidekick CLI shares that filetype,
  -- so a live cursor session would wrongly suppress the claude pre-warm.
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.tool and t.tool.name == PRIMARY and t:buf_valid() then
      return
    end
  end
  local cli = require('sidekick.cli')
  _G.__sidekick_prewarm = true
  pcall(cli.show, { name = PRIMARY, focus = false })
  vim.defer_fn(function()
    _G.__sidekick_prewarm = nil
    if prewarm_term then
      prewarm_term.open_win = nil
      prewarm_term = nil
    end
    -- Guard 2: if a *visible* primary CLI appeared during the show->hide
    -- window (user hit <leader>aa), skip the hide so we don't yank it away.
    -- Match the primary tool specifically (registry, not filetype) so a
    -- visible cursor session doesn't suppress our hide. Our own pre-warm
    -- float stays hidden (hide=true; promotion is skipped while
    -- pre-warming), so it's excluded.
    for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
      if t.tool and t.tool.name == PRIMARY and t:win_valid()
         and not vim.api.nvim_win_get_config(t.win).hide then
        return
      end
    end
    pcall(cli.hide, { name = PRIMARY })
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

-- Same warn-loud idea for every agent's binary, derived from AGENTS + EXE so a
-- new agent is covered automatically. cursor is why this exists: its binary is
-- `cursor-agent`, not `cursor`, so a reshaped preset would silently launch the
-- wrong thing. pcall the .cmd[1] index (tool.get returns `config = {}` rather
-- than throwing for a missing preset) — otherwise a reshaped upstream aborts
-- this file before `return M` and takes every AI keymap down.
for _, agent in ipairs(AGENTS) do
  local exe = EXE[agent] or agent
  local ok_cfg, cfg = pcall(function()
    return require('sidekick.cli.tool').get(agent).config
  end)
  if not ok_cfg or type(cfg.cmd) ~= 'table' or cfg.cmd[1] ~= exe then
    vim.notify(('sidekick: %s preset missing/reshaped — %s sessions may spawn the wrong binary'):format(agent, agent),
      vim.log.levels.ERROR)
  end
end

-- The display namespace is flat: a <leader>al row renders `label or name`, so
-- one string must never mean two sessions. Guarded both ways — a label may not
-- shadow a name (M.rename), and a session may not be born under a live label
-- (create_session/auto_name). Guarding only the first lets the collision
-- reappear later: label one 'claude 3', then <M-n> names the next fork that.
--
-- cli.tools, not running sessions: the stricter set (a registered-but-unstarted
-- name is still spawnable, so it stays reserved).
local function name_taken(str)
  return require('sidekick.config').cli.tools[str] ~= nil
end

-- Already some *other* session's label? Returns that session's name, so the
-- caller's notify can say what it collided with.
local function label_taken(str, except)
  for name, label in pairs(M._labels) do
    if label == str and name ~= except then return name end
  end
end

-- Auto numbers climb monotonically and never refill a freed number (delete
-- 'claude 2', fork again → next unused, not the gap). One global counter
-- across agents, so per-agent sequences are non-contiguous ('claude 2',
-- 'cursor 3') — deliberate; the prefix carries identity, not the number.
-- _auto_seq is the high-water mark this nvim run, also floored above any
-- existing '<agent> N' so a re-source (resets M) or an externally-created
-- name can't collide with a live session.
function M._next_auto_name(agent)
  local tools = require('sidekick.config').cli.tools
  local n = M._auto_seq or 1
  for name in pairs(tools) do
    for _, a in ipairs(AGENTS) do
      local k = tonumber(name:match('^' .. vim.pesc(a) .. ' (%d+)$'))
      if k and k > n then n = k end
    end
  end
  n = n + 1
  -- Step over numbers a label has claimed. No name_taken check needed — n
  -- already exceeds every existing '<agent> N', so candidates from here up are
  -- name-free. Terminates: _labels is finite.
  while label_taken(agent .. ' ' .. n) do n = n + 1 end
  M._auto_seq = n
  return agent .. ' ' .. n
end

-- Bare-name-first: with no running session named exactly <agent>, the auto
-- name IS the bare agent name (its static preset spawns, no dynamic
-- registration needed); otherwise the next global number. So an <M-n> fork
-- can resurrect a dead bare name instead of numbering.
local function auto_name(agent)
  if not running(agent)
     and not label_taken(agent) then   -- a label owns the bare name → number instead
    return agent
  end
  return M._next_auto_name(agent)
end

-- Register a dynamic tool (if new) and show it. Re-registering an
-- existing name is a no-op → labels re-attach (see "Labels are reusable").
-- show (not toggle): re-entering the label of a *visible* session must
-- focus it, not hide it. show auto-starts unstarted registered names via
-- the same select-auto path (state.lua:159).
-- Enforce one visible CLI window: hide the others, then show the target
-- (<leader>an/<leader>al would otherwise stack a second split). Hide
-- synchronously via terminal:hide() — cli.hide defers two hops vs cli.show's
-- one, so it would run show-before-hide; iterating terminals also skips the
-- same-name disambiguation picker. hide, not close — the job stays alive.
-- Agent-view delegate, shared by the show/focus/toggle wrappers below: while
-- the view tab is current it owns all display, so every switch path (cycle,
-- toggle_last, picker, create_session, open_index) must route into it — a
-- cli.show there would split the view tab (the embedded terminal isn't in
-- sidekick's window registry). package.loaded, not require: inert until the
-- user has opened the view once.
local function agentview_active()
  local av = package.loaded['agentview']
  return (av and av.is_active()) and av or nil
end

local function show_solo(name)
  local av = agentview_active()
  if av then return av.select(name) end
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.tool and t.tool.name ~= name then t:hide() end   -- no-op if not shown
  end
  require('sidekick.cli').show({ name = name, focus = true })
end

local function create_session(name)
  -- A non-parsing name means a producer broke the prefix invariant — refuse,
  -- never default: a silent claude fallback would revive the old "name is
  -- cosmetic" bug.
  local agent = agent_of(name)
  if not agent then
    vim.notify(('sidekick: session name %q has no agent prefix — refusing to spawn'):format(name),
      vim.log.levels.ERROR)
    return
  end
  -- Namespace guard, also BEFORE set_active (same reasoning as the binary
  -- check below). A repeat *name* still re-attaches ("labels are reusable");
  -- only a collision with someone's *label* is refused, since the picker would
  -- then show that string twice.
  local owner = label_taken(name)
  if owner then
    vim.notify(('sidekick: %q is already the label of %s — pick another name'):format(name, owner),
      vim.log.levels.WARN)
    return
  end
  local preset = require('sidekick.cli.tool').get(agent).config
  -- Missing-binary guard, BEFORE set_active: proceeding would wedge M.active
  -- on an unspawnable name (built-ins never GC via the detach sweep) and
  -- spawn a terminal that dies instantly.
  local exe = type(preset.cmd) == 'table' and preset.cmd[1]
  if not exe or vim.fn.executable(exe) == 0 then
    vim.notify(('sidekick: %s not executable — install it to run %s sessions'):format(exe or '?', agent),
      vim.log.levels.WARN)
    return
  end
  local cfg = require('sidekick.config')
  if not cfg.cli.tools[name] then
    -- Clone the agent's own resolved preset (claude: cmd + format +
    -- resume/continue; cursor: bare cmd) — see plan "clone the preset".
    cfg.cli.tools[name] = vim.deepcopy(preset)
    -- The clone carries the BASE agent's SIDEKICK_SESSION — force-overwrite
    -- with this session's own name or every fork reports as its agent.
    cfg.cli.tools[name].env = vim.tbl_extend('force', cfg.cli.tools[name].env or {},
      { SIDEKICK_SESSION = name })
    M._dynamic[name] = 'registered'   -- 'started' once the first attach fires
  end
  set_active(name)  -- eager; WinEnter confirms once the window is entered
  show_solo(name)
end

-- <M-n> inside the CLI: fork an auto-named session of the ACTIVE session's
-- agent, no prompts (labels stay on <leader>an). The one agent-scoped nav
-- key; <M-l>/<M-]>/<M-[> stay pool-wide.
function M.new_auto()
  create_session(auto_name(agent_of(M.active) or PRIMARY))
end

-- Drop a dynamically-registered name from cli.tools. Never touches the
-- built-in bare agent names (AGENTS) — only names create_session added.
function M._forget(name)
  if not M._dynamic[name] then return end
  require('sidekick.config').cli.tools[name] = nil
  M._dynamic[name] = nil
  -- Drop attention state with the name: a reused name (kill 'claude 2',
  -- spawn a new 'claude 2') must not inherit the old process's ring.
  local ev = package.loaded['agent_events']
  if ev then ev.clear(name) end
  -- If the name we're dropping was active, repoint to a survivor rather than
  -- the hardcoded default, so a summon reattaches. Handles the *dynamic*
  -- active-death path; a dying built-in `claude` (a no-op here) is repointed by
  -- the detach-sweep branch instead — the two split that responsibility.
  if M.active == name then M.active = fallback_active(name) end
end

-- <leader>an: the single creation door. Agent picker (first item is the
-- default, so plain <CR> confirms — +1 Enter, accepted), then a label:
-- blank = auto name (bare-first, then numbered), a repeat label re-attaches,
-- <Esc> cancels either step.
function M.new_session()
  -- Ranking only — identity stays with AGENTS; the rest follow in AGENTS
  -- order, so a new agent shows up in the picker automatically.
  -- TODO: cursor promoted to first while trialling it (<CR><CR> = new cursor
  -- session); drop the promotion to restore claude-first.
  local pick_order = { 'cursor' }
  for _, a in ipairs(AGENTS) do
    if a ~= 'cursor' then pick_order[#pick_order + 1] = a end
  end
  vim.ui.select(pick_order, { prompt = 'New session — agent:' }, function(agent)
    if agent == nil then return end                       -- <Esc> cancels
    vim.ui.input({ prompt = ('New %s session (blank = auto): '):format(agent) }, function(input)
      if input == nil then return end                     -- <Esc> cancels
      local name = input ~= '' and (agent .. ': ' .. input) or auto_name(agent)
      if #name >= 16 then
        -- sid's cwd-hash slice is empty at >=16 chars (session/init.lua:107):
        -- reusing this label from another project dir in this nvim run would
        -- silently reattach to this session. Warn, don't reject.
        vim.notify(('Long label (%d chars): reusing "%s" from another project dir will reattach to this session'):format(#name, name),
          vim.log.levels.WARN)
      end
      create_session(name)
    end)
  end)
end

-- <leader>ar / <M-r> / <C-r> in the picker: set or clear a session's display
-- label. Cosmetic — it changes how M.switch renders a row and nothing else;
-- identity stays the tool name. Hence no >=16-char warning: unlike a
-- <leader>an label, this string never reaches Session.sid. on_done fires on
-- every outcome including refusals, so a picker caller can always reopen.
function M.rename(name, on_done)
  -- Refuse a name with nothing running under it: M.active is PRIMARY before any
  -- session exists, so a cold-start <leader>ar would label a never-started
  -- 'claude' that nothing reclaims (the sweep only runs on SidekickCliDetach).
  -- Also what keeps that sweep simple — no label can be mid-spawn.
  if not running(name) then
    vim.notify(('sidekick: no running session named %q to label'):format(name), vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = ('Label for %s: '):format(name), default = M._labels[name] or '' }, function(input)
    if input == nil then return end                       -- <Esc> cancels
    if not running(name) then
      -- The session can die while the prompt is up — its label sweep has
      -- already run, so a label written now would orphan (and could re-attach
      -- to a future same-name session).
      vim.notify(('sidekick: %s exited while the prompt was open — label dropped'):format(name),
        vim.log.levels.WARN)
    elseif input == '' or input == name then
      M._labels[name] = nil                               -- blank (or its own name) clears
    elseif name_taken(input) then
      vim.notify(('sidekick: %q is a session name — pick another label'):format(input), vim.log.levels.WARN)
    else
      local owner = label_taken(input, name)
      if owner then
        vim.notify(('sidekick: %q is already the label of %s'):format(input, owner), vim.log.levels.WARN)
      else
        M._labels[name] = input
      end
    end
    if on_done then on_done() end
  end)
end

function M.toggle_active()
  -- In the view, "stash the agent UI" means leaving the view: the whole tab
  -- IS the agent UI, and cli.toggle would open a second window instead.
  local av = agentview_active()
  if av then return av.toggle() end
  require('sidekick.cli').toggle({ name = M.active, focus = true })
end

-- <leader>ax target: tear down the active session specifically (avoids the
-- unfiltered cli.close() → disambiguation-picker behaviour with 2+ sessions).
-- Reset M.active synchronously (cli.close is async — two scheduled hops); the
-- detach sweep still GCs the dynamic name after close's detach event fires.
function M.kill_active()
  local name = M.active
  -- Repoint to a survivor (excluding the one we're killing — cli.close is
  -- async, so it's still started=true here) so <leader>aa reattaches instead
  -- of spawning fresh. fallback_active returns the primary when none survive.
  M.active = fallback_active(name)
  require('sidekick.cli').close({ name = name })
end

-- Kill a named session synchronously (picker <C-x>, agent-view sidebar `x`).
-- State.detach inline, not cli.close: close is two vim.schedule hops, and a
-- send landing in that gap would re-route to the dead-but-still-registered
-- name → select({auto=true}) → a fresh session respawns under it. Repoint
-- active + GC synchronously too, before detach, while the target is still
-- started=true (same reasoning as kill_active). _forget is a no-op on
-- built-ins, so killing the default `claude` won't unregister its preset.
-- `state`: an optional pre-resolved session-state object (the picker's row
-- already holds one). Name-only State.get prefers the current-cwd session
-- for a same-named pair in different cwds, so a by-name-only lookup can kill
-- the wrong one — pass the exact object when the caller has it. The
-- agent-view sidebar has no state object per row (name-keyed), so it still
-- falls back to the lookup; accepted there.
function M.kill(name, state)
  local State = require('sidekick.cli.state')
  local s = state or State.get({ name = name, started = true })[1]
  if not s then return end
  if M.active == name then M.active = fallback_active(name) end
  State.detach(s)
  M._forget(name)
end

-- Routing wrappers: every send/focus targets the active session, so a second
-- running session never turns sends into a pick-a-target flow (state.lua:165).
-- Normalize a bare string like cli.send does, so a stray send('{selection}')
-- can't blow up tbl_extend.
function M.send(opts)
  -- Refuse in the view: cli.send hardcodes show=true (a stray split), and
  -- every context template renders against the current buffer — which here
  -- is the sidebar or a terminal, never the code being discussed.
  if agentview_active() then
    return vim.notify('agent view: context sends read the current code buffer — close the view first',
      vim.log.levels.WARN)
  end
  opts = type(opts) == 'string' and { msg = opts } or opts or {}
  require('sidekick.cli').send(vim.tbl_extend('force', opts, { name = M.active }))
end

function M.focus()
  local av = agentview_active()
  if av then return av.focus_main() end
  require('sidekick.cli').focus({ name = M.active })
end

-- <leader>al: indexed_select picker over running sessions. <CR>/<M-1>..<M-9>
-- show/focus (making it active); <C-x> tears one down.
function M.switch()
  local State = require('sidekick.cli.state')

  local function items()
    return vim.tbl_map(function(s)
      -- cwd in the display: same-named sessions in two cwds are otherwise
      -- indistinguishable (see Known edges).
      local cwd = s.session and vim.fn.fnamemodify(s.session.cwd, ':~') or ''
      local label = M._labels[s.tool.name]
      -- Label and name both go in `text` (the field snacks matches on), so a
      -- labelled row is still findable by its raw name.
      return {
        text = (label and label .. ' ' or '') .. s.tool.name .. ' ' .. cwd,
        label = label, name = s.tool.name, cwd = cwd, state = s,
      }
    end, State.get({ started = true }))              -- running sessions only
  end

  return require('pickers.common').indexed_select({
    source = 'sidekick_sessions',
    title = 'Sidekick sessions',
    finder = items,
    -- Label bright, raw name demoted beside it: the name carries the agent, so
    -- hiding it behind a label would lose which AI a row is.
    format = function(item)
      local ret = { { item.label or item.name } }
      if item.label then vim.list_extend(ret, { { '  ' }, { item.name, 'Comment' } }) end
      vim.list_extend(ret, { { '  ' }, { item.cwd, 'Comment' } })
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        set_active(item.name)  -- eager; WinEnter confirms on focus
        show_solo(item.name)   -- replace the open window, don't stack
      end
    end,
    -- M.kill's synchronous teardown is what keeps indexed_select's refresh
    -- reading post-kill state (detach inline, not cli.close's two hops).
    -- item.state: the exact session object this row was built from, so a
    -- same-named session in another cwd can't get killed instead (see M.kill).
    kill = function(item) M.kill(item.name, item.state) end,
    -- Close, prompt, reopen — not an in-place picker:find(). vim.ui.input
    -- resolves async and snacks owns the picker's own input window, so
    -- prompting over a live picker is the jank-prone path. Reopening also makes
    -- labelling several sessions in a row cheap.
    rename = function(picker, item)
      picker:close()
      M.rename(item.name, function() M.switch() end)
    end,
  })
end

-- Cycle to the prev/next running session in place (dir -1/+1), wrapping around.
-- Bound to <M-[>/<M-]> inside the CLI (see the sidekick_terminal FileType
-- autocmd) so you can move between AIs without exiting terminal mode. Sorted by
-- name for a stable order; no-op with fewer than two running sessions.
function M.cycle(dir)
  local sessions = require('sidekick.cli.state').get({ started = true })
  if #sessions < 2 then return end
  table.sort(sessions, function(a, b) return a.tool.name < b.tool.name end)
  local idx = 1
  for i, s in ipairs(sessions) do
    if s.tool.name == M.active then idx = i break end
  end
  local name = sessions[(idx - 1 + dir) % #sessions + 1].tool.name
  set_active(name)
  show_solo(name)
end

-- <leader>aj: jump to the most recently unread session (cmux's triage key),
-- skipping the session in the focused window — an urgent ring survives focus
-- (agent_events' ack rule), so without the skip an unanswered `!` would trap
-- repeat presses on itself. Landing acks a turn-complete ring via the
-- WinEnter handler; the direct ack below covers the in-view case where the
-- embed swaps the buffer under the cursor and no WinEnter ever fires.
function M.jump_unread()
  local ev = package.loaded['agent_events']
  if not ev then return end
  local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
  local here = tool and tool.name
  for _, name in ipairs(ev.unread_sessions()) do
    if name ~= here and running(name) then
      set_active(name)
      show_solo(name)
      local av = agentview_active()
      if av then av.enter_main() end
      ev.ack(name)
      return
    end
  end
  vim.notify('sidekick: no unread agent sessions', vim.log.levels.INFO)
end

-- <M-1>..<M-9> inside the CLI (and 1-9 in the agent-view sidebar): jump
-- straight to running session N in name-sorted order — the same comparator as
-- cycle(), so digit order always equals <M-]>/<M-[> order. No-op past the end.
function M.open_index(n)
  local sessions = require('sidekick.cli.state').get({ started = true })
  table.sort(sessions, function(a, b) return a.tool.name < b.tool.name end)
  local s = sessions[n]
  if not s then return end
  set_active(s.tool.name)
  show_solo(s.tool.name)
end

-- <C-]> inside the CLI: bounce to the session you were last in (alt-tab style;
-- set_active tracks it). No-op if there's no prior session or it has stopped.
-- set_active makes the one we left the new _last, so a second <C-]> bounces back.
function M.toggle_last()
  local last = M._last
  if not last or last == M.active then return end
  if not running(last) then return end
  set_active(last)
  show_solo(last)
end

return M
