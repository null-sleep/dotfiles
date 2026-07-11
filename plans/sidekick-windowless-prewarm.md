# Give sidekick a windowless CLI start (drop the hidden-float pre-warm hack)

## Context — why this exists

`ai.lua` pre-warms the claude CLI so the first `<leader>aa` isn't a ~1–2s freeze. Sidekick
has **no windowless "start the job, don't show it" API** (unlike toggleterm's `spawn()`), so the
config fakes one: it monkey-patches the terminal instance's `open_win` (via sidekick's
`cli.win.config` callback) to create a *hidden* float (`hide = true`), runs `cli.show`, then
`cli.hide`. A real window is created — just flagged hidden — and anything that reconfigures that
window can un-hide it.

That fragility already bit us: `SidekickCliAttach` → `promote_to_full_height` → `wincmd L`
converts the hidden float into a **visible split** (empirically verified:
`relative=editor/hide=true/focusable=false` → `relative=''/hide=false/focusable=true`), which the
pre-warm's Guard 2 then mistook for a user-opened CLI and left on screen. Patched in
`a989656` (skip promotion while `_G.__sidekick_prewarm` is set), but the underlying hack remains
brittle: **any upstream window-touching autocmd can re-break it.**

### Root cause (the seam)

Sidekick's `M:start()` (`cli/terminal.lua:147`) couples buffer-create + window-open + job-start.
The job launches *inside* the window (`cli/terminal.lua:280`):

```lua
vim.api.nvim_win_call(self.win, function()
  self.job = vim.fn.jobstart(norm_cmd, { cwd = self.cwd, term = true, ... })
end)
```

The only reason `self.win` must exist is to make `self.buf` current so `jobstart{term=true}`
attaches to it. Toggleterm avoids a window entirely (`toggleterm/terminal.lua:471` `spawn()` →
`nvim_buf_call(self.bufnr, __spawn)` → `termopen`). The rest of sidekick's terminal lifecycle is
already window-optional: `buf`/`job`/autocmds key off `self.buf`, and every window touch goes
through `win_valid()` guards.

### More hidden-float fragility (from the startup-perf Phase 1 review + source tracing)

An adversarial review of the reschedule work (plus reading the sidekick source) surfaced two more
races that are **inherent to the hidden-float hack** — both dissolve under a windowless start (no
window during pre-warm ⇒ no `open_win` override, no `_G.__sidekick_prewarm` flag, and `is_open()`
is false):

- **#3 — Cleanup timing race.** `cli.show`'s work runs through a `vim.schedule_wrap`'d `use`
  callback (`cli/state.lua:148`); `Terminal:init()` (which installs the hidden-float override) and
  `open_win` run back-to-back inside it. The pre-warm clears `_G.__sidekick_prewarm` on a fixed
  300 ms timer — so if that scheduled callback is delayed past 300 ms by a main-loop stall (exactly
  the LSP/treesitter storm the 3 s pre-warm lands in), the override isn't installed when `open_win`
  runs, claude opens **visible**, and Guard 2 then leaves it up. Low probability (needs a ~300 ms
  freeze) but it's a *second* path to the same stuck-visible symptom the `wincmd L` bug caused.
- **#4 — `<leader>aa` during the pre-warm window.** While the hidden float is alive (`self.win`
  valid), `cli.toggle` reads `is_open()` as true and *hides* it — showing nothing
  (`cli/init.lua:100`, `cli/terminal.lua:487`). A cold `<leader>aa` before the float exists, or
  after it's hidden, is fine; the ~300 ms show→hide window is the hole.

The startup-perf Phase 1 follow-up fixed only the confidently-correctable issues in place — the
lost `.git` gate on the reschedule path and the guards matching any tool instead of claude
(`c8f7cf5`). #3 and #4 are **awkward to fix in the hack** (both are properties of "there is a
window"), so they're carried here: **Phase B** hardens them in the hack as an interim if needed,
and **Phase D** eliminates them structurally. They are the strongest remaining argument for the
windowless rework (Phases C–D).

### Decision: don't fork

Sidekick is young and fast-moving (folke). Carrying a patched method means a rebase tax on every
upstream change for a *single* method — the maintenance cost dwarfs the payoff. Prefer an upstream
PR; keep the hardened monkey-patch as the interim; fork only as a last resort (upstream declines
**and** the hack keeps breaking **and** we accumulate more sidekick patches).

---

## Phase A — Prototype locally to de-risk (throwaway, not committed to this repo)

Prove the two caveats are handleable *before* proposing anything upstream. Edit the installed copy
(`~/.local/share/nvim/site/pack/core/opt/sidekick.nvim/lua/sidekick/cli/terminal.lua`) on a scratch
branch / stash — this is an experiment, nothing lands in dotfiles here.

Minimal change to validate:
- In `M:start()`, replace `nvim_win_call(self.win, jobstart)` with `nvim_buf_call(self.buf, jobstart)`
  and remove the in-`start()` `self:open_win()` (`cli/terminal.lua:157`). `show()` already appends
  `open_win()` (`cli/terminal.lua:413`), so `show()`/`focus()`/`toggle()` should keep working.
- Add a throwaway `M:spawn()` = `start()` with no window, to exercise the pre-warm path.

**Validate:**
1. **PTY sizing.** `nvim_buf_call` runs in the fixed-size autocmd window, so the terminal launches
   at the wrong dimensions. Confirm claude's TUI reflows correctly once a real window opens (first
   `show`) — i.e. it takes the SIGWINCH and repaints at the right width, no garbled first frame that
   sticks.
2. **Ready-detection.** The boot-detection timer reads `nvim_win_get_cursor(self.win)`
   (`cli/terminal.lua:263`) and currently needs a window; windowless it must fall back cleanly
   (there's a `READY_MAX_WAIT` timeout already). For pure pre-warm we don't need readiness, but the
   PR must not regress the normal path.
3. `show`/`focus`/`toggle`/`hide`/`close` still behave for a normally-opened CLI.

If PTY sizing turns out ugly/unfixable, stop and reassess (the hardened monkey-patch stays; no PR).

---

## Phase B — Harden the hidden-float hack against #3/#4 (interim, in-repo)

**Optional / superseded by Phase D.** These two races live only in the hidden-float hack, which
Phase D deletes outright — so do this **only if Phase C (upstream) stalls and the races actually
bite**. If the windowless API lands soon, skip straight to Phase D. Caveat up front: this touches
the delicate flag/override lifecycle (the same code the `wincmd L`, `.git`, and tool-scoping bugs
already came from), and Phase D throws it away — hence "interim, only if needed."

- **#3 — make the cleanup event-driven (removes the fixed-timing guess).** Today `do_prewarm`
  clears `_G.__sidekick_prewarm` and calls `cli.hide` on a fixed 300 ms `vim.defer_fn`, which can
  fire *before* the scheduled `cli.show` installs the override under a main-loop stall. Instead,
  trigger the flag-clear + `cli.hide` from **inside the override's `open_win`** — it runs exactly
  when the hidden float is created, so the cleanup can't out-race the show. Add a fallback timer
  (~2 s) that clears the flag if `open_win` never fires (show failed / claude missing), so a later
  real `<leader>aa` can't inherit a stuck override.
- **#4 — mitigate (no clean full fix in the hack).** The float is genuinely `is_open()`-true while
  it exists, so `<leader>aa` toggling it closed can't be fully prevented without removing the
  window. The event-driven cleanup above shrinks the vulnerable window to ~one schedule tick after
  the float opens; the full fix is Phase D (no float to toggle). Accept the shrunken window as the
  interim state — document it, don't chase a fragile in-hack workaround.
- **Commit** as one `fix(nvim):` commit here with `Part-of: plans/sidekick-windowless-prewarm.md`;
  update GUIDE.md's `Re-source safety` bullet if the timer shape changes.

---

## Phase C — Upstream PR to sidekick.nvim

Open an issue first sketching the approach (cite toggleterm's `spawn()` as prior art), then a PR.
Shape options (author's call, but propose):
- A public `M:spawn()` / `M:prewarm()` that starts the job windowless, **or**
- a `cli.show({ show = false })` / `focus = false, show = false` option that starts without opening.

The PR carries the Phase A handling for both caveats:
- Job-start via `nvim_buf_call(self.buf, …)`; `open_win()` moved out of `start()` into `show()`.
- PTY resize on first real `open_win` (SIGWINCH) so a windowless-started TUI paints correctly.
- Ready-detection windowless-safe (timeout fallback; don't require `self.win`).

Keep the diff faithful to sidekick's style; the normal show/focus path must be byte-for-byte
equivalent in behavior.

---

## Phase D — Simplify `ai.lua` once the API exists (this repo)

Depends on Phase C landing upstream (then bump `nvim-pack-lock.json`), **or** on a pinned fork
branch if we ever go that route. When available, replace the hack with the real API:

- **Delete** the hidden-float `open_win` monkey-patch in the `cli.win.config` callback, the
  `prewarm_term` upvalue, and the `_G.__sidekick_prewarm` flag.
- **Delete** Guard 2 (the visible-CLI re-check before `cli.hide`) and the `cli.hide` cleanup — a
  windowless `spawn()` never shows a window, so there's nothing to hide.
- **Delete** the `SidekickCliAttach` skip-promote guard from `a989656`, **and** whatever Phase B
  added (the event-driven cleanup / fallback timer) — with no pre-warm window, none of it applies.
- **Keep** Guard 1 (skip if a claude CLI already exists — now matched via
  `terminal.sessions()` → `t.tool.name == 'claude'` after `c8f7cf5`, not the filetype), the `.git`
  + `has_ui` gates in `do_prewarm`, the re-schedulable 3s one-shot timer **including its
  stale-callback identity guard** (`_G._sidekick_prewarm_timer ~= timer → return`, added
  2026-07-10 — it fixes a scheduling-level race, not a hidden-float one, so it survives this
  rework; see the startup-perf plan's post-landing section), and the
  `PersistenceLoadPre/Post` wiring — all orthogonal to windowing and still wanted. `do_prewarm()`
  collapses to roughly: has_ui/`.git`/guard-1 checks → `spawn the claude CLI`.
- **Resolves #3 and #4 for free.** With no window during pre-warm, the cleanup timing race (#3) and
  the `<leader>aa`-hides-the-hidden-float bug (#4) both vanish — there's no override to install late
  and no `is_open()`-true float to toggle. This is the payoff that makes this rework worth more than
  the ~ms it saves.
- Net: the pre-warm becomes structurally identical to `terminal.lua`'s (spawn a hidden buffer, no
  window, first user trigger opens onto it) — the asymmetry that motivated all this disappears.

### Doc sync (same change, per repo rules)
- `GUIDE.md` AI section: update the pre-warm description (no more hidden-float/monkey-patch prose;
  it now mirrors the terminal pre-warm). Drop the now-stale mechanics.
- Re-check the `Re-source safety` timer bullet still matches.

---

## Interim (now → until Phase D)

Keep the hardened monkey-patch (`a989656` + `c8f7cf5` guards in place). It works and costs zero fork
maintenance. If it re-breaks against a sidekick update before Phase C lands, patch the specific
autocmd (as we did for `wincmd L`) — or do Phase B — rather than escalating to a fork prematurely.

Two interim facts settled by the 2026-07-10 post-landing design review (details in
`plans/nvim-startup-performance.md` → "Post-landing status + design review"):

- **The pre-warm timer gained a stale-callback identity guard** in `schedule_prewarm` — a
  scheduling-level race fix (a LoadPre/LoadPost pair landing in the uv-fire → scheduled-callback
  gap let the stale callback close the re-armed timer and spawn claude right at restore-end).
  It's independent of the hidden-float hack: **Phase D keeps it** (see the Phase D keep list).
- **No shared scheduler module will absorb the timer/persistence wiring before Phase D.** A
  `startup.lua` scheduler abstraction was proposed and rejected (single restore-aware consumer;
  pre-D churn in this file). Phase D's keep/delete lists therefore remain accurate as written —
  don't expect the scheduling shell to have moved. Extraction is re-evaluated only after Phase D
  lands *and* a second restore-aware task exists.

## Fallback if upstream declines

Reassess fork vs. keep-hack **then**, with data on how often the hack breaks. A fork only earns its
maintenance cost if (a) upstream won't take it and (b) breakage is recurring. Pin the fork in
`nvim-pack-lock.json` if taken.

## Workflow

Phase A is throwaway (no dotfiles commits). Phase B is one optional interim `fix(nvim):` commit
here (superseded by D). Phase C is upstream (a PR to sidekick.nvim, not this repo). Phase D is one
`refactor(nvim):` commit here (docs included), gated on Phase C landing + lockfile bump.
`Part-of: plans/sidekick-windowless-prewarm.md` on the Phase B and Phase D commits.

## Verification

Phase A (local prototype):
1. Pre-warm via the throwaway `spawn()` → claude process running (`ps aux | grep claude`), **no**
   window/split visible, no flicker.
2. `<leader>aa` after pre-warm → CLI opens instantly and **renders at the correct width** (the PTY
   sizing check — no stuck narrow/garbled frame).
3. Cold `<leader>aa` (no pre-warm), `<leader>aa` toggle, focus, hide, close — all unchanged.

Phase B (if done):
4. Under an artificial main-loop stall right at the 3s mark (e.g. a big synchronous `require` or a
   busy-loop), the pre-warm still opens **invisibly** — the override installs regardless of timing.
5. Show-failed path (rename `claude` off `PATH`): the flag clears via the fallback timer, and a
   later real `<leader>aa` opens a normal visible CLI (no inherited hidden-float override).

Phase D (after simplification):
6. Full collision test from the startup-perf plan still passes: start nvim in a rust repo →
   `<leader>qs` → claude spawns ~3s after restore, invisibly; `<leader>aa` instant; `<C-\>` warm.
7. Re-source `ai.lua` twice → single autocmd/timer registration, no leaks.
8. `:checkhealth`, `:messages` clean; GUIDE.md greps resolve.
