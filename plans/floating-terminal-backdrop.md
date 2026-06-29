# Floating terminal backdrop / dim / outline

**Status:** Explored and working, then **reverted** (parked for later). This file
preserves the findings so it can be re-applied cleanly.

## Goal

With a light colorscheme, the toggleterm float (`<C-\>`) and the editor behind it
have near-identical backgrounds, so the float doesn't visually separate from the
page (only a faint border distinguishes them). We wanted the float to "pop" —
dim/recede the rest of the screen while the float is open, like VS Code's command
palette or snacks/zen backdrops.

## What we learned (the important part)

### snacks.nvim is the wrong tool
- `snacks.dim` dims inactive **code scopes within a buffer**, not the area behind
  floats, and it explicitly excludes terminal buffers. Not applicable.
- `snacks.zen` has the right *concept* (a `transparent + blend` backdrop) but it's
  wired to zen/distraction-free mode, not toggleterm floats. No clean public API to
  reuse just the backdrop.
- Conclusion: roll our own backdrop. ~30 lines, no new dependency.

### The backdrop approach (worked)
A full-screen scratch float at **zindex 49** (between editor at 0 and the toggleterm
float at 50), `style='minimal'`, `focusable=false`, with:
- `winhighlight = 'Normal:ToggleTermBackdrop'` where `ToggleTermBackdrop` bg = `#000000`
- `winblend = 70` → semi-transparent, so the editor shows through darkened.

Lifecycle subtlety: **teardown must use a `WinClosed` autocmd**, not toggleterm's
`on_close`. `on_close` fires only on terminal *exit*; hiding the float with `<C-\>`
does NOT fire it, so the backdrop would linger. `WinClosed` fires on hide *and*
exit. Keyed by the float's window id (which is all `WinClosed` gives you). Closing
the backdrop re-fires `WinClosed` for the backdrop window → guarded by nil lookup,
no loop.

Created in toggleterm's `on_open`, guarded on `term.direction == 'float'` so the
horizontal bottom panel and sidekick never get a backdrop.

### Neovide-specific: floating blur halo
Neovide's default `neovide_floating_blur_amount_x/y = 2.0` blurs whatever is behind
a **transparent** float. Our backdrop is a full-screen transparent float, so Neovide
blurred the editor text behind it → a "white halo / glow" around every glyph that
looked like blur smear. Fix: `vim.g.neovide_floating_blur_amount_x/y = 0.0` in
`neovide.lua`. (winblend changes were invisible until this was off, because the blur
dominated the perception.) This is terminal-independent — the halo was NOT present
in iTerm2 (terminals have no AA/blur).

### The "white ring around the border line" (the hard one)
Symptom: a bright/white ring around the float's border line, visible against the dim
backdrop, in **both** Neovide and iTerm2 (so not a Neovide AA artifact — it's
cell-level).

Root cause: **floating windows in Neovim are opaque.** A float's border cells have a
background, and `FloatBorder` inherits the float's light `Normal` background. The
box-drawing glyph is thin, so the light cell background shows around it = the "white
border around the black line". Against the dim backdrop, that light cell pops as a
ring.

Dead ends:
- Setting `FloatBorder bg = NONE` does **not** show the dim backdrop through it —
  opaque float falls back to the default (light) `Normal` bg. Still a ring.
- Can't put `winblend` on the float itself to make the border transparent — that
  would make the **terminal text** transparent too.

Why a dark-content float (e.g. a `git diff` view) looked clean while a light shell
prompt didn't: the ring is only *visible* when the float's edge cells are lighter
than the dim surroundings. Dark content hides it; light content (the user's shell /
Claude, which render on a light bg) exposes it.

### The fix that worked: match the border bg to the dim color
Instead of transparent, paint the border background the **exact color the backdrop
dims the editor to**. Black at `winblend = B` over `Normal` works out to `B%` of
`Normal`'s bg per channel (winblend=70 → `0.70 * Normal_bg`). So:
- Compute `dim = 0.70 * Normal.bg` (per channel).
- `ToggleTermBorder = { fg = FloatBorder.fg, bg = dim }`.
- Apply scoped to the float via `winhighlight = 'Normal:NormalFloat,FloatBorder:ToggleTermBorder'`,
  set **deferred** (`vim.schedule`) in `on_open` so toggleterm doesn't clobber it.
- `border = 'rounded'`, re-sync the highlight on `ColorScheme`.
- Factor the blend into a shared `BACKDROP_BLEND` constant so the backdrop's
  `winblend` and the border-bg math stay in sync.

Result: a clean thin outline (like the sidekick split's `WinSeparator`), no ring.

**Known imperfection / next step:** the border bg is computed from `Normal`, so where
the float's edge sits over a region with a *different* bg (e.g. the NvimTree panel),
it won't blend perfectly. Options if that bugs us: compute per-edge, or switch to a
dedicated **frame window** (a winblend'd bordered window sized to the float, at
zindex 49) whose border background is genuinely transparent/dim like the backdrop —
but a single `winblend` blends fg too, making the line faint, so it needs tuning.

## Final working config (before revert) — to re-apply

In `nvim/.config/nvim/lua/terminal.lua`, before `toggleterm.setup`:
- `ToggleTermBackdrop` hl (bg `#000000`), `BACKDROP_BLEND = 70`
- `sync_border_hl()` computing `ToggleTermBorder` (dim bg + FloatBorder fg) + `ColorScheme` autocmd
- `backdrops` table, `open_backdrop` / `close_backdrop`, `WinClosed` teardown autocmd

In `toggleterm.setup`:
- `float_opts.border = 'rounded'`
- `on_open`: `open_backdrop(term.window)` + deferred `winhighlight` border override (float direction only)

In `nvim/.config/nvim/lua/neovide.lua`:
- `vim.g.neovide_floating_blur_amount_x/y = 0.0`

## Why reverted
Parked to keep the session's other terminal fixes clean and shippable. The dimming
worked but the outline still has the NvimTree-edge imperfection above, and it's a
visual-polish feature worth revisiting deliberately rather than rushing.

## Tuning knobs (when re-applied)
- `BACKDROP_BLEND` (terminal.lua): lower = darker dim, higher = subtler. Drives both
  the backdrop winblend and the border-bg math.
- `ToggleTermBackdrop` bg: the dim color (default pure black).
- `neovide_floating_blur_amount_x/y`: 0 = crisp, 2 = frosted glass.
