# Plan: Agent event pipeline for sidekick Claude sessions (cmux-inspired)

## Problem

Three (or more) Claude Code CLI sessions run concurrently in this nvim config
via sidekick (`<leader>an`/`<M-n>` create dynamically-named sessions
`claude`, `claude 2`, `claude 3`, ...; see
`plans/sidekick-multi-claude-sessions.md` for how that multi-session system
works). Right now, knowing *which* session needs attention — finished its
turn, is blocked on a permission prompt, or is idle waiting for input —
requires manually checking each split. There is no signal, no badge, nothing
equivalent to what cmux (github.com/manaflow-ai/cmux) does for terminal-based
coding agents: rings around panes, sidebar badges, a notification popover,
and desktop notifications, all driven by agent lifecycle events.

## Goal

This plan covers **only the event pipeline** — getting a correctly-attributed,
categorized stream of "this Claude session just did X" events out of Claude
Code and into a queryable nvim-side registry. It deliberately does **not**
pick a UI (see "UI surface options" below, which documents the choices
without committing to one) — the user wants the event system designed and
built first, with UI consumers layered on top once the pipeline exists.

> **Motivating wishlist item** (folded in from the old `TODO.md` "New List"
> when the plans were consolidated): *"a status bar for sidekick telling me if
> a Claude window needs my input / is done / etc., ideally for all sidekick
> windows."* That status bar is a UI consumer of exactly this pipeline —
> per-session needs-input/done/idle state is what the event registry here is
> designed to expose.

## Prior art: how cmux does this

Recap from the cmux investigation (for reference, not something this repo
depends on): agent hooks call cmux's own CLI over a Unix socket with a
category-tagged payload (`c=turn-complete|needs-permission|idle-reminder`)
keyed by a terminal *surface id*. A gate (`AgentNotificationGate`) filters by
category and user settings, a queue coalesces bursts, a policy engine
(pluggable hooks) can mutate/suppress, and the result fans out to four UI
surfaces simultaneously (rings, badges, popover, desktop banner). The
category taxonomy and the "one event bus, many UI consumers" shape are worth
copying; the socket/CLI transport is not relevant here since Claude Code
already has its own hook mechanism.

## Investigation

### Claude Code's own hook events (verified against code.claude.com/docs/en/hooks)

Every hook receives common fields on stdin as JSON: `session_id`,
`transcript_path`, `cwd`, `hook_event_name`, plus event-specific fields.
**Confirmed absent from the payload: any tty, pid, or terminal identifier.**
Hooks run "without a controlling terminal" — this is the core problem this
plan solves (see "Session tagging" below).

Hook subprocesses are spawned by the Claude Code process and inherit its
environment like any child process — this is the mechanism the whole
pipeline leans on to identify *which* of the 3 nvim-managed sessions fired a
given hook.

Events relevant to an attention/status pipeline (verified via targeted
re-fetch, not the first pass — see "Confidence notes" below):

| Hook event | Matcher values | Fires when |
|---|---|---|
| `SessionStart` | `startup`, `resume`, `clear`, `compact` | Session begins/resumes/clears/recompacts |
| `SessionEnd` | `clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other` | Session process ends |
| `Stop` | none | Claude finishes responding (a normal turn completion) |
| `Notification` | `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed` | Claude Code sends a notification — the matcher tells you *which kind* |
| `SubagentStop` | agent type (`general-purpose`, `Explore`, `Plan`, custom/plugin names) | A subagent (Task) finishes |
| `PreCompact` | `manual`, `auto` | Before context compaction |

**Confidence notes:** the docs page does not show a full example JSON payload
for `Notification`, `SubagentStop`, or `SessionEnd` — only their matcher
tables are confirmed verbatim from the page. Field names beyond the common
set (e.g. whether `Notification` carries a `message` string field) are
**not** confirmed and should be checked by actually printing the hook's stdin
to a file the first time it's wired up, rather than assumed. Treat the table
above as a solid list of *event names and matchers* but the exact
event-specific JSON schema as unverified until observed directly.

### Session identity in this config

sidekick's own session id (`sid`) is `"<tool name> <sha256(cwd)[:n]>"`
(`sidekick.nvim`'s `lua/sidekick/cli/session/init.lua:104-108`) — it does not
know about, and has no way to learn, Claude's own `session_id` UUID. This
repo's multi-session system (`ai.lua`) instead keys everything off a plain
name string (`"claude"`, `"claude 2"`, ...) via `cfg.cli.tools[name]`,
`M.active`, and `M._dynamic[name]` — see `create_session` at `ai.lua:422-432`
and `plans/sidekick-multi-claude-sessions.md` §"Session identity is (tool
name, cwd)". **This plan reuses that same name string as the join key** —
it's already the stable, human-legible identity the rest of the config uses,
so there's no need to touch sid/pid machinery at all.

### The env bridge (verified against installed plugin source)

`sidekick.nvim`'s job spawn (`lua/sidekick/cli/terminal.lua:282-300`) builds
the child process environment as:

```lua
local env = vim.tbl_extend("force", {}, vim.uv.os_environ(),
  self.tool.config.env or {}, self.tool.env or {}, { ... })
...
self.job = vim.fn.jobstart(norm_cmd, { ..., clear_env = true, env = ... })
```

`self.tool.config.env` is exactly the `env` table on the entry you register
under `cfg.cli.tools[name]` — the same object `create_session` builds via
`vim.deepcopy(require('sidekick.cli.tool').get('claude').config)`. This means
**any env vars set here survive `clear_env = true`** because they're
explicitly re-added by sidekick's own merge, independent of whatever this
nvim process's ambient environment happens to contain.

**Correction (adversarial review caught this):** the plan originally proposed
injecting a custom `SIDEKICK_NVIM` var to work around uncertainty about
whether nvim's `$NVIM` survives `clear_env`. That uncertainty doesn't need
resolving — `terminal.lua:283` shows sidekick *itself* already puts
`NVIM = vim.v.servername` into that same explicit env table for every
session it spawns. The hook script can read plain `$NVIM`; there is no need
for a second, duplicate variable. Only `SIDEKICK_SESSION` needs adding.

### The nvim RPC bridge

Every non-headless nvim instance has a server address at `v:servername`
(no `serverstart()` call needed), and — per the correction above — sidekick
already exposes that address to hook subprocesses as `$NVIM`. External
processes talk to it with `nvim --server <addr> --remote-expr '...'`. This
was verified live (nvim 0.12.4): `nvim --server <addr> --remote-expr
"v:lua.require('agent_events').handle('<tmpfile-path>')"` calls the Lua
function, returns its value, and exits 0 — the mechanism works exactly as
assumed. Since `$NVIM` is scoped per nvim process, two separate `nvim`
instances each running their own sidekick sessions route events to the
correct one automatically, with no extra work.

### Gap: there is no existing UI consumer to build on

Correcting an earlier assumption made mid-conversation: `statusline.lua:59-80`
reads `sidekick.status`, which is sidekick's **Copilot/NES busy indicator**
(shows a robot glyph while Copilot's LSP-based next-edit-suggestion is
working) — it has nothing to do with Claude CLI sessions. There is currently
no per-Claude-session status display anywhere in this config (checked
`ai.lua` for `winbar`/`tabline` usage — none). Any UI surface is new work,
which is exactly why this plan scopes it out and documents options instead
of building one.

## Event taxonomy

Categories this pipeline should track, mapped to the verified hook table
above, loosely mirroring cmux's `turn-complete` / `needs-permission` /
`idle-reminder` split:

| Category | Source | Urgency (suggested) | Notes |
|---|---|---|---|
| `turn-complete` | `Stop` | Medium | Normal turn end — Claude did something and is waiting for review, not necessarily blocked |
| `needs-permission` | `Notification` matcher `permission_prompt` | High | Claude is blocked on an approve/deny prompt — the closest analog to cmux's most urgent category |
| `needs-input` | `Notification` matcher `idle_prompt` | High | The generic "Claude is waiting for your input" idle case |
| `subagent-done` | `SubagentStop` | Low | A Task/subagent finished; informational, not usually worth interrupting for |
| `session-start` / `session-end` | `SessionStart` / `SessionEnd` | n/a (bookkeeping) | Not an "attention" event — used to register/deregister the session in the nvim-side registry so stale entries don't linger |
| *(ignored)* | `Notification` matchers `auth_success`, `elicitation_*`, `agent_completed`, `agent_needs_input`; `PreCompact` | n/a | Lower-value noise for a first version — pass through unhandled rather than building UI for them yet |

`StopFailure` (an API-error turn end) showed up in the first, less reliable
docs fetch but was not independently confirmed in the targeted re-fetch —
worth checking for at implementation time since "Claude hit a rate limit and
silently stopped" is exactly the kind of event this pipeline should surface,
but don't build against it until its matcher/payload is confirmed.

## Architecture

```
Claude Code process (session "claude 2")
  └─ Stop/Notification[permission_prompt]/... hook fires
       (category is baked into WHICH hook command fired, not read from
        an env var — see "Hook registration" below)
       └─ hook script reads $SIDEKICK_SESSION, $NVIM (both already
            present in the job's env — see below), and its own hardcoded
            category argument
       └─ writes { session, category, raw: <stdin JSON> } to a temp file
            it owns (mktemp), traps its own cleanup (rm on exit)
       └─ `timeout 2 nvim --server "$NVIM" --remote-expr \
            "v:lua.require('agent_events').handle('<tmpfile-path>')"`
            (single argument — no session/category strings interpolated
            into the expr, so no quoting/injection risk from session names)
       └─ always exits 0, regardless of the above succeeding
            (a plumbing bug must never be able to block/alter Claude's turn)
  ↓
nvim process (the one that spawned it)
  lua/agent_events.lua
       registry: M.sessions[name] = { category, at, raw }
       fires `User AgentSessionEvent` autocmd with the session name in
       `vim.v.event` — any future UI consumer subscribes to this, without
       agent_events.lua knowing about UI at all
  ↓
(future work) UI consumer(s) — see options below
```

### 1. Session tagging at spawn (`ai.lua`)

Two edits, both small. Only `SIDEKICK_SESSION` needs adding — `$NVIM` is
already present in the job env courtesy of sidekick itself (see correction
above).

- In the existing `require('sidekick').setup({ cli = { tools = { ... } } })`
  block (`ai.lua:41-81`), add `tools.claude = { env = { SIDEKICK_SESSION =
  'claude' } }`. Confirmed via `sidekick.nvim`'s `tool.lua:27`
  (`vim.tbl_deep_extend("force", base[name], Config.cli.tools[name])`) that a
  user-supplied `cli.tools.claude` **deep-merges** onto the built-in preset
  by name — `cmd`/`format`/`resume` survive untouched.
- In `create_session` (`ai.lua:422-432`), after the `vim.deepcopy(...)` line,
  set `cfg.cli.tools[name].env = vim.tbl_extend('force', cfg.cli.tools[name].env
  or {}, { SIDEKICK_SESSION = name })` — use the `or {}` fallback rather than
  indexing `.env.SIDEKICK_SESSION` directly, so this doesn't nil-index if the
  cloned preset happens not to carry an `env` table for any reason (don't
  rely on edit 1 having run first for this to be safe).

### 2. Hook script

**Correction (adversarial review caught this):** the original draft assumed
a `$SIDEKICK_CATEGORY`/`$CLAUDE_HOOK_EVENT` env var would tell the script
which matcher fired. Verified against the docs: Claude Code does not expose
the matcher to the hook subprocess via an env var at all — only via the
`hook_event_name` field in stdin JSON (no field for the sub-matcher, e.g.
`permission_prompt` vs `idle_prompt`, was confirmed present). The category
must instead be **baked into which hook command was registered** — see
"Hook registration" below, where each event+matcher pair gets its own
`settings.json` entry, each passing a different hardcoded argument to the
same script.

A single shared script, checked into the `claude` stow package (this repo
already manages `~/.claude` via stow — see `claude/.claude/skills/`) at e.g.
`claude/.claude/hooks/sidekick-notify.sh <category>`. Responsibilities:

- No-op (exit 0 immediately) if `$NVIM` or `$SIDEKICK_SESSION` is unset —
  this is what makes it safe to register **globally** in
  `~/.claude/settings.json` rather than per-project: it fires for every
  Claude Code invocation everywhere (plain terminal, other editors, CI), and
  silently does nothing outside a sidekick-managed nvim session.
- `category="$1"` — the hardcoded argument from this specific hook
  registration (see below), not anything read from the environment.
- Read the hook's stdin JSON, write `{session, category, raw}` to a
  `mktemp` file; `trap 'rm -f "$tmpfile"' EXIT` so the script cleans up its
  own file regardless of whether the RPC call below succeeds — don't
  delegate deletion to `agent_events.lua`, since a dead/unreachable nvim
  would otherwise leak the file.
- `timeout 2 nvim --server "$NVIM" --remote-expr \
  "v:lua.require('agent_events').handle('$tmpfile')" >/dev/null 2>&1` —
  `timeout` guards against a stale server address (nvim crashed/restarted
  since Claude was spawned) ever hanging Claude's own turn completion. Only
  the tmpfile path (script-controlled, from `mktemp`) is interpolated into
  the expr — never the session name or category, which may contain
  characters that need escaping (a session named via `M.new_session` can
  contain arbitrary user text, e.g. `claude: it's broken`).
- Always `exit 0`.
- Expected, acceptable loss: if nvim's main loop is busy (blocked on a
  synchronous prompt/operator-pending), the `--remote-expr` call queues and
  `timeout 2` may drop it. Not worth engineering around for a first version.

### 3. Hook registration

Registering the hooks in `~/.claude/settings.json` needs one entry **per
event+matcher combination** this pipeline cares about, each passing its own
category argument to the shared script — e.g. (illustrative, not final
syntax):

- `Stop` → `sidekick-notify.sh turn-complete`
- `Notification` matcher `permission_prompt` → `sidekick-notify.sh needs-permission`
- `Notification` matcher `idle_prompt` → `sidekick-notify.sh needs-input`
- `SubagentStop` → `sidekick-notify.sh subagent-done`
- `SessionStart` / `SessionEnd` → `sidekick-notify.sh session-start` / `session-end`

This is a `settings.json` change — per this session's own tooling
conventions that goes through the `update-config` skill rather than a raw
file edit, and should land as `claude/.claude/settings.json` in this repo
(not an unmanaged, un-synced file in `~/.claude`) so it's portable across
machines like the rest of this repo's Claude config.

### 4. `lua/agent_events.lua` (new module)

The actual "event system" — deliberately UI-agnostic:

- `M.sessions` — table keyed by session name, holding the latest
  `{ category, at, raw }`.
- `M.handle(tmpfile_path)` — the RPC entrypoint
  (`v:lua.require('agent_events').handle`), taking only the tmpfile path
  (see the injection-safety note in "Hook script" above). Reads and decodes
  the JSON (`session`, `category`, `raw`), updates `M.sessions`, and fires
  `vim.api.nvim_exec_autocmds('User', { pattern = 'AgentSessionEvent', data
  = { session = session, category = category } })`. Does **not** delete the
  tmpfile — the hook script owns that via its own `trap`.
- Lifecycle cleanup: hook `M._forget` (`ai.lua:443-448`) and the picker's
  `<C-x>` teardown (`plans/sidekick-multi-claude-sessions.md` §"`<C-x>`
  teardown must be synchronous") to also clear `M.sessions[name]` — otherwise
  a reused name (spawn "claude 2", kill it, spawn a new "claude 2") starts
  with stale state from the previous process.
- No polling, no timers — purely event-driven off the RPC calls.

This module is the deliverable of this plan. Everything past this point is
future work.

## UI surface options (documented, not decided — future phase)

Per your instruction to document these in detail before picking one. All are
plausible `User AgentSessionEvent` autocmd subscribers and are not mutually
exclusive — cmux runs all four of its equivalents simultaneously.

### A. Sign/highlight on the session's terminal buffer
Closest analog to cmux's blue pane ring. Place a sign or highlight the
buffer's name/winbar when `M.sessions[name].category` is `needs-permission`/
`needs-input`, cleared on focus (`WinEnter`/`TermEnter` on that buffer).
**Pro:** visible exactly where cmux puts it, cheap to implement (signs are a
core nvim primitive). **Con:** invisible unless the split is currently on
screen — with only one session visible at a time in this config's solo-view
model (`show_solo` hides the others), this alone won't tell you that a
*hidden* session needs you.

### B. Status in the sidekick session picker/winbar
Extend the in-panel session cycler (the bracket-cycle keys added recently,
`ai.lua` picker code) so each session's label shows a glyph/color for its
category when listed. **Pro:** exactly where you already switch sessions,
so no new UI surface to learn. **Con:** only visible when you open the
picker — not an ambient/passive signal like cmux's rings.

### C. Lualine statusline segment
A global segment (à la the existing Copilot-busy indicator at
`statusline.lua:59-80`, which this plan's earlier investigation clarified is
*not* reusable for this but is a good template) summarizing all sessions at
once, e.g. `● claude 2 needs-input`. **Pro:** always visible regardless of
which buffer/session is focused — the closest thing to cmux's sidebar badge.
**Con:** statusline space is already fairly full; multiple simultaneous
"needs attention" sessions would need truncation/cycling logic.

### D. macOS desktop notification
Shell out to `terminal-notifier` or `osascript` from `agent_events.lua` (or
even directly from the hook script, bypassing nvim entirely for this one
surface). **Pro:** the only option that works when nvim isn't focused at all
(e.g. you alt-tabbed to a browser) — this is what cmux's desktop banner is
for. **Con:** needs its own suppression logic (don't banner if you're already
looking at that exact session) or it becomes noisy — cmux's
`shouldSuppressExternalDelivery` focus-gate is the relevant prior art if this
gets built.

A reasonable eventual shape, once the pipeline above exists and has been
used for a bit: start with **B** (cheapest, reuses the picker you already
look at) to validate the event data is correct, then add **C** for ambient
visibility, and consider **A**/**D** based on how often sessions get missed
in practice.

## Risks / open questions

- **Hook payload schema for `Notification`/`SubagentStop`/`SessionEnd` is
  unconfirmed** (see "Confidence notes" above) — first real implementation
  step should be logging raw stdin to a file for each event type before
  writing the category-mapping logic, rather than coding against guessed
  field names.
- ~~Env var name for "which matcher fired"~~ **Resolved by adversarial
  review:** there is no such env var. Claude Code does not expose the
  matcher to the hook subprocess at all — category comes from registering a
  distinct `settings.json` hook entry per event+matcher, each hardcoding its
  own argument to the shared script (see "Hook registration"). The
  architecture above already reflects this fix.
- **Global hook registration is broad-reach.** Since Claude Code hooks are
  process-global once in `~/.claude/settings.json`, this script fires for
  *every* Claude Code invocation on the machine, not just sidekick ones — the
  early-exit-if-env-unset guard is load-bearing for safety, not just
  tidiness.
- **`timeout`/always-exit-0 is a hard correctness requirement**, not a nice-
  to-have — a hang or nonzero exit in this plumbing must never be able to
  block/alter a real Claude Code turn (e.g. `Stop`'s exit-2 behavior
  "prevents Claude from stopping").
- **Multiple sidekick-managed nvim instances in the same repo** are handled
  for free by keying off `$NVIM` (per-process, injected by sidekick itself),
  but worth a verification pass once built.
- **Tmpfile ownership.** The hook script's own `trap ... EXIT` cleans up its
  tmpfile regardless of whether the RPC call reaches nvim — don't delegate
  deletion to `agent_events.lua`, or a dead/unreachable nvim leaks files into
  `/tmp` indefinitely.
- **No string interpolation of user-influenced data into `--remote-expr`.**
  Session names come from free-text input (`M.new_session`) and could contain
  quotes/special characters; only the `mktemp`-generated tmpfile path (never
  the session name or category) is interpolated into the remote expression.

## Verification (once implemented)

1. Log raw hook payloads to a temp file for each of `Stop`, `Notification`,
   `SubagentStop`, `SessionStart`, `SessionEnd` — confirm the taxonomy table
   above against real data before wiring the category mapper.
2. With 3 sidekick Claude sessions open, trigger a permission prompt in
   `claude 2` only — confirm `agent_events.M.sessions['claude 2'].category ==
   'needs-permission'` and that `claude`/`claude 3` are untouched.
3. Kill `claude 2` (`<C-x>` in the picker), spawn a new `claude 2` — confirm
   no stale category carries over.
4. Run a plain `claude` in a non-sidekick, non-nvim terminal (e.g. Terminal.app)
   — confirm the hook script no-ops cleanly (no error, no hang) since
   `$NVIM`/`$SIDEKICK_SESSION` are unset there.
5. Quit nvim (or kill it) while a session is still running and mid-turn —
   confirm the next hook fire (stale `$NVIM`) times out within 2s and does
   not delay or alter Claude's own behavior. Also confirm the hook script's
   own tmpfile is still cleaned up in this case (its `trap` doesn't depend on
   nvim responding).
6. Open two separate nvim instances, each with sidekick sessions, in the same
   repo — confirm events route to the correct instance.

## Out of scope / follow-ups

- Any UI consumer (see options above) — separate plan once this pipeline is
  validated.
- Mute/quiet-hours rules, per-category suppression settings (cmux's pluggable
  policy-hook-chain equivalent) — only worth building once real usage shows
  which categories are noisy.
- A "jump to next session needing attention" keymap (cmux's `Cmd+Shift+U`
  analog) — trivial once `agent_events.M.sessions` exists and a UI surface
  picks an ordering, but depends on picking a UI first.
- OSC 9/99/777 escape-sequence input as an alternative/supplement to hooks
  (what cmux itself supports) — Claude Code doesn't emit these itself as far
  as this investigation found; only relevant if other CLI agents (Codex,
  OpenCode) get added to this pipeline later, since they may support OSC
  where they don't support Claude-style hooks.
