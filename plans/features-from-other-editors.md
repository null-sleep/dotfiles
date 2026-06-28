# Features from other editors worth stealing

**Status:** research / not started
**Date:** 2026-06-28

A running list of features from other editors (Zed, VS Code, etc.) that the
current Neovim setup lacks, mapped to candidate plugins. Add new sections per
editor over time.

---

## Current stack (for gap reference)

Installed plugins (from `plugins.lua`): nvim-tree, telescope (+fzf-native,
+ui-select), nvim-treesitter, lualine, gitsigns, satellite, toggleterm,
sidekick.nvim (AI), blink.cmp, conform, nvim-lint, mason (+lspconfig
+tool-installer), nvim-lspconfig, which-key, persistence, flatten, nvim-autopairs,
render-markdown, lazydev, mini.icons / mini.notify, plenary.

Already strong: fuzzy finding, formatting, linting, LSP, AI assist, git signs,
sessions, terminal panel.

---

## Zed

The signature Zed feature with **no equivalent** in the current config is the
**multibuffer**: project-wide search results (and diagnostics / references)
rendered as *one editable surface*. You edit every call site in context and save
them all at once — ideal for refactors (search a signature, see every call site,
edit them all in one view, save).

### Top pick: multibuffer-style search & replace → `grug-far.nvim`
Closest faithful port of Zed's killer feature. Run a project search, results open
in a normal buffer, edit them inline (regex/replacement, per-match toggles),
changes apply to source files on save. Highest value-to-effort; no overlap with
anything currently installed.
- https://github.com/MagicDuck/grug-far.nvim

### Secondary gaps (each fills a real hole)

- **Breadcrumbs / symbol path in the winbar** → `dropbar.nvim`
  Zed's top-bar breadcrumb showing `module > Class > method` with clickable
  navigation. No breadcrumb exists today. Native winbar + LSP/treesitter, low
  cost. Easy win right after grug-far.
  - https://github.com/Bekaboo/dropbar.nvim
- **Diagnostics / references panel** → `trouble.nvim`
  Zed's problems panel and "find all references in a multibuffer." Pairs with the
  existing LSP setup. (Also relevant to the edgebar idea in
  `plans/unified-sidebar-panel.md`.)
  - https://github.com/folke/trouble.nvim
- **Git panel (stage/commit/diff in a pane)** → `neogit`
  Zed shipped a real git panel in 2025; current setup only has inline `gitsigns`.
  Biggest behavioral upgrade if doing commits inside the editor.
  - https://github.com/NeogitOrg/neogit
- **Native debugger** → `nvim-dap` + `nvim-dap-ui`
  Zed shipped this in 2025. Largest lift; only worth it for in-editor debugging.

### Recommendation / priority

1. `grug-far.nvim` — most distinctively "Zed," best value-to-effort.
2. `dropbar.nvim` — easy win, fills the breadcrumb gap.
3. `trouble.nvim` — diagnostics/references panel (ties into the sidebar plan).
4. `neogit` — only if moving git workflow into the editor.
5. `nvim-dap` — only if in-editor debugging is wanted.

---

## (Future) VS Code, JetBrains, etc.

Add sections here as more editors are reviewed.

---

## Sources

- Zed editing / multibuffers — https://zed.dev/docs/editing-code
- Zed 2025 recap — https://zed.dev/2025
- Zed git panel — https://zed.dev/docs/git
