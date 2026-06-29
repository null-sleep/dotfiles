# Unified editor-style sidebar / activity panel for Neovim

**Status:** research / not started
**Date:** 2026-06-28

Goal: support a VS Code / Zed-style side panel that can host multiple tools
(file explorer, code outline, git, etc.) — either as a single shared pane that
switches content, or as one docked edgebar with stacked, collapsible sections.

---

## What the current config already does

- **Left sidebar / file explorer** → `nvim-tree` (`filetree.lua`), VS Code-styled
  with git decorations, custom width (35), custom keymaps, and a `QuitPre`
  auto-close autocmd.
- **Git** → `gitsigns` inline signs + `satellite.nvim` scrollbar markers
  (`git.lua`). This is inline, *not* a panel.
- **Symbols / outline** → only a Telescope *picker* (`pickers/symbols.lua`).
  Transient popup, not a persistent docked pane.
- **Bottom panel** → recently added terminal panel (`terminal.lua`,
  see `plans/terminal-side-panel.md`).

So individual sidebars exist, but there is no **manager** that treats them as one
editor-style panel. That manager is the missing piece — and Neovim supports it.

---

## Two interpretations (they need different plugins)

### A. One pane, content swaps
True VS Code activity-bar feel: click an icon and the *same* pane shows
Explorer → then Git → then Outline; only one visible at a time.

- **switchpanel.nvim** — https://github.com/arakkkkk/switchpanel.nvim
  Explicitly built to mimic the VS Code sidebar with switchable views + icon bar.
- **vim-sidebar-manager** — https://github.com/brglng/vim-sidebar-manager
  Lighter; "switch" to one sidebar and it auto-closes the others sharing the slot.
  Lowest-friction add if we just want switching behaviour over existing sidebars.

### B. One edgebar, sections stacked & collapsible
Multiple tools docked together vertically, sub-sections collapsed by default.
This matches the "sub items collapsed by default" idea most closely.

- **edgy.nvim** (folke) — https://github.com/folke/edgy.nvim
  Strongest, best-maintained option. Declare which filetypes dock to
  `left`/`right`/`top`/`bottom`; multiple windows stack in one edgebar, each
  individually **collapsible** and **pinnable** (stays visible even when empty).
  Navigate the stack with `]w`/`[w`, close with `q`, hide with `<c-q>`.
  De-facto IDE-layout manager today. Could also formalize the bottom terminal
  panel into the same system.

**Leaning:** edgy.nvim — closest to the described behaviour and actively maintained.

---

## Missing piece for the outline: a persistent symbols pane

The current symbols Telescope picker won't dock into a panel. Need a real
sidebar plugin.

Worth being explicit about what such a pane reproduces: Zed's outline (and the
equivalent in any of these plugins) is **not** doing clever "relevant symbol"
selection. It renders LSP `textDocument/documentSymbol`, which the server already
returns as a hierarchy (methods nested under their type) with locals, params, and
loop vars excluded. So the screenshot-faithful result is automatic on that
endpoint — the plugin choice below is about the *pane* (docking, cursor-follow,
search, filters), not about any filtering smarts. Candidates:

- **aerial.nvim** (stevearc) — https://github.com/stevearc/aerial.nvim
  Recommended. Mature. Has the miller-column `AerialNav` view (like navbuddy),
  Telescope + statusline integration.
- **outline.nvim** (hedyhli) — https://github.com/hedyhli/outline.nvim
  Fork of symbols-outline.nvim. Simpler, broader source support (LSP +
  treesitter, JSX, Markdown, Norg, Man), but weaker ecosystem integration
  (Telescope/statusline still WIP per its README).

Trade-off (per the two projects' own comparison): use **aerial** if you want the
nav/miller-column view and tighter integrations; use **outline** if you want the
narrower, simpler "outline window only" scope and the extra non-LSP sources.

See also existing notes in `plans/symbol-picker-alternatives.md`.

---

## Sketch config (matches the native `vim.pack` style used in plugins.lua)

```lua
-- plugins.lua additions
{ src = gh('folke/edgy.nvim') },
{ src = gh('stevearc/aerial.nvim') },
```

```lua
require('aerial').setup({ layout = { default_direction = 'prefer_left' } })

require('edgy').setup({
  left = {
    { ft = 'NvimTree', title = 'Explorer', size = { width = 35 } },
    { ft = 'aerial',   title = 'Outline', pinned = true, collapsed = true },
  },
  bottom = {
    { ft = 'toggleterm', title = 'Terminal', size = { height = 0.25 } },
  },
})
```

edgy reference example (left edgebar with neo-tree used twice + outline):

```lua
left = {
  { ft = "neo-tree", title = "Files" },
  { ft = "neo-tree", title = "Git", pinned = true, collapsed = true },
  { ft = "Outline",  title = "Symbols", pinned = true },
}
```

edgy integrates with: neo-tree.nvim, bufferline.nvim, mini.animate, noice.nvim,
and has examples for toggleterm, lazyterm, Trouble, spectre_panel.

---

## Caveat specific to this config: nvim-tree vs edgy

edgy docks windows **by filetype**, but `nvim-tree` aggressively manages its own
window (width, position, plus the custom `QuitPre` auto-close autocmd in
`filetree.lua`). It can fight edgy. Two paths:

1. **Keep nvim-tree** and let edgy adopt the `NvimTree` filetype — works, but
   expect to relax/drop the custom width + auto-close logic so edgy owns layout.
2. **Switch the explorer to neo-tree** — what edgy is built and documented
   against; smoothest result, at the cost of porting nvim-tree keymaps/config.

If only interpretation A (unified switching) is wanted without restructuring the
layout, `vim-sidebar-manager` is the lowest-friction add — it just coordinates
opening/closing the sidebars that already exist.

---

## Other plugins seen during research (lower priority)

- **sidebar.nvim** — https://github.com/sidebar-nvim/sidebar.nvim
  Generic, modular lua sidebar inspired by lualine. Older, less active.
- **nvim-ui-modifier** (VS Code extension marketplace) — not relevant; for the
  vscode-neovim integration, not standalone Neovim.

---

## Open questions / decisions for later

1. Interpretation A (swap-in-place) vs B (stacked edgebar)? Leaning B (edgy).
2. Keep nvim-tree or migrate to neo-tree? (Determines edgy smoothness.)
3. aerial vs outline for the symbols pane.
4. Fold the existing bottom terminal panel into edgy, or leave it standalone?

---

## Sources

- edgy.nvim — https://github.com/folke/edgy.nvim
- switchpanel.nvim — https://github.com/arakkkkk/switchpanel.nvim
- vim-sidebar-manager — https://github.com/brglng/vim-sidebar-manager
- sidebar.nvim — https://github.com/sidebar-nvim/sidebar.nvim
- aerial.nvim — https://github.com/stevearc/aerial.nvim
- outline.nvim — https://github.com/hedyhli/outline.nvim
