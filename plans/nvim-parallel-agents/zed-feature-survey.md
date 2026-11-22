# Zed agent features: a survey for the nvim parallel-agents port

This is a list of what Zed's agent features do and what the user sees. It
leans hard on everything around running and managing several agents or
threads at once. It does not cover architecture. That is in the companion doc
[`zed-design-lessons.md`](zed-design-lessons.md). It also does not recommend
what to build. Triage comes later.

- **Surveyed:** the Zed source at `~/src/zed`, HEAD `596dfdcf32` (committed
  2026-11-15). Read-only. Nothing was built or run, so every claim comes from
  reading source and docs.
- **Written:** 2026-11-22.
- **Sources:** the crates `agent_ui`, `sidebar`, `agent`, `acp_thread`,
  `agent_servers`, `agent_settings`, `agent_skills`, `acp_tools`, `action_log`,
  `terminal`, `terminal_view`, `workspace` (`multi_workspace.rs`), `title_bar`,
  `git_ui_core`, `project` (`git_store.rs`), `feature_flags`, `ui`
  (`components/ai/thread_item.rs`), plus `assets/keymaps/default-macos.json`,
  `assets/settings/default.json` and `docs/src/ai/*.md`. The docs were used
  for intent only. Where code and docs disagree, the code wins. Claims seen
  only in docs are marked **docs only**.
- **Compared against:** the nvim setup in `nvim/.config/nvim/`:
  - `lua/ai.lua`: sidekick.nvim session pool.
  - `lua/agentview.lua`: the dashboard tab.
  - `lua/agent_events.lua`: the hook-driven attention registry.
  - `lua/ai_context.lua`: `@file#L` refs.
  - `lua/statusline.lua`: the badge.
  - `GUIDE.md`: the "AI (sidekick.nvim)" and "Reviewing diffs" sections.

All Zed paths below are relative to `~/src/zed`. Line numbers are approximate.

## How to read the tags

Each feature carries two tags:

- **Terminal-mode relevance** asks whether the feature makes sense, and could
  be built, when the agent is a CLI running in a terminal buffer (the sidekick
  model):
  - **high**: it maps directly.
  - **medium**: possible, but it needs extra signals such as hooks, git, or
    parsing.
  - **low**: it depends on owning the conversation or protocol.
  - **n/a**: the CLI owns it by definition.
- **Current nvim setup** says how much of it the nvim config already has:
  - **have**: an equivalent exists.
  - **partial**: some of it exists, or it is done another way.
  - **missing**: no equivalent.

## The big picture: three thread types in one surface

Zed's Agent Panel and Threads Sidebar hold three kinds of "thread" in one
list. One switcher moves between all of them, and one notification system
covers all of them.

1. **Zed Agent thread.** The native agent, using Zed's own tools, profiles,
   skills and MCP.
2. **External Agent thread.** An agent CLI such as Claude Code, Codex, Gemini
   or Cursor, spoken to over ACP (Agent Client Protocol). It renders as a
   native chat UI.
3. **Terminal Thread.** A plain terminal running whatever CLI or TUI you
   like. Zed organizes it as a thread but does not understand its contents.

The table in `docs/src/ai/parallel-agents.md` ("Thread Types") is the official
summary. None of this is behind a feature flag. The only gate is
`agent.enabled` being true and `disable_ai` being false
(`crates/workspace/src/multi_workspace.rs:~444`). Parallel agents are a
shipped, default-on feature.

The terminal-thread type is the closest analogue to the sidekick setup, so it
comes first.

## 1. Terminal Threads (the terminal-mode analogue)

The main code is in `crates/agent_ui/src/agent_panel.rs` (~1974-2720, plus
`AgentTerminal` at ~960-1076),
`crates/agent_ui/src/terminal_thread_metadata_store.rs`, and
`crates/sidebar/src/sidebar.rs` (`render_terminal` ~6600,
`split_leading_icon_char` ~243, `pick_icon_glyph` ~277). The docs are
`docs/src/ai/terminal-threads.md`.

### 1.1 Creating a terminal thread and the init command

- **What it does.** Choose **Terminal** in the new-thread menu (the agent
  selector, or `+` in the panel toolbar). The new-thread menu also opens with
  `cmd-alt-shift-n` (`agent::ToggleNewThreadMenu`). You can also run the
  unbound action `agent::NewTerminalThread`.
- **Remembers the kind.** The panel remembers whether you last created a
  thread or a terminal (`last_created_entry_kind`, saved per workspace and
  globally). After that, `cmd-n` (`agent::NewThread`) and the sidebar's
  per-project `+` create the same kind again.
- **Init command.** `agent.terminal_init_command` (default `""`) is typed into
  the new shell, followed by CR, once the shell is ready. Zed waits for a
  startup handshake marker, with a 5-second timeout fallback
  (`TERMINAL_INIT_COMMAND_STARTUP_TIMEOUT`). The shell stays interactive after
  the command exits. There is one init command for all terminal threads,
  not one per agent.
- **Count.** You can have as many terminal threads as you like. Each one is a
  sidebar row.
- **Terminal-mode relevance:** high. This is exactly the sidekick spawn model.
- **Current nvim setup:** have. `<leader>an` (agent picker, then label),
  `<M-n>` (fork the active agent in place), and `n` in the agent view. Sidekick
  spawns the CLI binary directly instead of typing into a shell. Unlike Zed,
  the nvim pool has five agents with their own presets.

### 1.2 What Zed owns and what the CLI owns

- **Zed owns:** the sidebar row, grouping by project, switching, the title,
  bell notifications, and the worktree chip. It owns nothing else.
- **The CLI owns:** auth, models, subscriptions, tools, skills, instruction
  files and MCP. Zed profiles, tool permissions, Skills and MCP settings do
  not apply.
- **Not available in a terminal thread:**
  - status other than "unread", so no running, waiting or error state;
  - edit tracking, review and keep/reject;
  - diff stats;
  - follow-the-agent;
  - context ring and cost;
  - `@`-mentions;
  - message queueing;
  - thread history and archive;
  - auto-generated titles.

  These were confirmed in code. Terminal rows never get an
  `AgentThreadStatus`, and the sidebar's `diff_stats` come only from
  `AcpThread` action logs (`sidebar.rs:~8153`).
- **Terminal-mode relevance:** n/a. This is the boundary itself.
- **Current nvim setup:** have. It is the same split. Each CLI keeps its own
  config.

### 1.3 Titles from the terminal (OSC title)

- **What it does.** The row title follows the terminal's title, which a CLI
  sets with an OSC 0/2 escape sequence, falling back to breadcrumbs.
  - A bare "Terminal" title is treated as empty, and the last non-empty
    title is cached (`AgentTerminal::refresh_title`, `agent_panel.rs:~973-1030`).
  - The title refreshes on `TitleChanged`, `Wakeup` and `BreadcrumbsChanged`,
    and is saved to the metadata DB.
- **Docs only:** the docs list CLI-side setup for title updates. Codex's
  `/title` picker (`tui.terminal_title = ["spinner", "project-name",
  "run-state", "thread-title"]`) puts run state and spinner into the title.
  Amp and OpenCode update titles automatically.
- **Terminal-mode relevance:** high. Neovim exposes the same signal as
  `b:term_title` and the `TermRequest` event.
- **Current nvim setup:** missing. Rows show the session name or a manual
  label. Nothing reads the CLI's title.

### 1.4 A title prefix glyph becomes the row's status icon

- **What it does.** This is the cleverest bit of the terminal integration. If
  the title starts with a non-alphanumeric "decorative prefix" followed by
  whitespace (a spinner glyph, an emoji, `[!]`, `...`), the sidebar strips the
  prefix and shows one representative glyph in place of the terminal icon.
  - Brackets are unwrapped: `[!]` shows as `!`.
  - A run of dots shows as `…`.
  - The first grapheme cluster is kept, so multi-codepoint emoji stay whole.

  A CLI that animates a braille spinner in its title therefore gets a
  "running" spinner in the sidebar for free. One that puts `!` or a bell
  emoji in its title gets an attention glyph.
- **Custom titles keep the prefix.** A manual name replaces only the text
  after the prefix (`compose_terminal_thread_title`), so the live status glyph
  survives a rename.
- **Terminal-mode relevance:** high. It works purely from the terminal title.
- **Current nvim setup:** missing. The nvim setup gets its status from hooks
  instead (see section 3).

### 1.5 Bell becomes an unread dot, a popup and a sound

- **What it does.** On `TerminalEvent::Bell`, `mark_terminal_notification`
  (`agent_panel.rs:~2642`) runs these steps:
  1. It does nothing if that terminal is active and visible in the focused
     window.
  2. Otherwise, on the first bell only, it sets `has_notification`. That
     draws the accent dot on the sidebar and switcher rows.
  3. It plays the `agent_done` sound, following
     `agent.play_sound_when_agent_done`.
  4. It calls `window.request_attention()` (dock bounce) and opens a Zed
     popup window, following `agent.notify_when_agent_waiting`. The popup
     shows the terminal title and project name, with **View** (which
     activates and focuses that terminal) and **Dismiss**.

  Later bells are ignored until the flag clears. Activating the terminal,
  focusing it, or seeing the popup become visible clears it.
- **Docs only:** CLI recipes to make them emit BEL:
  - Claude Code: `preferredNotifChannel: "terminal_bell"`.
  - Amp: `AMP_FORCE_BEL=1`.
  - OpenCode: a plugin that writes `\x07` on `session.idle` or
    `permission.asked`.
  - Pi: an extension that writes `\x07` on `agent_end`.
  - tmux needs `allow-passthrough on`.
- **Not distinguished.** The bell is the only attention signal. It does not
  tell "finished" apart from "needs permission", and there is no running or
  idle notion.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** partial, and ahead in fidelity. `agent_events.lua`
  gets typed events from hooks: needs-permission, needs-input, turn-complete,
  prompt-submit and session-end. All five agents feed them through the stowed
  `sidekick-notify.sh` script. So nvim can tell `!` (urgent), `●` (unread)
  and `»` (running) apart, where Zed terminal threads cannot. What nvim lacks
  compared with Zed: no sound, no dock bounce, and the desktop popup has no
  click-to-focus. The nvim setup does not listen for BEL itself.

### 1.6 Renaming, closing, and process exit

- **Rename.**
  - Click the title or the pencil icon in the panel toolbar.
  - Sidebar context menu > **Rename Title**.
  - `shift-r` (`agent::RenameSelectedThread`) while the sidebar is focused
    and not searching. There is no default panel binding for it.
  - The custom title is stored as `custom_title`.
- **Close.** Terminal threads are closed, not archived. They never go to
  Thread History. Close with the hover `×` or `shift-backspace`
  (`agent::ArchiveSelectedThread`) in the sidebar. A terminal that sends its
  own `CloseTerminal` event (the shell exits) asks the sidebar to close the
  row.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have.
  - Labels: `<leader>ar`, `<M-r>`, `<C-r>` in the picker, `r` in the view.
  - Kill: `<leader>ax`, `<C-x>` in the picker, `x` in the view.
  - A dead session is auto-unregistered by the detach sweep.

### 1.7 Persistence and restore of terminal threads

- **What it does.** The metadata (id, title, custom title, created_at,
  worktree paths, remote connection, working directory) is stored in SQLite
  (`terminal_thread_metadata_store.rs`), so terminal rows survive a restart.
  - On reopen, only the last-active terminal is respawned. The others stay as
    sidebar rows and respawn lazily when clicked (`restore_terminal`,
    `agent_panel.rs:~2439`; sidebar ~4591).
  - A respawn is a fresh shell in the saved working directory, with
    `terminal_init_command` run again. The old process and its conversation
    are gone.
  - Resuming the conversation is up to the CLI, for example an init command
    of `claude --continue`.
- **Terminal-mode relevance:** high. The metadata and lazy respawn are
  cheap. A real resume needs CLI flags.
- **Current nvim setup:** missing. GUIDE.md says nothing persists across an
  nvim restart without sidekick's mux backend, and the agent view closes
  before the session is saved. Re-creating a killed name starts a fresh
  conversation.

### 1.8 Sending editor context into a terminal thread

- **What it does.** `cmd->` (`agent::AddSelectionToThread`, bound in the
  editor, in the agent thread and in terminals) acts on the active panel
  entry.
  - **When that entry is a terminal thread,** it pastes text instead of
    adding a mention (`format_selection_for_terminal`, `agent_panel.rs:~725`):
    - An editor selection becomes `relpath:start-end ` (the path relative to
      the terminal's cwd, 1-based lines, a trailing space, no `@`, no file
      content).
    - A terminal selection is pasted as raw text.
  - **When it is an agent thread,** a terminal selection becomes a
    `TerminalSelection` mention crease.
  - It always targets the active thread. There is no picker to choose one.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have, and richer.
  - `<leader>at` sends `@file#L` refs.
  - `<leader>af` and `<leader>ac` send the enclosing function or class.
  - `<leader>ae` and `<leader>aE` send diagnostics.
  - `<leader>ab` sends buffers, `<leader>aq` sends the quickfix list, and
    visual `<leader>as` sends the literal selection.
  - `<C-CR>` sends picker selections.

  All of these target the active session.

### 1.9 Program detection (telemetry only)

- **What it does.** Zed watches the terminal's foreground process name and
  matches it against `KNOWN_TERMINAL_AGENT_COMMANDS` (`agent_panel.rs:~113`):
  agent, agy, aider, amp, claude, codex, copilot, crush, devin, droid,
  gemini, goose, grok, openhands, opencode, pi and qwen. The match only
  feeds a telemetry event. No UI uses it.
- **Terminal-mode relevance:** low. It is noted only because the hook could
  be used for per-agent icons.
- **Current nvim setup:** have, in a different way. The session's name
  prefix carries its agent identity.

## 2. Managing several threads

The main code is in `crates/sidebar/src/sidebar.rs` (8.4k lines),
`crates/sidebar/src/thread_switcher.rs`,
`crates/workspace/src/multi_workspace.rs`,
`crates/agent_ui/src/{agent_panel.rs, threads_archive_view.rs,
thread_import.rs, thread_metadata_store.rs}`. The docs are
`docs/src/ai/parallel-agents.md` and `agent-panel.md`.

### 2.1 Threads Sidebar

- **What it does.** A list of every thread, grouped by project.
  - Toggle it with `cmd-alt-j` (`multi_workspace::ToggleWorkspaceSidebar`).
  - Focus it with `cmd-alt-;`.
  - Settings: `agent.threads_sidebar.position` (`left`/`right`),
    `default_width` (300) and `auto_open` (true).
- **Each row shows** (`render_thread`, ~6242; `ThreadItem` in
  `crates/ui/src/components/ai/thread_item.rs`):
  - the agent icon (an external agent's own SVG, the Zed icon, or a circle
    for drafts);
  - the title, with fuzzy-match highlights while filtering;
  - a status icon, or a spinner while running (section 3.1);
  - a relative timestamp;
  - `+added/-removed` diff stats from the thread's action log;
  - worktree and branch chips;
  - a remote icon.
- **Hover buttons:** Rename (pencil), plus Stop while running or Archive
  otherwise. Drafts show Discard.
- **Context menu:** Rename Title, Regenerate Thread Title (native only), Open
  Thread as Markdown, Archive.
- **Order:** inside a group, newest first by `interacted_at`, falling back to
  `updated_at`. Terminal rows merge in by `created_at`.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** partial. The agent view (`<leader>av`, `<M-v>`) is
  a 30-column sidebar in its own tab. Each row has a status glyph, an index
  digit, a `▸` active marker, and the label with the raw name dimmed. Rows
  are name-sorted. Compared with Zed, there is no project grouping, no
  timestamp, no diff stats, and no worktree or branch chip.

### 2.2 Grouping by project, and several projects in one window

- **What it does.** `MultiWorkspace` lets one window hold several workspaces
  (projects), with one shown at a time. The sidebar groups threads by
  `ProjectGroupKey`: the main worktree's paths plus the remote host.
  - Linked git worktrees map to their main repo, so a thread running in a
    worktree appears under the main project.
  - Group headers collapse.
  - Order is manual: "Move Up/Down" in the header's `…` menu, with unbound
    `MoveProjectUp`/`Down`.
  - The header's `…` menu also has Open Project in New Window, Focus Project,
    an Open Worktrees list with Close Worktree, Create New Worktree, and
    Remove.
  - Add a project from the bottom bar's open-folder button, which offers
    recent projects, Add Local Folders and Add Remote Folder.
  - Multi-root projects let one thread span several folders.
- **Terminal-mode relevance:** medium. Grouping is easy if sessions record
  their cwd or worktree. Several projects in one window is a bigger change
  for nvim, where cwd is global or per tab.
- **Current nvim setup:** missing. Sessions are keyed by `(tool name, cwd)`,
  but nothing groups them by project, and one nvim instance is effectively
  one project.

### 2.3 Filtering and search

- **What it does.** Press `cmd-f` in the sidebar
  (`agents_sidebar::FocusSidebarFilter`). It fuzzy-matches thread titles,
  terminal titles, project labels and worktree names (sidebar ~1889-1933).
  Thread History has its own fuzzy search on titles.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have. The `<leader>al` snacks picker matches both
  the label and the raw name.

### 2.4 Creating threads

- **Entry points:**
  - `cmd-n` (`agent::NewThread`, repeats the last kind).
  - `cmd-alt-shift-n` opens the new-thread menu: Zed Agent, Terminal,
    External Agents by name, then "Add More Agents", which opens the ACP
    registry.
  - `agents_sidebar::NewThreadInGroup` (`cmd-n` while the sidebar is focused)
    targets the selected row's project.
  - The hover `+` on a project header opens a "New Thread In…" menu listing
    that group's workspaces and worktrees.
  - `agent::NewExternalAgentThread {agent}` is the per-agent action. It is
    unbound, and is the thing to bind for a key per agent.
- **Remembered choice.** The selected agent is remembered per workspace, with
  a global fallback.
- **Drafts.** An empty draft row is discarded automatically. A draft with
  text in it is kept (`draft_prompt_store.rs`).
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have. `<leader>an` (agent picker, then label; a
  blank label auto-names the session) and `<M-n>` (fork the same agent).
  Typed labels create named sessions that can be re-attached.

### 2.5 Switching threads

- **Thread switcher.** `ctrl-tab` (`agents_sidebar::ToggleThreadSwitcher`;
  `ctrl-shift-tab` passes `select_last`) opens an overlay of every thread and
  terminal across all projects, in MRU order. It is bound in the panel, the
  sidebar and the switcher.
  - Rows show the icon, status, project and worktree, diff stats and
    timestamp.
  - Pressing `ctrl-tab` again cycles. Each step previews live by switching
    the panel and workspace. Releasing the modifier commits; `Esc` restores
    the original.
  - It needs at least two entries (`thread_switcher.rs`; sidebar
    ~5863-6180).
- **Sidebar order.** `multi_workspace::NextThread`/`PreviousThread` cycle in
  sidebar order, wrap around, and include terminals. They are unbound by
  default.
- **Not found:** a "jump to the thread that needs attention" action.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** partial. The building blocks:
  - `<M-]>`/`<M-[>` cycle in name order.
  - `<M-1>`..`<M-9>` jump directly.
  - `<C-]>` toggles to the last-used session (MRU depth 1).
  - In the agent view, `j`/`k` preview live without committing.

  Missing: an MRU list deeper than one, shown as an overlay. nvim does have
  the attention jump (`<leader>aj`) that Zed lacks.

### 2.6 Naming threads

- **Zed Agent.** Titles are generated automatically by the
  thread-summary model (`Thread::generate_title`,
  `crates/agent/src/thread.rs:~4209`), gated by
  `agent.auto_generate_thread_titles` (true). A spinner shows while the title
  generates. "Regenerate Thread Title" is in the context menu.
- **External agents.** The title comes from ACP session-info updates. A user
  rename is stored as `title_override` and wins over the agent's updates.
- **Terminal threads.** Titled from OSC (section 1.3).
- **Terminal-mode relevance:** high for OSC titles. For summary titles,
  medium: the CLI could supply one through a hook.
- **Current nvim setup:** partial. Auto-names are numbered (`claude 2`), and
  labels are manual. There is no content-derived title.

### 2.7 Archive, Thread History, restore and delete

- **Archive.**
  - `shift-backspace` in the sidebar, or the hover archive icon.
  - It is a no-op on threads that are Running, WaitingForConfirmation or
    Unconfirmed (sidebar ~5752). Those rows show Stop instead.
  - Archiving a thread in a Zed-created worktree can also save and remove
    that worktree (section 4.3).
- **History.** `cmd-g` in the sidebar (`agents_sidebar::ToggleThreadHistory`)
  or the clock button opens `ThreadsArchiveView`.
  - Fuzzy search, time buckets ("This Week", "Past Week", …), and a "Show
    Only Archived" toggle.
  - Click a row to unarchive and reopen it. Its worktree is restored if
    needed.
  - The trash icon, or `cmd-shift-backspace` (`agent::RemoveSelectedThread`),
    deletes permanently and cleans up archived worktree data.
- **Storage.** The SQLite table `sidebar_threads` (`thread_metadata_store.rs`).
- **Terminal-mode relevance:** medium. Archiving a terminal session only
  means something if it can be resumed (CLI resume flags).
- **Current nvim setup:** missing. Kill is final.

### 2.8 Importing and resuming external-agent sessions

- **Import** (`thread_import.rs`). A modal lists every external agent with
  checkboxes and per-agent counts. Zed connects to each and calls ACP
  `session/list`.
  - Agents without that capability show as "Unsupported". The docs say Cursor
    and Gemini CLI are unsupported (**docs only** for the named agents).
  - Imported threads arrive archived, so they appear only in History.
  - An onboarding banner offers the import the first time.
  - `agent::ImportThreadsFromOtherChannels` copies threads between Zed
    release channels.
- **Resume.** ACP `load_session` and `resume_session` reopen a thread whose
  process was unloaded or lost (`crates/acp_thread/src/connection.rs:~117-173`).
- **Terminal-mode relevance:** medium. The CLI equivalents are
  `claude --resume <id>`, `codex resume` and similar. Listing past sessions
  would mean reading each CLI's session store.
- **Current nvim setup:** missing. Each CLI's own `/resume` still works
  inside a session.

### 2.9 Background running, retention and limits

- **What it does.** A thread keeps running when you switch away. Its view is
  held in `retained_threads` (`retain_running_thread`,
  `agent_panel.rs:~4228`).
  - Idle threads that can be reloaded are evicted oldest first beyond
    `agent.max_idle_retained_threads` (5; 0 unloads every idle thread).
    Running or blocked threads are never evicted. An evicted thread reloads
    through `session/load` when clicked.
  - There is no concurrency limit or queue for top-level threads. The only
    limit found is `MAX_SUBAGENT_DEPTH = 1`.
  - `agent.prevent_idle_sleep` (true) keeps the machine awake while threads
    run.
  - Quit shows only the generic confirm-quit prompt. No warning about
    running agents was found.
- **Terminal-mode relevance:**
  - Background running: high.
  - Retention and eviction: low. Terminals cannot be unloaded and reloaded
    without losing state.
  - Idle-sleep prevention: high, since it only needs to know "something is
    running".
- **Current nvim setup:**
  - Background running: have. Jobs survive hiding, and the agent view leaves
    every job running.
  - Idle-sleep prevention: missing.
  - Quit warning: missing.

### 2.10 Panel layouts

- **Layouts.** `workspace::UseAgenticLayout` and `UseClassicLayout` are in
  the user menu under Panel Layout and unbound by default. Agentic puts the
  Agent Panel and Threads Sidebar on the left, and the project and git panels
  on the right. A "Custom" state appears when panels match neither preset
  (`crates/title_bar/src/title_bar.rs:~85-120, ~1410`).
- **Panel settings.** `agent.dock` (left), `agent.flexible` (proportional
  width), `default_width` (640).
- **Zoom.** `shift-escape` (`workspace::ToggleZoom`) zooms the panel.
- **Not found:**
  - opening a thread in a center-pane tab or its own window;
  - two threads side by side.

  The panel shows one thread at a time. Only "Open Thread as Markdown" puts
  a read-only copy in a tab.
- **Terminal-mode relevance:** high. Layout is pure editor UI.
- **Current nvim setup:** have, and it differs. There is a right split
  column with a remembered width, plus the agent view as a separate tab (a
  mode switch, like diffview). nvim windows could show two sessions side by
  side, which Zed cannot.

## 3. Status and attention

The main code is in `crates/ui/src/components/ai/thread_item.rs`,
`crates/sidebar/src/sidebar.rs` (`all_thread_infos_for_workspace` ~8110,
group header ~2439), `crates/agent_ui/src/conversation_view.rs`
(`notify_with_sound` ~3406, `show_notification` ~3473),
`crates/agent_ui/src/ui/agent_notification.rs`, and
`crates/acp_thread/src/{acp_thread.rs, submission.rs}`.

### 3.1 Per-thread status states and icons

- **States** (`AgentThreadStatus`): `Completed` (idle), `Running`,
  `WaitingForConfirmation`, `Error`, `Unconfirmed`.
- **How the state is chosen**, in this order:
  1. A pending tool permission or elicitation means waiting.
  2. `had_error` means error.
  3. Otherwise the thread's own status applies: generating means running.
- **Unconfirmed and Unknown.** These appear only for ACP agents on the
  "agent-reported activity" transport, when the agent has not reported its
  state. That protocol is negotiated only with the `acp-beta` flag.
- **Icons**, in precedence order:
  - Running: a rotating spinner.
  - Error: a red ×.
  - Waiting: a yellow warning icon.
  - Unconfirmed: a muted info icon.
  - Unread: an accent dot.
  - Otherwise: the agent icon.
- **Inside a thread.**
  - A "Dots" spinner while running.
  - A "Sand" spinner with "Awaiting Confirmation" while a permission is
    pending.
  - Footer labels such as "N tasks in background".
- **Terminal threads** get only the unread dot, or a title glyph
  (section 1.4).
- **Terminal-mode relevance:** high, given hook events. Pure BEL cannot
  tell the states apart.
- **Current nvim setup:** have, except error. The glyphs are `!` urgent,
  `●` unread, `»` running, `○` idle and `…` spawning. They are distinct
  shapes, not just colors. There is no error state, and cursor, pi and omp
  never show `!` (GUIDE.md notes this tiering).

### 3.2 Unread ("finished while you weren't looking")

- **Agent threads.** A thread is marked unread when it goes from Running to
  Completed while it is not the active entry. The mark clears when it becomes
  the active, visible entry. It is held in memory only. Only that transition
  counts; waiting and error have their own icons.
- **Terminals.** Unread is set by the bell (section 1.5).
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have, and more careful:
  - A `●` for the pane you are looking at is deferred, then promoted when
    you leave.
  - Interaction acks it; mere presence does not.
  - `<M-u>` force-dismisses one.

### 3.3 Aggregated attention

- **What it does.** A collapsed project header shows:
  - a spinner if any thread in it is running;
  - a warning icon with "N threads are waiting for confirmation" if any are
    waiting;
  - otherwise a dot if any are unread.

  Nothing aggregates more widely:
  - no title-bar indicator;
  - no badge on the dock icon (`AgentPanel::icon` is static);
  - no global counter;
  - no "go to the next waiting thread" action.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** have, and ahead.
  - The statusline badge names the top candidate: `! refactor +2`.
  - `<leader>aj` jumps to the most recent unread session and notifies what
    it wants, including the agent's own prompt text.

### 3.4 Notifications: popup, dock bounce, sound

- **Which events** (`conversation_view.rs`):
  - tool authorization requested: "Waiting for tool confirmation";
  - elicitation requested: "Waiting for input";
  - turn ended: "Finished running tools" or "New message";
  - output token limit, refusal, and error stops.

  Subagent threads never notify.
- **Popup.**
  - A borderless 450×72 Zed window at the top right that does not take
    focus.
  - Shows the thread title, project and caption, with **View** (activates
    the window, the right workspace in the MultiWorkspace, the panel and the
    thread) and **Dismiss**.
  - It closes itself when the thread becomes visible.
  - At most one popup per conversation at a time.
  - With `notify_when_agent_waiting` set to `primary_screen` (default),
    `all_screens` or `never`, it also calls `request_attention()` (dock
    bounce).
- **Sound.** `play_sound_when_agent_done` is `never` (default), `when_hidden`
  or `always`. "Hidden" means the window is inactive, or neither the sidebar
  nor this thread is visible. Sound does not depend on the popup setting.
- **Not found:** integration with the OS notification center.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** partial.
  - A macOS desktop notification fires for urgent events only, at most once
    per blocked episode, and only when nvim lacks OS focus. It uses
    `terminal-notifier` or `osascript`.
  - Missing: turn-complete notifications (left out on purpose), sound, dock
    bounce, and a click-through that focuses the right session.

### 3.5 Context window, tokens and cost

- **What it does.**
  - A 16 px ring in the message-editor footer shows used tokens against the
    maximum. It turns the warning color at 85%. Models with split input and
    output limits get two rings.
  - The hover tooltip shows the percentage, input and output tokens, cost
    (from ACP `UsageUpdate.cost`), and for native threads the loaded
    AGENTS.md and project rules.
  - At 80%, small-context native threads show a "reaching the token limit"
    callout with "Start New Thread". Large windows auto-compact
    (`agent.auto_compact`, threshold 90%).
  - Optional `agent.show_turn_stats` adds elapsed time and per-turn tokens.
  - ACP agents report usage through `UsageUpdate`. Per-response token counts
    need `acp-beta`.
  - None of this is shown in the sidebar.
- **Terminal-mode relevance:** low to medium. The CLI renders its own. Some
  CLIs expose usage to statusline or hook scripts, for example Claude Code's
  statusline JSON.
- **Current nvim setup:** missing. Each CLI shows its own.

### 3.6 Error surfacing

- **Thread errors** appear as callouts with Retry where it is possible:
  "Rate Limit Reached", "Provider Unavailable", "Connection Interrupted",
  "Authentication Failed", and so on (`render_thread_error`,
  `thread_view.rs:~12836`). An auto-retry banner shows "Retrying. Next
  attempt in N seconds".
- **Agent-server failures** appear as "Failed to Install" or "Failed to
  Launch", with stderr and a Retry button. Losing the connection shows
  "Reconnect to restore the conversation".
- **Status.** Errors show a red × in the sidebar and a warning popup.
- **Terminal-mode relevance:** medium. A failure event from a CLI hook, or
  a dead process, could feed an error state.
- **Current nvim setup:** partial. A missing binary aborts with a notify. A
  dead session is swept. There is no error glyph.

## 4. Isolation: git worktrees per thread

The main code is in `crates/git_ui_core/src/{worktree_picker.rs,
worktree_service.rs, worktree_names.rs, created_worktrees.rs}`,
`crates/agent_ui/src/thread_worktree_archive.rs`,
`crates/project/src/git_store.rs` (~6201, ~10809),
`crates/git/src/repository.rs` (~3085), and
`crates/workspace/src/tasks.rs:~243`. The docs are `parallel-agents.md`
(Worktree Isolation), `git.md` and `tasks.md` (hooks).

### 4.1 Creating a worktree for a thread

- **There are three ways:**
  - The title-bar worktree picker. `cmd-ctrl-w` opens it (`git::Worktree`).
    It can create from the current or default branch (named, or with an
    auto-generated `adjective-noun` name), switch, open in a new window, or
    delete. Inside the picker, `cmd-shift-backspace` deletes and
    `cmd-alt-shift-backspace` force-deletes.
  - The sidebar project-header menu > "Create New Worktree…" > "Based on
    <branch>". This one is not in the docs.
  - The flagged `create_thread` agent tool (section 9.2).
- **Not found:** a "run this thread in a new worktree" option in the
  new-thread flow. A worktree opens as its own workspace. A thread started
  there is grouped under the main repo and carries a worktree chip.
- **Placement and state.**
  - Worktrees always start with a detached HEAD. A multi-repo project gets
    one linked worktree per repo.
  - The location is `git.worktree_directory`, default `"../worktrees"`,
    which resolves to `<parent>/worktrees/<project>/<name>`.
- **Branch picker, docs only:** choosing a branch that is already checked out
  elsewhere leaves the worktree detached.
- **Terminal-mode relevance:** high. A worktree is just a cwd for the CLI.
- **Current nvim setup:** missing. Neogit's worktree popup (`<leader>Gw`)
  can create one by hand, but sessions are not tied to worktrees. Sessions
  use nvim's cwd.

### 4.2 Setup hook for new worktrees

- **What it does.** The task hook `create_worktree` runs after Zed creates a
  linked worktree. It gets `ZED_WORKTREE_ROOT` and `ZED_MAIN_GIT_WORKTREE`.
  There is also `zed::OpenWorktreeSetupTasks`. This repo's
  An earlier private plan in this repo already looked at this hook.
- **Terminal-mode relevance:** high.
- **Current nvim setup:** missing.

### 4.3 Archiving a thread saves and removes its worktree

- **When it applies.** When you archive a thread whose worktree meets all of
  these:
  - it is linked;
  - it lives under `git.worktree_directory`;
  - Zed's DB records that Zed created it;
  - no other unarchived thread or terminal thread uses it.
- **What happens:**
  1. Zed makes two detached commits: "WIP staged" (the index) and "WIP
     unstaged" (the full tree, including untracked files).
  2. It pins them with `refs/archived-worktrees/<id>` in the main repo.
  3. It records branch, SHAs and path in the DB.
  4. It runs `git worktree remove`, after re-checking that the directory is
     the one Zed created.
- **Restore.** Zed re-creates the worktree at the original commit, checks
  out the recorded branch (staying detached if the branch has moved since),
  rebuilds the index and working tree from the checkpoint, and reopens the
  thread.
- **Delete.** Permanently deleting a thread cleans up the ref and the DB row.
- **What it is not.** It is not a stash and not a branch commit, and no
  branch moves.
- **Terminal-mode relevance:** medium. It is plain git, but it needs the
  "archive a session" concept first.
- **Current nvim setup:** missing.

### 4.4 Merging back

- **What it does.** Nothing special. The docs say to "review the diff and
  merge through your normal Git workflow". No apply-to-main or create-PR
  action was found. Per-thread diff stats are the only per-thread git
  summary.
- **Terminal-mode relevance:** high, since it is plain git.
- **Current nvim setup:** partial. Neogit and diffview cover the normal
  workflow. `<leader>vp` diffs a PR against its base branch.

## 5. Reviewing agent edits

The main code is in `crates/action_log/src/action_log.rs`,
`crates/agent_ui/src/agent_diff.rs`,
`crates/agent_ui/src/conversation_view/thread_view.rs` (`render_edits_summary`
~5290), and `crates/acp_thread/src/acp_thread.rs` (~8130-8300 fs writes,
~8053 rewind).

### 5.1 Edits summary bar

- **What it does.** An accordion above the message editor shows "N files"
  with +/- counts and lists the changed files. It has Review Changes, Reject
  All and Keep All buttons, which stay disabled while edits are still
  streaming.
- **Terminal-mode relevance:** medium. A per-session `git diff --stat` works
  only when sessions are isolated, for example by worktree. Otherwise you
  cannot tell which agent made which change.
- **Current nvim setup:** missing.

### 5.2 Agent Diff multibuffer and keep/reject

- **What it does.** `AgentDiffPane` is one tab per thread: a split or
  unified multibuffer of every changed buffer.
  - Each hunk has Keep and Reject buttons and previous/next arrows. The
    toolbar has Keep All and Reject All.
  - Keys:
    - `cmd-y` keeps a hunk and `cmd-alt-z` rejects it.
    - `shift-alt-y` keeps all and `shift-alt-z` rejects all.
    - `shift-alt-u` undoes the last reject.
    - `shift-ctrl-r` opens the diff.
  - `agent.single_file_review` (default false) puts the same Keep and Reject
    controls inline in regular editors, temporarily replacing the git diff.
- **Where it works.**
  - Native threads.
  - ACP threads, but only for edits the agent sends through ACP
    `fs/write_text_file`, which Zed applies to a buffer and records in the
    action log.
  - Not for an ACP agent writing files directly with its own tools or shell.
  - Never for terminal threads.
- **Terminal-mode relevance:** medium. A git-based equivalent (hunks of the
  session's worktree against its base) is possible. True per-edit tracking
  needs the protocol.
- **Current nvim setup:** partial. `<leader>vv` diffs uncommitted changes in
  diffview, and gitsigns can stage or reset hunks. Neither knows which agent
  made a change.

### 5.3 Follow the agent

- **What it does.** A crosshair button at the bottom left of the panel, or
  `cmd-enter` (`agent::ChatWithFollow`, send and follow). The workspace
  follows `CollaboratorId::Agent`, so the editor jumps to each file the agent
  reads or writes. For ACP agents this works only through fs requests. The
  plain `agent::Follow` action is unbound.
- **Terminal-mode relevance:** low to medium. Tool hooks that carry file
  paths (for example Claude `PostToolUse`) could drive it.
- **Current nvim setup:** missing.

### 5.4 Edit and rewind, and checkpoints

- **What it does.** Editing an earlier user message truncates the thread from
  that point, reverts that turn's edits through the action log, and
  regenerates. It works only where the connection supports `truncate`, which
  in practice means the native Zed agent; no real ACP implementation exists.
- **Not found:** a git "Restore checkpoint" UI on messages at this HEAD. The
  only checkpoint code is worktree archiving.
- **Terminal-mode relevance:** n/a. The CLI owns it, for example Claude
  Code's `/rewind`.
- **Current nvim setup:** n/a.

## 6. Context and input

The main code is in `crates/acp_thread/src/mention.rs`,
`crates/agent_ui/src/{completion_provider.rs, message_editor.rs}`, and
`crates/agent_skills`.

### 6.1 `@`-mentions

- **Kinds:** File, Directory, Symbol, Selection, Thread, Diagnostics, Fetch
  (URL), Branch diff, Skill, Pasted image, Terminal selection, Merge conflict.
  `ctrl-;` opens the add-context menu.
- **For ACP agents:**
  - Thread, Diagnostics, Fetch, Skill and Branch diff are offered only if the
    agent advertises `embedded_context`.
  - Mentions are sent as embedded resources, or as resource links without
    that capability.
  - Images need the `image` capability.
- **Terminal-mode relevance:** low. The `@` syntax is the CLI's, though text
  refs work.
- **Current nvim setup:** partial. Files, selections, function or class,
  diagnostics, buffers and quickfix are sent as `@file#L` refs. GUIDE.md
  notes these auto-attach only on claude and cursor. There are no
  thread, URL or branch-diff mentions.

### 6.2 Rules, instructions and Skills

- **Rules.** The native agent loads the first match among `.rules`,
  `.cursorrules`, … `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, plus a personal
  `~/.config/zed/AGENTS.md`.
- **Skills.** Loaded from `~/.agents/skills/*/SKILL.md` and project
  `.agents/skills`. Invoke one with `/skill-name` or an `@` mention; the
  model uses the `skill` tool. Native only. `cmd-alt-l` opens Manage Skills.
- **Terminal-mode relevance:** n/a. The CLI owns these.
- **Current nvim setup:** n/a.

### 6.3 Slash commands

- **What it does.** ACP agents publish `available_commands`, which appear in
  a `/` popup next to native `/compact`, MCP prompts and skills.
- **Terminal-mode relevance:** n/a.
- **Current nvim setup:** n/a. The prompt library at `<leader>ao` is the
  nearest thing.

### 6.4 Message queue and steer

- **What it does.** Sending while a thread runs queues the message.
  - `cmd-shift-enter` interrupts and sends now.
  - `cmd-shift-alt-enter` sends the next queued message.
  - `cmd-ctrl-e` edits the first queued message, and `cmd-shift-backspace`
    removes it.
  - `cmd-alt-backspace` clears the queue.
  - `cmd-ctrl-s` (native only) toggles "steer", which injects the message at
    the next step boundary.
- **Terminal-mode relevance:** n/a. The CLIs have their own queueing.
- **Current nvim setup:** n/a. The `p`/`P` bracketed paste and the `u`
  undo forward help with typing into the TUI.

## 7. Per-thread configuration: agent, model, profile, mode

- **Agent.** Each thread can use a different agent (section 2.4).
- **Native agent.**
  - Profiles: Write, Ask, Minimal, or custom. `cmd-i` opens the selector,
    `shift-tab` cycles, and `cmd-alt-p` manages profiles.
  - Model: `cmd-alt-/` opens the picker and `alt-tab` cycles
    `agent.favorite_models`.
  - Thinking: `cmd-alt-k` toggles it. `cmd-alt-'` and `ctrl-'` set the
    effort.
  - Fast mode: `cmd-alt-.`.
- **ACP agents.** The same keys drive the agent's session modes and config
  options (Mode, Model, ThoughtLevel). Per-agent defaults and favorites live
  in `agent_servers.<id>`.
- **Terminal-mode relevance:** n/a. The CLI owns these, and each TUI has its
  own key.
- **Current nvim setup:** n/a. The choice of agent at spawn time is covered.

## 8. Tool permissions, sandboxing and MCP

### 8.1 Permission prompts

- **What it does.** `agent.tool_permissions` has a default (`confirm`) plus
  per-tool regex lists for `always_allow`, `always_deny` and
  `always_confirm`, matched against commands, paths and URLs. MCP tools are
  matched as `mcp:<server>:<tool>`.
  - The prompt UI shows an ACP agent's own options as buttons, or for the
    native agent a granularity dropdown with checkboxes per command pattern.
  - Keys: `cmd-y` allows once, `cmd-alt-y` allows always, `cmd-alt-z`
    rejects, and `cmd-alt-a` opens the dropdown.
  - For external agents, Zed's deny and confirm rules still take precedence.
- **Terminal-mode relevance:** low. In a terminal the CLI renders its own
  prompt. What carries over is surfacing that a prompt is waiting, which is
  covered in section 3.
- **Current nvim setup:** partial. Landing via `<leader>aj` notifies with the
  permission text. You answer in the TUI.

### 8.2 Sandboxing

- **What it does.** An OS-level sandbox for the native agent's `terminal`
  and `fetch` tools: writes are allowed only inside the project, network is
  blocked, and the agent asks to escalate. It is behind the `sandboxing`
  flag, which is enabled for everyone. It does not apply to ACP agents or
  terminal threads.
- **Terminal-mode relevance:** n/a.
- **Current nvim setup:** n/a.

### 8.3 MCP

- **What it does.** `context_servers` configures stdio or HTTP servers.
  Their tools show up in profiles, and their prompts become slash commands.
  Zed forwards the configured servers to ACP agents in `new_session`,
  `load_session` and `resume_session`
  (`crates/agent_servers/src/acp/v1.rs:~10030`).
- **Terminal-mode relevance:** n/a. The CLI's own config applies.
- **Current nvim setup:** n/a.

## 9. Agent-driven parallelism

### 9.1 Subagents (`spawn_agent`)

- **What it does.** The native agent's `spawn_agent` tool is on by default in
  the Write and Ask profiles.
  - It runs a child session and gets back only the child's final message.
    The child can be resumed by `session_id`.
  - Depth is limited to 1. The model is `agent.subagent_model`, falling back
    to the parent's.
  - The child renders as an expandable card in the parent thread, with a
    drill-in view. Children are not sidebar rows.
  - The parent shows "subagents awaiting permission".
  - ACP agents can report subagents through v2 `SubagentUpdate`, which is
    likely `acp-beta` only.
- **Terminal-mode relevance:** low. The CLI owns its subagents.
- **Current nvim setup:** n/a.

### 9.2 `create_thread`: the agent spawns sibling threads

- **What it does.** Behind the `create-thread-tool` flag, which is on for
  staff only, so in effect not public yet. The agent can create independent
  sibling threads that appear in the sidebar like threads you made yourself.
  - Inputs: title, prompt, an optional agent and model (listed by
    `list_agents_and_models`), and `use_new_worktree`, `worktree_name` and
    `base_ref`.
  - With a new worktree, the sibling opens in a fresh worktree workspace.
  - The parent gets back only the title, agent and model. It cannot watch or
    control the sibling.
  - The tool description tells the model to call it only after the user
    agrees.

  This is the clearest sign of where Zed is heading: the agent fans out work
  across isolated worktrees, and the human triages from the sidebar
  (`crates/agent/src/tools/create_thread_tool.rs`; `agent_panel.rs:~4760-4960`).
- **Terminal-mode relevance:** medium. A CLI could ask nvim over RPC to
  spawn a session, the same way the hooks already call
  `nvim --server $NVIM --remote-expr`.
- **Current nvim setup:** missing.

## 10. External agents (ACP)

- **Install.** From the ACP Registry ("Add More Agents", `zed::AcpRegistry`;
  npx or binary distributions). The built-in ids are `claude-acp`,
  `codex-acp`, `gemini` and `cursor`. Custom agents go in
  `agent_servers.<name>`.
- **Auth.** Through ACP auth methods. A "Terminal" auth method runs a login
  command in a terminal.
- **What ACP threads get, by capability:**
  - load, resume and list sessions (the list powers import);
  - modes and config options;
  - slash commands;
  - images and embedded context;
  - plan and todo display (a collapsible progress list above the editor);
  - agent terminals embedded in the thread;
  - follow and edit review, but only for edits that go through ACP fs.
- **What ACP threads lack compared with native:** Zed profiles, skills, fast
  mode, steer, rewind and sandboxing.
- **Logs.** `dev::OpenAcpLogs` (`crates/acp_tools`) is a JSON-RPC traffic
  viewer for debugging an agent connection.
- **Beta.** `acp-beta` switches to the ACP v2 schema: reported activity,
  per-response usage, initial session options and subagent updates.
- **Terminal-mode relevance:** low. This is the alternative to terminal
  mode, included for completeness.
- **Current nvim setup:** missing, and not wanted. The setup is terminal
  mode on purpose.

## 11. Keybindings that make the multi-agent workflow fast (macOS defaults)

**Global and panel**

| Action | Key | Context |
|---|---|---|
| `multi_workspace::ToggleWorkspaceSidebar` | `cmd-alt-j` | Workspace |
| `multi_workspace::FocusWorkspaceSidebar` | `cmd-alt-;` | Workspace |
| `agent::ToggleFocus` | `cmd-?` | Workspace |
| `agent::NewThread` (repeats last kind) | `cmd-n` | AgentPanel |
| `agent::ToggleNewThreadMenu` | `cmd-alt-shift-n` | AgentPanel |
| `agents_sidebar::ToggleThreadSwitcher` | `ctrl-tab` / `ctrl-shift-tab` | AgentPanel, ThreadsSidebar |
| `agent::AddSelectionToThread` | `cmd->` | Editor, AcpThread, Terminal |
| `git::Worktree` (worktree picker) | `cmd-ctrl-w` | Workspace |
| `workspace::ToggleZoom` | `shift-escape` | Workspace |

**Threads Sidebar**

| Action | Key | Context |
|---|---|---|
| `agents_sidebar::NewThreadInGroup` | `cmd-n` | ThreadsSidebar |
| `agents_sidebar::FocusSidebarFilter` | `cmd-f` | ThreadsSidebar |
| `agents_sidebar::ToggleThreadHistory` | `cmd-g` | ThreadsSidebar |
| `agent::ArchiveSelectedThread` (closes a terminal) | `shift-backspace` | ThreadsSidebar |
| `agent::RemoveSelectedThread` | `cmd-shift-backspace` | ThreadsSidebar |
| `agent::RenameSelectedThread` | `shift-r` | ThreadsSidebar, not searching |

**Inside a thread**

| Action | Key | Context |
|---|---|---|
| `agent::AllowOnce` / `AllowAlways` / `RejectOnce` | `cmd-y` / `cmd-alt-y` / `cmd-alt-z` | AcpThread |
| `agent::Keep` / `Reject` | `cmd-y` / `cmd-alt-z` | AgentDiff, editor_agent_diff |
| `agent::KeepAll` / `RejectAll` | `shift-alt-y` / `shift-alt-z` | AgentDiff, AcpThread |
| `agent::OpenAgentDiff` | `shift-ctrl-r` | AcpThread, Editor |
| `agent::ChatWithFollow` | `cmd-enter` | AcpThread |
| `agent::SendImmediately` | `cmd-shift-enter` | AcpThread |

**Unbound by default** (palette only):

- `agent::NewTerminalThread`
- `agent::NewExternalAgentThread {agent}`
- `multi_workspace::NextThread`, `PreviousThread`, `NextProject`,
  `PreviousProject`
- `agent::Follow`
- `workspace::UseAgenticLayout`, `UseClassicLayout`

For comparison, the nvim equivalents are already dense. The full table is
in GUIDE.md "AI (sidekick.nvim)":

- `<leader>an` / `<M-n>` create.
- `<leader>al` / `<M-l>` pick.
- `<M-]>` / `<M-[>` / `<M-1..9>` / `<C-]>` switch.
- `<leader>av` / `<M-v>` open the view.
- `<leader>aj` jumps to attention.
- `<leader>ar` / `<M-r>` label.
- `<leader>ax` kills.
- `<M-u>` dismisses a ring.

## 12. Feature flags and direction

From `crates/feature_flags/src/flags.rs`, as used in the agent crates:

- `create-thread-tool`: on for staff. The agent spawns sibling threads,
  optionally in new worktrees (section 9.2).
- `agent-thread-worktree-label`: off. A three-way enum (`Both`, `Worktree`,
  `Branch`) for how sidebar worktree chips are labeled. They are actively
  tuning how worktree identity shows in the thread list.
- `acp-beta`: on for staff. ACP v2: agent-reported activity
  (Unconfirmed/Unknown states, "N tasks in background"), per-response
  usage, session options, subagent updates.
- `diff-review`: off. Used only in `editor/src/element.rs`, not in
  `agent_ui`. Its purpose was not traced.
- `sandboxing`: on for all.
- `lsp-tool`, `rename-tool`: extra native tools.

The parallel-agent core is unflagged: sidebar, switcher, history, archive
with worktree checkpointing, import, terminal threads, queueing and
notifications. Together with `create_thread` and the worktree-label tuning,
the direction is many concurrent threads, each in its own worktree, possibly
started by an agent, triaged from one sidebar, with terminal CLIs as
first-class rows. Notable gaps in Zed itself: no "jump to the thread that
needs me", no global attention badge, no side-by-side threads, and terminal
threads with only a bell for status.

## 13. Summary table

| Feature | Terminal-mode relevance | Current nvim setup |
|---|---|---|
| 1.1 Terminal thread creation + init command | high | have |
| 1.2 Zed/CLI ownership split | n/a | have |
| 1.3 Row title from OSC terminal title | high | missing |
| 1.4 Title prefix glyph as row status icon | high | missing |
| 1.5 Bell to unread dot, popup, sound | high | partial (hook events, richer) |
| 1.6 Rename / close terminal threads | high | have |
| 1.7 Persist rows, lazy respawn with init command | high | missing |
| 1.8 Send selection into terminal thread | high | have (richer) |
| 1.9 Foreground program detection | low | have (name prefix) |
| 2.1 Threads sidebar with rich rows | high | partial (agent view) |
| 2.2 Group by project, multi-project window | medium | missing |
| 2.3 Filter / search threads | high | have (picker) |
| 2.4 Create threads, per-agent entry points | high | have |
| 2.5 MRU thread switcher with live preview | high | partial |
| 2.6 Auto / agent-supplied titles | high (OSC), medium (summary) | partial (manual labels) |
| 2.7 Archive, history, restore, delete | medium | missing |
| 2.8 Import / resume external sessions | medium | missing |
| 2.9 Background running | high | have |
| 2.9 Idle retention / eviction | low | n/a |
| 2.9 Prevent idle sleep while running | high | missing |
| 2.10 Agentic layout, zoom | high | have (different shape) |
| 3.1 Per-thread status icons | high | have (no error state) |
| 3.2 Unread tracking | high | have (richer) |
| 3.3 Aggregated attention / jump to it | high | have (Zed lacks the jump) |
| 3.4 Popup with focus-the-thread, dock bounce, sound | high | partial (urgent desktop popup only) |
| 3.5 Context ring, tokens, cost | low to medium | missing |
| 3.6 Error surfacing and retry | medium | partial |
| 4.1 Worktree per thread | high | missing |
| 4.2 create_worktree setup hook | high | missing |
| 4.3 Archive saves and removes worktree, restore | medium | missing |
| 4.4 Merge back via normal git | high | partial (Neogit, diffview) |
| 5.1 Edits summary bar, per-thread diff stats | medium | missing |
| 5.2 Agent diff multibuffer, keep/reject hunks | medium | partial (diffview, gitsigns) |
| 5.3 Follow the agent | low to medium | missing |
| 5.4 Edit and rewind earlier messages | n/a | n/a |
| 6.1 At-mentions (file, symbol, thread, fetch...) | low | partial (text refs) |
| 6.2 Rules and skills | n/a | n/a |
| 6.3 Slash commands | n/a | n/a |
| 6.4 Message queue and steer | n/a | n/a |
| 7 Per-thread model, profile, mode | n/a | n/a |
| 8.1 Tool permission prompts | low | partial (surfacing only) |
| 8.2 Sandboxing | n/a | n/a |
| 8.3 MCP config and forwarding | n/a | n/a |
| 9.1 Subagents | low | n/a |
| 9.2 Agent spawns sibling threads (flagged) | medium | missing |
| 10 ACP external agents | low | missing (by choice) |
| 11 Multi-agent keybindings | high | have |

## 14. Open questions and things I couldn't determine

- **Nothing was run.** Every claim comes from reading source at
  `596dfdcf32`. UX details such as animation, exact layout and timing were
  inferred from render code.
- **ACP edit tracking for Claude Code.** Does Claude Code's ACP adapter
  route Edit and Write through `fs/write_text_file`? If it doesn't, Zed's
  review and keep/reject flow does not see its edits. The adapter lives
  outside the Zed repo.
- **Which ACP transport each agent uses.** It was not traced whether a
  given agent lands on the agent-reported-activity transport, which gives
  `Unconfirmed`/`Unknown` states and depends on `acp-beta`.
- **Terminal threads in a non-visible workspace.** When a MultiWorkspace
  holds a workspace that is not displayed, do its terminal threads keep
  receiving bells and updating titles? Probably yes, since panels stay alive
  in held workspaces, but this was not confirmed.
- **Quit with running threads.** Are ACP processes and terminal-thread
  shells killed or cancelled on quit, and is any state saved first? Only the
  generic confirm-quit prompt was found.
- **Branch picker when the branch is checked out elsewhere.** Only the docs
  describe it. No explicit handling was found in `branch_picker.rs`.
- **Import support per agent.** "Cursor and Gemini CLI unsupported" is from
  the docs. The code only checks the `session/list` capability.
- **What `diff-review` does.** It gates something in the editor element and
  may or may not be agent-related.
- **Terminal threads and new worktrees.** Can a terminal thread be started
  directly in a new worktree? Not from the new-thread menu. A terminal thread
  created in a worktree workspace does carry the worktree chip and blocks
  that worktree's archive cleanup. Whether there are other entry points was
  not exhaustively checked.
