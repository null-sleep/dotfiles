# Zed — shortcuts, workflows, and keymaps

How to drive [Zed](https://zed.dev) from the keyboard: the default macOS
bindings that matter, the workflows behind them (agent threads, review,
git, search), and how to add your own. Install/stow steps live in README's
`## Zed` section; vim mode has its own companion, [`docs/zed-vim.md`](zed-vim.md);
nvim's keymaps live in `nvim/.config/nvim/GUIDE.md`.
Nvim comparisons are deliberately brief — learn Zed's native keys first.

**Basis: Zed 1.28.1** (`zed --version`) — checked against the `v1.28.1`
tag (`assets/keymaps/default-macos.json`, `vim.json`) and the zed.dev docs
and release notes below; "not verified" marks claims checked nowhere. After
a Zed upgrade, re-check against the new tag and bump the version here.

## References

- [Key bindings](https://zed.dev/docs/key-bindings) — keymap.json syntax,
  contexts, precedence, `use_key_equivalents`
- [Default macOS keymap (v1.28.1)](https://github.com/zed-industries/zed/blob/v1.28.1/assets/keymaps/default-macos.json)
  and [vim.json](https://github.com/zed-industries/zed/blob/v1.28.1/assets/keymaps/vim.json)
  — the ground truth for every binding in this guide
- [Vim mode](https://zed.dev/docs/vim) — `vim_mode`, the `vim` settings
  block, Zed-specific `g`/`]`/`z` maps, `:` commands
- [Agent panel](https://zed.dev/docs/ai/agent-panel),
  [Parallel agents / Threads Sidebar](https://zed.dev/docs/ai/parallel-agents),
  [External agents (ACP)](https://zed.dev/docs/ai/external-agents),
  [Inline assistant](https://zed.dev/docs/ai/inline-assistant),
  [Edit prediction](https://zed.dev/docs/ai/edit-prediction),
  [Agent settings](https://zed.dev/docs/ai/agent-settings),
  [Instructions (AGENTS.md)](https://zed.dev/docs/ai/instructions)
- [Git](https://zed.dev/docs/git), [Multibuffers](https://zed.dev/docs/multibuffers),
  [Outline panel](https://zed.dev/docs/outline-panel),
  [Terminal](https://zed.dev/docs/terminal), [Tasks](https://zed.dev/docs/tasks),
  [Debugger](https://zed.dev/docs/debugger)
- [All actions](https://zed.dev/docs/all-actions),
  [All settings](https://zed.dev/docs/reference/all-settings)
- Release notes: [stable](https://zed.dev/releases/stable) (1.19–1.28
  reviewed); blog posts
  [Parallel Agents](https://zed.dev/blog/parallel-agents),
  [Terminal Threads](https://zed.dev/blog/terminal-threads),
  [Split Diffs](https://zed.dev/blog/split-diffs),
  [ACP Registry](https://zed.dev/blog/acp-registry),
  [Hidden Gems 4](https://zed.dev/blog/hidden-gems-part-4)

Docs render keys as `mac|linux`; this guide shows only the macOS half, in
Zed's notation (`cmd-shift-p`; `ctrl-g d` is a two-key chord). Vim-mode
equivalents appear in parentheses or a third column next to each binding.

## Contents

- [Daily keys — the quick glance](#quick-glance)
- [The mental model](#mental-model)
- [Pickers and navigation](#pickers)
- [Panes, tabs, and docks](#panes-docks)
- [Editing and LSP](#editing-lsp)
- [Search and multibuffers](#search-multibuffers)
- [Git](#git)
- [Terminal, tasks, debugger](#terminal-tasks-debugger)
- [Agent panel](#agent-panel)
- [Threads sidebar](#threads-sidebar)
- [Inside a thread](#inside-thread)
- [Reviewing agent edits](#review)
- [Inline assistant and edit prediction](#inline-prediction)
- [Vim mode](#vim-mode)
- [Adding your own bindings](#custom-bindings)
- [Gotchas cheat-sheet](#gotchas)

---

<a id="quick-glance"></a>
## Daily keys — the quick glance

Used many times a day; each is covered in full below.

| key | does |
|---|---|
| `cmd-shift-p` / `cmd-p` / `cmd-shift-f` | command palette / file finder / project search |
| `f12` / `alt-shift-f12` | go to definition / find references |
| `f2` / `cmd-.` | rename / code actions |
| `cmd-shift-i` / `cmd-/` | format / toggle comment |
| `cmd-shift-e` / `ctrl-shift-g` | project panel / git panel |
| `ctrl-g d` | project diff (from the git panel) |
| `` ctrl-` `` | terminal |
| `cmd-\` / `cmd-k cmd-<arrow>` | split right / move between panes |
| `cmd-w` / `ctrl--` | close tab / jump back |
| `cmd-?` | focus agent panel; again, back to the editor |
| `shift-escape` / `ctrl-alt-w` | zoom the focused panel / close the focused dock |
| `cmd-alt-j` / `cmd-n` | toggle threads sidebar / new thread (panel focused) |
| `enter` / `cmd-enter` | send / send and follow (in a thread) |
| `ctrl-shift-r` | open agent diff (review changes) |
| `alt-shift-y` / `alt-shift-z` | keep all / reject all agent edits |

<a id="mental-model"></a>
## The mental model

1. **Everything is an action.** A key maps to an action like
   `agent::ToggleFocus`; the palette (`cmd-shift-p`, or vim's `:`) lists it
   as `agent: toggle focus` with its binding — that is how you find names
   for keymap.json.
2. **The window is a tree: Workspace > Docks and Panes > Editors/Panels.**
   Three docks (left, bottom, right) host panels; the center holds panes of
   tabs. Bindings are scoped to a node via `context`, so one key can mean
   different things in the editor, the git panel, and an agent thread.
3. **Multibuffers are Zed's quickfix list — but editable.** Project search,
   diagnostics, references, project diff, and agent review all open one
   buffer of excerpts from many files; edit in place, `cmd-s` saves all.
   Since 1.9 most of these also have a Telescope-style picker with a
   preview pane (`alt-cmd-f` live grep, `lsp_results_location: "picker"`)
   for when you want to look, not edit.
4. **The agent panel is just a dock panel.** Threads (Zed Agent, external
   ACP agents, Terminal Threads) live in the Threads Sidebar; focus, zoom,
   and close are the generic dock operations.
5. **Your keymap.json loads after the defaults**, so a later definition in
   the same context wins. Binding `null` unbinds.

**Coming from the nvim config:** `cmd-p` is `<leader>sf`, `cmd-shift-f` is
`<leader>sg`, `cmd-shift-e` is `<leader>e`, `cmd-.` is `<leader>ca`, and
`cmd-?` is roughly `<leader>aa` (sidekick). Which leader keys to carry into
vim mode is decided in [`docs/zed-vim-keymap.md`](zed-vim-keymap.md); the
mechanics are under [Adding your own bindings](#custom-bindings).

<a id="pickers"></a>
## Pickers and navigation

| binding | action | what it does |
|---|---|---|
| `cmd-shift-p` | `command_palette::Toggle` | every action, with its binding; sorted by recency |
| `cmd-p` | `file_finder::Toggle` | fuzzy file finder with preview; pre-fills from the selection (`file_finder.prefill_query_from_selection`) |
| `alt-cmd-f` | `text_finder::Toggle` | live-grep picker with preview (Telescope `live_grep`); pre-fills from the selection or an open search; from the project-search view it carries the query over |
| `cmd-t` / `cmd-shift-o` | `project_symbols::Toggle` / `outline::Toggle` | workspace symbols (with preview) / current-file symbols (modal) |
| `cmd-shift-b` | `outline_panel::ToggleFocus` | outline as a panel; in a multibuffer, a tree of its files |
| `ctrl-tab` / `ctrl-shift-tab` | `tab_switcher::Toggle` | MRU tab switcher with file preview |
| `cmd-alt-o` | `projects::OpenRecent` | recent projects |
| `cmd-ctrl-b` / `cmd-ctrl-w` | `branches::OpenRecent` / `git::Worktree` | branch and worktree pickers; worktree workflow in [`docs/zed-worktrees.md`](zed-worktrees.md) |
| `ctrl-g` | `go_to_line::Toggle` | go to line |
| `ctrl--` / `ctrl-_` | `pane::GoBack` / `pane::GoForward` | jump list (`ctrl-o`/`ctrl-i`) |
| `cmd-k cmd-p` | `workspace::ReopenLastPicker` | reopen the last picker |
| `cmd-shift-m` | `diagnostics::Deploy` | all project diagnostics as a multibuffer |

Inside any picker (`menu` context): `enter` confirms, `cmd-enter` opens in
a split, `escape`/`ctrl-c` cancels, `ctrl-n`/`ctrl-p` or arrows move. In
the file finder, `cmd-shift-i` toggles ignored files.

**Telescope-style pickers (1.9+):** picker modals resize by dragging, the
file finder, text finder, and project symbols show a live preview pane, and
`"lsp_results_location": "picker"` turns references / definition /
implementation results into a filterable picker instead of a multibuffer
(per binding: `["editor::FindAllReferences", { "open_results_in": "picker" }]`).
So the choice is yours per feature: picker for a quick look, multibuffer
(`cmd-shift-f`, `cmd-shift-m`) when you want to edit the results in place.
Still no plugin ecosystem — the set of pickers is fixed.

<a id="panes-docks"></a>
## Panes, tabs, and docks

| binding | action | what it does |
|---|---|---|
| `cmd-b` / `cmd-r` / `cmd-j` | `workspace::ToggleLeftDock` / `ToggleRightDock` / `ToggleBottomDock` | show/hide a dock without moving focus |
| `cmd-alt-y` | `workspace::ToggleAllDocks` | hide/show every dock — from a dock or empty pane; inside an editor the deeper `git::ToggleStaged` binding wins |
| `shift-escape` | `workspace::ToggleZoom` | zoom the focused pane or panel to the whole window |
| `ctrl-alt-w` | `workspace::CloseActiveDock` | close the focused dock (was `cmd-w` before 1.22); also unzooms |
| `cmd-shift-e` | `project_panel::ToggleFocus` | project tree (`:E`); also reveals the current file |
| `ctrl-shift-g` / `cmd-shift-d` | git / debug `::ToggleFocus` | other panels (outline: [Pickers](#pickers), terminal: [Terminal](#terminal-tasks-debugger)) |
| `cmd-?` | `agent::ToggleFocus` | agent panel |
| `cmd-\` | `pane::SplitRight` | split; `cmd-k up/down/left/right` for the other directions |
| `cmd-k cmd-<arrow>` | `workspace::ActivatePane<Dir>` | move between panes (`ctrl-w h/j/k/l`) |
| `cmd-1`…`cmd-9` | `workspace::ActivatePane` | jump to pane N |
| `ctrl-1`…`ctrl-9`, `ctrl-0` | `pane::ActivateItem` / `ActivateLastItem` | jump to tab N |
| `cmd-{` / `cmd-}` | `pane::ActivatePreviousItem` / `ActivateNextItem` | cycle tabs |
| `cmd-w` / `cmd-shift-t` | `pane::CloseActiveItem` / `pane::ReopenClosedItem` | close / reopen tab |
| `cmd-k w` / `cmd-k u` / `cmd-alt-t` | `CloseAllItems` / `CloseCleanItems` / `CloseOtherItems` | bulk close |
| `cmd-k shift-enter` | `pane::TogglePinTab` | pin a tab |
| `f6` / `shift-f6` | `workspace::FocusNextPart` / `FocusPreviousPart` | cycle focus between docks and center |
| `ctrl-alt-0` / `ctrl-alt--` / `ctrl-alt-=` | `workspace::ResetActiveDockSize` / `Decrease…` / `Increase…` | resize the focused dock |

**`ToggleFocus` semantics:** every panel's `ToggleFocus` opens and focuses
the panel; pressed again while focused, it returns focus to the editor but
leaves the panel open. `"close_panel_on_toggle": true` makes the second
press close it.

**Panel layouts:** `workspace: use agentic layout` puts agent panel and
threads sidebar left, project/git right; `workspace: use classic layout`
(the default for existing users) restores editor-first docks.

<a id="editing-lsp"></a>
## Editing and LSP

The vim column includes Neovim 0.11's `g r*` set.

| binding | action | vim-mode key |
|---|---|---|
| `f12` / `alt-f12` | `editor::GoToDefinition` / `…Split` | `g d`, `ctrl-]` / `ctrl-w g d` |
| `cmd-f12` / `shift-f12` | `editor::GoToTypeDefinition` / `GoToImplementation` | `g y` / `g shift-i` |
| `alt-shift-f12` | `editor::FindAllReferences` | `g shift-a`, `g r r` |
| `f2` | `editor::Rename` | `c d`, `g r n` |
| `cmd-.` | `editor::ToggleCodeActions` | `g .`, `g r a` |
| `cmd-shift-i` / `alt-shift-o` | `editor::Format` / `OrganizeImports` | — |
| `cmd-k cmd-i` | `editor::Hover` | `shift-k`, `g h` |
| `cmd-i` | `editor::ShowSignatureHelp` | `ctrl-s` (insert) |
| `f8` / `shift-f8` | `editor::GoToDiagnostic` / `…Previous…` | `] d` / `[ d` |
| `cmd-/` | `editor::ToggleComments` | `g c c`, `g c` + motion |
| `cmd-d` / `cmd-k cmd-d` | `editor::SelectNext` (add / skip) | `g l` / `g >` |
| `cmd-shift-l` | `editor::SelectAllMatches` | `g a` |
| `cmd-ctrl-right` / `cmd-ctrl-left` | `editor::SelectLargerSyntaxNode` / `…Smaller…` | `[ x` / `] x` |
| `alt-up` / `alt-down` | `editor::MoveLineUp` / `…Down` | `[ e` / `] e` |
| `alt-shift-up` / `alt-shift-down` | `editor::DuplicateLineUp` / `…Down` | — |
| `ctrl-j` | `editor::JoinLines` | `shift-j` |
| `cmd-k cmd-l` / `cmd-k cmd-0` / `cmd-k cmd-j` | `editor::ToggleFold` / `FoldAll` / `UnfoldAll` | `z a` / `z shift-m` / `z shift-r` |
| `ctrl-:` / `cmd-k z` | `editor::ToggleInlayHints` / `ToggleSoftWrap` | — / `:set wrap` |
| `cmd-k cmd-h` | `call_hierarchy::ShowIncomingCalls` | — |
| `ctrl-space` | `editor::ShowCompletions` (see [Gotchas](#gotchas)) | `ctrl-x ctrl-o` (insert) |

<a id="search-multibuffers"></a>
## Search and multibuffers

| binding | action | what it does |
|---|---|---|
| `cmd-f` / `cmd-e` | `buffer_search::Deploy` / `UseSelectionForFind` | in-file search |
| `cmd-g` / `cmd-shift-g` | `search::SelectNextMatch` / `…Previous…` | step through matches |
| `alt-enter` (search bar) | `search::SelectAllMatches` | cursor on every match |
| `cmd-alt-c` / `cmd-alt-w` / `cmd-alt-x` | `search::ToggleCaseSensitive` / `ToggleWholeWord` / `ToggleRegex` | search options |
| `cmd-shift-f` / `cmd-shift-h` | `pane::DeploySearch` (+ replace) | project search multibuffer (`g /`) / search-and-replace |
| `cmd-shift-j` | `project_search::ToggleFilters` | include/exclude globs |
| `cmd-enter` / `cmd-shift-enter` | `project_search::SearchInNew` / `ToggleAllSearchResults` | query in a fresh tab / expand-collapse all results |
| `escape` | `project_search::ToggleFocus` | query box <-> results |

Project search runs as you type (`search.search_on_type: false` to require
`enter`). The regex engine is Rust's: groups are `(…)`, replacements use
`$1`, and `:%s/\(a\)/\1/` is auto-converted in the palette.

**Inside any multibuffer** (`Editor && multibuffer`) — also the review and
diff buffers:

| binding | action | what it does |
|---|---|---|
| `cmd-up` / `cmd-down` | `editor::MoveToStartOfExcerpt` / `…NextExcerpt` | jump between excerpts |
| `alt-enter` / `cmd-alt-enter` | `editor::OpenExcerpts` / `…Split` | open the real file at the cursor (`g space`) |
| `shift-enter` | `editor::ExpandExcerpts` | show more context around the excerpt |

<a id="git"></a>
## Git

Three surfaces: the **git panel** (`ctrl-shift-g`) for the file list and
commit box, the **project diff** (`ctrl-g d` from the panel, or
`git: diff`) as an editable multibuffer, and **inline hunks** in any editor.

| binding | action | where |
|---|---|---|
| `ctrl-shift-g` | `git_panel::ToggleFocus` | anywhere |
| `ctrl-g d` | `git::Diff` | panel; project diff multibuffer |
| `space` / `cmd-y` / `cmd-shift-y` | `git::ToggleStaged` / `StageFile` / `UnstageFile` | panel list (`x`) |
| `cmd-ctrl-y` / `cmd-ctrl-shift-y` | `git::StageAll` / `UnstageAll` | panel, project diff |
| `cmd-y` / `cmd-shift-y` | `git::StageAndNext` / `UnstageAndNext` | project diff, editor hunks (`d u` / `d shift-u`) |
| `cmd-alt-y` / `cmd-alt-z` | `git::ToggleStaged` / `Restore` | editor hunk: stage toggle (`d shift-o`) / revert (`d p`) |
| `cmd-f8` / `cmd-shift-f8` | `editor::GoToHunk` / `…Previous…` | editor (`] c` / `[ c`) |
| `cmd-'` / `cmd-"` | `editor::ToggleSelectedDiffHunks` / `ExpandAllDiffHunks` | show old text inline (`d o`); `escape` collapses |
| `cmd-alt-g b` / `cmd-k cmd-b` | `git::Blame` / `editor::BlameHover` | blame column / current line (`g shift-b`) |
| `cmd-alt-g r` / `cmd-alt-g m` | `git::ReviewDiff` / `OpenModifiedFiles` | branch review / open every changed file |
| `tab` | `git_panel::FocusEditor` / `FocusChanges` | list <-> commit box (`i`) |
| `cmd-enter` / `cmd-shift-enter` | `git::Commit` / `git::Amend` | commit box |
| `alt-tab` | `git::GenerateCommitMessage` | AI message (`agent.commit_message_model`) |
| `shift-escape` | `git::ExpandCommitEditor` | full-size commit editor |
| `ctrl-g ctrl-g` / `ctrl-g up` / `ctrl-g down` | `git::Fetch` / `Push` / `Pull` | panel; `shift-up`/`shift-down` for force-push / pull-rebase |

**Split vs unified:** project/branch diffs are side-by-side by default since
0.224; `editor: toggle split diff` (`editor::ToggleSplitDiff`) flips a view,
`"diff_view_style": "unified"` changes the default. Inline editor hunks are
always unified. Unbound but useful: `git::Switch` (branch picker, also
deletes branches), `git::StashAll`/`StashPop`, `editor::ToggleGitBlameInline`.

<a id="terminal-tasks-debugger"></a>
## Terminal, tasks, debugger

| binding | action | what it does |
|---|---|---|
| `` ctrl-` `` / `ctrl-~` | `terminal_panel::Toggle` / `workspace::NewTerminal` | terminal dock / new terminal tab in it |
| `cmd-n` / `cmd-d` | `workspace::NewTerminal` / `pane::SplitRight` | in the panel: new tab / split |
| `ctrl-shift-space` | `terminal::ToggleViMode` | vi-style scrollback selection |
| `cmd-k` / `cmd-f` | `terminal::Clear` / `buffer_search::Deploy` | clear / search |
| `cmd-shift-r` / `cmd-alt-r` | `task::Spawn` / `task::Rerun` | task picker / rerun last |
| `f4` | `debugger::Start` | new session picker (auto-detects tests, `main`) |
| `f5` / `f10` / `f11` / `shift-f11` | `debugger::Continue` / `StepOver` / `StepInto` / `StepOut` | while stopped |
| `f9` / `shift-f9` | `editor::ToggleBreakpoint` / `EditLogBreakpoint` | breakpoints |

Forward keys the shell needs (`ctrl-n`, `alt-b`) with
`["terminal::SendKeystroke", "ctrl-n"]` in a `Terminal` context. Tasks live
in `~/.config/zed/tasks.json` or `.zed/tasks.json` and can be bound:
`["task::Spawn", { "task_name": "start lazygit", "reveal_target": "center" }]`.

<a id="agent-panel"></a>
## Agent panel

A dock panel (right dock in classic layout, left in agentic), so the
[dock keys](#panes-docks) apply.

| binding | action | what it does |
|---|---|---|
| `cmd-?` | `agent::ToggleFocus` | open + focus; again returns focus to the editor (panel stays) |
| `cmd-n` | `agent::NewThread` | new Zed Agent thread (panel focused) |
| `cmd-alt-shift-n` | `agent::ToggleNewThreadMenu` | the `+` menu: Zed Agent, each installed external agent, New From Summary, Terminal |
| `ctrl-tab` / `ctrl-shift-tab` | `agents_sidebar::ToggleThreadSwitcher` | MRU thread switcher, like the tab switcher |
| `cmd-alt-c` / `cmd-alt-m` | `agent::OpenSettings` / `ToggleOptionsMenu` | AI settings page / the `…` menu |

**Full-screen a thread and come back:** `cmd-?` then `shift-escape` to
zoom. To return: `shift-escape` then `cmd-?`, or `ctrl-alt-w` to close the
dock (also unzooms). `cmd-r` (`cmd-b` in agentic layout) hides the dock
without moving focus.

**External agents** (Claude, Codex, Cursor, pi, Gemini, Copilot CLI — the
`agent_servers` entries in `settings.json`) install from `zed: acp registry`;
omp isn't in the registry, so it's a `custom` entry running `omp acp
--approval-mode yolo --config ~/.omp/agent/zed-models.yml`. All of them
appear in the `+` menu and sidebar like any thread. They bring
their own auth (`/login` in a Claude thread) and instructions (`CLAUDE.md`,
not Zed's `AGENTS.md`) and ignore Zed profiles. **Terminal Threads** (`+`
menu > Terminal) are a plain terminal tracked as a thread — run `claude`/
`pi`/`codex` there for the CLI itself (sidekick-in-nvim). They do not resume
after a Zed restart ([details](#terminal-thread-restore)). One-key launches:
see [Adding your own bindings](#custom-bindings).

**omp's model dropdown** is omp's own ACP `model` select, not Zed's model
selector: `agent.favorite_models` and `alt-tab` don't reach it, and omp's
`Ctrl+P` cycle and `Alt+O` preset picker are TUI-only. Unscoped it lists the
whole catalog (~870), so the `--config` file (`~/.omp/agent/zed-models.yml`,
written by `omp/setup-zed-models.sh` via `setup-settings.sh`) enables one
name pattern per model behind omp's chat roles (`*/*claude-opus-5[.-]5`).
Each then appears once per logged-in source — OpenRouter, Anthropic OAuth,
ChatGPT (OpenAI Codex) — with subscription entries suffixed ` (sub)`
(`omp/setup-model-labels.sh`); Bedrock's regional copies are disabled. The
list is alphabetical, not cycle order, and picking a model leaves the
separate Thinking select unchanged. Per-preset agent entries (start on Opus
at `high` in one click) are parked in
[`plans/zed-omp-preset-agents.md`](../plans/zed-omp-preset-agents.md).

**ACP thread or Terminal Thread?** Same brain, different cockpit: an ACP
thread runs the agent's own core (Codex's `codex-core`, Claude's Agent SDK)
with Zed as the UI; a Terminal Thread runs the full CLI with its own TUI.
What each side gives you:

- **ACP gets Zed's integration.** Every key in [Inside a thread](#inside-thread)
  and [Reviewing agent edits](#review) applies: keep/reject per hunk in the
  review multibuffer (`ctrl-shift-r`, `cmd-y`/`cmd-alt-z`), follow the agent
  through files (`cmd-enter`), `@file`/`@symbol`/`@diagnostics` from Zed's
  own index, `cmd->` to quote a selection, image paste, a searchable
  transcript (`cmd-f`, `shift-pageup`), plan and tool cards, permission
  cards with "Always for <tool>/<pattern>", desktop notifications when the
  agent is waiting, Zed's MCP servers forwarded, thread history/archive —
  and one set of keys for every agent, Zed Agent included.
- **Terminal gets the whole CLI.** Slash commands, hooks, status line,
  plugins, skills, the CLI's current version, and your own config for it
  (this repo's `claude/` hooks and skills, pi's extensions) all run; over
  ACP only what the adapter forwards exists, and the adapter can lag the
  CLI. Auth is the CLI's — Zed's Terminal Threads post (May 2026) says this
  is the only way to use Claude Code on a Claude *subscription* in Zed;
  Codex's native login works either way. In exchange the thread is a
  terminal: scrollback instead of a transcript, no review loop (use
  `git::Diff`), no waiting/done signals in the sidebar.
- **Both** sit in the Threads Sidebar, can be renamed, cycled, and are
  bound by the same `agent_servers` registry entries.
- **Restore after a Zed restart differs.** ACP threads go to Thread History
  and can be reopened, subject to the adapter's session support (open bugs
  zed#54750, #58887: external ACP threads loading empty or losing their
  `session_id`; not checked against `omp acp`). A Terminal Thread comes back
  as an empty shell, not as the agent session. See
  [Terminal Threads after a restart](#terminal-thread-restore).

<a id="terminal-thread-restore"></a>
### Terminal Threads after a restart

**What happens.** When the project reopens, Zed recreates each open Terminal
Thread's sidebar entry with a fresh shell. The agent process, scrollback,
and any half-typed prompt are gone. Zed 1.28.1 stores only a title, custom
title, creation time, working directory, and project/worktree paths per
thread (`sidebar_terminal_threads` in
`~/Library/Application Support/Zed/db/0-stable/db.sqlite`), so it has no
command or session id to resume from. The agent's conversation itself is
safe: each CLI keeps its sessions on disk, and you resume from the shell.

**Known quirks:**

- A thread closed with its **×** is deleted, not archived. Nothing in Thread
  History brings it back; open a new Terminal Thread and resume from there.
- Some users report the recreated shell starting in `/` instead of the
  project directory. A thread with no stored working directory would explain
  that [INFERENCE]; not seen here.
- The sidebar title is the shell's, not the session's. Rename threads
  (`shift-r` in the sidebar) before a restart if you want to tell them apart
  afterwards.

#### Resume by hand

Per thread, in this order:

1. Select the restored entry in the Threads Sidebar, or open a new Terminal
   Thread (`+` menu > Terminal) if you closed it.
2. Run `pwd`. If it is not the project root, `cd` there; sessions are looked
   up by directory, so the wrong directory finds nothing.
3. Run the resume command for the CLI you were using:

   | CLI | latest session here | pick from a list | exact session |
   |---|---|---|---|
   | omp | `omp -c` | `omp -r` | `omp -r <id-prefix>` |
   | claude | `claude -c` | `claude -r` | `claude -r <session-id>` |
   | pi | `pi -c` | `pi -r` | `pi --session <path\|id>` |

   Flags are from each CLI's `--help`. `claude -c` is documented as the most
   recent conversation *in the current directory*; omp stores sessions in
   per-directory folders under `~/.omp/agent/sessions/`; pi's scoping is
   unchecked.
4. omp after a crash or an update that interrupted a running turn:
   `omp --restore` resumes like `-r`, then continues the unfinished turn and
   its subagents.

**Several threads in one project:** `-c` gives every thread the *same*
latest session. Use the picker (`-r`) instead and choose a different session
in each thread. Zed does not record which thread had which session, so the
picker's titles and timestamps are the only clue. That missing mapping is
what `ZED_TERMINAL_THREAD_ID` (below) would supply.

#### Automating it

Nothing here is adopted; `settings.json` sets none of these, and none was
tried in a running Zed. Options, easiest first:

- **`agent.terminal_init_command`** (shipped). Zed types the command into
  every new *and* recreated Terminal Thread, e.g. `"omp -c"`. Fine with one
  thread per project; with several, they all resume the same session. It also
  fires for threads you wanted as plain shells.
- **`ZED_TERMINAL_THREAD_ID` plus a hook and wrapper** (unmerged
  [PR #65484](https://github.com/zed-industries/zed/pull/65484); needs a
  custom Zed build). The CLI records its session id keyed by that variable,
  and a wrapper resumes it. One user's Claude version: a `SessionStart` hook
  writes `.session_id` from the hook's stdin JSON to
  `$XDG_STATE_HOME/claude-zed-threads/$ZED_TERMINAL_THREAD_ID`, and a
  `claude-zed` wrapper runs `claude --resume <id>` when that file exists. The
  PR description has a Codex wrapper. This is the only per-thread approach
  reported working.
- **A persistent shell underneath** (tmux, zellij, or
  [zmx](../plans/zmx-session-persistence.md)): the CLI keeps running when
  Zed quits and a restored thread reattaches
  ([zed#25227](https://github.com/zed-industries/zed/discussions/25227)).
  With no thread id the session name could only come from the cwd, so
  threads in one project would share a session [INFERENCE: via
  `terminal_init_command`]. A reboot still ends it. tmux is installed here;
  zmx is not.
- **Not available:** a setting that maps thread to session.
  [PR #58693](https://github.com/zed-industries/zed/pull/58693) proposed
  `terminal_command: "claude --session-id {session_id}"` plus a matching
  `terminal_resume_command`. Zed closed it (Jun 15) because they want to
  design it themselves across shells and OSes. It would not fit omp anyway:
  `omp --help` has no flag to choose a session id, unlike
  `claude --session-id <uuid>`.

#### Patches and Zed's plans

**Is Zed working on it?** Acknowledged and planned, with no design, date or
assignee. Evidence:

- A Zed maintainer (macraig) on
  [zed#57428](https://github.com/zed-industries/zed/discussions/57428), May
  25: "This is already on our ToDo list. We just need a bit of time to figure
  out the best way to implement it in terminals."
- A Zed maintainer (anantdgoel) closing PR #58693, Jun 15: "we'll make sure
  this capability lands", pointing at issue #58697. That issue is closed and
  is only the *default command* request, which shipped as
  `agent.terminal_init_command`; it is not a resume tracker.
- A Zed reviewer (smitbarmase) on PR #65484, Oct 12: restoring is "on our
  list (#57428), but we haven't settled on how yet, so it might be a while";
  he asked users to try the PR and report back.
- Still open as of the last comments I read (Oct 2026). No linked Zed issue,
  milestone, or release note for resume exists that I found.

**Patch options**, none merged into Zed 1.28.1:

- **[PR #65484](https://github.com/zed-industries/zed/pull/65484)** (open,
  Oct 2026) adds `ZED_TERMINAL_THREAD_ID` to the Terminal Thread shell
  environment; you supply the hook and wrapper. Cost: you build Zed from the
  PR branch (the author used Zed's `script/bundle-*` scripts; not checked
  here) and give up the stable release and its auto-updates. Several users
  report it working on macOS and Linux; one reported a startup crash that
  turned out to be a security agent killing the debug build.
- **No patch, just a request:**
  [discussion #60306](https://github.com/zed-industries/zed/discussions/60306)
  asks for the same per-terminal id as an env var or as `{terminal_id}` in
  `terminal_init_command`. Nothing to install; add a +1 there if you want it.
- **Writing rows into `sidebar_terminal_threads` yourself.** One user's tmux
  bridge ([#57428](https://github.com/zed-industries/zed/discussions/57428),
  Jul 15) registers sessions as threads so a restored thread reattaches. It
  writes Zed's private SQLite, Zed sees new rows only after a reload, and its
  author says it should not become the contract. Not recommended.

**Practical choice today:** resume by hand, or `terminal_init_command` if you
keep one thread per project. If per-thread resume matters enough, the PR
#65484 build plus a wrapper is the only per-thread route reported working.
Its examples cover Claude and Codex, so an omp hook and wrapper would be
yours to write. Watch #57428 and PR #65484 to learn when stock Zed gets it.

Rule of thumb: ACP for Zed Agent and Codex when the in-editor review loop
is the point; Terminal Threads for a harness you have customised (Claude,
pi). Zed profiles, Skills, and `AGENTS.md` apply to neither — external
agents read their own instruction files.

<a id="threads-sidebar"></a>
## Threads sidebar

Every thread across open projects, grouped by project. Settings:
`agent.threads_sidebar.position`, `.default_width` (222 here), `.auto_open`.

| binding | action | what it does |
|---|---|---|
| `cmd-alt-j` / `cmd-alt-;` | `multi_workspace::ToggleWorkspaceSidebar` / `FocusWorkspaceSidebar` | show-collapse (anywhere) / focus without toggling |
| `up` / `down` (`ctrl-p` / `ctrl-n`) | `menu::SelectPrevious` / `SelectNext` | move through threads |
| `left` / `right` | `menu::SelectParent` / `SelectChild` | collapse / expand a project group |
| `enter` / `space` | `menu::Confirm` | switch to the thread |
| `cmd-f` | `agents_sidebar::FocusSidebarFilter` | fuzzy-filter thread titles |
| `cmd-n` | `agents_sidebar::NewThreadInGroup` | new thread in the selected project |
| `shift-r` | `agent::RenameSelectedThread` | rename |
| `shift-backspace` / `cmd-shift-backspace` | `agent::ArchiveSelectedThread` / `RemoveSelectedThread` | archive to history (running threads must finish first) / delete |
| `cmd-g` | `agents_sidebar::ToggleThreadHistory` | all threads, all projects, chronological; `backspace` un-archives, hover-trash deletes |

Mouse-free loop: `cmd-alt-;`, `down`/`up`, `enter`, read, `cmd-alt-;`
again — or skip the sidebar and `ctrl-tab` from inside a thread. To
**cycle threads directly** there is no default key, but the actions exist:
`multi_workspace::NextThread` / `PreviousThread` (and `NextProject` /
`PreviousProject`) — bind them, e.g. `alt-]` / `alt-[`, which is what
[`docs/zed-vim-keymap.md`](zed-vim-keymap.md#ai) proposes.

<a id="inside-thread"></a>
## Inside a thread

Contexts: `AcpThread` (the transcript) and `AcpThread > Editor` (the
message box). Most keys work from both.

| binding | action | what it does |
|---|---|---|
| `enter` / `cmd-enter` | `agent::Chat` / `ChatWithFollow` | send / send and follow the agent through files |
| `cmd-shift-enter` | `agent::SendImmediately` | interrupt generation and send now |
| `cmd-alt-shift-enter` | `agent::SendNextQueuedMessage` | send next queued message (see below) |
| `cmd-ctrl-s` | `agent::ToggleSteerFirstQueuedMessage` | steer = inject at the next step (Zed Agent only) |
| `alt-shift-escape` | `agent::ExpandMessageEditor` | full-height message box |
| `shift-pageup` / `shift-pagedown` | `agent::ScrollOutputToPreviousMessage` / `…Next…` | jump between messages (`ctrl-alt-pageup/pagedown` from the box) |
| `pageup` / `pagedown`, `home` / `end` | `agent::ScrollOutputPage…` / `…ToTop` / `…ToBottom` | scroll the transcript (`ctrl-` variants from the box) |
| `cmd-f` / `cmd-g` / `cmd-shift-g` | `agent::ToggleSearch` / `SelectNextThreadMatch` / `…Previous…` | search the thread; `escape` dismisses |
| `ctrl-;` / `@` | `agent::OpenAddContextMenu` | attach files, dirs, symbols, threads, diagnostics, URLs |
| `cmd->` | `agent::AddSelectionToThread` | from any editor or terminal: quote the selection |
| `cmd-shift-v` | `agent::PasteRaw` | paste without the auto `@`-mention wrapping |
| `cmd-i` / `shift-tab` | `agent::ToggleProfileSelector` / `CycleModeSelector` | Write / Ask / Minimal profile; ACP session mode |
| `cmd-alt-/` / `alt-tab` | `agent::ToggleModelSelector` / `CycleFavoriteModels` | model picker / cycle `agent.favorite_models` |
| `cmd-alt-k` / `ctrl-'` / `cmd-alt-.` | `agent::ToggleThinkingMode` / `CycleThinkingEffort` / `ToggleFastMode` | per-model knobs |
| `cmd-y` / `cmd-alt-y` / `cmd-alt-z` | `agent::AllowOnce` / `AllowAlways` / `RejectOnce` | tool-permission prompt (`cmd-alt-a`: granularity) |
| `cmd-alt-p` / `cmd-alt-l` | `agent::ManageProfiles` / `ManageSkills` | profile and skills modals |
| `ctrl--` | `pane::GoBack` | back to the previous thread view |
| `/compact` | — | manual context compaction |

Queued messages: `cmd-ctrl-e` edits, `cmd-shift-backspace` drops,
`cmd-alt-backspace` clears. No key collapses a message or tool card — click
its header. Stop is the button next to send.

**Stop approving every command** — the stowed `settings.json` mirrors omp's
`yolo` across all three layers that can prompt:

- **Zed Agent tools** — `agent.tool_permissions` (replaced the old
  `always_allow_tool_actions` boolean). `default: "allow"` auto-approves;
  `always_deny` blocks silently (edits to `.env`, `*.pem`, `*.key`). Avoid
  `always_confirm` and per-tool `"default": "confirm"` — each is a prompt.
  Zed's hardcoded `rm -rf` guards (`/`, `~`, `$HOME`, `.`, `..`) always block.
- **Zed Agent sandbox** — `terminal` and `fetch` run in an OS sandbox that
  prompts for network hosts and writes outside the project. `.git` metadata
  is never writable inside it, so any narrower grant still prompts on every
  `git commit`; `sandbox_permissions.allow_unsandboxed: true` turns it off,
  matching omp, which has no sandbox.
- **External agents** keep their own permission model; Zed's settings above
  don't reach them. omp's `acp` mode asks before every bash call unless yolo
  is set explicitly (the built-in default doesn't count), hence
  `"args": ["acp", "--approval-mode", "yolo"]`. Claude starts in
  `default_mode: "bypassPermissions"`; `shift-tab`
  (`agent::CycleModeSelector`) cycles modes per thread.

```jsonc
"agent": {
  "sandbox_permissions": { "allow_unsandboxed": true },
  "tool_permissions": {
    "default": "allow",
    "tools": {
      "edit_file": { "always_deny": [{ "pattern": "\\.env" }, { "pattern": "\\.(pem|key)$" }] }
    }
  }
},
"agent_servers": {
  "claude-acp": { "type": "registry", "default_mode": "bypassPermissions" },
  "omp": { "type": "custom", "command": "/opt/homebrew/bin/omp", "args": ["acp", "--approval-mode", "yolo", "--config", "~/.omp/agent/zed-models.yml"] }
}
```

A permission card's "Always for <tool>/<pattern>" menu still writes rules
into `settings.json` if a prompt ever appears.

<a id="review"></a>
## Reviewing agent edits

The review buffer is a multibuffer, so the [multibuffer keys](#search-multibuffers)
(`alt-enter` to open the real file) apply.

| binding | action | what it does |
|---|---|---|
| `ctrl-shift-r` | `agent::OpenAgentDiff` | "Review Changes" multibuffer of every edit in the thread |
| `ctrl-shift-d` | `git::Diff` | the ordinary project diff, from inside a thread |
| `cmd-y` / `cmd-alt-z` | `agent::Keep` / `agent::Reject` | per hunk, in the review buffer or an inline agent diff |
| `alt-shift-y` / `alt-shift-z` | `agent::KeepAll` / `agent::RejectAll` | whole thread (also from the message box) |
| `alt-shift-u` | `agent::UndoLastReject` | bring back the last rejected hunk |

`"agent.single_file_review": true` shows agent hunks inline in each file
with the same keys. Checkpoints were removed in 1.27 — reject or git is the
undo path.

<a id="inline-prediction"></a>
## Inline assistant and edit prediction

- **Inline assist:** `ctrl-enter` (`assistant::InlineAssist`) in any editor
  or terminal; `ctrl-x ctrl-a` from vim insert mode. Transforms the
  selection (or current line) in place, multi-cursor aware. `ctrl-[`/`ctrl-]`
  cycle alternatives when `agent.inline_alternatives` lists extra models.
  Prefill a prompt from a binding:
  `["assistant::InlineAssist", { "prompt": "Add a doc comment" }]`.
- **Edit prediction** (`edit_predictions.provider`: `zed`, `copilot`, …,
  `none`): `tab` or `alt-tab` accepts (`editor::AcceptEditPrediction`),
  `cmd-ctrl-right` / `cmd-ctrl-down` accept a word / line, `escape`
  dismisses, `cmd-ctrl-e` toggles. `"edit_predictions": { "mode": "subtle" }`
  hides them until you hold `alt`. Rebinding context:
  `Editor && edit_prediction`.

<a id="vim-mode"></a>
## Vim mode

`"vim_mode": true` (or `workspace: toggle vim mode`); this repo ships it
off with the `vim` block ready (`use_system_clipboard: "on_yank"` matches
nvim). Motions, operators, text objects, registers, marks, macros, `.`, and
`:` ranges work; `%` and `w` are Tree-sitter-tuned. LSP, search, hunk, and
pane vim keys sit beside their bindings above; the remaining Zed-specific
maps:

| keys | does |
|---|---|
| `g s` / `g shift-s` | outline / project symbols |
| `] m` `[ m`, `] ]` `[ [` | methods, sections |
| `y s`, `c s`, `d s`, `c x` | surround add/change/delete, exchange |
| `ctrl-w v`, `s`, `q`, `o` | split, close, close others |
| `shift-z shift-z` / `shift-z shift-q` | save and close tab / close without saving |
| `:E`, `:G`, `:A`, `:te`, `:cl`, `:D` | project panel, git, agent, terminal, diagnostics, debug |

**Differences from nvim:** `:` commands take no file arguments (`:e foo`
does not exist — use `cmd-p`); `s`/`shift-s` are substitute unless you bind
sneak; visual-block edits are multi-cursor; the regex dialect is Rust's.

The full vim-mode story — in-file and cross-file navigation, tabs, the
`ctrl-w` layer, panel keys, text objects, `:` commands, opt-ins — is the
companion [`docs/zed-vim.md`](zed-vim.md).

<a id="custom-bindings"></a>
## Adding your own bindings

`~/.config/zed/keymap.json` (stowed from `zed/`) is an array of
`{ "context", "bindings" }` blocks. Open it with `cmd-k cmd-s`
(`zed::OpenKeymap`, a GUI editor that writes back to the file) or
`zed: open keymap file`; the defaults with `zed: open default keymap`.

```jsonc
[
  { "bindings": { "cmd-k cmd-r": "git::ReviewDiff" } },          // global
  {
    "context": "Editor && vim_mode == normal && !menu",          // scoped
    "bindings": {
      "space a a": "agent::ToggleFocus",                        // chord
      "space a z": "workspace::ToggleZoom",
      "space a t": "multi_workspace::ToggleWorkspaceSidebar",
      "space a n": "agent::NewThread",
      "space a r": "agent::OpenAgentDiff",
      "shift-y": ["workspace::SendKeystrokes", "y $"],          // macro
      "space f g": ["pane::DeploySearch", { "replace_enabled": false }], // args
      "cmd-r": null                                              // unbind
    }
  },
  { "context": "Dock", "bindings": { "ctrl-w l": "workspace::ActivatePaneRight" } }
]
```

- **Finding the action name.** Palette entry `agent: toggle focus` is
  `agent::ToggleFocus` (module `::` PascalCase). The palette's bottom-left
  `Add Keybinding` button opens the keymap editor pre-filled; autocomplete
  in keymap.json also knows every action.
- **Key notation.** Modifiers `cmd-`, `ctrl-`, `alt-`, `shift-`, `fn-`,
  joined with `-`; `shift-` only with letters (`shift-g`, never `shift-(`).
  Chords are space-separated (`"space a a"`, `"cmd-k cmd-s"`) and wait 1 s;
  `alt-/` lists what can complete one, and
  `"which_key": { "enabled": true }` shows a which-key.nvim-style popup.
- **Contexts.** `Editor`, `Workspace`, `Pane`, `Dock`, `Terminal`,
  `ProjectPanel`, `GitPanel`, `AgentPanel`, `AcpThread`, `ThreadsSidebar`,
  `OutlinePanel`, `BufferSearchBar`, `menu`, plus attributes like
  `vim_mode == normal`, `multibuffer`, `mode == full`, `renaming`,
  `showing_completions`. Combine with `&&`, `||`, `!`, parentheses, and
  `>` for "descendant of" (`AcpThread > Editor` is the message box). Deeper
  nodes win. `dev: open key context view` shows the live context — use it
  when a binding does not fire.
- **Arguments.** `["action", arg]` — a bare value
  (`["workspace::ActivatePane", 0]`) or an object
  (`["task::Spawn", { "task_name": "…" }]`).
- **Macros.** `["workspace::SendKeystrokes", "escape g g"]` replays up to 100
  keys through normal dispatch, so it can chain existing bindings.
- **Unbinding.** `null`, following precedence: `"cmd-r": null` in `Editor`
  blocks the `Workspace` default too.
- **Vim leader.** In `VimControl` contexts `space` is `vim::WrappingRight`;
  any `space …` chord in `vim_mode == normal` shadows it — the trick behind
  the leader block proposed in [`docs/zed-vim-keymap.md`](zed-vim-keymap.md).
  Add `!menu` so completions and pickers keep their keys.
- **One-key agent launches.** `agent::NewExternalAgentThread` takes the
  agent to start; `agent::NewTerminalThread` opens a Terminal Thread. The
  argument shape was not verified against 1.28.1 — bind it through
  `Add Keybinding`, which fills in the accepted form, and check
  `dev: open acp logs` if a bound agent fails to start.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **Zed rewrites `settings.json`** through the stow symlink whenever you
  change a setting in its UI — run `git diff zed/` afterwards. The keymap
  editor does the same to `keymap.json`.
- **Terminal Threads restart as empty shells.** The sidebar entry returns,
  the agent session does not: resume with `omp -c` / `omp -r` (or the CLI's
  equivalent) from the right directory. Zed has planned per-thread resume
  but has no design or date
  ([details and patch options](#terminal-thread-restore)).
- **Closing a Terminal Thread with its `×` deletes it**; unlike an ACP
  thread it never reaches Thread History.
- **Closing docks:** `cmd-w` closes the tab, not the dock (1.22+) — use
  `ctrl-alt-w`. `cmd-?` toggles focus, not visibility; hide with
  `cmd-r`/`cmd-b` or set `close_panel_on_toggle`.
- **Overloaded keys:** `shift-escape` zooms, but expands the git commit
  editor in the commit box. `alt-tab` accepts edit prediction (editor), cycles
  favorite models (thread), generates a commit message (git panel). `cmd-y`
  is stage-and-next (editor), keep-hunk (agent review), allow-once
  (permission prompt). `cmd-alt-y` is toggle-all-docks, but toggle-staged
  on an editor hunk and allow-always in a thread.
- **`ctrl-space` needs the macOS input-source shortcut disabled** (System
  Settings > Keyboard > Shortcuts > Input Sources) or completions never open.
- **`cmd-ctrl-d` opens the macOS dictionary** instead of
  `editor::SelectPrevious`; the default keymap's comment carries a
  `defaults write` fix.
- **`vim_mode` contexts only exist on `Editor`:** a binding scoped
  `Workspace && vim_mode == normal` is silently dead.
- **Text threads and the Rules Library are gone** (replaced by Skills and
  `~/.config/zed/AGENTS.md`); old docs and blog posts still mention them.
