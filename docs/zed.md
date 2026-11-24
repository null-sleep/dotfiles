# Zed — shortcuts, workflows, and keymaps

How to drive [Zed](https://zed.dev) from the keyboard: the default macOS
bindings that matter, the workflows behind them (agent threads, review,
git, search), and how to add your own. Install/stow steps live in README's
`## Zed` section; vim mode has its own companion, [`docs/zed-vim.md`](zed-vim.md);
nvim's keymaps live in `nvim/.config/nvim/GUIDE.md`.
Nvim comparisons are deliberately brief — learn Zed's native keys first.

**Basis: Zed 1.29.2** (`zed --version`) — checked against the `v1.29.2`
tag (`assets/keymaps/default-macos.json`, `vim.json`) and the zed.dev docs
and release notes below; "not verified" marks claims checked nowhere. After
a Zed upgrade, re-check against the new tag and bump the version here.

## References

- [Key bindings](https://zed.dev/docs/key-bindings) — keymap.json syntax,
  contexts, precedence, `use_key_equivalents`
- [Default macOS keymap (v1.29.2)](https://github.com/zed-industries/zed/blob/v1.29.2/assets/keymaps/default-macos.json)
  and [vim.json](https://github.com/zed-industries/zed/blob/v1.29.2/assets/keymaps/vim.json)
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
- Release notes: [stable](https://zed.dev/releases/stable) (1.19–1.29
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
- **[Reviewing changes — local diffs and PRs](#diff-review)**
- [Pickers and navigation](#pickers)
- [Bookmarks](#bookmarks)
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
- [Background notes](#background) — open checks, Terminal Thread restore,
  Zed Pro vs OpenRouter cost

---

<a id="quick-glance"></a>
## Daily keys — the quick glance

Used many times a day; each is covered in full below.

| key | does |
|---|---|
| `cmd-shift-p` / `cmd-p` / `cmd-shift-f` | command palette / file finder / floating text search |
| `f12` / `alt-shift-f12` | go to definition / find references |
| `f2` / `cmd-.` | rename / code actions |
| `cmd-shift-i` / `cmd-/` | format / toggle comment |
| `cmd-shift-e` / `ctrl-shift-g` | project panel / git panel |
| `ctrl-g d` / `git: diff branch` | uncommitted diff (from the git panel) / branch vs its base — the PR view |
| `` ctrl-` `` | terminal |
| `cmd-\` / `cmd-k cmd-<arrow>` | split right / move between panes |
| `cmd-w` / `ctrl--` | close tab / jump back (`ctrl-_` forward) |
| `cmd-?` | focus agent panel; again, back to the editor |
| `shift-escape` / `ctrl-alt-w` | zoom the focused panel / close the focused dock |
| `cmd-alt-j` / `cmd-alt-;` | toggle threads sidebar (show/hide) / jump focus to it and back |
| `ctrl-tab` / `ctrl-shift-tab` | thread switcher, most recent first — from the message box too |
| `alt-]` / `alt-[` | next / previous thread directly, no switcher (bound in `keymap.json`; agent panel and sidebar only) |
| `cmd-n` | new thread (panel focused) |
| `cmd-b` / `cmd-r` | hide / show the agent dock (`cmd-b` agentic layout, `cmd-r` classic); `cmd-?` shows and focuses it |
| `enter` / `cmd-enter` | send / send and follow (in a thread) |
| `ctrl-shift-r` | open agent diff (review changes) |
| `alt-shift-y` / `alt-shift-z` | keep all / reject all agent edits |
| `cmd-k cmd-v` | toggle vim mode (`workspace::ToggleVimMode`; writes `vim_mode` to `settings.json`) |
| `cmd-k cmd-m` | open `cheatsheet.md` (the `cheatsheet` task in `tasks.json`; opens as a markdown preview, `cmd-shift-v` shows the source). Shadows Zed's default `toolchain::AddToolchain`; like `cmd-k cmd-v`, dead with a terminal focused |

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
   preview pane (`cmd-shift-f` live grep, `lsp_results_location: "picker"`)
   for when you want to look, not edit.
4. **The agent panel is just a dock panel.** Threads (Zed Agent, external
   ACP agents, Terminal Threads) live in the Threads Sidebar; focus, zoom,
   and close are the generic dock operations.
5. **Your keymap.json loads after the defaults**, so a later definition in
   the same context wins. Binding `null` unbinds.

**Coming from the nvim config:** `cmd-p` is `<leader>sf`, `cmd-shift-f` is
`<leader>sg`, `cmd-shift-e` is `<leader>e`, `cmd-.` is `<leader>ca`, and
`cmd-?` is roughly `<C-.>` / `<leader>ai` (focus the sidekick CLI). Which leader keys to carry into
vim mode is decided in [`docs/zed-vim-keymap.md`](zed-vim-keymap.md); the
mechanics are under [Adding your own bindings](#custom-bindings).

<a id="diff-review"></a>
## Reviewing changes — local diffs and PRs

Every view here is an editable multibuffer: the
[multibuffer keys](#search-multibuffers) apply, edits save to the real
files, and LSP works inside them. For a branch, the git panel's
[branch mode](#git-panel-branch-mode) lists its changed files; the outline
panel (`cmd-shift-b`) also lists the focused diff's files (not verified).

**Basis:** read from the v1.29.2 source and keymaps, not yet tried in a
running Zed; the checks still to run are in
[Untested in the app](#diff-review-untested).

**Pick the view by the question:**

| question | open | diffs against |
|---|---|---|
| what haven't I committed? [1] | `ctrl-g d` in the git panel, `git: diff` anywhere | `HEAD` (staged hunks drawn hollow) |
| only staged / only unstaged? | `git: view staged changes` / `git: view unstaged changes`, or right-click in the git panel | `HEAD`→index / index→working tree |
| everything on this branch, committed or not — the PR view | `git: diff branch`; file list: `git panel: show branch changes` | merge-base with the default branch |
| the same against another base (stacked PR, release branch) | `git: compare with branch`, or the `Base:` button in a branch diff | merge-base with the branch you pick |
| one commit | git panel History tab (`cmd-2`), `git graph: open`, `git: file history` | the commit's parent |
| what did the agent change? | depends on the agent — [Agent edits](#diff-review-agents) | — |

[1] `git: diff` obeys `git.diff_base` (default `head`); `git: diff head`
always shows uncommitted changes. See [Branch diff](#branch-diff).

The Git gutter is explicitly enabled for tracked files (`git.git_gutter`),
showing added, changed, and deleted lines against the selected diff base.

### Uncommitted changes — the project diff

`ctrl-g d` is bound only in the git panel; elsewhere use `git: diff`, or
`ctrl-shift-d` from a thread's message box. Hunk by hunk, `cmd-y` /
`cmd-shift-y` stage / unstage and `cmd-alt-z` (`git::RestoreAndNext`)
reverts, each jumping to the next hunk; `cmd-ctrl-y` stages everything and
`cmd-enter` commits straight from the diff. The rest of the keys are under
[Git](#git).

<a id="branch-diff"></a>
### Branch diff — committed and uncommitted, against a base

`git: diff branch` (`git::DiffBranch`; `git::BranchDiff` still works) has
no default key. It is Zed's local PR view:

- **Contents:** `git diff --merge-base <base>` — the branch's commits *plus*
  uncommitted edits. With a clean tree, the same files as GitHub's "Files
  changed" (not verified). The tab reads `Changes since origin/main`.
- **Default base:** the first of `upstream/HEAD`, `origin/HEAD`,
  `init.defaultBranch`, `main`, `master`; if none resolves, it opens the
  project diff instead. `git remote set-head origin --auto` fills a missing
  `origin/HEAD`.
- **Toolbar:** a `+N −M` stat; `Base: origin/main` picks another base (any
  local or remote branch); `Review Diff` (`cmd-alt-g r`, shown when AI is
  on and the diff is non-empty) opens a thread on the last-used agent with
  the diff attached and a review prompt auto-sent.
- **No hunk stage/restore.** Edit the text, or stage from the project diff.
- **Limits:** the base must be a branch and the other side is always the
  working tree — no tag or commit base, no branch-vs-branch. For "my last N
  commits": `git branch -f review-base HEAD~N`, then
  `git: compare with branch` → `review-base` (not verified; holds because
  the merge-base of `HEAD` and `HEAD~N` is `HEAD~N`).
- **As the default:** `"git": { "diff_base": "default_branch" }` points
  `git: diff`, the gutter, and file colors at the default branch's
  merge-base. Not set here; `git: toggle diff base` flips it by rewriting
  the stowed `settings.json`, which dirties the repo.

<a id="git-panel-branch-mode"></a>
### Branch changes in the git panel (1.29+)

`git panel: show branch changes` (`git_panel::ShowBranchChanges`, no
default key) switches the panel's Changes tab from uncommitted files to
every file changed since a base branch: the branch diff's file list.

- **Base:** the default branch, unless you pick one with "Compare Against
  Base" in the menu at the top of the Changes tab
  (`git_panel::CompareAgainstBase`, any local or remote branch). With no
  default branch it opens that picker. While a branch diff tab is active,
  the panel adopts its base and follows `Base:` changes made there.
- **Opening a file** (`enter`) opens the branch diff scrolled to it, or
  focuses the branch diff already showing it.
- **Read-only list:** no checkboxes, no stage or restore. Edit in the
  diff, or switch back with `git panel: show uncommitted changes`.
- The picked base is forgotten on leaving branch mode or switching
  repository.

### Reviewing a PR

Zed has no GitHub PR integration — no PR list, review comments, or
approve; `git: create pull request` only opens the host's new-PR page.
Check the PR out and use the branch diff:

1. `gh pr checkout <N>` in a terminal, or in a separate worktree to leave
   the current checkout alone ([`docs/zed-worktrees.md`](zed-worktrees.md)).
2. Fetch: `ctrl-g ctrl-g` in the git panel (`git.auto_fetch` is off here).
   A stale base after the PR was rebased drags unrelated commits into the
   diff (not verified).
3. `git: compare with branch` → `origin/<base>`
   (`gh pr view <N> --json baseRefName -q .baseRefName`). For a PR into
   the default branch, plain `git: diff branch` is enough.
4. Walk it: `cmd-down`/`cmd-up` between excerpts, `cmd-shift-b` for the
   file list, `alt-enter` into the real file; `f12`/`alt-shift-f12` work as
   usual.
5. Optional agent pass: `Review Diff` in the toolbar, or `@` → branch diff
   in any thread (not verified: the `@` menu label).
6. Comment and approve on GitHub: `gh pr review <N>` or the web UI.

Inline diff review comments (`editor::SubmitDiffReviewComment`, `Send
Review to Agent`) exist in 1.29.2 but sit behind the staff-only
`diff-review` feature flag, and stable builds ignore `feature_flags`
overrides. [Delta](https://zed.dev/blog/delta-public-beta) (public beta,
Sep 2026) is Zed's separate PR replacement — review inside the agent's
thread, on an isolated copy of its worktrees — and doesn't view GitHub PRs
either.

<a id="diff-review-agents"></a>
### Agent edits

The thread's review buffer (`ctrl-shift-r`, [keys](#review)) only sees
edits that go through Zed:

- **Zed Agent:** every edit.
- **ACP agents that write through Zed** (ACP v1's `fs/write_text_file`,
  still offered in 1.29.2): every edit. `omp acp` does
  ([`docs/omp.md`](omp.md#zed-acp), probed on omp 18.4.12).
- **ACP agents that write to disk themselves** (the registry Claude ACP agent, `claude-acp`): none — edits
  are final (not verified; reported in
  [zed#50142](https://github.com/zed-industries/zed/issues/50142) and
  [#56048](https://github.com/zed-industries/zed/discussions/56048)). A Zed
  maintainer said in June 2026 that ACP v2 drops these filesystem APIs and
  external-agent review needs a new design, with no timeline.
- **Terminal Threads** (omp/claude CLIs): none.

For the rest, git is the review. Commit or stash before handing over a
task; then `git: diff` shows exactly what the agent changed, `cmd-alt-z`
reverts a hunk, and `cmd-y` stages what you keep. Once the agent commits,
use `git: diff branch` or the History tab.

<a id="diff-display"></a>
### Display

- **Split vs unified:** side-by-side by default since 0.224;
  `editor: toggle split diff` (`editor::ToggleSplitDiff`) flips one view,
  `"diff_view_style": "unified"` changes the default. Zed's docs name
  project, file-history, and stash diffs; branch, staged/unstaged, and
  commit diffs use the same split editor in source (not verified in the
  app). Inline editor hunks are always unified.
- **Inline hunks** in a normal editor: `cmd-'` / `cmd-"` as under
  [Git](#git); `editor: toggle all diff hunks` flips them all.
- `"git": { "show_stage_restore_buttons": false }` hides the per-hunk
  buttons; word-level highlighting is on unless `word_diff_enabled: false`.

<a id="pickers"></a>
## Pickers and navigation

| binding | action | what it does |
|---|---|---|
| `cmd-shift-p` | `command_palette::Toggle` | every action, with its binding; sorted by recency |
| `cmd-p` | `file_finder::Toggle` | fuzzy file finder with preview; pre-fills from the selection (`file_finder.prefill_query_from_selection`) |
| `cmd-shift-f` | `text_finder::Toggle` | live-grep picker with preview (Telescope `live_grep`); pre-fills from the selection or an open search; custom binding swaps Zed's defaults with `alt-cmd-f` |
| `cmd-t` / `cmd-shift-o` | `project_symbols::Toggle` / `outline::Toggle` | workspace symbols (with preview; only from [running language servers](#language-servers)) / current-file symbols (modal) |
| `cmd-shift-b` | `outline_panel::ToggleFocus` | outline as a panel; in a multibuffer, a tree of its files |
| `ctrl-tab` / `ctrl-shift-tab` | `tab_switcher::Toggle` | MRU tab switcher with file preview |
| `cmd-alt-o` | `projects::OpenRecent` | recent projects |
| `cmd-ctrl-b` / `cmd-ctrl-w` | `branches::OpenRecent` / `git::Worktree` | branch and worktree pickers; worktree workflow in [`docs/zed-worktrees.md`](zed-worktrees.md) |
| `ctrl-g` | `go_to_line::Toggle` | go to line |
| `ctrl--` / `ctrl-_` | `pane::GoBack` / `pane::GoForward` | navigation history, see below |
| `cmd-k cmd-p` | `workspace::ReopenLastPicker` | reopen the last picker |
| `cmd-shift-m` | `diagnostics::Deploy` | all project diagnostics as a multibuffer |
| `project bookmarks: toggle` | `project_bookmarks::Toggle` | bookmark picker (1.29+, no default key) — see [Bookmarks](#bookmarks) |

**Back and forward after a jump.** Go to definition and similar jumps
(references, symbol and outline picks, `go_to_line`) record the previous
position in the navigation history. `ctrl--` goes back and
`ctrl-_` (`ctrl-shift--`) goes forward, in any mode; the tab bar's arrows
run the same actions. In vim normal mode `ctrl-o` / `ctrl-i` are the same
two actions and cross files, so they follow `gd` into another file and
back. In insert mode `ctrl-o` runs one normal-mode command instead, so
press `escape` first. `ctrl-]` / `ctrl-t` (`GoToDefinition` /
`GoToOlderTag`) are the tag-stack variant. Full vim-mode and nvim
comparison: [`zed-vim.md`](zed-vim.md#nvim-nav-compare).

Inside any picker (`menu` context): `enter` confirms, `cmd-enter` opens in
a split, `escape`/`ctrl-c` cancels, `ctrl-n`/`ctrl-p` or arrows move. In
the file finder, `cmd-shift-i` toggles ignored files.

**Telescope-style pickers (1.9+):** picker modals resize by dragging, the
file finder, text finder, and project symbols show a live preview pane, and
`"lsp_results_location": "picker"` turns references / definition /
implementation results into a filterable picker instead of a multibuffer
(per binding: `["editor::FindAllReferences", { "open_results_in": "picker" }]`).
So the choice is yours per feature: picker for a quick look, multibuffer
(`alt-cmd-f`, `cmd-shift-m`) when you want to edit the results in place.
Still no plugin ecosystem — the set of pickers is fixed.

<a id="bookmarks"></a>
## Bookmarks

A bookmark is a line you mark so you can return to it, optionally with a
label. Bookmarks landed in 1.28; 1.29 added the picker that searches them
across the project. **No bookmark action has a default key**, so bind the
ones you use (block below) or run them from the palette.

**Basis:** read from the v1.29.2 source (`crates/editor/src/bookmarks.rs`,
`crates/project/src/bookmark_store.rs`, `crates/project_bookmarks/`), not yet
tried in a running Zed; checks under [Untested](#bookmarks-untested).

| palette | action | what it does |
|---|---|---|
| `editor: toggle bookmark` | `editor::ToggleBookmark` | add / remove an unlabelled bookmark on the cursor's line |
| `editor: toggle bookmark with label` | `editor::ToggleBookmarkWithLabel` | add one and type a label in an inline prompt ("Enter bookmark label (Optional)") |
| `editor: edit bookmark` | `editor::EditBookmark` | rename the bookmark on the cursor's line |
| `editor: go to next bookmark` / `…previous…` | `editor::GoToNextBookmark` / `GoToPreviousBookmark` | step through bookmarks in the current editor |
| `project bookmarks: toggle` | `project_bookmarks::Toggle` | the picker: fuzzy-search every bookmark in the project, with preview |
| `editor: view bookmarks` | `editor::ViewBookmarks` | every bookmark as one editable multibuffer tab |
| `workspace: clear bookmarks` | `workspace::ClearBookmarks` | delete every bookmark in the project, no confirmation |

**Setting them.**

- One bookmark per line. Toggling on a bookmarked line removes it, label
  included.
- With several cursors, toggle acts on each cursor's line. If every one is
  already bookmarked it removes them all; otherwise it adds only the
  missing ones and leaves the rest alone. The with-label variant opens one
  prompt per new line.
- **Gutter:** hovering a line number shows an add button. With
  breakpoints and bookmarks both on (the default), a plain click adds a
  *breakpoint* and `cmd`-click adds a bookmark; the tooltip says so.
  Clicking an existing bookmark icon removes it. Right-click in the gutter
  for Add / Remove / Edit Bookmark. `"gutter": { "bookmarks": false }`
  hides the icons and the button.

**Finding them again.**

- **Picker** (`project bookmarks: toggle`): each row shows the label above
  `path:line`. An unlabelled bookmark uses the line's own text, trimmed.
  **The search matches labels only, not paths**, so label anything you'll
  want to find by name; an unlabelled `}` is hard to pick out. `enter`
  opens the file at that line; `cmd-enter` opens it as a regular tab, not a
  preview tab, and not in a split as in the file finder. Preview pane:
  the Preview button or `cmd-alt-p`; `cmd-alt-right` / `cmd-alt-down`
  place it, `cmd-alt-up` hides it. Opening the picker loads every
  bookmarked file; files deleted from disk are left out.
- **Next / previous** only cover the current editor (the file, or every
  excerpt of a multibuffer), wrap around at the ends, and unfold the line
  if it is folded. They never jump to another file; use the picker for that.
- **Bookmarks tab** (`editor: view bookmarks`): a "Bookmarks" multibuffer
  with each bookmarked line highlighted in its surrounding context. It
  refreshes as bookmarks change, reuses the open tab instead of opening a
  second one, and does nothing when there are no bookmarks. The
  [multibuffer keys](#search-multibuffers) apply (`cmd-down` to the next
  excerpt, `alt-enter` into the file).

**What they stick to.**

- Bookmarks belong to the workspace (the set of project folders) and are
  saved in Zed's database (`bookmarks` table in
  `~/Library/Application Support/Zed/db/0-stable/db.sqlite`), so they come
  back when the project reopens. A git worktree opened on its own is a
  separate workspace with its own bookmarks [INFERENCE: from the
  `workspace_id` key].
- While the file is open, a bookmark follows its line through edits. It is
  saved as a **row number**, though, so if the file changes while the
  project is closed (a pull, a rebase, an agent outside Zed), the bookmark
  comes back on whatever line now has that number. Rows past the end of the
  file are dropped.
- If a file is renamed while its buffer is open, its bookmarks move with
  it; if it's deleted while open, they're removed.
- Vim marks (`ma`, `'a`) are a separate system: they don't show in the
  picker or the gutter.

**Suggested bindings** (not in the stowed `keymap.json`; chords checked
free in the v1.29.2 macOS and vim keymaps). `cmd-k` is the terminal's clear
key, so none of these fire in a terminal:

```jsonc
{
  "context": "Editor && mode == full",
  "bindings": {
    "cmd-k b": "editor::ToggleBookmark",
    "cmd-k shift-b": "editor::ToggleBookmarkWithLabel",
    "cmd-k ]": "editor::GoToNextBookmark",
    "cmd-k [": "editor::GoToPreviousBookmark"
  }
},
{
  "context": "Workspace",
  "bindings": {
    "cmd-k '": "project_bookmarks::Toggle",
    "cmd-k shift-l": "editor::ViewBookmarks"
  }
}
```

<a id="bookmarks-untested"></a>
**Untested in the app.** Fix the text if reality differs, then delete the
item:

- [ ] Plain gutter click adds a breakpoint, `cmd`-click a bookmark.
- [ ] The picker doesn't match on file paths; an unlabelled bookmark shows
  the line text.
- [ ] `cmd-enter` in the picker opens a regular (non-preview) tab.
- [ ] Bookmarks survive a Zed restart; after the file changes on disk while
  Zed is closed, they stay on the old row number.
- [ ] The suggested chords work.

<a id="panes-docks"></a>
## Panes, tabs, and docks

| binding | action | what it does |
|---|---|---|
| `cmd-b` / `cmd-r` / `cmd-j` | `workspace::ToggleLeftDock` / `ToggleRightDock` / `ToggleBottomDock` | show/hide a dock without moving focus |
| `cmd-alt-y` | `workspace::ToggleAllDocks` | hide/show every dock — from a dock or empty pane; inside an editor the deeper `git::ToggleStaged` binding wins |
| `shift-escape` | `workspace::ToggleZoom` | zoom the focused pane or panel to fill the window; again to restore — see [Zoom](#zoom) |
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

<a id="zoom"></a>
### Zoom — `shift-escape`

One key, `workspace::ToggleZoom`, toggles zoom on **whatever has focus**.
Check focus first: the same key zooms the editor, the agent thread, or the
terminal depending on where the cursor is. It is in the global (context-free)
block of the default keymap, so it needs no `keymap.json` entry.

| focused thing | what `shift-escape` does |
|---|---|
| agent panel / thread | zooms the thread to fill the window; the header button (top right, "Enable Full Screen" / "Disable Full Screen") is the same action |
| terminal panel | zooms the terminal, all its splits together; button tooltip says Zoom In / Zoom Out |
| debugger panel | zooms the panel |
| editor (center pane) | zooms that pane; with splits open, the other panes are hidden until you zoom out. A pane with no tabs doesn't zoom |
| project / git / outline panel | nothing — their source defines no zoom handling in v1.29.2 (not tested) |
| git commit box | **expands the commit editor instead** (`git::ExpandCommitEditor`) |

**Getting out:**

- `shift-escape` again, with focus still in the zoomed thing. If focus moved
  elsewhere, click back into it first.
- `ctrl-alt-w` closes the focused dock, which also unzooms.
- Opening another dock (`cmd-b` / `cmd-r` / `cmd-j`, or a panel's
  `ToggleFocus`) drops the zoom: Zed hides the zoomed panel's dock and
  unzooms center panes.
- Closing the last tab in a zoomed center pane, or the last terminal
  in a zoomed terminal panel, unzooms.

**Related, not the same:** `ctrl-w _` (vim) maximizes a pane *within* its
split group, and `ctrl-cmd-f` / `fn-f` (`zed::ToggleFullScreen`) puts the
whole macOS window in full screen. Zoom keeps the window layout and only
hides the rest of the workspace.

Basis: v1.29.2 `default-macos.json` and the `workspace`, `agent_ui`,
`terminal_view`, and `debugger_ui` crate sources; the table is read from
source, not tested panel by panel.

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

<a id="folding"></a>
**Folding.** Fold ranges are indent-based by default, not a tree-sitter
`foldexpr` like this repo's nvim. A fold starts on a line whose next
non-blank line is indented deeper and runs to the next line at the same or
shallower indent; a closing bracket stays on the placeholder line
(`fn f() {⋯}`). Tree-sitter only keeps unindented lines inside a string or
block comment from ending the fold. Badly indented code folds badly.
- `"document_folding_ranges": "on"` (global, or per language under
  `languages`) uses the server's `foldingRange` ranges, falling back to
  indent folding when the server returns none.
- `"gutter": { "folds": false }` hides the fold chevrons.
- Folds are saved per file path in Zed's database and restored on reopen or
  restart — except with `restore_on_startup: "empty_tab"`.
- In a multibuffer (project diff, search results), fold actions collapse
  whole excerpts (one per file).

Native keys beyond the table:
- `alt-cmd-[` / `alt-cmd-]` — fold / unfold at the cursor.
- `cmd-k cmd-[` / `cmd-k cmd-]` — fold / unfold recursively.
- `cmd-k cmd-1`…`9` — fold at that indent level.
- `cmd-shift-enter` — toggle all folds.
- `editor: fold function bodies` (no key) — folds every `@function.inside`
  range from the language's `textobjects.scm`.

Source: `fold.rs`, `display_map.rs` (`crease_for_buffer_row`), v1.29.2. Vim
keys: [`zed-vim.md` → Tree-sitter objects and folds](zed-vim.md#treesitter).

**Syntax-node selection.** Besides `cmd-ctrl-right` / `cmd-ctrl-left`
(table above), `ctrl-shift-right` / `ctrl-shift-left` also grow / shrink the
selection to the enclosing syntax node; shrinking retraces the grow history.
`cmd-ctrl-down` / `cmd-ctrl-up` select the next / previous sibling node.

<a id="language-servers"></a>
**Language servers in a multi-language repo.** A server starts when you
open a file of its language, not when you open the project: a Go + Rust
repo with only `.go` files open runs only gopls. Workspace symbol search
(`cmd-t`, `project_symbols::Toggle`) queries every *running* server and
merges the results, so a language you have not opened yet contributes
nothing — open one file per language after launching Zed. Servers also run
per worktree ([`zed-worktrees.md`](zed-worktrees.md)), and servers that
only index open files return less than ones that scan the project. Check
what is running with `dev: open language server logs`; restart a stuck one
with `editor: restart language server` (e.g. after adding a `Cargo.toml`).

**Server roots follow manifests, not the project root.** Zed walks up from
the file to the nearest manifest (`Cargo.toml` for Rust, `go.mod` for Go).
This repo has neither at its root, only `fixtures/Cargo.toml` and
`fixtures/go.mod`, so opening the dotfiles repo starts servers rooted at
`fixtures/`, and only once you open `animal.rs` / `animal.go`. A Rust file
with no `Cargo.toml` above it gets a server with no workspace, which is
the "Failed to discover workspace" error. Read from the v1.29.2 source
(`LspStore::symbols`, `manifest_tree.rs`), not tested in the app.

**The `cmd-t` prompt is one name query.** Unlike nvim's `<leader>ss`
(first word to the LSP, the rest fuzzy-filters by file path), Zed sends the
whole prompt to each server and fuzzy-matches the symbol name locally; a
space is an ordinary character, not a path filter. Only `::` is special:
the part after the last `::` is used for the local match, for
rust-analyzer's `module::item` queries. To narrow by file, use `cmd-p` or
`cmd-shift-f` instead (source: `project_symbols.rs`, v1.29.2).

<a id="search-multibuffers"></a>
## Search and multibuffers

| binding | action | what it does |
|---|---|---|
| `cmd-f` / `cmd-e` | `buffer_search::Deploy` / `UseSelectionForFind` | in-file search |
| `cmd-g` / `cmd-shift-g` | `search::SelectNextMatch` / `…Previous…` | step through matches |
| `alt-enter` (search bar) | `search::SelectAllMatches` | cursor on every match |
| `cmd-alt-c` / `cmd-alt-w` / `cmd-alt-x` | `search::ToggleCaseSensitive` / `ToggleWholeWord` / `ToggleRegex` | search options |
| `alt-cmd-f` / `cmd-shift-h` | `pane::DeploySearch` (+ replace) | project search multibuffer (`g /`) / search-and-replace |
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

**No quickfix-style curation (Zed 1.29.2).** You can't prune a results
multibuffer down to a few hand-picked matches, or send picker or file-finder
results into one; no action removes a single excerpt, and the list is a live
view of the query, not a saved set. Workarounds: narrow the query or its
`cmd-shift-j` globs, keep the results tab open and use `cmd-alt-enter` to
open matches in a split, or edit in place (`cmd-d`, `option-click`). Files
you edit can drop out of the list when it refreshes. Read from the source,
not tested.

<a id="git"></a>
## Git

Four surfaces: the **git panel** (`ctrl-shift-g`) for the file list and
commit box (its Changes tab also has a [branch mode](#git-panel-branch-mode)),
the **project diff** (`ctrl-g d` from the panel, or `git: diff`) and
**branch diff** (`git: diff branch`) as editable multibuffers, and
**inline hunks** in any editor. Which diff to open for which review is in
[Reviewing changes](#diff-review).

| binding | action | where |
|---|---|---|
| `ctrl-shift-g` | `git_panel::ToggleFocus` | anywhere |
| `ctrl-g d` | `git::Diff` | panel |
| `space` / `cmd-y` / `cmd-shift-y` | `git::ToggleStaged` / `StageFile` / `UnstageFile` | panel list (`x`) |
| `cmd-ctrl-y` / `cmd-ctrl-shift-y` | `git::StageAll` / `UnstageAll` | panel, project diff |
| `cmd-y` / `cmd-shift-y` | `git::StageAndNext` / `UnstageAndNext` | project diff, editor hunks (`d u` / `d shift-u`) |
| `cmd-alt-y` / `cmd-alt-z` | `git::ToggleStaged` / `Restore` | editor hunk: stage toggle (`d shift-o`) / revert (`d p`) |
| `cmd-f8` / `cmd-shift-f8` | `editor::GoToHunk` / `…Previous…` | editor (`] c` / `[ c`) |
| `cmd-'` / `cmd-"` | `editor::ToggleSelectedDiffHunks` / `ExpandAllDiffHunks` | show old text inline (`d o`); `escape` collapses |
| `cmd-alt-g b` / `cmd-k cmd-b` | `git::Blame` / `editor::BlameHover` | blame column / current line (`g shift-b`) |
| `cmd-alt-g r` / `cmd-alt-g m` | `git::ReviewDiff` / `OpenModifiedFiles` | in a branch diff: send it to an agent thread for review / open every changed file |
| `tab` | `git_panel::FocusEditor` / `FocusChanges` | list <-> commit box (`i`) |
| `cmd-enter` / `cmd-shift-enter` | `git::Commit` / `git::Amend` | commit box |
| `alt-tab` | `git::GenerateCommitMessage` | AI message (`agent.commit_message_model`) |
| `shift-escape` | `git::ExpandCommitEditor` | full-size commit editor |
| `ctrl-g ctrl-g` / `ctrl-g up` / `ctrl-g down` | `git::Fetch` / `Push` / `Pull` | panel; `shift-up`/`shift-down` for force-push / pull-rebase |

Split vs unified and the other display settings are under
[Reviewing changes → Display](#diff-display). Unbound but useful:
`git::Switch` (branch picker, also deletes branches),
`git::StashAll`/`StashPop`, `editor::ToggleGitBlameInline`.

**Dates and the commit view (1.29+, none set here).** `git.date_format`
(`"locale"` default, `"iso"`, or strftime like `"%Y-%m-%d %H:%M"`) formats
absolute dates; each view picks `"relative"` or `"absolute"` with its own
`date_style`: `git.blame`, `git.inline_blame`, `git.branch_picker`,
`git.stash_picker`, `git_panel` (relative by default) and `git_graph`
(absolute). `git.commit_view.expand_description` (default `false`) and
`.expand_files` (default `true`) set how a commit view opens; opening one
from blame scrolls to the blamed file.

**Where commit and rebase messages open.** The commit box runs
`git commit --quiet -m <message> --cleanup=strip` (`--amend` for amend;
`crates/git/src/repository.rs` at v1.29.2), so no editor is involved and
hooks still run. Pull is non-interactive too; README's git setup sets
`pull.rebase true`, so plain `ctrl-g down` rebases as well. Zed has no
interactive-rebase UI and no highlighting for `git-rebase-todo`; conflicts
get native "Use <branch> / Use <other branch> / Use Both / Resolve with Agent" buttons
(`conflict_view.rs`). Git commands that need an editor (`git commit` without
`-m`, `git rebase -i`) go to `$GIT_EDITOR`: in Zed's terminal and in the
environment Zed captures for agents and tasks, zsh sets it to `zed-editor`
(`zed --wait`), so the file opens as a Zed tab (`COMMIT_EDITMSG` gets the
built-in Git Commit highlighting) and git continues once you save and close
it with `cmd-w`. Open a new terminal after changing this; agents pick it up
after Zed restarts or the project reopens. See README → zed-editor.

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

**Full-screen a thread and come back:** click into the thread (or `cmd-?`),
then `shift-escape`. Same key to restore; `ctrl-alt-w` also closes the dock
and unzooms. `cmd-r` (`cmd-b` in agentic layout) hides the dock without
moving focus. Details and other panels: [Zoom](#zoom).

**Hide the chat and bring it back.** The panel lives in a dock, so it hides
like one:

| goal | key |
|---|---|
| hide, focus stays put | `cmd-b` (agentic layout, left dock) / `cmd-r` (classic layout, right dock) |
| hide the dock you are focused in | `ctrl-alt-w` |
| show it again | the same `cmd-b` / `cmd-r`; or `cmd-?`, which also focuses the message box |
| hide every dock, then restore them | `cmd-alt-y` (from a dock or empty pane; inside an editor `git::ToggleStaged` wins) |
| hide / show the thread list only | `cmd-alt-j` |

`cmd-?` pressed while the panel is focused returns to the editor but leaves
the panel open (`close_panel_on_toggle` is off), so it is not a hide key.
If `cmd-b` hits the wrong dock, you are in the other layout: check with
`workspace: use agentic layout` / `use classic layout` from the palette.
Layouts are described under [Panes, tabs, and docks](#panes-docks).

**External agents** (ACP) install from `zed: acp registry`; `settings.json`
has Claude (`claude-acp`, a registry entry), Codex (`codex-acp`, also a
registry entry), and omp, which isn't in the
registry, so it's a `custom` entry running `omp acp --approval-mode yolo
--config ~/.omp/agent/zed-models.yml`. All appear in the `+` menu and
sidebar like any thread. They bring their own auth and instructions (not
Zed's `AGENTS.md`) and ignore Zed profiles. **Terminal Threads** (`+` menu >
Terminal) are a plain terminal tracked as a thread, for the CLI itself
(sidekick-in-nvim). Claude can also run this way:
`agent.terminal_init_command: "claude"` types `claude` into every new
Terminal Thread (Ctrl-C it for a plain shell, or to run `omp`/`codex`). They
do not resume after a Zed restart ([details](#terminal-thread-restore)).
One-key launches: see [Adding your own bindings](#custom-bindings).

**Zed Agent's model list** can't be trimmed: Zed has no hide/allowlist
setting (`hidden_models`, zed#52347, was closed unmerged, and
`language_models.*.available_models` only adds or overrides). Instead
`agent.favorite_models` pins one zed.dev model per omp cycle model, so this
picker matches the [omp ladder](../plans/omp-model-ladder.md), at the top of
the selector (`alt-tab` cycles them, in Zed's order, not the settings order);
the full list stays below. Pinned as of 2026-11 (Zed price per 1M in/out):
Claude Haiku 4.5 ($1.10/$5.50), GPT-5.6 Terra ($2.20/$13.20), GPT-6.1 Sol
($2.20/$11), Claude Sonnet 5.5 ($2.20/$11), Gemini 4 Argon ($2.20/$11, intro
price until Nov 30, then $4/$20; the stand-in for Neon), Claude Opus 5.5
($4.40/$22) and Claude Fable 5.2 ($8.80/$44, hosted since Zed 1.29). That is
7 entries for 8 cycle models: Gemini 4 Hydrogen has no zed.dev pin because
Zed doesn't host it. Models
outside the omp cycle (GPT-6 Astra, Gemini 3.5 Flash, GPT-6 Luna,
GPT-5.3-Codex, GPT-5 mini and nano) are left out. Zed lags OpenRouter here:
Haiku 4.5 vs 5.5, GPT-5.6 Terra vs 6.1 Terra, GPT-6.1 Sol vs 6.2, and no
Gemini 4 Neon. **TODO:** replace Argon with Gemini 4 Neon
(`google/gemini-4-neon` on OpenRouter) once Zed hosts it.

**Auto-compaction is off** (`agent.auto_compact.enabled: false`) as a
workaround for a Zed 1.28.1 bug: compacting a Claude thread fails with
"unknown variant `between_tools`, expected one of `enabled`, `adaptive`,
`disabled`". Retry repeats the error and reloading the agent clears it. In
the log, every hit came from auto-compaction (Sonnet 5.5 at ~612k tokens);
normal turns were fine. Manual compaction likely fails the same way. With
it off, a long thread fails at the context limit instead, so start a new
thread before then. The 1.29.2 client still sends `between_tools` and its
release notes mention no fix; not retested. **TODO:** re-enable after a Zed
update fixes it (test by compacting a long Claude thread by hand).

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
  review multibuffer (`ctrl-shift-r`, `cmd-y`/`cmd-alt-z`; only for agents
  that write through Zed — omp does, the registry Claude ACP agent doesn't, see
  [Agent edits](#diff-review-agents)), follow the agent
  through files (`cmd-enter`), `@file`/`@symbol`/`@diagnostics` from Zed's
  own index, `cmd->` to quote a selection, image paste, a searchable
  transcript (`cmd-f`, `shift-pageup`), plan and tool cards, permission
  cards with "Always for <tool>/<pattern>", desktop notifications when the
  agent is waiting, Zed's MCP servers forwarded, thread history/archive —
  and one set of keys for every agent, Zed Agent included.
- **Terminal gets the whole CLI.** Slash commands, hooks, status line,
  plugins, skills, the CLI's current version, and your own config for it
  (this repo's `claude/` hooks and skills, omp's extensions) all run; over
  ACP only what the adapter forwards exists, and the adapter can lag the
  CLI. In exchange the thread is a
  terminal: scrollback instead of a transcript, no review loop (review with
  git: [Agent edits](#diff-review-agents)), no waiting/done signals in the
  sidebar.
- **Both** sit in the Threads Sidebar and can be renamed and cycled.
- **Restore after a Zed restart differs.** ACP threads go to Thread History
  and can be reopened, subject to the adapter's session support (open bugs
  zed#54750, #58887: external ACP threads loading empty or losing their
  `session_id`; not checked against `omp acp`). A Terminal Thread comes back
  as a fresh shell (here running a new `claude`), not as the agent session.
  See
  [Terminal Threads after a restart](#terminal-thread-restore).

<a id="claude-acp-subscription"></a>
**Claude on a subscription over ACP.** `claude-acp` (registry entry
"Claude Agent", the ACP adapter for Anthropic's Claude Agent SDK) works on a
Claude Pro/Max subscription directly in an ACP thread; the terminal `claude`
CLI is not required. Install it from `zed: acp registry`, open a Claude Agent
thread, and sign in with `/login` using your Claude account (not an API key,
which bills the API instead). Confirmed working on this machine. Zed's
[External Agents docs](https://zed.dev/docs/ai/external-agents#claude-agent)
and [Use an Existing Subscription](https://zed.dev/docs/ai/use-an-existing-subscription)
agree. Zed's May 2026 blog post saying the terminal was the only
subscription route is superseded: Anthropic paused the announced billing
split, and as of 2026-11 its
[help article](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan)
says Agent SDK usage signed in with a plan still draws from subscription
limits. That can change; if ACP usage starts billing separately, fall back
to a Terminal Thread. `settings.json` sets `default_config_options` to
`model: sonnet` and `mode: bypassPermissions` (no approval prompts).

Rule of thumb: ACP for Zed Agent, Codex, and Claude when the in-editor
review loop or transcript UI is the point; Terminal Threads for a harness
you have customised and want the whole CLI for (Claude hooks/skills, omp).
Zed profiles, Skills, and `AGENTS.md` apply to neither — external
agents read their own instruction files.

<a id="mcp"></a>
### MCP in Zed and Terminal Threads

Zed Agent connects to the servers under `context_servers` in Zed settings.
Zed also forwards enabled server definitions when it opens or loads an
Agent Client Protocol (ACP) session. `omp acp` (verified on 18.22.0) mounts
those definitions instead of discovering servers from `~/.omp/agent/mcp.json`
or other CLI configs. A Terminal Thread is just a shell: `omp` launched
there uses its normal [terminal MCP discovery](omp.md#mcp).

To give omp an MCP server in Zed, add it to `context_servers` and open a
new omp thread after Zed picks up the change. `enabled: false` in Zed
prevents forwarding. Omp's ACP `/mcp list` reads omp's files, not the live
tool list; `/mcp reload` does not ask Zed to resend server definitions.

For HTTP servers, Zed forwards the URL and configured headers, not its
native OAuth session. `omp acp` can reuse a grant from terminal omp for the
same URL and profile if no static Authorization header is set. If it
expires, reauthorize in terminal omp and open a new ACP thread. Do not put
tokens in tracked Zed settings.

This checkout ships [Tabularis](../README.md#mcp-integration) as its only
Zed context server.

<a id="terminal-thread-notifications"></a>
### Terminal Thread notifications

A bell (BEL) from an unfocused Terminal Thread gives the same pop-up as an
ACP thread (`agent.notify_when_agent_waiting`; the sound follows
`agent.play_sound_when_agent_done`, default `never`). It has no caption line
and only one pop-up fires per thread until you focus it. For Claude, the
stowed `terminal-bell.sh` hook rings the bell the moment a turn ends or a
prompt appears and puts the reason in the terminal title (`✓ Finished`,
`⚠ Needs permission: Bash`). A thread renamed in Zed keeps only that leading
glyph. Details and gaps against omp's ACP pop-ups:
[plans/zed-claude-stop-bell.md](../plans/zed-claude-stop-bell.md); README →
Claude Code.

<a id="threads-sidebar"></a>
## Threads sidebar

Every thread across open projects, grouped by project. Settings:
`agent.threads_sidebar.position`, `.default_width` (222 here), `.auto_open`.

| binding | action | what it does |
|---|---|---|
| `cmd-alt-j` | `multi_workspace::ToggleWorkspaceSidebar` | show/hide the sidebar. Showing it also moves focus into it; hiding it from inside returns focus to where you were |
| `cmd-alt-;` | `multi_workspace::FocusWorkspaceSidebar` | **focus it and come back** — see below |
| `up` / `down` (`ctrl-p` / `ctrl-n`) | `menu::SelectPrevious` / `SelectNext` | move through threads |
| `left` / `right` | `menu::SelectParent` / `SelectChild` | collapse / expand a project group |
| `enter` / `space` | `menu::Confirm` | switch to the thread |
| `cmd-f` | `agents_sidebar::FocusSidebarFilter` | fuzzy-filter thread titles |
| `cmd-n` | `agents_sidebar::NewThreadInGroup` | new thread in the selected project |
| `shift-r` | `agent::RenameSelectedThread` | rename |
| `shift-backspace` / `cmd-shift-backspace` | `agent::ArchiveSelectedThread` / `RemoveSelectedThread` | archive to history (running threads must finish first) / delete |
| `cmd-g` | `agents_sidebar::ToggleThreadHistory` | all threads, all projects, chronological; `backspace` un-archives, hover-trash deletes |

The waiting triangle on a thread marks a pending permission prompt and,
since 1.29, an unanswered agent input form too (ACP elicitation, such as
omp's plan-approval card). Zed Agent titles new threads itself;
`agent.auto_generate_thread_titles: false` (1.29+) leaves them untitled
until you run "Regenerate Thread Title" or rename.

<a id="sidebar-focus"></a>
**How `cmd-alt-;` works** (read from `multi_workspace.rs` at the `v1.29.2`
tag). It is a two-state toggle with a one-slot memory, not a cycle through
recent panels:

- **Focus is elsewhere** (message box, editor, terminal, any panel): it
  remembers the exact widget that has focus, opens the sidebar if it was
  hidden, and focuses the sidebar.
- **Focus is already in the sidebar**: it hands focus back to the remembered
  widget. If nothing was remembered, it falls back to the active editor pane.

So from the message box, `cmd-alt-;` lands on the thread list and a second
press returns to the half-typed message, cursor intact. Notes:

- Only one slot. Press it from the editor, then again from the sidebar, and
  you return to the editor; it never remembers more than the last place you
  left.
- If the sidebar was hidden, `cmd-alt-;` opens it and leaves it open after
  you return. Use `cmd-alt-j` from inside it to hide it again.
- It is distinct from `cmd-alt-j`: that one is show/hide (and happens to
  focus the sidebar when it opens). Choose `cmd-alt-;` to peek and return,
  `cmd-alt-j` to change layout.
- `enter` on a thread switches to it. Focus then lands in that thread, and
  the remembered slot still points at the old widget, so the next
  `cmd-alt-;` goes to the sidebar, not back to the old thread. Untested.

**`ctrl-tab` vs `cmd-alt-;`.** `ctrl-tab` opens the MRU thread switcher and
`ctrl-shift-tab` opens it starting from the last entry; it needs no visible
sidebar. Hold-`ctrl`-and-release behavior is assumed from the tab-switcher
analogy, not verified. `cmd-alt-;` is for browsing the full grouped list,
filtering with `cmd-f`, renaming, archiving, or starting a thread in a
specific project.

Mouse-free loop: `cmd-alt-;`, `down`/`up`, `enter`, read, `cmd-alt-;`
again — or skip the sidebar and `ctrl-tab` from inside a thread. To
**cycle threads directly** there is no default key, but the actions exist:
`multi_workspace::NextThread` / `PreviousThread` (and `NextProject` /
`PreviousProject`). `zed/.config/zed/keymap.json` binds `alt-]` / `alt-[` to
the first two under the `AgentPanel || ThreadsSidebar` context, so they work
from the message box and the sidebar but still type `‘` / `“` in editors
(see [`docs/zed-vim-keymap.md`](zed-vim-keymap.md#ai)). Tested working from
the message box in a live Zed (2026-11-14); that editors still type `‘` / `“`
is read from the keymap contexts, not tried.

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
  `always_deny` blocks silently, but the only rules cover the `edit_file` and `write_file` tools (case-insensitive path match: `\.env`, which also hits `.envrc`/`.env.example`, and `*.pem`/`*.key`); terminal, read, move/copy/delete and fetch are unguarded, so a shell command can still read or write those files. Untrusted folders open in restricted mode (`session.trust_all_worktrees: false`), where the agent has no write or terminal tools. Avoid
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
  `"args": ["acp", "--approval-mode", "yolo"]`. `shift-tab`
  (`agent::CycleModeSelector`) cycles an ACP agent's modes per thread.
  Claude in a Terminal Thread follows its own `~/.claude/settings.json`.

```jsonc
"agent": {
  "sandbox_permissions": { "allow_unsandboxed": true },
  "tool_permissions": {
    "default": "allow",
    "tools": {
      "edit_file": { "always_deny": [{ "pattern": "\\.env" }, { "pattern": "\\.(pem|key)$" }] },
      "write_file": { "always_deny": [{ "pattern": "\\.env" }, { "pattern": "\\.(pem|key)$" }] }
    }
  }
},
"agent_servers": {
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
| `ctrl-shift-d` | `git::Diff` | the ordinary project diff, from a thread's message box (context `AcpThread > Editor`) |
| `cmd-y` / `cmd-alt-z` | `agent::Keep` / `agent::Reject` | per hunk, in the review buffer or an inline agent diff |
| `alt-shift-y` / `alt-shift-z` | `agent::KeepAll` / `agent::RejectAll` | whole thread (also from the message box) |
| `alt-shift-u` | `agent::UndoLastReject` | bring back the last rejected hunk |

`"agent.single_file_review": true` shows agent hunks inline in each file
with the same keys, replacing its git hunks while review is active.
Checkpoints were removed in 1.27 — reject or git is the undo path. This
config sets `"toolbar": { "agent_review": false }`, hiding the Keep/Reject
buttons in the editor toolbar; the "Reject All / Keep All" bar above the
message box has no setting, so `alt-shift-y` is the way to clear it. Which
agents' edits reach this buffer at all, and how to review the rest:
[Agent edits](#diff-review-agents).

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

Zed Pro vs OpenRouter token cost: [Background](#hosted-model-cost).

<a id="vim-mode"></a>
## Vim mode

`"vim_mode": true` (or `cmd-k cmd-v`, `workspace::ToggleVimMode`, bound in
`keymap.json`; palette: `workspace: toggle vim mode`); this repo ships it
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

**Differences from nvim:** `:e foo`, `:sp foo`, `:w foo` take paths from the
project root, not the current file's directory; `s`/`shift-s` are substitute unless you bind
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
  { "bindings": { "cmd-k cmd-r": "git::DiffBranch" } },          // global
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
  `alt-/` lists what can complete one, and the which-key.nvim-style popup
  (`"which_key": { "enabled": true }`, on in this repo) shows the same
  while you wait.
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
  argument shape was not verified against 1.29.2 — bind it through
  `Add Keybinding`, which fills in the accepted form, and check
  `dev: open acp logs` if a bound agent fails to start.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **Zed rewrites `settings.json`** through the stow symlink whenever you
  change a setting in its UI — run `git diff zed/` afterwards. The keymap
  editor does the same to `keymap.json`.
- **A tab can go stale if it has unsaved edits.** Zed reloads a buffer
  when its file changes on disk (git pull, an agent, a terminal) only while
  the buffer is clean; a buffer with unsaved edits is left alone, and
  restored unsaved buffers (`session.restore_unsaved_buffers`, Zed's
  default) survive restarts. A `●` on a tab you did not edit means it is
  stale: do not `cmd-s` it, which would write the old text over the file
  through the stow symlink. Run `editor: reload file`
  (`editor::ReloadFile`, reloads from disk) or close it with Don't Save.
  `settings.json` is the usual victim: Zed, git and agents all write it.
  This config sets `autosave` to `after_delay` 1000 ms (like nvim's
  auto-save.nvim, plus `autoread`/`checktime` there) so buffers rarely stay
  dirty. Known upstream issues:
  [#38109](https://github.com/zed-industries/zed/issues/38109)
  (out-of-sync buffers, closed), [#49162](https://github.com/zed-industries/zed/issues/49162)
  (ACP `readTextFile` can serve a stale buffer, open).

  **Agent edits and autosave** (read from the v1.29.2 source, not tested):
  ACP `write_text_file`, which omp uses, edits the buffer, records the edit
  for the review view, then saves it to disk at once, so agent edits are on
  disk before you review them with or without autosave. Reject restores the
  old text and saves again. Autosave adds nothing for those writes.
  Separately, that path formats the buffer first whenever the language's
  `format_on_save` is not `off`, with no autosave check, so omp's writes are
  formatted whether or not autosave is on. Zed defaults `format_on_save` on
  for Astro, Dart, EEx, Elixir, Elm, Go, GraphQL, HEEx, Kotlin, Rust,
  Starlark and Zig.

  **Your saves** (read from the v1.29.2 source, not tested): autosaves under
  `after_delay` skip `format_on_save`. `cmd-s` (`workspace::Save`) does not:
  it formats in those languages, even when the file is unchanged. Use
  `cmd-k s` (`workspace::SaveWithoutFormat`) to save without formatting, and
  `editor: format` (`cmd-shift-i`, like nvim's `<leader>cf`) to format on
  demand.

  **Policy here:** agent writes keep Zed's defaults, since omp's docs say
  formatting may change the text it writes, and the project's own formatter
  (gofmt, rustfmt, pre-commit, CI) is the source of truth. No per-language
  `format_on_save: "off"`: settings.json is global, so it would also switch
  off formatting in every other Rust or Go project. The only repo file this
  touches is `fixtures/animal.rs`, which isn't rustfmt-clean, so an agent
  write or a `cmd-s` could reformat it.
- **Codebook disappears from a language if you set `language_servers` for
  it without `"..."`.** The Codebook extension (installed by
  `auto_install_extensions`) attaches to every language it supports, but a
  per-language `language_servers` list replaces Zed's default server set, so
  any server you leave out stops running there. Today only `Nix` sets
  `language_servers` (`["nixd", "!nil", "..."]`), so Codebook works
  everywhere. When you add one, end the list with `"..."` (keeps defaults,
  Codebook included) or name
  `"codebook"` explicitly, e.g. `["pyright", "ruff", "..."]`. Symptom of a
  miss: no spelling squiggles or quickfixes in that language; check
  `dev: open language server logs`. Codebook's own config, ignore patterns
  and the `lsp.codebook.initialization_options` knobs are in its
  [README](https://github.com/blopker/codebook#configuration); the choice
  is recorded in [`plans/zed-spell-check.md`](../plans/zed-spell-check.md).
- **Terminal Threads restart as fresh shells.** The sidebar entry returns,
  the agent session does not; here `terminal_init_command` starts a new
  `claude`, so `/resume` inside it (or `omp -r` etc. from a plain shell in
  the right directory). Zed has planned per-thread resume
  but has no design or date
  ([details and patch options](#terminal-thread-restore)).
- **Closing a Terminal Thread with its `×` deletes it**; unlike an ACP
  thread it never reaches Thread History.
- **`cmd-alt-g r` is not "open the branch diff".** `git::ReviewDiff` only
  works from inside a branch diff and sends it to an agent thread; open the
  diff itself with `git: diff branch` (no default key).
- **Branch diffs use whatever `origin/<base>` you last fetched**, and
  `git.auto_fetch` is off here. Fetch before reviewing a PR.
- **Closing docks:** `cmd-w` closes the tab, not the dock (1.22+) — use
  `ctrl-alt-w`. `cmd-?` toggles focus, not visibility; hide with
  `cmd-r`/`cmd-b` or set `close_panel_on_toggle`.
- **Overloaded keys:** `shift-escape` zooms, but expands the git commit
  editor in the commit box. `alt-tab` accepts edit prediction (editor), cycles
  favorite models (thread), generates a commit message (git panel). `cmd-y`
  is stage-and-next (editor), keep-hunk (agent review), allow-once
  (permission prompt). `cmd-alt-y` is toggle-all-docks, but toggle-staged
  on an editor hunk and allow-always in a thread. `cmd-ctrl-right` /
  `cmd-ctrl-down` select syntax nodes, but accept the next word / line of
  an edit prediction while one is showing.
- **`ctrl-space` needs the macOS input-source shortcut disabled** (System
  Settings > Keyboard > Shortcuts > Input Sources) or completions never open.
- **`cmd-ctrl-d` opens the macOS dictionary** instead of
  `editor::SelectPrevious`; the default keymap's comment carries a
  `defaults write` fix.
- **`vim_mode` contexts only exist on `Editor`:** a binding scoped
  `Workspace && vim_mode == normal` is silently dead.
- **Text threads and the Rules Library are gone** (replaced by Skills and
  `~/.config/zed/AGENTS.md`); old docs and blog posts still mention them.

<a id="background"></a>
## Background notes

Research and open checks behind the sections above; each is linked from
where it applies.

<a id="diff-review-untested"></a>
### Untested in the app: reviewing changes

Claims in [Reviewing changes](#diff-review) still to check in a running
Zed. Per item: fix that text if reality differs, then delete the item; note
the date and Zed version in the commit message.

**Uncommitted**

- [ ] **Project diff keys:** `cmd-y` stages and moves on, `cmd-alt-z`
  reverts, `cmd-enter` commits from the diff.
- [ ] **Staged / unstaged views:** `git: view staged changes` shows only
  staged hunks; right-clicking a file in the git panel offers both views.

**Branch diff**

- [ ] **Contents:** on a feature branch with an uncommitted edit, the tab
  reads `Changes since origin/main` and shows the commits plus the edit.
- [ ] **Matches GitHub:** on a pushed PR with a clean tree, the same files
  as "Files changed".
- [ ] **Changing the base:** `Base:` re-bases the view;
  `git: compare with branch` opens the same picker.
- [ ] **No stage/restore:** no hunk buttons, `cmd-y` / `cmd-alt-z` do
  nothing, typing edits the real file.
- [ ] **File list:** `cmd-shift-b` lists the branch diff's files.
- [ ] **Git panel branch mode:** `git panel: show branch changes` lists the
  same files as `git: diff branch`; `enter` opens the diff at that file;
  "Compare Against Base" changes both; no stage checkboxes.
- [ ] **Review Diff:** the button and `cmd-alt-g r` open a thread with the
  diff attached and the prompt sent; note which agent it picks.
- [ ] **Last N commits:** `git branch -f review-base HEAD~3`, compare with
  `review-base` → exactly those 3 commits plus uncommitted edits.
- [ ] **No default branch:** without `origin/HEAD`, `main`, or `master`,
  `git: diff branch` opens the uncommitted diff.
- [ ] **`git: toggle diff base`:** `git: diff` becomes the branch diff and
  the gutter follows; `git diff zed/` shows `diff_base`. Toggle back and
  discard.

**PRs**

- [ ] **Walkthrough:** a PR into a non-default branch, fetched and compared
  with `origin/<base>`, matches the PR's file list.
- [ ] **Stale base:** skipping the fetch after a rebase onto newer base
  commits shows those commits in the diff.
- [ ] **`@` branch diff:** a thread's `@` menu lists it; record the label.
- [ ] **No review comments:** hovering a hunk shows no add-comment button.

**Agent edits**

- [ ] **Zed Agent:** an edit appears under `ctrl-shift-r` and `cmd-alt-z`
  rejects it; with `agent.single_file_review` on, the controls appear in
  the file.
- [ ] **omp ACP thread:** an edit appears under `ctrl-shift-r`; reject
  restores the file.
- [ ] **Registry Claude ACP agent (`claude-acp`):** the edit lands on disk and the review buffer stays
  empty.

**Display**

- [ ] **Split toggle coverage:** `editor: toggle split diff` works in
  branch, staged, and commit diffs; `diff_view_style: "unified"` sets each
  one's default.

<a id="terminal-thread-restore"></a>
### Terminal Threads after a restart

**What happens.** When the project reopens, Zed recreates each open Terminal
Thread's sidebar entry with a fresh shell. The agent process, scrollback,
and any half-typed prompt are gone. Zed 1.29.2 stores only a title, custom
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
3. Run the resume command for the CLI you were using. Here the restored
   thread has already started a fresh `claude` (`terminal_init_command`):
   use `/resume` in it, or Ctrl-C it first for another CLI.

   | CLI | latest session here | pick from a list | exact session |
   |---|---|---|---|
   | omp | `omp -c` | `omp -r` | `omp -r <id-prefix>` |
   | claude | `claude -c` | `claude -r` | `claude -r <session-id>` |

   Flags are from each CLI's `--help`. `claude -c` is documented as the most
   recent conversation *in the current directory*; omp stores sessions in
   per-directory folders under `~/.omp/agent/sessions/`.
4. omp after a crash or an update that interrupted a running turn:
   `omp --restore` resumes like `-r`, then continues the unfinished turn and
   its subagents.

**Several threads in one project:** `-c` gives every thread the *same*
latest session. Use the picker (`-r`) instead and choose a different session
in each thread. Zed does not record which thread had which session, so the
picker's titles and timestamps are the only clue. That missing mapping is
what `ZED_TERMINAL_THREAD_ID` (below) would supply.

#### Automating it

Only `terminal_init_command` is set here, and as a launcher, not for
resume; none of the resume options was tried in a running Zed. Options,
easiest first:

- **`agent.terminal_init_command`** (shipped; `"claude"` here). Zed types
  the command into every new *and* recreated Terminal Thread. As set, a
  recreated thread starts a fresh `claude` session; `/resume` inside it
  picks the old one. A resume command (`"claude -c"`, `"omp -c"`) is fine
  with one thread per project; with several, they all resume the same
  session. It also fires for threads you wanted as plain shells.
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

**Patch options**, none merged into Zed 1.29.2:

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

<a id="hosted-model-cost"></a>
### Zed Pro vs OpenRouter tokens

Zed Agent can run models through Zed (`zed.dev`, the provider
`agent.default_model` uses here) or an OpenRouter key (prepaid credits). Zed's
hosted models bill list price **+10%** and need Zed Pro ($10/month, includes $5 of
token credit); OpenRouter bills list price with a **5.5%** fee on credit
purchases ($0.80 minimum). Pro is also what unlocks unlimited Zed edit
predictions (the `zed` provider above), so the comparison depends on whether
you'd pay for Pro anyway. Per month, with `S` = list-price token spend:

| route | cost |
|---|---|
| OpenRouter | `1.055 × S` |
| Zed Pro, tokens only | `5 + 1.1 × S` (above the $5 credit) |
| Zed Pro, already paying for edit predictions | `1.1 × S − 5` extra |

- **Tokens alone:** OpenRouter is cheaper at every spend level.
- **Pro for edit predictions anyway:** Zed's tokens are cheaper than
  OpenRouter while `S` is under about **$111/month** (`0.045 × S < 5`). Above
  that, OpenRouter wins again.
- **Best with Pro already paid: hybrid.** Zed costs 4.5% more per token at
  every spend level; the $5 credit is a fixed monthly rebate, not a
  per-token discount. Spend the first ~$4.55 of list-price usage on Zed's
  hosted models (set the spend limit to $0 so overage never bills), then
  switch to the OpenRouter key. That saves a flat ~$4.80/month at any spend,
  where Zed-only shrinks to zero at $111 and goes negative after. The credit
  only covers models Zed hosts, used in Zed's own agent, inline assist, and
  commit messages (not omp threads).
- **Small top-ups:** the $0.80 minimum makes a $5 OpenRouter top-up a 16%
  fee, worse than Zed's 10%; $10 is 8%.
- Zed's spend limit (default $10 of overage, settable to $0) is postpaid and
  billed in arrears; an OpenRouter balance is already a hard cap.

Prices from zed.dev's [Plans & Pricing](https://zed.dev/docs/account/plans-and-pricing)
and OpenRouter's [FAQ](https://openrouter.ai/docs/faq.md#pricing-and-fees),
checked 2026-11-15; re-check before relying on the break-even.
