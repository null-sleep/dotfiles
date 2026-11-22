# Parallel agents in nvim: isolation and topology

Research and scoping only. This doc decides nothing and builds nothing. It
lays out how parallel agent sessions could map onto checkouts and nvim
instances, so the user can pick a model. It ends with a leaning.

- **Written:** 2026-11-22.
- **Question:** when several agent CLIs (Claude Code, omp, and others) run in
  nvim terminal buffers, how do sessions map to git checkouts and to nvim
  processes? Possible answers: one tree shared by all agents, one nvim that
  manages several worktrees, one nvim per worktree, or a mix.
- **Inputs:**
  - the companion docs [`zed-feature-survey.md`](zed-feature-survey.md)
    (section 4) and [`zed-design-lessons.md`](zed-design-lessons.md)
    (sections 2, 9 and 10, plus "Constraints and risks")
  - the nvim config under `nvim/.config/nvim/`: `ai.lua`, `agentview.lua`,
    `agent_events.lua`, `ai_context.lua`, `session.lua`, `lsp.lua`,
    `filetree.lua`, `titling.lua`
  - the hook bridges `claude/.claude/hooks/sidekick-notify.sh` and
    `omp/.omp/agent/extensions/nvim-notify.ts`
  - installed sidekick.nvim (`cli/session/init.lua`, `cli/state.lua`)
  - Zed's worktree code in `~/src/zed` (`git_ui_core/src/worktree_service.rs`)
  - earlier design docs in the public upstream's `plans/`:
    `git-worktree-nvim-plugin.md`, `sidekick-multi-claude-sessions.md`,
    `sidekick-agent-view.md`, `sidekick-agent-view-internals.md`,
    `sidekick-agent-event-pipeline.md`, `zmx-session-persistence.md`,
    `zed-fork-terminal-thread-notifications.md`
  - this repo's existing worktree plans: a long-lived slot controller for a
    large service repo, and a plan for the editor's throwaway worktrees in
    that repo. They are described generically here.
- **Sibling docs, not repeated here:**
  - `sidekick-assessment.md` asks whether to keep or replace sidekick.nvim.
    This doc only notes where the isolation choice constrains that decision.
  - `worktree-switching.md` covers switching mechanics and plugins. This doc
    stays at the topology level and does not survey plugins.

## Contents

- [User constraints this analysis takes as given](#user-constraints-this-analysis-takes-as-given)
- [Terms](#terms)
- [What the current setup assumes](#what-the-current-setup-assumes)
- [The nested worktree layout is a constraint on every model](#the-nested-worktree-layout-is-a-constraint-on-every-model)
- [Model 1: shared tree](#model-1-shared-tree)
- [Model 2: one nvim, many worktrees](#model-2-one-nvim-many-worktrees)
- [Model 3: one nvim per worktree](#model-3-one-nvim-per-worktree)
- [Model 4: hybrids](#model-4-hybrids)
- [What Zed chose, and how well it suits a terminal editor](#what-zed-chose-and-how-well-it-suits-a-terminal-editor)
- [Comparison matrix](#comparison-matrix)
- [Decision criteria](#decision-criteria)
- [Leaning](#leaning)
- [Decide early versus defer](#decide-early-versus-defer)
- [Open questions](#open-questions)

## User constraints this analysis takes as given

- **No per-agent change tracking.** The user does not want Zed's action log,
  per-agent diffs, or keep/reject. Existing tools are enough: diffview,
  gitsigns, Neogit and plain `git diff`. Seeing several agents' changes mixed
  together in one `git diff` is acceptable. Isolation is therefore not
  needed for review attribution. It only matters to stop agents interfering
  with each other while they work.
- **The workflow the user currently finds most interesting:** open one nvim
  at a repo's main root and switch between worktrees from there, with the
  cwd and open files following the switch. Then build the parallel-agent
  panel on top of that. This doc gives that model (2a below) proper weight.
- **The real repo keeps long-lived worktrees nested inside the main root**,
  at `.worktrees/<name>`. Its per-checkout setup is heavy. That makes the
  worktrees long-lived slots, not throwaways. This doc treats the nested
  layout as a hard constraint, not a detail.
- **Undecided:** whether to keep sidekick.nvim, and whether a separate nvim
  per worktree will happen anyway (terminal multiplexer tabs, Neovide
  windows).

## Terms

- **Main root:** the primary checkout, which owns `.git/`.
- **Linked worktree:** a `git worktree add` checkout. Its `.git` is a file.
  It shares refs, objects and stashes with the main root, and has its own
  HEAD and index.
- **Nested layout:** linked worktrees live under the main root, at
  `<main>/.worktrees/<name>`.
- **Sibling layout:** linked worktrees live outside the main root. Zed's
  default is `../worktrees/<project>/<name>`.
- **Slot:** a long-lived worktree that is set up once and reused across
  branches. Setup can include deps, env files, a database and ports.
- **Throwaway:** a worktree created for one task and removed or archived
  afterwards.
- **Session row:** one agent session as the agent view and the registry see
  it.
- **Active worktree:** in model 2, the worktree the editor is pointed at
  right now.

## What the current setup assumes

Everything shipped today assumes **one nvim, one project, N agents**. None
of the upstream sidekick docs plan for several worktrees or several nvim
instances. Those cases appear only as edge cases. These facts constrain
every model:

- **Spawn cwd is implicit.**
  - sidekick creates a session with `Session.new({ tool = tool.name })` and
    takes its cwd from `vim.fn.getcwd(0)` (`cli/state.lua`,
    `cli/session/init.lua` `M.cwd`). That is the current window's effective
    cwd, so `:tcd` and `:lcd` are honoured.
  - No `cwd` option passes through `cli.show`. To spawn an agent in a
    worktree, the current window's cwd must already be that worktree.
- **Two identity layers that disagree.**
  - sidekick's `sid` is `(tool, sha256(cwd))`.
  - The config's own join key is the plain name string. That covers
    `ai.lua` (`M.active`, `_dynamic`, `_labels`), `agent_events.sessions`,
    `$SIDEKICK_SESSION` in hooks, the digits and the badge.
  - Upstream `sidekick-multi-claude-sessions.md` ("Known behavioral edges")
    lists the results:
    - The same name in two cwds gives two attached sessions, and a picker
      pops up to choose between them.
    - A label of 16 or more characters collapses the cwd hash, so the same
      label from two cwds silently reattaches to one session.
    - A name-only kill can hit the wrong session of a same-named pair.
  - That doc calls these "a non-issue in normal single-project use". In any
    multi-worktree model they become the normal case.
- **State.get prefers the current cwd.**
  - Name-filtered lookups sort sessions in the current cwd first
    (`state.lua`).
  - So which session `<leader>aa` toggles depends on where nvim's cwd
    happens to be. That is hidden state once cwds differ.
- **Events route to the nvim that spawned the agent.**
  - sidekick puts `NVIM = vim.v.servername` in every job env.
  - `sidekick-notify.sh` then RPCs to `$NVIM`.
  - Upstream `sidekick-agent-event-pipeline.md` says separate nvims "route
    events to the correct one automatically". Its verification step 6 (two
    nvims, same repo) is not recorded as run, so treat the claim as asserted
    but untested.
- **The agent view is in-process only, by decision.**
  - Upstream `sidekick-multi-claude-sessions.md` ("What the switcher does
    NOT show") says another nvim's sessions are never listed, and calls this
    "the accepted behavior, not a compromise to revisit".
  - The view is a flat list sorted by name, with no grouping.
  - Notification titles are `ai.display(name)`, with no repo or worktree in
    them.
- **persistence.nvim keys sessions by global cwd plus branch**
  (`session.lua`, `branch = true`).
  - Terminals are excluded from saved sessions.
  - The agent view tab is torn down before saving.
- **Pre-warm.** One `claude` is pre-warmed in the startup cwd when a `.git`
  ancestor exists (`ai.lua`, using `vim.fs.root`, which works for worktrees
  whose `.git` is a file).
- **LSP.**
  - `vim.lsp.config` with root markers, enabled for lua_ls, pyright, ts_ls,
    gopls, elixirls, kotlin and eslint.
  - nvim starts one client per (server, root dir).
  - For a file inside a worktree, the nearest marker is the worktree's own
    `go.mod`, `package.json` or `.git` file, so it gets its own client.
- **Window title.** `titling.lua` shows the basename of the current buffer's
  git root. In a nested worktree that is `<name>`, not the repo.
- **Context refs are relative to nvim's cwd, not the agent's cwd.**
  `ai_context.ref` uses `vim.fs.relpath(cwd or getcwd(), name)`. Once the
  editor and an agent sit in different checkouts, a sent `@path#L` can point
  at the wrong file (see model 2).
- **No worktree code exists today.** Neogit's worktree popup can create one
  by hand. Sessions are not tied to worktrees.

## The nested worktree layout is a constraint on every model

`<main>/.worktrees/<name>` behaves differently from a sibling layout in
ways that matter whichever model is picked.

1. **Config lookups fall through to the main checkout.**
   - Anything that walks up the directory tree for config looks in the main
     checkout when the worktree has no copy of its own: direnv's nearest
     `.envrc`, `.env` loaders, eslint, prettier, tsconfig, pyproject,
     `go.work`, and so on.
   - Gitignored local config usually exists only in the main checkout, so a
     worktree without its own copy silently picks up main's.
   - Sometimes that is what you want, such as shared credentials. Sometimes
     it is a bug, such as ports or database names. The slot-controller plan
     already hit this class of bug: a worktree ended up pointed at the main
     checkout's database, by a different route.
   - A sibling layout fails loudly instead, because there is nothing to fall
     back to.
2. **Agent instruction files stack.**
   - Claude Code loads `CLAUDE.md` from its cwd and from every parent
     directory. An agent in `.worktrees/f1` therefore reads the worktree's
     `CLAUDE.md` and the main checkout's, which may be from a different
     branch.
   - Other agents that walk up for `AGENTS.md` behave the same way. This is
     unverified per agent.
   - The slot plan already keeps a "which checkout am I in" note for agents,
     telling them to trust the path over env vars. Nesting makes that note
     more necessary.
3. **The main root's scope contains every worktree.**
   - An agent started at the main root has every worktree under its working
     directory. Its file tools and its default edit scope (inside the cwd)
     cover the sibling worktrees.
   - A stray `rg` or an absolute path from a log can land it editing
     `.worktrees/f1/...`. Nesting makes cross-checkout edits easy and
     silent.
   - In the other direction, an agent in a worktree cannot reach the main
     root without asking.
4. **Editor-side scans at the main root see the worktrees unless
   `.worktrees/` is ignored.**
   - Pickers (ripgrep) and nvim-tree honour `.gitignore` and
     `.git/info/exclude`. With `.worktrees/` ignored, a picker opened at the
     main root shows main's files only.
   - Without it, every file appears once per checkout, with identical tails.
   - LSP servers rooted at the main root may index the nested trees anyway,
     because their own include and exclude rules are separate from git's.
     pyright, ts_ls and eslint are the likely cases. gopls treats a nested
     module as separate, but may still walk it. The result is duplicate
     workspace symbols and extra memory. This needs a per-server exclude,
     and measuring.
5. **Watchers rooted at the main root see every agent's writes.**
   - This covers nvim-tree's git watcher, sidekick's fs watcher and LSP
     file watching.
   - Agents writing in `f1` generate events in the main root's watchers.
     The cost is unmeasured. It is probably small on macOS FSEvents, but it
     grows with the number of busy agents.
6. **Per-file git tools are fine.**
   - gitsigns resolves the repo per buffer, so a buffer at
     `.worktrees/f1/x.go` shows f1's hunks.
   - `git` commands run at the main root act on main only.
   - All checkouts share refs, so a commit in f1 is visible from main at
     once. That makes merging back easy.
7. **Upsides.**
   - One prefix finds everything. A single nvim at the main root can open
     any worktree file by a short relative path.
   - Slots sit beside the code they belong to.
   - Claude Code's own `--worktree` option also nests, under
     `.claude/worktrees/`, in the versions I know of (verify). So nesting is
     a mainstream convention, not an oddity.
8. **Context refs go wrong silently.**
   - The same relative path exists in every checkout. Suppose the editor's
     cwd is `.worktrees/f1` and you send `@internal/x.go#L10` to an agent at
     the main root. The agent opens main's `internal/x.go`, a real but wrong
     file, and nothing errors.
   - In the reverse case (editor at the main root, agent in f1), the ref
     becomes `@.worktrees/f1/internal/x.go`, which resolves inside f1 to a
     path that does not exist. That at least fails visibly.
   - Either way, refs must be computed relative to the **target session's**
     cwd, not nvim's. A file outside the target's tree should be refused, or
     sent as an absolute path with a warning. This is a small change to
     `ai_context.ref`'s `cwd` argument, but every model with more than one
     checkout needs it.

## Model 1: shared tree

One checkout, several agents in it, one nvim. This is what ships today.

### Day-to-day UX

- **Switching:** today's agent view, digits and cycle. Nothing changes.
- **Attention:** `agent_events` as now. One process sees every event.
- **Review:**
  - One `git diff` shows every agent's work mixed together, which the user
    accepts.
  - diffview and gitsigns work unchanged.
  - The catch is that you cannot tell whose half-finished edit you are
    looking at while two agents are still working.
- **Merging back:** nothing to merge. Everything is already on one branch.
- **Interference:** this is the real cost.
  - Two agents can edit the same file, and the last write wins, or one
    agent re-reads a file mid-edit.
  - One agent's build or test run sees the other's half-edits, so failures
    get misattributed and agents start "fixing" each other's work.
  - Formatters and codegen run across the whole tree.
  - `git stash`, `git checkout` or `git reset` from one agent destroys the
    other's work. This is the worst case, and nothing stops it.
  - Both agents compete for `.git/index.lock` when they commit.

### nvim mechanics

- One cwd, one set of LSP clients and one session file. Nothing new.
- Terminal count is the only scaling axis. The open risk from the lessons
  doc still applies: libvterm parses every byte on the main thread, so 6 to
  8 streaming agents need measuring.

### Worktree lifecycle

None.

### Agent-side

- Hooks keyed by name work as shipped.
- Several agents of one tool need distinct names (`claude`, `claude 2`,
  `claude: tests`), already handled.
- Resume by agent session id is still missing, but that is separate from
  isolation.

### Changes to the existing setup

None needed.

### Zed

This is Zed's default. Threads share their workspace's folders, and
worktree isolation is opt-in. Zed's docs reach for a worktree only "if two
threads might edit the same files".

### Fit with several nvims later

Neutral. Two nvims on one checkout is model 1 with the agent view split in
two. The shared-tree hazards remain and become harder to see.

### When it is right

- Read-mostly work: review, research, questions, planning.
- Agents working in clearly separate areas.
- One "doing" agent plus helpers that don't write.

## Model 2: one nvim, many worktrees

A single nvim manages agent sessions whose cwds are different worktrees.
There are two editor variants. They share the same agent layer and differ
only in how the editor itself follows a worktree.

- **2a. Switch in place.** One active worktree at a time. A switch
  changes the global cwd and moves the open files to the same relative paths
  in the new worktree. Agents in other worktrees keep running in the
  background. This is the workflow the user finds most interesting.
- **2b. Tab per worktree.** Each tab has its own `:tcd`. A worktree is a
  tab, and switching worktree means switching tab. Several worktrees are
  live in the editor at once.

Both variants start nvim at the main root of a repo that uses the nested
layout.

### Day-to-day UX

- **Switching the editor (2a):**
  - One command or picker changes worktree. cwd, pickers, the file tree,
    the title and the statusline all follow.
  - Mechanics are in `worktree-switching.md`. The topology questions are:
    - what happens to modified buffers in the old worktree (block, save, or
      keep them);
    - whether old buffers are wiped or kept hidden;
    - whether old LSP clients are stopped.
- **Switching the editor (2b):** `gt` or a tab picker. Each tab keeps its
  own layout, which is the nearest nvim analogue of Zed's retained
  workspaces (see the Zed section).
- **Switching agents:**
  - The agent view lists rows from every worktree.
  - Picking a row in another worktree raises the main design question:
    - **Peek:** show that agent's terminal in the view, but leave the
      editor where it is.
    - **Follow:** also switch the editor to that worktree.
  - Zed follows: selecting a thread activates its workspace.
  - Peek suits a quick permission prompt. Follow suits reviewing what the
    agent did. A sensible default is peek, with an explicit follow key, but
    that is the user's call.
- **Attention:**
  - Every event reaches this one nvim, so the existing
    `agent_events` deferral, ack and `<leader>aj` work across worktrees with
    no transport change.
  - Rows and notifications need the worktree name, because "claude needs
    permission" is ambiguous once there is one `claude` per worktree.
- **Review:**
  - This is where isolation pays off. Inside a worktree, plain `git diff`
    (or diffview opened there) shows exactly that worktree's agents' work.
    No attribution layer is needed.
  - In 2a you review the active worktree. Reviewing another one means
    switching to it, or pointing diffview at that path.
  - In 2b you review in that worktree's tab.
- **Merging back:**
  - Each worktree has its own branch: PR, `git merge`, or cherry-pick from
    the main root.
  - Refs are shared, so nothing needs fetching between checkouts.
  - With long-lived slots, "merging back" really means "push the branch and
    reset the slot". That is the slot controller's job, not nvim's.

### nvim mechanics

- **LSP:**
  - One client per (server, worktree root).
  - In 2a, clients for worktrees you have left stay alive until stopped.
    You need a reaper that stops clients with no attached buffers after a
    switch, or the count grows with every worktree visited in a session.
  - In 2b, every open tab's clients are live at once. That is the design,
    and it is the cost.
  - For a large Go or TypeScript repo, one gopls or ts_ls client commonly
    runs to hundreds of MB, and up to a few GB on monorepos. Measure on the
    real repo before choosing 2b with 4 or 5 tabs.
  - A client rooted at the main root may also index `.worktrees/` (see the
    nested-layout section).
- **Buffers and paths:**
  - The buffer list is global in both variants.
  - In 2a, a switch that wipes the old worktree's buffers keeps the list
    clean. Without wiping, you get two `internal/x.go` buffers with the
    same tail.
  - 2b always has that duplication. Buffer pickers, bufferline and the
    title show identical tails from different checkouts.
  - Tabs do not isolate buffers in nvim. They isolate only layout and cwd.
- **Sessions (persistence.nvim):**
  - Keyed by global cwd plus branch.
  - In 2a, on quit the session saves under whichever worktree was active
    last. Restarting at the main root then loads main's older session.
  - The options are:
    - save and load per worktree on every switch (the before/after-switch
      session recipe the upstream `git-worktree-nvim-plugin.md` points to);
    - always key the session to the main root and record the active
      worktree.
  - This is a `worktree-switching.md` question, but the choice affects
    whether "reopen where I was" includes the agents.
  - In 2b, mksession should record tab-local directories (to verify), but
    the session file is still keyed by the global cwd.
- **File tree:**
  - nvim-tree's root does not follow `:cd` unless
    `sync_root_with_cwd` is set, and it is not set today (`filetree.lua`).
  - 2a needs it, or a re-root on switch.
  - 2b needs nvim-tree's per-tab behaviour checked.
- **Pickers:**
  - snacks uses the effective cwd, so pickers follow `:cd` (2a) and `:tcd`
    (2b) for free.
  - Grep at the main root stays out of `.worktrees/` only if it is ignored.
- **Statusline and title:**
  - Show `repo:worktree`, not the worktree basename alone.
  - `titling.lua` already re-computes on `DirChanged`. It needs the main
    root, which it can get from `git rev-parse --git-common-dir`.
- **Terminals and jobs:**
  - All agents from all worktrees live in one process. There is no
    practical limit on job count in nvim.
  - Main-loop parsing cost grows with the number of busy agents (lessons
    doc, "Constraints and risks").
  - **Blast radius:** one nvim crash or `:qa` kills every agent in every
    worktree. The only remedies are resume by id, which loses running turns,
    and a mux backend, which keeps them.
- **The agent view is a tab.**
  - In 2b, it is one more tab among worktree tabs, and it is global, not
    per worktree.
  - `agentview.is_active()` and sidekick's "current tab" show paths have
    never been tested against user-level worktree tabs. Upstream
    `sidekick-agent-view.md` flags that combination as untested.

### Worktree lifecycle

- **Long-lived slots (the user's real repo):**
  - Slots already exist and are set up by the slot controller. nvim only
    needs to list them and switch.
  - nvim must never delete a slot. It does not own it.
  - Branch changes inside a slot happen through the slot controller or
    Neogit. To nvim they look like a branch switch, and the
    persistence-per-branch rule then applies.
- **Throwaways:**
  - Created from nvim with `git worktree add --detach`, plus an async setup
    hook.
  - Archived Zed's way: WIP commits pinned by a ref, deleting only
    worktrees nvim created, and re-statting before delete (lessons doc
    section 9).
  - In a heavy repo they must stay code-only (no services). The existing
    throwaway plan reached that conclusion, because a throwaway inherits
    the main checkout's port and container settings.
  - Under the nested layout, throwaways at `.worktrees/<adjective-noun>`
    would mix with slots. A separate prefix such as `.worktrees/tmp/<name>`,
    or a sibling directory, keeps "nvim may delete this" visually distinct.
- **Disk:** one full checkout per worktree, plus untracked deps. In the
  heavy repo, dependency directories alone run to over a GB per worktree.
  That argues for few long-lived slots over many throwaways.

### Agent-side

- **An agent's cwd is fixed at spawn.** A CLI cannot follow the editor to
  another worktree. A 2a switch therefore never moves agents. It only
  changes which agents are "local" to the editor.
- **Hooks.**
  - Claude hook stdin carries `cwd` and `session_id` on every event. The
    bridge already forwards the raw payload, so grouping by worktree can
    come from the event itself, as well as from spawn-time bookkeeping.
  - omp's extension bridge sends no cwd today. Spawn-time bookkeeping
    covers it.
- **Resume by id.**
  - Claude stores sessions per project directory, keyed by cwd. So
    `--resume <id>` must run from the same worktree path. That is believed
    true, to verify.
  - A persisted row must record its cwd, not just the tool and id.
  - Long-lived slots help here: their paths are stable, while throwaway
    paths may be re-created somewhere else.
- **Nested-layout effects** (see that section): stacked `CLAUDE.md` files,
  config fallthrough to the main checkout, and a main-root agent's scope
  covering the worktrees.

### Changes to the existing setup

- **Identity must stop being the name.**
  - With one `claude` per worktree, the same name in two cwds becomes the
    normal case, not an edge.
  - You need a row id, with `tool`, `cwd`, `worktree_root`, `main_root`
    and `agent_session_id` as attributes. This is the registry in the
    lessons doc's option B.
  - `$SIDEKICK_SESSION` carries the row id, and `agent_events` keys by it.
  - Labels become display-only and may repeat across worktrees.
- **Spawn needs an explicit cwd.** sidekick derives cwd from
  `getcwd(0)`. Spawning in worktree B while the editor is on A (peek, or
  "new agent in slot f2") needs one of:
  - a temporary `:lcd` around `cli.show`, which is fragile because
    `cli.show` schedules twice before it spawns;
  - an owned spawn (`jobstart({ term = true, cwd = ... })`);
  - an upstream cwd option.

  This is a direct input to `sidekick-assessment.md`.
- **Name-only toggles become cwd-dependent.**
  - `<leader>aa`, `ai.focus` and sends resolve by name, with sidekick
    preferring the current cwd.
  - They must resolve by row id instead, or the same key reaches a
    different agent depending on which worktree the editor is in.
- **The agent view groups by main root, then worktree.**
  - The grouping key is `dirname(git rev-parse --path-format=absolute --git-common-dir)`
    (lessons doc section 9).
  - This breaks the shipped flat invariant "digits = name order = cycle
    order" (upstream `sidekick-agent-view-internals.md`, invariant 8). The
    new invariant would be "digits = display order, within or across
    groups".
- **Context refs** are computed relative to the target session's cwd (see
  the nested-layout section).
- **Pre-warm.** It warms one `claude` in the startup cwd, which is the main
  root. In 2a it could follow the active worktree, or stay at the main root
  as the "home" agent. A pre-warm per worktree is wasteful.
- **Notification titles** need a worktree suffix.

### Zed

Close to Zed, with one difference. Zed keeps every worktree as a retained
workspace inside one window, with one shown at a time and the sidebar
grouped by main repo. In nvim, 2b is the structural match. 2a matches Zed's
create flow, where open files carry over (see the Zed section).

### Fit with several nvims later

- Each nvim holds its own set of worktrees, so the overview problem from
  model 3 returns.
- Designing rows with cwd and main root, and making the registry
  serialisable, keeps that door open.

## Model 3: one nvim per worktree

Each worktree gets its own nvim: a Ghostty tab, a zellij or herdr pane, or
a Neovide window. Each nvim has its own agents.

### Day-to-day UX

- **Switching:** at the OS or multiplexer level, by terminal tab, pane or
  Neovide window. Each instance keeps full context, so there is no remap
  and no stale state.
- **Finding the agent that needs you:** this is the weak spot.
  - Each nvim sees only its own events, and the agent view only its own
    sessions. That is by upstream decision.
  - Without a cross-instance layer, you learn about a blocked agent in
    another worktree only from the desktop notification. Today that title
    says `claude`, with no worktree.
- **Review:** the same good property as model 2. `git diff` in each
  instance is exactly that worktree's work.
- **Merging back:** the same as model 2.
- **Sending context across worktrees:** impossible, and rarely wanted.

### Cross-instance awareness, if wanted

There are four mechanisms, from least to most coupled.

1. **Shared state directory.**
   - On each event, every nvim's `agent_events` writes a snapshot to
     `stdpath('state')/agents/<pid>.json` with an atomic rename. The
     snapshot holds rows with `{ id, label, worktree, main_root, status,
     servername }`.
   - An overview (any nvim, or a script) reads the directory, watches it
     with `vim.uv` fs_event, and drops files whose pid is dead.
   - It is event-driven, which matches the "no polling, no timers" rule in
     `sidekick-agent-view.md`.
   - It survives a crashed instance, because the stale file is detectable.
   - It reuses the same row serialisation that persistence needs anyway.
2. **RPC discovery.**
   - nvim 0.12's `serverlist({ peer = true })` returns the sockets of
     other running nvims (verified in the local 0.12.6 help; not supported
     on Windows).
   - An overview can query each one for
     `require('agent_events').snapshot()` when it opens. That is pull on
     demand, not polling.
   - It needs no files, but costs one RPC per instance on every open, and
     it hangs on a wedged instance unless each call has a timeout.
3. **Hooks also write to a common place.**
   - `sidekick-notify.sh` appends each event to a shared log as well as
     sending the RPC.
   - It is the simplest to add, but it duplicates the state machine
     outside nvim, where the ack and deferral rules don't exist.
4. **The multiplexer is the overview.**
   - Herdr is already adopted outside nvim (upstream
     `sidekick-agent-view.md`, "Could Herdr have replaced this build?").
   - It can show one pane per worktree, but its status detection is screen
     scraping, the heuristic class the view's design banned.

**Jumping to the instance that needs you** has two halves.

- **Inside nvim:** `nvim --server <servername> --remote-expr
  "v:lua.require('ai').jump_unread()"`. This is already proposed in
  `sidekick-agent-view.md` ("Unbuilt upgrades" item 2) for notification
  clicks.
- **The OS window:** raising the right Ghostty tab or Neovide window is
  outside nvim. That is the unsolved part (see open questions).

### nvim mechanics

- Everything works as it does today. Global cwd, persistence keyed per
  directory, LSP root detection, pre-warm and the in-process agent view all
  hold, because each process is a single-project nvim.
- The upstream `git-worktree-nvim-plugin.md` calls this "Option 0" and
  says it is correct by construction, with no stale state, and "arguably a
  feature" when switches are rare.
- **Cost:**
  - one full nvim per worktree: plugins, treesitter and its own LSP
    clients;
  - no LSP sharing between worktrees, though model 2 doesn't share them
    either, since roots differ;
  - the base nvim footprint, multiplied.
- **Blast radius:** one crash kills only that worktree's agents.

### Worktree lifecycle

- Creation happens outside nvim, through the slot controller or a shell,
  or from a "home" nvim (model 4b).
- Cleanup is the same as model 2.
- Long-lived slots fit naturally: one terminal tab per slot, and
  persistence restores each slot's editor state.
- The upstream `zmx-session-persistence.md` already assumes this shape. Its
  success criterion 3 is two projects in two nvims, each with independent
  sessions.

### Agent-side

- The name-keyed identity is fine inside each instance.
- `$NVIM` routing isolates events per instance. Run the pipeline doc's
  verification step 6 to confirm it.
- An overview must key rows by `(instance, row id)`, or by agent session
  id.

### Changes to the existing setup

- **Minimum:** worktree names in notification titles and the statusline.
- **With an overview:**
  - `agent_events.snapshot()` and a writer for the state directory;
  - an overview UI (a picker is enough);
  - a jump RPC.
- The shipped agent view stays exactly as it is.

### Zed

This is Zed's "open in new window" option, not its default.

### Fit with several nvims later

This is that future, made deliberate.

## Model 4: hybrids

### 4a. Home nvim, agents anywhere

- nvim stays at the main root and never switches. Agents are spawned with
  their cwd in a chosen worktree.
- You review a worktree by opening its files by path (short, thanks to
  nesting), or with diffview pointed at that worktree.
- This is model 2's agent layer without the editor switch. It is the
  smallest useful step from today: an explicit spawn cwd, a row id, grouping
  in the view, and target-relative refs.
- It is also the base that 2a and 2b both build on.
- **Weakness:** LSP, pickers and the title all describe the main root, so
  editing inside a worktree feels second-class. That is exactly what 2a's
  switch fixes.

### 4b. Main nvim, with pop-out instances

- Day to day you work in 2a. For a long focused stretch in one worktree,
  you "pop out" a Neovide window or terminal tab for it.
- **Hard constraint:** an agent is a child job of the nvim that spawned
  it. In a terminal editor an agent cannot move between instances.
  - The only ways are kill and resume by id, which loses scrollback and any
    running turn, or a mux backend that owns the process.
  - Zed has no such limit, because all its windows are one process.
- So a pop-out either leaves its agents behind in the main nvim, or needs
  resume or mux first.

### 4c. Shared tree by default, worktree on demand

- Start agents in the active checkout (model 1). Move a task to a slot only
  when it will touch the same files, or run builds that interfere.
- This is Zed's own default posture.
- It works on top of 2a or 4a. The agent layer just has to allow a per-row
  cwd.

### 4d. Agents hosted in a mux, any nvim attaches

- Agents run under tmux, zellij or zmx, and nvim panes attach to them.
- Agent lifetime is then decoupled from nvim. "One nvim versus many"
  becomes a view choice, and blast radius disappears.
- **Costs:**
  - sidekick's mux backends shell out on every `State.get`, the
    ~40 ms-per-call problem `ai.lua` stubs out today;
  - focus-event passthrough (`sidekick-agent-view.md` says re-verify
    FocusGained/FocusLost inside a mux);
  - nesting when nvim itself runs in a mux.
- It is the strongest form of persistence and the heaviest. It is
  orthogonal to the topology choice, so it can be deferred.

### 4e. Slots for service work, throwaways for code-only work

- This mixed lifecycle comes from the existing slot and throwaway plans:
  - long-lived slots run services;
  - throwaways are code-only, guarded so they cannot reach the main
    checkout's containers or ports.
- Any model 2, 3 or 4 variant can host it. The session layer only needs
  "use an existing worktree" alongside "create one". The lessons doc makes
  the same point.

## What Zed chose, and how well it suits a terminal editor

What the Zed code at HEAD `596dfdcf32` does:

- **Worktrees are opt-in, not per thread.** Threads share their workspace.
  A worktree comes from the title-bar picker, the sidebar header menu, or
  the agent's flagged `create_thread` tool.
- **The default switch opens the worktree as its own workspace in the same
  window, not a new window.**
  - `git_ui_core/src/worktree_service.rs` calls
    `multi_workspace.find_or_create_workspace(..., OpenMode::Add, ...)` and
    then `multi_workspace.activate(...)`.
  - The worktree workspace is retained alongside the others in one window,
    and one is shown at a time.
  - "Open in new window" is a separate picker button.
  - So the framing "a worktree opens as its own workspace and window" is
    half right: own workspace, same window by default.
- **Open files carry over only on create.**
  - `transfer_state = is_creating_new_worktree && activate`. Only when you
    create a worktree in the foreground are the open files remapped to the
    new paths, along with the active file and dock layout.
  - Switching to an existing worktree shows that workspace's own retained
    state.
  - A background create (the agent tool) starts clean.
- **Each workspace has its own project**, so its own language servers. The
  memory profile is the same as nvim's 2b.
- **The sidebar groups threads under the main repo** (`ProjectGroupKey`,
  which maps linked worktrees to their main worktree), with a worktree chip
  on each row.
- **Placement is sibling by default** (`../worktrees`), worktrees start
  detached, and Zed only deletes worktrees it created (re-statted before
  delete).

How that maps onto nvim:

- **Zed's retained workspaces map to 2b**, a tab per worktree. Each keeps
  its own layout and cwd. But nvim's buffer list stays global, so a tab is a
  weaker boundary than a Zed workspace.
- **The user's 2a is Zed's create-time transfer applied to every switch.**
  That is reasonable for long-lived slots, where "same file, other branch"
  is the common comparison. It needs a policy for modified buffers, which
  Zed avoids by retaining the old workspace.
- **Grouping by main repo carries over directly.** It is just a key on the
  row.
- **What does not carry over:**
  - Zed is one process for all windows and workspaces, so a thread is never
    tied to the window that started it.
  - In nvim the agent is a child of one process. That makes model 3's
    overview and 4b's pop-out real problems that Zed never has.
- **Zed's default location assumes throwaways.** Sibling placement and
  detached HEADs suit short-lived worktrees. The user's nested, long-lived
  slots are a different lifecycle, which Zed only supports through its
  "existing worktree" path.

## Comparison matrix

Cell text is deliberately short. See the sections above for the reasoning.

| Criterion | 1 shared | 2a switch in place | 2b tab per wt | 3 nvim per wt | 4a home nvim |
| --- | --- | --- | --- | --- | --- |
| Agents interfere | yes | no | no | no | no |
| `git diff` per task | mixed | per wt | per wt | per wt | per wt |
| One window | yes | yes | yes | no | yes |
| Overview of all agents | built | built | built | needs work | built |
| Editor follows worktree | n/a | yes | per tab | always | no |
| Stale state on switch | none | some | none | none | n/a |
| LSP clients alive | 1 set | 1 set + reaper | 1 set per tab | 1 set per nvim | main + visited |
| Duplicate buffer tails | no | if not wiped | yes | no | some |
| Crash blast radius | all | all | all | one wt | all |
| Identity rework needed | no | yes | yes | for overview | yes |
| Explicit spawn cwd | no | yes | tcd covers | no | yes |
| Persistence keying | as now | needs policy | tcd in session | as now | as now |
| Context refs across wt | n/a | target-relative | target-relative | n/a | target-relative |
| Code change from today | none | large | large | small to medium | medium |
| Matches Zed default | yes | partly | closest | no | partly |
| Fits slots | n/a | yes | yes | yes | yes |
| Fits many throwaways | n/a | ok | tab sprawl | window sprawl | yes |

## Decision criteria

These are questions about the user's own workflow. Each answer pushes
toward a model.

1. **How many agents run at once, and how many of them write?**
   - Two or three, mostly reading or in separate areas: model 1 is enough.
   - Several writing agents: worktrees.
2. **Do concurrent agents touch the same files, or run builds and tests that
   would see each other's half-edits?** Yes means worktrees. No means a
   shared tree is fine, and the user already accepts mixed diffs.
3. **Does the repo need heavy setup per checkout?** (deps, env files,
   databases, ports, generated code)
   - Yes means long-lived slots. Every model can sit on slots, but
     throwaways must stay code-only.
   - No makes throwaways per task cheap, which favours 4a or 2a with
     create and archive.
4. **Do you want one window?** Yes means model 2 or 4a. If you are happy
   with one terminal tab or Neovide window per worktree, model 3 is the
   least code.
5. **How often does the editor change worktree, and should context follow?**
   - Often, keeping open files: 2a.
   - Often, keeping each worktree's own layout: 2b.
   - Rarely, wanting a clean slate: model 3 (upstream
     `git-worktree-nvim-plugin.md`, Option 0).
6. **When an agent in another worktree needs you, should the editor go
   there (follow) or only show the terminal (peek)?** Follow-first suits
   2b or 3. Peek-first suits 2a or 4a.
7. **Do you send editor context (selections, `@file` refs) to agents in
   other worktrees?** If yes, refs must be relative to the target. If
   never, model 3's isolation costs nothing.
8. **Can one nvim restart kill every agent?** If not, choose model 3,
   resume by id, or a mux (4d).
9. **What is the memory budget for LSP per worktree on the real repo?** It
   decides whether 2b with every slot open is viable.
10. **Will several nvims exist anyway** (Neovide plus terminal, or
    multiplexer panes)? If yes, plan the serialisable registry and overview
    now, whichever model is primary.
11. **Branch policy:** named branches in slots (the slot controller) or
    detached throwaways (Zed)? It affects persistence-per-branch and
    archive design.

## Leaning

**Lean towards model 2a on top of 4a, over the existing long-lived nested
slots, with model 1 as the default for light parallel work.**

In practice:

1. **First build the agent layer of 4a.**
   - Session rows with an explicit cwd, keyed by a row id.
   - The agent view grouped by main root, then worktree.
   - Worktree names in notifications.
   - Context refs relative to the target session.

   This is useful on its own: agents in slots, editor at the main root. It
   is also the common base of 2a, 2b and 4c.
2. **Then add the 2a editor switch** (mechanics per `worktree-switching.md`),
   kept independent of the agent layer.
   - Agents never move.
   - The agent view offers peek by default and follow on an explicit key.
3. **Keep model 3 possible** by making the registry serialisable, which
   persistence needs anyway. A later overview of several instances can then
   read the same snapshots from a state directory.

Why:

- **It matches the stated workflow.** It is one nvim at the main root with
  the files following, and the nested layout makes that natural, since
  every slot is a short relative path away.
- **Isolation delivers review for free, which is what the user wants.**
  Per-worktree `git diff` and diffview are already the review tools, so no
  per-agent tracking is needed. Model 1 stays available when isolation
  isn't worth a slot.
- **2a over 2b:**
  - nvim tabs don't isolate buffers, so 2b's extra structure buys duplicate
    tails and every slot's LSP clients alive at once.
  - The agent view is already a tab and would compete with worktree tabs.
  - `:tcd` silently changes sidekick's spawn cwd, which is exactly the kind
    of implicit state a multi-worktree layer should remove.
  - 2b is the closer match to Zed, and its retained per-worktree layout is
    genuinely nicer. If 2a's "what happens to my modified buffers" policy
    proves annoying, 2b is the fallback. Because the agent layer is shared,
    switching between the two later is cheap.
- **Model 3 is less work but weaker where the user wants strength.**
  Attention across instances, sending context, and one window are all
  harder in model 3.
  - It stays the right answer for rare, clean-slate switches, and it is the
    natural degradation if a second nvim appears.
  - The shared state directory makes it a cheap add-on later.

Risks to watch in this leaning:

- **One process holds every agent.** Measure main-loop cost with 6 to 8
  streaming agents across slots. The blast radius stays until resume by id
  exists.
- **LSP clients for visited worktrees pile up without a reaper.**
- **A main-root agent can wander into `.worktrees/`.** Treat it as a
  read-mostly "home" agent, or tell it the layout explicitly.

## Decide early versus defer

### Decide early

These shape the code everything else sits on.

- **Session identity is a row id, not the name.** Rows carry `tool`,
  `cwd`, `worktree_root`, `main_root` and `agent_session_id`.
  - Model 2 needs it at once.
  - Model 1 doesn't mind it.
  - Model 3's overview needs it.
  - Doing it later means migrating every name-keyed path in `ai.lua` and
    `agent_events` twice.
- **Spawn takes an explicit cwd.** The implicit `getcwd(0)` behaviour is
  a sidekick property. Whether it is wrapped, patched or replaced is a
  `sidekick-assessment.md` decision, and it needs this requirement as an
  input.
- **Agents are fixed to their spawn cwd and never follow the editor.** The
  agent view's row actions are then peek and follow, nothing implicit.
- **Ownership of worktrees.** Slots belong to the user and the slot
  controller, and nvim never deletes them. Only worktrees nvim created can
  be archived or removed.
  - Decide the throwaway location now, so the two kinds never mix: a
    separate prefix under `.worktrees/`, or sibling.
  - Make sure `.worktrees/` is ignored in the main root.
- **Path policy for context refs:** relative to the target session's cwd,
  and refuse or absolutise across checkouts.

### Defer

- 2a versus 2b. This is editor-side and can change without touching the
  agent layer.
- Follow-versus-peek defaults and key choices.
- The cross-instance overview mechanism (state directory or `serverlist`
  RPC), as long as the registry can produce a snapshot.
- Throwaway archive and restore with WIP commits plus a ref. That is only
  needed if throwaways become common, and the slots make them rarer.
- Mux-hosted agents (4d).
- Visual details of grouping in the view, such as digit scope.

## Open questions

1. **LSP memory per worktree on the real repo.** How much does one gopls,
   ts_ls or pyright client cost there? Does a client rooted at the main root
   index `.worktrees/` unless it is excluded?
2. **Stacked instruction files.** Confirm that Claude Code in
   `.worktrees/<name>` loads the main checkout's `CLAUDE.md` too, and
   decide whether that is wanted. Check which project `.claude/` settings
   apply. Check the same for omp and its `AGENTS.md` lookup.
3. **Resume across paths.** Does `claude --resume <id>` find a session only
   from the cwd it ran in? Where does omp store sessions, and what id does
   its extension API expose?
4. **Two-nvim routing.** Run step 6 of the event pipeline doc's
   verification (two nvims, same repo) before relying on `$NVIM` isolation
   in models 3 and 4b.
5. **Name toggles across worktrees.** Which session does `<leader>aa`
   attach to when same-named sessions exist in two worktrees and the
   editor's cwd is a third? This decides how urgent the identity rework is
   in 4a.
6. **Raising the OS window for model 3.** Can a notification click raise
   the right Ghostty tab, Neovide window or herdr pane, and not only call
   into the right nvim?
7. **Persistence under 2a.** Should there be one session per worktree,
   saved and loaded on switch, or one session at the main root that
   records the active worktree? Should restored session rows include
   dormant agents (lessons doc section 10)?
8. **Config fallthrough.** Which gitignored files in the main checkout do
   nested worktrees currently inherit by walking up: `.envrc`, env files,
   local config? Is each inheritance intended?
9. **Watcher load.** Does nvim-tree's git watcher at the main root, or
   LSP file watching, react measurably to agents writing in nested
   worktrees?
10. **Tab-local dirs in sessions.** Does persistence.nvim's mksession
    record `:tcd` per tab, and restore it, if 2b is ever chosen?
11. **The pre-warmed agent under 2a.** Should it follow the active
    worktree, or stay at the main root as the home agent?
12. **Throwaway placement.** Should throwaways go under `.worktrees/` with
    a distinct prefix, or in a sibling directory as Zed does? Should nvim
    create them at all, or should that stay with the slot controller and
    the shell?
