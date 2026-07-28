# edgy.nvim — UI/UX evaluation plan

**Status:** evaluation plan — not an implementation spec
**Date:** 2026-07-27
**Plugin:** <https://github.com/folke/edgy.nvim>

Successor to the `nvim-backlog.md` → "Unified stacked edgebar" entry (itself
folded in from the deleted `unified-sidebar-panel.md`). This plan asks a
narrower question than "install edgy?": **which of the three screen edges
would actually feel better under edgy, and what hand-rolled code would it let
us delete?** Verdicts land per-edge, not all-or-nothing.

## What edgy does

Predefined layouts for the four screen edges (left/right/bottom/top). Windows
matching a view spec (filetype + optional filter fn) are captured into the
edgebar as **stacked, collapsible, titled sections** with fixed sizes;
`]w`/`[w` cycle sections, `q`/`<c-q>`/`Q` close/hide/close-all, titles render
in the winbar. Options: per-view `wo`, `pinned` placeholders, `exit_when_last`,
animations. Requirements already met here: nvim ≥ 0.10 (we run 0.12) and a
global statusline (lualine `globalstatus = true` ≙ `laststatus = 3`).

## The current landscape, per edge

**Left** — nvim-tree (`<leader>e`, width 35) and aerial (`<leader>o`,
min_width 25) with hand-rolled mutual exclusion: `buffers.lua` keeps
`special_filetypes`/`sidebar_filetypes` registries, `close_other_sidebars()`,
and per-plugin `sidebar_closers`. Works, but it's a miniature edgy that knows
exactly two plugins, and every new panel means editing three registries
(GUIDE.md → "Left-edge sidebars swap into each other").

**Bottom** — quietly fragmented into four uncoordinated occupants:
1. toggleterm bottom panel (`<C-/>`, dedicated id 100, 30% height, pre-warmed)
2. run-output split (`<leader>cR`/`<leader>co` via
   `utils.split_terminal_action`, also 30% height) — a *second* terminal
   split that can coexist with #1
3. quickfix/loclist (quicker.nvim, stock `:copen` placement)
4. the `:Cleanup` report (`botright split`)

Plus neotest's output panel (stock bottom) once it's used. No shared height,
no navigation between them, no titles — you can stack three anonymous bottom
splits today. This is the edge with the most visible UX debt.

**Right** — sidekick's Claude CLI, with two hand-rolled edgy-isms in `ai.lua`:
full-height promotion on attach (`wincmd L` via `utils.promote_to_full_height`)
and width memory across sessions on `WinClosed`. Also the edge
`neotest-workflow.md` flags as *contested*: unconfigured neotest opens its
summary right, on top of sidekick.

**Cross-edge machinery that is really layout code:**
- `autocmds.lua` QuitPre "quit when only sidebars remain" → edgy's
  `exit_when_last` is this exact feature.
- stickybuf.nvim (pin panels against buffer hijack) → edgy pins its views.
- Per-window `wo` juggling (scrolloff-by-winid in `filetree.lua`,
  `outline.lua`, `ai.lua`) → per-view `wo` tables.
- `session.lua` PersistenceSavePre closes all panels before `mksession` →
  would still be needed, but the close-everything call could become one edgy
  API call instead of per-plugin closers.

## What would visibly improve

- **Bottom edge coherence** — one edgebar where terminal / run output /
  quickfix / neotest output are titled sections at a shared height; `]w`/`[w`
  hop between them instead of `<C-w>j` roulette across anonymous splits. This
  is the single biggest visible win.
- **Panel labeling for free** — winbar titles on every panel. Partially
  answers the backlog's "buffer-name display for inactive windows" wish, and
  costs nothing since the winbar is unused (dropbar removed 2026-07-03) —
  titles appear only in panels, so this doesn't re-litigate breadcrumbs.
- **Left edge becomes declarative** — tree + outline as sections. Opens a
  *new* option the manual coordinator can't do: both visible **stacked** on
  one edge, not just either/or. Whether stacking beats swapping is itself an
  evaluation question (swap preserves full-height panels; stacking preserves
  context).
- **The right-edge contest gets an owner** — neotest summary and sidekick both
  declared as right views with sizes, instead of whoever opened last winning.
  This is exactly the "generalize the coordinator to per-edge groups" branch
  of `neotest-workflow.md`'s open decision — edgy *is* that generalization.
- **dap-ui and neotest for free** — both run stock `setup()` today; edgy's
  README has canonical recipes for both, so their panels join the system with
  config rather than new code.

## The deletion payoff

The strongest argument isn't new features — it's that a successful adoption
retires bespoke code that must otherwise be maintained per-plugin:

| Hand-rolled today | edgy equivalent |
|---|---|
| `buffers.lua` registries + `close_other_sidebars` + `sidebar_closers` | view specs per edge |
| QuitPre sidebars-only-quit (`autocmds.lua`) | `exit_when_last` |
| stickybuf.nvim (whole plugin) | view pinning |
| `promote_to_full_height` + sidekick width memory (`ai.lua`, `utils.lua`) | right edgebar with fixed size |
| scrolloff-by-winid dances (3 files) | per-view `wo` |

If a trial ends with edgy installed *alongside* all of this, it failed — the
kill criterion below.

## Out of scope — unaffected surfaces

Neogit and diffview (own tabpages, deliberately outside the layout), all
floats (toggleterm float pool, goto-preview, snacks picker/scratch, which-key,
grug-far's split could join an edge but `transient=true` works fine), and the
satellite/statusline chrome. Trouble stays rejected; edgy doesn't change that
calculus.

## Risks & conflicts (ranked)

1. **nvim-tree fights for its window.** The known caveat: nvim-tree manages
   its own width and lifecycle, and edgy is documented against neo-tree.
   Either relax nvim-tree's self-management or switch explorers — and a
   neo-tree switch reopens `telescope-vs-snacks-picker.md` §6's explicit
   keep-nvim-tree verdict. This is the make-or-break for the left edge.
2. **Sidekick already works.** The right edge's hand-rolled promotion + width
   memory is shipped, tested, and session-aware. Edgy capturing
   `sidekick_terminal` by ft is plausible but undocumented upstream; sidekick
   deepcopy-snapshots its win config per session. Highest chance of
   regression for the least visible gain — do this edge last or never.
3. **Filetype is edgy's routing key, and ours are muddy.** The run-output
   buffer has no filetype (needs a marker ft before it can dock — cheap);
   toggleterm uses ft `toggleterm` for floats *and* the bottom panel, so the
   bottom view needs a filter fn on direction/id or the float pool gets
   yanked into the edgebar.
4. **Fixed sizes vs. resize muscle memory.** `<A-hjkl>` resize maps and
   sidekick's width memory fight winfix{width,height}. Also edgy's default
   in-panel `]w`/`[w` collide with the backlog's planned warning-severity
   diagnostic jumps (buffer-local vs global — livable, worth deciding
   deliberately).
5. **Session restore.** `session.lua` already closes synthetic panels before
   `mksession`; edgy pinned views add a second opinion about what reopens.
   Must test restore early in any trial.
6. **Run-output semantics.** GUIDE.md documents that a dismissed finished
   run's terminal buffer is wiped on window close; edgy's hide-vs-close
   distinction (`<c-q>`) might actually *improve* this (hide keeps the
   buffer) — test, don't assume.
7. **Cosmetics.** Known flicker on reposition; wants `splitkeep = "screen"` —
   already independently queued in nvim-backlog.md's Options list, so do that
   first regardless. Satellite needs the panel fts in `excluded_filetypes`.

## Staged evaluation path

Order by payoff-to-risk, with a verdict gate after each stage:

- **Stage 0 (prep, no edgy):** land `splitkeep = "screen"`; give the
  run-output buffer a marker filetype. Both improve life even if edgy is
  rejected.
- **Stage A — bottom edge.** Dock toggleterm panel (filtered), run output,
  quickfix, neotest output panel. No explorer risk, no sidekick risk, and
  it's the fragmented edge. *Success:* one coherent titled bottom bar,
  `]w`/`[w` useful daily, quickfix ergonomics (quicker.nvim editing)
  unharmed. *Kill:* flicker/jank in the terminal, or the float pool gets
  captured, or `:copen`-from-`:grep` misroutes.
- **Stage B — left edge.** Tree + outline as sections; decide stacked vs
  swap. Gate: only if nvim-tree behaves without switching to neo-tree —
  changing explorers to serve a layout plugin is the tail wagging the dog
  (that verdict can be reopened, but on explorer merits, not edgy's).
  *Success:* `buffers.lua`'s coordinator and stickybuf become deletable.
- **Stage C — right edge (optional).** Sidekick + neotest summary. Only if
  Stages A/B earned trust; the incumbent code works.

Each stage is independently revertible (edgy views are config entries), and a
partial adoption — e.g. bottom-only — is a legitimate end state.

## Open decisions

1. nvim-tree vs neo-tree (Stage B gate; interacts with
   `telescope-vs-snacks-picker.md` §6).
2. Left edge: stacked sections vs today's swap-in-place exclusivity.
3. Does sidekick's edge join edgy at all, or stay hand-rolled?
4. Keep `<A-hjkl>` free resizing (and edgy's size discipline loose) or accept
   fixed sizes?
5. Animations on or off (off is the safe default with a pre-warmed terminal).

## Verdict shape

Adopt per-edge. Expected outcome from the research so far: **bottom = likely
yes** (real fragmentation, no incumbent), **left = maybe** (works today; the
win is deleting the coordinator, gated on nvim-tree cooperation), **right =
default no** (shipped hand-rolled code, undocumented integration). If Stage A
fails, edgy is rejected outright and the bottom-edge fragmentation goes back
to the backlog as its own problem.
