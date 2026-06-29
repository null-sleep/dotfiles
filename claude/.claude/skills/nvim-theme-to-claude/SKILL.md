---
name: nvim-theme-to-claude
description: Generate a Claude Code CLI custom theme (~/.claude/themes/<slug>.json) that matches an installed Neovim colorscheme. Use when the user wants a Claude Code theme that looks like one of their nvim themes (e.g. "make a Claude theme matching my tokyonight nvim theme", "port catppuccin-macchiato to Claude Code", "match the CLI to my editor"). Produces the JSON theme file, stows it for cross-machine sync, and activates it.
---

# nvim theme → Claude Code theme

Port an installed Neovim colorscheme into a Claude Code CLI custom theme. The
output is a JSON file whose palette and diff colors match the editor, kept in
this dotfiles repo so it syncs across machines.

This repo's setup (see `README.md` → "Claude Code"):
- Theme files live in `claude/.claude/themes/<slug>.json` and are symlinked to
  `~/.claude/themes/` via `stow claude`.
- `~/.claude/themes/` is a folded symlink into the repo, so a new file there is
  tracked automatically.
- Activation (`"theme": "custom:<slug>"` in `~/.claude/settings.json`) is a
  per-machine edit — `claude/setup-theme.sh` is the precedent for injecting it.

Requires Claude Code v2.1.118+. Reference:
https://code.claude.com/docs/en/terminal-config (the "Create a custom theme"
section + "Color token reference").

## Procedure

### 1. Find the nvim palette

Locate the colorscheme's raw palette. For an `opt`-installed plugin it's under
`~/.local/share/nvim/site/pack/*/opt/<plugin>/...`. Examples:

- **catppuccin**: `.../catppuccin/lua/catppuccin/palettes/<flavor>.lua`
  (`latte`, `frappe`, `macchiato`, `mocha`) — returns a Lua table of named
  hexes (`base`, `mantle`, `crust`, `text`, `subtext0`, `surface0/1/2`,
  `overlay0/1/2`, `red`, `green`, `peach`, `mauve`, `lavender`, `blue`, …).
- **tokyonight**: `.../tokyonight/lua/tokyonight/colors/<style>.lua`.
- **gruvbox / others**: grep the plugin for a `colors`/`palette` table.

`cat` the file. If a theme only exposes highlight groups (no flat palette),
read the highlight definitions instead and pull the hexes you need.

### 2. Pick `base`

Set `base` to the closest built-in preset the theme starts from:
`light`, `dark`, `light-daltonized`, `dark-daltonized`. **Avoid the `*-ansi`
bases** — on light Catppuccin terminals ANSI white (slot 7) renders nearly
invisible; explicit hex overrides (this skill's approach) sidestep that bug.

### 3. Map palette → Claude tokens

Write `overrides` as `{ token: "#rrggbb" }`. Values accept `#rrggbb`, `#rgb`,
`rgb(r,g,b)`, `ansi256(n)`, or `ansi:<name>`. Unknown tokens and bad values are
silently ignored, so a typo can't break rendering.

Canonical mapping (Catppuccin names shown — substitute the equivalent role from
any palette: accent, fg, muted fg, the red/green/yellow/blue family, and the
background ladder):

| Claude token | Role / nvim source |
|---|---|
| `claude`, `permission`, `rate_limit_fill` | brand accent (Catppuccin `mauve`) |
| `briefLabelClaude` | brand accent |
| `briefLabelYou` | a contrasting accent (`blue`) |
| `text` | default fg (`text`) |
| `inverseText` | bg base, for text on colored badges (`base`) |
| `inactive` | muted fg (`subtext0`) |
| `subtle` | faint fg / borders (`surface2`) |
| `suggestion`, `promptBorder` | secondary accent (`lavender`) |
| `remember` | `pink` |
| `success`, `autoAccept`, `ide` | `green` |
| `error` | `red` |
| `warning`, `fastMode` | `peach` |
| `merged`, `planMode` | `teal` / `sapphire` |
| `bashBorder` | `yellow` |
| `userMessageBackground` | `mantle` (one step off base) |
| `userMessageBackgroundHover`, `bashMessageBackgroundColor`, `memoryBackgroundColor` | `crust` / `mantle` |
| `messageActionsBackground`, `selectionBg` | `surface0` |
| `rate_limit_empty` | `surface1` |

Shimmer pairs (lighter gradient color used in the spinner): set each alongside
its base token, a few % lighter — `claudeShimmer`, `warningShimmer`,
`permissionShimmer`, `promptBorderShimmer`, `inactiveShimmer`, `fastModeShimmer`.
These are Claude-Code-only (no nvim analog); a lightened variant is fine.

### 4. Diff colors — match nvim's blend math (the non-obvious part)

catppuccin/nvim does NOT use flat palette colors for diff backgrounds; it
blends the accent over `base`. From `catppuccin/groups/syntax.lua`:

- `DiffAdd  = blend(green, base, 0.18)`
- `DiffDelete = blend(red,  base, 0.18)`
- `DiffText = blend(blue,  base, 0.30)`  (word-level changed text)

`blend(fg, bg, a)` is per-channel `round(a*fg + (1-a)*bg)`. Compute and map:

| Claude token | value |
|---|---|
| `diffAdded` | `blend(green, base, 0.18)` |
| `diffRemoved` | `blend(red, base, 0.18)` |
| `diffAddedDimmed` | `blend(green, base, 0.06)` (faint context) |
| `diffRemovedDimmed` | `blend(red, base, 0.06)` |
| `diffAddedWord` | `blend(green, base, 0.30)` (hue-preserving, mirrors DiffText intensity) |
| `diffRemovedWord` | `blend(red, base, 0.30)` |

Snippet to compute exact values (substitute the theme's hexes):

```python
def blend(fg, bg, a):
    f=[int(fg[i:i+2],16) for i in (1,3,5)]; b=[int(bg[i:i+2],16) for i in (1,3,5)]
    return "#%02X%02X%02X"%tuple(round(min(max(0,a*f[i]+(1-a)*b[i]),255)) for i in range(3))
# base/green/red from the nvim palette; alphas 0.18 / 0.06 / 0.30
```

For non-catppuccin themes, prefer the theme's own `DiffAdd`/`DiffDelete`
highlight backgrounds if it defines them; fall back to this blend otherwise.

### 5. Write, stow, activate

1. Write `claude/.claude/themes/<slug>.json` in this repo. The filename (minus
   `.json`) is the slug; `name` is the display label in `/theme`.
2. From the repo root: `stow claude` (folds the new file into `~/.claude/themes/`
   if not already symlinked).
3. Activate: set `"theme": "custom:<slug>"` in `~/.claude/settings.json` (e.g.
   `jq` it in like `setup-theme.sh`), or just pick it in `/theme`.
4. Claude Code hot-reloads `~/.claude/themes/`, but if the directory was just
   converted to a symlink mid-session, the watcher needs a **restart** to see
   new files.

### 6. Verify

- `jq empty <file>` — valid JSON.
- Spot-check that every value is a real hex / accepted format.
- Confirm the palette hexes actually came from the nvim file (don't invent
  colors — read them).

## Example skeleton

```json
{
  "name": "Catppuccin Macchiato",
  "base": "dark",
  "overrides": {
    "claude": "#c6a0f6",
    "text": "#cad3f5",
    "success": "#a6da95",
    "error": "#ed8796",
    "warning": "#f5a97f",
    "promptBorder": "#b7bdf8",
    "diffAdded": "<blend(green,base,0.18)>",
    "diffRemoved": "<blend(red,base,0.18)>",
    "userMessageBackground": "#1e2030"
  }
}
```

The committed `claude/.claude/themes/catppuccin-latte.json` is a complete,
real-world reference — read it for the full token set.
