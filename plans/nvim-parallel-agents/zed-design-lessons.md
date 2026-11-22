# Zed parallel agents: design lessons for the nvim (Lua) port

Research and scoping only. This doc decides nothing and builds nothing.

- **Zed source:** `~/src/zed`, HEAD `596dfdcf32` (commit date 2026-11-15).
  Read-only; nothing was built or run.
- **Written:** 2026-11-22.
- **nvim side:** the shipped `nvim/.config/nvim/` config as of branch
  `plan/nvim-parallel-agents`: `lua/ai.lua`, `lua/agentview.lua`,
  `lua/agent_events.lua`, `sk/cli/omp.lua`, the hooks in
  `claude/.claude/hooks/` and `omp/.omp/agent/extensions/nvim-notify.ts`.
  Also sidekick.nvim as installed: vim.pack, commit `17447a0`, at
  `~/.local/share/nvim/site/pack/core/opt/sidekick.nvim`.
- **Scope:** how Zed designed its agent, multi-thread and parallel-agent
  features (architecture, abstractions, state models, trade-offs visible in
  git history), and which parts carry over to a Lua implementation that
  runs agent CLIs in terminal buffers.
- **Not in scope:** what Zed offers the user. That is the companion
  `zed-feature-survey.md`, and this doc does not repeat its catalogue.

Paths below are relative to `~/src/zed/crates/` unless they start with `~`
or name a dotfiles file. Line numbers are approximate. Where a claim rests on
my reading of code rather than a comment or commit message, it says
"inferred".

## Contents

- [Summary](#summary)
- [1. Two thread families, one surface](#1-two-thread-families-one-surface)
- [2. Identity: stable local id, agent session id, display title](#2-identity-stable-local-id-agent-session-id-display-title)
- [3. The status model and how it reaches the UI](#3-the-status-model-and-how-it-reaches-the-ui)
- [4. Event flow, rendering and write batching](#4-event-flow-rendering-and-write-batching)
- [5. Terminal threads under the hood](#5-terminal-threads-under-the-hood)
- [6. Attention and notifications](#6-attention-and-notifications)
- [7. Many live threads: retention and performance](#7-many-live-threads-retention-and-performance)
- [8. Change tracking: action log, review, checkpoints](#8-change-tracking-action-log-review-checkpoints)
- [9. Worktree isolation](#9-worktree-isolation)
- [10. Persistence and restore](#10-persistence-and-restore)
- [11. Connections, processes, permissions, queueing](#11-connections-processes-permissions-queueing)
- [12. Actions, keymaps, settings](#12-actions-keymaps-settings)
- [What does not transfer to terminal mode](#what-does-not-transfer-to-terminal-mode)
- [Constraints and risks for a Lua implementation](#constraints-and-risks-for-a-lua-implementation)
- [Candidate architectures](#candidate-architectures)
- [Open questions](#open-questions)
- [Appendix: design history worth knowing](#appendix-design-history-worth-knowing)

## Summary

Zed runs two kinds of thread side by side:

- **ACP threads** are fully structured. Zed sees every message, tool call,
  permission request, file write and state change.
- **Terminal Threads** are a shell in a PTY. Zed sees only what any terminal
  emulator sees: the title, a bell, the working directory, the exit.

The user's setup is the terminal kind. Two facts follow:

1. **On status, the nvim side is already ahead of Zed's own terminal mode.**
   Zed's Terminal Threads have one bit of status: "rang the bell while you
   weren't looking". `agent_events.lua` has a five-state model fed by CLI
   hooks, plus deferral, ack rules and a jump-to-unread key. Zed has no
   jump-to-unread at all. The lessons here are refinements (an error state,
   resolving a permission ring, OSC as a universal fallback), not a rebuild.
2. **The rich Zed lessons come from the ACP side, and most of them are about
   structure, not wire protocol.** These carry over to terminal mode:
   - a stable local id separate from the agent's session id
   - status derived at render time from source state
   - "seen" tracked by transitions and held by the list, not the thread
   - eviction that only touches what can be reloaded
   - git-based worktree isolation with safe archive and restore
   - diff review against a per-session baseline

   What does not carry over is anything that needs Zed to sit between the
   agent and the filesystem, or between the agent and the permission prompt.

The single most useful finding for change tracking: **Zed removed
per-message git checkpoints in October 2026** (`eee7501970`). Snapshotting
every repo before each message took tens of seconds in large workspaces. Any
"snapshot on every prompt" design in Lua should start from that warning.

## 1. Two thread families, one surface

### How Zed does it

- `agent_ui/src/agent_panel.rs` holds both families in one panel:
  - `BaseView::{Uninitialized, AgentThread { conversation_view }, Terminal { terminal_id }}`
    is what the panel body shows.
  - `retained_threads: HashMap<ThreadId, Entity<ConversationView>>` holds
    the ACP threads that are live but not shown.
  - `terminals: HashMap<TerminalId, AgentTerminal>` holds every terminal
    thread.
- The sidebar (`sidebar/src/sidebar.rs`) renders
  `ListEntry::{ProjectHeader, Thread(Arc<ThreadEntry>), Terminal(TerminalEntry)}`.
  The thread switcher (`sidebar/src/thread_switcher.rs`) has the matching
  `ThreadSwitcherEntry::{Thread, Terminal}`.
- Each family has its own metadata store and SQLite table:
  `ThreadMetadataStore` (`sidebar_threads`) and `TerminalThreadMetadataStore`
  (`sidebar_terminal_threads`).
- Grouping, ordering, activation, rename and close are shared code paths:
  - grouping by main-worktree path list
  - `ThreadEntryWorkspace::{Open, Closed}`
  - `ActiveEntry::{Thread, Terminal}`
  - `RenameTarget::Terminal`
- The families differ in capability, not in surface:
  - terminal rows carry only `has_notification: bool`
  - ACP rows carry `AgentThreadStatus`, diff stats, title generation and
    draft state

### Why

The docs say "Zed owns the thread surface", and that the CLI owns auth,
model, tools, skills and MCP (`docs/src/ai/terminal-threads.md`). The
introducing commit (`5fc8a836dd`, "Experimental Terminal Mode") was framed
as "manage terminal sessions along with threads in the sidebar". The design
treats a terminal as a thread with a thin capability set, rather than a
separate feature.

### Lesson for nvim/Lua

- The current config has no session abstraction of its own. A "session" is
  whatever `require('sidekick.cli.state').get({ started = true })` returns,
  keyed by tool name. `agentview.rows()` and `ai.cycle()` both re-derive the
  list from sidekick on every call.
- Zed's split suggests a small registry module that owns rows and stores
  capabilities per row, instead of the UI reading sidekick's internal state
  directly. A sketch (name to be decided, e.g. `agent_sessions.lua`):

  ```lua
  -- one row per agent session, whoever spawned it
  M.rows[id] = {
    id = id,               -- stable local id (see section 2)
    kind = 'terminal',     -- room for 'acp' later; today always terminal
    agent = 'claude',      -- from AGENTS
    label = nil,           -- user-set display name
    title = nil,           -- last OSC title (b:term_title / TermRequest)
    cwd = '/path',         -- worktree path if isolated
    main_root = '/path',   -- `git rev-parse --git-common-dir` parent: grouping key
    agent_session_id = nil,-- from the CLI's SessionStart hook, for resume
    created_at = 0, last_access = 0,
    caps = { hooks = true, osc = true, resume_by_id = true },
    bufnr = nil, job = nil -- nil when dormant (restored but not spawned)
  }
  ```

- `agentview.lua` would render `M.rows` and `agent_events` would key into
  it. `ai.lua` keeps its sidekick calls, but only as the spawn and display
  backend.
- This is also the seam a later ACP experiment would plug into, without
  touching the sidebar.

## 2. Identity: stable local id, agent session id, display title

### How Zed does it

- `ThreadMetadata` (`agent_ui/src/thread_metadata_store.rs`) separates three
  things:
  - `thread_id: ThreadId(uuid)`, the local primary key
  - `session_id: Option<acp::SessionId>`, the agent's id. It is `None` for a
    draft that hasn't been sent.
  - `title` / `title_override`, where `display_title()` prefers the override
- Terminal threads mirror this. `TerminalId(uuid)` is the key. The raw
  terminal title and the user's `custom_title` are stored separately and
  recomposed on demand (`compose_terminal_thread_title`).
- `e5f5767d2c` explains why the two titles are kept apart: "Store raw
  terminal titles and custom user titles separately, recomposing display
  titles on demand". That way an agent's animated spinner or logo prefix
  survives a rename. `terminal_title_prefix` keeps a leading symbol plus
  space, and `d5fc4b74ef` renders the title's first character as the row
  icon.
- `55e47138e9` introduced `ThreadId` when drafts and background threads
  were merged into one `retained_threads` map: "A draft is just a thread
  that hasn't sent its first message".

### Lesson for nvim/Lua

- `ai.lua` uses the tool **name** as the only identity ("the name is a
  session's only identity"). Several of its documented sharp edges come
  straight from that:
  - Same-named sessions in two cwds are indistinguishable by name. `M.kill`
    has to accept a pre-resolved `state` object to avoid killing the wrong
    one.
  - Labels and names share one flat namespace, so collisions need guards
    both ways (`name_taken` / `label_taken`).
  - A label of 16 or more chars collapses sidekick's `sid` cwd hash
    (`session/init.lua` `M.sid`), so reusing it from another dir
    reattaches.
  - A reused name must not inherit the previous process's ring
    (`agent_events.clear` on `_forget`).
- Zed's answer is a uuid row id, with the agent name and the user label as
  plain attributes. In Lua the uuid could be the sidekick tool name itself,
  generated as `claude#<n>` and never shown. Labels then stop being a
  namespace problem, because they are display-only and may repeat.
- **Capture the agent's own session id.** It is what makes resume possible
  (sections 7 and 10). Claude Code hook stdin carries `session_id` and
  `transcript_path` on every event; `terminal-bell.sh` already reads
  `transcript_path`. A `SessionStart` registration of
  `sidekick-notify.sh session-start` would hand it to nvim. The `source`
  field (`startup` / `resume` / `clear` / `compact`) also says when the id
  changes under `/clear`. omp's `nvim-notify.ts` would need the equivalent
  field from its extension API (unverified).
- **Separate raw title from label** the way Zed does. Agents that set OSC
  0/2 titles (Claude Code does; Codex has `tui.terminal_title`) update
  `b:term_title` and fire `TermRequest` (verified headless on nvim 0.12.6,
  below). The sidebar can then show `label or title`, with the leading
  glyph of the raw title as a cheap status icon, as Zed does.

## 3. The status model and how it reaches the UI

### How Zed does it

Thread-level state (`acp_thread/src/acp_thread.rs`, `submission.rs`):

```rust
pub enum ThreadStatus { Unconfirmed, Idle, Generating }
pub enum ForegroundActivity { Unconfirmed, Idle, Running, RequiresAction, Unknown }
```

- "Waiting for permission" is not its own thread status. It is `Generating`
  with `foreground_activity() == RequiresAction`, true while
  `permission_requests` or pending elicitations exist.
- Errors are a flag (`had_error`) that resets when a new activity
  generation starts.
- `Unconfirmed` covers "connection lost / reloaded and the agent hasn't
  confirmed its state".

The sidebar's status is **derived at render time**, not stored. In
`sidebar.rs` (~L8141), `all_thread_infos_for_workspace` maps each live view
to `AgentThreadStatus` (`ui/src/components/ai/thread_item.rs`):

```rust
let status = if is_waiting_for_input { WaitingForConfirmation }
    else if thread.had_error() { Error }
    else { match thread.status() {
        Unconfirmed => Unconfirmed, Generating => Running, Idle => Completed } };
```

"Unseen finished" is a separate mechanism, and it is transition-based:

- `notified_threads: HashSet<ThreadId>` lives in the sidebar, not the
  thread.
- A thread is added when a rebuild sees `Completed` for a session whose
  previous status in `live_thread_statuses` was `Running`, and it isn't the
  active entry (~L1810).
- It is removed when the thread becomes the active, non-background entry.
- It is in-memory only.

`71a6d0005a` states the two-axis split explicitly:

- "Confirmation and error decorations persist as long as the thread is
  actually in that state... (unlike the blue dot which is
  notification-based)."
- "Priority order for decorations: confirmation > error > done > running
  spinner."

Later refinements: subagent permission requests surface on the parent row
(`d1871d5cf8`), and unanswered elicitation forms count as waiting
(`270df71b8d`).

### Why

The status must be truthful whether or not anyone is looking. That is why
waiting and error are state-based. "Done" only matters to someone who
didn't see it, which is why it is an event the list remembers. Deriving
status at render time means there is no second copy to drift.

### Lesson for nvim/Lua

- `agent_events.lua` already has the same two axes. `attention` /
  `running` are the state, and `unread` / `deferred` are the
  notification. The priority order also matches: `status()` returns urgent
  before unread before running.
- Zed's design highlights three gaps:
  - **Waiting can't clear itself, because nvim never sees the resolution.**
    Zed knows the moment a permission is answered
    (`ToolAuthorizationReceived`). The hook pipeline doesn't: the comment
    in `agent_events.lua` says "approving a permission prompt emits no
    hook". That is why `<M-u>` force-dismiss exists, and why the internals
    doc lists a stuck `!` as a known edge.
    - Candidate fix: register `PostToolUse` (and `PostToolUseFailure`) as a
      `tool-done` category whose transition clears `needs-permission` back
      to running.
    - Caveat: PostToolUse fires when the tool **finishes**, so a long Bash
      keeps `!` lit until it completes (inferred from Claude Code hook
      semantics, not tested).
    - A denied permission produces no PostToolUse. The next Stop or
      prompt-submit has to clear it, as today.
  - **There is no error state.** Claude Code's `StopFailure` hook is already
    registered, but only for `terminal-bell.sh`. Zed shows error as a
    persistent, state-based decoration with its own glyph. A
    `stop-failure` category would map to a new `error` status that clears
    on the next prompt-submit.
  - **Elicitation counts as waiting.** Zed added this in `270df71b8d`.
    Claude's `Elicitation` hook is registered for the bell but not for
    agent_events.
- Keep deriving status in one function (`agent_events.status()`), as Zed
  does. The existing invariant "every state transition the UI can see fires
  `AgentSessionEvent`" is the right shape.
- Unseen-finished: Zed's rule is cruder than the shipped one. Zed clears on
  becoming active; nvim clears on interaction, with deferral while you're
  looking. Zed has no equivalent of "deferred, promote on leave". Don't
  regress toward Zed here.

## 4. Event flow, rendering and write batching

### How Zed does it

- ACP traffic arrives on a background thread. It is queued in arrival
  order on one unbounded channel (`agent_servers/src/acp/runtime.rs`
  `ClientRuntime.dispatch_tx`) and applied on the foreground by
  `dispatch_task`.
- `AcpThread` mutates `entries` and emits `AcpThreadEvent`. The full list
  is in `acp_thread.rs` ~L3938; the attention-relevant ones are:
  - `StatusChanged`
  - `ToolAuthorizationRequested` / `ToolAuthorizationReceived`
  - `ElicitationRequested` / `ElicitationResponded`
  - `Stopped { activity_generation, stop_reason }`
  - `Error`
  - `ConnectionLost`
- **The sidebar does not subscribe to individual threads.** It listens to:
  - `AgentPanelEvent::{ActiveViewChanged, ActiveViewFocused, EntryChanged, TerminalCloseRequested, ThreadInteracted}`
  - `MultiWorkspaceEvent` variants
  - `cx.observe` on both metadata stores

  On any of these it schedules a full rebuild (`schedule_update_entries` →
  `rebuild_contents`), which re-reads live state from the panels'
  `ConversationView`s. The struct doc calls it one forward pass plus an
  O(T log T) sort. Row heights are cached by `EntryShape`, and collapsed
  groups skip materialising rows.
- Streaming text is revealed on a timer (`StreamingTextBuffer`), not per
  chunk. That is the only throttling in the event path.
- Persistence is write-behind and coalesced. Both metadata stores push
  `DbOperation::{Upsert, Delete}` onto a channel. A background task drains
  everything queued, dedups by id and writes. See
  `terminal_thread_metadata_store.rs` (~L395) and `a667d9c718`: "We now
  batch multiple db operations together if they happen very frequently".

### Lesson for nvim/Lua

- The shipped shape is already Zed's shape. `agent_events` emits one
  `User AgentSessionEvent`; `agentview.schedule_render()` coalesces a burst
  into one `vim.schedule` render; render re-derives every row. Keep it.
- Two things to add as sources multiply:
  - **Coalesce noisy sources before they reach the registry.** Zed's
    terminal threads refresh metadata on every `TerminalEvent::Wakeup`,
    which is every output burst, and only emit `EntryChanged` when the
    composed title or cwd actually changed (`AgentTerminal::refresh_metadata`
    returns `changed`). `0efac164b3` ("avoid setting unchanged terminal
    titles") and `26cf175930` (a memory leak "from too many title updates")
    show that this matters.
    - The Lua equivalent: a `TermRequest` handler compares the new title to
      the last one per buffer and fires `AgentSessionEvent` only on change.
    - Agents that animate a spinner in the title would otherwise trigger a
      render per frame.
  - **Write-behind persistence.** If session metadata gets persisted
    (section 10), write it from a debounced `vim.uv` timer or on
    `VimLeavePre`, never inline in the event handler. The existing "no
    timers" invariant (internals doc #9) would need an explicit exception
    for a write debounce. The other option is to persist only at
    lifecycle points: spawn, rename, kill, `VimLeavePre`.

## 5. Terminal threads under the hood

This is the closest analogue to the user's setup, so it gets the most
detail.

### How Zed does it

**Spawn** (`agent_panel.rs` `spawn_terminal` ~L2039):

- `project.create_terminal_shell(working_directory)` starts the user's
  **shell**, not the agent.
- An optional `agent.terminal_init_command` (e.g. `"claude"`) is typed
  into it, terminated by CR (not CRLF, because CRLF trips PowerShell
  continuation).
- To avoid typing before the shell is ready, Zed runs a startup handshake
  (`terminal/src/terminal.rs` ~L893). It sends a `printf` of a marker split
  across arguments, so the echoed command line can't match, and only the
  command's output contains the contiguous marker. It waits for that
  marker in output, with a 5 s fallback timeout
  (`TERMINAL_INIT_COMMAND_STARTUP_TIMEOUT`).
- Because it's a shell, the thread survives the agent exiting. You land
  back at a prompt.

**Signals**, from `insert_terminal` ~L2215:

- `TerminalEvent::TitleChanged | Wakeup | BreadcrumbsChanged` →
  `refresh_terminal_metadata`. This recomposes the title, notices a cwd
  change, and persists only if something changed.
- `TerminalEvent::Bell` → `mark_terminal_notification`. This is the only
  attention signal.
- `TerminalEvent::CloseTerminal` → close request.
- `foreground_process_command_name()` is checked against a hardcoded
  `KNOWN_TERMINAL_AGENT_COMMANDS` list (claude, codex, pi, opencode, amp,
  goose, ...). It is used **only for telemetry**, not for status or
  behaviour.

**Status:** a single `has_notification: bool` per terminal.

- It is set on Bell, unless the terminal is the visible, focused surface.
- It is cleared on activation, or when it becomes visible while its popup
  is up.
- There is no running, waiting or error state.
- The docs push CLIs to emit what Zed can read:
  - Claude Code: `preferredNotifChannel: "terminal_bell"`
  - Amp: `AMP_FORCE_BEL=1`
  - Codex: `tui.terminal_title`
  - OpenCode and pi: a small plugin that writes `\x07`

**Persistence:** `TerminalThreadMetadata`, which has no scrollback and no
agent session id:

```sql
CREATE TABLE sidebar_terminal_threads(
  terminal_id TEXT PRIMARY KEY, title TEXT NOT NULL, custom_title TEXT,
  created_at TEXT NOT NULL, working_directory TEXT,
  folder_paths TEXT, folder_paths_order TEXT,
  main_worktree_paths TEXT, main_worktree_paths_order TEXT,
  remote_connection TEXT) STRICT;
```

**Restore** (`restore_terminal` ~L2439):

- A fresh shell in the saved cwd, with the saved title as a placeholder
  until the shell sets a new one. The init command runs again; a test
  covers "runs once" (`test_restored_terminal_runs_init_command_once`).
- The conversation is not resumed unless the init command does it.
- Zed has no per-terminal id to substitute, so `claude --resume` without an
  id opens Claude's picker. Per the user's own
  `plans/zed-terminal-thread-agent-picker.md`, substitution is only a
  proposal upstream (zed#60306).

**Lifecycle:**

- Terminals are "closed rather than archived", and never go to Thread
  History.
- They are never evicted from memory: `cleanup_retained_threads` only
  considers ACP threads.
- Completed PTY resources are released (`3b90a96830`), and terminals
  shrink on clear (`1c9cbd3b24`).

### Why

Lowest common denominator on purpose. Bell and title are things every CLI
can emit with no Zed-specific integration, and no CLI is privileged. The
user's `terminal-bell.sh` exists precisely to bridge Claude's rich hook
events down into that thin channel: an OSC 2 caption plus BEL, because
Zed's popup shows the terminal title at bell time.

### Lesson for nvim/Lua

- **Signal layering: hooks and OSC, both.** The internals doc's "biggest
  structural lesson" is that cmux is OSC-first, and it says to invert the
  current hooks-first order if rebuilding. Zed is evidence on the other
  side: OSC and bell alone give it one bit of status per terminal. Zed
  shows the floor, and the shipped hook pipeline is the ceiling. Which one
  wins when both fire is an open question (see the end of this doc). A port
  should take both in:
  - **Hooks (rich):** Claude Code, omp and opencode via the existing
    `sidekick-notify.sh` RPC. These give running, needs-permission,
    needs-input, turn-complete and session-end.
  - **OSC via `TermRequest` (universal):** any CLI that sets a title or
    emits OSC 9 / OSC 777 notifications. Verified on nvim 0.12.6 with a
    headless probe that ran `printf` in a `jobstart({term=true})` buffer:
    - OSC 2, OSC 9, OSC 777 and OSC 133 each fired `TermRequest` with the
      raw sequence in `ev.data.sequence`.
    - `b:term_title` was updated.
  - **BEL is not observable from Lua.** nvim 0.11 made terminal bells
    silent by default (`'belloff'`), and there is no bell autocmd. Zed's
    one signal is the one nvim can't see. OSC 9 / 777 is the nvim
    equivalent, and Claude Code can emit OSC 9 notifications (the
    internals doc notes "Claude emits OSC 9 too", so dedupe against
    hooks).
  - Implementation sketch: one `TermRequest` autocmd, scoped to agent
    buffers (`vim.b[buf].sidekick_*` or the registry's `bufnr` index), that
    maps:
    - OSC 9 / OSC 777 → an `osc-notify` category in `agent_events.handle`
      (with the body as `message`)
    - OSC 0/2 → a title update (debounced compare, section 4)
    - OSC 133 → prompt markers (a possible "back at prompt = idle" signal
      for agents that emit it)
- **Shell-wrapped versus direct spawn.**
  - Sidekick spawns the CLI **directly**: `jobstart(norm_cmd, { term = true })`
    in `cli/terminal.lua` ~L296. When the CLI exits, `TermClose` → detach
    → the row disappears (the "detach sweep" in `ai.lua`).
  - Zed's shell wrapper keeps the row alive, and makes "agent exited" a
    non-event.
  - Trade-offs:
    - **Direct spawn:** exit status means something, there is no handshake
      race, and the existing GC and `running()` predicate depend on it.
    - **Shell wrapper:** you can run `claude --resume` by hand in the same
      row, and plain shells can be threads too. But you lose a reliable
      "agent is running" bit unless you watch the foreground process
      (which Zed only does for telemetry), and you inherit Zed's marker
      handshake problem.
  - For this config, direct spawn with resume-by-id (next bullet) gets the
    benefit without the cost.
- **Resume beats re-run.**
  - Zed's restore re-types a static command and loses which conversation
    the row was. With `agent_session_id` captured from `SessionStart`
    (section 2), a restored or "hibernated" row can spawn
    `claude --resume <id>`, keeping its label, cwd and worktree.
  - omp, pi and opencode differ: their sidekick presets declare
    `resume = { '--resume' }`, which opens a picker.
  - Note that sidekick's `resume` / `continue` preset fields are **not
    read by any Lua code** in the installed version (grep: they appear
    only in `sk/cli/*.lua` and `CHANGELOG.md`). Resume has to be built in
    `ai.lua` by passing an explicit `cmd`.
- **Title composition.** Copy Zed's raw-plus-custom split and its "keep
  the leading glyph" rule (`terminal_title_prefix`). It is about 20 lines of
  Lua and makes rows self-describing for any CLI that sets titles.

## 6. Attention and notifications

### How Zed does it

**Visibility predicate** (`agent_panel.rs` `terminal_status_visible` ~L2887;
`ConversationView::agent_status_visible` for ACP threads). A thread counts
as seen if the window is active and either:

- the sidebar is open and showing the thread list, or
- this thread is the visible surface of the active workspace's visible
  panel.

**Popup** (`ui/agent_notification.rs`):

- A 450x72 `WindowKind::PopUp`, top right, on the primary screen or all
  screens (`agent.notify_when_agent_waiting`), plus
  `window.request_attention()` (dock bounce).
- One popup per thread at a time (`notification_windows` non-empty →
  return).
- It auto-dismisses when the thread becomes visible: on window activation,
  `MultiWorkspace` change, or `ActiveViewChanged`.
- Clicking it activates the window and workspace, reveals the panel and
  activates the thread.
- Sound follows `agent.play_sound_when_agent_done` (`Never | WhenHidden |
  Always`) through `should_play(visible)`.

**ACP triggers:** `ToolAuthorizationRequested` ("Waiting for tool
confirmation"), `ElicitationRequested`, `Stopped` (including the error stop
reasons), `Error` and `LoadError`. Subagents are excluded.

**History of the suppression rule** (it flip-flopped):

- `d453d959f2`: "If you have Zed open and the sidebar open, don't show a
  notification when a thread finishes".
- `248cc134c6`: "always show a notification for a thread if it is not the
  active one (even if the sidebar is open)".
- `7240593335`, two days later: "Do not show notifications when sidebar is
  open".

**No "next needing attention" action.** Navigation is `NextThread` /
`PreviousThread` in sidebar order, an MRU thread switcher, or clicking.

### Lesson for nvim/Lua

- The shipped pipeline has these pieces already, and more:
  - focus tracking (`FocusGained` / `FocusLost`)
  - `looking_at()` with deferral
  - a one-popup-per-blocked-episode flag (`notified`)
  - urgent-only desktop popups when nvim is unfocused
  - `<leader>aj` jump-to-unread over a shared candidate list
- Zed's flip-flop on "sidebar open means seen" is evidence that this rule is
  contested, not settled. The current rule is that seeing a row is not
  reading it; only interaction acks. That is a defensible position, and
  Zed's churn doesn't argue against it.
- One Zed idea worth stealing: **sidebar visible counts as status visible
  for the sound and popup decision, but not for clearing.** In nvim terms,
  when the agent view tab is current and nvim has focus, skip the desktop
  popup (the glyph is on screen) but keep the ring. Today `notify_desktop`
  only checks `focused`.
- Zed suppresses notifications for subagents (`is_subagent`). The nvim
  hooks already do the equivalent with `CLAUDE_CODE_EXECPATH` and
  `ctx.hasUI` guards. Keep those as hard requirements for any new hook
  category.

## 7. Many live threads: retention and performance

### How Zed does it

**Retention policy** (`agent_panel.rs` `cleanup_retained_threads` ~L4305).
A retained ACP view is an eviction candidate only if all of these hold:

- no pending selections and no saved input
- its connection `supports_load_session()`
- `AcpThread::is_idle_for_retention()`: `Idle`, no unsettled or recoverable
  submissions, no permission requests, no pending elicitations

Candidates are sorted by `updated_at`, and everything beyond
`agent.max_idle_retained_threads` (default 5) is dropped. Running, waiting
and errored threads are never evicted, and neither is anything that can't
be reloaded. There is no cap on concurrent running threads.

The rationale is in `53db8891f0`: "reloading threads has a cost: For our
agent, we have to replay events, which is lossy; It's slower for external
agents; Some agents don't support reloading. So we keep the most recent 5
idle threads (or all threads who can't be reloaded)".

- An evicted thread keeps its sidebar row, shown with the default status
  and `is_live = false`. Clicking it rebuilds the view and calls
  `load_session` or `resume_session`.
- Terminals are never evicted. A PTY can't be reloaded.

**Performance work**, all on the ACP side, mostly October 2026:

- lazy markdown parsing on first render (`f41ac64812`, about 295 MiB saved)
- lazy tool-call diff materialisation (`9e65fc7682`; opening a thread had
  been costing about 3 GiB)
- skip redundant saves while streaming (`98e168265b`; 836 saves in 40 s
  became 2)
- a DB index so a thread-list reload reads 7 pages instead of 37,958
  (`fda552edce`)
- the generating spinner isolated in its own view so the animation doesn't
  re-render the thread (`36a23c2ff1`)

### Lesson for nvim/Lua

- **The eviction rule carries over almost exactly. The mechanism doesn't.**
  - An idle terminal agent can be "evicted" only by killing its process.
    That is safe only if it can be brought back.
  - So the Lua equivalent is **hibernate**: for a row that is idle (status
    `idle` or acked `unread`), has no unsent input, and has
    `caps.resume_by_id` plus a captured `agent_session_id`, it is fine to
    `jobstop` it and keep the row as dormant. Selecting the row respawns
    with `--resume <id>`.
  - The rest (needs-permission, running, no session id, agents whose resume
    is picker-only) are never hibernated, which is Zed's rule verbatim.
  - "Unsent input" is not observable for a TUI. That is a real gap; at best
    a heuristic over the last screen line, which the internals doc bans
    ("screen-scraping... the heuristic class we banned"). So hibernation
    may have to be manual-only, e.g. a sidebar key, not automatic.
- **Where the cost actually is in nvim** (inferred, needs measuring):
  - Each terminal buffer runs libvterm on nvim's main loop for every byte
    of output, **whether or not it is displayed**. Hidden buffers skip the
    redraw, not the parse.
  - Agent TUIs repaint constantly while working: spinners, timers, streamed
    diffs. N working agents means N streams parsed on the one UI thread.
    Zed parses terminal output off the main thread; nvim can't.
  - Scrollback memory is `'scrollback'` lines per buffer (default 10000,
    max 100000).
  - Measure with 4 to 8 concurrently working agents before designing
    around it.
- **Zed's spinner lesson applies to the sidebar.** If rows show an animated
  running indicator, don't re-render the whole sidebar buffer per frame.
  Use a static glyph (as now), or update a single extmark per row on a
  timer that only runs while some row is running.

## 8. Change tracking: action log, review, checkpoints

### How Zed does it

**`ActionLog`** (`action_log/src/action_log.rs`) holds a
`TrackedBuffer { diff_base: Rope, unreviewed_edits: Patch<u32>, diff: Entity<BufferDiff>, status: Created | Modified | Deleted, version }`
per buffer the agent touched.

- **Agent edits widen the diff; user edits are rebased into the base.**
  - `buffer_edited()` (the agent path) bumps `version` before the buffer's
    `Edited` event fires. Any `Edited` event with a newer version is
    therefore attributed to the user.
  - User edits that don't overlap an unreviewed hunk are folded into
    `diff_base` (`apply_non_conflicting_edits`), so they never show up as
    agent changes.
- **Keep** copies the current text of the hunk into `diff_base`. **Reject**
  writes `diff_base` text back to the buffer and saves; a file the agent
  created is deleted only if untouched since. **Undo reject** is
  best-effort, through `LastRejectUndo`.
- **Committing auto-keeps.** The log watches the buffer's git base, and
  `keep_committed_edits` folds hunks that match the commit into
  `diff_base`.
- **Review UI** (`agent_ui/src/agent_diff.rs`):
  - `AgentDiffPane` is a multibuffer of `changed_buffers()` excerpts with
    per-hunk Keep / Reject controls.
  - With `single_file_review`, ordinary editors get the same diff overlay
    via `EditorAgentDiffAddon`.
  - Actions are `Keep`, `Reject`, `KeepAll`, `RejectAll`, `UndoLastReject`
    and `OpenAgentDiff`, in key contexts `AgentDiff` and
    `Editor && editor_agent_diff`.
- **Subagents share the parent's log** (`linked_action_log`), so there is
  one review per top-level thread.
- `diff_stats()` feeds the `+N -M` on each sidebar row.

**How it learns about edits:**

- The native agent's tools call the log directly.
- External ACP agents are tracked **only** when they write through ACP's
  `fs/write_text_file`, which Zed advertises. `AcpThread::write_text_file`
  edits the buffer as `BufferEditSource::Agent` and calls `buffer_edited`.
- An external agent that writes to disk itself (its own Edit tool, `sed`
  in Bash) is not attributed. If the buffer was tracked, the reload looks
  like a user edit and is folded into the base (inferred from code; not
  tested). If not tracked, it is invisible.
- Zed has no file-watcher or git-diff fallback for attribution.

**Checkpoints were removed** (`eee7501970`, 2026-10-26): "Before every
message, the agent snapshotted every Git repo in the project and waited for
it before sending the prompt, and every Git status change during a turn
took another one. In large workspaces this took tens of seconds, and on
Windows it could hang forever... The snapshot only exists for 'Restore
Checkpoint', which very few people use, so this removes checkpoints
entirely."

- What replaces restore is **rewind**: `AcpThread::rewind` truncates
  entries, calls the agent's `truncate`, then `action_log.reject_all_edits`.
  That is a diff-base revert, not a git snapshot.
- The only checkpoint code left is the worktree archive (section 9).

**Follow agent:**

- `Project::agent_location` is set from ACP `read_text_file` /
  `write_text_file` and tool-call locations. A follow mode
  (`CollaboratorId::Agent`) moves an editor with it.
- It is gated to top-level sessions, so subagents don't move the cursor.

### Why

The action log exists because Zed sits in the write path for its own agent
and for ACP agents that use client fs. Checkpoints were a git-level safety
net that cost too much for how rarely restore was used.

### Lesson for nvim/Lua

The terminal-mode problem is the one Zed explicitly doesn't solve: **an
opaque CLI writes to disk behind the editor's back.** Zed's own answer for
that case is "not attributed". The options, in increasing fidelity:

1. **Filesystem watchers.**
   - Sidekick already has one: `cli/watch.lua`, on by default
     (`cli.watch = true`). It runs `vim.uv.new_fs_event` per directory of
     each loaded buffer, then `:checktime`, so open buffers reload.
   - That's freshness, not attribution. With several agents in one
     checkout it can't say who changed what, and it only watches dirs of
     loaded buffers.
   - Useful as is. Don't build review on it.
2. **Hook-reported touched files (Claude Code, maybe omp).**
   - Claude's `PostToolUse` stdin carries `tool_name` and `tool_input`,
     with `file_path` for Edit / Write / MultiEdit.
   - A `tool-done` category could append to `rows[id].touched_files`. That
     gives a per-session file list for a "what did this agent touch"
     picker, and an ACP-less **follow agent**: open or reveal the last
     touched file.
   - It misses Bash-driven writes (`sed -i`, codegen, formatters), which is
     the same blind spot Zed has.
   - Agent-specific: cursor and pi would need their own hooks or nothing.
3. **Git baseline per session (the transferable form of ActionLog).**
   - Record a base commit at a lifecycle point and diff the working tree
     against it.
   - In an isolated worktree (section 9), the base is simply the
     worktree's starting commit. "Everything in `git diff <base>` is this
     agent's or yours", with no attribution problem and no snapshot cost.
   - In a shared checkout you need a snapshot of the dirty state. Zed's
     archive recipe gives one without touching refs or the real index:
     `git write-tree` on a temp index (`GIT_INDEX_FILE`) after
     `git add --all`, then `git commit-tree`. See section 9 for the exact
     commands.
   - Do it with `vim.system` (async), on `prompt-submit` only, and **heed
     `eee7501970`**: on a large repo this can take seconds. Taking it per
     turn is exactly what Zed removed. Per session (at spawn) is cheap and
     usually enough.
   - **Review maps onto plugins the config already has:**
     - **Multi-file review (`AgentDiffPane`):** `:DiffviewOpen <base>`.
       diffview.nvim is installed, and git.lua / GUIDE "Reviewing diffs"
       document it.
     - **Inline per-hunk review (`single_file_review`):**
       `require('gitsigns').change_base(<base>, true)`. gitsigns.nvim is
       installed, and `change_base` exists in its `actions.lua`.
       `reset_hunk` then means **Reject** (it restores the base text).
     - **Keep:** advance the session's base to a new snapshot, which is
       exactly Zed's "copy into `diff_base`". Per-hunk keep is harder:
       gitsigns has no "keep this hunk into a custom base". Options are
       staging (if the base is the index) or accepting whole-file
       granularity.
     - **Diff stats for the sidebar row:** `git diff --shortstat <base>`
       via `vim.system`, refreshed on `turn-complete` only.
     - **Committing auto-keeps:** comes free if the base is "merge-base
       with the branch the agent started from", recomputed on demand.
   - User versus agent attribution inside one worktree is lost: your own
     edits in that worktree show up as the agent's. Zed's version-bump
     trick doesn't exist for disk writes. Accept it, or keep a rule of not
     editing inside agent worktrees.

## 9. Worktree isolation

### How Zed does it

**It is not automatic per thread.** Threads share their workspace's
folders. A worktree is made by the user ("Create New Worktree" in the
sidebar header or title-bar picker) or by the agent itself (the native
`create_thread` tool's `use_new_worktree: true`,
`agent/src/tools/create_thread_tool.rs`).

**Creation:**

- `git worktree add --detach -- <path> <start>`
  (`git/src/repository.rs` `RealGitRepository::create_worktree` ~L2277).
- All user-facing targets (`CurrentBranch`, `ExistingBranch`,
  `RemoteBranch` / `DefaultBranch`) produce a **detached HEAD** so a branch
  is never shared between worktrees. A remote target is fetched first.
- Names are generated "adjective-noun" (`git_ui_core::worktree_names`).
- The path is `<git.worktree_directory>/<name>/<project>`, with default
  `"../worktrees"` (`DEFAULT_WORKTREE_DIRECTORY`, verified). It is
  validated to stay inside an allowed area.
- A `create_worktree` task hook runs afterwards, with `ZED_WORKTREE_ROOT`
  and `ZED_MAIN_GIT_WORKTREE` set.

**Association:**

- `WorktreePaths` keeps two parallel `PathList`s: `folder_paths` (the
  linked worktree) and `main_worktree_paths` (the original checkout).
- The sidebar groups by the main path, so a project's worktree threads sit
  under the project header with a worktree chip
  (`WorktreeKind::{Main, Linked}`).
- `d77aba3ee7` exists because grouping by plain paths "can cause threads to
  be visible in the agent panel but not have an entry in the sidebar".

**Archive** (`agent_ui/src/thread_worktree_archive.rs`, `sidebar.rs`
`archive_worktree_roots`). Only when no other unarchived thread references
the root:

1. Record HEAD, branch and paths in `archived_git_worktrees`.
2. Make two detached WIP commits with Zed as author:

   ```
   git write-tree                                  # staged tree (real index)
   git commit-tree <staged> -p HEAD -m "WIP staged"
   # temp copy of .git/index:
   git add --all; git write-tree
   git commit-tree <full> -p <staged_sha> -m "WIP unstaged"
   ```

3. Pin them with `refs/archived-worktrees/<id>` on the main repo so GC
   can't collect them.
4. `git worktree remove`.

Restore recreates the worktree at the original path, then runs
`git read-tree --reset -u <unstaged>` and `git read-tree <staged>`, and
restores the branch.

**Safety rules from history:**

- "Only archive worktrees that Zed created" (`e2780f6fbd`).
- Then `29622911de`: record the creation time of `.git/worktrees/<name>`
  and re-stat it before deleting. If it changed, the worktree was recreated
  outside Zed, so refuse. "Every failure mode fails safe."
- Every step has a rollback (`rollback_root`, `rollback_persist`), and the
  archive task is cancellable by unarchiving.

### Lesson for nvim/Lua

- This is the most directly portable subsystem. It is all git CLI, and the
  hard parts are already designed.
- A Lua module (e.g. `agent_worktree.lua`) built on `vim.system({ 'git', ... })`:
  - `create(main_root, name?)` → `git worktree add --detach`, record
    `{ path, created_at = fs_stat('.git/worktrees/<name>').birthtime }` in
    the registry.
  - The session row's `cwd` is the worktree. Sidekick already keys
    sessions by `(tool name, cwd)` (`session/init.lua` `M.sid`), so its
    identity model already allows one session per worktree. **Correction
    (see `sidekick-assessment.md`):** the public API can't pass that cwd.
    Spawn uses `getcwd(0)`, read one scheduled tick later, and `cli.show`
    has no cwd option. Spawning into a worktree the editor isn't on needs
    sidekick internals (`Session.new({tool, cwd})` + `State.attach`) or our
    own spawn.
  - Grouping key: `vim.fs.dirname(git rev-parse --path-format=absolute --git-common-dir)`.
    That is Zed's "main worktree path", and it lets the agent view group
    rows by project.
  - `archive(row)` / `restore(row)` with Zed's WIP-commit-plus-ref recipe.
  - Copy the safety rules verbatim:
    - only remove what this module created
    - re-stat before delete
    - never remove a worktree another live row references
- **Relation to existing repo work:** the user already has
  plans for throwaway worktrees and a fixed-slot worktree controller
  for a large service repo, which has a handful of fixed slots with heavy infra per
  slot. For such repos, fixed slots beat ad-hoc worktrees because the
  expensive state is the infra, not the checkout. So a Lua worktree layer
  should accept "use an existing worktree path" as a first-class option,
  not only "create one". That is Zed's `ExistingBranch` / worktree-picker
  path.
- **Branch policy:** Zed's detached-HEAD default avoids the "branch already
  checked out in another worktree" error. It shifts branch creation to the
  user, which is fine for review-then-merge flows.

## 10. Persistence and restore

### How Zed does it

- Only **metadata** is persisted:
  - `sidebar_threads`: ids, agent, titles, timestamps, both path lists,
    archived flag, remote connection.
  - `sidebar_terminal_threads`: the table in section 5.
  - Drafts' unsent text lives in a KV store keyed by `ThreadId`
    (`draft_prompt_store.rs`).
- **Content lives with the agent:**
  - the native agent's thread store, or
  - the ACP agent's own session store (`load_session` / `resume_session`)
- **Restore is lazy and minimal:**
  - `AgentPanel::load` restores only the last-active terminal or thread per
    workspace.
  - Every other row is a metadata row that hydrates on click.
  - Retained threads are not re-hydrated, and "notified" state is lost on
    restart.
- `a8decbea13` added cross-release-channel import so Nightly testers
  wouldn't lose threads moving to Stable. The metadata DB had become the
  user's working set, worth migrating.

### Lesson for nvim/Lua

- Today nothing survives an nvim restart without sidekick's mux backend:
  "Nothing persists across an nvim restart without the mux backend"
  (GUIDE). The view tab is deliberately torn down before
  persistence.nvim saves (`PersistenceSavePre` in `agentview.lua`).
- Zed's split carries over cleanly:
  - Persist **rows, not terminals**: `{ id, agent, label, cwd, main_root,
    worktree, agent_session_id, created_at, last_access }`.
  - Store it as JSON in `stdpath('state')/agent-sessions/<hash of main_root>.json`,
    written at lifecycle points (section 4).
  - On startup, load rows as **dormant**. The sidebar shows them, and
    selecting one spawns with `--resume <agent_session_id>`.
  - Only the primary pre-warmed `claude` is spawned eagerly, as now.
  - That is Zed's "metadata rows hydrate on click", with the agent CLI's
    own session store standing in for ACP `load_session`.
- **Interaction with the pre-warm:** `do_prewarm` spawns a fresh `claude`.
  With dormant rows, the pre-warm could instead resume the most recent
  claude row, or stay fresh. Open question.
- **Alternative: the mux backend.** tmux or zellij keeps processes alive
  across restarts, which is stronger than resume: running turns survive.
  But `ai.lua` stubs the mux discovery backends because `State.get` shells
  out synchronously (~40 ms; GUIDE "Sidekick's session backends shell out
  on every lookup"). Resume-by-id is the lighter path. Mux is the "turns
  keep running while nvim is closed" path. They don't conflict.

## 11. Connections, processes, permissions, queueing

Mostly ACP-only; summarised for completeness and for the boundaries it
draws.

### How Zed does it

**Processes:**

- One agent process per agent type per project panel
  (`AgentConnectionStore`, `agent_ui/src/agent_connection_store.rs`),
  shared by all its sessions.
- The connection holds `sessions: HashMap<SessionId, AcpSession>` with
  **weak** thread references. The UI owns threads strongly. Dropping a
  thread closes its session if the agent supports it.
- `30b7178f67` renamed `ConnectionView` → `ConversationView` because "we
  now share connections across multiple" views.
- The process is killed on drop (`OwnedChild`). There is no auto-restart
  on connection loss; the user reconnects.

**Permissions:**

- An agent request installs a `oneshot` in `permission_requests` and emits
  `ToolAuthorizationRequested`. The ACP response is held open until the
  user picks an option.
- "Always allow" persistence happens only for the native agent: it writes
  settings and tool patterns. External agents get only the chosen
  `option_id`; their own "always" is their business.

**Queueing:**

- A UI-level `MessageQueue` holds prompts typed while busy and auto-sends
  on `Stopped`. It pauses on error, refusal or max-tokens, and on manual
  stop. `69ecd31b02`: "there can never exist a 'stuck queue'".
- An optional "steer" ends the turn at the next boundary (native only).

**Subagents:**

- Child `AcpThread`s are owned by the parent (`subagents`), created when
  the agent announces them.
- `AgentOwned` transport means Zed can't prompt them.
- Their permission requests surface on the parent's sidebar row.

### Lesson for nvim/Lua

- **Process per session is the terminal-mode reality.** Each sidekick
  terminal is its own CLI process. There is nothing to share, and that's
  fine. The one Zed idea that carries over is that the list owns rows
  strongly while processes come and go, which is the dormant-row model
  from sections 7 and 10.
- **Permissions stay in the CLI.** Zed can answer a permission prompt
  because ACP puts the prompt in Zed. In terminal mode the prompt is drawn
  by the TUI, and the answer is keystrokes. nvim can surface that one is
  pending (hooks) and jump you there (`<leader>aj`). It must not answer on
  your behalf: sending `y` bytes blind is the same "a guessed byte does
  real damage" class as the `u` allowlist in `ai.lua`.
- **A message queue is possible but agent-specific.** Every CLI the config
  runs already queues typed input during a turn. nvim-side queueing would
  only add "send this to the agent when it finishes", via `turn-complete`
  and `nvim_chan_send` with bracketed paste (as `paste_to_claude` does).
  Low value; noted for completeness.
- **Subagents:** the existing nested-claude suppression
  (`CLAUDE_CODE_EXECPATH`, `ctx.hasUI`) is the terminal-mode analogue of
  `is_subagent` muting. Surfacing a subagent's permission request on the
  parent row comes free, since the TUI shows it in the parent.

## 12. Actions, keymaps, settings

### How Zed does it

- **Actions are namespaced** (`agent::`, `agents_sidebar::`,
  `multi_workspace::`) and bound per **key context**: `AgentPanel`,
  `ThreadsSidebar`, `ThreadSwitcher`, `AgentDiff`,
  `Editor && editor_agent_diff`. The same keystroke (`cmd-n`) means
  `NewThread` in the panel and `NewThreadInGroup` in the sidebar.
- **Two navigation orders:**
  - sidebar order: `NextThread` / `PreviousThread`, unbound by default on
    macOS
  - MRU order: the ctrl-tab thread switcher, sorted by
    `thread_last_accessed`, which is "updated only on explicit user
    actions"
- `AgentPanelEntryKind` (`Thread` / `Terminal`) remembers what you last
  created, so "new" repeats it.
- **Settings that shape the parallel experience** (`agent_settings.rs`):
  - `notify_when_agent_waiting`
  - `play_sound_when_agent_done`
  - `max_idle_retained_threads`
  - `terminal_init_command`
  - `threads_sidebar.*`
  - `git.worktree_directory`

### Lesson for nvim/Lua

- The config already follows the key-context idea:
  - buffer-local keymaps in `sidekick_terminal` buffers (`<M-]>`, `<M-l>`,
    ...)
  - in the agent-view sidebar buffer (`n`, `r`, `x`, digits)
  - global `<leader>a*`
- Digits plus name-sorted cycling is Zed's "sidebar order". The missing
  half is **MRU order**: `toggle_last` is MRU depth 1. A `last_access`
  field on registry rows (set only on explicit switches, as Zed does,
  never on preview) would allow an MRU picker with no new concepts.
- If Zed-style grouping arrives (by main repo or worktree), name-sorted
  digits stop matching what's on screen. The "digits = cycle order = row
  order" invariant (internals doc #8) would need restating as "row order",
  whatever that becomes.
- Settings: the Lua equivalents are module-level constants today
  (`AGENTS`, `PREWARM_DELAY`). Zed's set suggests which knobs proved worth
  exposing: notification target, sound, retention count, init and resume
  command, worktree dir.

## What does not transfer to terminal mode

- **Per-edit attribution and hunk-level keep/reject against the agent's
  own writes** (ActionLog). It needs Zed to be the writer. Approximations:
  a git baseline, or hook-reported paths (section 8). Neither separates
  your edits from the agent's in the same tree.
- **Answering permission prompts from editor UI**, and "always allow"
  persistence. The prompt lives in the TUI. nvim can only point at it.
- **State-based "waiting" that clears exactly when answered.** No hook
  fires on approval. PostToolUse is a late proxy.
- **Structured transcript features:**
  - message editing or rewind (`AcpThread::rewind` + `truncate`)
  - lazy markdown or diff rendering
  - search over entries
  - token usage bars
  - title generation by a model
  - subagent cards

  The TUI renders its own transcript. A port gets only what the CLI exposes
  (titles, hooks, transcript files on disk; Claude's `transcript_path` is
  JSONL that could be read, but that's a parser per CLI version).
- **Eviction without loss.** Zed reloads a thread from the agent's store.
  A terminal can only be killed and resumed. That works for resume-by-id
  agents, and loses scrollback.
- **Follow agent with precise positions.** ACP reports read and write
  locations. Hooks report file paths at best, not cursor positions, and
  only for some agents.
- **Shared-connection economics.** One process serving many sessions is an
  ACP property; CLIs are one process each.
- **Zed's bell-based terminal attention, literally.** nvim exposes no bell
  event, so OSC 9/777 via `TermRequest` is the substitute.

## Constraints and risks for a Lua implementation

- **Main-loop cost of N busy terminals.** libvterm parses every byte on the
  UI thread, displayed or not (section 7). This is the first thing to
  measure, with 6 to 8 agents streaming at once. There's no off-thread
  option in nvim.
- **Sidekick's model limits** (installed `17447a0`; unpinned, per the
  internals doc):
  - Identity is the tool name, and dynamic sessions are implemented by
    registering cloned presets into `cli.tools`. A uuid-keyed registry
    would sit on top of that, with names as opaque keys. Workable, but it
    is a parallel bookkeeping layer that `ai.lua` already half-maintains
    (`_dynamic`, `_labels`).
  - `State.get` is synchronous and walks every backend's `sessions()`.
    `ai.lua` stubs the shell-out backends to keep it at about 0.05 ms. Any
    sidekick update can undo that.
  - The CLI is spawned directly, and `TermClose` with a quick or failing
    exit has delay heuristics (`TERM_CLOSE_DELAY`). Resume-by-id needs a
    per-spawn `cmd`, which today means cloning a preset per resumed
    session.
  - Preset `resume` / `continue` fields are inert in this version.
  - Display ownership (`term.win`, `open_win`, `show/hide`) is already
    being worked around: the agent view embeds via `nvim_win_set_buf` and
    keeps `term.win` nil (internals doc invariant 7).
  - Rough split of what to keep versus replace:
    - **Keep sidekick for:** context sends and `{selection}` / `@file`
      rendering (`ai_context.lua`), the spawn env plumbing (`NVIM`,
      `SIDEKICK_SESSION`), the fs watcher.
    - **Candidates to replace with a small owned module:** session
      identity and listing, spawn with arbitrary argv (resume), and window
      management. That is roughly `jobstart({ term = true, cwd, env })`
      plus the `sidekick_cli` window stamp that `agent_events` and the
      keymaps rely on.
- **Hook availability across agents:**
  - **Claude Code:** full set (UserPromptSubmit, Notification
    `permission_prompt` / `idle_prompt`, Stop, StopFailure,
    PermissionRequest, Elicitation, SessionStart / End, PostToolUse with
    `tool_input`). Also emits OSC titles and can bell.
  - **omp:** extension events give running and done only (`nvim-notify.ts`:
    "urgent (`!`) stays Claude/opencode"). The session id for resume and
    touched files are unverified.
  - **opencode:** plugin events include `permission.asked` and
    `session.idle` (per Zed's docs snippet). The internals doc says
    opencode supports the urgent tier.
  - **pi:** extension `agent_end` (turn-complete). The `pi -p`
    session_shutdown race is noted in the internals doc.
  - **cursor-agent:** relies on a Claude-hook merge, with an explicit
    `~/.cursor/hooks.json` fallback (internals doc retreat positions).
  - **codex:** not in `AGENTS`; it has title support (`tui.terminal_title`),
    so OSC-only.
  - Every hook path must keep the existing hard rules: always exit 0, time
    out the RPC, interpolate only the tmpfile path, and suppress nested
    agents. The `CLAUDE_CODE_EXECPATH` guard is a single point of failure.
    If Claude ever injects it into hook envs, all events vanish.
- **Event RPC transport:** `nvim --server $NVIM --remote-expr` per event
  costs one process spawn per hook (two with `timeout`). Fine at hook rates.
  A PostToolUse registration raises the rate to every tool call. That is
  probably still fine, but measure, or batch through a FIFO or socket the
  module reads with `vim.uv`.
- **Git cost:** worktree creation and snapshots on large repos
  (large service repos) are the exact cost Zed removed checkpoints over. Always
  async (`vim.system`), never per turn, never blocking spawn.
- **Single-instance assumption:** `$NVIM` routes events to the nvim that
  spawned the agent. Persisted dormant rows restored into a different nvim
  must re-inject `NVIM` / `SIDEKICK_SESSION` at respawn, which happens
  naturally because sidekick sets `NVIM = vim.v.servername` at spawn.
  flatten.nvim also routes nested `nvim` invocations, so keep
  `env -u NVIM` in tests.
- **Tests:** `tests/agentview/run.sh` encodes ring semantics. Every lesson
  above that touches `agent_events` transitions (error state, PostToolUse
  clear, OSC category) changes the truth table in the internals doc and
  needs the suite updated with it.

## Candidate architectures

These are options to compare, not a decision.

### Option A: extend in place

Keep sidekick as the session layer. Add to the existing modules:

- `agent_events`:
  - new categories: `error`, `tool-done`, `osc-notify`, `session-start`
    carrying `agent_session_id`
  - a `TermRequest` listener for OSC
- `agentview`: title column, grouping by main repo, diff-stat column
- a new `agent_worktree.lua` for worktree create, archive and restore
- resume-by-id via per-session preset clones with an explicit `cmd`

**For:** smallest diff, keeps every invariant and test.
**Against:** identity stays name-based. Persistence and dormant rows have
to be faked through `cli.tools` entries. The sidekick-internals surface the
config depends on grows.

### Option B: own registry, sidekick as a backend

Add the registry from section 1 as the single source of rows (uuid ids,
dormant state, persistence, capabilities). `ai.lua` becomes the spawn and
display adapter that maps a row to a sidekick tool name and back.
`agent_events` keys by row id; hooks still send `SIDEKICK_SESSION`, which
now carries the row id.

**For:** fixes the identity problems at the root, and makes dormant rows,
MRU, grouping and worktrees natural. Sidekick stays for context sends.
**Against:** a migration of `ai.lua`'s name-keyed logic (cycle, digits,
labels, kill), and a second source of truth during the transition.

### Option C: own terminal manager, drop sidekick's session layer

Spawn with `jobstart({ term = true })` directly (shell-wrapped or direct,
per section 5). Keep sidekick only for context rendering, or reimplement
the `@file#L` refs (`ai_context.lua` already overrides them).

**For:** full control of argv (resume), env, windows and lifecycle; no
dependency on sidekick internals the internals doc says to re-verify after
every update.
**Against:** the most code to own. Sidekick's send queue and ready
detection (`on_ready`, `SEND_DELAY`) and its watcher would need
equivalents or would be lost.

### Orthogonal: an ACP lane

Zed's ACP crates show what a native client costs: a JSON-RPC client,
session update application, a permission UI, terminal and fs client
methods, and an action log. The user's stated direction is terminal mode.
An ACP lane would only make sense for one narrow win the terminal can't
give: real keep/reject attribution, or answering permissions from the
sidebar. Registry `kind = 'acp'` is where it would slot in. Out of scope
here.

## Open questions

1. Is per-session resume worth building for omp, pi and opencode, whose
   presets only offer a picker-style `--resume`? Or should dormant rows be
   Claude-only at first? This needs checking what each CLI accepts as
   `--resume <id>`, and whether its hook or extension API exposes the id.
2. Should `agent_events` gain an `error` status, and should `PostToolUse`
   clear `needs-permission`? Both change the shipped truth table and the
   test suite.
3. Does hiding versus showing agent terminals change CPU materially with 6
   to 8 working agents? This needs a measurement before any eviction or
   hibernation design.
4. Worktrees: ad-hoc `git worktree add --detach` (Zed), fixed long-lived
   slots for heavy-setup repos, or both behind one "session cwd" field?
5. Shell-wrapped spawn (Zed) or direct spawn (sidekick)? This decides
   whether "agent exited" removes the row or leaves a shell.
6. Should the agent view group rows by main repo / worktree (Zed's project
   groups)? That breaks today's flat "digits = name order" invariant.
7. OSC-first (the internals doc's lesson from cmux) or hooks-first (what
   ships today)? Is Claude Code's OSC 9 output redundant with its hooks, or
   worth ingesting as the cross-agent path? This needs observing what Claude
   actually emits inside nvim's terminal (`TERM=xterm-256color` set by
   sidekick; `TERM_PROGRAM` is inherited from the outer terminal).

## Appendix: design history worth knowing

From `git log` on the agent crates. Many big PRs have empty bodies, so
rationale is quoted only where it exists.

- **2025-07-09 `495ec7a109` "ACP":** the ACP client lands (`acp_thread`,
  `agent_servers`). August 2025: the native agent is rebuilt as "agent2"
  on top of the ACP thread view. 2025-10-17 `3f1319162a`: agent1 is
  removed. The native agent became just another `AgentConnection`.
- **2026-02-08 `1c21718587` "New multi workspace":** the root of the
  sidebar and parallel-agents design. It was reverted and re-landed within
  days purely for sequencing (`165b404460`, `ee3f40fe25`).
- **2026-03-10 → 2026-03-16:** the threads sidebar moved **into** the agent
  panel (`b5666319b4`), then back out (`977cd6ac7e`) six days later. No
  reason was given; it has stayed a window-level surface since.
- **2026-03-16 `015225196d`:** thread metadata store, then caching
  (`09b0388312`), write batching (`a667d9c718`) and race fixes
  (`080e80df2b`).
- **2026-03-20 `53db8891f0`:** retention policy (quoted in section 7).
  Made configurable on 2026-09-28 (`c821538b57`).
- **2026-04-13 `55e47138e9`:** drafts and background threads unified into
  `retained_threads`, keyed by a new `ThreadId`.
- **2026-04-08 `2169ebaf4b`:** worktree archive and restore, then
  hardening (`e2780f6fbd`, `29622911de`, quoted in section 9).
- **2026-05-07 `5fc8a836dd`:** terminal threads, experimental:
  - 2026-05-11 `1c884d13d3`: bell notifications
  - 2026-05-13 `a7f037d94b`: feature flag removed
  - 2026-05-18 `e1f13a84b7`: persistence
  - 2026-06-16 `fd5d42dd55`: `terminal_init_command`
- **2026-04-14 `7240593335`:** final (for now) rule: no notifications while
  the sidebar is open, after two reversals (section 6).
- **October 2026:** long-thread performance pass (section 7), the ACP v2
  migration, and **2026-10-26 `eee7501970`: checkpoints removed** (quoted
  in section 8).
