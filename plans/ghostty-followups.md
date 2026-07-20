# Plan: Ghostty follow-ups — leftover items + features not yet used

**Status:** shrunk 2026-07-18 — cut the "Why Ghostty"/"Context" background,
the zero-config feature listings (§2.1/2.2/2.7 bodies), and the
files-touched/sources appendices. Open items and decision records kept.
Part 1 §3 (inline images/mermaid) dropped 2026-07-20 — tombstone only.

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

## 3. Inline images & mermaid diagrams — DROPPED

Prototyped and parked 2026-07-15, then dropped 2026-07-20: not wanted.
Terminal-graphics images only draw in the *focused* window, which blanks a
diagram whenever the Claude split is focused — fatal in this split-heavy
workflow. The whole pipeline is removed (snacks `image` block, the
`SNACKS_GHOSTTY` force-detect, the `mmdc`→`mmdr` shim, the mmdr tap and
imagemagick). Full record in git history; do not re-propose without a fix
for the focused-window limitation.

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
