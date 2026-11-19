# Zed — git worktrees

How Zed creates, switches, and deletes [git worktrees](https://git-scm.com/docs/git-worktree),
what switching does to your workspace, and how to fit Zed to a repo with its
own worktree tooling (per-worktree ports, Docker stacks, local config).
Companion to [`docs/zed.md`](zed.md); install/stow steps live in README's
`## Zed` section.

**Basis: Zed 1.29.2** (`zed --version`) — checked against the zed.dev pages
below and the `v1.29.2` tag:

- `crates/git_ui_core/src/{worktree_service,worktree_picker,created_worktrees}.rs`
- `crates/project/src/git_store.rs` — worktree paths
- `crates/workspace/src/{multi_workspace,tasks}.rs` — switching, hooks
- `crates/agent_ui/src/thread_worktree_archive.rs` — archiving
- `assets/keymaps/default-macos.json`

That's source reading, not use: [Untested in the app](#untested) lists what
still needs trying in a running Zed, and "not verified" marks claims checked
nowhere. After a Zed upgrade, re-check against the new tag and bump the
version here.

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

1. **Two meanings of "worktree".** In Zed's code and trust model, a
   *worktree* is any root folder or file you open; a *git worktree* is a
   linked checkout. This guide means the git kind unless it says otherwise.
2. **Three title-bar pickers, left to right: project, worktree, branch.**
   The worktree picker lists every checkout of the repo
   (`git worktree list`), main included; the branch picker acts on the
   active checkout.
3. **One workspace per worktree.** Switching opens the other checkout as
   its own workspace in the same window, with its own tabs, docks,
   terminals, and language servers. With agent features on (the default),
   the workspace you left stays alive, so switching back finds it as you
   left it; with `disable_ai: true` it's dropped. [1]
4. **The threads sidebar groups by repo.** Threads in linked worktrees
   appear under the main checkout's project group, so one repo is one group
   however many checkouts it has.
5. **Zed's worktrees start detached.** A picker-created worktree has no
   branch until you name one in the branch picker; that's how Zed avoids two
   worktrees sharing a branch (git forbids it).

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

Picker search matches both directory name and checked-out branch, so a
ticket ID finds its worktree either way.

<a id="creating"></a>
## Creating a worktree

With an empty query, the picker offers create rows based on repo state:

- **From the current branch** — detached at your `HEAD`. Hidden when you're
  on the default branch.
- **From the default branch** — fetches, then detaches at the default
  branch's remote tip (e.g. `origin/main`); the usual choice for new work.
  If the fetch fails, a toast offers "Use local origin/main".

Typing adds a **create <name>** row below the matches (spaces become `-`).
It's disabled when a worktree with that exact name exists, or in a
multi-repo project. Without a name, Zed picks a random `adjective-noun`
(`nimble-sky`).

On create, Zed:

1. runs `git worktree add` at the [configured location](#location) and
   records the worktree as Zed-created (this matters for
   [deleting](#deleting));
2. opens it, **carrying over your open files and dock layout** at the same
   relative paths. The agent panel keeps the selected agent and copies an
   unsent draft into a **new** thread; the conversation stays in the source
   workspace. Switching carries none of this;
3. runs any [`create_worktree` hooks](#hooks).

Then name a branch with the branch picker (`cmd-ctrl-b`): create one, or
check out one no other worktree holds. Picking a branch held elsewhere
leaves the worktree detached.

In a multi-root project, Zed creates one linked worktree per git repo and
carries non-git folders over as-is (with a toast saying so).

<a id="switching"></a>
## Switching

- **In place (`enter`)** — the window shows the other checkout's retained
  workspace, or a fresh one the first time. Open editors are *not*
  remapped, and threads and drafts don't follow
  ([zed#54938](https://github.com/zed-industries/zed/issues/54938)): start
  a new thread there, or go back to the old one.
- **New window (`cmd-enter`)** — for two checkouts side by side.
- **From the shell** — `zed path/to/worktree` opens it like any folder, in
  the same project group; `zed -n` forces a new window.
- **Not `zed -a <worktree>`** (add folder to the current workspace). Two
  checkouts in one project means two repos in the git panel, duplicate hits
  in project search and the file finder, and two language-server roots for
  one codebase.

The workspace you switch away from stays open in the window. To close it
without touching the checkout, hover its picker row and click `×`
(**Remove Worktree from Window**).

A switch is a workspace change, not a `git checkout`: nothing on disk
moves, so uncommitted work stays in the checkout you left.

<a id="location"></a>
## Where Zed puts worktrees

`git.worktree_directory` sets the base, relative to the main checkout
(default `"../worktrees"`). The full path is `<base>/<name>/<repo-dir-name>`:

| setting | repo at `~/src/app` → new worktree |
|---|---|
| `"../worktrees"` (default) | `~/src/worktrees/app/nimble-sky/app` |
| `".worktrees"` | `~/src/app/.worktrees/nimble-sky/app` |
| `".git/zed-worktrees"` | `~/src/app/.git/zed-worktrees/nimble-sky/app` |

- **The leaf is always the repo's own name**, so every Zed-created worktree
  shares the main checkout's basename. Anything named after the checkout
  folder (Zed's window title, `docker compose`'s default project name,
  `basename "$(git rev-parse --show-toplevel)"`) sees the same name in every
  worktree; see [Repos that already manage their own worktrees](#repo-managed).
- A base outside the repo gets the repo name appended (`worktrees/app/`) so
  sibling repos don't collide; an in-repo base doesn't.
- The base must be relative and resolve inside the repo or next to it:
  absolute paths, `".."`, and anything further up are rejected.
- Only the **global** value is read; a project's `.zed/settings.json` can't
  set it per repo.
- An in-repo base must be gitignored, or the main checkout shows every
  worktree as untracked files.

<a id="hooks"></a>
## Setup hooks

A task with `"hooks": ["create_worktree"]` runs in the new checkout after
Zed creates a worktree, from the picker or the agent's `create_thread`
tool. It does **not** run on switch, or for worktrees made with
`git worktree add` in a shell. Variables:

- `ZED_WORKTREE_ROOT` — the new checkout (also the task's default `cwd`)
- `ZED_MAIN_GIT_WORKTREE` — the main checkout, to copy gitignored files from

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
  and the new checkout's `.zed/tasks.json` — which exists there only if
  it's **committed**; an untracked or `.git/info/exclude`d `.zed/` stays in
  the main checkout. If you can't commit editor config to a shared repo,
  use the global file and guard on a repo marker (a script's path, a file
  name).
- **Trust.** No hook, global ones included, runs in a Restricted Mode
  worktree. Zed passes the source workspace's trust to the new one. This
  repo's `settings.json` sets `session.trust_all_worktrees: false`, so trust
  the main checkout (or its parent, e.g. `~/src`, which covers every folder
  below) first. Restricted mode ignores the repo's `.zed/settings.json`
  (LSP binaries, MCP servers, tasks) and drops the Zed Agent to a profile
  with no write or terminal tools.
- **Re-running.** Hook tasks also appear in the task picker
  (`cmd-shift-r`), so the template doubles as a manual "re-run setup" for
  worktrees made outside Zed.
- `cmd-shift-c` in the worktree picker opens `tasks.json` with a harmless
  hook template.

<a id="deleting"></a>
## Deleting, and thread archiving

- **From the picker** — `cmd-shift-backspace` runs `git worktree remove`;
  with modified or untracked files, Zed asks whether to force it
  (`cmd-alt-shift-backspace` forces without asking). It refuses the main
  checkout and any worktree still open in a workspace of this project
  group, including one you only switched away from: close that with
  **Remove Worktree from Window** on its picker row first.
- **The branch survives** — plain git behavior. Clean up with
  `git branch -d` or `git::Switch` (the branch picker can delete branches).
- **Archiving a thread can remove its worktree.** Archiving the last thread
  in a linked worktree saves its git state to
  `refs/archived-worktrees/<id>` and removes it from disk; restoring the
  thread from history (`cmd-g` in the sidebar) recreates it. Only worktrees
  **Zed created inside `git.worktree_directory`** qualify: Zed keeps a
  registry of what it made and checks the git-dir creation time before
  deleting. Worktrees from `git worktree add` or a repo script are never
  touched.
- **Nothing outside git is cleaned up** — Docker containers and volumes, a
  database, a running dev server. Tear those down first; see
  [Teardown order](#teardown).

<a id="environment"></a>
## Environment per worktree

- **direnv.** `load_direnv` defaults to `"direct"`: Zed runs
  `direnv export json` in each project root and passes the result to
  language servers, tasks, and terminals. Each worktree gets its own
  `.envrc` environment (ports, tool versions, a Nix flake) with no Zed
  config.
- **But direnv allows by path.** A new checkout's `.envrc` stays blocked,
  and Zed gets no environment, until `direnv allow` runs in it. Put
  `direnv allow .` in the hook (as above) or run it in the worktree's
  terminal, then reopen the workspace if it was already open (not verified
  whether Zed picks up a later `allow` without a reopen).
- **Terminals start in the active checkout.** `` ctrl-` `` in a
  switched-to workspace opens at that worktree's root, with its
  environment.
- **Language servers run per checkout.** Two open worktrees of a large repo
  means two of each server (gopls, tsserver, …), each started when you open
  a file of its language there ([`zed.md`](zed.md#language-servers)); close
  workspaces you aren't using if memory is tight.

<a id="repo-managed"></a>
## Repos that already manage their own worktrees

A common service-monorepo setup: a `make worktree NAME=…` script that

- creates `<repo>/.worktrees/<branch>` from a freshly fetched `origin/main`;
- gives each checkout a **port offset** (main `+0`, then `+100`, `+200`, …)
  in a gitignored `.envrc.local`, which `.envrc` turns into every service
  port;
- derives the Docker Compose project name from the checkout's directory
  name;
- runs per-checkout setup (copy or symlink local config, install
  dependencies, codegen).

Zed's picker knows none of this, so decide who owns what.

### Pick one creator: the repo script

Create with the repo's script; use Zed only to **switch, open, and
search**. This is the boring option and usually the right one:

- The script picks a free offset, writes `.envrc.local`, and runs setup. A
  Zed-created worktree has no `.envrc.local`, so it **defaults to offset 0
  and collides with the main checkout's ports and stack**.
- The script creates and names the branch up front; Zed leaves the worktree
  detached until you name one.
- Script-made worktrees still show in Zed's picker, which lists
  `git worktree list`, not just its own.
- Thread archiving never deletes them ([Deleting](#deleting)) — right for
  checkouts that own a Docker stack and a database.

Loop: `make worktree NAME=ticket-123` in a terminal → `cmd-ctrl-w`, type
`ticket-123`, `enter` → work → `cmd-ctrl-w` back to main. Use `cmd-enter`
to keep both checkouts in separate windows.

### If you do create from Zed

Make the hook do the script's job, and fix what Zed's layout breaks:

- **Basename-derived names collide.** The leaf is always the repo name
  (`…/nimble-sky/<repo>`), so a Compose project or "worktree name" taken
  from `basename $(git rev-parse --show-toplevel)` matches the main
  checkout's, and the new checkout's `docker compose up` targets main's
  containers. Derive the name from the parent directory when the basename
  equals main's, or set it explicitly in `.envrc.local` from the hook.
- **Allocate the port offset in the hook**, not by hand. Split the repo
  script into "create" and "set up an existing checkout", and call the
  second half from the hook (`cwd` `$ZED_WORKTREE_ROOT`); the checkout
  already exists by then.
- **Copy gitignored local config** (`*.local` files, credentials, `.env`)
  from `$ZED_MAIN_GIT_WORKTREE`. Copy rather than symlink anything a
  checkout may change on its own, such as port overrides.
- **Name the branch immediately** (`cmd-ctrl-b`). A detached worktree's
  commits are easy to lose, and branch-keyed tooling (PR scripts, stack
  tools) won't find it.
- **Mind the location.** `git.worktree_directory` is global, so
  `".worktrees"` applies to every repo, and any repo that doesn't gitignore
  `.worktrees/` shows Zed's checkouts as untracked. The default
  `"../worktrees"` keeps them out of every repo.

### Docker bind mounts

Bind mounts only work for paths the Docker VM shares. Colima shares your
home directory; Docker Desktop also shares `/tmp`, `/private`, and
`/var/folders`. In-repo `.worktrees/` and Zed's default `../worktrees` are
under home, so both work everywhere; check the runtime's file-sharing
settings before putting worktrees elsewhere.

<a id="exclusions"></a>
### Keep nested worktrees out of the main project

Opened at the main checkout, an in-repo `.worktrees/` shows in the project
panel as an expandable ignored folder. File finder and project search skip
it by default (`include_ignored: "smart"` includes ignored files only when
the opened root is itself ignored), but reach into it once you toggle
ignored files on. This repo's stowed `settings.json` hides it everywhere:

```jsonc
"file_scan_exclusions": ["...", "**/.worktrees", "**/.claude/worktrees"]
```

- `.claude/worktrees/` is where Claude Code's `--worktree` puts its
  checkouts.
- Patterns are relative to each opened root, so opening a worktree directly
  (`<repo>/.worktrees/x`) still works; only the main checkout stops
  scanning into it.
- `"..."` keeps Zed's default exclusions; drop it and `.git`, `.DS_Store`,
  and the rest stop being excluded.
- **Zed Agent** is bound too: its `read_file`, `list_directory`, and `grep`
  tools refuse or skip excluded paths, so a thread in the main checkout
  can't read a nested worktree — open that worktree to work in it. External
  agents (Codex and omp over ACP, Claude in a Terminal Thread) use their own
  tools; not verified whether any honor the exclusion.

<a id="teardown"></a>
### Teardown order

Neither Zed's delete nor `git worktree remove` knows about containers.
From inside the worktree:

1. Stop its stack: `docker compose -p <that checkout's project> down -v`
   (or the repo's make target), freeing the offset's ports, volumes, and
   database.
2. Switch Zed away (`cmd-ctrl-w` → main), then close the retained workspace
   with **Remove Worktree from Window** on its picker row, so the picker
   allows deletion.
3. Delete it from the picker, or with `git worktree remove <path>`.
4. Delete the branch if it's merged.

Skip step 1 and the script sees the offset as free once the directory is
gone, while the old containers still hold the ports: the next worktree
given that offset fails to start its stack.

<a id="gotchas"></a>
## Gotchas

Quick recap; details in the linked sections.

- **Threads don't follow a switch**; only *create* carries files, agent,
  and draft. [Switching](#switching)
- **Every Zed-created checkout has the repo's basename** — trust the
  worktree picker, not the window title. [Location](#location)
- **`create_worktree` hooks skip switches and shell-made worktrees** — run
  the hook from `cmd-shift-r` instead. [Hooks](#hooks)
- **Hooks don't run in Restricted Mode** — trust the main checkout first.
  [Hooks](#hooks)
- **`git.worktree_directory` is global-only and relative-only.**
  [Location](#location)
- **A branch can be checked out in only one worktree** —
  `git worktree list` shows who holds it. [Creating](#creating)
- **The picker won't delete an open worktree**, retained ones included —
  **Remove Worktree from Window** first. [Deleting](#deleting)

<a id="untested"></a>
## Untested in the app

Nothing in this guide has been exercised in a running Zed yet. For each
item: record the result (date, Zed version, what happened), fix the linked
section if reality differs, then delete the item. "Repo with its own
worktree script" means one shaped like
[Repos that already manage their own worktrees](#repo-managed).

### Exclusions (`file_scan_exclusions`)

- [ ] **Project panel hides `.worktrees/`** — open a repo with in-repo
  worktrees; `.worktrees/` and `.claude/worktrees/` don't appear (reopen
  the project if they do). ([Keep nested worktrees out](#exclusions))
  - Result:
- [ ] **Ignored-files search skips them** — `cmd-p`, toggle ignored files
  (`cmd-shift-i`), search a file name present in every checkout: one hit.
  Same in `cmd-shift-f` with "include ignored" on.
  - Result:
- [ ] **Opening a worktree directly still works** — `zed <repo>/.worktrees/<x>`
  shows its files normally.
  - Result:
- [ ] **Zed Agent is blocked** — from a main-checkout thread, ask it to
  read `.worktrees/<x>/README.md`: expect a `file_scan_exclusions` refusal.
  - Result:
- [ ] **External agents** (not verified) — same request from a Claude
  Terminal Thread and a Codex and omp thread; note which read the file
  anyway.
  - Result:

### Picker and switching

- [ ] **Picker lists script-made worktrees** — `cmd-ctrl-w` in a repo with
  its own script; typing a branch name finds the right row.
  ([Keys and actions](#keys))
  - Result:
- [ ] **Switch keeps the old workspace** — open files in main, switch to a
  worktree and back: main's tabs and docks are as you left them.
  ([Switching](#switching))
  - Result:
- [ ] **Create carries files, agent, and draft** — type a prompt without
  sending, create from the default branch: same files open at the new
  paths, same agent selected, the draft in a new thread there, the original
  thread still in main. ([Creating a worktree](#creating))
  - Result:
- [ ] **`zed -n <worktree>` opens a new window; plain `zed <worktree>` joins
  the current window's project group.** ([Switching](#switching))
  - Result:
- [ ] **Window title** — two Zed-created worktrees of one repo show the
  same project name in the title. ([Location](#location))
  - Result:

### Deleting

- [ ] **"Remove Worktree from Window" unblocks delete** — switch away from
  a worktree: its row has no trash icon. Click the `×` on hover, and the
  trash icon appears. ([Deleting](#deleting))
  - Result:
- [ ] **Dirty worktree prompts for force** — delete a worktree with an
  untracked file: expect the "Force delete it?" prompt.
  - Result:
- [ ] **Archiving leaves script-made worktrees alone** — archive the only
  thread in a script-made worktree: the directory stays. Repeat in a
  Zed-created one: the directory goes, and restoring the thread brings it
  back. ([Deleting](#deleting))
  - Result:

### Hooks and environment

- [ ] **The bootstrap hook runs** — put the [Setup hooks](#hooks) example
  in `~/.config/zed/tasks.json` and create a worktree: `.env` copied,
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
  `.envrc` isn't allowed yet, run `direnv allow` in Zed's terminal. Do a
  new terminal and the language server pick up the environment without
  reopening the workspace? ([Environment per worktree](#environment))
  - Result:
- [ ] **Per-worktree environment** — in a repo with port offsets, open two
  worktrees; `echo $<some port var>` differs between their terminals.
  - Result:

### Repo with its own worktree script

- [ ] **Zed-created worktree collides** — create one from the picker: it
  has no `.envrc.local`, gets offset 0, and its Compose project name
  matches main's (confirming the advice to create with the repo script).
  ([Pick one creator](#repo-managed))
  - Result:
- [ ] **Teardown order** — follow [Teardown order](#teardown) end to end on
  a throwaway worktree; note any step that doesn't match.
  - Result:
