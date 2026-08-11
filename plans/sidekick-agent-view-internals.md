# Agent-view internals — companion for agents

Audience: agents (and future-me) editing `lua/agent_events.lua`,
`lua/agentview.lua`, the agent-view parts of `lua/ai.lua`/
`lua/statusline.lua`, or any of the Phase-3 emitters. The design story
and decision history live in [sidekick-agent-view.md](sidekick-agent-view.md);
this file is the operational truth: the state machine as shipped, the
invariants you must not break, the external behavior we depend on, and
how to test any of it headless. Written 2026-08-10, at the end of the
UX-follow-ups + adversarial-review cycle. **The code is the source of
truth if this drifts** — but update this file in the same change when
you move any of it.

**Before editing any of these modules, run the regression suite:**

```sh
nvim/.config/nvim/tests/agentview/run.sh
```

Run it again after. It encodes ~everything below; a red suite is a
semantics change, intended or not.

## Module map

```
claude/.claude/hooks/sidekick-notify.sh   hook → tmpfile → --remote-expr
opencode/.config/opencode/plugins/nvim-notify.ts   (full rings)
pi/.pi/agent/extensions/nvim-notify.ts             (running/done)
cursor: no file — rides the Claude-hook merge of ~/.claude/settings.json
      ▼
lua/agent_events.lua    registry + state machine + ack/promote +
      │                 desktop notification; fires User AgentSessionEvent
      ▼ (pure subscribers)
lua/agentview.lua       the view tab: sidebar render, embed, placeholders
lua/statusline.lua      `! <label> +N` badge (via ai.unread_candidates)
lua/ai.lua              session layer: labels, jump, kill, delegates
```

`agent_events` knows nothing about UI; `agentview` knows nothing about
hooks. Keep it that way.

## State machine (per session name, `M.sessions[name]`)

Flags: `running`, `unread` (the ring), `attention`
(`'needs-permission'|'needs-input'|'turn-complete'|nil`), `deferred`
(held turn-complete), `notified` (popup fired this blocked episode),
`last = {category, at, seq, raw}` (`seq` is the monotonic order key;
`at` is os.time, display-only).

| event | running | unread | attention | deferred | notified |
|---|---|---|---|---|---|
| prompt-submit | true | false | nil | nil | nil |
| needs-permission | true | **true always** | needs-permission | nil | set if popup fires |
| needs-input | false | **true always** | needs-input | nil | set if popup fires |
| turn-complete | false | true — unless focused+looking → `deferred=true` instead | turn-complete | see prev cell | nil |
| session-end | false | false | nil | nil | nil |

`ack(name)` (non-force): only acts when `attention == 'turn-complete'`
and `unread or deferred`; clears both; fires `kind='ack'`.
`ack(name, {force=true})`: clears `unread`/`deferred`/`notified`, resets
`attention=nil, running=false` (else a dismissed `!` shows `»` forever);
returns true/false. `M.promote(name)`: `deferred` → `unread`, fires
`kind='promote'` (skips the fire if already unread — no-op repaint
guard). `M.clear(name)`: GC, wired into `_forget`/kills/detach sweep.

### Ack triggers (turn-complete tier ONLY — urgent never focus-acks)

- `WinEnter` on a window stamped with the session (`w.sidekick_cli`).
- `ModeChanged *:t*` — *entering* terminal-mode there (pattern is
  `old:new`; matches `nt→t`, not `n→nt`).
- `FocusGained` — narrow: only when the current window is the session's
  AND mode is already terminal-mode (parked-and-typing). Normal-mode
  refocus deliberately does NOT ack.
- `agentview.embed()` when `main_win` is current (in-view swaps fire no
  WinEnter). `<CR>`/digits/`<leader>aj` from the sidebar ack via
  `enter_main()`'s WinEnter instead. Sidebar `<M-]>`/`<M-[>` and
  `j`/`k` ack nothing — preview-grade, on purpose.
- `<M-u>` = force-ack: sidebar (row under cursor) and inside CLI
  terminals (stamp-resolved, NOT `ai.active`); both notify on no-op.

### Promote triggers (deferred → unread; miss one and rings drop silently)

`WinLeave` (leaving the session's window) · `FocusLost` (sweeps ALL
sessions — the window stamp isn't reliable identity at that point) ·
`agentview.embed()` promotes the outgoing stamped session before
re-stamping · `show_scratch()` · `agentview.close()` and the
`PersistenceSavePre` handler (tabclose fires no WinLeave for main_win).
If you add a new way to swap the main pane's buffer or tear the view
down, it must promote.

## Notification pipeline

In `M.handle`, **after** `fire()` and pcall'd (a notifier throw must
never skip the UI repaint). Gate: post-transition status is urgent AND
`focused == false` AND `not notified`. One popup per continuous blocked
episode; the flag arms only when a popup actually *fires* (no-notifier
machines retry next event) and clears per the table above. Delivery:
`notify_argv` prefers `terminal-notifier -title <label> -message <body>
-ignoreDnD` (body space-padded — a dash-leading message is silently
swallowed to an EMPTY notification, exit 0), falls back to osascript
(`applescript_str` escaping — injection-tested), else nil. Body =
`last.raw.message` or the category phrase, never both. Title =
`ai.display(name)`.

## Invariants (each one broke, or nearly broke, at least once)

1. **Badge and `<leader>aj` consume the same list** —
   `ai.unread_candidates()` (unread, running, excluding the focused
   window's session, `seq`-ordered). The badge must never name a
   session the jump refuses.
2. **Urgent (`!`) is only cleared by real progress**: prompt-submit,
   the session's next attention event, or force-ack. Never by focus,
   entry, or interaction.
3. **`deferred` is invisible**: excluded from `unread_sessions()` and
   `status()` returns `'idle'` — no badge, no `●`. But it must never be
   *dropped* while the session lives (see promote triggers).
4. **Ordering is `last.seq`** (monotonic counter). `os.time()` ties are
   nondeterministic under table.sort — never sort on `at`.
5. **Sidebar keymaps read `rows_by_lnum`, never parse buffer text**;
   render errors must restore `modifiable=false` and empty the map (act
   on nothing rather than the wrong row).
6. **Glyph column is leading, fixed, real text** — every row kind
   (numbered, ≥10 unnumbered, spawning `…`, degrade-no-registry) keeps
   the same prefix width.
7. **The view owns display**: while embedded, `term.win` stays nil and
   sidekick owns zero windows; never call `cli.show()` from inside the
   view. Embedded windows must carry the stamps (`sidekick_cli`,
   `sidekick_session_id`, `agentview_main`) or WinEnter tracking, byte
   keys, and acks all die.
8. **Digits = name-sorted running list = cycle order**; spawning rows
   render unnumbered.
9. **No polling, no timers, anywhere.** Reactive reads only.
10. **Every state transition the UI can see fires `AgentSessionEvent`**
    (kinds: event/ack/clear/promote); sidebar + badge are pure
    subscribers.

## External behavior we depend on (verified 2026-08-10)

sidekick.nvim — installed at
`~/.local/share/nvim/site/pack/core/opt/sidekick.nvim` (**vim.pack, not
lazy**; a separate clone at `~/src/sidekick.nvim` is NOT what nvim
loads). Unpinned — re-verify these after any sidekick update:

- `terminal.lua` `open_win` sets `vim.w.sidekick_cli` /
  `.sidekick_session_id`; `focus()` uses `nvim_set_current_win` with
  **no** noautocmd → WinEnter fires (the solo-column jump ack rides
  this).
- `SidekickCliAttach` is emitted synchronously from inside
  `State.attach`, and `terminal:show()` runs right after the handler
  returns → the view's Attach handler must `vim.schedule` its work.
- `cli.show{layout='right'}` splits the *current* tab; `state.get({
  started=true})` is the row source.

Other: terminal-notifier 2.0.0 (`-ignoreDnD` confirmed real; dash
quirk above; needs one-time Notifications permission). Claude Code
hook env: `CLAUDE_CODE_EXECPATH` set ⇒ nested-claude, suppressed —
if a future release injects it into *hook* envs, ALL events vanish
(breadcrumb also in the main plan). Same-family guards:
`PI_SUBAGENT_DEPTH` (pi children), opencode `parentID` filtering.
`$SIDEKICK_SESSION` is injected via the `cli.tools` env blocks in
ai.lua — required, not optional, for built-ins.

## Testing headless — hard-won recipes

- Always `env -u NVIM`; add `-u CLAUDE_CODE_EXECPATH` for hook e2e
  (Claude injects it into tool subprocesses; the guard then suppresses
  everything and reads as "plugin broken").
- **Real terminal-mode is unreachable headless** — `startinsert`/
  `feedkeys('i')` land in `nt`, never `t`. Stub `nvim_get_mode` and
  fire the autocmd via `nvim_exec_autocmds`.
- `nvim_win_set_cursor` does NOT fire `CursorMoved` under `--headless
  -l`; dispatch it explicitly.
- macOS unix sockets cap at ~104 path bytes — `--listen` sockets go in
  `/tmp`, never a deep scratchpad path.
- Notifications: spy `vim.system` + stub `vim.fn.executable`; escaping
  may be checked with `osascript -e 'return "…"'` round-trips — never
  `display notification` in a test.
- Lualine end-to-end: `require('lualine').statusline(true)` renders for
  real; `update_status` runs before `apply_highlights`, so a
  stash-in-component/read-in-color pattern is safe.
- The opencode SDK client never throws (`{data=undefined, error}`) —
  check `res.data`, don't try/catch. opencode's plugin loader re-wraps
  v2 events as `properties`-shaped before your hook sees them.
- `pi -p` loses the `session_shutdown` race ~half the time; anything
  needing session-end must tolerate absence (Detach sweep covers it).

## Pre-agreed retreat positions (simplify, don't patch, if these misbehave)

- **Defer machinery feels flaky in daily use** → delete the `deferred`
  flag entirely: unconditional unread + interaction-ack. That's the
  agreed fallback, not another promote path.
- **Solo-column jump ack regresses** (sidekick changes focus()) →
  restore the one-line direct `ev.ack(name)` in `jump_unread`.
- **cursor's Claude-hook merge breaks** → explicit `~/.cursor/hooks.json`
  per the main plan's Phase 3 fallback.
- **Notification under- or over-fires** → the episode flag vs
  dedupe-on-message trade-off is written up in the main plan's Knobs
  section; pick the other one, don't invent a third.

## Comparators for the next design round

claude-squad / Crystal (multi-session managers: worktrees, pending
diffs, batch prompting) · Conductor, Vibe Kanban (task-centric framing
we rejected) · **Slack's unread model** (`●`≈bold unread, `!`≈mention
badge, manual mark-unread ≈ `<M-u>` — best prior art for ack
semantics) · Ghostty's native OSC 9/777 (what agents get for free
outside nvim; the argument for the `TermRequest` follow-up) · Zed and
Cursor agent panels (editor-native peers; binary-dot, cruder ack).
Biggest structural lesson already learned: cmux's real transport is
OSC-first, hooks second — if rebuilding, invert our order (see the
main plan's follow-up 4).

## History

Six feature commits (`3a1cdd8`…`7917d3d`), three-reviewer adversarial
pass, six fix commits (`61281b7`…`07d9a25`) — the main plan's
"Follow-ups — UX critique" section has the full record, including the
11 confirmed defects and what each fix changed.
