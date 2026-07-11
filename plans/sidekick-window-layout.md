# Sidekick CLI window: split vs. float overlay

## Context

Opening the sidekick CLI (`<leader>aa`) currently splits the editor and shrinks
the working area. With two documents open side-by-side, the CLI opens as a third
window at the same level, so Neovim reflows everything and squishes the right
document down to an unreadable width. Since the CLI pane isn't being actively
read most of the time, the desired behavior is for it to open **on top of** the
existing code buffers (a floating overlay) rather than stealing horizontal space.

Goal of this doc: capture the research so we can **try both the existing split
and a float overlay** and decide which to keep. **No implementation yet** — this
is reference material.

> **Related wishlist item** (folded in from the old `TODO.md` "New List" when
> the plans were consolidated): *"an easy way to have sidekick panels go from
> being a pane on the right side to opening as a floating window on the right
> side — still respecting the panel size."* That's the runtime split↔float
> toggle this doc's "try both" recommendation points at; if a toggle is built
> rather than a one-or-the-other choice, it should preserve the remembered
> width (see the multi-session work's width-persistence handling).

---

## Why the split shrinks the workspace (root cause)

The CLI is configured as a right-side vertical split:

- `nvim/.config/nvim/lua/ai.lua:19` → `layout = 'right'`
- Fixed width 80 (plugin default `split.width = 80`), then promoted to full
  editor height via `wincmd L` on every attach (`ai.lua:63-73`,
  `utils.promote_to_full_height` at `utils.lua:23-27`).

A split is a real window living at the same level as your code windows, so
opening it forces Neovim to reflow the layout and give it 80 columns — those
columns come out of your existing windows. That's the squish.

## How sidekick decides the layout (three layers)

1. **User config** — `ai.lua:13-49`. `cli.win.layout = 'right'`. The comment on
   line 19 already notes: *"switch to 'float' if preferred."*
2. **Post-open promotion** — `ai.lua:63-73`. On `SidekickCliAttach` it reads
   `require('sidekick.config').cli.win.layout`; for `left`/`right` it runs
   `wincmd L`/`H` to make the split full-height at the screen edge. **Already
   no-ops for `float`/`top`/`bottom`** (side becomes nil → early return).
3. **Plugin defaults + geometry** — `~/.local/share/nvim/.../sidekick/config.lua`
   and `.../cli/terminal.lua`:
   - `config.lua:44` → `layout = "right"  ---@type "float"|"left"|"bottom"|"top"|"right"`
   - `config.lua:47-50` → `float = { width = 0.9, height = 0.9 }`
   - `config.lua:53-56` → `split = { width = 80, height = 20 }`
   - `terminal.lua:350-388` `M:open_win()` — the branch that turns `layout`
     into an actual `nvim_open_win` call. `float` → `relative='editor'`,
     centered (row/col 0.5), 90%×90%, min 80×10, titled `" Sidekick "`. Every
     non-float value → a `split` (vertical side split for left/right, horizontal
     for top/bottom).

**Key implementation caveat for "try both":** `terminal.lua:105` does
`self.opts = vim.deepcopy(Config.cli.win)`. Each CLI session **snapshots** the
layout config at creation time. This config creates the `claude` terminal at
startup via the pre-warm flow (`ai.lua:117-147`), so it persists across toggles.
Mutating the global `require('sidekick.config').cli.win.layout` alone will **not**
re-lay-out that already-created session. A working runtime toggle must mutate the
**live terminal instance's** `opts.layout` (via
`require('sidekick.cli.terminal').get(id)`) and re-show it.

---

## Float behavior, day to day (what to expect if we switch)

- **Geometry (default):** centered overlay, 90%×90% of the editor, titled
  `" Sidekick "`, `style = 'minimal'`. A ~5% margin of code peeks around the
  edges. **We don't want centered — see next section for the right-anchored
  config that keeps it where the split sits today.**
- **Doesn't disturb your layout:** a float draws on top; your two-document split
  underneath is untouched. Hiding the float (toggle off) returns you to exactly
  the layout you had — **no reflow, no squish** either on open or on close. This
  is the main win over the split.
- **Covers your code while open:** you can no longer read code and the CLI
  side-by-side. Fine given you don't read that pane much; worth naming explicitly.
- **Focus / dismiss unchanged:** `<leader>aa` toggle, `<C-.>` / `<leader>ai`
  focus, and in-window `q` / `<C-q>` hide all still work.
- **Position is configurable — right-anchored is what we want.** `open_win`
  computes placement from `cli.win.float.row`/`col` (`terminal.lua:367-370`):
  `col = floor((columns - width) * col)` and `row = floor((lines - height) * row)`
  when each is `<= 1`. The base uses `row = col = 0.5` → centered. To make the
  float sit **exactly where today's right split is** (right edge, full height,
  width 80):

  ```lua
  cli.win.float = {
    width  = 80,    -- absolute cells (>1), matches split.width today
    height = 0.95,  -- ~full editor height (fraction of lines; min is 10)
    row    = 0,     -- top
    col    = 1,     -- col=1 -> floor((columns-80)*1) = columns-80 -> flush right
  }
  ```

  So `col = 1` is the whole trick: it pushes the leftover horizontal space
  entirely to the left, pinning the window to the right edge. `row = 0` pins it
  to the top; `height = 0.95` makes it near-full-height like the promoted split.
- **Optional border:** the split has a natural window separator; a `minimal`
  float has none, so it can blend into the code underneath. Adding
  `border = 'left'` (or `'rounded'`) to `cli.win.float` gives a visible edge.
  A border consumes 1-2 interior cells, so nudge `width`/`col` if it matters.
- **Window-nav keys go inert:** `<C-h/j/k/l>` (set in `ai.lua:96-99` and
  sidekick's own `nav_*`) do nothing inside a float — sidekick disables
  directional window-nav for floats because there's no adjacent window to move
  to. `jj` (→ normal mode), `<C-\>` (toggleterm float), `<C-u>/<C-d>` scroll
  still work.
- **Pre-warm still fine:** the startup pre-warm (`ai.lua:30-45`, `117-147`)
  already uses its own hidden float regardless of layout, so it's compatible
  either way.

## Alternatives to a full-screen float (if the overlay feels too big/small)

All are one-value tweaks, listed for completeness:

- **Smaller/larger float:** set `cli.win.float = { width = 0.7, height = 0.85 }`
  (fractions of the editor) — e.g. a narrower right-leaning panel that still
  overlays. Values ≤ 1 are treated as fractions; > 1 as absolute cells
  (`terminal.lua:362-366`).
- **Narrower split (keep split, hurt less):** drop `split.width` from 80 to,
  say, 60 so your documents keep more room.
- **Bottom split instead of right:** `layout = 'bottom'` puts the CLI under your
  code as a horizontal split — shrinks height, not the side-by-side width, so
  two vertically-split documents stay full width. (Promotion autocmd no-ops for
  bottom, so no `wincmd L` needed.)
- **Auto split width:** `split.width = 0` lets Neovim pick a default share
  instead of a fixed 80.

---

## The two approaches (expanded)

### Option A — Always float (simplest)

Change `ai.lua:19` from `layout = 'right'` to `layout = 'float'` **and** add the
right-anchored `cli.win.float = { width = 80, height = 0.95, row = 0, col = 1 }`
block (above) so it opens on the right, not centered. The promotion autocmd
already no-ops for float; pre-warm already float-compatible. Downside: no more
side-by-side; you can't A/B against the split without editing config again.

### Option B — Keep both, toggle at runtime (what "try both" wants)

Keep `layout = 'right'` as the default, set `cli.win.float` to the right-anchored
block above (so when we do flip to float it lands on the right, not centered),
and add a small helper + keymap to flip the **current** session between split and
float on demand, so we can compare them live before committing.

Sketch (for when we implement — not now):

- New keymap, e.g. `<leader>aF` = "toggle sidekick float/split".
- Handler:
  1. Read current layout from `require('sidekick.config').cli.win.layout`.
  2. Compute the other value (`right` ⇄ `float`).
  3. Set **both** `require('sidekick.config').cli.win.layout = new` (so the
     promotion autocmd sees the right `side` and future sessions inherit it)
     **and** the live terminal's `opts.layout` — get it via
     `require('sidekick.cli.terminal').get(id)` (id from `SidekickCliAttach` /
     the session), because of the `deepcopy` snapshot at `terminal.lua:105`.
  4. Hide then show the CLI (`cli.hide` + `cli.show`, which leaves the job
     alive) so `open_win` re-runs and picks up the new layout.
- Because promotion is keyed off the global config value, keeping the two in
  sync avoids `wincmd L` running against a float window.

This is a genuinely small amount of code but it is code (not a config flag),
precisely because each session snapshots its layout at creation.

---

## Recommendation

Since the ask is explicitly to **try both**, go with **Option B**: leave the
right split as the default and add a runtime toggle keymap, so split vs. float
is a keystroke away and we can decide after living with each. If after trying it
the float clearly wins, collapse to **Option A** (set the default to `float`)
and optionally drop the toggle.

## Files involved (for the eventual change)

- `nvim/.config/nvim/lua/ai.lua` — `cli.win.layout` (default), the new
  `cli.win.float = { width = 80, height = 0.95, row = 0, col = 1 }` block for the
  right-anchored overlay, and the promotion autocmd (`:63-73`) which already
  handles float correctly.
- `nvim/.config/nvim/lua/keymaps.lua:206-251` — where the outside-the-window
  sidekick keymaps live; the new `<leader>aF` toggle would go here.
- Reference only (installed plugin, do not edit):
  `~/.local/share/nvim/site/pack/core/opt/sidekick.nvim/lua/sidekick/config.lua`
  and `.../cli/terminal.lua` (`open_win` at `:350-388`, `deepcopy` at `:105`).

## Verification (when implemented)

1. Open two files in a vertical split (`:vsp`), confirm both are readable.
2. `<leader>aa` with default → CLI opens as the right split (documents squish) —
   baseline still works.
3. Trigger the float toggle → CLI reopens as a right-anchored overlay sitting
   where the split used to be (right edge, full height, width 80); the two
   documents underneath keep their widths.
4. Hide (`<leader>aa` / `q`) → confirm the split returns unchanged (no reflow).
5. Toggle back to split → confirm `wincmd L` full-height promotion still applies
   and float-only inertness of `<C-h/j/k/l>` is gone again.
6. Restart nvim → confirm pre-warm still boots claude without a visible flicker.

## Status

Research only — no config changes have been made yet. Next step, when ready:
implement Option B (runtime split/float toggle) in `ai.lua` and `keymaps.lua`,
try both for a while, then decide whether to keep the toggle or collapse to a
single default per the recommendation above.
