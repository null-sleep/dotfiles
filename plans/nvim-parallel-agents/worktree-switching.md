# Switching git worktrees inside one nvim

Research and scoping only. Nothing here is built. This doc covers the
mechanics of one nvim, opened at a repo's main root, switching between that
repo's git worktrees so that cwd, file tree, pickers, buffers, LSP, git
tools, statusline and terminals follow the active worktree. It feeds the
parallel-agents design, where agent CLIs run in nvim terminal buffers, one or
more per worktree.

- **Written:** 2026-11-22, against nvim 0.12.6, gopls v0.24.0, and the
  plugin versions pinned in `nvim/.config/nvim/nvim-pack-lock.json`.
- **The real repo:** a large Go service repo with long-lived nested
  worktrees under `.worktrees/` and a make-based worktree setup (the make
  target creates the worktree, allocates a port offset, copies local
  configs, installs deps and allows direnv). There are eight Go modules and
  no `go.work`. The worktrees are slots: set up once, then reused across
  branches.
- **Sibling docs, not repeated here:**
  - [`isolation-analysis.md`](isolation-analysis.md) picks the topology.
    Its leaning is model 2a ("switch in place": one nvim, one active
    worktree, global cwd, open files follow) on top of 4a (agents in any
    worktree, grouped rows, explicit spawn cwd). This doc is the mechanics
    of 2a, with 2b (tab per worktree) as the fallback it names.
  - [`zed-feature-survey.md`](zed-feature-survey.md) section 4 and
    [`zed-design-lessons.md`](zed-design-lessons.md) section 9 cover Zed's
    worktree creation, hooks and archive. The "How Zed does it" section below
    goes deeper on switching only.
  - `sidekick-assessment.md` decides whether sidekick.nvim stays.
- **User decisions taken as given:** no per-agent diff tracking or action
  log (plain `git diff`, diffview and gitsigns with agents' changes mixed
  together are fine); terminal multiplexers and external agent managers are
  out of scope.
- **Method:** read the nvim config, the installed plugin sources
  (`~/.local/share/nvim/site/pack/core/opt/`), the nvim runtime, Zed's
  source (HEAD `596dfdcf32`) and the source of eleven worktree plugins
  (cloned to a scratch dir); ran read-only `git`, `rg`, `fd` and `ps` checks
  against the real repo. Claims marked [INFERENCE] come from reading code,
  not from running it.

## Contents

- [Summary](#summary)
- [How switching works today](#how-switching-works-today)
- [How Zed does it](#how-zed-does-it)
- [Switching models](#switching-models)
- [The switch itself: buffers, jumps, marks, sessions](#the-switch-itself-buffers-jumps-marks-sessions)
- [What must follow, per subsystem](#what-must-follow-per-subsystem)
- [Nested layout gotchas](#nested-layout-gotchas)
- [Plugin survey](#plugin-survey)
- [Creating and removing worktrees from nvim](#creating-and-removing-worktrees-from-nvim)
- [Hand-off to agents (sketch)](#hand-off-to-agents-sketch)
- [Recommendation](#recommendation)
- [Open questions](#open-questions)

## Summary

- **Most of the config already follows a `:cd`**, because it resolves roots
  per buffer (gitsigns, diffview, lualine `branch`, conform, gopls's
  `root_dir`) or reads `getcwd(0)` at call time (snacks pickers, sidekick
  spawns, toggleterm spawns, nvim-lint, dap's `${workspaceFolder}`). LSP
  needs no restart: swapping buffers to the new worktree's paths makes them
  attach to that worktree's clients.
- **What does not follow** is a short, concrete list: nvim-tree's root and
  its git-status cache, neogit's module-level repo, neotest-golang's root
  cache, persistence's session key, the window title, existing terminals,
  the process environment (direnv), and `ai_context.ref`'s paths.
- **Recommendation:** a small owned module (`worktree.lua`, a few hundred
  lines) over any plugin. It does a global `:cd`, swaps the current file to
  its counterpart, restores the target worktree's remembered working set,
  unloads the old worktree's clean buffers, emits `User WorktreeSwitched`,
  and lets each module subscribe. Add a reaper for idle LSP clients, a
  per-worktree environment from `direnv export json`, and a snacks picker
  that delegates creation to the repo's own make target.
- **No existing plugin is safe for the nested layout and this config.** The
  survey found that most use unanchored string-prefix matching that misfires
  when the main root is a prefix of every worktree path, none handles LSP,
  and Juksuu's (the snacks-native one an earlier plan favoured) deletes every
  file buffer on switch.
- **Keep the nested layout.** rg, fd, snacks and gopls already behave at the
  main root. The gotchas it causes (parent `.ignore` inheritance, nvim-tree's
  ignored-dir shortcut, recent-file leakage, stacked `CLAUDE.md`) each have a
  small fix, and moving the worktrees has real costs.

## How switching works today

There is no worktree code in the config. What exists:

- **Neogit's worktree popup** (`<leader>Gw`, `gitui.lua:50`) can create,
  delete and "visit" worktrees. Its visit and create actions call
  `nvim_set_current_dir`, a global `:cd` (`neogit/lua/neogit/buffers/status/init.lua:291-305`),
  and only work while a status buffer is open. Its default new-worktree path
  is a sibling of cwd (`popups/worktree/actions.lua:15-18`), not
  `.worktrees/`. Nothing else in the config reacts beyond the generic
  `DirChanged` handlers below.
- **`DirChanged` handlers that exist:**
  - `session.lua`: stops persistence if the new cwd is a temp dir.
  - `titling.lua`: recomputes the project name as the basename of
    `vim.fs.root(0, '.git')` of the *current buffer* (not the cwd). In a
    nested worktree that is `<name>`, not the repo, and if the current buffer
    still belongs to the old worktree the title keeps the old name.
- **Manual `:cd .worktrees/<name>`** works for pickers and new terminals,
  leaves everything else stale.
- **Option 0, a fresh nvim per worktree,** is the documented baseline in the
  upstream `git-worktree-nvim-plugin.md`. That plan stopped at "research /
  not started"; it compared five plugins by README and leaned to Juksuu's
  `worktrees.nvim` (snacks-native) or afonsofrancof's (zero deps) if
  switching became frequent. The source reading below changes that
  conclusion.

## How Zed does it

Zed solves the same problem as an editor, so its switch path is worth
reading closely. Paths are relative to Zed's repo at HEAD `596dfdcf32`.

### Switching opens or reuses a workspace in the same window

- The picker (`crates/git_ui_core/src/worktree_picker.rs`, `confirm`
  ~L978) has four row kinds: create from current branch, create from the
  default branch, an existing worktree, and create with a typed name. On an
  existing worktree, Enter dispatches a switch and the secondary confirm
  opens it in a new window instead. The current worktree cannot be switched
  to or deleted (`is_current`, ~L1031 and ~L1173). Delete and force-delete
  are in-picker actions.
- `handle_switch_worktree` (`crates/git_ui_core/src/worktree_service.rs:900`)
  captures the source workspace's state
  (`Workspace::capture_state_for_worktree_switch`,
  `crates/workspace/src/workspace.rs:2689`: dock structure, every open
  file's absolute path, the active file, the focused dock), then calls
  `do_switch_worktree` (L1114), which calls `open_worktree_workspace`
  (L1153).
- `open_worktree_workspace` asks the window's `MultiWorkspace` to
  `find_or_create_workspace(paths, ..., OpenMode::Add)`
  (`crates/workspace/src/multi_workspace.rs:1119`):
  - If a workspace with exactly those root paths is already held in the
    window, it is activated as is (L1136, and `find_or_create_local_workspace`
    L1229-1252).
  - Otherwise `Workspace::new_local` builds one, restoring that root set's
    serialized layout from Zed's DB (`workspace.rs:2282`,
    `workspace_for_roots`).
  - It then waits for the initial file scan and each repository's
    `barrier()` (worktree_service.rs L1241-1262), propagates trust from the
    main worktree, and activates.
- **Open files carry over only on create.** `transfer_state =
  is_creating_new_worktree && activate` (L1178). On a foreground create, each
  previously open path is remapped with a longest-prefix match of old root
  to new root (L1283-1304) and opened unfocused, and the dock layout is
  copied. On a switch to an existing worktree, nothing is remapped: you see
  that workspace's own retained or restored state.
- **The old workspace stays alive when agents are enabled.**
  `MultiWorkspace::activate` (L1347) pins the outgoing workspace if
  `multi_workspace_enabled` (L444: AI not disabled and the agent setting
  on), otherwise detaches it (`detach_workspace`, L1443). Each workspace owns
  its own `Project`, so its own language servers, project panel, git panel
  and terminal panel [INFERENCE for the panels: they are per-`Workspace`
  panels]. With agents on, every visited worktree keeps its servers running.
- **Grouping.** `ProjectGroupKey::from_project`
  (`crates/project/src/project.rs:6887`) keys a workspace by its main
  worktree paths, so linked worktrees group under the main repo in the
  sidebar. A repository is linked when its repository dir differs from its
  common dir (`crates/project/src/git_store.rs:6249`).
- **Nested ignored dirs cost nothing.** Zed's scanner does not scan ignored
  directories until they are expanded (`crates/worktree/src/worktree.rs`,
  comments at ~L2912 and ~L4004, `should_scan_directory` ~L6307), so a
  gitignored `.worktrees/` inside the main root is not indexed by the main
  workspace.
- **Create hook.** `run_create_worktree_tasks` runs after the new workspace
  opens (worktree_service.rs L1377). The workspace's environment was already
  read and cached by then, which a private plan in this repo found makes
  env written by the hook invisible to agents in that workspace.
- The picker, create targets (current branch, default branch, named), the
  detached-HEAD default and archive are covered in the sibling Zed docs.

### What transfers to nvim

- **Per-worktree retained state.** Zed's real answer to "what happens to my
  open files" is that each worktree keeps its own. In nvim that is either a
  tab per worktree (2b) or, in 2a, a remembered working set per worktree
  that the switch restores. The recommendation below takes the second.
- **Reuse, don't reopen.** Switching back to a worktree should find its
  existing state, not rebuild it.
- **Longest-prefix remap.** Zed's remap picks the deepest matching old root.
  That is exactly the rule the nested layout needs, where the main root is a
  prefix of every worktree path.
- **Wait for readiness before spawning.** Zed waits for the repo barrier
  before anything uses the workspace. The nvim analogue is "load the
  worktree's environment before spawning an agent there".
- **Group by common dir**, with a worktree chip per row.
- **Retention is a policy, tied to agents.** Zed keeps every visited
  workspace alive only when agents are on. nvim needs an explicit LRU or
  idle reaper for LSP clients instead.
- **Guard rails:** the current worktree is not a switch or delete target;
  the main worktree is never deleted.

### What does not transfer

- **Isolation of everything per workspace.** Zed gives each worktree a
  separate project, buffer set, panels and settings. nvim has one global
  buffer list, one nvim-tree instance, one neogit repo and one process
  environment. Tabs isolate only layout and cwd.
- **Several windows in one process.** Zed's "open in new window" is free; in
  nvim a second window is a second nvim (model 3).
- **Remap only on create.** Zed can afford it because the old workspace
  stays open. The user's 2a wants "same file, other worktree" on every
  switch, which suits long-lived slots where comparing branches is the point.

## Switching models

Four ways to point the editor at a worktree. The first three are in-process;
the fourth is the baseline.

### Global `:cd` (model 2a)

- One active worktree. `:cd <root>` changes the global cwd and clears the
  current window's local dir (`:help :cd`, "Clear any window-local
  directory").
- **Pros:** everything that reads `getcwd()` or `getcwd(0)` follows,
  including the process cwd. Only one set of things is "current". It matches
  the stated workflow and the isolation doc's leaning.
- **Cons:**
  - Windows with their own `:lcd` (neogit's status window sets one,
    `neogit/lua/neogit/lib/buffer.lua:1021-1024`; nvim-tree uses `:lcd` when
    you re-root from inside the tree, `actions.change_dir.global = false`)
    and tabs with a `:tcd` keep their old dir. The switch must reset them
    (`win_execute(win, 'cd ' .. root)` per window with `haslocaldir()`),
    except windows that deliberately carry an agent's cwd.
  - Old-worktree buffers, jumps and the alternate file need a policy (next
    section).
  - Implicit: `:tcd`/`:lcd` set by a plugin later silently change sidekick's
    spawn cwd (isolation doc). Spawning with an explicit cwd removes that.

### Tab-local `:tcd` (model 2b)

- A tab per worktree, each with its own cwd. Switching worktree is switching
  tab. Several worktrees are live at once.
- **Pros:** the closest match to Zed's retained workspaces; no buffer swap at
  all; each tab keeps its own layout.
- **Cons:**
  - Buffers are still global: buffer pickers, `recent`, and alternate files
    mix worktrees, with identical tails.
  - `DirChanged` fires on every tab switch (`v:event.changed_window`), so
    every cwd-reactive module re-runs on each `gt`.
  - nvim-tree is a single explorer shared by all tabs (`nvim-tree/core.lua:11,41-43`);
    with `sync_root_with_cwd` it re-roots on each tab switch rather than
    keeping a tree per tab.
  - neogit's repo is module-global (below), so a popup in tab B can act on
    tab A's repo.
  - Every open tab's LSP clients are live, which on the real repo is about
    1 GB or more per worktree for gopls alone.
  - The agent view is itself a tab and would compete with worktree tabs.
  - persistence names the session file after one cwd; whether mksession
    restores each tab's `:tcd` is unverified (isolation doc open question 10).
- **Prior art:** aero.nvim (below) is built exactly this way: `$tabnew`,
  `:tcd`, and a per-worktree remembered buffer set
  (`lua/aero/tabs.lua`, `M.enter`). snacks's `projects` source also has a
  `<c-w>` action that just runs `tcd` (`snacks/picker/config/sources.lua:905-910`).

### Window-local `:lcd`

- Not a switching model, but useful in one place: a window that shows an
  agent's terminal could carry that agent's worktree as its `:lcd`, so a
  picker opened from it searches the agent's tree, and sidekick's context
  `ctx.cwd = getcwd(win)` (`sidekick/cli/context/init.lua:209`) matches the
  agent. The agent view's main window shows different agents in turn, so it
  would have to re-`lcd` on every row change. Treat as optional polish.

### A fresh nvim per worktree (model 3, Option 0)

Correct by construction, zero code, loses the session and the single agent
overview. It stays the escape hatch for rare clean-slate switches; the
isolation doc covers it.

### Comparison

| Aspect | `:cd` (2a) | `:tcd` (2b) | fresh nvim |
|---|---|---|---|
| Worktrees live in editor | 1 | 1 per tab | 1 per process |
| Buffer swap needed | yes | no | no |
| Duplicate buffer tails | only if old kept | yes | no |
| LSP clients alive | active + LRU | every tab | per process |
| nvim-tree | re-root on switch | shared, re-roots per tab | own |
| neogit | re-target on switch | stale across tabs | own |
| `DirChanged` frequency | per switch | per tab change | n/a |
| Session keying | needs a policy | one file, all tabs | as today |
| Code needed | module + hooks | module + per-tab fixes | none |

## The switch itself: buffers, jumps, marks, sessions

### Ownership: which worktree does a path belong to

Every step below needs "which worktree owns this path". In the nested layout
the main root is a string prefix of every linked worktree, so the answer is
the **longest** worktree root that is a prefix of the path followed by `/`
(Zed's rule). Getting the list from `git worktree list --porcelain` once per
switch is cheap. Most surveyed plugins get this wrong (see the survey).
`git -C <dir> rev-parse --show-toplevel` per buffer is also correct but costs
a process per buffer.

### What to do with open buffers

Options, from least to most work:

1. **Leave them.** Old buffers stay open and listed. Simple, but every
   picker and `:ls` now mixes two checkouts with identical tails, and those
   buffers keep the old worktree's LSP clients alive.
2. **Wipe all file buffers** (Juksuu's plugin, RayIci's). Clean, but loses
   every buffer and fails partway on a modified one.
3. **Remap the current buffer only** (ThePrimeagen, polarmutex,
   afonsofrancof, awerebea): open the same relative path in the new
   worktree, else a fallback. Other buffers are left stale.
4. **Remap every buffer** (mitubaEX, and Zed on create). Rename-in-place
   (`nvim_buf_set_name` + `edit!`) is dangerous: it discards unsaved edits,
   confuses undo history and keeps LSP attached with the old root.
   Opening the counterpart as a new buffer and dropping the old one is safe.
5. **Per-worktree working set** (Zed's switch semantics, aero.nvim,
   yongjohnlee80's plugin). On leaving worktree A, remember A's buffers and
   which file each window showed. On entering B, restore B's remembered set.
   On a first visit to B there is nothing remembered, so fall back to option
   4.

**Proposed default: 5, with the current window always remapped.** That
merges both Zed behaviours: the window you are looking at jumps to the same
file in the other worktree (the "same file, other branch" comparison slots
are for), and everything else is B's own working set. Concretely:

1. `:wall`. With `auto-save.nvim` saving on `BufLeave`/`FocusLost`
   (`autosave.lua`), modified buffers are already rare.
2. Snapshot A: listed file buffers owned by A, ordered by `lastused`, plus
   each code window's buffer and cursor.
3. `:cd` B, reset local dirs that pointed into A.
4. For each code window showing an A buffer: the counterpart path in B if it
   exists, else B's remembered file for that window, else B's last-used
   file, else open the file tree. Cursor comes back through the existing
   `"` mark restore (`autocmds.lua`).
5. Add B's remembered set as listed, unloaded buffers (`bufadd` plus
   `buflisted`; they load lazily).
6. A's clean buffers: unload and unlist (`:bdelete`). Marks and undo files
   survive, LSP detaches, and the reaper can stop A's clients. A's modified
   buffers (save failed): keep listed and warn, never block.
7. Fire `User WorktreeSwitched` with `{ from, to }`.

Special buffers (terminals, the agent view, nvim-tree, quickfix, help,
scratch) are never touched.

### Jumplist and alternate file

- The jumplist holds absolute positions, so `<C-o>` after a switch silently
  reopens a file in the old worktree (and re-attaches its LSP client). nvim
  has no API to filter a jumplist, only `:clearjumps`. Every surveyed plugin
  except mitubaEX clears it. **Default: `:clearjumps` in each window that
  was swapped**, configurable.
- The alternate file `#` may point at an unloaded A buffer; `<C-^>` then
  reopens it. Acceptable, or set `#` to the previous B buffer by editing it
  first. Low priority.

### Marks, undo, shada, quickfix

- **Undo:** `undofile` is on (`configs.lua:17`) and undo files are keyed by
  absolute path, so each worktree's copy of a file keeps its own history.
  This is another reason never to rename a buffer in place.
- **File marks and shada:** keyed by absolute path; uppercase marks into A
  still jump into A. Fine: they are explicit.
- **Quickfix and location lists:** entries carry buffer numbers or absolute
  paths into A. A quickfix list from A stays valid but points at A. Leave
  it; the qf history picker (`pickers/qfhistory.lua`) shows where each list
  came from.
- **`v:oldfiles`:** spans all worktrees. See the `recent` leak in the nested
  layout section.

### `DirChanged` as the fallback trigger

`:cd` fires `DirChanged` (pattern `global`). The module should also listen
to it, so a switch done by something else (neogit's visit, snacks's
`projects` `tcd`, a hand-typed `:cd .worktrees/x`) still runs the "adopt"
path: detect that the new cwd's owning worktree changed, then do steps 2 to
7. Modules subscribe to `User WorktreeSwitched`, not to `DirChanged`
directly, because it carries `from`/`to` and fires after buffers moved.

### Sessions per worktree

`session.lua` uses persistence.nvim with `branch = true`. persistence names
the file from `getcwd()` plus `%%<branch>` and saves only on `VimLeavePre`
(`persistence/lua/persistence/init.lua:11-21, 35-55`); it has no `DirChanged`
handling. Under 2a, quitting saves under the last active worktree, and the
next nvim started at the main root loads main's older session.

Options:

- **Save and load a full session on every switch** (RayIci's plugin, the
  upstream plan's `mini.sessions` recipe). `:mksession` here first needs the
  panels closed (`session.lua`'s `PersistenceSavePre` closes aerial,
  nvim-tree and grug-far), and sourcing a session runs `only`/`tabonly`,
  which closes agent terminal windows and the agent view tab mid-session.
  RayIci's plugin refuses to switch while any terminal job is live for this
  reason. Poor fit with agents in terminals.
- **Keep persistence for "the editor at quit", add a light per-worktree
  working-set store.** The working sets from step 2 above go to
  `stdpath('state')/worktrees/<hash of main root>.json` (files, last file,
  cursor, plus which worktree was active). persistence keeps saving at quit;
  on startup at the main root, the module can offer to re-enter the last
  active worktree. **Proposed.**
- Whether persistence's file should always be keyed by the main root (so
  restarting at the main root finds the latest state) or by the active
  worktree (as now) is open; `cleanup.lua`'s dead-branch pruning already
  copes with either.

## What must follow, per subsystem

For each: what the config does today, what goes wrong on a switch, and how to
make it follow. "Follows" means works with no change.

### cwd and local dirs

- Global `:cd` plus resetting `:lcd`/`:tcd` windows that pointed into the
  old worktree (above).

### File tree (nvim-tree)

- **Today:** `filetree.lua` sets `git.enable`, `update_focused_file.enable`,
  no `sync_root_with_cwd`. Defaults: `filters.git_ignored = true`, so the
  gitignored `.worktrees/` is hidden at the main root.
- **On switch:** the root stays at the old worktree.
- **Fix:** `sync_root_with_cwd = true` (its `DirChanged` handler covers all
  scopes, `nvim-tree/autocmd.lua:51-58`), or call
  `api.tree.change_root(to)` from the switch hook.
- **Gotcha, nested only:** nvim-tree short-circuits toplevel lookup for any
  path under a directory that a known project reports as ignored
  (`nvim-tree/git/init.lua:66-84, 178-183`). Once main's project is loaded
  with `.worktrees/` as `!!`, paths under `.worktrees/x` resolve to **main's**
  toplevel, so after re-rooting into a worktree its files get main's
  "ignored" status and may be hidden by `git_ignored` [INFERENCE, needs a
  test]. Fix: purge nvim-tree's git cache on switch
  (`require('nvim-tree.git').purge_state()`, an internal function; the
  public route is closing the tree and `require('nvim-tree.core').purge_all_state()`)
  before re-rooting.

### Pickers (snacks)

- **Follows:** `files`, `grep` and the filter's cwd use `getcwd(0)` or the
  process cwd at open (`snacks/picker/core/filter.lua:39`,
  `source/files.lua:156`); `git_*` sources use the git root of that cwd
  (`Snacks.git.get_root`, which handles a `.git` file).
- **At the main root:** `.worktrees/` stays out of `files` and `grep` even
  with this config's `hidden = true` (`picker.lua:296-318`), because it is
  both a dot-dir and gitignored; you need both `hidden` and `ignored` to
  descend. Flipping the "ignored" toggle in a picker at the main root floods
  it with every worktree (and their dependency dirs).
- **Leak:** `smart` and `recent` include `v:oldfiles`, and the cwd filter is
  a plain prefix test (`filter.lua:97`). At the main root, files you opened
  in `.worktrees/x` pass it. `<leader><leader>` (`keymaps.lua:189`,
  `filter = { cwd = true }`) therefore mixes worktrees. Fix: add
  `filter.paths = { [<main>/.worktrees] = false }` when cwd is the main root
  (snacks supports exclusion paths, `filter.lua:100-106`).
- Custom pickers already resolve per buffer: `pickers/gitstatus.lua` and
  `pickers/gotargets.lua` use the buffer's directory, `yank.lua` the
  buffer's toplevel.

### Buffers and the buffer picker

Handled by the switch policy. With old clean buffers unlisted, the buffer
picker shows only the active worktree plus any kept modified buffers. A
statusline marker for "this buffer belongs to another worktree" covers the
rest.

### LSP

- **Follows, mostly.** Roots are resolved per buffer. lspconfig's gopls
  `root_dir` is `vim.fs.root(fname, 'go.work') or ... 'go.mod' or ... '.git'`
  (`nvim-lspconfig/lsp/gopls.lua:87-101`); `vim.fs.root` matches a `.git`
  file, so a worktree file finds its own markers. nvim 0.12's default
  `reuse_client` reuses a client only if its workspace folders contain the
  new root (`runtime/lua/vim/lsp.lua:119-146`). After the buffer swap, new
  buffers attach to (or start) the new worktree's clients. **No restart is
  needed**, unlike yongjohnlee80's plugin, which stops and re-fires
  `FileType` because its buffers keep old roots.
- **Problem 1: clients pile up.** Clients for the old worktree keep running
  with zero buffers. Add a reaper: on `WorktreeSwitched` (and on
  `LspDetach`), stop clients whose root is owned by a worktree that is
  neither active nor in a small LRU (default: keep one previous worktree
  warm for quick switch-back), once they have no attached buffers.
- **Problem 2: one gopls per module.** In a multi-module repo with no
  `go.work`, every module dir is its own root, so nvim already starts a
  gopls per module touched, and per worktree after a switch. On the real
  repo one gopls covering the whole checkout (under Zed) was at about 1.2 GB
  RSS. Fix: a custom gopls `root_dir` returning the worktree toplevel when
  it has no `go.work`, so one process serves every module; gopls since
  v0.15 creates a view per module on demand inside one process [INFERENCE
  for the memory saving: views share the file cache, but each type-checks
  its own module graph]. Measure before and after.
- **Problem 3: an outer `go.work` captures nested files.** `go.work` is
  searched before `go.mod` at any distance, so a `go.work` at the main root
  but not in the worktree (for example an untracked one) makes every
  `.worktrees/x` Go file resolve to the main root and attach to main's
  gopls. Fix in the same custom `root_dir`: never return a dir above the
  file's own git toplevel (`vim.fs.root(fname, '.git')`).
- **Problem 4: module-cache jumps.** For files in `GOMODCACHE` or GOROOT,
  lspconfig reuses `clients[#clients].config.root_dir`, the most recently
  started gopls, which with several worktrees may be the wrong one
  (`gopls.lua:88-99`). Prefer the client attached to the buffer you jumped
  from.
- **Other servers:** ts_ls, eslint and pyright resolve per buffer the same
  way; whether a client rooted at the main root walks into `.worktrees/` is
  per server and unmeasured (isolation doc open question 1).
- **Env:** LSP servers inherit nvim's process env. gopls cares about
  `PATH`, `GOFLAGS`, `GOWORK`; if a worktree's direnv sets different ones,
  use `cmd` as a function (nvim 0.11+) to spawn with that worktree's env.

### Git tools

- **gitsigns: follows.** Per buffer: `rev-parse` from the file's dir, one
  repo object per gitdir (`gitsigns/git/repo.lua:540-557, 630-684`).
- **diffview: follows.** Picks the current file's repo first, then cwd
  (`diffview/vcs/adapters/git/init.lua:131-167`). From a non-file buffer it
  uses cwd, which is the active worktree after a switch. `-C=<dir>` targets
  another worktree explicitly.
- **neogit: does not follow.** Its repo is a module-level `lastDir`
  (`neogit/lib/git/repository.lua:184-202`), set only when Neogit opens with
  a dir; later popups reuse it. Fix: on switch, close any Neogit status
  buffer and open the next one with `:Neogit cwd=<root>`; for keymaps that
  open popups directly, pass `cwd`. Its own worktree visit does a global
  `:cd`, which the `DirChanged` fallback adopts.
- **Snacks lazygit:** cwd at launch, keyed by cwd; follows for new
  instances.

### Statusline and title

- lualine's `branch` is per buffer and handles `.git` files
  (`lualine/components/branch/git_branch.lua:204-224`). `filename` with
  `path = 1` is relative to `getcwd(0)`, so after a switch a kept buffer
  from another worktree shows as `.worktrees/x/...` (from main) or an
  absolute path.
- **Add** a worktree component: the active worktree's name, plus a warning
  marker when the current buffer is owned by a different worktree. Agent
  attention counts per worktree can live here later.
- **Title:** `titling.lua` should show `<repo>:<worktree>`, with the repo
  from `git rev-parse --path-format=absolute --git-common-dir` (its parent
  dir) and the worktree from the cwd's owner, refreshed on
  `WorktreeSwitched` rather than from the current buffer on `DirChanged`.

### Terminals (shells)

- toggleterm resolves `dir` at open (`toggleterm/terminal.lua:186-193`,
  default the process cwd), so **new** terminals follow. Existing ones stay
  where they are; `autochdir` would `cd` them on reopen, which is unsafe if
  a command is running. Snacks terminals are keyed by cwd, so they naturally
  split per worktree.
- **Proposed:** leave existing shells alone, tag each terminal with its
  owning worktree, and scope the float cycle and the bottom panel to the
  active worktree (one bottom terminal per worktree, like snacks's cwd key).
- An interactive shell picks up the worktree's direnv env from its own zsh
  hook on the first prompt. Non-shell jobs do not (next item).

### Process environment (direnv)

- **Today:** nvim has no direnv integration. It carries the env of the shell
  that launched it. Opened at the main root, that is the main checkout's
  env.
- **What goes wrong:** every job nvim starts directly inherits it: agent
  CLIs (sidekick uses `jobstart`), neotest `go test`, dap, run targets,
  formatter and linter processes, LSP servers. In a repo whose direnv sets
  per-worktree ports and container project names, an agent in a worktree
  that runs a container or database command acts on the **main** checkout's
  stack. This is the nvim form of the env-caching problem the private Zed
  plan hit.
- **Fix:** per-worktree env from `direnv export json` run with the worktree
  as cwd (direnv unloads the inherited dir's diff first). Cache per worktree;
  invalidate when `.envrc`, `.envrc.local` or the flake lock changes;
  serialize loads (a flake shell hook may write the shared `.git/config`).
  Load asynchronously on switch, and await it before spawning an agent in
  that worktree. Pass it as `env` to agent spawns, test and debug runs, and
  task terminals.
- **Open:** whether to also swap nvim's own `vim.env` on switch. It is the
  only way that tools nvim spawns implicitly (formatters, linters, LSP)
  follow, but a half-applied env swap is hard to reason about. Per-job env
  first.

### Formatters and linters

- conform: per file (`util.root_file` is `vim.fs.root` from the file's dir;
  gofmt and goimports take `$FILENAME`/`$DIRNAME`). Follows.
- nvim-lint: per-run cwd is `getcwd()` (`lint.lua:368`), so it follows the
  `:cd`. But golangci-lint's args are computed once at module load from
  `go env GOMOD` in the startup cwd (`nvim-lint/lua/lint/linters/golangcilint.lua:20-60`).
  In a multi-module repo it is already awkward at the main root; give the
  linter a per-buffer `cwd` (the module root) to make it independent of
  both.

### Test runner (neotest, neotest-golang)

- neotest handles `DirChanged` for global and tab scope and re-discovers
  adapters for the new dir (`neotest/client/init.lua:453-460`); it never
  drops old adapters.
- neotest-golang caches its first root in a module-level
  `primary_root_cache` and returns it for any path under it, never clearing
  it (`neotest-golang/lib/find.lua:12-18, 55-78`). If the main root is
  discovered first, every file under `.worktrees/x` maps to the main root's
  adapter tree. Fix: call
  `require('neotest-golang.lib.find').clear_root_cache()` on switch, then
  let neotest re-discover. Verify.
- Tests run with nvim's env unless given the worktree env (above).

### Debugging (nvim-dap, nvim-dap-go)

- `${workspaceFolder}` is `getcwd()` at launch (`nvim-dap/lua/dap.lua:384-389`),
  so it follows. dap-go's `./${relativeFileDirname}` configs are relative to
  the cwd and break when the file is in a different worktree from the cwd;
  after a proper switch they agree.
- The delve process and debuggee inherit nvim's env: pass the worktree env.
- `pickers/gotargets.lua` already resolves the module root from the buffer.

### Context sent to agents (`ai_context.ref`)

- `ai_context.ref` makes paths relative to `cwd or getcwd()`
  (`ai_context.lua:33`); sidekick's own context also uses the window's cwd.
  After a 2a switch, or with agents in other worktrees, a ref can name the
  same relative path in the wrong checkout and nothing errors (isolation
  doc, nested-layout item 8). Fix: compute refs relative to the **target
  session's** cwd; refuse, or send absolute with a warning, when the file is
  owned by a different worktree than the session.

### Watchers

- nvim-tree's git watcher watches the main `.git` dir, which agents in
  linked worktrees touch on every commit (`.git/worktrees/<name>`, refs).
  Probably cheap on macOS; unmeasured (isolation doc open question 9).
- Buffers from a worktree an agent is editing go stale; `autoread` plus
  `:checktime` on `FocusGained`/`BufEnter` already handles files on disk.

## Nested layout gotchas

Findings from the real repo (`.worktrees/` gitignored at the main root,
long-lived worktrees inside). Each has a small fix; together they are why
ownership must use the longest-prefix rule everywhere.

1. **rg and fd at the main root skip `.worktrees/` twice:** it is a dot-dir
   and gitignored. `rg --files`, `rg --files --hidden`, `rg --files --no-ignore`
   and `fd --type f --hidden` all list 0 files there. Only
   `fd --hidden --no-ignore-vcs` descends, and it lists about 360,000 files
   (every worktree's dependency dirs). A ripgrep config that adds `--hidden`
   still would not descend. Keep ripgreprc to `--type-add` lines, as it is.
2. **Parent `.ignore` files are inherited.** The main root has an untracked
   `.ignore` that un-ignores a few gitignored paths (local configs, a plans
   dir, local agent files). The worktrees have no `.ignore`, yet rg and fd in
   a worktree still show those paths, because both read ignore files in
   parent directories; `--no-ignore-parent` makes them disappear. This is
   the "config lookups fall through to the main checkout" effect from the
   isolation doc, confirmed for ignore files. Usually harmless here; with a
   sibling layout it would not happen.
3. **nvim-tree's ignored-dir shortcut** maps worktree paths to main's
   toplevel once main is loaded (subsystem section). Purge on switch.
4. **`recent` and `smart` at the main root** include files from
   `.worktrees/` because the cwd filter is a prefix test. Exclude the
   worktrees dir when at the main root.
5. **neotest-golang's root cache** maps worktree files to the main root if
   main was seen first. Clear on switch.
6. **gopls and an outer `go.work`** (not present today) would capture nested
   files. Clamp `root_dir` to the file's git toplevel.
7. **Stacked agent instruction files.** Claude Code loads `CLAUDE.md` (and
   `CLAUDE.local.md`) from its cwd and every parent directory, so an agent
   in `.worktrees/x` also reads the main checkout's copies, which may be
   from another branch [believed true from Claude Code's memory docs;
   verify, and check omp's `AGENTS.md` lookup]. In the real repo this is
   also why worktrees missing their own local agent file still get one.
8. **A main-root agent's scope covers every worktree.** Covered in the
   isolation doc; the worktree layer should make the main-root "home" agent
   visibly distinct.
9. **Neogit's worktree popup defaults to sibling paths** and global `:cd`.
   If it is used to create worktrees, type the `.worktrees/<name>` path, or
   better, use the repo's own creation flow.

### Should the worktrees move out of the main root?

- **What moving buys:** no prefix ambiguity (simpler ownership), no parent
  config or instruction-file inheritance, a main-root agent that cannot
  wander into slots, and gotchas 2 to 5 and 7 disappear.
- **What it costs:** the repo's worktree tooling, docs, agent guidance and a
  planned slot controller all assume `.worktrees/`; each moved worktree
  needs `git worktree move`, a fresh `direnv allow` (the allow list is keyed
  by path) and a rebuilt nix-direnv cache; and muscle memory.
- **Leaning: keep the nested layout.** The things that would be expensive
  to get wrong (pickers flooding, gopls double-indexing, Zed's scanner) are
  already fine at the main root, and the rest is a handful of local fixes.
  Revisit only if stacked instruction files turn out to mislead agents.

## Plugin survey

Eleven plugins were read at source level (clones in a scratch dir; nothing
executed). Dates and stars from the GitHub API on 2026-11-22. snacks.nvim
itself has no worktree source (no match in the installed copy or on GitHub
code search). fzf-lua has a built-in `git_worktrees` picker with a cd scope
option, but this config uses snacks.

| Plugin | Last commit | Stars | Deps | cd mode | Buffers on switch | LSP | Hooks | Nested-safe |
|---|---|---|---|---|---|---|---|---|
| ThePrimeagen/git-worktree.nvim | 2023-11 | 906 | plenary, telescope | cd, configurable | current buf only | none | `on_tree_change` | no |
| polarmutex/git-worktree.nvim | 2025-02 | 144 | plenary, telescope | cd, configurable | none unless hook added | none | create/delete/switch | no |
| Juksuu/worktrees.nvim | 2026-04 | 39 | plenary, snacks or telescope | cd, fixed | deletes all file bufs | none | before/after switch, add, remove | partial |
| afonsofrancof/worktrees.nvim | 2026-04 | 45 | none | cd, fixed | current buf, else `edit .` | none | create/delete/switch | yes |
| mitubaEX/git_worktree.nvim | 2026-06 | 4 | none, telescope optional | global cd | renames all, `edit!` | none | post-switch command | no |
| awerebea/git-worktrees.nvim | 2026-08 | 5 | snacks | `chdir` | current buf, picker fallback | none | before/after switch, add, delete | yes |
| RayIci/git-worktree.nvim | 2026-11 | 1 | none (nvim 0.12) | global cd | session save, wipe, restore | none | User events, participants | sibling default |
| yongjohnlee80/worktree.nvim | 2026-10 | 3 | auto-core (hard) | global cd | close stale, restore list | restart | event bus | unverified |
| ryuichi24/aero.nvim | 2026-11 | 1 | many (agent suite) | tcd, tab per wt | per-worktree remember/restore | none | events | yes |
| fzf-lua `git_worktrees` | n/a | n/a | fzf-lua | scope option | none | none | none | n/a |

Notes per plugin (file references are into each plugin's repo):

- **ThePrimeagen/git-worktree.nvim:** effectively abandoned; there is no
  rewrite branch. Parses plain `git worktree list` (breaks on spaces).
  Buffer remap uses unanchored `string.find` (`lua/git-worktree/init.lua:476-509`):
  switching from `.worktrees/a` to main, a buffer in `a` contains main's
  path, so it is judged "already in the new tree" and left pointing at `a`.
  Open issue #88 is "changing worktree while having active LSP clients".
- **polarmutex/git-worktree.nvim:** the maintained fork, quiet since
  2025-02. Parses `--porcelain` correctly, supports detached create, has a
  clean hooks registry. The builtin buffer hook is opt-in and has the same
  unanchored match. Telescope only.
- **Juksuu/worktrees.nvim:** the snacks sources ship in the plugin
  (`lua/worktrees/snacks.lua`). On switch, `update_current_buffer` calls
  `delete_buffers()`, which `nvim_buf_delete`s every `buftype == ""`
  buffer, before opening the counterpart (`lua/worktrees/utils.lua:161-198`);
  a modified buffer makes it error partway. The `cd` is hard-coded and
  unescaped. `worktree_path` always inserts the project name, so
  `<main>/.worktrees/<name>` is not directly expressible. Its
  `on_before_switch` hook can cancel, which is useful prior art.
- **afonsofrancof/worktrees.nvim:** zero deps, `vim.ui.select` UI.
  `startswith` without a separator, but a file-exists check makes nested
  misses fall back to `edit .`, which is safe. Delete always passes
  `--force`. A detached worktree has no name and fails to switch
  [INFERENCE].
- **mitubaEX/git_worktree.nvim:** defaults to exactly the nested
  `.worktrees/` layout, and is the most dangerous for it. It matches buffers
  by `^<old cwd>` (`lua/git_worktree/init.lua:451`), renames them in place
  and runs `edit!`, discarding unsaved edits; switching from main closes the
  target worktree's own clean buffers. Has a PR-review command via `gh` and
  a `.worktreeinclude` copy list.
- **awerebea/git-worktrees.nvim:** snacks picker, `/`-anchored prefix check,
  picker fallback when no counterpart. The cleanest small switcher; still
  current-buffer only and no LSP or env handling.
- **RayIci/git-worktree.nvim:** "switching replaces the workspace": saves
  the session, wipes every buffer, restores the target's session, rolls back
  on failure. It refuses to switch while any terminal job is live, which
  rules it out with agents in terminals. Its participant registry (prepare,
  check, flush, restore) and `User GitWorktreeSwitchPre/Switched` events are
  good design references.
- **yongjohnlee80/worktree.nvim:** the only one that handles LSP on switch
  (stop, then re-fire `FileType` for buffers under the new cwd, with a
  generation counter against rapid switches). Hard dependency on its own
  core library; about 17k lines.
- **ryuichi24/aero.nvim:** an agent suite (OpenCode, Claude Code, Codex)
  where each worktree is a tab with `:tcd` and a remembered buffer set
  (`lua/aero/tabs.lua`). The only surveyed plugin that combines worktrees
  and agents; far too broad to adopt, useful as 2b prior art.
- **fzf-lua `git_worktrees`:** the only mainstream picker with a cd scope
  (`local|win|tab|global`). Action bodies not read.
- Not read: laoz40/git-worktree.nvim, Geromendez135/worktree-manager.nvim,
  chadnorvell/worktrees.nvim and a few forks.

**Verdict:** none fits. The three that are nested-safe either do too little
(afonsofrancof, awerebea: current buffer, no LSP, no env) or are a different
product (aero). What a fit needs is small: porcelain parsing, longest-prefix
ownership, the buffer policy above, events, and a snacks picker. Write it,
borrowing RayIci's events and pre-flight idea, Juksuu's cancellable
before-switch hook, and Zed's remap rule.

## Creating and removing worktrees from nvim

### The picker

A snacks picker source (snacks has none built in). One row per worktree
from `git worktree list --porcelain`:

- name (dir basename), branch or `(detached <sha>)`, active marker, dirty
  count (`git -C <wt> status --porcelain`, run async), and porcelain flags
  (`locked`, `prunable`);
- per-repo health badges from a hook (for the real repo: "no port offset",
  "setup not run", "generated code missing");
- later, agent counts and attention state per worktree.

Actions:

- `<CR>` switch; a second key opens the worktree in a new tab (2b-style
  peek) without switching the main view.
- create (below);
- remove: refuse the main worktree and the active one; refuse when agents
  are running there; `git worktree remove <path>` without `--force` unless a
  second confirm; then offer to delete the branch if it is merged.
- prune: show `git worktree prune --dry-run --verbose`, then prune on
  confirm.

### Create: respect the repo's own flow

- Generic default: `git worktree add` with three variants (new branch from
  the default branch, existing branch, PR via `gh pr checkout` run inside a
  fresh detached worktree), placed under a configured base dir.
- **Per-repo override:** a hook table keyed by main root, for example
  `create = function(name) return { cmd = { 'make', 'worktree', 'NAME=' .. name }, cwd = main_root } end`,
  plus optional `post_create`, `pre_remove` and `health`. When a repo has a
  `create` hook, the generic `git worktree add` is not offered, so nothing
  bypasses the repo's setup (in the real repo, a plain `git worktree add`
  produced a worktree with no port offset, no allowed direnv and no deps).
- Run creation in a visible terminal split, not a silent job: it can fetch,
  install dependencies, prompt, and take minutes. On exit 0, offer to switch.
- Pass names explicitly; a make target that falls back to an interactive
  prompt will hang a background job.
- Map branch to path through porcelain output, never by guessing the dir
  name (the real repo turns `/` into `-`).
- **Where the hooks live:** repo-specific hooks name the repo, so they
  belong in the private fork; the public config gets only the mechanism.
  Options: a fork-only Lua file the module `require`s if present, or an
  optional `stdpath('config')/worktree-hooks/<repo-dir-name>.lua`. Avoid
  `exrc`-style files inside the repo.
- **Slots versus throwaways:** for a repo with long-lived slots, "start
  work on branch X" often means reusing a slot (`git switch` inside it plus
  whatever reset the repo needs), not creating a worktree. That is a slot
  controller's job; the picker should call it when one exists rather than
  reimplement it. nvim never deletes a slot it did not create (isolation
  doc, "Ownership of worktrees").

## Hand-off to agents (sketch)

Only a sketch; the agent layer is designed elsewhere. Consistent with the
isolation doc's "decide early" list.

- **Agents belong to a worktree by spawn cwd**, resolved with the
  longest-prefix rule (main root is a prefix of every slot, so a plain
  prefix test files every agent under main). Agents never move on a switch.
- **The switch never hides agents.** The agent view groups rows by main
  root, then worktree; the active worktree's group sorts first and expanded,
  others collapse but keep status and attention badges. Hiding would bury
  exactly the agent that needs you.
- **Spawn:** a new agent defaults to the active worktree, with the
  worktree's env (await the async direnv load). "New agent in worktree X"
  from the worktree picker passes an explicit cwd. The pre-warmed agent
  stays at the main root as the home agent (isolation doc open question 11).
- **"Take me to the agent that needs me":** `<leader>aj` jumps to the next
  row needing attention. If its worktree is not active, the default is
  **peek** (show its terminal in the agent view, editor untouched); a
  **follow** key runs `worktree.switch(row.worktree)` and then focuses the
  terminal. The worktree picker shows the same badges, so "switch to the
  worktree with a waiting agent" is one picker away.
- **Context sends** compute paths relative to the target session's cwd and
  refuse cross-worktree files (above).
- **Statusline:** a compact per-worktree attention summary next to the
  worktree component (for example `f1:1!`), so a waiting agent in another
  slot is visible without the agent view.
- **Removal guard:** the picker refuses to remove a worktree with running
  agents; archive or kill them first.
- **Inputs to `sidekick-assessment.md`:** spawn with an explicit cwd and
  env; identity by row id, not tool name (`ai.lua`'s `M.active` and kill
  paths are name-keyed, and sidekick's `State.get` prefers the current cwd,
  so after a switch the same key can reach a different agent).

## Recommendation

**Build a small `worktree.lua` for model 2a with global `:cd`**, matching
the isolation doc's leaning, using per-worktree working sets so a switch
feels like Zed's retained workspaces without tabs.

Build first, in order:

1. **Core module:** porcelain listing, longest-prefix ownership, `switch()`
   with the buffer policy above, `clearjumps`, local-dir reset,
   `User WorktreeSwitchPre`/`WorktreeSwitched` events, and the `DirChanged`
   adopt fallback. Working sets in memory, then persisted per main root.
2. **Subscribers that fix today's stale spots:** nvim-tree re-root plus git
   purge; neotest-golang cache clear; neogit re-target; title and a
   statusline worktree component; snacks `recent`/`smart` exclusion at the
   main root.
3. **LSP:** the reaper with an LRU of one previous worktree; a gopls
   `root_dir` that returns the worktree toplevel and never climbs above it.
   Measure gopls RSS before and after.
4. **Per-worktree env** via `direnv export json`, required before agents are
   spawned per worktree.
5. **Snacks worktree picker** with switch, remove, prune and a create action
   that delegates to a per-repo hook.

Defer:

- Agent-layer integration (grouping, peek/follow, badges): after the agent
  registry exists.
- Swapping nvim's own `vim.env` on switch.
- Session keying changes beyond the working-set store.
- Tab-per-worktree (2b): only if the buffer policy proves annoying. The
  module's ownership and event layer is the same for both, so 2b is mostly a
  different `switch()`.
- Throwaway create/archive (Zed's WIP-commit recipe): only if throwaways
  become common.
- Moving worktrees out of the main root: not recommended.

## Open questions

1. **Buffer policy defaults.** Is "current window remaps to the counterpart,
   everything else restores the target's working set" right, or should every
   window remap (Zed's create behaviour) on every switch?
2. **Jumplist.** Clear on switch (loses history) or keep (risks jumping into
   the old worktree)?
3. **LSP retention.** Keep one previous worktree's clients warm, none, or
   all? Depends on measured gopls RSS with the multi-module root.
4. **gopls root.** Does one gopls per worktree root (eight modules, no
   `go.work`) actually use less memory than one per module, and do
   cross-module references still work?
5. **Process env.** Per-job env only, or also swap `vim.env` on switch so
   formatters, linters and LSP spawns follow?
6. **Session file keying.** Should persistence always save under the main
   root (with the working-set store recording the active worktree), or under
   the active worktree as now?
7. **nvim-tree.** Does the ignored-dir shortcut really hide a worktree's
   files after re-rooting, and does `purge_state()` fix it?
8. **Stacked instruction files.** Confirm Claude Code (and omp) in a nested
   worktree read the main checkout's instruction files, and decide whether
   that is wanted.
9. **Hook location.** Fork-only Lua file versus an optional per-repo hook
   file under the config dir.
10. **Neogit's worktree popup.** Keep it as an alternative entry point
    (adopted through `DirChanged`), or route `<leader>Gw` to the new picker?
11. **Terminals.** Scope toggleterm's float cycle and bottom panel per
    worktree, or keep them global?
