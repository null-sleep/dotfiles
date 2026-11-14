# Zed — git worktrees and switching between them

How Zed creates, switches, and deletes [git worktrees](https://git-scm.com/docs/git-worktree)
of one repository, what it does to your workspace when you switch, and how
to fit it to a repo that already has its own worktree tooling (per-worktree
ports, Docker stacks, local config). Companion to [`docs/zed.md`](zed.md);
install/stow steps live in README's `## Zed` section.

**Basis: Zed 1.28.1 source + docs.** Every behavior here was checked
against the installed Zed (`zed --version` → 1.28.1): the zed.dev docs below
plus the source at the `v1.28.1` tag —
`crates/git_ui_core/src/{worktree_service,worktree_picker,created_worktrees}.rs`,
`crates/project/src/git_store.rs` (worktree paths),
`crates/workspace/src/{multi_workspace,tasks}.rs` (switching, hooks),
`crates/agent_ui/src/thread_worktree_archive.rs` (archiving), and
`assets/keymaps/default-macos.json`. That's source reading, not use: what
hasn't been tried in the running app is listed in
[Untested in the app](#untested), and statements marked "not verified"
weren't checked at all. After a Zed upgrade, re-check a claim against the
new tag before relying on it, then update this line.

## References

- [Git → Git Worktrees](https://zed.dev/docs/git#git-worktrees) — picker,
  detached-HEAD rule, `git.worktree_directory`
- [Parallel Agents → Worktree Isolation](https://zed.dev/docs/ai/parallel-agents#worktree-isolation)
  — threads in worktrees, archive/restore
- [Tasks → Hooks](https://zed.dev/docs/tasks#hooks) — the `create_worktree`
  hook, `ZED_WORKTREE_ROOT` / `ZED_MAIN_GIT_WORKTREE`
- [All settings → Git Worktree Directory](https://zed.dev/docs/reference/all-settings#git-worktree-directory)
- [Trusted worktrees](https://zed.dev/docs/worktree-trust) — Zed's broader
  "worktree" (any opened root) and what Restricted Mode blocks
- [zed#54938](https://github.com/zed-industries/zed/issues/54938) — why a
  thread doesn't follow you when you switch

## Contents

- [The model](#model)
- [Keys and actions](#keys)
- [Creating a worktree](#creating)
- [Switching](#switching)
- [Where Zed puts worktrees](#location)
- [Setup hooks](#hooks)
- [Deleting, and thread archiving](#deleting)
- [Environment per worktree](#environment)
- [Repos that already manage their own worktrees](#repo-managed)
- [Gotchas](#gotchas)
- [Untested in the app](#untested)

---

<a id="model"></a>
## The model

1. **Two meanings of "worktree".** In Zed's code and trust model a
   *worktree* is any root folder or file you open. A *git worktree* is a
   linked checkout. This guide means the git kind unless it says otherwise.
2. **The title bar has three pickers, left to right: project, worktree,
   branch.** The worktree picker lists every checkout of the current repo
   (`git worktree list`), the main one included; the branch picker acts on
   whichever checkout is active.
3. **One workspace per worktree.** Switching opens the other checkout as its
   own workspace in the same window — its own tabs, docks, terminals, and
   language servers. With the agent features on (the default), the workspace
   you left stays alive, so switching back returns to it as you left it.
   With `disable_ai: true` it's dropped on switch. [1]
4. **The threads sidebar groups by repo.** Threads running in linked
   worktrees appear under the main checkout's project group, so one repo
   stays one group however many checkouts it has.
5. **Zed's worktrees start detached.** A worktree created from the picker
   has no branch; you name one with the branch picker afterwards. This is
   how Zed avoids two worktrees sharing a branch (git forbids it).

[1] `MultiWorkspace::activate` retains workspaces only when
`multi_workspace_enabled` — agent settings enabled and AI not disabled.

<a id="keys"></a>
## Keys and actions

| key | action | where |
|---|---|---|
| `cmd-ctrl-w` | `git::Worktree` | anywhere: open the worktree picker |
| `enter` | `git::SwitchWorktree` | picker, on a worktree: switch this window |
| `cmd-enter` | `git::OpenWorktreeInNewWindow` | picker, on a worktree: open in a new window |
| `enter` | `git::CreateWorktree` | picker, on a "create" row |
| `cmd-shift-backspace` | `worktree_picker::DeleteWorktree` | picker, on a worktree |
| `cmd-alt-shift-backspace` | `worktree_picker::ForceDeleteWorktree` | picker; same as holding `alt` on the trash icon |
| `cmd-shift-c` | `zed::OpenWorktreeSetupTasks` | picker: open `tasks.json` with a hook template |
| `cmd-ctrl-b` | `branches::OpenRecent` | anywhere: branch picker (name the branch after creating) |
| `cmd-alt-o` | `projects::OpenRecent` | anywhere: recent projects, worktrees included |

Search in the worktree picker matches both the directory name and the
checked-out branch, so typing a ticket ID finds its worktree either way.

<a id="creating"></a>
## Creating a worktree

With an empty query the picker offers fixed create rows, depending on repo
state:

- **From the current branch** — detached at your current `HEAD`. Omitted
  when the current branch is the default branch.
- **From the default branch** — fetches the remote first, then detaches at
  the default branch's tip (e.g. `origin/main`); the usual choice for new
  work. If the fetch fails, a toast offers "Use local origin/main".

Type anything and a **create <name>** row appears below the matching
worktrees (spaces become `-`). It's disabled when a worktree with that exact
name exists, or in a multi-repo project. With no name, Zed picks a random
`adjective-noun` one (`nimble-sky`).

1. Zed runs `git worktree add` at the path described under
   [Where Zed puts worktrees](#location) and records it as Zed-created
   (this matters for [deleting](#deleting)).
2. It opens the new checkout and **carries your open files and dock layout
   over**, remapped to the same relative paths in the new tree. The agent
   panel keeps your selected agent, and an unsent draft is copied into a
   **new** thread there; the conversation itself stays in the source
   workspace. Switching transfers none of this.
3. It runs any [`create_worktree` hook tasks](#hooks).
4. You open the branch picker (`cmd-ctrl-b`) and create a branch, or check
   out an existing one that no other worktree holds. Pick one already
   checked out elsewhere and the worktree stays detached.

In a multi-root project, Zed creates one linked worktree per git repo and
carries non-git folders over as-is (with a toast saying so).

<a id="switching"></a>
## Switching

- **In place (`enter`)** — the window shows the other checkout. Open
  editors are *not* remapped: you see that worktree's own retained
  workspace, or a fresh one the first time. Agent threads and drafts don't
  follow you either ([zed#54938](https://github.com/zed-industries/zed/issues/54938));
  start a new thread there, or keep the thread where it was.
- **Closing a retained workspace** — switching away keeps the old workspace
  open in the window. The worktree picker's row for it shows a
  **Remove Worktree from Window** button (`×`, on hover) that closes it
  without touching the checkout.
- **New window (`cmd-enter`)** — use this when two checkouts need to be
  visible at once, e.g. comparing behavior side by side.
- **From the shell** — `zed path/to/worktree` opens it like any folder,
  and it lands in the same project group. Use `zed -n` to force a new
  window.
- **Avoid `zed -a <worktree>`** (add folder to the current workspace). Two
  checkouts of one repo in one project means two git repos in the git
  panel, duplicate symbols in project search and the file finder, and two
  language-server roots for one codebase.

A switch is a workspace change, not a `git checkout`: nothing on disk
moves, so uncommitted work in the checkout you left stays where it is.

<a id="location"></a>
## Where Zed puts worktrees

`git.worktree_directory`, a path relative to the main checkout, default
`"../worktrees"`. The full path is `<base>/<name>/<repo-dir-name>`:

| setting | repo at `~/src/app` → new worktree |
|---|---|
| `"../worktrees"` (default) | `~/src/worktrees/app/nimble-sky/app` |
| `".worktrees"` | `~/src/app/.worktrees/nimble-sky/app` |
| `".git/zed-worktrees"` | `~/src/app/.git/zed-worktrees/nimble-sky/app` |

- When the base resolves outside the repo, Zed appends the repo name
  (`worktrees/app/`) so sibling repos don't collide. Inside the repo, it
  doesn't.
- The base must be relative and resolve inside the repo or next to it.
  Absolute paths, `".."`, and anything further up are rejected.
- **The leaf directory is always the repo's own name.** Every Zed-created
  worktree has the same basename as the main checkout. Anything that names
  itself after the checkout folder (Zed's window title, `docker compose`'s
  default project name, scripts using `basename "$(git rev-parse --show-toplevel)"`)
  sees identical names in every worktree. See
  [Repos that already manage their own worktrees](#repo-managed).
- Zed reads the **global** value only. A project's `.zed/settings.json`
  can't change it per repo.
- An in-repo base must be gitignored, or the main checkout shows the whole
  worktree as untracked files.

<a id="hooks"></a>
## Setup hooks

A task with `"hooks": ["create_worktree"]` runs after Zed creates a
worktree, from the picker or the agent's `create_thread` tool, in the new
checkout. It does **not** run when you switch, or for worktrees made with
`git worktree add` in a shell. Variables:

- `ZED_WORKTREE_ROOT` — the new checkout (also the task's default `cwd`)
- `ZED_MAIN_GIT_WORKTREE` — the main checkout: the source to copy
  gitignored files from

```jsonc
// ~/.config/zed/tasks.json — runs for every repo, so guard each step.
[
  {
    "label": "worktree: bootstrap",
    "command": "for f in .env .envrc.local; do if [ -f \"$ZED_MAIN_GIT_WORKTREE/$f\" ] && [ ! -e \"$f\" ]; then cp \"$ZED_MAIN_GIT_WORKTREE/$f\" . || exit $?; fi; done; if [ -f .envrc ] && command -v direnv >/dev/null; then direnv allow . || exit $?; fi; if [ -x scripts/worktree-setup ]; then scripts/worktree-setup || exit $?; fi",
    "cwd": "$ZED_WORKTREE_ROOT",
    "hooks": ["create_worktree"],
    "reveal": "always",
    "hide": "on_success"
  }
]
```

- **Global or project file.** Hooks come from `~/.config/zed/tasks.json`
  and the new checkout's `.zed/tasks.json`. The project file only exists
  in the new worktree if it's **committed**; an untracked or
  `.git/info/exclude`d `.zed/` stays behind in the main checkout. If you
  can't commit editor config to a shared repo, use the global file and
  guard on a repo marker (a script's path, a file name).
- **Trust.** Hooks (global ones too) don't run in a Restricted Mode
  worktree. Zed passes trust from the source workspace to the new one, and
  this repo's `settings.json` sets `session.trust_all_worktrees: true`, so
  it isn't an issue here. On a stock install, trust the main checkout first.
- Hook tasks also appear in the task picker (`cmd-shift-r`), so the same
  template doubles as a manual "re-run setup" for worktrees made outside
  Zed.
- `cmd-shift-c` in the worktree picker opens `tasks.json` with a harmless
  hook template.

<a id="deleting"></a>
## Deleting, and thread archiving

- **From the picker** — `cmd-shift-backspace` runs `git worktree remove`.
  If the checkout has modified or untracked files, Zed asks whether to force
  it (`cmd-alt-shift-backspace` skips the question). You can't delete the
  main checkout, or a worktree open in *any* workspace of this project
  group, and switching away still leaves it open as a retained workspace.
  Switch away, close it with **Remove Worktree from Window** on its picker
  row, then delete.
- **Deleting a checkout doesn't delete its branch** — that's plain git
  behavior. Clean up with `git branch -d` or `git::Switch` (the branch
  picker can delete branches).
- **Archiving a thread can remove its worktree.** When you archive the last
  thread using a linked worktree, Zed saves the worktree's git state to
  `refs/archived-worktrees/<id>` and removes it from disk; restoring the
  thread from history (`cmd-g` in the sidebar) recreates it. This only
  applies to worktrees **Zed created inside `git.worktree_directory`**:
  Zed keeps a registry of what it made and compares the git-dir creation
  time before deleting anything. Worktrees from `git worktree add` or a
  repo script are never touched.
- Anything outside git (Docker containers and volumes, a database, a
  running dev server) survives either path. Tear it down first; see
  [teardown](#teardown).

<a id="environment"></a>
## Environment per worktree

- **direnv.** `load_direnv` defaults to `"direct"`: Zed runs
  `direnv export json` in each project root and gives the result to
  language servers, tasks, and terminals. Each worktree therefore gets its
  own `.envrc` environment (ports, tool versions, a Nix flake) without any
  Zed config.
- **But direnv allows by path.** A new checkout's `.envrc` is blocked until
  `direnv allow` runs in it, so Zed gets no environment. Put
  `direnv allow .` in the hook (as above), or run it in the new
  worktree's terminal. If the workspace was already open, reopen it so Zed
  reloads the environment (not verified whether Zed picks up a later
  `direnv allow` without a reopen).
- **Terminals start in the active checkout.** `` ctrl-` `` in a switched-to
  workspace opens in that worktree's root, with its environment.
- **Language servers run once per checkout.** Two open worktrees of a large
  repo means two of each server (gopls, tsserver, …). Close workspaces you
  aren't using if memory is tight.

<a id="repo-managed"></a>
## Repos that already manage their own worktrees

A common setup in service monorepos: a `make worktree NAME=…` script that
creates `<repo>/.worktrees/<branch>`, branches from a freshly fetched
`origin/main`, gives each checkout a **port offset** (main at `+0`, then
`+100`, `+200`, …) in a gitignored `.envrc.local`, derives the Docker
Compose project name from the checkout's directory name, and runs a
per-checkout setup (copy or symlink local config, install dependencies,
codegen). `.envrc` turns the offset into every service port. Zed's picker
knows none of this, so decide who owns what.

### Pick one creator: the repo script

Create with the repo's script; use Zed only to **switch, open, and
search**. This is the boring option and usually the right one:

- The script picks a free offset, writes `.envrc.local`, and runs setup.
  A Zed-created worktree has no `.envrc.local`, so it **defaults to offset
  0 and collides with the main checkout's ports and stack**.
- The script creates and names the branch up front. Zed's create rows
  leave the worktree detached until you name a branch.
- Script-created worktrees show up in Zed's picker anyway: it lists
  `git worktree list`, not just its own.
- Zed's thread archiving never deletes them ([Deleting](#deleting)), which
  is what you want for checkouts that own a Docker stack and a database.

Loop: `make worktree NAME=ticket-123` in a terminal → `cmd-ctrl-w`, type
`ticket-123`, `enter` → work → `cmd-ctrl-w` back to main. Use `cmd-enter`
when you want both checkouts in separate windows.

### If you do create from Zed

Make the hook do the script's job and fix what Zed's layout breaks:

- **Basename-derived names collide.** The leaf is always the repo name
  (`…/nimble-sky/<repo>`), so a Compose project or "worktree name" taken
  from `basename $(git rev-parse --show-toplevel)` comes out identical to
  the main checkout's. In practice the new checkout's
  `docker compose up` targets the main checkout's containers. Derive the
  name from the parent directory when the basename equals the main
  checkout's, or set it explicitly in `.envrc.local` from the hook.
- **Allocate the port offset in the hook**, not by hand. Split the repo
  script into "create" and "set up an existing checkout", and call the
  second half from the hook with `cwd` set to `$ZED_WORKTREE_ROOT`. The
  hook runs after the checkout exists, so the create half doesn't apply.
- **Copy gitignored local config** (`*.local` files, credentials, `.env`)
  from `$ZED_MAIN_GIT_WORKTREE`. Copy rather than symlink anything a
  checkout may change independently, such as port overrides.
- **Name the branch immediately** (`cmd-ctrl-b`). A detached worktree's
  commits are easy to lose, and branch-keyed tooling (PR scripts, stack
  tools) won't find it.
- **Match the location.** Zed reads `git.worktree_directory` globally, so
  setting it to `".worktrees"` affects every repo, and a repo that doesn't
  gitignore `.worktrees/` then shows Zed's checkouts as untracked. The
  default `"../worktrees"` keeps Zed's checkouts out of every repo.

### Location constraints

Bind mounts only work for paths the Docker VM runtime shares. Defaults
differ: Colima mounts your home directory, while Docker Desktop also
shares `/tmp`, `/private`, and `/var/folders`. In-repo `.worktrees/` and
Zed's default `../worktrees` sit under home, so they work everywhere; check
the runtime's file-sharing settings before putting worktrees elsewhere.

### Keep nested worktrees out of the main project

With checkouts inside the repo (`.worktrees/`), opening the main checkout
shows `.worktrees/` in the project panel as an expandable ignored folder.
Being gitignored, it's left out of file-finder and project-search results
by default (`include_ignored: "smart"` only includes ignored files when the
opened root itself is ignored), but they reach into it as soon as you
toggle ignored files on. Hiding it removes it from all of those:

```jsonc
"file_scan_exclusions": ["...", "**/.worktrees", "**/.claude/worktrees"]
```

This repo's stowed `settings.json` ships exactly that line;
`.claude/worktrees/` is where Claude Code's `--worktree` puts its
worktrees. The pattern is relative to each opened root, so opening a
worktree directly (`<repo>/.worktrees/x`) still works; only the main
checkout stops scanning into it. `"..."` keeps Zed's default exclusions;
leave it out and `.git`, `.DS_Store`, and the rest stop being excluded.

The exclusion also binds **Zed Agent's** built-in tools: `read_file`,
`list_directory`, and `grep` refuse or skip excluded paths, so a Zed Agent
thread in the main checkout can't read or search a sibling worktree. Open
that worktree to work in it. External ACP agents (Claude, Codex, omp) run
their own tools; not verified whether any of them honor the exclusion.

<a id="teardown"></a>
### Teardown order

Neither Zed's delete nor `git worktree remove` knows about containers.
From inside the worktree:

1. Stop its stack: `docker compose -p <that checkout's project> down -v`
   (or the repo's equivalent make target), so the offset's ports, volumes,
   and the DB are freed.
2. Switch Zed away from it (`cmd-ctrl-w` → main), then close its retained
   workspace with **Remove Worktree from Window** on its picker row, so
   the picker allows deletion.
3. Delete it from the picker, or with `git worktree remove <path>`.
4. Delete the branch if it's merged.

Skip step 1 and the offset still looks free to the script once the
directory is gone, while the old containers keep the ports: the next
worktree to get that offset fails to start its stack.

<a id="gotchas"></a>
## Gotchas

- **Switching drops the thread.** Threads and drafts stay with the
  workspace they started in. *Create* carries open files, the selected
  agent, and an unsent draft (as a new thread), but not the conversation.
- **Every Zed-created checkout has the repo's basename.** Window titles and
  basename-keyed tooling can't tell them apart: check the worktree picker
  in the title bar, not the window title.
- **`create_worktree` hooks never run on switch** or for shell-created
  worktrees. Run the hook task from `cmd-shift-r` to set those up.
- **Hooks are skipped in Restricted Mode** — trust the main checkout first
  on a fresh install.
- **`git.worktree_directory` is global-only and relative-only.**
- **A branch can be checked out in only one worktree.** Picking a held
  branch in the branch picker leaves you detached; `git worktree list`
  shows who holds it.
- **The picker refuses to delete open worktrees**, including ones you
  switched away from (still retained) or open in another workspace of the
  same project group. Use **Remove Worktree from Window** first.

<a id="untested"></a>
## Untested in the app

Everything above comes from Zed's source and docs; none of it has been
exercised in a running Zed yet. Work through these when there's time.
Record the result under each item (date, Zed version, what happened), fix
the section it links to if reality differs, then delete the item.
"Repo with its own worktree script" means a repo shaped like
[Repos that already manage their own worktrees](#repo-managed).

### Exclusions (`file_scan_exclusions`)

- [ ] **Project panel hides `.worktrees/`** — open a repo with in-repo
  worktrees; `.worktrees/` and `.claude/worktrees/` don't appear. If they
  still show, reopen the project.
  ([Keep nested worktrees out](#repo-managed))
  - Result:
- [ ] **Ignored-files search skips them** — `cmd-p`, toggle ignored files
  (`cmd-shift-i`), search a file name that exists in every checkout: one
  hit. Same in `cmd-shift-f` with "include ignored" on.
  - Result:
- [ ] **Opening a worktree directly still works** — `zed <repo>/.worktrees/<x>`
  shows its files normally.
  - Result:
- [ ] **Zed Agent is blocked** — from a main-checkout thread, ask it to
  read `.worktrees/<x>/README.md`: expect a `file_scan_exclusions` refusal.
  - Result:
- [ ] **External agents** (not verified) — same request from a Claude,
  Codex, and omp thread. Note which ones read the file anyway.
  - Result:

### Picker and switching

- [ ] **Picker lists script-made worktrees** — `cmd-ctrl-w` in a repo with
  its own script; typing a branch name finds the right row.
  ([Keys and actions](#keys))
  - Result:
- [ ] **Switch keeps the old workspace** — open files in main, switch to a
  worktree, switch back: main's tabs and docks are as you left them.
  ([Switching](#switching))
  - Result:
- [ ] **Create carries files, agent, and draft** — type a prompt without
  sending it, create from the default branch: same files open at the new
  paths, same agent selected, the draft is in a new thread there, and the
  original thread stays in main. ([Creating a worktree](#creating))
  - Result:
- [ ] **`zed -n <worktree>` opens a new window; plain `zed <worktree>` joins
  the current window's project group.** ([Switching](#switching))
  - Result:
- [ ] **Window title** — two Zed-created worktrees of one repo show the same
  project name in the title. (Gotchas)
  - Result:

### Deleting

- [ ] **"Remove Worktree from Window" unblocks delete** — switch away from a
  worktree, confirm the trash icon is missing on its row, click the `×`
  ("Remove Worktree from Window") on hover, and the trash icon appears.
  ([Deleting](#deleting))
  - Result:
- [ ] **Dirty worktree prompts for force** — delete a worktree with an
  untracked file: expect the "Force delete it?" prompt.
  - Result:
- [ ] **Archiving leaves script-made worktrees alone** — archive the only
  thread in a script-made worktree; the directory stays. Then do the same
  in a Zed-created one: the directory goes, and restoring the thread brings
  it back. ([Deleting](#deleting))
  - Result:

### Hooks and environment

- [ ] **The bootstrap hook runs** — put the [Setup hooks](#hooks) example
  in `~/.config/zed/tasks.json`, create a worktree: `.env` copied,
  `direnv allow` ran, terminal closes on success.
  - Result:
- [ ] **A failing hook stays visible** — make `scripts/worktree-setup` exit
  non-zero: the terminal stays open showing the failure. (The shell command
  itself was smoke-tested: exit codes 0 / 0 / 7 for the copy, no-op, and
  failing cases.)
  - Result:
- [ ] **Hooks skip switching** — switch to an existing worktree: the hook
  doesn't run.
  - Result:
- [ ] **direnv after `allow`** (not verified) — in a worktree whose
  `.envrc` isn't allowed yet, run `direnv allow` in Zed's terminal. Does a
  new terminal or the language server pick up the environment without
  reopening the workspace? ([Environment per worktree](#environment))
  - Result:
- [ ] **Per-worktree environment** — in a repo with port offsets, open two
  worktrees; `echo $<some port var>` in each workspace's terminal differs.
  - Result:

### Repo with its own worktree script

- [ ] **Zed-created worktree collides** — create one from the picker in
  such a repo: confirm it has no `.envrc.local`, gets offset 0, and its
  Compose project name matches main's. (This confirms the advice to keep
  creating worktrees with the repo script.)
  ([Pick one creator](#repo-managed))
  - Result:
- [ ] **Teardown order** — follow [Teardown order](#teardown) end to end on
  a throwaway worktree; note any step that doesn't match.
  - Result:
