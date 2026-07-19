# Multiple Claude sessions in sidekick (no mux, dynamic — not hardcoded)

> **Status:** shipped; shrunk to reference core + runbook 2026-07-18. The
> Implementation and Verification sections were removed — shipped code in
> `ai.lua` is the source of truth (see the Implementation stub below).

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
   was wrong** ("SidekickCliAttach fires on every show path … covers internal
   re-shows"); fixed as part of this change. Empirically re-shows land
   full-height without re-promotion (hide/show toggling works, and attach
   never re-fires), so no functional change — verified under session
   switching at ship time.

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
clone shape (shipped in `ai.lua`) surfaces a preset-shape break at startup
without hard-erroring (an `assert` would throw before `ai.lua`'s `return M`
and take every AI keymap down over a formatting-only regression), and the
`SidekickCliAttach` handler carries a `notify`-once tripwire (also in
`ai.lua`) — "first attach but no `sidekick_cli` window stamp → warn loud
once" — so a future upstream change that drops the stamp surfaces immediately
instead of silently mis-routing sends.
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
- **Upstream self-exit edge: a fast exit can leave a corpse.** `terminal.lua`'s
  `close()` suppresses teardown when the process exits within ~500ms of last
  activity — or errors within ~3s — leaving a "started" session with a dead
  job and **no** detach event, so the sweep never runs and `<leader>aa`
  toggles a corpse. Normal self-exit (type `exit` after interacting) tears
  down cleanly: the name leaves the launcher and `<leader>aa` falls back to
  #1 without silently respawning. If `claude` exits that fast, interact with
  it once before typing `exit` — don't misdiagnose the corpse as this
  design's bug.

## Implementation

Shipped in `ai.lua` — code is the source of truth (the shipped picker is
snacks-based `indexed_select`, not the telescope picker specced here; see git
history for the original spec, along with the verification checklist and the
keymaps/plugins/GUIDE.md edit plan).

## Performance — the shell-out session backends

**Symptom: nvim freezes up to ~0.6s when you cycle (`<M-]>`), toggle (`<C-]>`)
or tear down a session.** Found 2026-07-12, fixed in `88cb662`. Start here for
any sidekick hang.

### Root cause

`State.get()` — which this design leans on everywhere (`fallback_active`, the
detach sweep, `M.switch`, `M.cycle`, `M.toggle_last`) — runs **every registered
backend's `sessions()`** synchronously on the main thread (`Util.exec` is
`vim.system(cmd):wait()`, and nvim has no separate UI thread). Three of them
shell out, none of which we asked for:

| backend | registered because | blocking call | cost |
|---|---|---|---|
| `opencode` | load side-effect of its tool spec, `dofile`d since it's in the default `cli.tools` | `lsof -iTCP -sTCP:LISTEN` | ~41 ms |
| `tmux` | `executable('tmux') == 1` alone — **not** `cli.mux.enabled` | `ps` scan + `list-panes`/`list-clients` | ~41 ms |
| `zellij` | `executable('zellij') == 1` alone — same | `zellij list-sessions` | ~21 ms |
| `terminal` | always; the one we use | none (in-memory registry) | ~0 ms |

`mux.enabled = false` does **not** prevent registration — it only picks the
backend for *new* sessions. Discovery runs regardless.

Then the **multiplier**: the detach sweep issues up to 2 `State.get` per dynamic
name, +1 for `M.active`, +2 in `fallback_active` — **9 calls** with 3 forked
sessions. Measured with tmux + zellij + lsof all present:

| | before | after `88cb662` |
|---|---|---|
| `State.get()` | 65 ms | 0.05 ms |
| `<M-]>` cycle | 65 ms | 0.03 ms |
| detach sweep (3 sessions) | ~590 ms | 0.17 ms |

**This is why identical code hangs differently per machine**: with no mux binary
only `opencode` registers (41 ms); install tmux — as the README tells you to,
for claude-squad — and it's 65 ms.

### The fix

`ai.lua` stubs those backends' `sessions()` to `{}` and prunes `cli.tools` to
`claude`. Only *external* session discovery is lost; starting and attaching from
nvim is untouched. See GUIDE.md "Sidekick's session backends shell out on every
lookup" for the three constraints (stub-never-nil; `Session.setup()` must run
before the stub or it's silently reversible; skip tmux/zellij when mux is
actually enabled).

### Diagnostic runbook

```sh
cd ~/src/dotfiles && git log --oneline -1 && \
git log --oneline -1 88cb662 2>/dev/null || echo "!! perf fix NOT pulled"; \
echo "tmux:   $(command -v tmux   || echo 'not installed')"; \
echo "zellij: $(command -v zellij || echo 'not installed')"; \
env -u NVIM nvim --headless \
  -c 'lua local S=require("sidekick.cli.session") S.setup() print("backends: "..table.concat(vim.tbl_keys(S.backends),", ")) local t0=vim.uv.hrtime() for _=1,20 do require("sidekick.cli.state").get({started=true}) end print(("State.get: %.1f ms"):format((vim.uv.hrtime()-t0)/1e6/20))' \
  -c 'qa!'
```

- `State.get` **above ~1 ms** → a shell-out backend is live; if the fix isn't
  pulled, `git pull`.
- Backends staying *listed* post-fix is correct — only `sessions()` is stubbed.
  Nil-ing them would trip `Session.new`'s `assert` if mux were enabled.
- `env -u NVIM` is mandatory, or flatten.nvim routes the probe into your live
  nvim and reports nothing useful.

### Open follow-ups (only matter if mux is ever enabled)

- **Collapse the sweep's 9 `State.get` calls to 1.** Each is a filtered view of
  the same snapshot — the filter runs *after* a full enumeration, so it buys
  nothing. One snapshot + table lookups would take mux's sweep from ~190ms to
  ~21ms, and immunize this design against whatever backend upstream registers
  next. Deferred: at 0.05ms/call it changes nothing today.
- **Async discovery** for the rest: have `sessions()` return the last-known list
  instantly and refresh via `vim.system(cmd, opts, callback)` (no `:wait()`) —
  sidekick already does this in `status.lua` (5s TTL). Threads are *not* the
  answer: `vim.uv` threads get a separate Lua state with no `vim.api`, and the
  work is a subprocess anyway — only `:wait()` blocks.

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
- **Strictly claude-only switch picker.** `<leader>al`'s custom picker lists
  all *in-nvim* running sidekick sessions (the `started` filter), not just
  `claude*`. Now that the picker is hand-rolled (for `<C-d>` delete),
  claude-only would be a trivial `tool.name:match('^claude')`, but the user
  confirmed all-sessions is fine. See "What the switcher does NOT show" for why
  external sessions don't leak in the zellij setup.
- **Hanging `<C-d>` off sidekick's `select()`.** Not possible — `select()` is
  `vim.ui.select` with no action hooks (see "The switch picker"); the custom
  picker is the reason `<leader>al` doesn't reuse `select()`.
- **`cli.close()` in the `<C-d>` handler.** Two `vim.schedule` hops late for a
  same-tick `picker:refresh` (see "`<C-d>` teardown must be synchronous");
  `State.detach(entry.value)` is the synchronous equivalent. `<leader>ad`
  keeps `cli.close({name})` since nothing there needs same-tick state.
- **Rejecting long labels outright.** `'claude: '` alone is 8 chars, so a hard
  `#name < 16` cap would limit labels to 7 chars. Warn-and-proceed instead;
  the collision needs same-label-from-a-second-cwd in one nvim run to bite.
