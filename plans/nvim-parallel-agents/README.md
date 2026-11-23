# nvim parallel agents

Research and scoping for bringing Zed-style "parallel agents" polish into the
Neovim config: several agent CLIs (Claude Code, omp, ...) running in nvim
terminal buffers, with a session list, attention/status, resume, and
worktree-aware switching. Started 2026-11-22. **Status: research done,
triage not started.** Nothing is built.

This folder is kept identical in the public upstream and the private fork.
Fork-only, repo-specific notes live outside it (fork: `plans/`), so nothing
here names employers, work repos or private hosts.

## Before building: Zed + vim mode + a fork? (2026-11-22)

An open alternative to the whole nvim build (decision D0 in
[decisions.md](decisions.md)): if Zed with vim key bindings works well
enough, use it, and add minor features through a fork. This may be the
cheapest path to the polish wanted, and the research supports it with some
caveats.

### Why Zed plus a fork is attractive

- **The hard parts already exist:** parallel threads, worktrees as separate
  workspaces, per-directory environments, grouping in the sidebar. A
  full-time team maintains them and they're improving quickly. Agents
  spawning sibling threads in new worktrees is already in progress behind a
  flag.
- **Most of the 5,000 lines of research describes things nvim would have to
  build and maintain.** In Zed, only the parts added on top need
  maintaining.
- **This road is already partly travelled:** the Zed vim docs
  (`docs/zed-vim.md`, `docs/zed-vim-keymap.md`), the Claude ACP agent in
  Zed, and the earlier `zed-fork-terminal-thread-notifications.md` plan.

### Caveats

- **Use ACP threads, not terminal threads.** In Zed the terminal-vs-ACP
  trade-off flips. Terminal threads are thin: status is just "the bell rang
  while hidden" plus a glyph from the terminal title, with no running,
  waiting or error state, no review, no history. ACP threads get the full
  feature set. Going with Zed means accepting Claude through the ACP
  adapter, and checking which Claude Code CLI features survive it (hooks,
  skills, slash commands, `/` workflows). Whether the adapter sends its
  edits through ACP's file-write request is still unconfirmed.
- **The nvim attention model is better than Zed's.** Zed has no "jump to
  whichever thread needs me" and no global badge. Porting that into a fork
  means Rust and GPUI work in `agent_ui`, which isn't small.
- **Forks of Zed's agent UI are expensive to keep current.** The design
  lessons doc's history appendix shows the threads sidebar moved into the
  agent panel and back out within six days. A fork touching `agent_ui` will
  need frequent painful rebases. It also means giving up auto-updates and
  building Zed yourself, which is a long Rust compile. Small, contained
  patches (a notification tweak, a keybinding action) are fine; anything
  structural is not. Upstream PRs are a better outlet for those.
- **Vim mode is good, but it isn't nvim.** The real question is how much
  daily editing depends on nvim-specific things: plugins, Lua
  customisations, the textobjects and keymaps in GUIDE.md. The existing Zed
  vim docs record where parity falls short.
- **Per-worktree environments only work when Zed is launched from the
  GUI.** Launching with `zed .` from a shell makes it use that shell's
  environment for everything.

### Fresh assessment from the Zed parity docs (2026-11-22)

Written after reading `docs/zed-vim.md`, `docs/zed-vim-keymap.md`,
`docs/zed-worktrees.md`, the stowed Zed `keymap.json` / `settings.json` and
GUIDE.md's contents. The docs are written against Zed 1.29.2; 1.29.3 is
installed.

**The premise hasn't been tested yet.** `settings.json` has
`"vim_mode": false`, and only two rows of the keymap proposal are adopted
(thread cycling and the vim toggle). The docs are thorough research on Zed
vim mode, not experience living in it. "Zed + vim works for me" is still a
hypothesis, and the trial is what settles it.

**Editing parity is better than first assumed.** For moving around and
editing, Zed vim mode is a deep layer, not a thin emulation:

- **Same keys as the nvim setup:** motions, counts, marks, `ctrl-w` panes,
  and the LSP keys (`gd`, `gy`, `gri`, `grr`, `grn`, `gra`, `K`, `]d`).
  `grt` is the only nvim key with no twin, and `gy` covers it.
- **Better than the nvim config:**
  - Tree-sitter text objects (`af`/`if`, `ac`/`ic`, arguments, indent
    blocks), which the nvim config maps nothing for
  - surround, exchange, multiple cursors and replace-with-register built in
  - hunk operations on the `d` operator (`do`/`dp`/`du`), which beat
    leader chords
- **About equal:** pickers with preview, structural select (`[x`/`]x`), a
  project panel with netrw-style keys, `:s` with vim regex auto-converted.
- **Ready to adopt:** `docs/zed-vim-keymap.md` already has a complete
  leader block (`space s f`, `space g d`, `space a a`, `H`/`L`,
  `ctrl-hjkl`, `jk`) with reasons for each row.
- **Real gaps:**
  - small: no quickfix (multibuffers stand in), partial folds, Rust regex
    in `/`, `:e` relative to the project root, `:w!` still formats
  - docks aren't panes: `ctrl-w h` doesn't reach the file tree or agent
    panel without the extra `Dock` keymap block
  - custom tree-sitter queries need an extension, and there are no swap or
    argument motions
  - no equivalent of `<leader>aj`: nothing jumps to the agent that needs
    you

**The real lock-in is the customisations, not the keys.** GUIDE.md's
Design Decisions section is a long list of behaviour built in Lua:

- sidebar pinning and panel clamping
- the file tree's reveal mode
- renaming a file rewrites its imports
- pickers that revert on cancel
- quit when only sidebars remain
- flatten.nvim routing
- custom title and statusline
- grug-far, neotest

In Zed, all that can be customised is keymaps, settings, tasks and limited
extensions; anything beyond that means a fork. The trial should check how
many of these are actually missed, not whether `gd` works.

**Zed already does the worktree workflow wanted here.** Per
`docs/zed-worktrees.md`, and the config is already set up for it:

- **Switching:** open at the main root, `cmd-ctrl-w` to switch worktree.
  Each worktree becomes its own workspace with its own tabs, terminals and
  language servers. The one you left stays alive, so switching back finds
  it as you left it.
- **Environment:** each worktree loads its own direnv environment (after
  `direnv allow` in that checkout), which handles per-worktree ports.
- **Nested worktrees:** the stowed `file_scan_exclusions` already hides
  `.worktrees/` from the main project.
- **Creation:** the doc recommends letting the repo's own worktree script
  create worktrees and using Zed only to switch.

That's exactly the "open at the root and switch, with files following"
workflow the nvim plan would spend the most effort on (build step 3 below
and all of `worktree-switching.md`). Caveats: threads don't follow a
switch; each open worktree runs its own gopls; per-worktree environments
only apply when Zed is launched from the GUI, not with `zed .`.

**Agents remain the weak spot.** omp runs as a terminal thread
(`agent.terminal_init_command: "omp"`), which has the thin status model: a
bell plus a title glyph, no running/waiting/error state, and no jump to
whichever thread needs you. The rich features need ACP threads (Claude ACP
is already set up), which means accepting whatever the ACP adapter keeps of
Claude Code's CLI. The earlier upstream
`zed-fork-terminal-thread-notifications.md` plan exists because of this
gap.

**Updated verdict: leaning more towards Zed than before.** Editing parity
is strong and the keymap is already written; the worktree half of the nvim
plan comes free. What's left to judge:

1. whether the Lua customisations are missed
2. whether ACP Claude, or terminal threads plus a small fork patch for
   attention, is good enough for agents

### Suggested way to decide: a time-boxed trial

The trial costs almost nothing to start:

1. set `vim_mode: true` (or press `cmd-k cmd-v`)
2. paste the block from `docs/zed-vim-keymap.md` into `keymap.json`
3. run Claude as ACP threads, plus omp as a terminal thread for comparison
4. work in the repo's long-lived worktrees through `cmd-ctrl-w` for a week

Keep a list of what's missed, especially the GUIDE.md customisations and
the agent attention model, sorted into:

1. Zed settings or keymaps fix it
2. a small fork patch fixes it
3. it needs nvim

If most items land in 1 and 2, Zed wins and the nvim plan shrinks to "keep
sidekick as is". If nvim editing keeps getting reached for, or ACP Claude
loses CLI features that matter, that's concrete evidence for the nvim
build. Step 0's measurements and step 1 (session ids and registry) in the
synthesis below would still be worth doing, since they're cheap.

### Trial list (running)

Items found while using Zed, in the three buckets above.

**2. A small fork patch fixes it**

- Tasks can't be run from the command palette (`cmd-shift-p` lists actions
  only), so the cheatsheet task needs `cmd-k cmd-m` or `task: spawn`. Found
  2026-11-22; scope in
  [../zed-fork-palette-tasks.md](../zed-fork-palette-tasks.md).
- Terminal Thread notifications: see
  [../zed-fork-terminal-thread-notifications.md](../zed-fork-terminal-thread-notifications.md).

## Synthesis so far (2026-11-22)

Claude's take after reading all five research docs. This is a
recommendation, not a decision; decisions are tracked in
[decisions.md](decisions.md).

The research makes one thing clear: **the hard part is the session layer
underneath the agent view, not the UI.** The current setup already beats
Zed on attention: per-session status, the jump to whichever agent needs
you, the statusline badge. Zed's polish lead is in session lifecycle:
stable identity, resume, dormant sessions, and awareness of worktrees and
their environments. All of that sits underneath sidekick, which is why the
sidekick question carries so much weight.

### Where it agrees with the research

- **Session ids and a registry are a no-regret first step.** Every
  topology, backend choice and feature on the list needs them, and doing it
  later means migrating the name-based code twice. Start here no matter
  what else is decided.
- **Replace sidekick's spawn and terminal handling, keep its context
  sends.** The evidence is convincing: the config already fights its model,
  upstream is slow, and an explicit start directory and environment are
  impossible through its public API.
- **Copy Zed's per-directory environment.** It's small, well understood,
  and prevents a real class of bug: agents hitting the wrong stack's ports.

### Where it's more sceptical

- **Switching worktrees inside one nvim is the expensive part, and may not
  be where the value is.** The 2a design needs:
  - per-worktree sets of open files
  - a reaper for idle language servers
  - re-targeting nvim-tree, Neogit and neotest
  - snacks filters
  - jumplist rules

  That's a whole subsystem fighting nvim's single-directory model. Zed's
  "mini instances" are basically what separate nvim processes give you for
  free.
- **Most of what's wanted may come from agents running in any worktree
  while the editor stays put.** Picture one nvim at the main root:
  - agents are started in `feature-1` or `pr-review-2` from a picker
  - the agent view is grouped by worktree
  - review uses `DiffviewOpen -C .worktrees/feature-1`, since diffview can
    target another checkout without switching

  That alone might cover 80% of it. Only build the editor switch once its
  absence is felt.
- **Five thousand lines of research invites scope creep.** Commit to a thin
  first version and treat everything else as optional.

### Suggested build order

0. **An afternoon of measurements:**
   - CPU with 6–8 busy agent terminals
   - gopls memory per worktree
   - whether `claude --resume <id>` works from another directory
   - whether agents in nested worktrees also read the main `CLAUDE.md`

   The CPU result could rule out "one nvim holds everything", so it goes
   first.
1. **Registry, ids and a sidekick adapter, with no visible change.** Add
   the quick wins alongside: an error state, status read from the terminal
   title for agents without hooks, and the worktree name in notifications.
2. **Own terminal backend:** explicit directory and per-worktree
   environment, a picker to start an agent in any worktree, the view
   grouped by worktree, and Claude resume by id.
3. **Only if it's missed, the editor switch,** starting minimal: `:cd`,
   remap the current window, fix nvim-tree, Neogit and the title. Add
   per-worktree sets of open files only if the minimal version annoys.
4. **Deferred until pulled in by real need:** throwaway worktrees and
   archiving, an overview across several nvims, a tmux layer.

### What this means for the decisions

- **D1 (topology) can mostly wait.** Steps 1–2 are the same whether the
  end state is one home nvim or nvim per worktree. Using step 2 for a while
  will answer the question better than deciding now.
- **D2 (session ids) and D3 (the sidekick plan) are the ones to settle
  first.** Both point the same way.

## Docs

**To pick this up later, start with [decisions.md](decisions.md):** every
open decision with background, options, trade-offs and the research
leaning, plus the measurements that gate some of them.

Research, in reading order:

1. [zed-feature-survey.md](zed-feature-survey.md): what Zed's agent
   features do and their UX (~45 features). Each is tagged with
   terminal-mode relevance and whether the current nvim setup has it.
2. [zed-design-lessons.md](zed-design-lessons.md): how Zed built it
   (entities, status model, persistence, worktrees, change tracking) and
   what each piece would look like in Lua on top of `agentview.lua` /
   `agent_events.lua`. Includes three candidate architectures (none chosen).
3. [sidekick-assessment.md](sidekick-assessment.md): keep, wrap, fork or
   replace sidekick.nvim. Recommends a hybrid: our own session registry,
   then our own terminal backend, with sidekick kept only for context sends.
4. [isolation-analysis.md](isolation-analysis.md): how sessions map to
   checkouts and nvim instances (shared tree / one nvim many worktrees /
   nvim per worktree / hybrids). Leans to one "home" nvim that switches
   worktrees in place, with agents fixed to their spawn directory.
5. [worktree-switching.md](worktree-switching.md): the mechanics of
   switching worktrees inside one nvim opened at the main root, a survey of
   11 worktree plugins (none fits; leans to a small owned `worktree.lua`),
   how Zed does it, and a sketch of the hand-off to agents.

Zed was studied at commit `596dfdcf32`.

## Decisions so far

- **Terminal mode is the focus.** Agent CLIs live in terminal buffers; a
  native ACP chat UI in Lua is out of scope.
- **No action log or per-agent diffs.** Plain `git diff` / diffview /
  gitsigns, with changes from several agents mixed together, is enough. A
  cheap "diff since session start" baseline is optional, only if it falls
  out for free. Per-turn checkpoints are out (Zed removed them over git
  cost on large repos).
- **Resume by id is enough** to survive an nvim restart. A running agent
  turn does not have to survive. Possible later extensions: a tmux layer,
  or a layered strategy (id resume by default, tmux-hosted sessions as an
  opt-in).
- **External multiplexers (herdr, Orca) are not considered** as
  alternatives.

## Open

See [decisions.md](decisions.md). First: Zed or nvim (D0). Then the
foundational ones: topology (D1),
session identity (D2), the sidekick plan (D3) and sidekick long-term (D4).
