# Decisions to make

Everything still open for the nvim parallel-agents work, written so it can
be picked up cold. Each decision has background, options with trade-offs,
the research's leaning, and what it depends on. Leanings are the research
agents' recommendations, not decisions. Compiled 2026-11-22 from the five
research docs in this folder (see [README.md](README.md)).

Read the top of the README first. [Before building: Zed + vim mode + a
fork?](README.md#before-building-zed--vim-mode--a-fork-2026-11-22) asks
whether to build in nvim at all (D0). [Synthesis so
far](README.md#synthesis-so-far-2026-11-22) argues, if building in nvim, for
settling D2 and D3 first, building agents-in-any-worktree before the editor
switch, and letting D1 wait.

How to use this:

1. Settle D0 (Zed or nvim), ideally with the one-week trial. The rest
   only matters if nvim stays in the picture.
2. Answer the workflow questions in [Start here](#start-here-workflow-questions).
   They drive the topology choice (D1), and most other decisions follow
   from it.
3. Settle the **foundational** decisions (D1 to D4). They shape the code
   everything else sits on.
4. Run the [measurements](#measurements-to-run-before-deciding) that gate
   the LSP and terminal-count decisions.
5. Do feature triage (D20) and the detail decisions in any order.

When a decision is made, move it to [Already decided](#already-decided)
with the date and a one-line reason, and update the README.

## Already decided

- **Terminal mode, not ACP** (2026-11-22). Agent CLIs run in nvim terminal
  buffers. A native ACP chat client in Lua is out of scope.
- **No action log or per-agent diffs** (2026-11-22). Plain `git diff` /
  diffview / gitsigns, with changes from several agents mixed together, is
  enough. Per-turn checkpoints are out: Zed removed them because git
  snapshots took tens of seconds on large repos. A once-per-session "diff
  since session start" baseline (`git stash create` at spawn, then
  `DiffviewOpen <ref>`) stays optional, only if it falls out for free.
- **Resume by id is enough to survive an nvim restart** (2026-11-22). A
  running agent turn does not have to survive. Keep two later extensions
  in mind:
  - a tmux layer hosting agent processes so they outlive nvim
  - a layered strategy: resume by id by default, tmux-hosted sessions as
    an opt-in for long runs
- **External multiplexers (herdr, Orca) are not alternatives**
  (2026-11-22).

## Start here: workflow questions

From `isolation-analysis.md` → Decision criteria. Each answer pushes toward
a topology (D1).

1. **How many agents at once, and how many of them write files?** Two or
   three, mostly reading: a shared tree is enough. Several writing:
   worktrees.
2. **Do concurrent agents touch the same files, or run builds and tests
   that would see each other's half-finished edits?** Yes means worktrees.
3. **Does the repo need heavy setup per checkout** (deps, env files,
   databases, ports, generated code)? Yes means long-lived slots, and
   throwaway worktrees must stay code-only.
4. **Do you want one window?** Yes means one home nvim (D1 options A/B).
   Fine with a terminal tab or Neovide window per worktree: nvim per
   worktree (option C) is the least code.
5. **How often does the editor change worktree, and what should follow?**
   Often, keeping open files: option A. Often, keeping each worktree's own
   layout: option B (or A with working sets, see D6). Rarely, wanting a
   clean slate: option C.
6. **When an agent in another worktree needs you, should the editor go
   there (follow) or only show its terminal (peek)?** See D12.
7. **Do you send editor context (selections, file refs) to agents in other
   worktrees?** If yes, D13 matters. If never, nvim per worktree loses
   nothing here.
8. **Is it acceptable that one nvim crash kills every agent?** Resume by
   id softens this (decided above). If it's still not acceptable, that
   points to nvim per worktree or a tmux layer.
9. **What's the LSP memory budget per worktree?** Decides whether keeping
   several worktrees' language servers alive is viable (D8).
10. **Will several nvims exist anyway** (Neovide plus terminal)? If yes,
    make the session registry saveable to disk now so an overview across
    instances can be added later.
11. **Branch policy:** named branches in long-lived slots, or detached
    throwaways per task (Zed's way)? Affects D5.

## Foundational

### D0. Zed or nvim

**Background.** Zed already ships most of what this plan would build:
parallel threads, worktrees as separate workspaces, per-directory
environments, sidebar grouping. If Zed with vim mode works well enough,
minor features could be added through a fork instead of building the nvim
side. Full write-up: README → [Before building: Zed + vim mode + a
fork?](README.md#before-building-zed--vim-mode--a-fork-2026-11-22).

Status from the parity docs (2026-11-22): **the premise is untested.**
`vim_mode` is off in the stowed `settings.json`, and only two rows of
`docs/zed-vim-keymap.md` are adopted. On paper:

- **Editing parity is strong.** The core keys are identical, and Zed has
  some things the nvim config doesn't: tree-sitter text objects, surround,
  multiple cursors.
- **Zed already does the worktree switching** this plan would build, and
  the stowed config is set up for it (`cmd-ctrl-w`, per-worktree direnv,
  `.worktrees/` excluded).
- **The open questions are the GUIDE.md Lua customisations, and the agent
  attention model** (terminal threads are thin; ACP threads are rich but
  route Claude through the adapter).

Current leaning: towards A, pending the trial.

**Options.**

- **A. Zed with vim mode, Claude as ACP threads, small fork patches.**
  - For: the hard parts are built and maintained by a full-time team; only
    additions need maintaining.
  - Against: must use ACP threads (terminal threads are thin), so check
    which Claude Code CLI features survive the ACP adapter; Zed's attention
    model is weaker (no jump-to-attention, no global badge), and porting
    the nvim one is real Rust/GPUI work; forks touching `agent_ui` need
    frequent painful rebases and self-built releases; vim mode isn't nvim;
    per-worktree env only when launched from the GUI.
- **B. Build in nvim** (the rest of this doc).
  - For: keeps nvim editing and the existing, better attention model; full
    control.
  - Against: a lot to build and maintain (session layer, own backend,
    worktree switching).
- **C. Both.** Zed for multi-agent work, nvim for editing. Splits the
  workflow across two editors.

**How to settle it.** A one-week trial of option A on real parallel-agent
work:

- turn `vim_mode` on
- paste the keymap doc's block into `keymap.json`
- run Claude as ACP threads and omp as a terminal thread
- switch between the long-lived worktrees with `cmd-ctrl-w`

Keep a list of what's missed, sorted into "Zed settings fix it", "a
small fork patch fixes it", and "needs nvim". Mostly the first two: pick A,
and the nvim plan shrinks to "keep sidekick as is". Otherwise: B, with the
trial list as evidence.

**Affects.** Everything below. D1 to D20 only matter if B or C wins. Step
0's measurements and the session-id registry (D2) are cheap enough to do
either way.

### D1. Topology: how sessions map to checkouts and nvim instances

**Background.** Parallel agents need to be kept apart somehow, or at least
to coexist. The question is whether nvim follows a worktree, hosts many,
or whether there's one nvim per worktree. Zed opens a worktree as a
separate workspace in the same window (own project, language servers,
panels, open files) and switches which one is shown. Open files carry over
only when a worktree is created. Detail: `isolation-analysis.md`,
`worktree-switching.md` → How Zed does it.

**Options.**

- **A. One home nvim, global `:cd` switch** ("2a"). One nvim at the repo's
  main root; switching runs `:cd .worktrees/<name>` for the whole editor,
  and the file tree, pickers, statusline and LSP follow. Agents stay in
  the directory they started in.
  - For: one window, one consistent "current worktree", the simplest
    mental model; matches the stated "open nvim at the root and switch"
    workflow; nested `.worktrees/` makes every slot a short path away.
  - Against: only one worktree in view at a time; every switch is a
    context switch (buffers swap, other language servers attach); one
    process holds every agent; agents need an explicit start directory
    (so sidekick's spawn must be replaced first, see D3).
- **B. Tab per worktree** ("2b"). Each tab has its own `:tcd`.
  - For: several worktrees side by side; closest to Zed's retained
    per-worktree layout.
  - Against: nvim tabs share one buffer list, so you get duplicate
    `bar.go` entries from different checkouts; every worktree's language
    servers stay alive; competes with the agent view, which is already a
    tab; `:tcd` silently changes where sidekick spawns agents.
- **C. nvim per worktree.** A separate nvim (terminal tab or Neovide
  window) per worktree, each with its own agents.
  - For: natural isolation and the least code; a crash only takes out one
    worktree's agents.
  - Against: finding "the agent that needs me" across instances needs a
    shared state directory or RPC via `serverlist({peer=true})`; raising
    the right OS window from a notification is unsolved; sending context
    across worktrees is harder; many windows to juggle. Event routing
    between two nvims has never been tested.
- **D. Shared tree.** One checkout, several agents in it.
  - For: zero setup; fine for light or read-mostly work.
  - Against: agents see each other's half-finished edits and break each
    other's builds and tests.

**Leaning.** A on top of an agent layer that lets agents run in any
worktree ("home nvim, agents anywhere"), over the existing long-lived
slots. Keep D (shared tree) as the default for light work. B is the
fallback if A's buffer handling proves annoying; both share the agent
layer, so switching later is cheap. Keep C possible by making the
registry saveable to disk.

**Affects.** Build order (D3), buffer policy (D6), LSP (D8), follow/peek
(D12). **Can be deferred:** A versus B specifically, since it's
editor-side and doesn't touch the agent layer. **Must be decided early:**
that agents have an explicit start directory and never follow the editor.

### D2. Session identity and how attach keys resolve

**Background.** Today a session is identified by its name (`claude`,
`claude 2`). Attaching by name finds that session or starts one. This
breaks with worktrees (two `claude` sessions in different worktrees
collide), can't survive a restart (sidekick's tmux restore turns
`claude 3` into a second plain `claude`), and gives resume nothing stable
to key on. Zed keeps a local id separate from the agent's own session id
and from the display title. Detail: `zed-design-lessons.md` §2,
`sidekick-assessment.md` §9 step 2.

**Options.**

- **A. Keep name-based identity.** No migration, but blocks worktrees,
  persistence and resume.
- **B. Opaque ids, display-only labels.** Each session gets an id (e.g.
  `claude#7`) that's saved, used for resume and mapped to the agent's own
  id (Claude's `--resume <session_id>`). The label (`claude · feature-1`)
  is display-only, renamable, and may repeat.
  - Gains: renames don't break anything; same-named sessions in different
    worktrees coexist; dormant sessions come back as the same session.
  - Cost: "open the session named X" no longer has a guaranteed answer.
    Repeating a `<leader>an` label would create a new session rather than
    reattach.
- **C. B plus scoped lookup (suggested middle ground).** Ids are the real
  key, and the attach keys resolve by rule. For example, `<leader>aa`
  attaches to the most recently used session of that tool *in the current
  worktree* and starts one only if none exists. A picker covers the rest.

**Leaning.** C. It must be decided early: every name-keyed path in
`ai.lua` and `agent_events` would otherwise be migrated twice.

**Sub-decisions.**

- What exactly does each attach key resolve to (current worktree, or
  global MRU)?
- Keep the names `sidekick_terminal` (filetype) and `SIDEKICK_SESSION`
  (env var) for compatibility, or rename once across all producers? See
  D19.

### D3. Session manager: build on sidekick, wrap it, or replace it

**Background.** sidekick.nvim spawns and tracks the agent terminals today.
Its session model is (tool name, cwd), and a session only exists while
its process runs. It always spawns in nvim's current directory
(`getcwd(0)`, read one scheduled tick later; `cli.show` has no cwd
option). Its preset `resume`/`continue` fields are never read. The config
already depends on five internal modules, a monkey-patch, two
undocumented events and runtime config mutation (~600 adapter lines in
`ai.lua`). Upstream is slow: last commit 2026-09-08, resume PRs open since
2025-12. Detail: `sidekick-assessment.md`.

**Options.**

- **A. Public API only.** Not viable: it would drop multiple sessions per
  agent, agent-view embedding and the pre-warm the config already relies
  on.
- **B. Wrap it.** Our own session registry (ids, labels, cwd, agent
  session id, live/dormant/exited state, MRU order, saved to disk), with
  every sidekick internal call moved into one adapter file. sidekick still
  spawns terminals.
  - For: no visible change; needed under every other option anyway.
  - Against: the spawn-cwd limit and windowless-spawn hacks remain.
- **C. Fork/vendor sidekick.** Full control, but we'd own a whole plugin
  including parts we've disabled (NES, multiplexer backends).
- **D. Replace entirely.** Own everything, including context rendering
  and the prompt library.
- **E. Hybrid (recommended).** B first, then our own terminal backend
  (`agent_term.lua`) behind a flag: spawn with explicit cwd/argv/env,
  no window until asked, embed anywhere, send without opening a window.
  Roughly 600 to 800 lines including the registry. sidekick stays for
  context sends only (templates, prompt library, claude format) via its
  documented `cli.render()` / `cli.prompt()` / `cli.context`.

**Trade-offs of E.** We'd give up NES, the multiplexer backends, external
session discovery, scrollback handling and the file watcher. The config
already disables, stubs or duplicates all of them.

**Leaning.** E. Under D1 option A, build our own backend *before* any
worktree work, and build persistence/resume directly on it; doing them on
sidekick first would be throwaway. If a worktree prototype is wanted
sooner, use the internal synchronous `Session.new({tool, cwd})` +
`State.attach` call inside the adapter, never an `:lcd`/`:tcd` wrapper.

**What would change it.**

- Upstream merges a per-session id, a cwd option and windowless spawn.
  Then B on sidekick could be the end state. Check before starting step 2.
- Triage drops persistence, resume and background sends *and* D1 moves to
  nvim per worktree or a shared tree. Then B alone is enough.
- Measurements show nvim can't handle 6 to 8 busy terminals. That pushes
  toward fewer live terminals (dormant rows matter more), not toward
  sidekick.

### D4. sidekick long-term

**Background.** Under D3 option E, sidekick stays only for context sends.
Context rendering is reachable through documented API and doesn't depend
on sidekick owning terminals.

**Options.**

- **Keep it for context sends.** Little code to own; depends on a slow
  upstream, but the public context API has been stable.
- **Drop it eventually.** Port the renderers and the prompt picker. One
  less dependency, more code to own.

**Leaning.** Keep for now and revisit only if its context API breaks.
You said this depends on how the build-out goes, so revisit after D3's
step 2 lands.

**Related housekeeping.**

- **Pin a commit.** The lockfile pins `3d80a47` but this machine runs
  `17447a0`; the difference touches nothing the config uses. Decide which
  to pin and whether `plugins.lua` should carry an explicit `version`.
- **File upstream issues or PRs** (cwd option, windowless spawn, stable
  session id) anyway, given the slow merge rate? None has been filed.

## Worktrees

### D5. Worktree kinds, ownership and creation

**Background.** Some repos need heavy per-checkout setup, so they use a
few long-lived "slots" created by the repo's own make target. Zed creates
throwaway detached worktrees per thread and, on archive, saves the work as
WIP commits pinned by a ref, then deletes only worktrees it created
(re-checking creation time first). Detail: `isolation-analysis.md` →
Decide early, `worktree-switching.md` → Creation.

**Decisions.**

- **Does nvim create worktrees at all?** Options: no (shell and repo
  tooling only; nvim just switches); yes, via a picker whose create action
  delegates to a per-repo hook (e.g. the repo's make target in a visible
  terminal); yes, plus Zed-style throwaways.
- **Ownership rule.** Leaning: nvim never deletes slots, only worktrees it
  created. Must be decided early.
- **Where throwaways live** (if any). A distinct prefix under
  `.worktrees/`, or a sibling directory like Zed. Must not mix with slots.
- **Archive/restore** with WIP commits + ref. Leaning: defer; only needed
  if throwaways become common.
- **Where per-repo hooks live.** A fork-only Lua file, or an optional
  per-repo hook file under the config dir.
- **Keep worktrees nested inside the main root?** Leaning: yes. rg and fd
  already skip `.worktrees/` at the root (hidden and gitignored), Zed
  doesn't scan it either, and moving it would break repo tooling. Make
  sure `.worktrees/` is ignored in every repo that uses it.

### D6. What happens to open buffers on a switch

**Background.** Buffers from the old worktree have the same relative paths
as the new one's. Left alone, pickers and `:ls` mix two checkouts and the
old language servers stay alive. Detail: `worktree-switching.md` → What to
do with open buffers.

**Options** (least to most work).

1. **Leave them.** Simple; confusing duplicates; old LSP clients stay up.
2. **Wipe all file buffers.** Clean, but loses everything, and fails
   partway on a modified buffer.
3. **Remap only the current buffer** to its counterpart. Other buffers go
   stale.
4. **Remap every buffer** (open counterparts as new buffers; never rename
   in place, which discards unsaved edits). Zed's create-time behaviour.
5. **Per-worktree working sets.** Remember each worktree's buffers and
   window layout; restore them on entry; fall back to 4 on a first visit.
   Zed's switch-time behaviour, without tabs.

**Leaning.** 5, with the current window always jumping to the same file in
the new worktree. Clean old buffers are unloaded; modified ones are kept
with a warning.

**Sub-decisions.**

- Remap only the current window and restore the rest, or remap every
  window on every switch?
- **Jumplist:** clear on switch (lose history) or keep (risk jumping into
  the old worktree)? Leaning: clear.

### D7. Environment per worktree

**Background.** nvim has no direnv integration. Agents, tests and debug
runs started from nvim inherit the main checkout's environment, including
its ports and container project name. An agent in a worktree could run
docker or database commands against the main checkout's stack. Detail:
`worktree-switching.md`.

**Options.**

- **Per-job env.** Run `direnv export json` for the target worktree and
  pass it to each job nvim starts (agents, tests, DAP). Contained; nvim's
  own env never changes.
- **Also swap `vim.env` on switch.** Formatters, linters and LSP spawns
  follow too, but every global env change is a source of surprises.

**How Zed does it** (`crates/project/src/environment.rs`). Zed computes
an environment per directory instead of having one global env. For each
(shell, directory) it starts your login shell in that directory, as if
you'd `cd`'d there, captures its env, and with `"load_direnv": "direct"`
(the default) also runs `direnv export json` there. The result is cached
per directory and handed to everything that spawns a process for that
worktree: terminals (including terminal threads), language servers,
tasks, git and toolchain detection, and ACP agents. Caveat: if Zed was
launched from a shell (`zed .`), it uses that inherited CLI env for
everything instead, so per-worktree env only applies when launched from
the GUI.

**Options.**

- **Per-job env (Zed's model).** Keep a per-worktree env cache in Lua,
  built from `direnv export json` (or a login shell's `env`) in that
  directory, and pass it to each job nvim starts: agents and terminals
  (`jobstart`/`termopen` `env`), tests, DAP, and LSP (`cmd_env`).
  Contained; nvim's own env never changes.
- **Also swap `vim.env` on switch.** Formatters, linters and any spawn
  that doesn't take an explicit env follow too, but every global env
  change is a source of surprises, and agents in other worktrees must
  still get their own env.

**Leaning.** Per-job env, and it's required before agents are spawned per
worktree. Swapping `vim.env` is deferred.

### D8. LSP across worktrees

**Background.** Language servers resolve their root per buffer, so swapped
buffers attach to the new worktree's clients without a restart. But
clients for visited worktrees pile up. On a large Go repo with several
modules and no `go.work`, nvim starts one gopls per module you touch, and
that multiplies per worktree (Zed's single repo-wide gopls was ~1.2 GB).

**Decisions.**

- **Retention:** keep one previous worktree's clients warm, none, or all?
  Needs a reaper that stops idle clients. Leaning: one.
- **gopls root:** one gopls per worktree root (never climbing above the
  worktree), or keep one per module? Needs measuring for memory, and for
  whether cross-module references still work.

Gated on measurements (below).

### D9. Session (layout) file keying

**Background.** persistence.nvim saves sessions keyed by cwd. Under global
`:cd`, the cwd changes on every switch.

**Options.** Always save under the main root, with the working-set store
recording the active worktree; or under the active worktree, as now.
Related: should restored sessions bring back dormant agents?

## Agent layer

### D10. Which agents get resume

**Background.** Claude Code supports `--resume <id>`, and its
`SessionStart` hook exposes the id. omp, pi and opencode only offer a
picker-style `--resume`. Unknown: whether `claude --resume <id>` only
works from the original cwd.

**Options.** Claude-only dormant rows first, with others restarting
fresh; or investigate each CLI's id support before building.

**Leaning.** Claude-only first.

### D11. Status signals

**Background.** The current setup is already ahead of Zed on attention:
hook-driven `!`/`●`/`»` states, deferred unread, `<leader>aj` jump,
statusline badge. Zed's terminal threads only know "the bell rang while
hidden" plus a status glyph read from the terminal title. In nvim, a
terminal bell has no Lua event, but OSC 2/9/777/133 all fire
`TermRequest` (verified on nvim 0.12.6). Hook support varies: Claude has
the full set; omp gives running and done; codex would only have OSC
titles. Detail: `zed-design-lessons.md` §3, §5.

**Decisions.**

- **Hooks-first (what ships) or OSC-first** (portable across agents, but
  gives less detail)? Or both: hooks where available, OSC title glyphs as
  the fallback for agents without hooks.
- **Add an `error` state?** `StopFailure` is only wired to the bell today.
  Changes the truth table and `tests/agentview/run.sh`.
- **Count Elicitation as "waiting"?**
- **Clear needs-permission on `PostToolUse`?** It fires only when the tool
  finishes, so the ring may linger during long tools.

### D12. Follow versus peek

**Background.** Under D1 option A, an agent in another worktree may need
you while the editor is elsewhere.

**Options.**

- **Peek:** show its terminal (float or the agent view) without moving the
  editor.
- **Follow:** switch the editor to that worktree too.

**Leaning.** Peek by default, follow on an explicit key.

**Related.** Should the pre-warmed agent follow the active worktree, or
stay at the main root as a "home" agent? Should pre-warm extend to other
agents, or resume the most recent dormant Claude session?

### D13. Context refs across worktrees

**Background.** `ai_context.ref` builds paths relative to nvim's cwd.
After a switch, or when sending to an agent in another worktree, the same
relative path exists in every checkout, so an agent can open a real but
wrong file without any error.

**Options.** Make refs relative to the target agent's cwd; refuse cross-
checkout sends; or send absolute paths across checkouts.

**Leaning.** Relative to the target, absolute (or refuse) across
checkouts. Must be decided early.

### D14. Agent view grouping

**Background.** The agent view lists sessions flat, with digits mapped to
name order. Zed groups threads by project, with worktree/branch chips.

**Options.** Keep flat; group by repo then worktree (breaks "digits = name
order"); or flat with a worktree column. Visual detail can be deferred,
but notifications should name the worktree regardless.

### D15. Spawn style

**Background.** Zed runs the agent inside a shell, so the row survives the
agent exiting and shows a shell. sidekick spawns the CLI directly, so the
row ends when the agent does.

**Options.** Direct spawn (clean "exited" state; resume brings it back) or
shell-wrapped (can rerun by hand; messier status).

### D16. Instruction files in nested worktrees

**Background.** With worktrees nested in the main root, an agent in
`.worktrees/<name>` may also load the main checkout's `CLAUDE.md` (and omp
its `AGENTS.md`), and config lookups fall back to the main checkout.
Unconfirmed.

**Decision.** After confirming, is that wanted? If not: per-worktree
overrides, or tell agents the layout. Also: an agent started at the main
root can edit every worktree. Treat it as a read-mostly "home" agent, or
tell it the layout explicitly?

## Editor details

### D17. Other plugins on switch

Each has a proposed fix in `worktree-switching.md`; decide which to do:

- **Neogit** keeps one global repo. Re-target on switch; and keep its
  worktree popup as a second entry point (picked up via `DirChanged`), or
  point `<leader>Gw` at the new picker?
- **nvim-tree**: re-root and clear its git cache. Its ignored-dir shortcut
  may hide a worktree's files (untested).
- **neotest-golang**: clear its root cache.
- **snacks `recent`/`smart`**: exclude `.worktrees/` files at the main
  root.
- **Window title and statusline**: add a worktree component.

### D18. Terminals per worktree

Scope toggleterm's float cycle and bottom panel per worktree, or keep them
global?

### D19. Naming compatibility

Keep `sidekick_terminal` and `SIDEKICK_SESSION` after sidekick stops
owning terminals (zero churn), or rename once across the producers,
stickybuf, `buffers.lua` and the panel clamp (clearer)?

## Features

### D20. Feature triage

**Background.** `zed-feature-survey.md` §13 has the full table (~45
features, tagged by terminal-mode relevance and current status). Already
ahead of Zed: per-session status, unread, jump-to-attention, sending
selections, multi-agent keybindings.

**Candidates** (high or medium terminal relevance, missing or partial
today):

- Row titles from the agent's OSC terminal title, and title glyphs as
  status (1.3, 1.4, 2.6)
- Saved rows with lazy respawn / resume (1.7, 2.8)
- MRU switcher with live preview (2.5)
- Group by project/worktree (2.2; see D14)
- Archive / history / restore (2.7)
- Prevent the machine sleeping while agents run (2.9)
- Click-to-focus notifications, sound, dock bounce (3.4)
- Error state and retry (3.6; see D11)
- Worktree per session and a create hook (4.1, 4.2; see D5)
- Per-session diff stats (5.1). Decided against per-agent diffs, but a
  `git diff --stat` per worktree is cheap if worktrees are used.
- Agent-spawned sibling sessions (9.2; Zed has this staff-only)

Lower relevance: context/token/cost display (3.5), follow the agent (5.3),
@-mentions (6.1), permission prompts from editor UI (8.1, not possible in
terminal mode).

## Measurements to run before deciding

- **gopls memory per worktree** on the real repo, per-module versus
  worktree-root, and whether a main-root client indexes `.worktrees/`.
  Gates D8 and D1 option B.
- **CPU with 6 to 8 busy agent terminals**, shown versus hidden. Gates
  hibernation/dormant design and the D1 "one process holds every agent"
  risk.
- **Two-nvim event routing**: the upstream event-pipeline doc's step 6.
  Gates D1 option C.
- **`claude --resume <id>` from a different cwd**, and where omp stores
  session ids. Gates D10.
- **What Claude Code emits over OSC** inside nvim's terminal. Gates D11.
- **Stacked instruction files** in nested worktrees. Gates D16.
- **nvim-tree's ignored-dir shortcut** after re-rooting. Gates D17.
