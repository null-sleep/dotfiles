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
- **Outline panel (persistent symbol tree)** → `outline.nvim`
  Zed's right-side outline: an always-visible, collapsible tree of the buffer's
  symbols (methods nested under their type) with a search box at the top and
  cursor-follow. Worth being clear about what it *isn't* doing — Zed is not
  selecting "relevant" symbols, it just renders LSP `textDocument/documentSymbol`,
  which is already hierarchical and omits locals/params/loop vars. Any plugin on
  that same endpoint reproduces the screenshot. We have a fuzzy *picker* for this
  (`pickers/symbols.lua`, `<leader>ss`) — the popup search box — but no persistent
  sidebar tree.
  - `hedyhli/outline.nvim` — closest faithful port: sidebar, collapsible tree,
    cursor-follow, built-in symbol search. Pure Lua, no deps → cleanest fit for
    our `vim.pack` setup. Top pick.
    - https://github.com/hedyhli/outline.nvim
  - alt `stevearc/aerial.nvim` — most powerful (sidebar *or* fuzzy-nav, breadcrumb
    support, treesitter fallback when no LSP), more config surface.
    - https://github.com/stevearc/aerial.nvim
  - alt: `trouble.nvim` symbols mode (`:Trouble symbols`) gives a near-identical
    live outline for free if we install Trouble for the references panel above.
  - All three support `kind` filters, so we *could* go beyond Zed's default and
    hide e.g. variables — show only types/functions. (Ties into the edgebar idea
    in `plans/unified-sidebar-panel.md`.)
  - Sketch (vim.pack one-liner): `{ src = gh('hedyhli/outline.nvim') }`, then
    `require('outline').setup({})` + a `<leader>o` → `:Outline` toggle, registered
    the same way as the other `plugins.lua` sources.
- **Git panel (stage/commit/diff in a pane)** → `neogit`
  Zed shipped a real git panel in 2025; current setup only has inline `gitsigns`.
  Biggest behavioral upgrade if doing commits inside the editor.
  - https://github.com/NeogitOrg/neogit
- **Native debugger** → `nvim-dap` + `nvim-dap-ui`
  Zed shipped this in 2025. Largest lift; only worth it for in-editor debugging.

### Recommendation / priority

1. `grug-far.nvim` — most distinctively "Zed," best value-to-effort.
2. `dropbar.nvim` — easy win, fills the breadcrumb gap.
3. `outline.nvim` — persistent symbol-tree sidebar; cheap, pure Lua, complements
   the existing `<leader>ss` symbol picker.
4. `trouble.nvim` — diagnostics/references panel (also gives an outline mode for
   free; ties into the sidebar plan).
5. `neogit` — only if moving git workflow into the editor.
6. `nvim-dap` — only if in-editor debugging is wanted.

---

## VS Code

VS Code's distinctive day-to-day features that have **no equivalent** in the
current config are **sticky scroll** and **multi-cursor**. A few others (problems
panel, breadcrumbs) overlap with the Zed section above — listed as cross-refs
rather than duplicated.

### ✅ Done: sticky scroll → `nvim-treesitter-context`
Pins the enclosing scope (class / function / interface signatures) to the top of
the window as you scroll, so you always know where you are in a deeply nested
file and can jump back to the scope top. Cleanest, highest-value port — already
running treesitter, so this was near-zero added cost.
Implemented in `lua/treesitter_context.lua` (2026-07-03).
- https://github.com/nvim-treesitter/nvim-treesitter-context

### Second pick: multi-cursor (Ctrl+D) → `multicursor.nvim` (or `vim-visual-multi`)
VS Code's signature `Ctrl+D` "select next occurrence / edit many spots at once"
flow. No native Neovim equivalent (vim's closest is `:s`, macros, or visual-block
— different ergonomics). The most-missed VS Code muscle memory for many vim users.
- https://github.com/jake-stewart/multicursor.nvim
- alt: https://github.com/mg979/vim-visual-multi

### Other gaps (each fills a real hole)

- **Peek definition / references (inline, no jump)** → `glance.nvim`
  VS Code's "Peek Definition" opens an inline preview window instead of jumping
  away. Native LSP only jumps. Complements the existing LSP setup.
  - https://github.com/dnlhc/glance.nvim
  - alt: https://github.com/rmagatti/goto-preview
- **Tasks runner (tasks.json: build/test/run from the editor)** → `overseer.nvim`
  VS Code's task system with a task list and output panel. No task runner today.
  - https://github.com/stevearc/overseer.nvim
- **Rename with live preview (F2)** → `inc-rename.nvim`
  VS Code's rename shows changes as you type. Native LSP rename has no live
  preview. Small, focused.
  - https://github.com/smjonas/inc-rename.nvim
- **Zen / centered layout** → `zen-mode.nvim`. Minor, nice-to-have.

### Already covered (no action needed)

- **Command palette** → telescope (`commands` / `command_history` pickers) +
  which-key already cover this.
- **Minimap** → `satellite.nvim` already provides the navigation/overview role
  (git, diagnostics, search, cursor marks) without a full minimap render. A true
  minimap (`neominimap` / `codewindow.nvim`) would be cosmetic overlap.
- **Problems panel** → `trouble.nvim` (already listed under Zed).
- **Breadcrumbs** → `dropbar.nvim` (already listed under Zed; VS Code shares it).
- **Integrated terminal** → `toggleterm` (installed).

### Recommendation / priority

1. `nvim-treesitter-context` — sticky scroll; easiest high-value win.
2. `multicursor.nvim` — fills the biggest VS Code muscle-memory gap.
3. `glance.nvim` — peek definition/references.
4. `overseer.nvim` — only if running build/test tasks from the editor.
5. `inc-rename.nvim` — small polish on LSP rename.

---

## (Future) JetBrains, etc.

Add sections here as more editors are reviewed.

---

## Sources

- Zed editing / multibuffers — https://zed.dev/docs/editing-code
- Zed 2025 recap — https://zed.dev/2025
- Zed git panel — https://zed.dev/docs/git
- VS Code sticky scroll — https://dev.to/robole/vs-code-sticky-code-sections-for-improved-contextual-browsing-sticky-scroll-1o6
- VS Code user interface (minimap, peek) — https://code.visualstudio.com/docs/getstarted/userinterface
- nvim sticky scroll discussion — https://neovim.discourse.group/t/is-there-a-function-plugin-works-like-vs-codes-sticky-scroll/3173
