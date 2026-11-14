# Zed — shortcuts, workflows, and keymaps

How to drive [Zed](https://zed.dev) from the keyboard: the default macOS
bindings that matter, the workflows behind them (agent threads, review,
git, search), and how to add your own bindings. Install/stow steps live in
README's `## Zed` section; nvim's own keymaps live in
`nvim/.config/nvim/GUIDE.md`. Everything here was checked against the
`v1.28.1` default keymap (the installed version) and the docs below.
Comparisons to the nvim config are deliberately brief — Zed is not a vim
clone and the point is to learn its native keys first.

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
Zed's own notation (`cmd-shift-p`, `ctrl-g d` for a two-key chord).

## Contents

- [The mental model](#mental-model)
- [Pickers and navigation](#pickers)
- [Panes, tabs, and docks](#panes-docks)
- [Editing and LSP](#editing-lsp)
- [Search and multibuffers](#search-multibuffers)
- [Git](#git)
- [Agent panel](#agent-panel)
- [Threads sidebar](#threads-sidebar)
- [Inside a thread](#inside-thread)
- [Reviewing agent edits](#review)
- [Inline assistant and edit prediction](#inline-prediction)
- [Terminal, tasks, debugger](#terminal-tasks-debugger)
- [Vim mode](#vim-mode)
- [Adding your own bindings](#custom-bindings)
- [Gotchas cheat-sheet](#gotchas)

---

<a id="mental-model"></a>
## The mental model

1. **Everything is an action.** A key maps to an action like
   `agent::ToggleFocus`. The command palette (`cmd-shift-p`) lists every
   action as `agent: toggle focus` and shows its binding — that is how you
   discover names for keymap.json. Vim's `:` opens the same palette.
2. **The window is a tree: Workspace > Docks and Panes > Editors/Panels.**
   Three docks (left, bottom, right) host panels (project, outline, git,
   terminal, agent, debug). The center holds panes of tabs. Bindings are
   scoped to a node in this tree via `context`, so the same key can mean
   different things in the editor, the git panel, and an agent thread.
3. **Multibuffers are Zed's quickfix list — but editable.** Project search,
   diagnostics, references, project diff, and agent review all open one
   scrollable buffer stitched from excerpts of many files. You edit in it
   directly and `cmd-s` saves everything.
4. **The agent panel is a dock panel with its own thread list.** Threads
   (Zed Agent, external ACP agents, Terminal Threads) all live in the
   Threads Sidebar, grouped by project. Focus, zoom, and close are the
   generic dock operations, not agent-specific ones.
5. **Your keymap.json loads after the defaults**, so a later definition in
   the same context wins. Binding `null` unbinds.

**Coming from the nvim config:** `cmd-p` is `<leader>ff`, `cmd-shift-f` is
`<leader>fg`, `cmd-shift-e` is `<leader>e`, `cmd-.` is `<leader>ca`, and
`cmd-?` is roughly `<leader>aa` (sidekick). The commented-out block in
`zed/.config/zed/keymap.json` wires those leader keys up for when vim mode
is on — see [Adding your own bindings](#custom-bindings).

<a id="pickers"></a>
## Pickers and navigation

| binding | action | what it does |
|---|---|---|
| `cmd-shift-p` | `command_palette::Toggle` | every action, with its binding; sorted by recency |
| `cmd-p` | `file_finder::Toggle` | fuzzy file finder; pre-fills from the selection (`file_finder.prefill_query_from_selection`) |
| `cmd-t` | `project_symbols::Toggle` | workspace symbols |
| `cmd-shift-o` | `outline::Toggle` | symbols in the current file (modal) |
| `cmd-shift-b` | `outline_panel::ToggleFocus` | outline as a panel; doubles as a tree view of search results |
| `ctrl-tab` / `ctrl-shift-tab` | `tab_switcher::Toggle` | MRU tab switcher with file preview |
| `cmd-alt-o` | `projects::OpenRecent` | recent projects |
| `cmd-ctrl-b` / `cmd-ctrl-w` | `branches::OpenRecent` / `git::Worktree` | branch and worktree pickers |
| `ctrl-g` | `go_to_line::Toggle` | go to line |
| `ctrl--` / `ctrl-_` | `pane::GoBack` / `pane::GoForward` | jump list (`ctrl-o`/`ctrl-i` in vim mode) |
| `cmd-k cmd-p` | `workspace::ReopenLastPicker` | reopen the last picker |
| `cmd-shift-m` | `diagnostics::Deploy` | all project diagnostics as a multibuffer |

Inside any picker (`menu` context): `enter` confirms, `cmd-enter` is the
secondary confirm (open in split), `escape`/`ctrl-c` cancels, `ctrl-n`/`ctrl-p`
or arrows move. In the file finder, `cmd-shift-i` toggles ignored files.

There is no Telescope-style plugin ecosystem: the pickers are fixed, and
live-grep is the project search multibuffer rather than a preview picker.

<a id="panes-docks"></a>
## Panes, tabs, and docks

| binding | action | what it does |
|---|---|---|
| `cmd-b` / `cmd-r` / `cmd-j` | `workspace::ToggleLeftDock` / `ToggleRightDock` / `ToggleBottomDock` | show/hide a dock |
| `cmd-alt-y` | `workspace::ToggleAllDocks` | hide/show every dock |
| `shift-escape` | `workspace::ToggleZoom` | zoom the focused pane or panel to the whole window |
| `ctrl-alt-w` | `workspace::CloseActiveDock` | close the dock that has focus (was `cmd-w` before 1.22) |
| `cmd-shift-e` | `project_panel::ToggleFocus` | project tree (`:E` in vim mode); also reveals the current file |
| `cmd-shift-b` / `ctrl-shift-g` / `cmd-shift-d` | outline / git / debug `::ToggleFocus` | other panels |
| `` ctrl-` `` / `ctrl-~` | `terminal_panel::Toggle` / `workspace::NewTerminal` | terminal dock / new terminal in it |
| `cmd-?` | `agent::ToggleFocus` | agent panel |
| `cmd-\` | `pane::SplitRight` | split; `cmd-k up/down/left/right` for the other directions |
| `cmd-k cmd-<arrow>` | `workspace::ActivatePane<Dir>` | move between panes (`ctrl-w h/j/k/l` in vim mode) |
| `cmd-1`…`cmd-9` | `workspace::ActivatePane` | jump to pane N |
| `ctrl-1`…`ctrl-9`, `ctrl-0` | `pane::ActivateItem` / `ActivateLastItem` | jump to tab N |
| `cmd-{` / `cmd-}` | `pane::ActivatePreviousItem` / `ActivateNextItem` | cycle tabs |
| `cmd-w` / `cmd-shift-t` | `pane::CloseActiveItem` / `pane::ReopenClosedItem` | close / reopen tab |
| `cmd-k w` / `cmd-k u` / `cmd-alt-t` | `CloseAllItems` / `CloseCleanItems` / `CloseOtherItems` | bulk close |
| `cmd-k shift-enter` | `pane::TogglePinTab` | pin a tab |
| `f6` / `shift-f6` | `workspace::FocusNextPart` / `FocusPreviousPart` | cycle focus between docks and center |
| `ctrl-alt-0` / `ctrl-alt--` / `ctrl-alt-=` | `workspace::ResetActiveDockSize` / `Decrease…` / `Increase…` | resize the focused dock |

**`ToggleFocus` semantics:** every panel's `ToggleFocus` opens the panel and
focuses it; pressed again with the panel focused it returns focus to the
editor but leaves the panel open. Set `"close_panel_on_toggle": true` to make
the second press close it instead.

**Panel layouts:** `workspace: use agentic layout` puts the agent panel and
threads sidebar on the left and project/git on the right;
`workspace: use classic layout` restores editor-first docks. Existing users
keep classic until they opt in.

<a id="editing-lsp"></a>
## Editing and LSP

| binding | action | vim-mode key |
|---|---|---|
| `f12` / `alt-f12` | `editor::GoToDefinition` / `…Split` | `g d`, `ctrl-]` / `ctrl-w g d` |
| `cmd-f12` | `editor::GoToTypeDefinition` | `g y` |
| `shift-f12` | `editor::GoToImplementation` | `g shift-i` |
| `alt-shift-f12` | `editor::FindAllReferences` | `g shift-a`, `g r r` |
| `f2` | `editor::Rename` | `c d`, `g r n` |
| `cmd-.` | `editor::ToggleCodeActions` | `g .`, `g r a` |
| `cmd-shift-i` | `editor::Format` | — |
| `alt-shift-o` | `editor::OrganizeImports` | — |
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
| `ctrl-:` | `editor::ToggleInlayHints` | — |
| `cmd-k z` | `editor::ToggleSoftWrap` | `:set wrap` |
| `cmd-k cmd-h` | `call_hierarchy::ShowIncomingCalls` | — |
| `ctrl-space` | `editor::ShowCompletions` | `ctrl-x ctrl-o` (insert) |

`ctrl-space` collides with macOS's input-source switcher — disable that in
System Settings > Keyboard > Shortcuts > Input Sources if completions never
appear.

<a id="search-multibuffers"></a>
## Search and multibuffers

| binding | action | what it does |
|---|---|---|
| `cmd-f` / `cmd-e` | `buffer_search::Deploy` / `UseSelectionForFind` | in-file search |
| `cmd-g` / `cmd-shift-g` | `search::SelectNextMatch` / `…Previous…` | step through matches |
| `alt-enter` (search bar) | `search::SelectAllMatches` | cursor on every match |
| `alt-cmd-c` / `alt-cmd-w` / `alt-cmd-x` | `search::ToggleCaseSensitive` / `ToggleWholeWord` / `ToggleRegex` | search options |
| `cmd-shift-f` | `pane::DeploySearch` | project search multibuffer (`g /` in vim mode) |
| `cmd-shift-h` | `pane::DeploySearch` + replace | project search-and-replace |
| `cmd-shift-j` | `project_search::ToggleFilters` | include/exclude globs |
| `cmd-enter` | `project_search::SearchInNew` | run the query in a fresh tab |
| `cmd-shift-enter` | `project_search::ToggleAllSearchResults` | expand/collapse every result |
| `escape` | `project_search::ToggleFocus` | query box <-> results |

Project search runs as you type (`search.search_on_type: false` to require
`enter`). The regex engine is Rust's: groups are `(…)`, replacements use
`$1`, and `:%s/\(a\)/\1/` is auto-converted in the palette.

**Inside any multibuffer** (`Editor && multibuffer`):

| binding | action | what it does |
|---|---|---|
| `cmd-up` / `cmd-down` | `editor::MoveToStartOfExcerpt` / `…NextExcerpt` | jump between excerpts |
| `alt-enter` / `cmd-alt-enter` | `editor::OpenExcerpts` / `…Split` | open the real file at the cursor (`g space` in vim mode) |
| `shift-enter` | `editor::ExpandExcerpts` | show more context around the excerpt |
| `cmd-shift-b` | `outline_panel::ToggleFocus` | tree of the files in the multibuffer |

<a id="git"></a>
## Git

Three surfaces: the **git panel** (`ctrl-shift-g`) for the file list and
commit box, the **project diff** (`ctrl-g d` from the panel, or
`git: diff`) as an editable multibuffer, and **inline hunks** in any editor.

| binding | action | where |
|---|---|---|
| `ctrl-shift-g` | `git_panel::ToggleFocus` | anywhere |
| `ctrl-g d` | `git::Diff` | panel; project diff multibuffer |
| `space` / `cmd-y` / `cmd-shift-y` | `git::ToggleStaged` / `StageFile` / `UnstageFile` | panel list (`x` in vim mode) |
| `cmd-ctrl-y` / `cmd-ctrl-shift-y` | `git::StageAll` / `UnstageAll` | panel, project diff |
| `cmd-y` / `cmd-shift-y` | `git::StageAndNext` / `UnstageAndNext` | project diff, editor hunks (`d u` / `d shift-u`) |
| `cmd-alt-y` | `git::ToggleStaged` | editor hunk (`d shift-o`) |
| `cmd-alt-z` | `git::Restore` | revert the hunk (`d p`) |
| `cmd-f8` / `cmd-shift-f8` | `editor::GoToHunk` / `…Previous…` | editor (`] c` / `[ c`) |
| `cmd-'` / `cmd-"` | `editor::ToggleSelectedDiffHunks` / `ExpandAllDiffHunks` | show old text inline (`d o`); `escape` collapses |
| `cmd-alt-g b` | `git::Blame` | toggle blame column |
| `cmd-k cmd-b` | `editor::BlameHover` | blame for the current line (`g shift-b`) |
| `cmd-alt-g r` / `cmd-alt-g m` | `git::ReviewDiff` / `OpenModifiedFiles` | branch review / open every changed file |
| `tab` | `git_panel::FocusEditor` / `FocusChanges` | list <-> commit box (`i` in vim mode) |
| `cmd-enter` / `cmd-shift-enter` | `git::Commit` / `git::Amend` | commit box |
| `alt-tab` | `git::GenerateCommitMessage` | AI message (`agent.commit_message_model`) |
| `shift-escape` | `git::ExpandCommitEditor` | full-size commit editor |
| `ctrl-g ctrl-g` / `ctrl-g up` / `ctrl-g down` | `git::Fetch` / `Push` / `Pull` | panel; `shift-up`/`shift-down` for force-push / pull-rebase |

**Split vs unified:** project/branch diffs are side-by-side by default since
0.224; `editor: toggle split diff` (`editor::ToggleSplitDiff`) flips a view,
`"diff_view_style": "unified"` changes the default. Inline editor hunks are
always unified. Unbound but useful: `git::Switch` (branch picker, also
deletes branches), `git::StashAll`/`StashPop`, `editor::ToggleGitBlameInline`.

<a id="agent-panel"></a>
## Agent panel

The panel is a dock panel (right dock in classic layout, left in agentic),
so opening, zooming, and closing it are the generic dock keys:

| binding | action | what it does |
|---|---|---|
| `cmd-?` | `agent::ToggleFocus` | open + focus; again returns focus to the editor (panel stays) |
| `shift-escape` | `workspace::ToggleZoom` | with the panel focused: fill the window with it; again to restore |
| `ctrl-alt-w` | `workspace::CloseActiveDock` | close the dock the panel is in |
| `cmd-r` (or `cmd-b` in agentic layout) | `workspace::ToggleRightDock` / `…Left…` | hide/show the dock without moving focus |
| `cmd-alt-y` | `workspace::ToggleAllDocks` | hide every dock for a clean editor, then bring them back |
| `cmd-n` | `agent::NewThread` | new Zed Agent thread (panel focused) |
| `cmd-alt-shift-n` | `agent::ToggleNewThreadMenu` | the `+` menu: Zed Agent, each installed external agent, New From Summary, Terminal |
| `ctrl-tab` / `ctrl-shift-tab` | `agents_sidebar::ToggleThreadSwitcher` | MRU thread switcher, like the tab switcher |
| `cmd-alt-c` / `cmd-alt-m` | `agent::OpenSettings` / `ToggleOptionsMenu` | AI settings page / the `…` menu |
| `cmd-shift-e` | `project_panel::ToggleFocus` | hop to the project tree from the panel |

**Full-screen a thread and come back:** `cmd-?` (focus the panel),
`shift-escape` (zoom). To return to code: `shift-escape` (unzoom) then `cmd-?`
(focus the editor), or `ctrl-alt-w` to close the dock outright — closing a
zoomed dock also unzooms. `cmd-alt-y` is the quickest "I just want the
editor" key when several docks are open.

**External agents** (Claude, Codex, Cursor, pi, Gemini, Copilot CLI — the
`agent_servers` entries in `settings.json`) are installed from
`zed: acp registry` and then appear in the `+` menu and the sidebar like any
other thread. They bring their own auth (`/login` inside a Claude thread),
read their own instruction files (`CLAUDE.md`, not Zed's `AGENTS.md`), and
ignore Zed profiles. **Terminal Threads** (`+` menu > Terminal) are a plain
terminal tracked as a thread in the sidebar — run `claude`/`pi`/`codex`
there when you want the CLI itself; this is the sidekick-in-nvim
equivalent. `agent::NewExternalAgentThread` and `agent::NewTerminalThread`
are the actions to bind for one-key launches.

<a id="threads-sidebar"></a>
## Threads sidebar

Lists every thread across open projects, grouped by project
(`agent.threads_sidebar.position`, `.default_width` — 222 in this repo —
and `.auto_open`).

| binding | action | what it does |
|---|---|---|
| `cmd-alt-j` | `multi_workspace::ToggleWorkspaceSidebar` | show/collapse the sidebar (anywhere) |
| `cmd-alt-;` | `multi_workspace::FocusWorkspaceSidebar` | focus it without toggling |
| `up` / `down` (`ctrl-p` / `ctrl-n`) | `menu::SelectPrevious` / `SelectNext` | move through threads |
| `left` / `right` | `menu::SelectParent` / `SelectChild` | collapse / expand a project group |
| `enter` / `space` | `menu::Confirm` | switch to the thread |
| `cmd-f` | `agents_sidebar::FocusSidebarFilter` | fuzzy-filter thread titles |
| `cmd-n` | `agents_sidebar::NewThreadInGroup` | new thread in the selected project |
| `shift-r` | `agent::RenameSelectedThread` | rename |
| `shift-backspace` | `agent::ArchiveSelectedThread` | archive to history (running threads must finish first) |
| `cmd-shift-backspace` | `agent::RemoveSelectedThread` | delete |
| `cmd-g` | `agents_sidebar::ToggleThreadHistory` | all threads, all projects, chronological; `backspace` there un-archives, hover-trash deletes |
| `ctrl-tab` | `agents_sidebar::ToggleThreadSwitcher` | MRU switcher |

Loop for iterating threads without the mouse: `cmd-alt-;`, `down`/`up`,
`enter`, read, `cmd-alt-;` again. Or skip the sidebar entirely and `ctrl-tab`
from inside a thread.

<a id="inside-thread"></a>
## Inside a thread

Context is `AcpThread` (the transcript) and `AcpThread > Editor` (the
message box). Most keys work from both.

| binding | action | what it does |
|---|---|---|
| `enter` / `cmd-enter` | `agent::Chat` / `ChatWithFollow` | send / send and follow the agent through files |
| `cmd-shift-enter` | `agent::SendImmediately` | interrupt generation and send now |
| `cmd-shift-alt-enter` | `agent::SendNextQueuedMessage` | queued messages: send next; `cmd-ctrl-e` edit, `cmd-shift-backspace` drop, `cmd-alt-backspace` clear |
| `cmd-ctrl-s` | `agent::ToggleSteerFirstQueuedMessage` | steer = inject at the next step (Zed Agent only) |
| `shift-alt-escape` | `agent::ExpandMessageEditor` | full-height message box |
| `shift-pageup` / `shift-pagedown` | `agent::ScrollOutputToPreviousMessage` / `…Next…` | jump between messages (`ctrl-alt-pageup/pagedown` from the box) |
| `pageup` / `pagedown`, `home` / `end` | `agent::ScrollOutputPage…` / `…ToTop` / `…ToBottom` | scroll the transcript (`ctrl-` variants from the box) |
| `cmd-f` / `cmd-g` / `cmd-shift-g` | `agent::ToggleSearch` / `SelectNextThreadMatch` / `…Previous…` | search inside the thread; `escape` dismisses |
| `ctrl-;` / `@` | `agent::OpenAddContextMenu` | attach files, dirs, symbols, threads, diagnostics, URLs |
| `cmd->` | `agent::AddSelectionToThread` | from any editor or terminal: quote the selection into the thread |
| `cmd-shift-v` | `agent::PasteRaw` | paste code without the auto `@`-mention wrapping |
| `cmd-i` / `shift-tab` | `agent::ToggleProfileSelector` / `CycleModeSelector` | Write / Ask / Minimal profile; ACP session mode |
| `cmd-alt-/` / `alt-tab` | `agent::ToggleModelSelector` / `CycleFavoriteModels` | model picker / cycle `agent.favorite_models` |
| `cmd-alt-k` / `ctrl-'` / `cmd-alt-.` | `agent::ToggleThinkingMode` / `CycleThinkingEffort` / `ToggleFastMode` | per-model knobs |
| `cmd-y` / `cmd-alt-y` / `cmd-alt-z` | `agent::AllowOnce` / `AllowAlways` / `RejectOnce` | answer a tool-permission prompt; `cmd-alt-a` opens the granularity dropdown |
| `cmd-alt-p` / `cmd-alt-l` | `agent::ManageProfiles` / `ManageSkills` | profile and skills modals |
| `ctrl--` | `pane::GoBack` | back to the previous thread view |
| `/compact` | — | manual context compaction |

There is no key for collapsing an individual message or tool card — click
the card header. Stop is the button next to the send icon.

<a id="review"></a>
## Reviewing agent edits

| binding | action | what it does |
|---|---|---|
| `shift-ctrl-r` | `agent::OpenAgentDiff` | "Review Changes" multibuffer of every edit in the thread |
| `shift-ctrl-d` | `git::Diff` | the ordinary project diff, from inside a thread |
| `cmd-y` / `cmd-alt-z` | `agent::Keep` / `agent::Reject` | per hunk, in the review buffer or an inline agent diff |
| `shift-alt-y` / `shift-alt-z` | `agent::KeepAll` / `agent::RejectAll` | whole thread (also from the message box) |
| `shift-alt-u` | `agent::UndoLastReject` | bring back the last rejected hunk |
| `alt-enter` | `editor::OpenExcerpts` | open the real file from the review buffer |

`"agent.single_file_review": true` shows agent hunks inline in each file with
the same keep/reject keys. Checkpoints were removed in 1.27 — rejecting
edits or git is the undo path.

<a id="inline-prediction"></a>
## Inline assistant and edit prediction

- **Inline assist:** `ctrl-enter` (`assistant::InlineAssist`) in any editor
  or terminal; `ctrl-x ctrl-a` from vim insert mode. Transforms the selection
  (or current line) in place; works with multiple cursors. `ctrl-[`/`ctrl-]`
  cycle alternatives when `agent.inline_alternatives` lists extra models.
  Prefill a prompt from a binding:
  `["assistant::InlineAssist", { "prompt": "Add a doc comment" }]`.
- **Edit prediction** (`edit_predictions.provider`: `zed`, `copilot`, …,
  `none`): `tab` or `alt-tab` accepts (`editor::AcceptEditPrediction`),
  `ctrl-cmd-right` / `ctrl-cmd-down` accept a word / line, `escape` dismisses,
  `ctrl-cmd-e` toggles. `"edit_predictions": { "mode": "subtle" }` hides them
  until you hold `alt`. Context for rebinding: `Editor && edit_prediction`.

<a id="terminal-tasks-debugger"></a>
## Terminal, tasks, debugger

| binding | action | what it does |
|---|---|---|
| `` ctrl-` `` / `ctrl-~` | `terminal_panel::Toggle` / `workspace::NewTerminal` | panel / new terminal tab in it |
| `cmd-n` / `cmd-d` | `workspace::NewTerminal` / `pane::SplitRight` | in the panel: new tab / split |
| `ctrl-shift-space` | `terminal::ToggleViMode` | vi-style scrollback selection |
| `cmd-k` / `cmd-f` | `terminal::Clear` / `buffer_search::Deploy` | clear / search |
| `cmd-shift-r` / `cmd-alt-r` | `task::Spawn` / `task::Rerun` | task picker / rerun last |
| `f4` | `debugger::Start` | new session picker (auto-detects tests, `main`) |
| `f5` / `f10` / `f11` / `shift-f11` | `debugger::Continue` / `StepOver` / `StepInto` / `StepOut` | while stopped |
| `f9` / `shift-f9` | `editor::ToggleBreakpoint` / `EditLogBreakpoint` | breakpoints |

Keys the shell needs (`ctrl-n`, `alt-b`) are forwarded with
`["terminal::SendKeystroke", "ctrl-n"]` in a `Terminal` context. Tasks live
in `~/.config/zed/tasks.json` or `.zed/tasks.json` and can be bound:
`["task::Spawn", { "task_name": "start lazygit", "reveal_target": "center" }]`.

<a id="vim-mode"></a>
## Vim mode

`"vim_mode": true` (or `workspace: toggle vim mode`). This repo's
`settings.json` ships it off with the `vim` block ready
(`use_system_clipboard: "on_yank"` matches nvim's yank-to-clipboard). Motions,
operators, text objects, registers, marks, macros, `.`, and `:` ranges all
work; `%` and `w` are Tree-sitter-tuned per language.

**Zed-specific maps worth learning** (they replace most of nvim's LSP
leader keys):

| keys | does |
|---|---|
| `g d` / `g y` / `g shift-i` / `g shift-a` | definition / type / implementation / references |
| `g r n` / `g r a` / `g r r` | rename / code actions / references (Neovim 0.11 `gr*` set) |
| `g h`, `shift-k` | hover |
| `g s` / `g shift-s` / `g /` | outline / project symbols / project search |
| `] d` `[ d`, `] c` `[ c`, `] m` `[ m`, `] ]` `[ [` | diagnostics, hunks, methods, sections |
| `d o` / `d p` / `d u` | expand hunk / revert hunk / stage hunk and next |
| `g c c`, `y s`, `c s`, `d s`, `c x` | comment, surround add/change/delete, exchange |
| `g l` / `g a` | add cursor at next match / all matches (multi-cursor) |
| `ctrl-w h/j/k/l`, `v`, `s`, `q`, `o` | pane navigation, splits, close, close others |
| `z a` / `z shift-m` / `z shift-r` | fold toggle / fold all / unfold all |
| `shift-z shift-z` / `shift-z shift-q` | save and close tab / close without saving |
| `:E`, `:G`, `:A`, `:te`, `:cl`, `:D` | project panel, git, agent, terminal, diagnostics, debug |

**Differences from nvim to expect:** `:` commands take no file arguments
(`:e foo` does not exist — use `cmd-p`); `s`/`shift-s` are substitute unless
you bind sneak; visual-block edits are multi-cursor; the regex dialect is
Rust's. Vim contexts (`vim_mode == normal`) exist only on `Editor`, so a
binding scoped `Workspace && vim_mode == normal` never fires.

<a id="custom-bindings"></a>
## Adding your own bindings

`~/.config/zed/keymap.json` — stowed from `zed/.config/zed/keymap.json`.
Open it with `cmd-k cmd-s` (`zed::OpenKeymap`, a GUI editor that writes
back to the file) or `zed: open keymap file`. Open the defaults with
`zed: open default keymap`. The file is an array of
`{ "context", "bindings" }` blocks; user blocks load after the defaults and
a later definition in the same context wins.

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

The pieces:

- **Finding the action name.** Command palette: the entry
  `agent: toggle focus` is `agent::ToggleFocus` (module `::` PascalCase).
  The palette's bottom-left `Add Keybinding` button opens the keymap editor
  pre-filled. Autocomplete inside keymap.json also knows every action.
- **Key notation.** Modifiers `cmd-`, `ctrl-`, `alt-`, `shift-`, `fn-`,
  joined with `-`; `shift-` only with letters (`shift-g`, never `shift-(`).
  Chords are space-separated: `"space a a"`, `"cmd-k cmd-s"`. Pending
  chords wait 1 s; `alt-/` lists what can complete one, and
  `"which_key": { "enabled": true }` shows a which-key.nvim-style popup.
- **Contexts.** `Editor`, `Workspace`, `Pane`, `Dock`, `Terminal`,
  `ProjectPanel`, `GitPanel`, `AgentPanel`, `AcpThread`, `ThreadsSidebar`,
  `OutlinePanel`, `BufferSearchBar`, `menu`, plus attributes like
  `vim_mode == normal`, `multibuffer`, `mode == full`, `renaming`,
  `showing_completions`. Combine with `&&`, `||`, `!`, parentheses, and
  `>` for "descendant of" (`AcpThread > Editor` is the message box). Deeper
  nodes win over shallower ones. `dev: open key context view` shows the
  live context under the cursor — use it when a binding does not fire.
- **Arguments.** `["action", arg]` — a bare value
  (`["workspace::ActivatePane", 0]`) or an object
  (`["task::Spawn", { "task_name": "…" }]`).
- **Macros.** `["workspace::SendKeystrokes", "escape g g"]` replays up to 100
  keys through the normal dispatch, so it can chain existing bindings.
- **Unbinding.** `null`. It follows precedence, so `"cmd-r": null` in
  `Editor` blocks the `Workspace` default too.
- **Vim leader.** In `VimControl` contexts `space` is `vim::WrappingRight`;
  any `space …` chord you add in `vim_mode == normal` shadows it, which is
  the whole trick behind the commented-out leader block in this repo's
  keymap.json. Add `!menu` so completions and pickers keep their keys.

**One-key agent launches.** `agent::NewExternalAgentThread` takes the agent
to start; `agent::NewTerminalThread` opens a Terminal Thread. The argument
shape was not verified against 1.28.1 — bind it through the keymap editor
(`Add Keybinding`), which fills in the accepted form, and check
`dev: open acp logs` if a bound agent fails to start.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **Zed rewrites `settings.json`** through the stow symlink whenever you
  change a setting in its UI — run `git diff zed/` afterwards. The keymap
  editor does the same to `keymap.json`.
- **`cmd-w` no longer closes a dock** (1.22+); it is `ctrl-alt-w`. `cmd-w`
  closes the active tab.
- **`cmd-?` toggles focus, not visibility.** The panel stays open; use
  `cmd-r`/`cmd-b` (dock), `ctrl-alt-w` (close), or set
  `close_panel_on_toggle`.
- **`shift-escape` is context-sensitive:** zoom in the editor/panels,
  expand-commit-editor in the git commit box.
- **`alt-tab` is overloaded:** accept edit prediction in the editor, cycle
  favorite models in a thread, generate a commit message in the git panel.
- **`cmd-y` is overloaded too:** stage-and-next in editors, keep-hunk in
  agent review, allow-once at a permission prompt.
- **`ctrl-space` needs the macOS input-source shortcut disabled** or
  completions will not open.
- **`ctrl-cmd-d` opens the macOS dictionary** instead of
  `editor::SelectPrevious`; the default keymap's comment carries a
  `defaults write` fix.
- **External agents do not read Zed's `AGENTS.md`, profiles, or skills** —
  Claude reads `CLAUDE.md`, pi reads its own config.
- **`vim_mode` contexts only exist on `Editor`;** a `Workspace`-scoped vim
  binding is silently dead.
- **Text threads and the Rules Library are gone** (replaced by Skills and
  `~/.config/zed/AGENTS.md`); old docs and blog posts still mention them.
