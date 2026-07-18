# Plan: Ghostty follow-ups — leftover items + features not yet used

## Why Ghostty

Ghostty ([ghostty.org](https://ghostty.org/)), by Mitchell Hashimoto
(Terraform/Vagrant), aims to be **fast, feature-rich, and native** at once —
most terminals pick two: Alacritty is fast/native but minimal, iTerm2 is
feature-rich but not GPU-accelerated, Electron terminals are feature-rich but
neither fast nor native. Its core, `libghostty` (Zig), is wrapped natively per
platform — Swift/AppKit on macOS — so this Mac gets real `NSWindow` tabs,
native splits, and Metal GPU rendering.

What that buys here:
- **Speed you feel.** Metal rendering → 120Hz scrolling, sub-2ms input
  latency, ~3x iTerm2's throughput. Matters for large `git diff`/`rg`/build
  scrollback.
- **Kitty graphics protocol.** iTerm2 can't do this at all — it's the only
  reason inline-mermaid rendering (Part 1 §3) is possible here.
- **Zero-config defaults.** Most of what iTerm2 needed a settings pane for
  (text editing, split/tab shortcuts) is a sane macOS default — why the
  original migration ported almost nothing.
- **Actively shipping.** 1.2 (late 2025) added the command palette and
  quick-terminal — real features that landed after the migration plan was
  written and never got evaluated, hence Part 2.

Ghostty is now the *only* terminal in this repo — iTerm2 was uninstalled and
fully de-referenced (see `plans/README.md`).

## Context

Supersedes `plans/ghostty.md` (the iTerm2→Ghostty migration plan, now
**deleted** — fully shipped). That plan left two things undone: genuine open
items (status bar, `ApplePressAndHoldEnabled`, a parked image feature), and
zero coverage of Ghostty capabilities beyond iTerm2 parity, since porting
iTerm2 was its whole frame.

Part 1 carries that leftover work forward. Part 2 is new: features
`ghostty +show-config --default` (1.3.1, verified on this machine) exposes
that `ghostty/.config/ghostty/config` doesn't touch.

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

Verified against `ghostty +show-config --default` (1.3.1, this machine) and
cross-checked against `ghostty/.config/ghostty/config`, which sets only: font,
theme, window size/padding, cursor style, `macos-option-as-alt`,
`scrollback-limit`, `confirm-close-surface`, `quit-after-last-window-closed`,
and one keybind (`shift+enter`). Everything below is Ghostty's out-of-the-box
default — no upgrade needed, all available today.

## 2.1 Command Palette — `Cmd+Shift+P` (already bound, zero config)

Added in 1.2. Searchable list of every keybind action, including unbound
ones — 80+ entries on this build. Highest-value zero-effort item here: a
live cheat sheet for everything else in this section. Try it first.

## 2.2 Split Zoom — `Cmd+Shift+Enter` (already bound, zero config)

Temporarily maximizes the focused split without closing others
(`toggle_split_zoom`, same shortcut to undo). No conflict with the
`shift+enter=text:\n` binding — different modifier combo. Useful for the
nvim+Claude split workflow (Part 1 §3): zoom in on whichever pane needs
attention, zoom back out.

## 2.3 Quick Terminal — adopted (2026-07-18)

Global drop-down terminal, summonable from any app. iTerm2 never had this
configured (`Has Hotkey = False`), so it's new territory, not a port.
Replaces nvim's old `<C-\>` floating terminal — nvim's own terminal is now
bottom-split only, on `<C-/>` (see `nvim/.config/nvim/lua/terminal.lua`).

```ini
keybind = global:cmd+backslash=toggle_quick_terminal
quick-terminal-position = center
quick-terminal-size = 60%,60%
```

Adopted `cmd+backslash` / `center`, not this doc's originally proposed
`cmd+backquote` / top-default — matches the old `<C-\>` muscle memory, and
1Password's own `Cmd+\` (Quick Access) needed disabling anyway. `center`
positions relative to the **screen**, never the window (no anchor-window
concept — it works with zero Ghostty windows open). `size = 60%,60%` reads as
a large panel rather than a full-screen takeover. `quick-terminal-screen`,
`-animation-duration`, `-autohide` stay default.

**Gotcha:** `window-save-state = always` (§2.4) has no separate
quick-terminal scope — it also caches this window's frame, silently
overriding `quick-terminal-size`/`-position` on later edits. To resize: set
it to `never`, relaunch, summon at the new size, then `always` and relaunch
again to bake in the frame.

## 2.4 `window-save-state` — adopted (2026-07-15)

Default `default` defers to macOS's own "reopen windows" toggle. Set
explicitly to `always` so Ghostty restores window/tab/split *layout* (not
processes) on every quit — useful given the regular multi-split nvim+Claude
sessions here.

```ini
window-save-state = always
```

No per-window-type scope exists (no `quick-terminal-save-state` key) — see
§2.3's gotcha for the interaction and fix procedure.

## 2.5 Background opacity + blur — declined (2026-07-15)

`background-opacity`/`background-blur` (defaults `1`/`false`) — translucent
blur is a common macOS terminal look, but **rejected, never wanted**. Staying
opaque; no action.

## 2.6 `unfocused-split-opacity` — confirmed active (2026-07-15)

Default `0.7`. **Confirmed on-machine — inactive splits are visibly dimmed
already**, no config needed. Useful beyond looks: makes it obvious which
split is focused, the exact ambiguity behind the Part 1 §3 image blocker.

## 2.7 Custom shaders — cosmetic, low priority

`custom-shader` (GLSL, unset) runs per-frame effects — cursor trails, CRT
scanlines. Community collection:
[awesome-ghostty](https://github.com/fearlessgeekmedia/awesome-ghostty).
Not a priority, listed for completeness.

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
  toggle, no Space-switch animation, but loses per-Space window tracking.
  Situational.

## 2.9 `auto-update-channel` — already `stable`, no action

Not a gap — confirmed already on the `stable` channel (Ghostty's default).
Listed so it isn't rediscovered as an open question later.

---

## Files likely touched, if Part 2 items are adopted

| File | Change |
|---|---|
| `ghostty/.config/ghostty/config` | whichever of §2.3–2.8 get adopted |
| `README.md` → `## Ghostty` | document any new keybind/setting, same-change rule per root `CLAUDE.md` |
| `nvim/.config/nvim/lua/picker.lua` | Part 1 §3 resume, if picked back up |

## Sources (Part 2 research)

- [Ghostty — official site](https://ghostty.org/)
- [About Ghostty](https://ghostty.org/docs/about)
- [Ghostty GitHub repository](https://github.com/ghostty-org/ghostty)
- [Ghostty 1.2.0 release notes](https://ghostty.org/docs/install/release-notes/1-2-0) — command palette, quick terminal
- [Ghostty config reference](https://ghostty.org/docs/config/reference)
- [Ghostty keybind reference — `global:` prefix](https://ghostty.org/docs/config/keybind/reference)
- [awesome-ghostty — shaders/tools collection](https://github.com/fearlessgeekmedia/awesome-ghostty)
- `ghostty +show-config --default` / `ghostty +show-config` / `ghostty +list-actions` — run directly on this machine, Ghostty 1.3.1, 2026-07-15
