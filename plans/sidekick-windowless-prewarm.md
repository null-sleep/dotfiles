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

### More hidden-float fragility (from the Phase 1 review + source tracing)

An adversarial review of the reschedule work (plus reading the sidekick source) surfaced two more
races that are **inherent to the hidden-float hack** — both dissolve under a windowless start (no
window during pre-warm ⇒ no `open_win` override, no `_G.__sidekick_prewarm` flag, and `is_open()`
is false):

- **Cleanup timing race.** `cli.show`'s work runs through a `vim.schedule_wrap`'d `use` callback
  (`cli/state.lua:148`); `Terminal:init()` (which installs the hidden-float override) and
  `open_win` run back-to-back inside it. The pre-warm clears `_G.__sidekick_prewarm` on a fixed
  300 ms timer — so if that scheduled callback is delayed past 300 ms by a main-loop stall (exactly
  the LSP/treesitter storm the 3 s pre-warm lands in), the override isn't installed when `open_win`
  runs, claude opens **visible**, and Guard 2 then leaves it up. Low probability (needs a ~300 ms
  freeze) but it's a *second* path to the same stuck-visible symptom the `wincmd L` bug caused.
- **`<leader>aa` during the pre-warm window.** While the hidden float is alive (`self.win` valid),
  `cli.toggle` reads `is_open()` as true and *hides* it — showing nothing
  (`cli/init.lua:100`, `cli/terminal.lua:487`). A cold `<leader>aa` before the float exists, or
  after it's hidden, is fine; the ~300 ms show→hide window is the hole.

These are **awkward to fix in the hack** (both are properties of "there is a window"), so the
Phase 1 follow-up fixed only the confidently-correctable issues in place — the lost `.git` gate on
the reschedule path and the guards matching any tool instead of claude (`c8f7cf5`) — and left these
two for this plan to eliminate structurally. They are the strongest remaining argument for Phase B.

### Decision: don't fork

Sidekick is young and fast-moving (folke). Carrying a patched method means a rebase tax on every
upstream change for a *single* method — the maintenance cost dwarfs the payoff. Prefer an upstream
PR; keep the hardened monkey-patch as the interim; fork only as a last resort (upstream declines
**and** the hack keeps breaking **and** we accumulate more sidekick patches).

---

## Phase 0 — Prototype locally to de-risk (throwaway, not committed to this repo)

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

## Phase 1 — Upstream PR to sidekick.nvim

Open an issue first sketching the approach (cite toggleterm's `spawn()` as prior art), then a PR.
Shape options (author's call, but propose):
- A public `M:spawn()` / `M:prewarm()` that starts the job windowless, **or**
- a `cli.show({ show = false })` / `focus = false, show = false` option that starts without opening.

The PR carries the Phase 0 handling for both caveats:
- Job-start via `nvim_buf_call(self.buf, …)`; `open_win()` moved out of `start()` into `show()`.
- PTY resize on first real `open_win` (SIGWINCH) so a windowless-started TUI paints correctly.
- Ready-detection windowless-safe (timeout fallback; don't require `self.win`).

Keep the diff faithful to sidekick's style; the normal show/focus path must be byte-for-byte
equivalent in behavior.

---

## Phase 2 — Simplify `ai.lua` once the API exists (this repo)

Depends on Phase 1 landing upstream (then bump `nvim-pack-lock.json`), **or** on a pinned fork
branch if we ever go that route. When available, replace the hack with the real API:

- **Delete** the hidden-float `open_win` monkey-patch in the `cli.win.config` callback, the
  `prewarm_term` upvalue, and the `_G.__sidekick_prewarm` flag.
- **Delete** Guard 2 (the visible-CLI re-check before `cli.hide`) and the `cli.hide` cleanup — a
  windowless `spawn()` never shows a window, so there's nothing to hide.
- **Delete** the `SidekickCliAttach` skip-promote guard from `a989656` — with no pre-warm window,
  there's nothing to mis-promote.
- **Keep** Guard 1 (skip if a claude CLI already exists — now matched via
  `terminal.sessions()` → `t.tool.name == 'claude'` after `c8f7cf5`, not the filetype), the `.git`
  + `has_ui` gates in `do_prewarm`, the re-schedulable 3s one-shot timer, and the
  `PersistenceLoadPre/Post` wiring — all orthogonal to windowing and still wanted. `do_prewarm()`
  collapses to roughly: has_ui/`.git`/guard-1 checks → `spawn the claude CLI`.
- **Resolves the two review residuals for free.** With no window during pre-warm, the cleanup
  timing race (#3) and the `<leader>aa`-hides-the-hidden-float bug (#4) both vanish — there's no
  override to install late and no `is_open()`-true float to toggle. This is the payoff that makes
  Phase B worth more than the ~ms it saves.
- Net: the pre-warm becomes structurally identical to `terminal.lua`'s (spawn a hidden buffer, no
  window, first user trigger opens onto it) — the asymmetry that motivated all this disappears.

### Doc sync (same change, per repo rules)
- `GUIDE.md` AI section: update the pre-warm description (no more hidden-float/monkey-patch prose;
  it now mirrors the terminal pre-warm). Drop the now-stale mechanics.
- Re-check the `Re-source safety` timer bullet still matches.

---

## Interim (now → until Phase 2)

Keep the hardened monkey-patch (`a989656` guard in place). It works and costs zero fork
maintenance. If it re-breaks against a sidekick update before Phase 1 lands, patch the specific
autocmd (as we did for `wincmd L`) rather than escalating to a fork prematurely.

## Fallback if upstream declines

Reassess fork vs. keep-hack **then**, with data on how often the hack breaks. A fork only earns its
maintenance cost if (a) upstream won't take it and (b) breakage is recurring. Pin the fork in
`nvim-pack-lock.json` if taken.

## Workflow

Phase 0 is throwaway (no dotfiles commits). Phase 1 is upstream (a PR to sidekick.nvim, not this
repo). Phase 2 is one `refactor(nvim):` commit here (docs included), gated on Phase 1 landing +
lockfile bump. `Part-of: plans/sidekick-windowless-prewarm.md` on the Phase 2 commit.

## Verification

Phase 0 (local prototype):
1. Pre-warm via the throwaway `spawn()` → claude process running (`ps aux | grep claude`), **no**
   window/split visible, no flicker.
2. `<leader>aa` after pre-warm → CLI opens instantly and **renders at the correct width** (the PTY
   sizing check — no stuck narrow/garbled frame).
3. Cold `<leader>aa` (no pre-warm), `<leader>aa` toggle, focus, hide, close — all unchanged.

Phase 2 (after simplification):
4. Full collision test from the startup-perf plan still passes: start nvim in a rust repo →
   `<leader>qs` → claude spawns ~3s after restore, invisibly; `<leader>aa` instant; `<C-\>` warm.
5. Re-source `ai.lua` twice → single autocmd/timer registration, no leaks.
6. `:checkhealth`, `:messages` clean; GUIDE.md greps resolve.
