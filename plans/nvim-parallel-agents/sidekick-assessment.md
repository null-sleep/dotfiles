# sidekick.nvim: build on it, wrap it, fork it, or replace it?

Research and scoping only. This doc recommends a direction but builds nothing.

- **Written:** 2026-11-22.
- **sidekick assessed:** the checkout this machine actually runs, commit
  `17447a0` (2026-03-24, `git describe`: `stable-2-g17447a0`), at
  `~/.local/share/nvim/site/pack/core/opt/sidekick.nvim`.
  - `nvim-pack-lock.json` has recorded `3d80a47` (2026-09-08) since the
    2026-11-19 lockfile commit. So the lockfile and this machine's checkout
    disagree.
  - The five commits between them change 69 lines: a NES debounce, a tmux
    dump limit, a `<cr>` normal-mode key, `leftcol=0` on focus, and a claude
    column format.
  - None of those commits touches the internals this config depends on, so
    the findings below hold for both commits.
- **nvim side:** `nvim/.config/nvim/` on branch `plan/nvim-parallel-agents`:
  `lua/ai.lua`, `lua/agentview.lua`, `lua/agent_events.lua`,
  `lua/ai_context.lua`, `sk/cli/omp.lua`, `tests/agentview/`.
- **Hook producers:**
  - `claude/.claude/hooks/sidekick-notify.sh`
  - `omp/.omp/agent/extensions/nvim-notify.ts`
  - `pi/.pi/agent/extensions/nvim-notify.ts`
  - `opencode/.config/opencode/plugins/nvim-notify.ts`
- **Earlier design docs** live in the public upstream repo's `plans/`
  (`sidekick-agent-view.md`, `-internals.md`, `-agent-event-pipeline.md`,
  `-multi-claude-sessions.md`, `-windowless-prewarm.md`,
  `-cursor-support.md`, `git-worktree-nvim-plugin.md`). They are cited
  below as "upstream `<name>.md:<line>`".
- **Companions:**
  - `zed-feature-survey.md` covers the features.
  - `zed-design-lessons.md` covers the architecture.
  - `isolation-analysis.md` covers worktrees. It leans to one "home" nvim
    at the main root that switches worktrees in place with a global `:cd`
    (its model 2a on top of 4a). Agents stay fixed to their spawn cwd,
    often a worktree the editor is not on. Under "Decide early" it lists
    row-id identity and "spawn takes an explicit cwd" as inputs to this
    doc.
  - Section 6 covers how this recommendation depends on isolation.

Refs that start `sk:` are paths inside the sidekick checkout, under
`lua/sidekick/` unless they start with `sk/cli/`. Bare refs such as
`ai.lua:785` are files in the nvim config.

## Contents

- [Summary](#summary)
- [1. What sidekick provides](#1-what-sidekick-provides)
- [2. What the config uses, and how](#2-what-the-config-uses-and-how)
- [3. Verifying the flagged risks](#3-verifying-the-flagged-risks)
- [4. Upstream activity and maintenance risk](#4-upstream-activity-and-maintenance-risk)
- [5. Capability matrix](#5-capability-matrix)
- [6. How isolation changes the picture](#6-how-isolation-changes-the-picture)
- [7. Options](#7-options)
- [8. Recommendation](#8-recommendation)
- [9. Migration path](#9-migration-path)
- [10. Open questions](#10-open-questions)

## Summary

- Stop treating sidekick as the session manager. Use it as a library for
  sending context.
- **Step one: a session registry the config owns.** It is option B, and it
  is worth doing on its own merits.
  - Identity, labels, the active/MRU order, captured agent session ids and
    persisted rows all move out of sidekick's tool-name model.
  - Every sidekick internal call moves into one adapter file.
  - This step changes nothing the user sees.
- **Step two (the destination): a terminal backend the config owns.**
  - It replaces sidekick's spawn, window and state layer, about 600 to 800
    lines all told (section 7, D). The new backend takes on the spawn and
    window work that sidekick does today.
  - sidekick stays installed only for `{this}`/`{selection}`/diagnostics
    rendering and the prompt library. Those are reached through its
    documented `cli.render()` / `cli.prompt()` and the `cli.context` config
    hook.
  - This is the hybrid, E.
- **Do not fork (C).**
  - A fork inherits sidekick's core assumption that identity means
    `(tool name, cwd)`. Every feature on the list fights that assumption.
  - A fork also carries about 1,500 lines (NES, mux, process scanning,
    pickers) that the config disables or stubs today.
- **Do not stay on the public API alone (A).** It is not really on offer:
  the shipped config already left it behind (section 2).
- **Deciding factors:**
  - sidekick's session model cannot represent the likely features without
    internals. Stable ids, resume, dormant rows, a cwd per spawn and a
    spawn with no window all fall in this group.
  - About 600 lines of `ai.lua` already exist to adapt that model.
  - Upstream is in a slow phase:
    - last commit 2026-09-08
    - 6 commits since the 2.3.0 release
    - resume PRs open since 2025-12
  - That pace keeps breakage risk low. It also means the missing pieces are
    unlikely to arrive upstream.
- **How urgent step two is depends on isolation:**
  - **One nvim hosting sessions in several worktrees:** do the backend swap
    *before* the worktree work. sidekick's public API cannot spawn in a
    given cwd, and same-named sessions across cwds route through a
    disambiguation picker.
  - **One nvim per worktree, or a shared tree:** step one delivers most of
    the value, and step two can wait until pre-warm, resume or embedding
    pain justifies it.
- **The isolation analysis leans to the first of these:** a home nvim with
  a global `:cd`, and agents in other worktrees.
  - I verified its claim: sidekick reads the spawn cwd from `getcwd(0)`,
    and `cli.show` has no cwd option.
  - The cwd is also read one scheduled tick *after* the `cli.show` call
    (section 3), so a wrapper that does `:lcd` and then restores it is
    fragile.
  - Under that leaning, step two belongs at the front of the worktree work,
    not at the end of the queue.

## 1. What sidekick provides

sidekick has two halves that share almost nothing: **NES** (Copilot
next-edit suggestions, `sk: nes/`, about 750 lines) and **CLI** (`sk: cli/`,
about 3,500 lines). This config disables NES (`ai.lua:171`, `nes = {
enabled = false }`) and does not use the Copilot status. Everything below
is the CLI half.

### Session model

- **A session is `(tool, cwd)`.**
  - `Session.new` sets `sid = M.sid({tool, cwd})` and `id = id or sid`
    (`sk: cli/session/init.lua:79-96`).
  - `M.sid` is `"<tool> <sha256(cwd):sub(1, 16 - #tool)>"`
    (`sk: cli/session/init.lua:104-108`). A tool name of 16 or more
    characters leaves no hash at all.
  - **Consequence:** two sessions of the same tool in the same cwd are the
    same session. sidekick has no session id of its own and stores no agent
    session id.
- **The cwd comes from the current window.**
  - `State.attach` builds a fresh session as `Session.new({ tool =
    tool.name })` with no cwd (`sk: cli/state.lua:185`).
  - `M.cwd` then falls back to `vim.fn.getcwd(0)`
    (`sk: cli/session/init.lua:98-101`).
  - The public `cli.show/toggle/send` options take `name`, `focus`,
    `filter` and `all`, but no `cwd` (`sk: cli/init.lua:25-37`).
- **Tools come from a runtime-mutable table.**
  - `tool.get(name)` deep-merges the runtimepath preset `sk/cli/<name>.lua`
    with `Config.cli.tools[name]` on every call (`sk: cli/tool.lua:25-34`).
  - Writing a new key into `Config.cli.tools` therefore creates a new
    "tool". This is the hook the config's dynamic sessions are built on.
- **Listing is synchronous and walks every backend.**
  - `State.get` calls `Session.sessions()`, which runs every registered
    backend's `sessions()` in a row on the UI thread
    (`sk: cli/session/init.lua:133-155`). It asserts on duplicate ids at
    `:142`.
  - It then adds one unstarted row per configured tool, calling
    `executable()` for each (`sk: cli/state.lua:97-107`).
  - tmux and zellij register whenever their binary exists, whether or not
    `cli.mux.enabled` is set (`sk: cli/session/init.lua:118-131`).
- **Routing is by filter.** `State.with` pops a disambiguation picker when
  more than one attached session matches (`sk: cli/state.lua:143-174`).
  - `Filter` supports `name` (exact `tool.name`), `cwd` (meaning "the
    current cwd"), `session` (an id), `started`, `terminal` and others
    (`sk: cli/state.lua:17-46`).
  - `filter.session` is a public way to target one session by id.
- **Lifecycle events:**
  - `SidekickCliAttach` fires once per session lifetime
    (`sk: cli/session/init.lua:194`). It is skipped on re-attach by the
    early return at `:171`.
  - `SidekickCliDetach` is emitted through `vim.schedule`
    (`sk: cli/session/init.lua:162-164`).
  - Neither event is documented in the README or the vimdoc.

### Terminal and window management (`sk: cli/terminal.lua`)

- **`start()` couples buffer, window and job** (`:147-319`).
  - It creates the buffer, sets filetype `sidekick_terminal` and stamps
    `vim.b.sidekick_cli`.
  - It binds keys, **opens a window** (`:157`), and runs
    `jobstart(cmd, { term = true, cwd, clear_env = true, env })` inside
    `nvim_win_call(self.win)` (`:280-302`).
  - The env merges `os_environ`, the tool's `env` (where `false` unsets a
    variable) and `NVIM = v:servername` (`:282-295`).
- **Each terminal registers global autocmds.** TermEnter, TermLeave,
  WinEnter, WinLeave and TermOpen are bound without a buffer scope
  (`:160-187`, `:211-214`). With N terminals, every window switch runs N
  sets of callbacks.
- **Readiness is a heuristic.**
  - A 100 ms timer waits for a window, then for more than 5 lines and a
    cursor below row 3, then for 500 ms of stable output (`:226-276`).
  - It gives up waiting after 5 s.
  - Sends queue until ready, then go out via `nvim_put` into the terminal
    buffer (`:328-348`).
- **`send()` always shows the window first** (`:492-498`). The public
  `cli.send` also hardcodes `show = true` (`sk: cli/init.lua:200-205`).
- **`open_win()` stamps the window.** It sets `vim.w.sidekick_cli = tool`
  and `vim.w.sidekick_session_id = id` (`:385-386`). The scrollback mouse
  handler and this config both resolve the session from these stamps.
- **`TermClose` auto-closes the session**, except when the process exited
  within 500 ms, or exited non-zero within 3 s (`:189-205`). Those two
  cases leave a dead session with no detach event (upstream
  `sidekick-multi-claude-sessions.md:363-371`).
- **A per-instance hook exists.** `Config.cli.win.config(terminal)` runs at
  `init()` (`:104-116`). The pre-warm uses it to monkey-patch `open_win`.

### Multiplexer backends

- **tmux** (`sk: cli/session/tmux.lua`):
  - It runs `tmux new -A -s <sid>` (`:31-38`) and passes env through
    `-e`/`-u` (`:74-83`).
  - On restart it rediscovers sessions by walking pane process trees and
    matching each tool's `is_proc` regex (`:124-155`). A rediscovered
    session gets the id `"tmux <pane pid>"`.
  - Rediscovery maps a pane to whichever **configured** tool matches
    first. A dynamic name such as `claude 3` is not registered at startup,
    so it comes back as a second bare `claude`. **Mux persistence keeps
    processes alive but loses this config's identity and labels.**
- **zellij:** always embedded, and its scripting is limited
  (`sk: cli/session/zellij.lua:59-78`).
- **Scrollback** (`sk: cli/scrollback.lua:42-44`) is enabled only for
  mux-parented terminals, so it is inactive in this config.
- **External discovery:** opencode's preset registers an `lsof` scanner as
  a load side effect (`sk/cli/opencode.lua`).

### Context and prompts

- **Template rendering:** `cli.render()` → `Context.get():render()`
  (`sk: cli/init.lua:164-166`).
  - Built-in variables: `{this}`, `{file}`, `{line}`, `{position}`,
    `{buffers}`, `{diagnostics}`, `{diagnostics_all}`, `{quickfix}`,
    `{selection}`, `{function}`, `{class}` (`sk: cli/context/init.lua:12-57`).
  - About 1,140 lines with `text.lua` and `treesitter.lua`.
- **`Config.cli.context` overrides** are looked up before the built-ins
  (`sk: cli/context/init.lua:189-191`).
- **The context window** is the most recently visited window whose buffer
  is not filetype `sidekick_terminal`, ordered by `vim.w.sidekick_visit`
  (`sk: cli/context/init.lua:193-216`, `sk: config.lua:210`).
- **Per-tool `format(text)`**, for example claude's `@file#L` rewrite
  (`sk/cli/claude.lua:8-21`).
- **Prompt library and picker:** `cli.prompt()`, plus `<c-b>`/`<c-f>`
  buffer and file pickers inside the terminal (`sk: cli/actions.lua:25-41`).
- **fs watcher:** `checktime` on file changes, on by default
  (`sk: config.lua:35`, `sk: cli/watch.lua`).
- **A public session list:** `require('sidekick.status').cli()` returns
  `{id, tool, cwd}` for attached sessions without walking backends
  (`sk: status.lua:26-37`, `:100-110`).

### Public API versus internals

- **The documented surface** (README "AI CLI Integration" and the setup
  options):
  - `require('sidekick').setup`
  - `sidekick.cli.{show, toggle, focus, hide, close, send, prompt, select,
    render}`
  - `sidekick.status.cli()`
  - the `cli.win`, `cli.tools`, `cli.context`, `cli.prompts` and `cli.mux`
    options
- **Everything else is internal:**
  - `sidekick.cli.state`, `.session`, `.terminal` and `.tool`
  - Terminal fields and methods
  - window and buffer variables
  - the `SidekickCli*` events

## 2. What the config uses, and how

The rest of the config reaches sidekick through `require('ai')` alone.
Keymaps, pickers and the statusline all call `ai.*`
(`keymaps.lua:401-486`, `picker.lua:83`, `pickers/aibuffers.lua:53`,
`statusline.lua:41-50`). The one exception is `keymaps.lua:441`, which
calls the public `cli.prompt`. `ai.lua` is already a session façade, which
makes a swap tractable. The coupling sits in three files.

### Public API use

- `setup` with `picker`, `win`, `tools.<agent>.env`, `context` and `nes`
  (`ai.lua:98-172`).
- `cli.show`, used by `show_solo` (`ai.lua:751`), the pre-warm
  (`ai.lua:555`) and agentview (`agentview.lua:343`, `:558`).
- `cli.toggle` (`ai.lua:906`), `cli.focus` (`ai.lua:963`) and `cli.hide`
  (`ai.lua:574`).
- `cli.close` (`ai.lua:919`), `cli.send` (`ai.lua:957`) and `cli.prompt`
  (`keymaps.lua:441`).
- The `win.config` callback is a documented option, but it is used to
  replace a method (next section).

### Internals reached into

- **`sidekick.cli.state`:**
  - `get({ name, started })` serves as the liveness predicate and the row
    source (`ai.lua:47`, `:64`, `:344`, `:983`, `:1026`, `:1089`;
    `agentview.lua:78`, `:273`, `:557`).
  - `detach(state)` gives a same-tick kill (`ai.lua:940`).
- **`sidekick.cli.terminal`:**
  - `get(id)` and `sessions()` (`ai.lua:245`, `:300`, `:319`, `:466`,
    `:548`, `:568`, `:748`; `agentview.lua:496`, `:588`).
  - Fields: `job` (raw byte forwarding, `ai.lua:467-468`), `buf`, `win`,
    `tool`, `id` and `opts.split.width` (`ai.lua:273`, `:301`).
  - Methods: `hide`, `is_open`, `buf_valid` and `win_valid` (`ai.lua:549`,
    `:569`, `:749`; `agentview.lua:288-302`, `:497`).
- **`sidekick.cli.session`:** `setup()`, then stubbing
  `backends[name].sessions` for opencode, tmux and zellij
  (`ai.lua:194-204`).
- **`sidekick.config` mutation:**
  - pruning `cli.tools` down to the five agents (`ai.lua:215-218`)
  - registering cloned presets as new tools (`ai.lua:785-794`)
  - writing `cli.win.split.width` (`ai.lua:299`)
  - reading `cli.mux.enabled` (`ai.lua:198`)
- **`sidekick.cli.tool.get(agent).config`:** preset cloning and load-time
  tripwires (`ai.lua:645-665`, `:774`).
- **Monkey-patching `term.open_win`** with a hidden float for the pre-warm
  (`ai.lua:117-132`, cleared at `:559`).
- **The window stamps `vim.w.sidekick_cli` / `sidekick_session_id`:**
  - read for active tracking (`ai.lua:289`), byte forwarding (`:464`,
    `:494`), unread candidates (`:1050`) and width memory (`:318`)
  - read by `agent_events` (`agent_events.lua:37`, `:278`, `:324`)
  - **forged** onto the agent view's main pane (`agentview.lua:238-239`,
    `:298-299`)
- **The undocumented events:**
  - `SidekickCliAttach`, for promote, the `_dynamic` phase and the stamp
    tripwire (`ai.lua:234-280`)
  - `SidekickCliDetach`, for the GC sweep (`ai.lua:328-374`)
  - agentview's handlers for both, which must `vim.schedule` around the
    synchronous emit (`agentview.lua:573-630`)
- **Tests stub these internal modules by name.** See
  `tests/agentview/helpers.lua:133-157` (`sidekick.cli.state`,
  `sidekick.cli.terminal`, `sidekick.config`) and
  `tests/agentview/badge.lua:17-26`.
- **The `sidekick_terminal` filetype** is keyed on by stickybuf
  (`plugins.lua:473`), `buffers.lua:22`, `autocmds.lua:158` and
  `terminal.lua:197`. It is also keyed on by sidekick's own context-window
  filter.

### How much of `ai.lua` is adaptation

These ranges exist because of sidekick's model, comments included:

- name-as-identity parsing: `ai.lua:1-22`
- liveness and fallback: `:43-70`
- the pre-warm `open_win` patch: `:94-132`
- the backend stubs and tool pruning: `:174-218`
- promote and stamp tracking: `:220-292`
- width memory: `:294-323`
- the detach sweep: `:325-374`
- the pre-warm dance and its race guards: `:513-630`
- preset tripwires: `:637-665`
- namespace guards, auto names and preset cloning: `:667-797`
- `_forget` and `kill`: `:806-821`, `:909-942`

That is about 600 of 1,108 lines. Some of it (auto-naming, labels,
pre-warm timing around persistence.nvim) would survive under any backend,
but in simpler form. My estimate is that half of it disappears under an
owned registry plus backend.

### The event pipeline is already independent

- The hooks RPC `agent_events.handle()` through `$NVIM` and join on
  `$SIDEKICK_SESSION` (`sidekick-notify.sh:17`, `:44-50`; the same in the
  three `.ts` producers).
- Its only sidekick dependencies:
  - the env var's *name*
  - sidekick passing the per-tool `env` into the job (`ai.lua:140-158`,
    `:791-792`)
  - the `sidekick_cli` window stamp, which `agent_events` uses for "am I
    looking at it"
- All three are trivial to provide from an owned backend. Keeping the env
  var name `SIDEKICK_SESSION` avoids touching four producer files.

## 3. Verifying the flagged risks

`zed-design-lessons.md` flagged three risks.

- **"Preset `resume`/`continue` fields aren't read by any code":
  confirmed.**
  - `grep -rn 'resume\|continue' lua/` in the sidekick checkout finds
    nothing apart from `goto continue` labels.
  - The fields appear only in `sk/cli/{claude,codex,opencode,pi}.lua`
    (e.g. `sk/cli/claude.lua:6-7`) and in this config's `sk/cli/omp.lua`.
  - No upstream commit has wired them up. PR #223 ("add session selection
    and resume functionality", 2025-12-18) and PR #306 ("picker to choose
    new/continue/resume on launch", 2026-04-19) are both still open and
    unmerged.
- **"Identity is name-based": confirmed, and it is structural.**
  - `filter.name` matches `tool.name` (`sk: cli/state.lua:42`).
  - `sid` is derived from `(tool, cwd)` (section 1).
  - The config's "name is the only identity" (`ai.lua:13`) is the only way
    to get two sessions of one agent in one cwd.
- **"A growing set of internals": confirmed.** Section 2 lists:
  - five internal modules
  - one method monkey-patch
  - two undocumented events
  - two window-variable stamps (read and forged)
  - runtime mutation of three config tables
- **One correction to `zed-design-lessons.md` section 9.** It says a
  worktree session "needs no sidekick change. The cwd is passed at spawn."
  - Through the public API it is not. No public entry point accepts a cwd.
  - The cwd is whatever `getcwd(0)` returns in the window that triggers the
    spawn (`sk: cli/state.lua:185`, `sk: cli/session/init.lua:98-101`).
  - The cwd is not even read at call time.
    - `cli.show` → `State.with` → `ui/select` (`auto`) → `use`, which is a
      `vim.schedule_wrap` (`sk: cli/state.lua:148`) → `State.attach` →
      `Session.new` → `getcwd(0)`.
    - So the cwd is read at least one main-loop tick later, in whichever
      window is current *then*.
  - **An `:lcd` wrapper** must hold the window-local cwd across that hop
    and restore it afterwards, and hope nothing switches windows in
    between.
  - **A `:tcd` wrapper** has the same problem, and it also changes the
    editor's cwd for the whole tab.
  - **The only synchronous route is internal:**
    `State.attach({ tool = tool, session = Session.new({ tool = name, cwd
    = path }) }, { show = true })`. It works because `M.attach` uses
    `state.session` when one is provided (`sk: cli/state.lua:185`).
  - **A global `:cd` (isolation model 2a) adds a further trap.**
    - Respawning a dead bare name, such as a `<M-n>` resurrecting `claude`,
      happens in whatever worktree the editor is on, not where that row
      used to live.
    - Unstarted rows in `State.get` are computed for the *current* cwd
      (`sk: cli/state.lua:99`).
- **One partial correction to the "keep sidekick for" list in
  `zed-design-lessons.md`.**
  - The fs watcher duplicates the config's own `checktime` (`autoread`,
    `configs.lua:39-70`).
  - The spawn env plumbing (`NVIM`, `SIDEKICK_SESSION`) is about 10 lines.
  - Neither is a reason to keep sidekick. Context rendering is.

## 4. Upstream activity and maintenance risk

From `gh api` reads of the upstream repository, 2026-11-22:

- **Releases:** v2.1.0 (2025-10-23), v2.2.0 and v2.3.0 (both 2026-03-20).
- **Commits since 2.3.0:** six non-bot commits.
  - 2026-03-20/24: diagnostics context, scrollback.
  - 2026-04-22: mux dump limit, scrollback enter.
  - 2026-09-08: NES on LspNotify, claude column, leftcol.
  - None since 2026-09-08.
- **About 60 open issues and PRs.** The relevant open, unmerged ones:
  - resume and session selection (#223, #306)
  - a kind filter for sessions (#341)
  - a tmux duplicate-session-id crash (#297)
  - "support mux backends registered by other plugins" (#365)
  - an omp tool preset (#358)
- **What this means.** The upstream `sidekick-windowless-prewarm.md:105-110`
  rejected a fork because "sidekick is young and fast-moving". That premise
  no longer holds. sidekick is now slow-moving and selective about merges.
  - **Breakage risk from updates is low.** There are few commits, and none
    in the last 2.5 months has touched session, state or terminal code that
    this config depends on.
  - **The odds of upstream fixes are also low.** None of the earlier docs
    records an issue or PR filed by this setup, and similar community PRs
    sit open for many months.
  - **Pin explicitly.** The spec `{ src = gh('folke/sidekick.nvim') }`
    (`plugins.lua:102`) carries no `version`, so the next
    `vim.pack.update()` moves to whatever upstream HEAD is.
  - The lockfile/checkout mismatch noted in the intro shows the pin is
    already loose in practice.

## 5. Capability matrix

How well sidekick supports each likely feature from `zed-feature-survey.md`.

- **Public API:** what you can do through the documented surface.
- **With internals:** what is possible by reaching into internals, as the
  config does today.
- **Verdict:** whether sidekick helps, is neutral, or gets in the way,
  compared with building the feature in an owned module.

| Feature | Public API | With internals | Verdict |
| --- | --- | --- | --- |
| Several sessions of one agent, same cwd | no | yes, clone preset into cli.tools | in the way |
| Stable session id, labels display-only | no | partial, the name is the id | in the way |
| Capture agent session id (hooks) | n/a | n/a, ours already | neutral |
| Resume by agent session id | no, resume fields inert | yes, clone with resume argv | in the way |
| Persisted rows, lazy respawn (dormant) | no | partial [1] | in the way |
| Turns survive nvim restart | yes, mux backend | yes | helps, loses identity [2] |
| Spawn without a window (pre-warm) | no | hack, open_win patch | in the way |
| Spawn in an explicit cwd | no [3] | yes, Session.new | in the way |
| Status from hooks | n/a | n/a, ours already | neutral |
| Status from OSC and titles | no | yes, via buffer var | neutral |
| Many concurrent terminals | yes | yes | mild cost [4] |
| MRU switcher | no | partial, terminal atime | neutral |
| Per-worktree grouping | no | partial, session cwd | neutral to in the way [5] |
| Send context (templates, refs) | yes | yes | helps |
| Prompt library | yes | yes | helps |
| Send without showing (background) | no, send shows | no, terminal send shows | in the way |
| Right or left column layout | yes | yes | helps, a little |
| Embed in agent view or grid | no | forged stamps | in the way |
| Kill or exit handling | yes, async | yes, State.detach | mild cost [6] |
| NES and Copilot | yes | yes | not wanted |

Notes:

- **[1]** Registered but unstarted tools do appear in `State.get` as rows
  with no session (`sk: cli/state.lua:97-107`). A dormant row could be a
  cloned tool whose `cmd` is the resume argv. That works, but the label,
  agent session id and timestamps still have to live in our own registry.
- **[2]** tmux rediscovery maps panes back to *configured* tools by process
  regex (`sk: cli/session/tmux.lua:124-155`), so `claude 3` returns as a
  second bare `claude`. Rediscovery also runs the shell-out scans that the
  config stubs for speed (`ai.lua:174-204`; upstream
  `sidekick-multi-claude-sessions.md:380-457`).
- **[3]** The cwd is `getcwd(0)` of the window active at spawn time.
- **[4]** Global per-terminal autocmds (section 1), and an `executable()`
  per configured tool on each `State.get`. libvterm's cost is the same
  under any option.
- **[5]** It depends on the isolation model; see section 6.
- **[6]** `cli.close` is two scheduled hops late (`sk: cli/state.lua:145-148`).
  Quick or failed exits skip the detach (`sk: cli/terminal.lua:189-205`).

**Reading the matrix:**

- sidekick earns its place through the **context path**: rendering, the
  prompt library, and the claude format.
- It also handles the basic open/close of one column.
- Every **session-management** row is "in the way" or "neutral", and those
  are the features this project is about.

## 6. How isolation changes the picture

The recommended destination is the same under all four isolation models.
What changes is how urgent the backend swap (step two) is.

The headings below map onto `isolation-analysis.md` like this:

| This section | isolation-analysis.md |
| --- | --- |
| Shared tree | model 1 |
| One nvim per worktree | model 3 |
| Worktree per agent, one nvim | 4a (home nvim, agents anywhere) |
| One nvim across many worktrees | 2a (global `:cd`) and 2b (tabs with `:tcd`) |

That doc leans to **2a on top of 4a**, with model 1 for light work, so the
last two subsections are the ones that matter. Under that leaning, its
"decide early" list is effectively a list of things sidekick cannot do
without internals:

- **Row-id identity with `tool`, `cwd`, `worktree_root`, `main_root` and
  `agent_session_id`.** sidekick's identity is the tool name plus a hash of
  cwd, and it stores none of those fields.
- **Spawn with an explicit cwd.** Not in the public API, and only reachable
  asynchronously by side effect (section 3).
- **Agents fixed to their spawn cwd.** A running sidekick session does keep
  its cwd. A respawn or resurrection by name takes the editor's current cwd
  instead.
- **Context refs relative to the target session.** sidekick renders
  against the code window's cwd.

All four are native properties of the owned registry and backend in
options D and E. Under B they become adapter workarounds.

### Shared tree, one nvim (today's model)

- sidekick works as it does today.
- Step one (the registry) delivers stable ids, labels, MRU, persistence
  metadata and resume. Resume would run through cloned tools with the
  resume argv as an interim.
- **Backend swap:** optional, driven by pre-warm, embed or send-in-background
  pain.

### One nvim per worktree

- Each nvim's `getcwd` is its worktree, so the cwd issue goes away and so
  do name collisions across worktrees.
- A cross-worktree overview has to come from outside any single nvim, for
  example a shared state file. sidekick is no help there either way.
- **Backend swap:** optional, as for the shared tree.

### Worktree per agent, one nvim

- **Spawn cwd:** a session must spawn in the worktree's cwd, which needs
  internals or a `:tcd` dance (section 3).
- **Name routing:** the same agent name in two worktrees has two `sid`s but
  one `tool.name`. Name-filtered `show`/`send` then pops sidekick's
  picker, and `ai.lua`'s name-keyed `active` becomes ambiguous (already
  documented: upstream `sidekick-multi-claude-sessions.md:347-362`).
- **Context paths:** templates render paths relative to the *code
  window's* cwd (`sk: cli/context/init.lua:207`), not the target agent's
  worktree. A send from the main checkout to a worktree agent then points
  at the wrong copy of the file. No sidekick option addresses this. An
  owned send path can rewrite refs for the target row's cwd.
- **Backend swap:** do it before the worktree work.

### One nvim across many worktrees (2a global `:cd`, 2b tabs with `:tcd`)

- Same as the previous model, plus the editor's own cwd now moves.
- **2b (tabs with `:tcd`):** tab-local cwds make sidekick's implicit cwd a
  little less wrong. But spawn routing then depends on which tab is
  current. `isolation-analysis.md` cites exactly this ("`:tcd` silently
  changes sidekick's spawn cwd") as one reason it prefers 2a.
- **2a (global `:cd`):** every implicit-cwd path is wrong as soon as you
  switch worktree:
  - a bare-name respawn
  - the `<M-n>` resurrection of a dead `claude`
  - the pre-warm, which also gates on `vim.fs.root(0, '.git')`
- **Backend swap:** do it before the worktree work. This is the leaning's
  case.

## 7. Options

### A. Keep sidekick and build on its public API

- **What it means:** use only `cli.*`, `status.cli()` and config options.
- **Effort:** low per feature, but most features cannot be built at all
  (section 5).
- **Risk:** the config left option A behind when it took on dynamic
  sessions. Going back would mean giving up several sessions per agent,
  the agent view's embedding and the pre-warm.
- **We'd own:** UI only.
- **Upgrade burden:** low.
- **Verdict:** not viable for this project.

### B. Keep sidekick but wrap it behind an owned session layer

- **What it means:**
  - A new registry module (name to be decided, e.g. `agent_sessions.lua`)
    owns the rows: `{ id, agent, label, cwd, agent_session_id, state =
    live|dormant|exited, created_at, last_access }`.
  - It also owns the active and MRU order, labels, and persistence to
    `stdpath('state')`.
  - `ai.lua`, `agentview.lua`, `agent_events.lua` and the statusline read
    and write only the registry.
  - A single adapter (e.g. `agent_backend_sidekick.lua`) holds every
    sidekick internal call that exists today. It maps a row id to a
    sidekick tool name, uses `cli.tools` clones for spawning and resume,
    and handles stamps, embedding and kill.
- **Effort:** moderate.
  - The registry is about 250 to 400 lines.
  - Moving existing code into the adapter is mostly relocation.
  - The tests switch from stubbing three sidekick modules to stubbing one
    adapter.
- **Risk:** low. Nothing user-visible changes until features land on top.
  - Upstream changes become easier to absorb, because breakage is confined
    to one file.
  - sidekick-shaped hacks remain: the pre-warm patch, forged stamps, cloned
    presets, send-always-shows, and the implicit cwd.
- **We'd own:** identity, metadata, persistence and the UI. sidekick still
  owns spawn, windows and liveness.
- **Upgrade burden:** concentrated in one adapter. A re-verify checklist
  already exists (upstream `sidekick-agent-view-internals.md:137-152`).
- **Verdict:** a good first step, and needed by every other option, D
  included. As a final state it leaves the hardest features (dormant rows,
  resume, worktree cwd, background sends) running through hacks.

### C. Vendor or fork sidekick

- **What it means:**
  - Copy sidekick into the config, or point vim.pack at a personal fork.
  - Patch in a cwd option, a spawn that opens no window, `show = false`
    for sends, a stable id separate from `sid`, and resume argv.
- **Effort:** moderate to high.
  - The minimal useful subset (`terminal`, `state`, `session`, `init`,
    `tool`, `context`, `text`, `treesitter`, `config`, `util`) is about
    2,700 lines.
  - Removing the `(tool, cwd)` identity means rewriting `state.lua` and
    `session/init.lua`, which is the core of the fork.
- **Risk:** moderate.
  - We inherit code built for a different model.
  - Upstream fixes have to be ported by hand. With sidekick's current pace
    there are few to port, which also means little benefit from tracking
    upstream at all.
- **We'd own:** everything in the fork, including parts we don't want (the
  mux backends, process scanning, pickers, NES unless deleted).
- **Upgrade burden:** low in volume, but every upstream change needs a
  judgement call.
- **Verdict:** the costs of D with the shape of sidekick. Not recommended.
  The upstream `sidekick-windowless-prewarm.md:108-110` set fork triggers
  (upstream declines, the hack keeps breaking, patches pile up). They are
  partly met today, but D answers them better than C.

### D. Replace sidekick with our own module

- **What it means:** a terminal-agent backend that the config owns, for
  example `agent_term.lua`:
  - **Spawn, about 150 lines:**
    - `nvim_create_buf`, then `nvim_buf_call` + `jobstart(argv, { term =
      true, cwd, env })`. toggleterm's `spawn()` is prior art for spawning
      without a window (upstream `sidekick-windowless-prewarm.md:30-31`).
    - The env sets `SIDEKICK_SESSION = id` and unsets
      `CLAUDE_CODE_EXECPATH`. nvim already sets `$NVIM` for terminal jobs.
    - Argv per spawn: fresh, `--resume <id>`, or `--continue`.
  - **Windows, about 150 to 200 lines:**
    - Show in a right or left column or a float, hide, focus.
    - Embed into any window by `nvim_win_set_buf`, with stamps written by
      us. During the transition, keep writing `vim.w.sidekick_cli` /
      `sidekick_session_id` too.
    - Width memory and promote become part of `show()` instead of event
      handlers.
  - **Lifecycle, about 100 lines:**
    - Buffer-scoped autocmds only.
    - On `TermClose`, mark the row exited (keep it, show the exit status)
      instead of deleting it. That is what gives dormant rows and resume.
  - **Send, about 80 to 120 lines:**
    - Render with sidekick's public `cli.render()`, or with our own
      renderers.
    - Apply the agent's format.
    - Write with bracketed paste over `nvim_chan_send`. The config already
      does this for `p` (`ai.lua:501-505`).
    - Keep a small readiness queue for freshly spawned rows, and do not
      force a window open.
  - **Registry and persistence:** from B, about 250 to 400 lines.
- **Rough size:** 600 to 800 lines of new Lua, against about 1,270 lines of
  sidekick core (`terminal`, `state`, `session`, `init`, `tool`) and about
  600 adapter lines in `ai.lua` that it replaces.
- **What we would lose if sidekick went entirely:**
  - **Context renderers** (`{selection}`, `{diagnostics}`,
    `{diagnostics_all}`, `{file}`, `{buffers}`, `{this}` dispatch), the
    prompt library (`<leader>ao`), and the in-terminal `<c-b>`/`<c-f>`
    pickers. We care about these. `ai_context.lua` already replaces four
    renderers, and the rest is roughly 300 to 500 lines to port. This is
    why D should be the hybrid E below, not a clean break.
  - **NES and Copilot status.** Already disabled; we don't care.
  - **The tmux/zellij backends.** Disabled and stubbed today, and they
    lose identity anyway ([2]).
    - If running turns must survive an nvim restart, an owned wrapper
      (`tmux new -d -s <row id>` plus a terminal running `tmux attach`)
      is about 100 lines.
    - Because it is keyed by row id, it would keep identity. It can wait
      until that need is real (open question 1).
  - **opencode external-server discovery.** Already stubbed.
  - **Scrollback.** Mux-only, so inactive here.
  - **The fs watcher.** Redundant with `configs.lua` checktime.
  - **Default terminal keymaps** (`q`, `<c-q>`, `<c-.>`, `<c-z>`, nav).
    The config already layers its own (`utils.term_nav_keymaps`,
    `ai.lua:376-511`), so porting the few we keep is small.
- **Effort:** high relative to B, but bounded. The hard behavioural work
  (rings, view, routing rules) already exists and stays.
- **Risk:** moderate during the swap, because routing, embedding and
  pre-warm all change backend. A feature flag (section 9) contains it.
- **We'd own:** spawn, windows, lifecycle and identity.
- **Upgrade burden:** none from sidekick for sessions.

### E. Hybrid: owned sessions and terminals, sidekick as a context library (recommended)

- **What it means:** B, then the D backend, while keeping sidekick
  installed for the context path only.
  - **The public calls we keep:** `require('sidekick').setup({ cli = {
    context = …, prompts = … }, nes = { enabled = false } })`,
    `cli.render()` and `cli.prompt({ cb })`.
  - **Formatting:** either call the preset's `format`
    (`require('sidekick.cli.tool').get(agent):format(text)`), which is one
    small internal, or port claude's 15-line format into `ai_context.lua`.
    The second option leaves zero internals.
- **A compatibility constraint we keep on purpose:** owned terminal buffers
  keep the filetype `sidekick_terminal`.
  - sidekick's context-window picker skips that filetype
    (`sk: cli/context/init.lua:195-198`). Without it, a send could render
    against the agent terminal instead of the code buffer.
  - stickybuf, `buffers.lua` and the panel clamp also key on it.
  - Renaming is possible, but it is a separate, grep-wide change.
- **Effort:** B plus D-minus-renderers.
- **Risk:** as for D, but the context path, which is what users actually
  touch most, does not change.
- **We'd own:** sessions and terminals. sidekick owns the template
  language.
- **Upgrade burden:** we depend on three documented entry points and one
  filetype convention.
- **What we lose:** nothing we use today.

## 8. Recommendation

**Go with E, built in order: B first, then the owned backend. Not C, and
not A.**

### Deciding factors

1. **The model mismatch is structural.**
   - Every session feature on the survey assumes a row whose identity is
     independent of tool name and cwd, and which can exist without a live
     process.
   - sidekick has neither: its sessions are `(tool, cwd)` and exist only
     while running.
   - The config already pays for the mismatch with about 600 adapter lines
     and silent-failure tripwires (`ai.lua:254-260`, `:645-665`).
2. **The features we want sit on the internals we already depend on.**
   - Resume, dormant rows, a spawn with no window, an explicit cwd, sends
     that don't steal a window, and embedding are all "in the way" or
     "hack" in the matrix.
   - Building them on sidekick would deepen exactly the coupling that
     `zed-design-lessons.md` flagged.
3. **The part of sidekick we value is separable and public.**
   - Context rendering and prompts are reachable through documented API
     and do not depend on sidekick owning the terminal.
4. **Upstream is slow, so waiting buys nothing.**
   - Low churn makes the interim (B) safe to run for a long time.
   - It also makes "wait for upstream resume/cwd/windowless" a poor plan.
5. **B is needed under every option.** The registry is the same code
   whether the backend is sidekick or our own, so starting there commits to
   nothing irreversible.
6. **The isolation leaning makes an explicit cwd a day-one requirement.**
   - `isolation-analysis.md`'s first build step is 4a's agent layer: rows
     keyed by id with an explicit cwd, and agents in worktrees the editor
     isn't on.
   - On sidekick that requires either the async `:lcd` wrapper or the
     internal `Session.new` + `State.attach` call (section 3).
   - The owned backend's `spawn({ cwd, argv, env })` makes it a parameter.
   - **This is the factor that moves step two from "eventually" to "before
     worktrees".**

### What would change this

- **Upstream merges** a per-session id distinct from `sid`, a `cwd` option,
  resume argv, and a spawn or send that opens no window (#223/#306, or
  something similar). Then B on sidekick could be the final state. Check
  before starting step two.
- **Triage drops** persistence, resume and background sends, *and*
  isolation moves away from the current leaning to nvim-per-worktree or a
  shared tree. Then B alone is enough, and the backend swap is not worth
  it.
- **Running turns must survive an nvim restart, and you'd rather not own a
  tmux wrapper.** sidekick's tmux backend then gains real value, but it
  still loses identity ([2]), so the honest comparison is "fix sidekick's
  rediscovery" against "own 100 lines of tmux".
- **Measurement shows libvterm can't sustain 6 to 8 streaming agents.**
  That is backend-independent. It would push toward fewer live terminals
  (dormant rows matter more) rather than toward sidekick.

## 9. Migration path

Each step leaves `<leader>a*`, the `<M-*>` in-terminal keys, the agent view,
rings and context sends working. Run `tests/agentview/run.sh` before and
after each step.

0. **Pin and reconcile.**
   - Decide which sidekick commit to run, `17447a0` or the lockfile's
     `3d80a47`, and make the checkout match.
   - Pin it in `plugins.lua` with `version = '<sha>'`, so a blanket
     `vim.pack.update()` can't move it unseen.
   - Turn the internals re-verify list (upstream
     `sidekick-agent-view-internals.md:137-152`) into a headless smoke test
     next to `tests/agentview/`.
1. **Registry, with no behaviour change.**
   - Add `agent_sessions.lua`, with row id = today's sidekick tool name
     (`claude`, `claude 2`, `cursor: foo`).
   - Move `_labels`, `_dynamic`, `active`/`_last` (extended to an MRU list)
     into it.
   - Point `agentview.rows()`, `statusline.lua` and `agent_events` lookups
     at it.
   - Move every `sidekick.cli.state/terminal/session/config` call into one
     adapter.
   - Re-point the tests' stubs at the adapter.
2. **Identity.**
   - New rows get opaque ids, for example `claude#7`. Short ids keep
     sidekick's `sid` hash slice non-empty.
   - Labels become display-only and may repeat. That retires the
     `name_taken`/`label_taken` guards and the 16-character warning.
   - `SIDEKICK_SESSION` carries the row id, so the env var name stays the
     same and the four producers need no change.
   - Add a Claude `SessionStart` registration that hands
     `session_id`/`source` to the registry (`zed-design-lessons.md`
     section 2). Do the same for other agents where their extension API
     allows.
3. **Persistence and resume on the sidekick backend, as an interim.**
   - Write rows to `stdpath('state')` and load them dormant.
   - Respawn through the adapter, by registering a cloned tool whose `cmd`
     is the resume argv.
   - This proves the UX before any backend work.
   - It is the natural place to stop if the triggers in section 8 point
     that way.
4. **Owned backend, behind a flag.**
   - Add `agent_term.lua`, implementing the same adapter interface as
     `agent_backend_sidekick.lua`.
   - Select it with `vim.g.agent_backend = 'own'`. The default stays on the
     sidekick backend until the new one has been used for a while.
   - Keep the `sidekick_terminal` filetype and write both stamp sets.
   - Context sends go through `cli.render()`, plus our own paste and
     readiness queue.
   - The pre-warm becomes a plain spawn with no window. Its open_win patch,
     the flag and Guard 2 go away; Guard 1 and the timer stay, as
     `sidekick-windowless-prewarm.md` Phase D planned.
   - Under the isolation leaning (2a on 4a), do this step **before** the
     worktree work. The explicit `cwd`, rows pinned to their spawn cwd, and
     target-relative ref rewriting all live here.
   - **Under that leaning, step 3 can be skipped.** Build persistence and
     resume directly on the owned backend. Prototyping resume through
     cloned sidekick tools would be throwaway work.
   - **If a worktree prototype is wanted before this step,** the stopgap is
     the internal synchronous call `State.attach({ tool, session =
     Session.new({ tool = name, cwd = path }) })`, inside the adapter. Do
     not use an `:lcd`/`:tcd` wrapper around `cli.show`.
5. **Retire the sidekick adapter.**
   - Delete `agent_backend_sidekick.lua`, the backend stubs, the tool
     pruning and the preset tripwires.
   - Shrink `setup()` to `context`, `prompts` and `nes = { enabled = false
     }`.
   - Update GUIDE.md's `AI (sidekick.nvim)` section and the "Sidekick's
     session backends shell out" design note. Both are grep anchors, so
     check references before renaming.
6. **Optional, later:** port the remaining renderers and the prompt picker,
   then drop sidekick. Low value while the public context API stays stable.
   Revisit only if it breaks.

## 10. Open questions

1. **Persistence:** must running turns survive an nvim restart (process
   persistence through tmux), or is resume-by-id on demand enough? This
   decides whether a mux layer is ever needed, and whether it is ours or
   sidekick's.
2. **Isolation:** do you accept `isolation-analysis.md`'s leaning (one home
   nvim, global `:cd`, agents in other worktrees)? If yes, step 4 comes
   before any worktree work, and step 3 is skipped (section 9). If you move
   to nvim-per-worktree or a shared tree, step 4 becomes optional.
3. **Naming:** is it acceptable to keep the names `sidekick_terminal`
   (filetype) and `SIDEKICK_SESSION` (env var) after sidekick stops owning
   terminals? Or should they be renamed once, across the four producers,
   stickybuf, `buffers.lua` and the panel clamp?
4. **Long-term dependency:** should sidekick stay a dependency just for
   context rendering and the prompt library? Or is it a goal to drop it
   eventually (step 6)?
5. **Pinning:** which commit should be pinned? Should `plugins.lua` carry
   an explicit `version` from now on, rather than relying on the lockfile?
6. **Session naming UX:** are you happy to move to opaque ids with
   display-only labels that may repeat? It changes how `<leader>an` labels
   behave (a repeated label would no longer re-attach to the same session).
7. **Pre-warm:** once it is cheap, should the pre-warm extend to other
   agents, or resume the most recent dormant claude row instead of starting
   fresh?
8. **Upstream:** is filing issues or PRs (a cwd option, a spawn with no
   window, a session-id stable across restarts) worth doing anyway, given
   the merge rate? None of the earlier docs records one being filed.
