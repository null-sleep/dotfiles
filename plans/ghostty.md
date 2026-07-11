# Plan: Add a `ghostty` stow package

## Context

The repo runs **iTerm2** (primary) + **nvim** on macOS, with a partial **kitty**
package already present. This adds **Ghostty** — a native-macOS, GPU-accelerated
terminal — as a stow package **alongside** kitty and iTerm2 (nothing removed),
mirroring the existing kitty pattern. Ghostty fits this repo better than either
existing terminal: it needs **zero binary import/export** (unlike iTerm2's
tracked `.itermexport` blob) and **no manual theme-picker step** (unlike kitty's
`kitten themes`) — a single plain-text config does it all.

Decisions already made:
- **Theming:** native macOS-following dual theme via Ghostty's built-in themes
  (Catppuccin Latte light / Dracula dark), so it swaps with macOS appearance on
  its own — exactly like the iTerm2 dual-color profile. The `zsh/.local/bin/theme`
  script is **not touched**.
- **Config scope:** ship **parity-only** by default; the Ghostty-only niceties
  (§5) are a menu to enable individually — none on unless chosen.

### ⚠️ Verify before building (two real risks flagged in review)

- **Theme name casing.** Ghostty **1.2.0** switched built-in theme names to
  **Title Case** (`Catppuccin Latte`, `Dracula`) — *not* the kebab-case
  `catppuccin-latte`/`dracula` slugs the `theme` script uses for nvim/Claude,
  which do not transfer to Ghostty's namespace. Confirm exact names with
  `ghostty +list-themes` and write those exact strings.
- **Dracula availability.** Catppuccin flavors are definitively bundled. Ghostty
  also bundles the `iterm2-color-schemes` set, which contains a `Dracula` scheme,
  so it is *likely* present — but **not guaranteed**. If `ghostty +list-themes`
  does not list Dracula, vendor it as a theme file (fallback in §1).

## Key wins (why Ghostty is worth it for this setup)

1. **Slots into the theme switcher for free.** One line
   (`theme = light:Catppuccin Latte,dark:Dracula`) makes Ghostty follow macOS
   light/dark natively — same behavior as the iTerm2 dual-color profile, and it
   matches the `catppuccin-latte`/`dracula` pair the `theme` script already pins
   (README theme table). No script changes, no daemon, no escape codes — better
   than kitty, which needs a manual `kitten themes` run and ignores macOS
   appearance.
2. **Native splits with iTerm2 muscle memory.** Ghostty macOS defaults are
   `Cmd+D` = split right, `Cmd+Shift+D` = split down, `Cmd+[`/`Cmd+]` = focus
   previous/next split — the **same keys as the iTerm2 panes** (README §iTerm2 →
   Panes). Kitty has *no* `Cmd+D` split. iTerm2-style splitting out of the box.
3. **Plain-text, stow-managed, one file.** Config at `~/.config/ghostty/config`
   — a single stowable, git-diffable text file, unlike iTerm2's binary export.
4. **Faster than iTerm2 on TUIs, native on macOS.** GPU-accelerated (Metal) like
   kitty/Alacritty, but a real Cocoa app — native tabs, window management, macOS
   integration that Alacritty/kitty lack.
5. **nvim renders correctly with no special config.** Truecolor + undercurl are
   on by default. The nvim config sets no hard terminal requirement (no
   `termguicolors`, and it deliberately avoids the kitty graphics protocol —
   `lua/gitui.lua:26`); the only prerequisite is a Nerd Font, already installed
   (Hack Nerd Font).
6. **Zero-cost coexistence.** kitty and iTerm2 stay exactly as they are; purely
   additive.

## 1. New files (the stow package)

Mirror the kitty layout (`kitty/.config/kitty/kitty.conf` →
`~/.config/kitty/kitty.conf`):

```
ghostty/.config/ghostty/config      →  ~/.config/ghostty/config   (via `stow ghostty`)
```

`.stowrc` already targets `~`, so `stow ghostty` just works — no stow changes.

### `ghostty/.config/ghostty/config` (parity build)

Ported 1:1 from `kitty/.config/kitty/kitty.conf`, in Ghostty's `key = value`
syntax:

```ini
# Font (matches iTerm2 / kitty: Hack Nerd Font Mono, size 15)
font-family = Hack Nerd Font Mono
font-size = 15

# Window (matches iTerm2 / kitty: 125x25 in cells)
window-width = 125
window-height = 25
window-padding-x = 4
window-padding-y = 4

# Cursor (matches iTerm2 / kitty: bar cursor)
cursor-style = bar

# macOS — Option-as-Meta so nvim <M-...> mappings work (iTerm2 "Left Option: Esc+")
macos-option-as-alt = true
# Cmd+D / Cmd+Shift+D splits and Cmd+[ / Cmd+] focus are Ghostty defaults —
# they already match the iTerm2 pane bindings, so no keybinds here.
# Shell integration is auto-detected (no setting needed).

# Theme — follows macOS appearance natively (like the iTerm2 dual profile).
# Title Case names as of 1.2.0; confirm with `ghostty +list-themes`.
theme = light:Catppuccin Latte,dark:Dracula
```

Notes:
- **Verify theme names** with `ghostty +list-themes` before committing (Title
  Case, per the risk callout above).
- **Dracula fallback:** if the built-in is missing, vendor it — this mirrors
  kitty's `current-theme.conf` convention and stays fully in-repo:
  ```
  ghostty/.config/ghostty/themes/dracula     # palette file, checked into the repo
  ```
  Ghostty auto-discovers files in `~/.config/ghostty/themes/`; reference it by
  name. Only add this file if the built-in is absent.
- `macos-option-as-alt = true` uses `true`, not kitty's `yes`.

## 2. `CLAUDE.md` (repo root) — stow package list

Add `ghostty` to the stow-packages sentence (currently "nvim, zsh, kitty, macos,
rcmd, zellij, claude, yknotify"). One-word edit; keeps the canonical list right.

## 3. `Brewfile` — commented optional cask

Add next to the other optional-terminal casks, same commented style:

```ruby
# cask "ghostty"       # GPU-accelerated native terminal; config in ghostty/ (then `stow ghostty`)
```

## 4. `README.md` edits (required in the same change per CLAUDE.md)

Following the kitty precedent:

- **Contents TOC** — add to the *Terminals & multiplexing* line:
  `[iTerm2](#iterm2) · [Kitty](#kitty) · [Ghostty](#ghostty) · [Zellij](#zellij)`.
  Plain-word heading → **no explicit `<a id>` anchor needed**.
- **New `## Ghostty` Part 2 section** — right after `## Kitty`, before
  `## Zellij` (grouping the two GPU terminals). Model on `## Kitty`: one-line
  intro, `brew install --cask ghostty` + `stow ghostty` block, a note that
  font/window/cursor match the iTerm2 profile, the native-theme line, a short
  **Keymaps** table (Cmd+D / Cmd+Shift+D splits, Cmd+[ /Cmd+] focus, Cmd+T,
  Cmd+1–9) noting these match iTerm2, and a `ghostty +list-themes` /
  `ghostty +show-config` reference line (the analog of kitty's `kitten themes`).
- **Setup** — add under the "Optional terminals" block:
  `stow ghostty                 # needs the ghostty cask`.
- **Quick start step 6** — extend the parenthetical to
  ``(add `kitty`/`zellij`/`ghostty` only if you enabled those optional casks)``.
- **Fonts** — extend the "terminals (iTerm2, kitty)" / "used by iTerm2, kitty,
  nvim, Neovide" mentions to include ghostty (same Hack Nerd Font Mono 15). In
  place, no new heading.

## 5. Ghostty-only niceties — a menu to decide individually

Not in the parity build; each is one or two lines, added as a commented,
labeled block in the config so it can be toggled without hunting docs:

- **Drop-down "quick terminal"** — global hotkey summons a Ghostty panel over
  any app (like iTerm2's hotkey window):
  `keybind = global:cmd+backquote=toggle_quick_terminal` (key token is
  `backquote`, not `grave_accent`). Grants macOS Accessibility permission on
  first use.
- **Background opacity + blur** — `background-opacity = 0.96` +
  `background-blur = 20`. Pure aesthetics; off by default (kitty/iTerm2 are
  opaque).
- **Ligatures off (explicit)** — `font-feature = -calt,-liga,-dlig`. A no-op
  with Hack, but documents intent if the font is ever swapped.
- **Cursor / mouse niceties** — `cursor-style-blink = false`,
  `mouse-hide-while-typing = true`.
- **Window save/restore** — `window-save-state = always` (reopen where you left
  off) and/or `macos-titlebar-style = tabs` (compact native tabs). Caveat:
  `window-save-state = always` restores the previous window *size*, overriding
  `window-width`/`window-height` on later launches; combined with
  `macos-titlebar-style = tabs` it has reported quirks. Enable deliberately.
- **Larger scrollback** — `scrollback-limit` (bytes) beyond the default.

## Files touched (summary)

| File | Change |
|---|---|
| `ghostty/.config/ghostty/config` | **new** — parity config (+ any §5 opt-ins) |
| `CLAUDE.md` (root) | add `ghostty` to stow-package list |
| `Brewfile` | commented `# cask "ghostty"` |
| `README.md` | Contents TOC, new `## Ghostty` section, Setup, Quick start, Fonts |

No changes to `.stowrc`, the `theme` script, kitty, or iTerm2.

## Verification

1. **Install & stow** — `brew install --cask ghostty`; `stow ghostty`;
   `ls -l ~/.config/ghostty/config` is a symlink into the repo.
2. **Config is valid & themes resolve** — run `ghostty +list-themes` first,
   confirm exact names/casing for Catppuccin Latte and Dracula, and write those
   into the `theme` line (vendor a Dracula theme file if absent — see §1). Then
   `ghostty +show-config` prints the merged config with no parse errors and the
   resolved theme.
3. **Launch Ghostty** — Hack Nerd Font Mono 15, ~125×25 window, bar cursor;
   `Cmd+D`/`Cmd+Shift+D` split and `Cmd+[`/`Cmd+]` move focus (iTerm2 parity);
   toggle macOS Appearance (or `theme light`/`theme dark`) and Ghostty recolors
   between Catppuccin Latte and Dracula on its own, all windows, no restart;
   open `nvim` — truecolor + LSP undercurls render, Nerd Font glyphs (not tofu),
   `Option+1` in insert mode behaves as `<M-1>` not `¡`.
4. **Docs sanity** — README `## Ghostty` renders in `render-markdown`, the
   `#ghostty` TOC link resolves, and
   `grep -n ghostty README.md CLAUDE.md Brewfile` shows all expected spots.
