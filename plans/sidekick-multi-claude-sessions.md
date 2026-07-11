# Multiple Claude sessions in sidekick (no mux, dynamic — not hardcoded)

## Goal

Run several independent `claude` CLI sessions in one nvim instance and switch
between them, **without** the mux (tmux/zellij) backend and **without**
pre-declaring a fixed count. The organizing concept is the **active session**:
the CLI session whose window you last entered (default: the pre-warmed
`claude`). Every "act on the CLI" keymap targets it. Concretely:

- `<leader>aa` — toggle the **active** session.
- `<leader>an` — spawn/attach a Claude session, created on demand (unbounded).
  Prompt for a label; **blank Enter = auto-numbered** (always a *new* session);
  a **typed label re-attaches** if it already exists (reusable/named); `<Esc>`
  cancels. The new/reattached session becomes active.
- `<leader>al` — **switch** between currently-running CLI sessions via a
  **custom telescope picker**. `<CR>` shows/focuses the session (making it
  active); **`<C-d>` tears down** the highlighted session (telescope's delete
  convention). Torn-down dynamic names are GC'd from `cli.tools` synchronously
  in the `<C-d>` handler (the detach sweep is the backstop for self-exits).
- `<leader>ad` — kill the **active** session (was: kill the single CLI),
  behind the existing confirm popup.
- **All context-send keys (`<leader>at/ap/af/ac/ae/ab/aq`), `<leader>ao`
  (prompt), `<M-a>` in pickers, and `<C-.>`/`<leader>ai` (focus) route to the
  active session.** Without routing, sidekick pops a disambiguation picker on
  *every* send/focus the moment a second session is attached (see Context) —
  the biggest day-to-day behavior change multi-session would otherwise cause.

Each session is a *separate* `claude` process (separate conversation/context),
living in an nvim-owned scratch terminal. Sessions persist across hide/show
within an nvim run and die on nvim exit (consistent with the no-mux choice —
nothing survives restart without mux). Killed names are unregistered by the
detach sweep; re-creating a name via `<leader>an` spawns a **fresh**
conversation (no `--resume`) — see Design decisions.

## Context — why this shape, and what the source forces

Verified against sidekick `main` (`lua/sidekick/cli/*`, `sk/cli/claude.lua`):

### Session identity is `(tool name, cwd)` — no per-session counter

`session/init.lua`:

```lua
function M.sid(opts)
  return ("%s %s"):format(tool, vim.fn.sha256(cwd):sub(1, 16 - #tool))
end
```

A session's id is the **tool name + a hash of the cwd**. There is no index or
counter. So two `claude` sessions in the *same* project dir collide to one.
**Concurrent Claude sessions in one project each need a distinct tool name** —
the name *is* the identity.

### Tool names can be registered at runtime (so: no hardcoding)

`cli/tool.lua`'s resolver reads live config:

```lua
function M.get(name)
  local config = vim.tbl_deep_extend("force",
    vim.deepcopy(base[name] or {}),               -- runtime preset sk/cli/<name>.lua
    vim.deepcopy(Config.cli.tools[name] or {}))   -- user config
  ...
end
```

and `config.lua`'s `M.tools()` iterates `Config.cli.tools` **at call time**:

```lua
function M.tools()
  local ret = {}
  for name in pairs(M.cli.tools) do ret[name] = M.get_tool(name) end
  return ret
end
```

So inserting a new key into `require('sidekick.config').cli.tools` at runtime
makes that name immediately toggle-able and visible in the picker. (Verified:
`Config`'s metatable `__index` at config.lua:307 returns the live module-local
`config` table by reference, and `setup()` — which rebuilds it — runs once at
startup, before any registration.) No fixed cap, no pre-declaration. This is
the mechanism that replaces "hardcode 5".

### Built-in `claude` carries no `cmd` in user config — clone the preset

The default `cli.tools.claude` is just `{}` (config.lua:109); the real spec
lives in the runtime preset `sk/cli/claude.lua`:

```lua
return {
  cmd = { "claude" },
  is_proc = "\\<claude\\>",
  resume = { "--resume" }, continue = { "--continue" },
  format = function(text) ... end,   -- makes sent context claude-friendly
  url = "...",
}
```

A dynamically-registered `claude 2` has **no** `base` preset (base is keyed by
name), so it must carry the full spec. Don't hardcode `{ cmd = {'claude'} }` —
that would drop `format`/`resume`/`continue`. Instead clone the resolved
preset: `vim.deepcopy(require('sidekick.cli.tool').get('claude').config)`
(`vim.deepcopy` copies the `format` function by reference — verified). This
inherits whatever claude's real spec is, now and after upstream changes.

### `toggle({name})`/`show({name})` auto-start a named tool — no stray picker

`state.lua` `M.with` (used by `toggle`/`show`/`focus`):

```lua
if #attached == 0 and opts.attach then
  select({ auto = true, filter = opts.filter, cb = use })   -- auto=true + 1 match → auto-attach
elseif #attached > 1 and not opts.all then
  select({ auto = true, filter = filter_attached, cb = use })
else
  vim.tbl_map(use, attached)
end
```

With `filter.name = 'claude 2'`, exactly one tool matches, so `auto = true`
attaches it directly (`ui/select.lua`: `#tools == 1 and opts.auto → on_select`).
So `show({ name = X, focus = true })` works whether or not that session is
currently running, as long as the name is registered in `cli.tools`.

### `SidekickCliAttach` fires ONCE per session lifetime — not on every show

The sole emit site is `session/init.lua:194`, inside `Session.attach`, which
**early-returns at line 171 when the session is already in `M._attached`**.
With the terminal backend a session stays attached from spawn until `close()`:
`terminal:hide()` (terminal.lua:422) only closes the window and never
detaches. So the event does **not** fire when re-showing a hidden session or
switching to a running one — it fires exactly once, at spawn.

Two consequences:

1. **"Active session" tracking cannot hang off `SidekickCliAttach`** —
   switching sessions via `<leader>al`/`<leader>as`/`<C-.>` would never update
   it. Instead we track on **`WinEnter`**: sidekick stamps every CLI window
   with `vim.w[win].sidekick_cli = tool` (terminal.lua:385), so a trivial
   WinEnter autocmd reads it and records the name. This covers every path
   that matters — picker `<CR>` (focus enters the window), `<leader>as`
   launches, `<C-w>` navigation, mouse clicks — with zero coupling to
   sidekick's event timing. The pre-warm float is `focusable = false` and
   never entered, so it never pollutes tracking.
2. **The existing comment on the promote-to-full-height autocmd in `ai.lua`
   is wrong** ("SidekickCliAttach fires on every show path … covers internal
   re-shows"). Fix the comment in this change. Empirically re-shows land
   full-height today without re-promotion (hide/show toggling works now, and
   attach never re-fires), so no functional change — but verification step 10
   re-checks this under session switching.

### With 2+ attached sessions, every unfiltered keymap pops a picker

All current entry points besides `<leader>aa` — `<C-.>`/`<leader>ai`
(`focus()`), every send key, `<leader>ao`'s default prompt callback, `<M-a>`
in telescope — call `State.with` with **no name filter**. With
`#attached > 1`, state.lua:165 shows the disambiguation select on **every
invocation**: "send this to Claude" becomes a two-step flow the moment a
second session exists. This is why routing through the active session is part
of the core design, not a follow-up: `filter_opts` (cli/init.lua:48) already
threads `opts.name` into the filter for `send`/`focus`/`toggle`/`close`, so
routing is just passing `name = M.active`.

### The switch picker: custom telescope picker (needed for `<C-d>` delete)

Two facts force a hand-rolled picker:

1. **sidekick's `select()` is just `vim.ui.select`.** `cli/ui/select.lua:46`
   calls `vim.ui.select(tools, opts, on_select)` — there is **no** native
   telescope integration and **no** custom-action hook. (The `picker =
   'telescope'` in `ai.lua` only routes `vim.ui.select` through
   telescope-ui-select, which presents choices and returns one — it can't bind
   `<C-d>` to a delete action per call.) So a delete-in-picker affordance
   cannot hang off `select()`.
2. `sidekick.cli.Filter.name` is an **exact** match (`filter.name ==
   t.tool.name`, state.lua:42) — no prefix — so `select()` couldn't be filtered
   to `claude*` anyway.

**Decision (reverses the earlier "no hand-rolled picker" note):** because the
user wants `<C-d>` to delete sessions from the switcher, `<leader>al` becomes a
**custom telescope picker** built on `require('sidekick.cli.state').get({
started = true })` (state.lua:69, public):

- `<CR>` → set `M.active`, then `cli.show({ name, focus = true })`.
- `<C-d>` → **synchronous teardown + refresh** (see next section), then
  `picker:refresh(finder())` in place. `M.active` reset and name GC also happen
  synchronously here (not just in the sweep) — otherwise a send in the gap
  before the scheduled sweep re-routes to the dead name and respawns it.

Entries display `name` **plus the session cwd** (`:~`-shortened) — with the
same name possible in two cwds, name-only entries would be indistinguishable.

Scope stays **all running in-nvim sidekick sessions** (not claude-only) per the
user's preference — Copilot/Codex started in this nvim appear too.

### `<C-d>` teardown must be synchronous — `cli.close()` is two hops late

`cli.close({name})` → `State.with(State.detach, …)`, and `state.lua` wraps
both `cb` (line 145) and `use` (line 148) in `vim.schedule_wrap` — so the
actual detach runs **two main-loop ticks after `cli.close` returns**. A
`picker:refresh()` issued right after `cli.close` re-reads
`State.get({started = true})` while the session is still alive: the killed
entry stays in the list and a second `<C-d>` double-fires.

Fix: call `require('sidekick.cli.state').detach(entry.value)` **directly** in
the `<C-d>` handler. It is synchronous — `terminal:close()` removes the
terminal from `M.terminals` inline (terminal.lua:455); only the
`SidekickCliDetach` *event* is scheduled — so the refresh on the very next
line reads post-kill state. (`<leader>ad` can keep `cli.close({name})`:
nothing observes it synchronously there.)

### What the switcher does NOT show — and one tmux gotcha to know

For this repo (zellij, no tmux) `<leader>al` lists **only sessions started
inside the current nvim**. Confirmed against the backend model:

- **Terminal backend** (`terminal.lua`): `sessions()` returns `M.terminals`, a
  module-local table in *this* nvim process. So another nvim's sidekick claude,
  or a plain-terminal claude, is never in it.
- **Mux backends are registered on *executable presence*, NOT on
  `cli.mux.enabled`** — `session/init.lua` `M.setup()` registers tmux/zellij
  whenever `vim.fn.executable(name) == 1`, and `Session.sessions()` iterates
  every registered backend. So discovery can run even with mux "disabled." But:
  - **zellij** (`session/zellij.lua`) has no process info from zellij's API, so
    it discovers *only sidekick-created* zellij sessions (keyed off sidekick's
    session-name marker). With mux disabled sidekick creates none → an ad-hoc
    `claude` in a zellij/terminal pane is **not** discovered. This is why the
    zellij-only setup stays clean.
  - **tmux** (`session/tmux.lua`) walks the process tree of *every* tmux pane
    and matches each proc against every registered tool's `is_proc` regex
    (tmux.lua:135, first match wins via `pairs()` order). Every dynamic clone
    carries claude's `is_proc = \<claude\>`, so a hand-started claude in any
    tmux pane would surface as an attachable external session **labeled with
    whichever `claude*` name `pairs()` happens to iterate first** —
    nondeterministic naming, not just leakage.
  - **Gotcha:** because registration is executable-gated, **installing tmux on
    this machine — even without using it as sidekick's mux — would start
    leaking (nondeterministically-named) tmux-pane claude processes into
    `<leader>al`.** Not a concern today (no tmux here); recorded so it isn't a
    surprise later.
- Plain `claude` in a bare terminal (no mux) is discoverable by neither backend.

Net: sessions stay nvim-managed as intended; `<leader>al` showing all *in-nvim*
sidekick sessions is the accepted behavior, not a compromise to revisit.

### The internals this leans on — and the one that fails *silently*

This routing layer reaches several sidekick internals: `State.get`/`State.detach`
(`cli/state.lua`), runtime mutation of `Config.cli.tools`,
`tool.get('claude').config` (for the clone), `terminal.get`, and the
`sidekick_cli` window-var stamp. Most break **loudly** if upstream changes
shape — a nil index, or a visible disambiguation picker. The exception is the
**`sidekick_cli` WinEnter stamp**: if upstream stops stamping CLI windows,
active-tracking silently stalls and sends mis-route to a stale `M.active` with
no error. Two guards for the silent cases: a load-time `notify(ERROR)` on the
clone shape (impl 1e) surfaces a preset-shape break at startup without hard-
erroring (an `assert` would throw before `ai.lua`'s `return M` and take every
AI keymap down over a formatting-only regression), and the `SidekickCliAttach`
handler carries a `notify`-once tripwire (impl 1c) — "first attach but no
`sidekick_cli` window stamp → warn loud once" — so a future upstream change
that drops the stamp surfaces immediately instead of silently mis-routing
sends. Verification step 4 exercises the same stamp at implement-time.
Worth keeping in perspective: `ai.lua` **already** operates at this coupling
level (the pre-warm hook overrides `term.open_win` and reads
`terminal.get`/the session stamp), so this is more of the same surface, not a
new class of dependency. The line numbers cited throughout this plan are
documentation anchors, not runtime dependencies — they drift, they don't break.

## Design decisions locked

- **Active-session routing (user-decided).** The session in use right now is
  the "active" one, and *everything* targets it: `<leader>aa` toggle,
  `<leader>ad` kill, all sends, `<leader>ao`, `<M-a>`, `<C-.>`/`<leader>ai`
  focus. No disambiguation pickers in the hot path — *except* the documented
  same-name-in-two-cwds edge (Known edges), which is name-filter-wide: it hits
  sends/`ad`/focus too, not only `<leader>aa`. `<leader>al`/`<leader>an`
  are how you change targets.
- **Active tracking is tool-generic, WinEnter-based.** `M.active` records the
  last *CLI window entered* — any tool, not just `claude*`. Rationale: if you
  switch to a copilot session and hit `<leader>at`, the send should go to
  copilot; claude-only tracking would silently mis-route it. Default
  `'claude'`, eagerly set by `<leader>an`/`<leader>al` (async spawn means the
  window isn't entered instantly), confirmed by WinEnter, reset to `'claude'`
  by the detach sweep when the active session dies.
- **Naming (`<leader>an`)**: prompt via `vim.ui.input`; **blank Enter →
  auto-numbered** (`claude 2`, `claude 3`, …), a typed label → `claude: <label>`
  (e.g. `claude: tests`), `<Esc>`/`nil` → cancel. (User-selected.)
- **Labels are reusable (re-attach, not error/dup).** `<leader>an` → `tests`
  twice lands on the *same* `claude: tests` session — the `if not
  cli.tools[name]` guard makes named sessions idempotent, and `cli.show` (not
  `toggle`) means re-entering the label of a *visible* session focuses it
  rather than hiding it. Only blank-Enter auto-numbering guarantees a
  brand-new session. (User-decided.)
- **Long labels warn, not reject.** For `#name >= 16` the sid's cwd-hash slice
  is empty (see Known edges) — `new_session` warns but proceeds, since the
  failure mode only bites when reusing the same label from a second cwd in one
  nvim run. Rejecting would cap labels at 7 chars (`'claude: '` is 8), too
  restrictive.
- **Re-creating a killed name spawns fresh (no `--resume`).** The old context
  dies with the process; the detach sweep also unregisters the name, so
  revival is always an explicit `<leader>an` re-create, never a surprise
  `<leader>aa` respawn. Accepted (documented so it isn't a surprise).
  (User-decided.)
- **The detach sweep is in v1 (promoted from follow-up).** A
  `SidekickCliDetach` autocmd (event emitted at session/init.lua:163,
  post-removal via `vim.schedule`) GCs dynamic names with no remaining started
  session and resets `M.active` if its session is gone. Without it, a session
  that *exits on its own* (user types `exit`, claude crashes → TermClose →
  `close()`) leaves a stale name in the `<leader>as` launcher **and** a stale
  `M.active` — so `<leader>aa` would silently spawn a *fresh* session under
  the old name where the user expected their conversation. That failure mode
  is why this can't stay a TODO. To avoid GC'ing a name whose spawn is still
  in flight (registration → attach spans a few scheduled hops),
  `M._dynamic[name]` is a two-state marker: `'registered'` at creation,
  flipped to `'started'` on first `SidekickCliAttach`; the sweep forgets
  `'started'` entries once their session is gone, and a `'registered'` entry
  only once it has *neither* a started session nor a terminal — so a spawn
  that never attaches (missing binary, jobstart failure) is still GC'd instead
  of leaking a name that `M.active` would keep auto-respawning, while genuinely
  in-flight spawns (terminal exists, attach pending) are preserved.
- **`claude` (#1) stays the default + the only pre-warmed session.** Sessions
  2+ cold-start (~1–2s) on first open. Acceptable; generalizing the pre-warm to
  N sessions is explicitly out of scope here.
- **State ownership**: `ai.lua` owns the sidekick-internals knowledge, the
  `active`/`_dynamic` state, and all helpers (including the `send`/`focus`
  routing wrappers); `keymaps.lua` and `plugins.lua`'s `<M-a>` hold only thin
  outside-entry-point bindings (matches the existing split noted at
  `keymaps.lua:285-287`). Routing through `require('ai')` also improves the
  first-launch packadd race: the stubs `vim.notify` instead of the hard
  `require('sidekick.cli')` error the direct bindings throw today.

### Known behavioral edges (documented, not fixed)

- **Same name in two cwds → `<leader>aa` may pop a picker.** Identity is
  `(name, cwd)` but the toggle *filter* is name-only (state.lua:42). Open
  `claude` in project A, `:cd` to B, open `claude` again → two attached
  `claude` sessions → `#attached > 1` → sidekick shows a disambiguation picker
  (state.lua:165). Applies to the **default** `claude` too, not just dynamic
  names. A non-issue in normal single-project use; noted so the occasional
  picker isn't mistaken for a bug.
- **Very long labels collapse identity across cwds.** `session/init.lua:107`
  slices `sha256(cwd):sub(1, 16 - #tool)`; for `#name >= 16` the slice is
  empty, so the same label used from two different cwds is **one sid**: not
  the disambiguation-picker case above, but a *silent* re-attach to the other
  project's session — and since `M.terminals` is keyed by id
  (terminal.lua:110), a colliding fresh spawn would overwrite the registry
  entry and orphan the old job. Names of 13–15 chars keep only 1–3 hex chars
  of hash (weakened, not gone). Mitigated by the `new_session` length warning;
  fully correct behavior needs the mux-style identity rework, out of scope.

## Implementation

### 1. `nvim/.config/nvim/lua/ai.lua`

**a. Export a module table** with race-safe method stubs (so keymaps can reach
the helpers even on the first-launch packadd race, where the real definitions
below never run). Currently the file returns nothing and early-`return`s on the
race. Change to:

```lua
-- top of file, before the packadd pcall:
local M = { active = 'claude', _dynamic = {} }

-- Stub the public methods so a keypress during the first-launch packadd race
-- notifies instead of throwing "attempt to call a nil value". The real
-- definitions below overwrite these once sidekick has loaded.
local function not_ready()
  vim.notify('sidekick.nvim still loading — retry after restart', vim.log.levels.WARN)
end
M.toggle_active, M.new_session, M.switch, M.kill_active, M.focus, M.send =
  not_ready, not_ready, not_ready, not_ready, not_ready, not_ready
...
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return M end            -- was: return end
...
-- very end of file:
return M
```

`active` defaults to `'claude'` so everything works before any session is
entered; `_dynamic` maps names we registered → `'registered' | 'started'`
(only these are ever removed from `cli.tools`).

**b. Track the active session on WinEnter** (new autocmd in the existing
`UserSidekick` augroup). Sidekick stamps CLI windows at open
(terminal.lua:385); the pre-warm float is never entered, so no pre-warm guard
is needed:

```lua
vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  desc = 'Sidekick: track active CLI session',
  callback = function()
    local tool = vim.w[vim.api.nvim_get_current_win()].sidekick_cli
    if tool and tool.name then M.active = tool.name end
  end,
})
```

**c. Fix + extend the `SidekickCliAttach` autocmd.** Two edits to the existing
promote-to-full-height handler:

- **Correct the stale comment**: the event fires once per session lifetime
  (first attach; emit at session/init.lua:194 behind the already-attached
  early return at :171) — it does *not* fire on re-shows. Promotion of the
  first show is all it has ever done; re-shows land full-height on their own
  (verification step 10 re-checks).
- **Flip `_dynamic` to `'started'`** so the detach sweep knows the spawn
  completed (reuse the `terminal.get` call already there).
- **Stamp tripwire.** WinEnter tracking (part b) reads the `sidekick_cli`
  window var sidekick stamps at open (terminal.lua:385). That stamp is the one
  internal whose loss fails *silently* — if upstream stops setting it, WinEnter
  never updates `M.active` and sends mis-route to a stale session with no error
  (see "The internals this leans on"). A first attach means a CLI window just
  opened, so the stamp *should* be present; if it isn't, notify once per nvim
  run. Verification step 4 also covers this at implement-time — the tripwire is
  the backstop for a *future* upstream change we won't re-verify against.

```lua
if _G.__sidekick_prewarm then return end
local term = require('sidekick.cli.terminal').get(args.data.id)
if term and term.tool and M._dynamic[term.tool.name] == 'registered' then
  M._dynamic[term.tool.name] = 'started'
end
-- Silent-surface tripwire: on the first attach where the expected window
-- stamp is missing, warn loud once — active-session tracking is broken.
if not _G.__sidekick_stamp_ok and term and term.win
   and vim.api.nvim_win_is_valid(term.win)
   and vim.w[term.win].sidekick_cli == nil then
  vim.notify('sidekick: CLI window stamp (sidekick_cli) missing — active-session tracking is broken, sends may mis-route',
    vim.log.levels.ERROR)
  _G.__sidekick_stamp_ok = true   -- fire once per nvim run, not per attach
end
local layout = require('sidekick.config').cli.win.layout
local side = layout == 'right' and 'right' or layout == 'left' and 'left' or nil
if not side then return end
if term then utils.promote_to_full_height(term.win, side) end
```

**d. The detach sweep** (new autocmd; the event is emitted post-removal via
`vim.schedule`, so `State.get` reads post-detach state here):

```lua
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
```

(Removing the *current* key during `pairs` is safe in Lua; `_forget` only ever
removes the name it's given.)

**e. Add the helpers** (place after the `setup{}` block; these overwrite the
stubs from part a):

```lua
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
local function create_session(name)
  local cfg = require('sidekick.config')
  if not cfg.cli.tools[name] then
    -- Clone claude's resolved preset (cmd + format + resume/continue), not a
    -- bare { cmd = {'claude'} } — see plan "clone the preset".
    cfg.cli.tools[name] = vim.deepcopy(require('sidekick.cli.tool').get('claude').config)
    M._dynamic[name] = 'registered'   -- 'started' once the first attach fires
  end
  M.active = name  -- eager; WinEnter confirms once the window is entered
  require('sidekick.cli').show({ name = name, focus = true })
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
  local cli            = require('sidekick.cli')
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
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        if entry then
          M.active = entry.value.tool.name  -- eager; WinEnter confirms on focus
          cli.show({ name = entry.value.tool.name, focus = true })
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
```

Note: `State.get` (state.lua:69) is public and returns `sidekick.cli.State`
objects whose `.tool.name` is the session name and whose lazy metatable
resolves `terminal`/`attached` at access time, so `State.detach(entry.value)`
works on entries captured at finder time.

### 2. `nvim/.config/nvim/lua/keymaps.lua`

Replace the current hardcoded `<leader>aa` (keymaps.lua:308), add two
bindings, re-point `<leader>ad` (keymaps.lua:319) at `kill_active`, and
**re-point every unfiltered sidekick call at the `ai` wrappers** —
`<C-.>`/`<leader>ai` (:303-306), the send keys (:331-355), and `<leader>ao`
(:323). `<leader>al`/`<leader>an` are free (`a`-prefix keys in use:
a,i,s,d,o,t,p,f,c,e,b,q). Keep `<leader>as` (`select()`) as the full **tool
launcher** — it needs no routing (it *chooses* a target) and WinEnter tracking
makes whatever it launches/focuses the active session.

```lua
vim.keymap.set({ 'n', 't', 'i', 'x' }, '<C-.>',
  function() require('ai').focus() end, { desc = 'AI: Focus active CLI' })
vim.keymap.set('n', '<leader>ai',
  function() require('ai').focus() end, { desc = 'AI: Focus active CLI (fallback for <C-.>)' })

vim.keymap.set('n', '<leader>aa',
  function() require('ai').toggle_active() end,
  { desc = 'AI: Toggle active CLI session' })
vim.keymap.set('n', '<leader>an',
  function() require('ai').new_session() end,
  { desc = 'AI: New Claude session' })
vim.keymap.set('n', '<leader>al',
  function() require('ai').switch() end,
  { desc = 'AI: Switch/kill running CLI session' })   -- <CR> switch, <C-d> kill
```

Update the existing `<leader>ad` block (keep its confirm popup):

```lua
vim.keymap.set('n', '<leader>ad', function()
  require('utils').confirm('Kill active CLI session? (Tears down the terminal and session state)',
    function() require('ai').kill_active() end)
end, { desc = 'AI: Kill active CLI session' })
```

Sends become `require('ai').send({ msg = '{this}' })` etc. (same table
arguments as today, just the module swapped). `<leader>ao` keeps sidekick's
prompt picker but routes the chosen prompt through the wrapper (the default
callback is an unfiltered `cli.send` — cli/init.lua:62):

```lua
vim.keymap.set('n', '<leader>ao', function()
  require('sidekick.cli').prompt({ cb = function(_, text)
    if text then require('ai').send({ text = text }) end
  end })
end, { desc = 'AI: Select prompt' })
```

### 3. `nvim/.config/nvim/lua/plugins.lua` — `<M-a>` picker send

`plugins.lua:412`'s `send_to_sidekick` calls `require('sidekick.cli').send`
directly — swap for `require('ai').send({ msg = table.concat(refs, ' ') })`
so picker sends target the active session too.

### 4. `nvim/.config/nvim/GUIDE.md` — same change (repo rule)

Per the nested `nvim/.config/nvim/CLAUDE.md` ("Update GUIDE.md in the same
change"), update the `## AI (sidekick.nvim)` section (`GUIDE.md:1609`):

- **Rewrite the stale single-session prose at `GUIDE.md:1630-1633`.** It
  currently reads "opens Claude in a terminal split. `<leader>aa` toggles
  Claude … `<leader>as` switches to a different CLI tool. `<leader>ad` tears
  down the session entirely." Replace with the multi-session model, leading
  with the **active session** concept: the CLI session whose window you last
  entered (default `claude`); `<leader>aa` toggles it, `<leader>ad` kills it,
  and **all send keys, `<leader>ao`, `<M-a>`, and `<C-.>`/`<leader>ai` target
  it** — with several sessions running, sends never ask which one.
  `<leader>an` spawns a new session (blank = auto-numbered, label = reusable
  named session); `<leader>al` opens a telescope picker to **switch** (`<CR>`,
  which also makes it active) or **kill** (`<C-d>`) running sessions;
  `<leader>as` stays the **tool launcher** (start Copilot/Gemini/etc.),
  distinct from `<leader>al`.
- **Update the keymap table** (`GUIDE.md:1635-1653`): reword the
  `<C-.>`/`<leader>ai` rows to "Focus **active** CLI"; change the `<leader>aa`
  row to "Toggle active CLI session"; add `<leader>an` ("New Claude session —
  blank prompt = auto-numbered, label = named/reusable") and `<leader>al`
  ("Switch (`<CR>`) or kill (`<C-d>`) a running CLI session (telescope)");
  reword `<leader>as` to "**Launch** a CLI tool (copilot, gemini, …)" so it
  reads as distinct from `<leader>al`; reword `<leader>ad` to "Kill **active**
  CLI session …". The send-key rows keep their action text (their *target* is
  covered once in the prose — don't repeat "active session" in every row).
  Feature-specific keys stay in this table, not the Keymap index ("Keymap
  ownership rule").
- **Add a short prose note** (near the rewritten block): sessions are keyed by
  `(tool name, cwd)`; extra sessions are dynamically-registered tool names
  cloned from the `claude` preset; only `claude` #1 is pre-warmed; killed
  names are auto-unregistered (detach sweep) and re-creating one starts a
  fresh conversation; long labels (≥16 chars) trigger a warning about
  cross-cwd identity; nothing persists across restart without mux.
- No new module and no `init.lua` `require()` change → no `Architecture` /
  `Load order` edit needed. `<leader>al`/`<leader>an` start no new prefix
  family (still `a`), so the *By prefix* table is unchanged. `## AI
  (sidekick.nvim)` already carries an explicit anchor and isn't being renamed
  → no anchor-hygiene action.

## Verification

1. `<leader>aa` → pre-warmed `claude` shows. `<leader>an` → Enter → `claude 2`
   opens as a second independent session, focused. `<leader>an` → type `tests`
   → `claude: tests` opens.
2. `<leader>an` → type `tests` **again** while `claude: tests` is *visible* →
   it stays visible and gains focus (show-not-toggle: must not hide).
3. `<leader>al` → picker lists running sessions with their cwd; `<CR>`
   switches to the highlighted one **and** a following `<leader>at` sends to
   it (active followed the switch). `<C-d>` tears one down and it disappears
   from the list **immediately** (same keypress — no stale entry); a moment
   later it's gone from `<leader>as`'s launcher too (sweep GC'd it). Kill the
   built-in `claude` via `<C-d>` and confirm `claude` is still in the launcher
   (built-ins never GC'd).
4. Active follows window entry: `<C-w>w` (or click) into `claude 2`'s window,
   move back to a code window, `<leader>aa` → toggles `claude 2`. Switch to
   #1 via `<leader>al`, `<leader>aa` → toggles #1.
5. With two sessions running, `<leader>at`/`<leader>ap`/`<C-.>`/`<leader>ao`/
   `<M-a>` act on the active session directly — **no disambiguation picker**.
6. `<leader>ad` → confirm popup → kills the active session; afterwards
   `<leader>aa` toggles `claude` #1 (sweep reset `active`), and the killed
   dynamic name is gone from the launcher.
7. Self-exit: type `exit` inside `claude 2` → its name leaves the launcher and
   `<leader>aa` toggles #1 — it must **not** silently respawn a fresh
   `claude 2`. (Upstream edge, not a regression: `terminal.lua`'s `close()`
   suppresses teardown when the process exits within ~500ms of last activity
   — or errors within ~3s — leaving a "started" session with a dead job and
   **no** detach event, so the sweep never runs and `<leader>aa` toggles a
   corpse. If `claude` exits that fast, interact with it once before typing
   `exit` and retry; don't misdiagnose it as this change's bug.)
8. `<leader>an` with a ≥16-char label → warning notification, session still
   opens and works.
9. Confirm each session is a distinct process (`:!pgrep -fl claude` shows N).
10. Hide/re-show and picker-switching keep every CLI full-height at the right
    edge (re-checks the promotion-on-reshow assumption now that the attach
    event is known to fire only once per session).
11. Context formatting survives the clone: with `claude 2` active, visually
    select code and `<leader>at` (or send a `{file}` ref via `<leader>af`) →
    `claude 2` receives a claude-friendly `@file#Lx-y`-style reference, **not**
    raw pasted text. This is the one behavior the "clone the preset" work
    exists to preserve, and nothing else in this list exercises it.

## Out of scope / follow-ups

- **Persistence across nvim restart** → that's the mux backend
  (`cli.mux.enabled = true`, `backend = 'zellij'`); it interacts heavily with
  the pre-warm/stickybuf/`sidekick_terminal` machinery and is a separate
  decision. See `plans/sidekick-windowless-prewarm.md`.
- **Pre-warming sessions 2+** (the cold-start on first open of extras).
- (The auto-GC of `cli.tools` that used to sit here is now the v1 detach
  sweep — see Design decisions.)

## Still consider — fixed pre-named pool (rejected for now, revisit if the
dynamic approach frets)

Instead of mutating `Config.cli.tools` at runtime, register a **fixed pool** of
pre-named aliases once at `setup()` — `claude`, `claude 2`, … `claude N` (say
N=5–9) — each cloned from the claude preset. `<leader>an` would then cycle to
the next unused pool slot rather than minting a name.

Trade-offs vs. the chosen dynamic approach:

- **For the pool:** no runtime config mutation; no `cli.tools` growth (the
  detach sweep *and* the `_dynamic` marker disappear); a bounded, predictable
  `<leader>as` launcher list; simpler mental model. It also deletes most of the
  internal-surface mutation flagged in "The internals this leans on", not just
  the sweep/marker.
- **Against the pool:** a hard cap (the very "hardcode 5" the user rejected);
  no meaningful labels (`claude: tests`) — pool slots are just numbers; unused
  slots clutter the launcher list from the start.

Rejected because the user explicitly wanted **unbounded, name-as-you-go**
sessions and labels. Worth revisiting only if the dynamic approach's moving
parts prove more annoying than a fixed cap.

## Decided against

- **Tracking the active session via `SidekickCliAttach`.** The event fires
  once per session lifetime (emit at session/init.lua:194 behind the
  already-attached early return at :171; terminal `hide()` never detaches), so
  switching to a running session would never update it — the headline
  "`<leader>aa` toggles what I'm using" would break the moment you switched.
  WinEnter tracking covers every switch path for free.
- **Claude-only active tracking.** With sends routed to the active session, a
  claude-only tracker would mis-route `<leader>at` to claude while you're
  working in a copilot session you just switched to. Generic tracking keeps
  "active = the session in use" literally true across tools. (If `<leader>aa`
  toggling a non-claude tool ever feels wrong in practice, revisit — it's a
  one-line filter in the WinEnter callback.)
- **Strictly claude-only switch picker.** `<leader>al`'s custom telescope
  picker lists all *in-nvim* running sidekick sessions (the `started` filter),
  not just `claude*`. Now that the picker is hand-rolled (for `<C-d>` delete),
  claude-only would be a trivial `tool.name:match('^claude')`, but the user
  confirmed all-sessions is fine. See "What the switcher does NOT show" for why
  external sessions don't leak in the zellij setup.
- **Hanging `<C-d>` off sidekick's `select()`.** Not possible — `select()` is
  `vim.ui.select` with no action hooks (see "The switch picker"); the custom
  telescope picker is the reason `<leader>al` doesn't reuse `select()`.
- **`cli.close()` in the `<C-d>` handler.** Two `vim.schedule` hops late for a
  same-tick `picker:refresh` (see "`<C-d>` teardown must be synchronous");
  `State.detach(entry.value)` is the synchronous equivalent. `<leader>ad`
  keeps `cli.close({name})` since nothing there needs same-tick state.
- **Rejecting long labels outright.** `'claude: '` alone is 8 chars, so a hard
  `#name < 16` cap would limit labels to 7 chars. Warn-and-proceed instead;
  the collision needs same-label-from-a-second-cwd in one nvim run to bite.
