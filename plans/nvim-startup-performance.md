# Speed up nvim startup + session restore (`<leader>qs`)

**Status (shrunk 2026-07-18):** Phase 1 — de-colliding the startup/restore window —
**shipped and verified in full** (commits and verification record in "Post-landing
status + design review" below). Phase 2 — the on-demand module deferrals — is
**parked for good**, with its revival trigger recorded in the same section. This doc
was cut to roughly half on 2026-07-18: the Phase 1 triage tables and step-by-step
spec are spent and live in this file's git history; what remains is the verified
mechanics, the unshipped Phase 2 spec, the Q&A rationale (kept for posterity), and
the post-landing record.

## Context — what the profiling found

Headless startup was ~124ms with everything loading eagerly, but the sluggish *feel* —
especially `<leader>qs` — was a **startup collision**, not module load time: the
claude-CLI pre-warm (~1–2s of node CPU at +100ms), the toggleterm shell pre-warm,
mason-tool-installer's daily ~19-package update check, and `configs.lua`'s background
checks all landed in the same window as the async storm session restore triggers
(rust-analyzer indexing, Copilot LSP, lua_ls, treesitter/gitsigns per buffer). Phase 1
rescheduled that eager work out of the window; the Phase 2 deferrals below are a
~22ms once-per-session polish at the edge of perception.

An Opus adversarial review verified every plugin-level gotcha empirically (neogit
`did_setup` lock-in, plugin-phase clobbering of init-time command overrides, nvim-tree
pre-setup error notify, toggleterm `spawn()` non-idempotency, mason `start_delay`,
persistence Load events). Debugging (dap) deferral was dropped: for a Rust-first user
its 5.8ms would be reloaded ~2s after the first `.rs` buffer anyway, and its dap-ui
listener wiring has five entry points (incl. unguarded `:Dap*` commands) — highest
risk, no real gain.

Key mechanic (verified): `vim.pack.add` puts every plugin on the rtp and sources its
`plugin/` files during startup regardless of our `packadd` calls — so deferral targets
the `require()`/`setup()` work, plugin commands still exist, and `require()` resolves
at any time.

---

## Phase 2 (parked) — defer on-demand modules (~22ms)

### 5. `utils.lua` — add `M.lazy_setup(fn)`
Returns a memoized `ensure()`: runs `fn` on first call, no-ops after (module-local flag, resets on
re-source like today's eager behavior).

### 6. `gitui.lua` — defer neogit setup (11.3ms) — **`<leader>g*` only**
- Wrap the neogit packadd + `setup{}` in `ensure()`; prepend it in the `<leader>g*` callbacks only.
- **Leave `<leader>v*` untouched**: diffview has no `setup()` call today, runs on defaults, and is
  already on the rtp via `vim.pack.add` — routing it through neogit's ensure would add an
  unnecessary 11ms to plain diffview opens. Keep `local dv = require('diffview')` as is.
- **`:Neogit` override (required):** `neogit.open()` auto-setups with `{}` and `setup()` has a
  `did_setup` guard — a manual `:Neogit` before first keypress silently locks in default config.
  Re-register the command to call `ensure()` first, from a **`UIEnter`-once autocmd** (an
  init-time override gets clobbered when the end-of-startup plugin phase re-sources `plugin/`
  files — verified empirically).

### 7. `testing.lua` — defer neotest (7.6ms → ~15-19ms since Go landed)
- **The payoff roughly doubled (2026-07).** Adding Go support put `neotest-golang` in the
  adapter list, and constructing it eagerly costs **~7-11ms** on its own (it `require`s
  plenary's whole lib chain at load). `nvim-dap-go` adds a further ~1.5ms to `debugging.lua`.
  Every session pays it, including ones that never open a `.go` file — Rust, by contrast, is
  ftplugin-lazy via `rust.lua`. Deferring this item now buys ~15-19ms, not 7.6ms.
- `ensure()` wraps packadds + `neotest.setup{adapters={...}}`; all `<leader>n*` prepend it.
  (`<leader>nd` needs no extra wiring now that dap stays eager.)
- `rust.lua` stays an eager require in `init.lua` (keeps the deferred adapter require safe) —
  reword the ordering comments in `init.lua`/`testing.lua`/nvim `CLAUDE.md`.
- Careful: `testing.lua` now builds its adapter list behind a `pcall` so a broken
  neotest-golang can't take neotest (or Rust tests) down with it. Preserve that guard when
  moving the setup into `ensure()`.
- Optional: `UIEnter`-once `:Neotest` override calling `ensure()` (failure without it is loud,
  not silent — lower priority than `:Neogit`).

### 8. `filetree.lua` + `keymaps.lua` + `outline.lua` — defer nvim-tree (3.6ms)
- Keep eager: netrw-disable globals, QuitPre auto-close autocmd (needs no setup). Defer: setup +
  FileCreated subscription. Export `{ ensure, is_ready }`.
- `keymaps.lua` `<leader>e` calls `ensure()` first. `outline.lua` `<leader>o` must check
  `require('filetree').is_ready()` before `nvim-tree.api.tree.is_visible()` — pre-setup that call
  emits a `[NvimTree] setup not called` error notify (verified). A never-setup tree can't be
  visible, so the guard is exactly equivalent.
- Sessions never contain the tree, so restore can't surface a broken panel.

**Not deferred, deliberately:** debugging.lua (see Context), completion.lua/blink,
plugins.lua's telescope/treesitter setup, git.lua/gitsigns, aerial (symmetric candidate to
nvim-tree — revisit only if Phase 2 proves worthwhile).

### 10. `grugfar.lua` — grug-far ships lazy from day one (NOT a parked item)
Unlike the deferrals above, grug-far shipped **lazy-loaded from the start** (greenfield, so no
migration risk to weigh against reviving Phase 2). `grugfar.lua` (the shipped code)
registers the `<leader>sR` keymap + the `special_filetypes`/stickybuf glue eagerly (all
plugin-independent), and memoizes `packadd('grug-far.nvim')` + `setup{}` behind a local
`ensure()` that fires on first `<leader>sR` press — the same shape as Phase 2's `ensure()`
pattern (step 5), hand-rolled locally rather than via the shared `utils.lua` helper (not built
while Phase 2 is parked). `:GrugFar`/`:GrugFarWithin` still exist from boot (vim.pack sources the
plugin/ files), so no command override is needed. Recorded here for the timeline/registry; it is
**not** a Phase-2-revival dependency. If `utils.lua`'s `lazy_setup` ever lands, migrate
grugfar.lua's local `loaded` flag to it.

### 9. Doc sync (same change, per repo rules)
- GUIDE.md: Architecture "Plugin loading pattern" + file-responsibility bullets + Load-order
  rewording; new Design Decisions subsection ("On-demand modules set up on first use"); first-use
  notes in the Neogit/Rust-testing/nvim-tree/toggleterm/AI/LSP Part 2 sections.
- nvim `CLAUDE.md`: reword the "rust before testing" bullet.

## Verification (Phase 2, if revived)

Steps 5 precedes 6–8; Phase 1's verification checklist all passed 2026-07-10 (see below).

6. `nvim --startuptime` before/after — gitui/testing/filetree drop (~22ms total), nothing new >1ms.
7. First-press smoke tests: `<leader>gg/gc/gq` (config applied: tab kind, no gutter signs),
   `<leader>vv/vp/vq` (unchanged path), `<leader>nn/ns/nd` in a Cargo project, `<leader>e` both
   ways, `<leader>o` before ever opening the tree (no error notify), panel swaps.
8. Command paths: `:Neogit` (our config applied → override works), `:DiffviewOpen`, `:Neotest run`.
9. `:checkhealth` / `:messages` clean; GUIDE.md/CLAUDE.md greps resolve; re-source the three
   deferred modules twice each.

---

## Q&A — design rationale (for posterity)

Captured from the review discussion so the *why* survives the plan.

### Q: Why do session restore and the claude pre-warm conflict? Can't we just do both concurrently?

They already **do** run concurrently today — and that concurrency is what makes it slow. The
two jobs aren't waiting on each other (an ordering problem); they're both consuming the same
finite resources at the same instant (a contention problem). Running them in parallel doesn't
create more CPU — it makes them fight over what you have. Three layers:

1. **It's CPU-bound, not I/O-bound.** Concurrency is free only when work is *waiting* (network,
   disk) — then overlapping two waits costs nothing. Here both jobs are compute: claude spawns a
   node process that burns ~1–2s of real CPU booting; session restore's own I/O is cheap (~130ms,
   files are a few KB), but what it *triggers* is expensive — opening each buffer kicks off
   rust-analyzer indexing, the Copilot node LSP, lua_ls, treesitter parsing, gitsigns per buffer.
   Total CPU work is fixed; running them together just makes everything (including the
   rust-analyzer you're waiting on) finish slower.

2. **The real killer: nvim's UI is single-threaded.** The main loop that draws the screen and
   processes keystrokes runs on one thread. Almost all that async LSP/treesitter/gitsigns work
   hops *back* onto the main thread via `vim.schedule` to apply results. When restore floods the
   main loop with callbacks *and* the OS is oversubscribed because claude is eating cores, the
   loop can't service redraws/keypresses promptly. That's the "frozen for a beat right when I
   pressed the key" feeling — not a blocked job, a starved UI thread.

3. **claude is pure overhead at that moment.** When you press `<leader>qs` you want to *see your
   restored session* — you weren't going to press `<leader>aa` in the next 3s. The pre-warm only
   makes a *later* action instant. So deferring it 3s costs you nothing and hands restore the
   whole machine (cores + main-thread headroom) to finish fast.

The whole idea of Phase 1: not "stop pre-warming" and not "force serialization," but **spread the
peak demand over a few seconds** so no single ~200ms window has claude + shell + mason +
rust-analyzer + treesitter all landing at once. Same total work, same concurrency — just not all
stacked on the moment you're staring at the screen.

### Q: Is staggering/deferring a common way to get nvim performance gains? Any plugins that help?

Yes — moving work off the startup path is the single most common nvim performance lever — but it
comes in two flavors, and this plan is mostly the rarer, hand-rolled one.

**Flavor A — lazy-loading (load-on-demand): common, plugins automate it.** "Don't
`require()`/`setup()` until a trigger fires."
- **lazy.nvim** — the dominant manager, built entirely around this (`event`/`ft`/`cmd`/`keys`
  triggers, plus a `VeryLazy` event that fires *after* the UI is up — the "defer off startup"
  idea as a first-class primitive). Ships `:Lazy profile`.
- **mini.deps** — lighter, with a `now()` / `later()` API; `later()` queues plugins to load in
  the background after startup via a scheduler — the closest off-the-shelf thing to what this
  plan does by hand.

  *Catch for this config:* it uses **`vim.pack`** (nvim 0.12's built-in manager), which
  deliberately has **no** declarative lazy-loading — everything lands on the rtp at startup.
  That's exactly why **Phase 2** (deferring neogit/neotest/nvim-tree behind manual `packadd` +
  `ensure()` guards) is hand-written: it re-implements lazy.nvim's `keys`/`cmd` triggers by hand.
  A manager like lazy.nvim would give that declaratively — at the cost of migrating off native
  `vim.pack`.

**Flavor B — de-collision / staggering eager work: bespoke, no plugin does it.** **Phase 1**
(rescheduling the claude/shell pre-warms with timers + persistence events + race guards) isn't
something a plugin gives you. Lazy-loading answers "don't load until needed"; Phase 1's problem is
different — several things you *want* eagerly warmed that just shouldn't all land in the same
200ms. No manager models "spread these N eager pre-warms across a few seconds and guard against
the user racing them." `mini.deps`'s `later()` queue is the nearest concept but wouldn't handle
the sidekick monkey-patch or the `<leader>qs` race guards.

**Tooling that helps regardless of manager:**
- **`vim.loader.enable()`** — core Lua bytecode cache (absorbed the old `impatient.nvim`); often
  a free 10–30ms if not already called early in `init.lua`.
- **Profilers** — `nvim --startuptime` (what this plan used), `:Lazy profile` (lazy.nvim only),
  and **snacks.nvim's profiler** (`Snacks.profiler`) for in-session flame-graph hotspots (snacks
  is already installed here).
- **`snacks.bigfile`** — orthogonal but common: disables treesitter/LSP on huge files, a frequent
  "why is nvim slow" culprit that isn't startup at all.

**Bottom line:** the load-on-demand half (Phase 2) is what managers automate and what this config
reimplements because `vim.pack` won't; the staggering half (Phase 1 — the actual felt fix) is
genuinely bespoke with no plugin shortcut. If startup perf becomes a recurring fight, the biggest
structural lever is reconsidering `vim.pack` vs. a lazy-loading manager; short of that, the manual
approach here is the right tool.

### Q: A lot of code here is written by AI (sidekick, or claude in other terminals) that edits files on disk. Do the interactive autocmds actually catch those external edits — and if so, isn't the checktime-timer win modest?

Both true. The AI workflows **are** covered, and by *which* autocmd depends on where claude runs:

- **claude in another terminal window** → best covered. You alt-tab away (nvim loses focus) and
  back → **`FocusGained`** → `checktime` → all buffers re-check → silent reload (`autoread`).
  Instant on return, independent of the poll interval.
- **sidekick (claude CLI inside nvim)** → covered by three events depending on what you do next:
  leaving the CLI terminal fires **`TermLeave`**; switching to the edited buffer fires
  **`BufEnter`**; sitting idle on it fires **`CursorHold`/`CursorHoldI`** after 300ms. Every path
  by which you actually *look at* an edit trips one of these.
- **multiplexer nuance:** claude in a zellij/tmux pane beside nvim *in the same terminal window*
  may not fire `FocusGained` (depends on the mux forwarding focus events — tmux `focus-events on`;
  zellij's support is uncertain). `BufEnter`/`CursorHold` still catch it when you return to the
  nvim pane.

**So yes, the checktime-interval win is modest** — during active use the events fire `checktime`
often enough that the poll is redundant. One correction to the intuition, though: `CursorHold` is
**one-shot-per-idle-period** (fires once, 300ms after your last movement), *not* a repeating 300ms
poll. So the poll is the *sole* detector in exactly one regime — **focused, idle, watching a
buffer being rewritten** — where, after that single `CursorHold`, detection latency falls to the
timer. That's why the interval bump was framed as a **startup** win (the shipped Phase 1 step 4
delayed the first all-buffer stat sweep, 500→2000ms, out of restore), not a steady-state one, and
why it's a mild *regression* (0.5s → 2s) in that one AI-review regime — with `1000ms` offered as
a hedge.

---

## Post-landing status + design review (2026-07-10)

**Status:** Phase 1 landed in full — `5bd4882` (#3 mason), `5e381b9` (#4 configs),
`5bf993b` (#2 terminal), `b7c1bc7` (#1 ai) — plus two follow-up fixes to the pre-warm
(`a989656` skip-promote, `c8f7cf5` `.git`/tool scoping; both now tracked by
`plans/sidekick-windowless-prewarm.md`).

**Phase 1 verified interactively, 2026-07-10 — all checks passed:** claude spawned ~3s out
(watched via `ps`, using the `watch` formula added to the Brewfile for this); `<leader>qs` felt
fast; `<leader>aa` at ~5s instant and `<C-\>` warm; the early-`<leader>aa` race guards behaved;
re-sourcing `ai.lua` twice showed each `UserSidekick` autocmd registered once, a clean
`:messages`, and the timer arming then self-closing (`<userdata>` → `nil`).

**Phase 2 is parked for good, not just deferred:** the felt problem is fixed, so the
once-per-session ~22ms module deferrals don't earn their risk (the plan predicted exactly this
outcome). Steps 5–8 remain written up above should startup cost ever regress enough to
re-justify them — re-measure with `nvim --startuptime` before reviving them.

### Design review: "should the sprinkled scaffolding be one abstraction?" — no (for now)

After Phase 1 landed, a design review examined whether the recurring shapes — the two
hand-rolled `_G` uv timers, the five staggered delays with no central timeline, the repeated
`has_ui()`/`.git` gates — should be extracted into a shared startup/deferred-task scheduler
(`startup.lua`: name-keyed delay table, `defer(name, fn, {restore_aware, when})`, one
`_G._startup_tasks` registry, a single PersistenceLoadPre/Post pair). An adversarial
counter-review **rejected it**, and the rejection is the settled decision:

- **Effective N is 1, not 3.** The only non-trivial shared machinery — the persistence
  pause/re-arm pair — has exactly one consumer (the claude pre-warm). The other two sites
  (`terminal.lua`, `configs.lua` update check) are bare `vim.defer_fn` calls that need nothing
  beyond the stdlib. The config's own extraction discipline (see nvim `CLAUDE.md`'s
  "wrapper re-evaluation trigger", and `buffers.lua`'s history) extracts on the *third*
  duplicated site, after real drift — not before.
- **Sequencing vs. the sidekick plan.** Migrating `ai.lua`'s scheduling shell pre-Phase-D
  would rewrite the config's most bug-prone code for zero behavior change, then Phase D would
  touch it again — double churn — and would stale Phase D's written keep/delete lists.
- **A central delays table had false uniformity.** Two of five rows (checktime poll,
  mason `start_delay`) aren't schedulable by such a module at all, and moving mason's `30000`
  would orphan the 30–60s rationale comment this plan explicitly requires to sit next to the
  number.

**What was adopted instead:**

1. **Docs-only timeline** — GUIDE.md → Design Decisions → **"Startup stagger timeline"** is
   now the single place all five delays are visible together, with the slotting rule for new
   deferred tasks. Keep it in sync when any delay changes.
2. **A confirmed latent race in the pre-warm timer, fixed in place** (`ai.lua`
   `schedule_prewarm`): the uv fire and its `schedule_wrap`'d callback are a main-loop hop
   apart; a `<leader>qs` landing in that gap runs LoadPre + restore + LoadPost synchronously,
   so the stale queued callback then saw the *re-armed* timer in
   `_G._sidekick_prewarm_timer`, closed it, and ran `do_prewarm()` immediately — claude
   spawning right at restore-end (the exact collision the reschedule exists to avoid) and the
   re-armed pre-warm silently cancelled. Fix: the callback captures its own handle and
   returns unless `_G._sidekick_prewarm_timer == timer` (identity guard). GUIDE.md's
   "Re-source safety" Timers bullet documents the three-part pattern (stop-before-create,
   self-close on fire, identity guard) for any future cancellable one-shot.

**Extraction trigger (recorded so future sessions don't re-litigate):** revisit a shared
scheduler only if a **second restore-aware task** appears (e.g. deciding the shell pre-warm
should re-anchor to restore too), and only **after** sidekick Phase D simplifies `ai.lua`.
Until then, new deferred tasks copy the local patterns and add a row to GUIDE.md's timeline
table.
