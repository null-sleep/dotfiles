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
  - Tried and removed (2026-07-03): didn't like it in practice.
  - https://github.com/Bekaboo/dropbar.nvim
- **Diagnostics / references panel** → `trouble.nvim`
  Zed's problems panel and "find all references in a multibuffer." Pairs with the
  existing LSP setup. (Also relevant to the edgebar idea in
  `plans/unified-sidebar-panel.md`.)
  - https://github.com/folke/trouble.nvim
- ✅ **Done: Outline panel (persistent symbol tree)** → `stevearc/aerial.nvim`
  Zed's right-side outline: an always-visible, collapsible tree of the buffer's
  symbols (methods nested under their type), cursor-follow, kind-filtered to
  structural symbols by default (Class/Function/Method/Interface/Struct/Enum/
  Module/Constructor — same as VS Code's default, hiding locals/params/vars).
  Chose aerial over `hedyhli/outline.nvim` for its treesitter-first backend
  (works with no LSP attached) and first-class Telescope extension. Docked
  left (alongside nvim-tree), persistent (never auto-closes on jump).
  We already have a fuzzy *picker* for this (`pickers/symbols.lua`, `<leader>ss`
  workspace / `<leader>sS` document) — the popup search box — this adds the
  persistent sidebar tree that was missing, plus a second Telescope picker
  scoped to aerial's own symbol source.
  `<leader>o` toggles the sidebar, `<leader>O` the AerialNav popup,
  `<leader>sb` the Telescope picker, `]a`/`[a` jump between symbols.
  Implemented in `lua/outline.lua` (2026-07-03).
  - https://github.com/stevearc/aerial.nvim
  - alt (not chosen): `hedyhli/outline.nvim` — lower Neovim version floor,
    finer-grained inclusive/exclusive kind filtering, weaker picker integration.
    https://github.com/hedyhli/outline.nvim
  - alt: `trouble.nvim` symbols mode (`:Trouble symbols`) gives a near-identical
    live outline for free if we install Trouble for the references panel above.
- **Git panel (stage/commit/diff in a pane)** → `neogit`
  Zed shipped a real git panel in 2025; current setup only has inline `gitsigns`.
  Biggest behavioral upgrade if doing commits inside the editor.
  - https://github.com/NeogitOrg/neogit
- **Native debugger** → `nvim-dap` + `nvim-dap-ui`
  Zed shipped this in 2025. Largest lift; only worth it for in-editor debugging.

### Recommendation / priority

1. `grug-far.nvim` — most distinctively "Zed," best value-to-effort.
2. ~~`dropbar.nvim`~~ — tried and removed (2026-07-03); didn't like it in practice.
3. ✅ `aerial.nvim` — persistent symbol-tree sidebar; done (2026-07-03), complements
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

- ✅ **Done: Peek definition / references (inline, no jump)** → `rmagatti/goto-preview`
  VS Code's "Peek Definition" opens an inline preview window instead of jumping
  away. Already implemented (predates this doc's audit) via `goto-preview`, not
  `glance.nvim`: `<leader>pd`/`pt`/`pi`/`pr` peek definition/type/implementation/
  references in a scrollable float, `<leader>pq` closes all. Configured in
  `lua/lsp.lua` (`border = 'rounded'`, `focus_on_open = true`,
  `dismiss_on_move = false`).
  Compared against `glance.nvim` (2026-07-03): goto-preview's `references`/
  `implementation`/`type_definition` peeks *do* handle multiple results — via a
  picker overlay (telescope by default) rather than glance's persistent
  embedded list+preview split. `goto_preview_definition` itself only jumps to
  the first result (no multi-result list), unlike the others. glance's real
  edges: folds inside its results list, and results stay visible without a
  picker-selection step. goto-preview's edges: supports peeking `declaration`
  (glance doesn't), nested/stacked peek-within-a-peek, and pluggable picker
  backends (telescope/fzf-lua/snacks/mini.pick) instead of a fixed native UI.
  Judged not worth switching for the definition-picker gap alone.
  - https://github.com/rmagatti/goto-preview
  - alt (not chosen): https://github.com/dnlhc/glance.nvim
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
- **Breadcrumbs** → `dropbar.nvim` (already listed under Zed; tried and removed
  2026-07-03 — didn't like it in practice).
- **Integrated terminal** → `toggleterm` (installed).

### Recommendation / priority

1. ✅ `nvim-treesitter-context` — sticky scroll; done.
2. `multicursor.nvim` — fills the biggest VS Code muscle-memory gap.
3. ✅ `goto-preview` — peek definition/references; done (predates this doc's audit).
4. `overseer.nvim` — only if running build/test tasks from the editor.
5. `inc-rename.nvim` — small polish on LSP rename.

---

## JetBrains

**Status:** research / not started
**Date:** 2026-07-04

JetBrains IDEs let a single "Find in Files" search become a saved, persistent
panel: iterate over the results, dismiss irrelevant hits, keep the rest, then
act on what's left. The closest Neovim primitive is the **quickfix list** —
it's just not wired up to Telescope or pruned with a plugin yet.

### Core loop (native, no new plugin required)
1. Seed the quickfix list from a search — `:grep`/`:vimgrep`, LSP references,
   or (since Telescope is already installed) hit `<C-q>` in a `live_grep`/
   `grep_string` picker to send all (or just the `<Tab>`-multiselected)
   results to the qflist instead of jumping to one match.
2. `:copen` opens it as a persistent panel. `]q`/`[q` (or `:cnext`/`:cprev`)
   cycle entries; `<CR>` on a line jumps there while the panel stays open.
3. **Dismissing entries** — the quickfix window is an editable buffer: `dd` a
   line to remove it, then `:cbuffer` re-parses the buffer back into the
   quickfix list. Pure vim, prunes the list down to "only the relevant hits."
4. Quickfix lists are stacked — `:colder`/`:cnewer` moves between previous
   searches, like flipping between saved search tabs.
5. Once pruned, `:cfdo <cmd>` runs a command across every remaining entry —
   the batch-action equivalent of "select the relevant ones, then act."

### Top pick: `nvim-bqf` for the panel UX
Turns the quickfix window into the JetBrains-style panel directly: interactive
fuzzy-filter/delete of entries, live preview pane, sign toggling — without the
`dd` + `:cbuffer` dance above.
- https://github.com/kevinhwang91/nvim-bqf

### Alt: `trouble.nvim`
Sidebar-styled list (diagnostics/qf/loclist) instead of the classic quickfix
window. Already on the list above for VS Code's problems panel — would cover
both asks if installed. Less delete-oriented than bqf, more of a live-view.
- https://github.com/folke/trouble.nvim

### Related: Harpoon2 for the "keepers," once pruned
Quickfix (and even a bqf-filtered qflist) is still ephemeral — it's overwritten
by the next search and doesn't survive a session restart. Once you've dismissed
the noise and are left with a handful of genuinely relevant locations,
`plans/harpoon2.md` (planned, not yet installed — no `harpoon` entry in
`plugins.lua` today) is the natural next step: a small, persistent, ordered
bookmark list per project that survives restarts and is jumped to by index
(`<leader>1`-`<leader>5`). It's not a search/results panel itself — it has no
own concept of dismissing/filtering — but it's the right place to "graduate"
the results you decided to keep, for a project you're returning to over
several sessions.
- https://github.com/ThePrimeagen/harpoon (branch `harpoon2`)
- see `plans/harpoon2.md` for the existing implementation plan

### Gaps in the current config
No `<C-q>`-to-qflist keymap and no qf-pruning plugin are wired up yet
(`pickers/filter.lua` wraps `live_grep`/`find_files` with filter presets, but
doesn't touch quickfix). Telescope, fzf-native, and ui-select are already
installed, so this is mostly wiring + one new plugin. Harpoon2 is a fully
separate, already-planned addition (see above) — not required for the
quickfix workflow itself.

### Recommendation / priority
1. Wire `<C-q>` in the existing `live_grep` picker (`pickers/filter.lua`
   `M.live_grep`) to send results to the quickfix list.
2. Add a `:cbuffer`-reload keymap in the qf window as the zero-dependency
   dismiss workflow.
3. `nvim-bqf` — if the native `dd`+`:cbuffer` loop feels clunky in practice.
4. Revisit `trouble.nvim` decision jointly with the VS Code problems-panel ask
   above, since one install would serve both.
5. Harpoon2 — separate track, already planned in `plans/harpoon2.md`; worth
   implementing regardless, and complements this workflow for cross-session
   bookmarking of the results you kept.

Add further sections here as more editors are reviewed.

---

## Sources

- Zed editing / multibuffers — https://zed.dev/docs/editing-code
- Zed 2025 recap — https://zed.dev/2025
- Zed git panel — https://zed.dev/docs/git
- VS Code sticky scroll — https://dev.to/robole/vs-code-sticky-code-sections-for-improved-contextual-browsing-sticky-scroll-1o6
- VS Code user interface (minimap, peek) — https://code.visualstudio.com/docs/getstarted/userinterface
- nvim sticky scroll discussion — https://neovim.discourse.group/t/is-there-a-function-plugin-works-like-vs-codes-sticky-scroll/3173
