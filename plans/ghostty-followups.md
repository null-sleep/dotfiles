# Plan: Ghostty follow-ups — leftover items + features not yet used

**Status:** shrunk 2026-07-18 — cut the "Why Ghostty"/"Context" background,
the zero-config feature listings (§2.1/2.2/2.7 bodies), and the
files-touched/sources appendices. Open items and decision records kept;
Part 1 §3 kept in full (only surviving record of the parked image pipeline).

Supersedes `plans/ghostty.md` (the iTerm2→Ghostty migration plan, deleted —
fully shipped). Ghostty is the only terminal in this repo; iTerm2 was
uninstalled and de-referenced (see `plans/README.md`).

---

# Part 1 — Leftover items from the migration

## 1. Status bar — cwd/git resolved via Starship, CPU/mem still open

iTerm2 showed cwd, git branch, CPU, and memory. **Ghostty has no status bar.**
cwd/branch now survive via the Starship prompt (`## Prompt (Starship)` in
`README.md`) + OSC-1/2 window title (`zsh/.zshrc_config.zsh:97-130`); CPU/mem
still don't, and nothing replaces them.

Decide one of:
- **Accept the loss** — CPU/mem were a glance-at-rarely nice-to-have.
- **A separate CPU/mem indicator** — not researched. Candidates: a zsh
  `precmd` hook calling `top -l 1` (cheap, adds prompt latency), or a
  menu-bar app (`stats`/iStat-Menus-style, brew-installable).

## 2. `ApplePressAndHoldEnabled` — resolved (2026-07-15), no override needed

iTerm2 sets this `false` on its own app domain so holding Option for an accent
doesn't intercept the keystroke. Checked whether Ghostty needs the same, or
whether `macos-option-as-alt = true` already covers it.

**Verified:** `Option+e` doesn't pop the accent picker. `macos-option-as-alt`
intercepts Option before macOS's press-and-hold logic sees it, so `ESC e`
reaches zsh instead — no `M-e` binding there (unlike `M-f`/`M-b`), so `e`
self-inserts (looks like the cursor advancing, not a popup). That's the pass
condition — **no `defaults write` needed.** Left here in case a future
macOS/Ghostty update changes this.

## 3. Inline images & mermaid diagrams — PARKED, not abandoned

Real, working, on-machine-verified prototyping, parked on one UX problem —
preserved here in full so it isn't lost with `plans/ghostty.md`'s deletion.

**No new nvim plugin needed.** `snacks.nvim`'s `image` module already renders
mermaid natively (shells out to a `mmdc`-named binary, themes to the current
background — `snacks/image/init.lua:125`). It was just gated on a terminal
this repo didn't run at the time.

**Renderer decision (2026-07-15): reject `mmdc`, use the Rust `mmdr` shim.**
Official `mmdc` costs **~1 GB of disk** (`npm i -g @mermaid-js/mermaid-cli`
pulls headless Chromium via puppeteer — measured: 549 MB cache + ~403 MB
package). Chromium isn't resident, but the disk footprint was rejected. It's
also not fundamental to mermaid — just an artifact of the official CLI driving
real browser Mermaid.js. Leaner options:

| Renderer | How | Chromium | Notes |
|---|---|---|---|
| **mmdr** — chosen | native Rust | none | `brew tap 1jehuang/mmdr && brew install mmdr`; SVG+PNG, ~500x faster, 23 diagram types. Young (v0.3.1) — fidelity may not fully match mermaid-cli |
| mermaidx (Python) | embedded JS engine | none | higher fidelity, not a drop-in |
| kevalin/mermaid.nvim | chafa ASCII/ANSI | none | ASCII-art look, not crisp |
| official `mmdc` | puppeteer + browser | **~1 GB** | highest fidelity, rejected on weight |

**Integration catch:** `snacks.image` **hardcodes the mermaid command as
`mmdc`** (`snacks/image/convert.lua:120-127` — only args are configurable, not
the binary). Chosen path: a **`mmdc` shim** on `PATH` that translates snacks'
args and calls `mmdr` — keeps the whole pipeline, only swaps Chromium for a
tiny native binary.

**Already installed / committed (keep, don't undo):**
- `zsh/.local/bin/mmdc` — the shim (stowed, ahead of homebrew on `PATH`).
  Dormant while images are off.
- `brew "mmdr"` (+ tap) and `brew "imagemagick"` — both installed.
- `nvim/.config/nvim/lua/picker.lua`: `can_render_images()` gate,
  `SNACKS_GHOSTTY=1` force-detect, `image = { enabled = false, math =
  { enabled = false }, doc = { conceal = false } }`. **Resume: flip `enabled`
  to `can_render_images()`.**

**Verified working (2026-07-15):** live session had `enabled=true`,
`term=ghostty`, `placeholders=true`, doc path **inline**; diagrams render
correctly in both themes, fast (mmdr ~20ms, magick ~0ms — snacks' own
scan/transmit dominates latency, one-time and cached). `SNACKS_GHOSTTY` is
necessary: snacks' ghostty detection has no env fallback, only an async
XTVERSION probe, and `env()` memoizes the result — lose that race once and it
caches `placeholders=false` forever, dropping to `float`/hover so diagrams
flash once then vanish. Forcing `SNACKS_GHOSTTY=1` from
`GHOSTTY_RESOURCES_DIR` makes detection deterministic.

**Why it's parked, by severity:**
1. **Focused-window only — the real blocker.** Terminal-graphics images draw
   only in the current window (snacks hides them on `WinLeave`). This setup
   runs Claude Code in an nvim split beside the docs, so focusing Claude
   blanks the doc-pane diagram constantly. Inherent to the kitty graphics
   protocol under nvim splits, not a config bug.
2. **conceal flicker (mitigated, unverified).** `doc.conceal` hides the image
   when the cursor is on its source lines; with `concealcursor=""` that reads
   as flicker. Set `doc.conceal = false` — believed fixed, not confirmed on a
   clean restart.
3. **normal-mode crop vs insert-mode full height.** Image clips to source
   lines in normal mode, expands in insert mode — likely the conceal
   show/hide cycle recomputing reserved height. Probably resolves with #2.

**Testing gotcha — read before resuming.** A Claude Code session run inside
nvim gets its `nvim` calls routed by `flatten.nvim` into the already-running
instance, which never re-reads config. "Restart to test" silently reused the
stale instance during prototyping. **Test in a fresh Ghostty tab (`⌘T`) or
quit the hosting nvim entirely.**

**Resume plan:** (1) flip `image.enabled` back on; (2) in a fresh tab, confirm
`conceal=false` kills the flicker/crop in a single window; (3) decide if
focused-window-only is acceptable for the Claude-in-split workflow — if not,
stays parked (diagrams work fine single-window). Fidelity/latency are settled;
only split UX is open.

**Frontend support** (`snacks/image/terminal.lua:7-38`, kept for reference):

| Frontend | Can display | Unicode placeholders [1] |
|---|---|---|
| kitty | yes | yes |
| ghostty | yes | yes |
| wezterm | yes | no |
| zellij | no — `supported = false` | n/a |
| Neovide | no — GUI, no image protocol | n/a |

[1] Keeps images anchored correctly when scrolling/splitting.

**Prerequisite binaries — two, not one:**
- `mmdc` for mermaid — writes PNG directly, no ImageMagick needed for that path.
- `magick` (ImageMagick) for everything else — svg, pdf, rasters, LaTeX/typst
  math. Missing it is a health **ERROR**, not a warning.

**The gate, and why:** config must never try to render where a frontend can't
display it. snacks' own terminal detection is good (XTVERSION probe + tmux
fallback), but **the document path never calls it** — `doc.lua` computes
`inline = doc.inline and env().placeholders`, `float = doc.float and not
inline`, so wherever `placeholders` is nil, `float` wins and `doc.attach()`
proceeds anyway, spawning `mmdc` into a terminal that can't read the escapes.
The doc path **fails open**; the gate exists to stop that.

```lua
-- Image rendering only where the frontend can actually display one.
-- snacks' doc path fails OPEN, so ungated it'd spawn mmdc anywhere. Gate it.
--
-- Detect via terminal env vars, NOT $TERM: tmux rewrites TERM, kitty sets no
-- TERM_PROGRAM — a $TERM sniff would false-negative under tmux (which does
-- support graphics via snacks' own passthrough).
local function can_render_images()
  -- Neovide inherits TERM=xterm-ghostty from the launching shell — this check
  -- is load-bearing, not belt-and-braces.
  if vim.g.neovide then return false end
  if os.getenv('ZELLIJ') then return false end        -- drops graphics escapes
  return os.getenv('KITTY_WINDOW_ID') ~= nil          -- kitty
      or os.getenv('GHOSTTY_RESOURCES_DIR') ~= nil    -- ghostty
      or os.getenv('WEZTERM_PANE') ~= nil             -- wezterm
end

require('snacks').setup({
  picker = { ... },              -- unchanged
  image = { enabled = can_render_images() },
})
```

Notes:
- **Don't fold `executable('mmdc')` into the gate.** `image.enabled = false`
  disables the whole module (png/jpg/pdf/mp4 buffers, LaTeX/typst math too),
  not just mermaid. Let snacks degrade mermaid on its own — it health-warns.
- **tmux is deliberately allowed** — the env-var approach makes that safe.
- **Neovide gets nothing from this gate.** Mermaid there would need a
  browser-preview plugin (`brianhuster/live-preview.nvim`) — separate decision.
- **Not unlocked by any of this:** `lua/gitui.lua:26`'s neogit `kitty` graph
  style needs kitty's PUA symbol map, not the graphics protocol. Leave
  `graph_style = 'unicode'` alone.

---

# Part 2 — Ghostty features not currently used

Verified against `ghostty +show-config --default` (1.3.1, this machine),
2026-07-15. §2.x numbers are stable — cut items keep their headings as
tombstones so cross-references (root `README.md` cites §2.4/§2.8) don't
shift.

## 2.1 Command Palette — zero-config, adopted silently

`Cmd+Shift+P` (1.2+), works out of the box; body cut 2026-07-18.

## 2.2 Split Zoom — zero-config, adopted silently

`Cmd+Shift+Enter` (`toggle_split_zoom`), works out of the box; body cut
2026-07-18.

## 2.3 Quick Terminal — tried (2026-07-18), reverted

Global drop-down terminal via a `global:`-prefixed keybind
(`toggle_quick_terminal`). Tried `cmd+backslash` / `center` (replacing nvim's
`<C-\>` float) and reverted the same week — back to nvim's `<C-\>` floating
terminal + `<C-/>` bottom panel (`nvim/.config/nvim/lua/terminal.lua`).

## 2.4 `window-save-state` — adopted (2026-07-15)

Default `default` defers to macOS's own "reopen windows" toggle. Set
explicitly to `always` so Ghostty restores window/tab/split *layout* (not
processes) on every quit — useful given the regular multi-split nvim+Claude
sessions here.

```ini
window-save-state = always
```

## 2.5 Background opacity + blur — declined (2026-07-15)

`background-opacity`/`background-blur` — rejected, never wanted. Staying
opaque; no action.

## 2.6 `unfocused-split-opacity` — confirmed active (2026-07-15)

Default `0.7`, confirmed on-machine — inactive splits already dim, no config
needed.

## 2.7 Custom shaders — cosmetic completeness listing, cut

Body cut 2026-07-18; see
[awesome-ghostty](https://github.com/fearlessgeekmedia/awesome-ghostty) if
ever wanted.

## 2.8 macOS window chrome

- `macos-titlebar-style` — **adopted `tabs` (2026-07-15)**, replacing the
  `transparent` default. Tried `hidden` first, but it still drew a separate
  title-text row above the tab bar (confirmed via screenshot). `tabs` merges
  the tab bar into the titlebar row next to the traffic lights — one row.

  ```ini
  macos-titlebar-style = tabs
  ```

- `macos-non-native-fullscreen` (default `false`, **not adopted**) — in-place
  borderless fullscreen instead of macOS Spaces-based fullscreen. Faster
  toggle, but loses per-Space window tracking. Situational.

## 2.9 `auto-update-channel` — already `stable`, no action

Confirmed already on the `stable` channel (Ghostty's default); listed so it
isn't rediscovered as an open question later.
