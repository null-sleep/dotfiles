# Plan: Agent view — cmux-style dashboard for sidekick sessions (MVP)

> UX walkthrough (static mockups reviewed 2026-08-08):
> https://claude.ai/code/artifact/93af4a5d-ed72-48ed-9518-0400679ec2bd

## Status — Phases 1+2+3 landed; UX-critique follow-ups 1/2/3/5/6 landed (2026-08-10)

Phase 3 shipped as three commits on `agent-view`: `7cafee0` opencode
plugin (full rings), `9e1075e` pi extension (running/done), `66f7c44`
cursor docs (the free Claude-hook merge verified — no hooks.json needed,
no cursor stow entry created). Deltas and headless verification below;
the interactive checklist gained three Phase-3 items.

### Phase 3 deltas discovered during execution

- **opencode's published v1 plugin types lag its live bus.** The 1.18.10
  binary contains zero `permission.updated` strings — the bus publishes the
  v2 vocabulary (`permission.asked`, `question.asked`, payloads under
  `data`) while `@opencode-ai/plugin` still types the `event` hook with the
  v1 union (`permission.updated`, payloads under `properties`); observed
  events actually arrived `properties`-shaped. The plugin normalizes both
  shapes and answers to both permission names.
- **opencode loads plugins from both `plugin/` and `plugins/`**
  (marker-tested on 1.18.10). `plugins/` (current docs' name) is used.
- **opencode subagent (task-tool) child sessions emit the same
  idle/deleted events** as the prompted session; a child's idle would ring
  `●` mid-turn. Filtered via `parentID` (SDK `session.get`, cached,
  fail-open); `session.deleted` filters on the payload's own
  `info.parentID` since the session is already gone. Urgent events are
  deliberately NOT filtered — a child's permission ask still blocks the
  terminal.
- **pi needed its own nested guard**: pi-subagents children are full pi
  processes inheriting the sidekick env; the extension no-ops when
  `PI_SUBAGENT_DEPTH` is set — the pi analogue of the
  `CLAUDE_CODE_EXECPATH` heuristic. Also: `pi -p` never emits
  `session_shutdown`, so session-end bookkeeping there falls to the
  Detach sweep (fine — TUI quit/reload/new/resume do emit it).
- **cursor's merge map recovered from the shipped bundle** (2026.08.04):
  `UserPromptSubmit→beforeSubmitPrompt`, `Stop→stop`,
  `SessionEnd→sessionEnd`, `SubagentStop→subagentStop`, and — explicitly
  null — `Notification` and `PermissionRequest`. Matches the plan's
  prediction exactly; the free route stands, no `~/.cursor/hooks.json`.
- **Testing gotcha (breadcrumb):** e2e-testing any of these from inside a
  Claude Code session requires `env -u CLAUDE_CODE_EXECPATH` — Claude
  injects it into tool subprocesses, and the script's nested-claude guard
  (correctly) suppresses every event otherwise. First e2e attempt read as
  "plugin broken" for exactly this reason.
- **Review hardening (2026-08-10, adversarial Opus review of the three
  Phase-3 commits):** the opencode `isMain` filter no longer caches a
  failed lookup (the SDK client resolves errors as `{data: undefined}`
  instead of throwing — caching that as "main" would poison the subagent
  filter for the process lifetime); `lastIdle` is pruned alongside
  `topLevel` on `session.deleted`; pi's `session_shutdown` handler skips
  reasons `reload` (extension/settings reload — the conversation
  continues) and `fork`, which would otherwise wipe a live ring or an
  unseen `●`; pi's `ctx.isIdle()` comment no longer claims a filtering
  behavior that doesn't exist (settle fires after retries/continuations
  drain, run flag already cleared — the check is a defensive no-op);
  both emitters gained the `CLAUDE_CODE_EXECPATH` no-op guard so an
  opencode/pi spawned from a claude session's tool subprocess doesn't
  mis-attribute to the claude row.
- **Accepted: cross-agent nesting beyond claude-parented.** An agent CLI
  launched from *another* non-claude agent's tool subprocess (pi's bash
  runs `opencode run`, etc.) inherits `$SIDEKICK_SESSION` and would emit
  events onto the parent's row — there is no env marker to key on for
  the pi/opencode/cursor-parented directions (claude-parented is covered
  by `CLAUDE_CODE_EXECPATH`, pi-under-pi by `PI_SUBAGENT_DEPTH`).
  Accepted as rare + self-healing (the parent's own next event corrects
  the row), same stance as the pipeline plan's lossy delivery.
- **Deliberate drops vs. the Phase 3 spec:** pi's `session_start` is not
  wired (no registry category maps to it — Claude's `SessionStart` was
  dropped for the same reason); the pi >= 0.80.5 floor for
  `agent_settled` is noted in README's pi section rather than enforced
  (pi installs unpinned by design; 0.84.1 verified).

### Phase 3 verified headless (2026-08-10)

- opencode, real `opencode run` with `$NVIM`+`$SIDEKICK_SESSION` against a
  live `--listen` instance: `chat.message` → prompt-submit and
  `session.idle` → turn-complete both delivered; final registry state
  `unread`/`turn-complete`. Event-type inventory logged from a sandboxed
  `XDG_CONFIG_HOME` run (session.idle fires; session.status too).
- pi 0.84.1, real `pi -p` run, same rig: prompt-submit then turn-complete
  delivered; `before_agent_start`/`agent_settled`/`ctx.isIdle` confirmed
  in pi's shipped type declarations first.
- cursor, real `cursor-agent -p` run, same rig: `sessionEnd` delivered
  through the Claude-hook merge with env intact (registered nowhere but
  `~/.claude/settings.json` — proves the merge path). The
  `beforeSubmitPrompt`/`stop` pair errored out headlessly (usage limit
  killed the turn pre-submission) — interactive item 12 remains.

### Field notes — non-obvious facts learned along the way (Phase 3)

Durable knowledge that outlives this feature, worth having greppable:

- **cursor-agent treats `~/.claude/` as a first-class config source**, not
  just for hooks: the bundle also reads `.claude/settings.json` for
  `enabledPlugins`, discovers skills from `~/.claude/skills` (alongside
  `.codex/skills` and `.agents/skills`), and its workspace-sync patterns
  include `**/.claude/**/*.json`. Changing anything in the claude stow
  package can therefore change cursor-agent's behavior — the hook merge
  that Phase 3 rides on is one instance of a broader pattern.
- **cursor hooks fire on error paths**: the usage-limit run never submitted
  a prompt, yet `sessionEnd` still arrived (`final_status: "error"`,
  `reason: "error"` in the payload). Lifecycle hooks are reliable even
  when the turn dies pre-submission; per-turn hooks are not.
- **opencode's plugin loader normalizes the bus for you**: raw v2 events
  carry `data`, but the loader re-wraps them as
  `{id, type, properties: <data>}` before calling the `event` hook — so a
  plugin only ever sees `properties`-shaped payloads even though the
  binary's internal vocabulary is v2. (The plugin keeps a `?? ev.data`
  fallback as forward-compat, currently dead code.)
- **opencode calls every exported function of a plugin module** — no
  default export or naming convention required — and loads from both
  `plugin/` and `plugins/` (symlinks followed). A second, separate
  "config-plugin" loader globs the same files expecting an
  `{id, effect|setup}` shape and silently ignores modules that don't
  match, so one file can serve either system without breaking the other.
- **The opencode SDK client doesn't throw**: generated methods default to
  `ThrowOnError = false`, resolving errors as `{data: undefined, error}`.
  A `try/catch` around an SDK call is almost always dead code — check
  `res.data` instead. This exact trap produced the isMain cache-poisoning
  bug the review caught.
- **pi's `agent_settled` is genuinely terminal**: retries, auto-compaction,
  and queued continuations all drain inside the run loop before settle is
  emitted, and the running flag clears first — so `ctx.isIdle()` is
  unconditionally true at settle time. Any "wait for the real end of the
  turn" logic should key on `agent_settled` alone, no idle-check needed.
- **pi-subagents has two transports with different extension semantics**:
  the default subprocess transport spawns full pi processes (inheriting
  env, hence the `PI_SUBAGENT_DEPTH` guard), while the in-process
  transport builds child sessions with `noExtensions: true` — in-process
  children can never fire an extension, guarded or not.
- **`pi -p` loses its shutdown race roughly half the time**: the
  `session_shutdown(quit)` emit races process exit, so session-end
  delivery from one-shot runs is best-effort (observed both outcomes).
  Anything depending on session-end must tolerate its absence — the
  registry does, via the nvim-side Detach sweep.
- **macOS unix sockets cap at ~104 bytes of path**: `nvim --listen` into a
  deep per-session scratchpad path fails (no socket, no clear error);
  test sockets belong in `/tmp`.
- **Real terminal-mode is unreachable in headless nvim**: `startinsert`/
  `feedkeys('i')` in a term buffer land in `nt`, never `t` — any
  headless test of t-mode-gated behavior must stub `nvim_get_mode` and
  fire the autocmd directly. Likewise `nvim_win_set_cursor` doesn't fire
  `CursorMoved` under `--headless -l`; dispatch it explicitly.
- **terminal-notifier swallows a dash-leading message**: `-message "-rf
  please"` exits 0 and delivers an EMPTY notification (silent data loss,
  confirmed via `-list ALL`). Space-pad any body that could start with
  `-`.

## Follow-ups — UX critique (2026-08-10, design review vs live cmux)

### Status — items 1, 2, 3, 5, 6 shipped (2026-08-10, six commits)

`3a1cdd8` manual dismiss (`M.ack(name, {force})` + sidebar `<M-u>`),
`ad056d7` defer-not-drop + ack-on-interaction, `c085088` leading glyph
column + `·`→`○` merge, `5321473` badge redesign, `77e0e71` quick wins,
`7917d3d` urgent-only desktop notification. Item 4 (OSC 9/777 via
`TermRequest`) is deferred to its own follow-up plan as the critique
itself recommended. All verified headless (state-machine suites, real
lualine render, real `CursorMoved`-driven preview, `vim.system` spy for
osascript); the interactive checklist gained items 14–17 below.

Execution deltas worth keeping:

- **Defer-not-drop fan-out**: the `deferred` flag must be nil'd in four
  of the five transitions (an urgent landing on a deferred session would
  otherwise re-promote after being answered), and `ack`'s guard widened
  to `unread or deferred` — net ~35 LOC, not the estimated ~8.
  `FocusLost` promotes via a sweep over all sessions (the current
  window's stamp isn't a reliable identity for what was deferred).
- **The removed `FocusGained` blanket ack leaves one intended gap**:
  alt-tab back, sit in the CLI window in normal mode, never type — the
  ring stays lit until real interaction (`ModeChanged *:t*`, WinEnter,
  or `<M-u>`). That is the "read = interaction" semantics, chosen
  knowingly against the old comment's argument.
- **`jump_unread`'s direct ack was removed** (one path now: embed-ack in
  the view, WinEnter in the solo column). If the solo-column ack ever
  regresses, restoring the one-line `ev.ack(name)` there is the fix.
- **Badge label resolution**: sidebar/picker render label and raw name
  as separate spans, so there was nothing to reuse — new `ai.display()`
  is the one-string owner; truncation (12 cells incl. `…`) lives in
  statusline.lua because it's a statusline-space constraint, not a
  label property. A stale urgent still outranks a fresher plain unread
  in badge naming (matches `!`-outranks-`●`).
- **Desktop notification re-fire is per-episode** (revised in the review
  fixes below; the first cut compared tiers, which was both too tight —
  approving a permission emits no hook, so later prompts that turn were
  silenced — and too loose — Claude's ~60s `idle_prompt` re-popped the
  same unanswered block): a per-session `notified` flag arms when a
  popup actually fires and clears on prompt-submit/turn-complete/
  session-end/force-ack. One popup per continuous blocked period.
  Delivery prefers `terminal-notifier -ignoreDnD` (Brewfile; survives
  Focus), falling back to osascript; argv-only `vim.system`, no shell;
  README's Neovim section documents the setup traps.

### Adversarial review of the six follow-up commits (2026-08-10, three Opus reviewers) — fixed in six more commits

Reviewers confirmed the risky surfaces (AppleScript escaping vs real
injection payloads, extmark byte arithmetic, deferred-flag exclusion
from badge/sidebar, `jump_unread`'s removed ack traced to a real
WinEnter in sidekick's `focus()`) and found 11 real defects, all fixed:

- `61281b7` force-ack also resets `attention`/`running` (a dismissed `!`
  showed `»` forever); failed embed no longer leaves a stale stamp that
  mis-acks. In-view swaps, `show_scratch`, `close()`, and
  PersistenceSavePre now `promote()` the outgoing deferred session —
  the in-view paths otherwise reintroduced cmux's silent-drop bug.
- `afe94a4` `<M-u>` also bound in CLI terminals (stamp-resolved, not
  `ai.active`); both bindings notify on a no-op press. Plus the narrow
  refocus ack: `FocusGained` acks only when parked in terminal-mode in
  that session's window (normal-mode sitting keeps the ring).
- `1d793d6` badge and `<leader>aj` share one candidate list
  (`ai.unread_candidates()`: running, excluding the focused session) —
  the badge could name a session the jump refused to route to; `fit()`
  O(n²)→O(1)-ish (33.96ms→0.018ms on a 5k label) and computed once per
  draw; `unread_sessions` ordering now keyed on a monotonic `seq`
  (`os.time()` ties were nondeterministic, visible once the badge named
  sessions).
- `06cf7e6` render() can't strand the sidebar `modifiable` on error;
  `M.rename` rejects control chars; labelled spawning rows keep
  `AgentviewSpawning`.
- `785da78` the episode-flag notification model + terminal-notifier
  (above); notify runs pcall'd after `fire()` (a notifier throw
  previously skipped the UI repaint); body is message-or-phrase, not
  both (same for `<leader>aj`'s notify); summary truncates by display
  cells. terminal-notifier quirk found: a body starting with `-` is
  swallowed to an EMPTY notification (exit 0) — space-padded.
- `07d9a25` the "starting…" placeholder can't outlive the spawn (Attach
  re-embeds on pending OR placeholder-shown OR cursor-row match;
  `sync()` respects a cursor parked on a spawning row).

Accepted, deliberately unfixed: `ambiwidth=double` would break glyph
widths (config never sets it); `focused` starts `true` (urgent before
the first focus event doesn't pop); terminal focus-reporting is
load-bearing for defer/notify; stickybuf's `unpin` restores bufhidden
on the wrong buffer (benign here, upstream wart).

### Knobs, surprises, and unbuilt upgrades — read after living with it

One-time setup: allow **terminal-notifier** in System Settings →
Notifications (macOS asked on first fire). Optional: add it to a Focus
allowlist — though `-ignoreDnD` should cover Focus already.

Tunable constants, if the defaults chafe:

- `BADGE_CELLS = 12` (statusline.lua) — badge label truncation.
- `MSG_CELLS = 100` (agent_events.lua) — notification/`<leader>aj`
  message truncation.
- Sidebar width 30 (agentview.lua `topleft 30vsplit`).
- Notifications are **silent banners** — terminal-notifier supports
  `-sound default` (or any system sound name) if urgent should ding;
  one argv entry in `notify_argv`.

Behaviors that may surprise (each with its one-line tweak if disliked):

- **The badge goes blank when the only ring is the pane you're in** —
  by design (badge and `<leader>aj` share `unread_candidates()`; you're
  looking at it). If it reads as "badge broke", the tweak is rendering
  the focused-session case dimmed instead of hidden in `agent_badge()`.
- **A `●` survives alt-tabbing back in normal mode** — read =
  interaction now. Escapes: enter the pane, enter terminal-mode,
  refocus while parked in t-mode, `<M-u>`, next prompt. If it grates,
  the revert is one branch in the `FocusGained` handler (drop the
  t-mode gate → old blanket ack).
- **Sidebar `<M-]>`/`<M-[>` cycling acks nothing** (sidebar stays
  current — it's preview-grade, same as `j`/`k`). Commit via
  `<CR>`/digits/entering the pane if you want the ack.
- **A deferred turn-complete renders `○`**, indistinguishable from
  quiet, until you walk away. Honest by design (you're looking at the
  result); a distinct dim glyph is the tweak if the held state should
  be visible.
- **One popup per blocked episode** — a second permission prompt while
  you're still away stays silent until you engage. If that under-warns,
  the alternative is dedupe-on-message-change in `notify_desktop`
  (pops per distinct question, at the cost of the idle_prompt double).

Unbuilt upgrades, in rough payoff order:

1. **OSC 9/777 ingestion via `TermRequest`** (critique item 4, still
   the highest ceiling): closes the cursor/pi `!` gap and carries
   preview text; deserves its own plan before building.
2. **Click-to-focus on the notification — TRY THIS NEXT** (flagged
   2026-08-10; small, high payoff): clicking the banner currently does
   nothing. Two rungs:
   - Floor (~1 LOC): `-activate com.mitchellh.ghostty` in `notify_argv`
     raises the terminal app. Verify the bundle id (`osascript -e 'id
     of app "Ghostty"'`) and how it behaves with multiple ghostty
     windows.
   - Full (~10 LOC): `-execute` runs a shell command on click — the
     emitting hook already knows `$NVIM` + `$SIDEKICK_SESSION`, so it
     can bake `nvim --server $NVIM --remote-expr
     'v:lua.require("ai").jump_unread()'` (or a jump-to-*this*-session
     variant) into the argv: click → land in the asking session, same
     path as `<leader>aj`. Caveats: the socket may be dead by
     click-time (harmless failure, but pair with `-activate` so the
     app still raises); quote the baked command carefully; and
     `notify_argv` builds in-process where `$NVIM` is nvim's own
     `v:servername`, not an env passthrough — read it from
     `vim.v.servername`.
3. **`PostToolUse` as "permission resolved"**: still the documented fix
   if the approved-but-`!`-until-Stop staleness annoys; would also let
   the notification episode reset on approval.
4. Cleanup candidates: `last.at` now has no reader (`seq` owns
   ordering) — drop it or re-point `summary` at it; the
   `pcall(require('stickybuf').unpin, …)` in agentview.lua guards the
   call, not the require.

Known-unguarded edge: while a placeholder/scratch shows in the main
pane, the window is unpinned — a stray `:e` there loads a file into the
view until the next embed. Rare enough to accept; re-pin-on-scratch is
the fix if it bites.

An adversarial design review of the shipped view against cmux's current
behavior. Two research corrections first — the plan's "What cmux actually
does" section is out of date on both:

- **cmux's primary transport is OSC (9/777), not hooks** — `cmux notify`
  is the fallback. That's how cmux supports cursor and pi rings without
  per-agent integration files; our hook-only reading is what produced the
  cursor/pi `!` gap, it is not a property of those agents.
- **cmux removed focus-auto-read entirely** (issue #963 → PR #971) after
  shipping exactly the bug we ship: a notification arriving while the
  target pane is focused was silently dropped, unrecoverable. Their fix
  (store unread, suppress only the desktop popup, ack only on explicit
  action) is an inbox answer; ours should defer, not drop (below).

### Ranked follow-ups

1. **Repair the ack model** (highest impact — rings currently feel like
   weather, not a system; three overlapping paths make the last-focused
   session the one that can never ring):
   - Focused-suppression should *defer*, not drop: on turn-complete while
     focused+looking, set a `deferred` flag; promote to `unread` on
     WinLeave/FocusLost; `prompt-submit` clears it. Sitting there stays
     silent; walking away without reading rings. (~8 LOC)
   - Replace the blanket `FocusGained` ack (destroys a ring the frame you
     alt-tab back) with ack-on-first-interaction — `ModeChanged` into
     terminal-mode as the proxy. Read = interaction, not presence.
   - `agentview.embed()` acks when `main_win` is current: in-view
     `<M-N>`/cycle/`<CR>` swaps never fire WinEnter today, so the row and
     badge stay lit while you read the session (and its *next* turn gets
     focus-suppressed — worst of both). `jump_unread` already
     special-cases this; generalize it. (~2 LOC)
   - **Manual dismiss** (quick win, ship first): `M.ack(name, {force})` +
     a sidebar key (`<M-u>`, mirroring cmux's `⌥⌘U`). Today a stuck `!`
     (prompt answered but turn errors, `<Esc>`'d prompt, dropped Stop
     RPC) is permanent: `! 1` lit forever, `<leader>aj` trapped. An
     unclearable top-severity badge is how users stop trusting rings.
2. **Glyph column legibility**: the right-aligned extmark loses to long
   labels (13-char label + dim name overruns 30 cols — `M.rename` has no
   length cap) and right-alignment defeats a single vertical scan. Move
   the glyph to a fixed *leading* column (real text, before the digit);
   merge `·` into `○` (diagnostic distinction, not triage — 6 glyphs → 5).
3. **Badge redesign**: `! <label> +N` / `● <label>`, not `● N` — the
   statusline answers "is this worth interrupting for", an identity
   question; the count is dead weight since `<leader>aj` routes anyway.
   Truncate label ~12 cells; hide inside the view tab (sidebar already
   says it better). Resolves the plan's open badge TODO: per-agent glyph
   rows, tier-split counts, and running counts are all rejected (growth,
   non-actionable distinctions, anti-signal respectively).
4. **OSC 9/777 ingestion via `TermRequest`** (highest ceiling, own
   follow-up plan): nvim 0.12 exposes unhandled OSC to an autocmd with
   the terminal buffer — maps straight to a session, no env bridge, no
   per-agent files, no nested-process guards (~15 LOC). One mechanism
   closes the cursor/pi `!` gap AND delivers notification preview text
   (OSC 777 `title;body` — surface in the `<leader>aj` landing notify,
   not the 30-col sidebar). Caveats to verify: prefer hooks where both
   exist (Claude emits OSC 9 too — dedupe or per-agent preference);
   confirm OSC survives to nvim's parser through the direct terminal
   backend.
5. **Quick wins, one batch**: drop `<Esc>` as a sidebar close key (reflex
   key tearing down the tab; keep `q`); GUIDE.md `●` wording — cleared by
   *entering* the pane, not "looking at it" (preview deliberately doesn't
   ack); `<leader>aj` landing notify shows `last.raw.message` when
   present ("what is it even asking me?"); a one-line "starting…" scratch
   when the cursor previews a spawning `…` row (main pane currently shows
   the previous session).
6. **Urgent-only desktop notification** (small, gated): on an urgent
   transition while `focused == false` — the exact alt-tabbed-away case
   the feature exists for — `osascript display notification`. Urgent-only;
   a `●` popup per turn across four agents trains ignoring them.

### Explicitly not changing (validated better-than-cmux)

- `j`/`k` preview + explicit commit, including preview-not-acking — fix
  the GUIDE wording, never the behavior.
- Two-tier `!`/`●` asymmetry — don't flatten to cmux's binary ring, and
  don't import post-#971 "nothing auto-reads" (right for an inbox of
  discrete notifications, wrong for a per-session boolean — rings would
  sit permanently lit).
- Stable name-sorted order shared by rows/cycle/digits/picker — cmux's
  reorder-on-notify setting would repoint `<M-N>` under time pressure;
  never adopt. (Spawning rows staying unnumbered protects the same
  invariant.)
- Shapes-not-colors glyphs, the dedicated tabpage, no spinner.

Shipped on the `agent-view` branch as the initial six commits below (each
with a `Part-of:` trailer), plus follow-ups: live preview (`7b894bc`),
column restore on close (`0ffe65d`), and — after an adversarial review by
two independent reviewers that verified findings against the sidekick
source — a three-commit hardening batch (`2a4880e` view lifecycle,
`8c86688` kill-by-state/focus-ack/nested-claude env, `935e6e8` hook script
+ setup scripts + docs). A model-preference change (`466ae08`) also rides
on the branch. Phase 3 is untouched. Interactive verification below is
**outstanding** — nothing past the headless list has been exercised in a
real UI session.

- `37b0077` ai.lua groundwork: `M._set_active` export, `M.kill(name)`
  (picker `<C-x>` now delegates to it), `M.open_index(n)`,
  `<M-1>`–`<M-9>` in CLI terminals.
- `35c25e4` `lua/agentview.lua` + delegates/guards + registrations
  (stickybuf, clamp, special_filetypes, 4 row-part highlight groups).
- `4051374` `~/.claude/settings.json` adopted into the claude stow package.
- `d90646a` `claude/.claude/hooks/sidekick-notify.sh` + the 5 hook
  registrations — live in Claude Code from that commit on.
- `64d8d16` `lua/agent_events.lua` + `$SIDEKICK_SESSION` env bridge;
  `init.lua` loads it immediately before `ai`.
- `7bf47a2` glyphs, `<leader>aj`, `● N`/`! N` statusline badge.

### Deltas discovered during execution (now part of the design)

- **Two stray-window paths beyond the planned delegates.** With
  `term.win = nil` during an embed, ANY sidekick show-path splits the view
  tab (`open_win`'s guard is `is_open()`). `M.toggle_active`
  (`<leader>aa`/`<M-a>`, via `cli.toggle`) now delegates to
  `agentview.toggle()` — inside the view, "stash the agent UI" means
  leaving it, keeping `<M-a>`/`<M-v>` symmetric. `M.send` (`cli.send`
  hardcodes `show=true`) refuses with a notify — a context send in the
  view would render against the sidebar, not code.
- **The three `claude/setup-*.sh` scripts clobbered stow symlinks**
  (`jq … > tmp && mv tmp "$SETTINGS"` replaces the *link* with a plain
  file). Fixed with `SETTINGS="$(readlink -f "$SETTINGS")"` before the
  atomic write; verified by running all three post-adoption.
- **Sidebar digits are assigned from the running-only name-sorted list**;
  spawning (`_dynamic == 'registered'`) rows render unnumbered with `…` —
  otherwise a spawning row holding digit N would desync sidebar `N` from
  `<M-N>`/cycle order.
- `agent_events.handle` returns `''` explicitly (`--remote-expr`
  serializes the return value; a table/nil errors on the caller side).
- `<leader>aj` acks directly after landing in addition to the WinEnter
  path: an in-view jump while sitting in the main pane swaps the buffer
  under the cursor, so no WinEnter ever fires (agentview exports
  `enter_main` for this).
- Bare built-ins spawn from `cli.tools.<agent> = {}` untouched, so the
  setup-block env entries (pipeline plan edit 1) are required, not
  optional, for the primary session to carry `$SIDEKICK_SESSION`.
- **Selection model revised during live use (2026-08-10)**: `j`/`k` now
  live-preview the row's terminal in the main pane (buffer swap only —
  the plan's layout-surgery objection didn't survive contact with the
  implementation); commit-as-active stays on `<CR>`/digits/pane entry.
  See the revised "Selection model" rationale below.
- **Column restore on close (2026-08-10, live use)**: opening the view
  over an open `<leader>aa` column hid it (the embed owns the buffer's
  only window) and left the working tab column-less on return — surprising
  in practice. `close()` now re-shows the active session's column in the
  origin tab when one was open at `open()` time.
- **Review hardening (2026-08-10, commits `2a4880e`/`8c86688`/`935e6e8`)** —
  the adversarial review corrected several design assumptions:
  - `SidekickCliAttach` is emitted **synchronously from inside**
    `State.attach`, which calls `terminal:show()` right after the handler
    returns — so hiding the transient window in the handler *caused* a
    fresh split instead of preventing one (reproduced headlessly). The
    view's handler now defers all its work with `vim.schedule`.
  - `embed()` hides a reopened window even when the buffer is already the
    main pane's; the Detach handler only re-embeds when the view tab is
    current (a background view must not steal the working tab's column);
    `restore_solo` survives view re-entry; a last-tab close failure strips
    the tab marker; `PersistenceSavePre` does minimal teardown (no tab
    switch, no column re-show); `pending` clears on close.
  - `M.kill` takes an optional pre-resolved state object and the picker
    passes its row's — a name-only lookup prefers the current-cwd session
    and could kill the wrong one of a same-named pair.
  - Focus-ack has a second trigger: `FocusGained` acks the current
    window's session (a ring raised while nvim was OS-backgrounded was
    otherwise stuck if you were already sitting in that window).
  - Hook script: stdin read bounded (`timeout 2 cat` — a closed pipe hung
    until Claude's hook timeout), mktemp path guarded against quote/
    backslash, nested-claude events dropped (next bullet's heuristic);
    `ai.lua` force-unsets `CLAUDE_CODE_EXECPATH` in job envs as the
    counterpart. Setup scripts refuse to create a plain settings.json
    (post-adoption that made stow abort); the rtk hook self-guards on
    machines without rtk.
- **Accepted: trap-vs-slow-RPC race.** If the hook's `timeout 2` fires while
  nvim's main loop is busy, the EXIT trap unlinks the tmpfile before
  `handle()` reads it — the event is silently dropped. Accepted per the
  pipeline plan's lossy-delivery stance; not worth a fix.
- **Accepted: nested-claude `EXECPATH` heuristic (empirical, dated
  2026-08-10).** `sidekick-notify.sh` treats a set `CLAUDE_CODE_EXECPATH` as
  proof the firing claude is nested inside another claude session and no-ops.
  If a future Claude Code release starts injecting `CLAUDE_CODE_EXECPATH`
  into hook envs too, ALL events would be silently suppressed — this sentence
  is the greppable breadcrumb for that failure mode.

### Verified headless (2026-08-10)

- Full `agent_events` state machine: every transition, urgent-survives-ack,
  prompt-submit clears urgent, `unread_sessions` most-recent-first,
  `clear` GC, garbage/unknown-category inputs inert, `handle` returns `''`.
- Hook script: env-unset no-op (exit 0), stale `$NVIM` fails fast with the
  tmpfile trap-cleaned, and **end-to-end** — script → live `--listen`
  instance → `status('claude 2') == 'unread'` with `last.raw` preserved.
- Env bridge: `cli.tools.claude` carries `SIDEKICK_SESSION` with the
  preset's `format` function intact after the deep-merge.
- View open/close/re-source (module reload + reopen, named-buffer reuse),
  full-config startup clean, `jq` validity of settings.json, setup-script
  idempotence with the symlink surviving.
- Post-review round: nested-claude guard end-to-end (event with
  `CLAUDE_CODE_EXECPATH` set → suppressed; without → delivered as
  `unread`, against a live `--listen` instance); hook script with stdin
  closed exits 0 in ~2s (was: hang); `PersistenceSavePre` teardown with
  the view open removes the tab without switching; setup scripts re-run
  against the live symlink → "already configured", link intact.

### Interactive verification — OUTSTANDING (needs a real session)

Restart Claude Code sessions first so they pick up the new hooks. Then, in
one `env -u NVIM nvim` session:

- [ ] `<leader>av` from a code buffer: view opens, sidebar cursor on the
      active row, agent embedded, `:echo w:sidekick_session_id` populated
      in the main pane (item 1).
- [ ] `<M-]>`/`<M-[>` in the main pane and `<CR>` in the sidebar cycle;
      `▸` and cursor row track; `3` in the sidebar ≡ `<M-3>` in the main
      pane; `<M-3>` from a terminal *outside* the view switches the solo
      column (item 2).
- [ ] Exit restores tab 1 exactly, including a previously-open right CLI
      column at its remembered width (guard 4 / item 3).
- [ ] `n` in the sidebar: no three-column reflow (guard 3), transient
      split hidden, new agent embedded on attach (item 4).
- [ ] Rings with 3 claude sessions: permission prompt in one → `!` on that
      row only; focusing does NOT clear it; answering downgrades to `●` on
      the turn's Stop, which DOES clear on focus; `/clear` resets the row
      without killing it (item 5). **While here: inspect
      `require('agent_events').sessions[name].last.raw` for the
      `UserPromptSubmit` and `Notification` payloads — field names beyond
      the envelope are still unverified against real data.**
- [ ] Focused-suppression (defer semantics, post-`ad056d7`): Stop while
      sitting in that terminal → no ring; then move to another window or
      alt-tab away WITHOUT typing → the deferred ring appears (item 6 +
      item 14a). A permission prompt rings even while focused. Alt-tab
      back and sit in normal mode → ring stays lit; enter terminal-mode
      (type) → clears (the `ModeChanged` ack that replaced `FocusGained`).
- [ ] `<leader>aj` picks the newest of two unread and skips the focused
      session (an unanswered `!` must not trap the jump) (item 7).
- [ ] Non-sidekick `claude` in Terminal.app: hook no-ops (item 8 —
      pipe-tested headless, worth one real-world spot check).
- [ ] Kill the visible agent via sidebar `x`: confirm popup, re-embed of
      next active, no stale row — this is also the real test of the
      stickybuf pin across the kill-last-agent → scratch transition
      (item 9, flagged in Panel registration).
- [ ] Re-source `init.lua` with the view open: no duplicate autocmds,
      panel functional; `<leader>qs` restore doesn't resurrect a blank
      sidebar split (item 10 + the PersistenceSavePre buffer-wipe check).
- [ ] Statusline badge: `● N` appears with the view closed, flips to `! N`
      on a permission prompt, clears at zero; repaint is immediate (the
      lualine refresh autocmd).
- [ ] Phase 3, opencode (item 11): prompt in a sidekick opencode session →
      `»`; finish → `●`; trigger a permission ask → `!` on that row only
      (headless run verified »/● already; the urgent tiers need the TUI).
- [ ] Phase 3, cursor (item 12): prompt → `»`, finish → `●` via the
      Claude-hook merge (headless run only proved sessionEnd — the
      beforeSubmitPrompt/stop pair needs a turn that actually runs; usage
      limit blocked it 2026-08-10). If `»`/`●` never appear, the fallback
      is an explicit `~/.cursor/hooks.json` per the Phase 3 section.
- [ ] Phase 3, pi (item 13): prompt in a sidekick pi TUI → `»`, settle →
      `●`; `/subagents` work must NOT flicker rings mid-turn (the
      PI_SUBAGENT_DEPTH guard).
- [ ] UX follow-ups, ack (item 14): in-view `<M-N>`/cycle/`<CR>` swap
      acks the row while reading it (no more lit row + suppressed next
      turn) AND promotes a deferred ring on the row you swapped away
      from; `<M-u>` (sidebar or inside the CLI) clears a stuck `!` back
      to `○` (not `»`) and un-traps `<leader>aj`; a no-op `<M-u>`
      notifies; refocusing nvim while parked in terminal-mode clears a
      `●` on that pane (normal-mode sitting doesn't).
- [ ] UX follow-ups, sidebar+preview (item 15): leading glyph column
      aligned across all row kinds incl. an unnumbered `…` row; a long
      renamed label overruns rightward without hiding any glyph; `<Esc>`
      in the sidebar no longer closes the view; previewing a spawning
      row shows the "starting…" scratch, not the previous session.
- [ ] UX follow-ups, badge (item 16): `! <label> +N` with two more unread,
      `● <label>` alone for a single unread, label truncated at 12 cells,
      badge hidden while inside the view tab; a ring on the session
      you're sitting in shows NO badge (badge and `<leader>aj` share
      `unread_candidates()` — the jump always reaches what the badge
      names).
- [ ] UX follow-ups, desktop notification (item 17): alt-tab away →
      permission prompt → macOS banner via terminal-notifier (label
      title, message body; allow it in System Settings → Notifications
      first); a second prompt while still blocked stays silent (one per
      episode); answer + a new prompt pops again; never for
      turn-complete; `<leader>aj` landing notify shows the prompt's
      message text.

## Problem

Multiple agent CLI sessions (claude, cursor, opencode, pi — dynamically
named "claude", "claude 2", …) run concurrently via sidekick, but the config
only ever shows one at a time in the right column (`show_solo`), and there is
no dedicated place to *see them all*: which exist, which is active, which
needs attention. cmux (github.com/manaflow-ai/cmux) solves this with a left
sidebar of agent rows plus notification rings; this plan is the nvim-native
MVP of exactly that, scoped to the user's ask: **one leader shortcut →
a dedicated view with a vertical agent list on the left, the selected agent's
real terminal beside it, quick cycling, and a per-agent attention indicator.**
Nothing else from cmux.

## What cmux actually does (research findings that shaped this)

- Lifecycle states `running | idle | needsInput | unknown`, set by **agent
  hooks**, not polling — cmux only aggregates what agents announce.
- The "notification ring" is **binary**: unread-attention → one blue ring,
  cleared when you focus the pane. There is no done/error/idle ring-color
  taxonomy. Activity ("running") is a separate spinner signal.
- Attention persists until acknowledged (focus / jump / mark-read); an event
  for the pane you're already focused on doesn't ring.
- The triage key: jump-to-most-recent-unread.

Two orthogonal signals per agent — activity and attention — is the core
insight this MVP copies.

## Decisions at a glance

| Decision | Choice |
|---|---|
| Entry shortcut | `<leader>av` toggle (+ `<M-v>` inside CLI terminals) |
| View layout | dedicated tabpage: 30-col left sidebar + main pane |
| Selection model | `j`/`k` live-preview the row in the main pane (revised 2026-08-10, first live use); `<CR>`/digits/entering the pane commit it as active |
| Index jumps | rows numbered 1–9: `1`–`9` in the sidebar, `<M-1>`–`<M-9>` in agent terminals |
| Agent window | embed the real terminal buffer via `nvim_win_set_buf` |
| Attention model | binary unread flag + running flag (cmux's two signals) |
| Attention source | Claude Code hooks via the already-designed pipeline in [sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) |
| Acknowledgment | unread (`turn-complete`) clears on focus; urgent (needs input/permission) persists until actually answered |
| Triage key | `<leader>aj` — jump to most recent unread |
| Non-Claude agents | wired natively in Phase 3 — opencode plugin (full rings), cursor via its native Claude-hook merge (running + done + session-end, no hooks.json), pi extension (running + done); no polling heuristics anywhere |
| Ambient signal | statusline unread-count badge when the view is closed |

## Architecture

Three parts, two new modules; the sidebar knows nothing about hooks and the
event registry knows nothing about UI:

```
claude/.claude/hooks/sidekick-notify.sh  (+ settings.json registrations)
      │  $NVIM + $SIDEKICK_SESSION env bridge (pipeline plan, unchanged)
      ▼
lua/agent_events.lua      state registry: unread/running per session name,
      │                   ack API, fires User AgentSessionEvent
      ▼
lua/agentview.lua         the view: tabpage, sidebar buffer, embed logic
      │                   (also consumed later by a statusline badge)
      ▼
lua/ai.lua                existing session layer — reused, ~15 LOC of
                          delegates/guards added
```

`agentview.lua` degrades gracefully when `agent_events` isn't loaded
(pcall-guarded): the view works with no attention glyphs. This makes Phase 1
(view) shippable before Phase 2 (rings).

## Phase 1 — the view (`lua/agentview.lua`)

### Entry/exit

- `<leader>av` (normal, global, `desc = 'AI: Agent view (toggle)'`; falls
  under the existing `<leader>a` which-key group — no whichkey.lua change).
  Lazy `require('agentview')` at keypress, like `pickers/*`.
- `<M-v>` (`{ 't', 'n' }`, buffer-local) added to the `FileType
  sidekick_terminal` autocmd in `ai.lua`, same toggle — consistent with the
  `<M-a>`/`<M-l>`/`<M-n>` in-panel family.
- Toggle, three states: no view tab → create it (remember `origin_tab`);
  view tab exists but not current → switch to it and re-sync (re-embed
  `ai.active`, redraw sidebar); currently in it → `tabclose`, return to
  `origin_tab` if still valid.

### Why a dedicated tabpage (not an in-place left panel)

- "A view I enter" is a mode switch; a tabpage is nvim's native mode switch,
  and this config already blesses own-tabpage tools (Neogit, diffview).
- The left edge is exclusively coordinated by `buffers.lua`'s
  nvim-tree/aerial swap machinery; an in-place panel would have to join that
  registry and fight for the edge. A fresh tab avoids it entirely.
- Exit = close the tab; the working tab's layout (including a right CLI
  column) is untouched by construction.

Tab structure: `tabnew` (its empty window becomes `main_win`) →
`vim.t[tab].agentview = true` marker → `topleft 30vsplit` sidebar. Window
opts set by win id after creation (panel convention), `winfixwidth`,
`cursorline`, no numbers/signs, `wrap=false`.

### Embedding the agent's terminal

`V.embed(name)`: find the terminal by tool name, `t:hide()` if open (while
the view owns display, sidekick owns zero windows), then
`nvim_win_set_buf(main_win, t.buf)` and **re-stamp the window**:
`vim.w[main_win].sidekick_cli`, `.sidekick_session_id`, plus
`.agentview_main = true`. The stamps are window-scoped; without them the
WinEnter active-tracker and the byte-forward keys (`u`, `p`, `<C-u>`, …)
silently die in our window. Never `cli.show()` inside the view — sidekick's
`open_win` would split the current tab per `layout='right'`, and a terminal
whose window lives in another tab makes `focus()` yank the user out of the
view.

Sessions that are registered but not started are not listed; creation goes
through sidebar `n` → `ai.new_session()`, whose `show_solo` call the
delegate (below) routes back into the view: it opens via
`cli.show({name=..., focus=false})` (the sanctioned auto-start door), marks
the name pending, and the view's `SidekickCliAttach` handler hides the
transient split and embeds.

### ai.lua integration (~15 LOC, the whole trick)

1. `show_solo` delegate at the top of the function:
   `local av = package.loaded['agentview']; if av and av.is_active() then
   return av.select(name) end` — every existing switch path (`cycle`,
   `toggle_last`, picker, `create_session`) becomes view-aware for free.
   `is_active()` requires the view tab to be *current*, so working in tab 1
   while the view idles in tab 2 uses the normal right-column path.
2. Same-pattern delegate in `M.focus` (else `<C-.>` inside the view splits
   the view tab).
3. Promote-autocmd guard in the `SidekickCliAttach` callback:
   `if vim.t[current_tab].agentview then return end` — without this, a
   session starting while the view is current gets `wincmd L`-promoted and
   reflows the view into three columns.
4. `remember_width` guard in `WinClosed`:
   `if vim.w[win].agentview_main then return end` — else closing the view
   records the huge main-pane width as the CLI column width and the next
   `<leader>aa` opens a giant right column.
5. Export `M._set_active = set_active`; add small public
   `M.kill(name)` (generalizes `kill_active`) for the sidebar's `x`.

### Sidebar buffer

- One scratch buffer reused across open/close and re-sources (looked up by
  name `agentview://agents`; `buftype=nofile`, `bufhidden=hide`,
  `filetype=agentview` set last).
- Rows: running sessions from `sidekick.cli.state.get({started=true})` plus
  in-flight spawns from `ai._dynamic == 'registered'`, sorted by name — the
  same order as `ai.cycle`, so `j`/`k` order equals `<M-]>`/`<M-[>` order.
- Row = status glyph in a fixed leading column (real text — revised by
  UX follow-up 2, `c085088`; originally a `right_align` extmark, which
  lost to long labels and defeated a vertical scan), index digit (dim,
  rows 1–9 only; later rows get a blank column), active marker (`▸`),
  display label (bright) with raw name demoted (`Comment`) — same
  convention as the `<leader>al` picker. The index is display order
  (name-sorted), so it's also cycling order.
- Keymaps read a `rows_by_lnum` table, never parse buffer text.
- Refresh: one debounced (single `vim.schedule` coalesce) `render()`, driven
  by `User SidekickCliAttach`/`SidekickCliDetach`, `User AgentSessionEvent`,
  and `WinEnter` (active-marker moves). No polling. Hidden panel renders
  lazily on next open. Augroup `UserAgentview`, `clear=true`.
- Cursor sync: when re-rendering and the sidebar is not the current window,
  snap its cursor to `ai.active`'s row; never yank the cursor while the user
  is browsing inside the sidebar.

### In-sidebar keymaps (buffer-local, all `desc = 'AI: …'`)

| Key | Action |
|---|---|
| `<CR>` | select + focus session under cursor (`set_active` + embed) |
| `1`–`9` | select + focus row N directly (cmux's number-jump) |
| `<M-]>` / `<M-[>` | `ai.cycle(±1)` (same keys as inside the terminal) |
| `n` | `ai.new_session()` |
| `r` | `ai.rename(row, refresh)` |
| `x` | `utils.confirm` → `ai.kill(row)` |
| `<M-u>` | force-dismiss the row's ring, any tier (UX follow-up 1) |
| `q` | close the view (`<Esc>` dropped in UX follow-up 5 — reflex key) |

**Selection model — revised 2026-08-10 after first live use.** The plan
originally chose explicit `<CR>` over cmux-style live-switch, fearing
per-keystroke window surgery and `M.active`/`M._last` thrash. Half of that
fear was wrong: inside the view a switch is just `nvim_win_set_buf` — no
layout surgery. So `j`/`k` now **preview**: a CursorMoved handler swaps the
row's terminal into the main pane immediately (skipping spawning rows), but
does NOT touch `M.active`/`M._last` — the half of the objection that was
right. Commit stays explicit: `<CR>`/digits, or entering the pane (the
embed re-stamp makes the WinEnter tracker commit whatever you're looking
at). Browsing and leaving keeps the pool exactly as it was.

**Index jumps** (cmux's `⌘1–8`, `indexed_select`'s `<M-1>`–`<M-9>`): plain
`1`–`9` in the sidebar select row N (safe — it's a list panel, digits have
no other job; count-prefixes are worthless in a ≤10-row list). In agent
terminals, `<M-1>`–`<M-9>` (`{t,n}`, added to the `FileType
sidekick_terminal` maps in `ai.lua`) switch to session N in the same
name-sorted order — working both inside the view (via the `show_solo`
delegate) and outside it, like `<M-]>` does today. Capped at 9 by design;
a 10th+ session keeps `j`/`k`/`<CR>` and cycling.

### Panel registration

`special_filetypes` yes; `sidebar_filetypes` **no** (it is not a left-edge
panel of the working tab — the tabpage decision — and must not feed the
quit-when-only-sidebars autocmd); stickybuf `get_auto_pin` arm;
`clamped_panels` yes (nowrap list panel). The main window gets auto-pinned
to `sidekick_terminal` by filetype once it shows a CLI buffer; verify the
kill-last-agent → scratch transition against the pin during testing.

### Exit/cleanup/persistence

- Terminals keep running on close: the view's windows were never in
  sidekick's registry (`term.win` stayed nil after the embed-time hide), so
  back in tab 1 `<leader>aa` opens a fresh right split at the remembered
  width. **Revised 2026-08-10 (live use)**: the open-time embed hides an
  open `<leader>aa` column, which read as "sidekick disappeared" — so
  `open()` remembers a column was open in the origin tab and `close()`
  re-shows the active session there (unfocused, remembered width) instead
  of requiring a manual re-summon.
- Manual `:q`/`:tabclose` needs no teardown handler — every entry point
  validates tab/win handles and rebuilds; the `vim.t` marker dies with the
  tab.
- Persistence: the sidebar scratch would restore as a blank split.
  agentview registers its own `User PersistenceSavePre` handler closing the
  view tab (feature-local augroup; don't grow session.lua's list).

### Edge cases

- Zero running agents: sidebar shows `(no running agents)` + hint; `n`
  creates one; main pane keeps a scratch with a one-line hint.
- Killing the visible agent: the Detach sweep repoints `M.active`; the
  view's Detach handler re-embeds the new active or falls to empty state.
- View open in tab 2 while interacting from tab 1: tab-1 flows take the
  normal path (`is_active()` false); the view re-syncs on every re-entry.

## Phase 2 — attention rings (`lua/agent_events.lua` + hooks)

The transport is the already-designed pipeline
([sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md)):
`$SIDEKICK_SESSION` env injection per session, `$NVIM` RPC via
`--remote-expr`, tmpfile protocol, `timeout 2`, always-exit-0. None of that
is redesigned. What the dashboard adds on top:

### Hook registrations (MVP cut — 5 entries, one shared script)

| Hook | Category | Role |
|---|---|---|
| `Stop` | `turn-complete` | attention (medium) |
| `Notification` matcher `permission_prompt` | `needs-permission` | attention (high) |
| `Notification` matcher `idle_prompt` | `needs-input` | attention (high) |
| `UserPromptSubmit` | `prompt-submit` | activity signal (added vs pipeline plan) |
| `SessionEnd` | `session-end` | bookkeeping — clears state on `/clear`/resume, which `SidekickCliDetach` can't see |

Dropped for MVP: `SubagentStop` (a ring for subagent completion trains you
to ignore rings) and `SessionStart` (nvim already knows sessions exist
before Claude's hook could say so).

### State model (per session name)

```lua
M.sessions[name] = {
  unread    = false,  -- the ring; cleared only by ack
  attention = nil,    -- 'needs-permission'|'needs-input'|'turn-complete'
  running   = false,  -- between prompt-submit and turn end
  last      = { category, at, raw },
}
```

Transitions (hooks arrive in temporal order; last-writer-wins):

```
prompt-submit    → running=true; unread=false, attention=nil
                   (real interaction — the only thing that clears urgent)
needs-permission → running stays true; unread=true   (turn blocked, not over)
needs-input      → running=false;     unread=true
turn-complete    → running=false;     unread=true*
session-end      → running=false; unread=false
ack (focus)      → clears unread ONLY when attention == 'turn-complete';
                   urgent states are untouched by focus
* turn-complete only: DEFERRED (not dropped — revised by UX follow-up 1,
  `ad056d7`) when it targets the currently-focused window while nvim has
  OS focus: a `deferred` flag promotes to unread on WinLeave/FocusLost,
  and clears on prompt-submit or interaction. Urgent events always set
  unread — a block is a block regardless of where you're looking.
```

Running detection uses the `UserPromptSubmit` hook rather than nvim-side
inference (impossible — keys go straight to the terminal job) or polling
(banned). Glyph is static, no spinner animation. A dropped Stop RPC leaves
a stale `running` that self-heals on the next event — accepted.

### Acknowledgment — two tiers, deliberately asymmetric

Looking at an agent is enough to acknowledge "I finished a turn", but NOT
enough to resolve "I need something from you" — an urgent state must
survive focus and only clear when the user actually responds:

- **`turn-complete` (`●`)**: ack-on-interaction autocmds in
  `agent_events.lua` (the state owner) — `WinEnter`, plus `ModeChanged`
  into terminal-mode (revised by UX follow-up 1, `ad056d7`: the blanket
  `FocusGained` ack destroyed a ring the frame you alt-tabbed back; read
  = interaction, not presence): if the entered/typed-in window's
  `sidekick_cli` stamp names a session whose attention is
  `turn-complete`, `M.ack`. This is why the view re-stamps embedded
  windows. In-view swaps ack via `embed()` when `main_win` is current
  (no `WinEnter` fires on a buffer swap — `<leader>aj`'s old direct ack
  generalized).
- **`needs-permission` / `needs-input` (`!`)**: no focus-ack. Cleared by
  real progress only: `prompt-submit` (the user typed a prompt there), or
  superseded by the session's next attention event (answering a permission
  prompt resumes the turn, whose eventual `Stop` downgrades `!` to `●`) —
  or manually via sidebar `<M-u>` / `M.ack(name, {force=true})` (UX
  follow-up 1, `3a1cdd8`: a stuck `!` was otherwise permanent).
  Known MVP staleness: between approving a permission and the turn's next
  event, the row still shows `!` — accepted; registering `PostToolUse` as
  a "permission resolved" signal is the documented upgrade if this annoys
  in practice.
- `<leader>aj` (`desc = 'AI: Jump to unread agent'`): most-recent unread →
  the normal show/focus path. Landing acks a `turn-complete` ring (via the
  WinEnter above — one code path); an urgent ring stays lit until answered.
  Repeat presses must therefore skip the currently-focused session, or an
  unanswered `!` would trap the jump on itself. Notify + no-op when nothing
  is unread.

### API surface (UI-agnostic)

```lua
M.handle(tmpfile)               -- RPC entry + state machine
M.status(name) -> 'urgent'|'unread'|'running'|'idle'|'none'
M.unread_sessions() -> name[]   -- most-recent-first (jump key, badge)
M.ack(name)                     -- no-op unless attention=='turn-complete';
                                -- fires AgentSessionEvent kind='ack'
M.clear(name)                   -- lifecycle GC; wired into ai._forget + kills
```

`User AgentSessionEvent` payload:
`data = { session, kind = 'event'|'ack'|'clear', category?, unread, running }`
— fired on every transition including acks, so the sidebar is a pure
subscriber.

### Visualization

| Status | Condition | Glyph | Group | Links to |
|---|---|---|---|---|
| urgent | unread, needs-permission/input | `!` | `AgentviewUrgent` | `DiagnosticWarn` |
| unread | unread, turn-complete | `●` | `AgentviewUnread` | `Special` |
| running | not unread, running | `»` | `AgentviewRunning` | `DiagnosticOk` |
| idle | entry exists, quiet — or no entry yet | `○` | `AgentviewIdle` | `Comment` |
| spawning | `_dynamic == 'registered'` | `…` | `AgentviewSpawning` | `NonText` |

(`·`/`AgentviewNoSignal` merged into `○` by UX follow-up 2, `c085088` —
the no-entry-yet distinction was diagnostic, not triage.)

Distinct shapes (not just colors) keep the urgent/unread distinction legible
without status text — a deliberate deviation from cmux's single-glyph ring.
Unread beats running in display precedence. Red is reserved for a future
`StopFailure` category; nothing here is an error. Row-part groups:
`AgentviewActive` → `Function`, `AgentviewLabel` → `Special`,
`AgentviewName` → `Comment`. All links live in `themes.lua`
`global_overrides` — no hex anywhere.

A session that hasn't produced an event yet renders `○` like any quiet
one; after Phase 3 all four agents emit real signals (with per-agent
tiers — see the support matrix below). No polling heuristics anywhere: output-churn
detection would need timers and confidently lies (TUI spinners churn while
idle).

### Ambient badge (view closed)

One statusline segment — `! <label> +N` / `● <label>` (revised by UX
follow-up 3, `5321473`; originally `● N`): names the most-recent urgent
session, else the most-recent unread, with ` +N` for the remaining
unread. Label via `ai.display()`, truncated to 12 cells; hidden at zero,
hidden inside the view tab (the sidebar says it better), colored
urgent-if-any-urgent, purely reactive reads — no timers. Without it the
attention system is invisible whenever the view is closed.

The former open TODO here is resolved: the identity question ("is this
worth interrupting for") beat every counting variant. Rejected: per-agent
glyph rows (growth), tier-split counts (non-actionable distinction),
running counts (anti-signal).

## Phase 3 — rings for cursor / opencode / pi

Researched against both cmux's shipped integrations (it wires all three via
per-agent hook/plugin/extension files — proven ground, no polling anywhere)
and each agent's current official docs. Every agent reuses the same
transport: it runs inside a sidekick terminal job, so its hook/plugin
subprocesses inherit `$NVIM` + `$SIDEKICK_SESSION` and can invoke the same
`sidekick-notify.sh <category>` script → same RPC → same registry. The
nvim side (`agent_events.lua`, sidebar, badge, `<leader>aj`) needs **zero
changes** — Phase 3 is purely agent-side emitters.

### Support matrix

| Category | claude | opencode | cursor | pi |
|---|---|---|---|---|
| running (`»`) | `UserPromptSubmit` | `chat.message` hook | `beforeSubmitPrompt` | `before_agent_start` |
| turn-complete (`●`) | `Stop` | `session.idle` event | `stop` hook | `agent_settled` (pi >= 0.80.5; else `agent_end`) |
| needs-permission (`!`) | `Notification`/`permission_prompt` | `permission.asked` event | none (workaround only) | none |
| needs-input (`!`) | `Notification`/`idle_prompt` | `question.asked` event | none | none |
| session-end | `SessionEnd` | `session.deleted` | `sessionEnd` | `session_shutdown` |

### opencode — full rings (best non-Claude support)

A single TS plugin, stowed in the existing `opencode` stow package →
`~/.config/opencode/plugins/nvim-notify.ts` (auto-loaded; plugins run
in-process in the opencode server, so `process.env.NVIM` is directly
readable and Bun's `$` shell inherits env):

- `chat.message` hook → `prompt-submit`
- `event` hook: `session.idle` → `turn-complete`, `permission.asked` →
  `needs-permission`, `question.asked` → `needs-input`,
  `session.deleted` → `session-end`
- Guard: no-op unless `NVIM` + `SIDEKICK_SESSION` are set (same rule as
  the shell script).
- Caveats: `question.asked` is source-verified but undocumented — degrade
  gracefully if absent; `session.idle` is marked deprecated in favor of
  `session.status` (`status.type == "idle"`) — listen for both. In
  client/server mode (`opencode serve`) the server's env is not the nvim
  terminal's; sidekick launches the TUI directly, so this doesn't apply
  here. Requires un-stubbing nothing — the `ai.lua` session-backend stub
  only disables sidekick's *discovery* shell-outs, not the plugin.

### cursor — running + done, no urgent tier

Two routes; take the free one first:

- **Free route (preferred): Claude-hook merging.** cursor-agent reads
  `~/.claude/settings.json` and maps `UserPromptSubmit` →
  `beforeSubmitPrompt` and `Stop` → `stop` — the Phase 2 hook
  registrations fire for cursor sessions with zero new config, and the
  script already keys the right session via `$SIDEKICK_SESSION`
  (`"cursor 2"` etc.). Claude's `Notification` matcher events are
  explicitly NOT merged, so no `!` tier.
- **Fallback (if the merge proves flaky): explicit `~/.cursor/hooks.json`**
  (`{"version":1, "hooks":{"beforeSubmitPrompt":[...], "stop":[...],
  "sessionEnd":[...]}}`) calling the same script. Env inheritance for hook
  subprocesses is undocumented — verify `$NVIM` arrives; if not, a
  `sessionStart` hook can re-export env for later hooks. Would live in a
  new `cursor` stow entry.
- Urgent gaps: no needs-input hook exists (cursor's built-in
  terminal-notification feature is OSC-based — a future `TermRequest`
  listener could catch it); needs-permission only via a
  `beforeShellExecution` side-effect pattern — deferred, telemetry-grade.

### pi — running + done via a stowed extension

A TypeScript extension in the existing `pi/` stow package →
`~/.pi/agent/extensions/nvim-notify.ts` (cmux ships exactly this shape;
extensions dir is stow-safe — pi only owns `settings.json`, which stays
machine-local per the package's existing rule):

- `pi.on('before_agent_start')` → `prompt-submit`
- `agent_settled` + `ctx.isIdle()` → `turn-complete` (pi >= 0.80.5;
  `agent_end` fallback for older versions — cmux version-detects, we can
  just require a floor version since this repo pins pi's install)
- `session_start` / `session_shutdown` → bookkeeping
- Extension spawns the shared shell script; same env guard. No permission/
  question events in pi's vocabulary today → no `!` tier.
- Coordinate with plans/pi-extensions-integration.md (the `@narumitw`
  extension batch) so both land through the same `pi/` package
  conventions.

### What this changes elsewhere

- The `·` no-signal glyph stops meaning "agent has no integration" and
  just means "no event yet this session".
- The support-tier asymmetry is honest UI: a cursor/pi session can show
  `»`/`●`/`○` but never `!` — document that in GUIDE.md so absence of `!`
  isn't read as "nothing needed".
- Statusline badge, `<leader>aj`, ack semantics: unchanged — they consume
  the registry, which is agent-agnostic by construction.

## Implementation order

1. **Phase 1** — `agentview.lua` + ai.lua delegates/guards + registrations
   (`buffers.lua`, `plugins.lua` stickybuf, `autocmds.lua` clamp,
   `themes.lua` groups, `keymaps.lua`). Ships standalone: view, cycling,
   session management, no glyphs.
2. **Phase 2a** — hook script + `settings.json` registrations in the
   `claude` stow package (note: `claude/.claude/` has no `settings.json`
   yet — adopt the machine-local one into stow first, via the update-config
   flow). First run logs raw hook stdin per event type before trusting
   field names (pipeline plan's own verification step), especially
   `UserPromptSubmit`.
3. **Phase 2b** — `agent_events.lua` (+ `init.lua` require — must be loaded
   for the `v:lua` RPC to resolve), env injection in `ai.lua`,
   `M.clear` wired into `_forget`/kills, `<leader>aj`, statusline badge.
4. **Phase 3** — one agent at a time, in payoff order: opencode plugin
   (full rings) → pi extension → cursor (verify the free Claude-hook merge
   before writing any hooks.json). Each lands in its own stow package with
   its README.md section updated in the same change.
5. **Docs, same change as each phase** — GUIDE.md Architecture bullets +
   Load order + keymap rows in the `## AI (sidekick.nvim)` section table;
   this plan's entry in plans/README.md.

## File-by-file (merged)

| File | Change | est. LOC |
|---|---|---|
| `lua/agentview.lua` | new — view + sidebar + embed + refresh | ~220–260 |
| `lua/agent_events.lua` | new — registry, state machine, ack, API | ~150 |
| `claude/.claude/hooks/sidekick-notify.sh` | new — shared hook script | ~30 |
| `claude/.claude/settings.json` | new in stow — 5 hook registrations | ~45 |
| `lua/ai.lua` | delegates, guards, env injection, `M.kill`, `M.open_index(n)`, `<M-v>`, `<M-1>`–`<M-9>` | ~40 |
| `lua/keymaps.lua` | `<leader>av`, `<leader>aj` | ~8 |
| `lua/buffers.lua` | `special_filetypes.agentview` | 1 |
| `lua/plugins.lua` | stickybuf `get_auto_pin` arm | 3 |
| `lua/autocmds.lua` | `clamped_panels.agentview` | 1 |
| `lua/themes.lua` | 9 linked `Agentview*` groups | ~10 |
| `lua/statusline.lua` | unread badge segment | ~15 |
| `lua/init.lua` | `require('agent_events')` | 1 |
| `opencode/.config/opencode/plugins/nvim-notify.ts` | new (Phase 3) — full-ring plugin | ~40 |
| `pi/.pi/agent/extensions/nvim-notify.ts` | new (Phase 3) — running/done extension | ~35 |
| `cursor` stow entry (`.cursor/hooks.json`) | only if the Claude-hook merge proves flaky | ~15 |

## Verification

1. `<leader>av` from a normal buffer: view opens, sidebar cursor on active
   row, main pane shows the active agent, stamps present (`:echo
   w:sidekick_session_id`).
2. `<M-]>`/`<M-[>` in the main pane and `<CR>` in the sidebar cycle
   correctly; `▸` and cursor row track. `3` in the sidebar and `<M-3>` in
   the main pane both land on row 3; `<M-3>` from a terminal outside the
   view switches the solo column to session 3.
3. Exit restores tab 1 exactly, including a previously-open right CLI
   column at its remembered width (guard 4).
4. Start a new session from inside the view (`n`): no three-column reflow
   (guard 3), transient split hidden, new agent embedded.
5. Pipeline: with 3 claude sessions, trigger a permission prompt in one —
   only that row shows `!`; focusing it does NOT clear the glyph; answering
   the prompt does (downgrade to `●` on the turn's Stop, then focus-ack).
   A `turn-complete` `●` DOES clear on focus alone. `/clear` in a session
   resets its state without killing the row.
6. Focused-suppression: trigger Stop while sitting in that terminal → no
   ring; alt-tab to another app first → ring appears. A permission prompt
   rings even while you sit in that terminal (urgent is never suppressed).
7. `<leader>aj` picks the newest of two unread sessions, and skips the
   session currently focused (an unanswered `!` must not trap the jump).
8. Non-sidekick `claude` in Terminal.app: hook script no-ops (env guard).
9. Kill the visible agent from the sidebar: confirm prompt, re-embed of
   next active, no stale row.
10. Re-source `init.lua` with the view open: no duplicate autocmds, panel
    still functional (augroup clear, buffer reuse).
11. Phase 3, opencode: prompt in an opencode session → `»`; let it finish
    → `●`; trigger a permission ask → `!`; all in the right row only.
12. Phase 3, cursor: confirm the Claude-hook merge fires our script
    (`beforeSubmitPrompt`/`stop` → `»`/`●`) with `$NVIM` +
    `$SIDEKICK_SESSION` intact in the hook's env; if not, fall back to
    explicit hooks.json and retest.
13. Phase 3, pi: prompt → `»`, settle → `●`; extension no-ops cleanly for
    pi runs outside sidekick (env guard).

## Out of scope (MVP)

- Spinner animation, per-category mute rules. (Desktop notifications
  landed urgent-only via UX follow-up 6, `7917d3d` — broader
  per-category notification rules remain out of scope.)
- Urgent (`!`) tier for cursor (no needs-input hook exists; its built-in
  OSC terminal notifications via a `TermRequest` listener is the future
  path) and for pi (no permission/question events in its vocabulary yet).
- Notification history/preview text in rows (cmux shows last-notification
  previews; needs payload fields confirmed first).
- `SubagentStop`/`SessionStart` categories; `StopFailure` (add when its
  matcher/payload is confirmed — reserve red).
- Statusline click-to-jump; multi-agent grid layouts.
