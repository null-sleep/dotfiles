# Multiple Claude sessions in sidekick (no mux, dynamic — not hardcoded)

## Goal

Run several independent `claude` CLI sessions in one nvim instance and switch
between them, **without** the mux (tmux/zellij) backend and **without**
pre-declaring a fixed count. Concretely:

- `<leader>aa` — toggle the **last-used** Claude session (defaults to the
  pre-warmed `claude`).
- `<leader>an` — spawn/attach a Claude session, created on demand (unbounded).
  Prompt for a label; **blank Enter = auto-numbered** (always a *new* session);
  a **typed label re-attaches** if it already exists (reusable/named); `<Esc>`
  cancels.
- `<leader>al` — **switch** between currently-running CLI sessions via a
  **custom telescope picker**. `<CR>` shows/focuses the session; **`<C-d>`
  tears down** the highlighted session (telescope's delete convention) and, if
  it's a dynamically-registered name, drops it from `cli.tools`.
- `<leader>ad` — kill the **last-used** session (was: kill the single CLI),
  behind the existing confirm popup.

Each session is a *separate* `claude` process (separate conversation/context),
living in an nvim-owned scratch terminal. Sessions persist across hide/show
within an nvim run and die on nvim exit (consistent with the no-mux choice —
nothing survives restart without mux). Reviving a torn-down name re-spawns a
**fresh** conversation (no `--resume`) — see Design decisions.

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
makes that name immediately toggle-able and visible in the picker. No fixed
cap, no pre-declaration. This is the mechanism that replaces "hardcode 5".

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
(`vim.deepcopy` preserves the `format` function by reference). This inherits
whatever claude's real spec is, now and after upstream changes.

### `toggle({name})` auto-starts a named tool — no stray picker

`state.lua` `M.with` (used by `toggle`/`focus`):

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
So `toggle({ name = last_claude, focus = true })` works whether or not that
session is currently running, as long as the name is registered in
`cli.tools` — which `<leader>an` guarantees for the session lifetime, so
`<leader>aa` can even revive a torn-down `claude 2`.

### No "last used" tracking exists — we maintain it

`state.lua` sorts by installed/cwd/started, **not** recency. So "toggle the
last-used claude" is not native; we record it ourselves off the
`SidekickCliAttach` event (fires on every show/toggle/focus).

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
started = true })`:

- `<CR>` → `cli.show({ name, focus = true })` (switch to it).
- `<C-d>` → `cli.close({ name })` **plus** drop the name from `cli.tools` if we
  registered it dynamically (never the built-in `claude`) — this is the
  interactive GC that partially addresses the `cli.tools`-growth leak below,
  then `picker:refresh()` in place.

Scope stays **all running in-nvim sidekick sessions** (not claude-only) per the
user's preference — Copilot/Codex started in this nvim appear too. Now that the
picker is custom, claude-only filtering would be a one-line `tool.name:match`,
but we deliberately keep it all-sessions.

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
    and matches each proc against a tool's `is_proc` regex (claude's is
    `\<claude\>`). → it would surface **any** claude in **any** tmux pane, even
    one started by hand, as an attachable external session.
  - **Gotcha:** because registration is executable-gated, **installing tmux on
    this machine — even without using it as sidekick's mux — would start
    leaking tmux-pane claude processes into `<leader>al`.** Not a concern today
    (no tmux here); recorded so it isn't a surprise later.
- Plain `claude` in a bare terminal (no mux) is discoverable by neither backend.

Net: sessions stay nvim-managed as intended; `<leader>al` showing all *in-nvim*
sidekick sessions is the accepted behavior, not a compromise to revisit.

## Design decisions locked

- **Naming (`<leader>an`)**: prompt via `vim.ui.input`; **blank Enter →
  auto-numbered** (`claude 2`, `claude 3`, …), a typed label → `claude: <label>`
  (e.g. `claude: tests`), `<Esc>`/`nil` → cancel. (User-selected.)
- **Labels are reusable (re-attach, not error/dup).** `<leader>an` → `tests`
  twice lands on the *same* `claude: tests` session — the `if not
  cli.tools[name]` guard makes named sessions idempotent. This is intended:
  labels name a durable session you can return to; only blank-Enter
  auto-numbering guarantees a brand-new session. (User-decided.)
- **Revival re-spawns fresh (no `--resume`).** `<leader>aa`/`<leader>an`
  re-opening a torn-down name starts a new `claude` process with an empty
  conversation — the old context is gone with the killed process. Accepted
  (documented so it isn't a surprise). (User-decided.)
- **`claude` (#1) stays the default + the only pre-warmed session.** Sessions
  2+ cold-start (~1–2s) on first open. Acceptable; generalizing the pre-warm to
  N sessions is explicitly out of scope here.
- **`cli.tools` growth is accepted for now.** Dynamic names accumulate for the
  nvim lifetime (die on restart); `<C-d>` in `<leader>al` GCs individual dead
  entries, but there's no automatic sweep. A TODO to auto-GC is filed under
  Out of scope. (User-decided.)
- **State ownership**: `ai.lua` owns the sidekick-internals knowledge and the
  `last_claude` state + the helper functions; `keymaps.lua` holds only the thin
  outside-entry-point bindings (matches the existing split noted at
  `keymaps.lua:285-287`).

### Known behavioral edges (documented, not fixed)

- **Same name in two cwds → `<leader>aa` may pop a picker.** Identity is
  `(name, cwd)` but the toggle *filter* is name-only (state.lua:42). Open
  `claude` in project A, `:cd` to B, open `claude` again → two attached
  `claude` sessions → `#attached > 1` → sidekick shows a disambiguation picker
  (state.lua:165). Applies to the **default** `claude` too, not just dynamic
  names. A non-issue in normal single-project use; noted so the occasional
  picker isn't mistaken for a bug.
- **Very long labels erode the `sid` cwd-hash.** `session/init.lua:107` slices
  `sha256(cwd):sub(1, 16 - #tool)`; for `#name ≥ 16` the slice is empty, so the
  cwd component of the id effectively vanishes. Harmless with the terminal
  backend (names differ ⇒ no `sid` collision, no `session/init.lua:142`
  duplicate-assert), but it would matter if a mux backend is ever enabled.
  Cosmetic today.

## Implementation

### 1. `nvim/.config/nvim/lua/ai.lua`

**a. Export a module table** with race-safe method stubs (so keymaps can reach
the helpers even on the first-launch packadd race, where the real definitions
below never run). Currently the file returns nothing and early-`return`s on the
race. Change to:

```lua
-- top of file, before the packadd pcall:
local M = { last_claude = 'claude', _dynamic = {} }

-- Stub the public methods so a keypress during the first-launch packadd race
-- notifies instead of throwing "attempt to call a nil value". The real
-- definitions below overwrite these once sidekick has loaded.
local function not_ready()
  vim.notify('sidekick.nvim still loading — retry after restart', vim.log.levels.WARN)
end
M.toggle_last, M.new_session, M.switch, M.kill_last = not_ready, not_ready, not_ready, not_ready
...
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return M end            -- was: return end
...
-- very end of file:
return M
```

`last_claude` defaults to `'claude'` so `<leader>aa` works before any attach
fires; `_dynamic` is the set of names we registered ourselves (only these are
safe to delete from `cli.tools`); the stubs keep the race path from erroring.

**b. Track the last-shown claude in the `SidekickCliAttach` autocmd.** Reuse
the single `terminal.get()` call already there; track *before* the `side`-nil
early return so float layouts are covered too:

```lua
if _G.__sidekick_prewarm then return end
local term = require('sidekick.cli.terminal').get(args.data.id)
-- Record the most-recently-shown claude* session so <leader>aa toggles it.
if term and term.tool and tostring(term.tool.name):match('^claude') then
  M.last_claude = term.tool.name
end
local layout = require('sidekick.config').cli.win.layout
local side = layout == 'right' and 'right' or layout == 'left' and 'left' or nil
if not side then return end
if term then utils.promote_to_full_height(term.win, side) end
```

(The pre-warm branch already returns early; its session is `claude`, which is
the default anyway, so nothing to track there.)

**c. Add the helpers** (place after the `setup{}` block; these overwrite the
stubs from part a):

```lua
function M._next_auto_name()
  local tools = require('sidekick.config').cli.tools
  local n = 2
  while tools['claude ' .. n] do n = n + 1 end
  return 'claude ' .. n
end

-- Register a dynamic claude tool (if new) and show it. Re-registering an
-- existing name is a no-op → labels re-attach (see "Labels are reusable").
local function create_session(name)
  local cfg = require('sidekick.config')
  if not cfg.cli.tools[name] then
    -- Clone claude's resolved preset (cmd + format + resume/continue), not a
    -- bare { cmd = {'claude'} } — see plan "clone the preset".
    cfg.cli.tools[name] = vim.deepcopy(require('sidekick.cli.tool').get('claude').config)
    M._dynamic[name] = true   -- mark ours, so <C-d>/kill can GC it later
  end
  M.last_claude = name
  require('sidekick.cli').toggle({ name = name, focus = true })
end

-- Drop a dynamically-registered name from cli.tools. Never touches built-ins
-- (claude/copilot/…) — only names we added via create_session.
function M._forget(name)
  if not M._dynamic[name] then return end
  require('sidekick.config').cli.tools[name] = nil
  M._dynamic[name] = nil
  if M.last_claude == name then M.last_claude = 'claude' end
end

function M.new_session()
  vim.ui.input({ prompt = 'New Claude session (blank = auto): ' }, function(input)
    if input == nil then return end                       -- <Esc> cancels
    local name = input ~= '' and ('claude: ' .. input) or M._next_auto_name()
    create_session(name)
  end)
end

function M.toggle_last()
  require('sidekick.cli').toggle({ name = M.last_claude, focus = true })
end

-- <leader>ad target: tear down the last-used session specifically (avoids the
-- unfiltered cli.close() → disambiguation-picker behaviour with 2+ sessions).
function M.kill_last()
  require('sidekick.cli').close({ name = M.last_claude })
  M._forget(M.last_claude)
end

-- <leader>al: custom telescope picker over running sidekick sessions.
-- <CR> shows/focuses; <C-d> tears down + GCs the highlighted session.
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
        return { value = s, display = name, ordinal = name }
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
        if entry then cli.show({ name = entry.value.tool.name, focus = true }) end
      end)
      map({ 'i', 'n' }, '<C-d>', function(pbuf)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local name = entry.value.tool.name
        cli.close({ name = name })
        M._forget(name)
        action_state.get_current_picker(pbuf):refresh(finder(), { reset_prompt = false })
      end)
      return true
    end,
  }):find()
end
```

Note: `State.get` (state.lua:67) is public and returns `sidekick.cli.State`
objects whose `.tool.name` is the session name; `cli.close({ name })` /
`cli.show({ name })` target that exact session.

### 2. `nvim/.config/nvim/lua/keymaps.lua`

Replace the current hardcoded `<leader>aa` (around `keymaps.lua:308`), add two
bindings, and re-point the existing `<leader>ad` (around `keymaps.lua:319`) at
`kill_last`. `<leader>al`/`<leader>an` are free (`a`-prefix keys in use:
a,i,s,d,o,t,p,f,c,e,b,q). Keep `<leader>as` (`select()`) as the full **tool
launcher**; `<leader>al` is the **running-session switcher**.

```lua
vim.keymap.set('n', '<leader>aa',
  function() require('ai').toggle_last() end,
  { desc = 'AI: Toggle last Claude session' })
vim.keymap.set('n', '<leader>an',
  function() require('ai').new_session() end,
  { desc = 'AI: New Claude session' })
vim.keymap.set('n', '<leader>al',
  function() require('ai').switch() end,
  { desc = 'AI: Switch/kill running CLI session' })   -- <CR> switch, <C-d> kill
```

And update the existing `<leader>ad` block to target the last-used session
(keep its confirm popup):

```lua
vim.keymap.set('n', '<leader>ad', function()
  require('utils').confirm('Kill last CLI session? (Tears down the terminal and session state)',
    function() require('ai').kill_last() end)
end, { desc = 'AI: Kill last CLI session' })
```

### 3. `nvim/.config/nvim/GUIDE.md` — same change (repo rule)

Per the nested `nvim/.config/nvim/CLAUDE.md` ("Update GUIDE.md in the same
change"), update the `## AI (sidekick.nvim)` section (`GUIDE.md:1607`):

- **Rewrite the stale single-session prose at `GUIDE.md:1626-1629`.** It
  currently reads "opens Claude in a terminal split. `<leader>aa` toggles
  Claude … `<leader>as` switches to a different CLI tool. `<leader>ad` tears
  down the session entirely." Replace with the multi-session model: `<leader>aa`
  toggles the **last-used** Claude session; `<leader>an` spawns a new one
  (blank = auto-numbered, label = reusable named session); `<leader>al` opens a
  telescope picker to **switch** (`<CR>`) or **kill** (`<C-d>`) running
  sessions; `<leader>as` is the **tool launcher** (start Copilot/Gemini/etc.),
  distinct from `<leader>al`; `<leader>ad` kills the **last-used** session.
- **Update the keymap table** (`GUIDE.md:1631-1649`): change the `<leader>aa`
  row (1638) to "Toggle last-used Claude session"; add `<leader>an` ("New
  Claude session — blank prompt = auto-numbered, label = named/reusable") and
  `<leader>al` ("Switch (`<CR>`) or kill (`<C-d>`) a running CLI session
  (telescope)"); reword `<leader>as` (1639) to "**Launch** a CLI tool
  (copilot, gemini, …)" so it reads as distinct from `<leader>al`; reword
  `<leader>ad` (1640) to "Kill **last-used** CLI session …". Feature-specific
  keys stay in this table, not the Keymap index ("Keymap ownership rule").
- **Add a short prose note** (near 1626-1629): sessions are keyed by `(tool
  name, cwd)`; extra sessions are dynamically-registered tool names cloned from
  the `claude` preset; only `claude` #1 is pre-warmed; reviving a killed name
  starts a fresh conversation; nothing persists across restart without mux.
- No new module and no `init.lua` `require()` change → no `Architecture` /
  `Load order` edit needed. `<leader>al`/`<leader>an` start no new prefix
  family (still `a`), so the *By prefix* table is unchanged. `## AI
  (sidekick.nvim)` already carries an explicit anchor (`GUIDE.md:1607`) and
  isn't being renamed → no anchor-hygiene action.

## Verification

1. `<leader>aa` → pre-warmed `claude` shows. `<leader>an` → Enter → `claude 2`
   opens as a second independent session. `<leader>an` → type `tests` →
   `claude: tests` opens.
2. `<leader>an` → type `tests` **again** → re-attaches the existing
   `claude: tests` (no duplicate) — confirms labels are reusable.
3. `<leader>al` → telescope picker lists the running sessions; `<CR>` switches
   to the highlighted one; `<C-d>` tears it down and it disappears from the
   (refreshed) list. Kill a dynamic one and confirm it no longer appears in
   `<leader>as`'s launcher list (GC worked); kill the built-in `claude` and
   confirm `claude` is still in the launcher list (built-in not GC'd).
4. After using `claude 2`, `<leader>aa` toggles `claude 2` (last-used), not #1.
   Show #1 again, then `<leader>aa` toggles #1.
5. `<leader>ad` → confirm popup → kills the **last-used** session specifically.
6. `<leader>aa`/`<leader>an` on a killed name → re-spawns (fresh conversation,
   no resume).
7. Confirm each session is a distinct process (`:!pgrep -fl claude` shows N).

## Out of scope / follow-ups

- **Persistence across nvim restart** → that's the mux backend
  (`cli.mux.enabled = true`, `backend = 'zellij'`); it interacts heavily with
  the pre-warm/stickybuf/`sidekick_terminal` machinery and is a separate
  decision. See `plans/sidekick-windowless-prewarm.md`.
- **Pre-warming sessions 2+** (the cold-start on first open of extras).
- **TODO (after main implementation lands): auto-GC of `cli.tools`.** Today
  dynamic names are GC'd only interactively (`<C-d>` in `<leader>al`, or
  `<leader>ad` on the last-used). Add an automatic sweep so torn-down names
  don't linger in the `<leader>as` launcher list — e.g. on `SidekickCliDetach`
  (emitted at `session/init.lua:163`), `M._forget` the name if no session for
  it remains. Deferred so the first cut stays small and the detach-timing/
  re-show interactions can be worked out separately.

## Still consider — fixed pre-named pool (rejected for now, revisit if the
dynamic approach frets)

Instead of mutating `Config.cli.tools` at runtime, register a **fixed pool** of
pre-named aliases once at `setup()` — `claude`, `claude 2`, … `claude N` (say
N=5–9) — each cloned from the claude preset. `<leader>an` would then cycle to
the next unused pool slot rather than minting a name.

Trade-offs vs. the chosen dynamic approach:

- **For the pool:** no runtime config mutation; no `cli.tools` growth/leak (so
  the auto-GC TODO above disappears); a bounded, predictable `<leader>as`
  launcher list; simpler mental model.
- **Against the pool:** a hard cap (the very "hardcode 5" the user rejected);
  no meaningful labels (`claude: tests`) — pool slots are just numbers; unused
  slots clutter the launcher list from the start.

Rejected because the user explicitly wanted **unbounded, name-as-you-go**
sessions and labels. Worth revisiting only if the dynamic approach's launcher
clutter or the auto-GC work proves more annoying than a fixed cap.

## Decided against

- **Strictly claude-only switch picker.** `<leader>al`'s custom telescope
  picker lists all *in-nvim* running sidekick sessions (the `started` filter),
  not just `claude*`. Now that the picker is hand-rolled (for `<C-d>` delete),
  claude-only would be a trivial `tool.name:match('^claude')`, but the user
  confirmed all-sessions is fine. See "What the switcher does NOT show" for why
  external sessions don't leak in the zellij setup.
- **Hanging `<C-d>` off sidekick's `select()`.** Not possible — `select()` is
  `vim.ui.select` with no action hooks (see "The switch picker"); the custom
  telescope picker is the reason `<leader>al` doesn't reuse `select()`.
