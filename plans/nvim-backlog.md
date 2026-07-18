# Neovim enhancement backlog

**Status:** research / backlog — running list, not a committed roadmap
**Started:** 2026-06-28 · consolidated 2026-07-11 · re-audited against the code
2026-07-14

The single backlog of Neovim features/enhancements this config doesn't have
yet, mapped to candidate plugins. Consolidated from four docs that used to
duplicate each other: the by-editor gap analyses (Zed / VS Code / JetBrains
below), the **LazyVim** and **LunarVim** comparison passes (now the capability
sections — Editing power, Language servers, Options & autocmds), and the loose
`TODO.md` wishlist (Smaller wishlist + Learning notes). Items that have their
own dedicated plan file are pointers under "See dedicated specs," not
re-listed here. Won't-do decisions are preserved in "Rejected" so they don't
get re-litigated.

The code is the source of truth; ✅ marks items already shipped.

---

## Current stack (for gap reference)

Installed plugins, grouped as in `plugins.lua` — keep this in sync with that
file, since every "no equivalent today" claim below is measured against it:

- **Editing / UI** — nvim-treesitter (+ `-context` for sticky scroll,
  `-textobjects` for the queries sidekick reads), snacks.nvim (picker, indent,
  bigfile, scratch, profiler), nvim-tree, aerial (outline sidebar), stickybuf,
  lualine, satellite, which-key, render-markdown, nvim-autopairs, mini.icons /
  mini.notify / mini.bufremove.
- **LSP / completion** — nvim-lspconfig, mason (+ lspconfig + tool-installer),
  lazydev, nvim-lsp-file-operations, goto-preview (peek), blink.cmp, conform,
  nvim-lint.
- **Git** — gitsigns (signs, inline blame), neogit (Magit-style operations
  dashboard, `<leader>g*`), diffview (rich diffs, `<leader>v*`).
- **Debug / test / languages** — nvim-dap + nvim-dap-ui + nvim-nio, neotest,
  rustaceanvim (Rust), nvim-dap-go + neotest-golang (Go).
- **Workflow** — sidekick.nvim (AI), toggleterm, persistence (sessions),
  auto-save, flatten, plenary.

Already strong: fuzzy finding, formatting, linting, LSP, AI assist, git (signs
*and* a full operations UI), debugging, test running, sessions, terminal panel.

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
anything currently installed. Independently reconfirmed by the LazyVim and TODO
passes. Keymap: LazyVim binds it `<leader>sr`, but that's taken here by
picker-resume (`Snacks.picker.resume()`, `keymaps.lua`) — use `<leader>sR`.
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
  `plans/unified-sidebar-panel.md`.) The LazyVim/LunarVim passes both *rejected*
  trouble for now — loclist + the picker + satellite marks cover the
  diagnostics-list workflow, and `plans/quickfix-improvements.md` owns list
  ergonomics; reconsider only if that plan stalls or the problems-panel/
  references ask below wins out.
  - https://github.com/folke/trouble.nvim
- ✅ **Done: Outline panel (persistent symbol tree)** → `stevearc/aerial.nvim`
  Zed's right-side outline: an always-visible, collapsible tree of the buffer's
  symbols (methods nested under their type), cursor-follow, kind-filtered to
  structural symbols by default (Class/Function/Method/Interface/Struct/Enum/
  Module/Constructor — same as VS Code's default, hiding locals/params/vars).
  Chose aerial over `hedyhli/outline.nvim` for its treesitter-first backend
  (works with no LSP attached). Docked left (alongside nvim-tree), persistent
  (never auto-closes on jump).
  We already have a fuzzy *picker* for this (`pickers/symbols.lua`, `<leader>ss`
  workspace / `<leader>sS` document) — the popup search box — this adds the
  persistent sidebar tree that was missing.
  `<leader>o` toggles the sidebar, `<leader>O` the AerialNav popup, `]a`/`[a`
  jump between symbols. Implemented in `lua/outline.lua` (2026-07-03).
  (The originally-planned third keymap — a fuzzy picker over aerial's own
  symbol source — was never bound: it was to be aerial's Telescope extension,
  and the snacks migration dropped Telescope. `<leader>sb` is
  `Snacks.picker.lines()`. The two `pickers/symbols.lua` maps cover the ask.)
  - https://github.com/stevearc/aerial.nvim
  - alt (not chosen): `hedyhli/outline.nvim` — lower Neovim version floor,
    finer-grained inclusive/exclusive kind filtering, weaker picker integration.
    https://github.com/hedyhli/outline.nvim
  - alt: `trouble.nvim` symbols mode (`:Trouble symbols`) gives a near-identical
    live outline for free if we install Trouble for the references panel above.
- ✅ **Done: Git panel (stage/commit/diff in a pane)** → `neogit` + `diffview`
  Zed shipped a real git panel in 2025; this config had only inline `gitsigns`
  when the gap was written. Now a Magit-style operations dashboard in
  `lua/gitui.lua` (`<leader>gg` status, `<leader>gc`/`gp`/`gu`/`gl`/`gd`/`gb`/
  `gr`/`gw` popups, mnemonics mirroring the zsh git aliases), with `diffview`
  for the rich diffs (`<leader>v*`). gitsigns still owns the gutter — Neogit's
  own signs are disabled so the two don't stack.
  - https://github.com/NeogitOrg/neogit
- ✅ **Done: Native debugger** → `nvim-dap` + `nvim-dap-ui`
  Zed shipped this in 2025; it was the largest lift on this list and it landed.
  `lua/debugging.lua` owns the generic engine + docked UI (scopes, call stack,
  breakpoints, watches, REPL); adapters live in the language modules
  (`rust.lua`/codelldb, `golang.lua`/delve). Test running came with it via
  `neotest` (+ `neotest-golang`). Still open, and now a genuine one-liner:
  `nvim-dap-virtual-text` (see Smaller wishlist).

### Recommendation / priority

1. `grug-far.nvim` — most distinctively "Zed," best value-to-effort.
2. ~~`dropbar.nvim`~~ — tried and removed (2026-07-03); didn't like it in practice.
3. ✅ `aerial.nvim` — persistent symbol-tree sidebar; done (2026-07-03), complements
   the existing `<leader>ss` symbol picker.
4. `trouble.nvim` — diagnostics/references panel (also gives an outline mode for
   free; ties into the sidebar plan).
5. ✅ `neogit` + `diffview` — git operations dashboard; done.
6. ✅ `nvim-dap` + `nvim-dap-ui` — in-editor debugging; done (plus `neotest`).

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
  VS Code's task system with a task list and output panel. Narrower ask than
  when first written (2026-07-14): `neotest` now runs tests from the editor,
  and the Go targets picker (`plans/go-targets-picker.md`) runs/debugs `main`
  packages. What's still missing is the *generic*, per-project task list —
  arbitrary build/lint/deploy commands with an output panel. Only worth it if
  that generic need shows up.
  - https://github.com/stevearc/overseer.nvim
- **Rename with live preview (F2)** → `inc-rename.nvim`
  VS Code's rename shows changes as you type. Native LSP rename has no live
  preview. Small, focused.
  - https://github.com/smjonas/inc-rename.nvim
- **Zen / centered layout** → `zen-mode.nvim`. Minor, nice-to-have.

### Already covered (no action needed)

- **Command palette** → which-key (leader-key discovery) + the custom
  keybindings picker cover the discovery half. The literal `:`-command half
  (snacks' `commands` / `command_history` sources) is *not* bound — it's the
  "Vim-state pickers" item under "Picker (snacks)" below, not a separate ask.
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
it's just not wired up to the picker or pruned with a plugin yet.

### Core loop (native, no new plugin required)
1. Seed the quickfix list from a search — `:grep`/`:vimgrep`, LSP references,
   or from the picker: `<C-q>` sends all results (or just the
   `<Tab>`-multiselected ones) to the quickfix list instead of jumping to one
   match. ✅ Already works — it's a snacks *default* binding, so it came free
   with the picker migration; see GUIDE.md "Picker (snacks.nvim)".
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
Step 1 (seeding) is **already done** — `<C-q>` → `qflist` is a stock snacks
binding in both the input and list windows, so it came free with the picker
migration and works in every source. What's missing is everything downstream of
it: no qf-pruning plugin, and no `:cbuffer`-reload keymap for the
zero-dependency dismiss loop. Harpoon2 is a fully separate, already-planned
addition (see above) — not required for the quickfix workflow itself.

### Recommendation / priority
1. Add a `:cbuffer`-reload keymap in the qf window as the zero-dependency
   dismiss workflow. (Seeding the list is already covered — see Gaps above.)
2. `nvim-bqf` — if the native `dd`+`:cbuffer` loop feels clunky in practice.
3. Revisit `trouble.nvim` decision jointly with the VS Code problems-panel ask
   above, since one install would serve both.
4. Harpoon2 — separate track, already planned in `plans/harpoon2.md`; worth
   implementing regardless, and complements this workflow for cross-session
   bookmarking of the results you kept.

Add further sections here as more editors are reviewed.

---

## Editing power & motions

From the LazyVim/LunarVim passes. Ordered roughly by payoff. Collision checks
belong at implementation time against `plans/keymap-tracker.md` (the keymap
inventory).

- **Surround add/change/delete** — the single biggest editing-power gap;
  nothing here can surround existing text (nvim-autopairs only *inserts*
  pairs). `nvim-mini/mini.surround` fits the existing mini.* family; use the
  `gs`-prefixed keyset (`gsa`/`gsd`/`gsr`/`gsf`/`gsh`) — it keeps `s` free in
  case flash lands there. Alt: `kylechui/nvim-surround` (`ys`/`cs`/`ds`).
- **Labeled jump motion → `folke/flash.nvim`** — no long-range motion story
  today. `s` labeled jump, `S` treesitter-node select, `r`/`R` remote in
  operator-pending, `<c-s>` toggle during `/`. Conflict: `s` = core substitute
  (standard flash trade-off); `S` overlaps the hand-built `<M-o>`/`<M-i>`
  structural select — keep both initially, judge later. (LazyVim rates this a
  strong yes; the LunarVim pass rated it weakest given the existing structural
  select — decide based on whether jump-to-arbitrary-position friction is real
  for you.)
- **Move line/selection** — no move-line maps today. `<A-j>`/`<A-k>` (LazyVim's
  keys) are split-resize here, so use **`<A-Up>`/`<A-Down>`** in n/i/x:
  `:m .+1<CR>==` / `:m .-2<CR>==` (insert: `<Esc>…gi`; visual: `:m '>+1<CR>gv=gv`).
- **Undo break-points in insert mode** — map `,` `.` `;` each to `<char><c-g>u`
  so one `u` no longer nukes an entire insert session. Three one-liners.
- **`j`/`k` → `gj`/`gk` when no count** — `{expr=true}`, `v:count==0 ? 'gj':'j'`
  (n+x, also `<Down>`/`<Up>`). Matters here because `wrap` is **on**.
- **`n`/`N` always forward/backward** — regardless of `/` vs `?`; append `zv`
  to open folds at the match. Expr maps, n/x/o.
- **snacks `words`** — `]]`/`[[` (and `<a-n>`/`<a-p>`) jump between LSP
  references of the symbol under cursor. Document-highlight is already wired on
  LspAttach, so the visual half exists; this adds navigation. Nearly free
  (snacks already installed). Conflict: `]]`/`[[` are core section motions —
  confirm they're unused in your languages first.

## Picker (snacks) — missing keymaps & sources

From a 2026-07-13 pass over LazyVim's `extras/editor/snacks_picker.lua` (~45
picker keymaps) against this config's ~12. The picker *internals* here are far
ahead of LazyVim's (custom `confirm` scroll-to-20%, `send_to_sidekick`,
frecency, width-flipping layout, the empty-until-typed `lines` source, plus the
bespoke symbols/keybindings/gitstatus/buffer/theme pickers) — the gap is purely
which stock snacks sources are bound. All of these are one-liners against
already-installed snacks; the only real work is collision-checking keys against
`plans/keymap-tracker.md`.

Ordered by expected payoff:

- **`<leader>sw` grep word/selection** — `Snacks.picker.grep_word()` in **both**
  `n` and `x` mode (visual selection becomes the query). The most-used LazyVim
  picker map and the most obvious hole here — today grepping the symbol under
  the cursor means `<leader>sg` + retyping it.
- **Diagnostics picker** — `Snacks.picker.diagnostics()` /
  `diagnostics_buffer()`. There is no diagnostics *list* of any kind today
  (no trouble, no qflist wiring), so this is the cheapest path to
  project-wide-problems browsing. Overlaps the trouble.nvim /
  `plans/quickfix-improvements.md` asks — do this first and see if either is
  still wanted.
- **`Snacks.picker.undo()`** — undotree as a picker (diff preview per undo
  state), no new plugin. Nothing covers this today.
- **Git history pickers** — `git_log_file()` (current file's history),
  `git_log_line()` (blame the line, with the commit's diff in the preview),
  `git_log()`, `git_diff()` (hunks), `git_stash()`. `pickers/gitstatus.lua`
  covers *status* only; history/blame browsing has no picker (gitsigns'
  inline blame is a different question — "who wrote this line", not "show me
  the commit").
- **`grep_buffers()`** — grep across open buffers only; the natural middle
  ground between `<leader>sb` (this buffer) and `<leader>sg` (whole tree).
- **Vim-state pickers** — `command_history`, `search_history`, `registers`,
  `marks`, `jumps`, `qflist`, `loclist`, `commands`. Low individual value, but
  they're free and they're what makes the picker a command palette.

Not worth porting from LazyVim's picker config:

- **`<a-t>` trouble_open** — requires trouble.nvim, which is not installed
  (and is separately deferred above).
- **`<a-c>` toggle_cwd** — the in-picker half of the root-dir abstraction; see
  Rejected below.
- **Flash-in-picker (`s` labels every visible row, then jumps)** — genuinely
  nicer than the `<M-1>`–`<M-9>` quick-pick in `pickers/common.lua` (not capped
  at 9, works after filtering), but it's a flash.nvim feature. Fold this into
  the flash decision under "Editing power & motions" rather than treating it as
  a picker item — if flash lands, add the picker action too.
- **`Snacks.picker.projects()` / `colorschemes()`** — no project-switching
  workflow here, and `pickers/theme.lua` already beats the stock colorscheme
  picker.

## Language servers & snippets

- **JSON/YAML LSP + schemastore** — verified gap: no `jsonls`/`yamlls` in
  `vim.lsp.enable` (`lsp.lua`), so JSON/YAML files get no LSP at all. Add
  `b0o/schemastore.nvim`, configure both servers via `vim.lsp.config` with
  `schemas = require('schemastore').json.schemas()` (and `yaml.schemas()`),
  add both to the mason-tool-installer list. Gets schema validation on
  package.json, GitHub workflows, docker-compose, etc.
- **friendly-snippets** — blink.cmp's `snippets` source is enabled
  (`completion.lua`) but no snippet collection is installed, so it's empty
  outside LSP-provided snippets. blink auto-loads `rafamadriz/friendly-snippets`
  once it's on the runtimepath — a one-line `vim.pack.add` entry. (This is the
  TODO "snippets" item too.)

## Options & autocmds

Options land in `configs.lua`, autocmds in `autocmds.lua`. Only genuine deltas
(checked-and-already-equivalent options from the LazyVim pass are omitted).

- **Options** — `splitkeep="screen"` (no text jump when splits open/close;
  noticeable with the bottom panel + sidebars), `jumpoptions="view"` (jumplist
  restores scroll position — pairs with the mouse-button jumplist maps),
  `grepprg="rg --vimgrep"` + `grepformat` (makes `:grep` a usable
  straight-to-quickfix fallback when you don't want the picker UI),
  `smoothscroll`, `virtualedit="block"`, `shiftround`.
- **`VimResized` auto-equalize** — `tabdo wincmd =` then return to the active
  tab (LunarVim's fixed version, commit `aa51c20f`). Relevant here: Neogit
  opens in a tab, Neovide resizes are common.
- **Lua `gf` on `require()` paths** — in lua files, make `gf`/`<C-w>f` jump to
  the module behind `require("foo.bar")`: FileType-lua autocmd setting
  `includeexpr` (dots→slashes), `suffixesadd=.lua`, runtimepath `/lua` dirs on
  `path`. lazydev gives completion/types but not this jump. ~15 lines.
- **Cmdline `<C-j>`/`<C-k>` wildmenu nav** — expr maps in cmdline mode:
  navigate the wildmenu when the pum is visible, pass through otherwise.
  Complements the existing window-nav muscle memory.
- **Prose `wrap`+`spell` for gitcommit/markdown/text** — spell is globally off
  (toggle `<leader>tz`); this scopes it on where it's useful without flipping
  the global. (Covers the TODO "spell check when reviewing" item.)
- **Severity-filtered diagnostic jumps** — `]e`/`[e` errors-only, `]w`/`[w`
  warnings-only, alongside `]d`/`[d`. Small `vim.diagnostic.jump({severity=…})`
  wrappers; useful since virtual text is off by default.
- **Extend the `q`-close handler** — the landed handler covers help/quickfix;
  add `checkhealth`, `lspinfo`, `neotest-output`/`-summary`/`-output-panel`,
  `dap-float`. Keep its don't-clobber-existing-`q` guard.
- **`ts-context-commentstring`** (consider) — correct `gc` commentstring in
  embedded languages (JS-in-HTML, CSS-in-templates). Low priority for
  Rust/Go/Python-heavy work; cheap to add when web work picks up.
- **Terminal-mode window nav `<C-h/j/k/l>`** (consider, with caveat) — leaving
  a toggleterm split needs `<C-\><C-n>` first today. But `<C-h/j/k/l>` are real
  shell/TUI keys (readline, the Claude CLI uses several) — scope to non-CLI
  terminals only, or skip.

### ✅ Done: big-file protection → `snacks.bigfile`

Enabled with stock defaults in `picker.lua` (2026-07-13) — a one-liner, since
snacks was already installed. Mechanism: it renames a >1.5MB (or minified —
average line length >1000) buffer's **filetype to `bigfile`**, and everything
ft-keyed (LSP, treesitter, nvim-lint, conform, aerial, render-markdown) then
never matches. Not covered by the rename, and deliberately deferred: gitsigns,
satellite, auto-save, sidekick NES. See `plans/large-file-protection.md` and
GUIDE.md "Large files".

## Smaller wishlist (from TODO.md)

- **octo.nvim** — view/comment/review GitHub PRs in-editor. Heavy plugin; may
  want to defer or avoid.
- **Markdown auto lists/headings** — continue list markers / heading levels on
  `<CR>` in markdown.
- ✅ **Picker preview placement / result scroll position** — both landed with
  the snacks migration: the layout flips preview placement by window width, and
  the custom `confirm` action scrolls the jumped-to result to ~20% from the top.
  See `plans/telescope-vs-snacks-picker.md`. No action.
- **Buffer-name display for inactive windows** — low-effort way to show which
  buffer an inactive window holds.
- **`nvim-dap-virtual-text`** — inline variable values during DAP sessions;
  one-line setup next to the existing dap-ui config in `debugging.lua`.
- **Spell in completion** — add the spell source to blink.cmp so suggestions
  appear inline while typing; map something ergonomic to `1z=` for quick fixes.
- **Alt file-explorers** (`neo-tree`/`oil`) — only if nvim-tree frustrations
  mount; not pursued, noted so the option isn't forgotten.
- ✅ **Indent guides** — already shipped via `snacks.indent` (`scratch.lua`,
  toggle `<leader>tg`). No action.
- ✅ **Next-edit prediction** — shipped via sidekick.nvim's Copilot-LSP NES
  (not `blink-edit.nvim`, which the TODO note pointed at). No action.
- **Sidekick CLI: force terminal mode on plain window-nav re-entry** —
  toggleterm now always reopens in terminal mode (`persist_mode = false` in
  `terminal.lua`, 2026-07-18), but sidekick.nvim has no equivalent config flag:
  it hardcodes a `self.normal_mode` field, restored on its own internal
  `WinEnter` autocmd (`sidekick/cli/terminal.lua`). Commands routed through
  `ai.lua` (`<leader>aa`, `<M-]>`/`<M-[>`, `<M-l>`) already force insert via
  `terminal:focus()`, so this only matters for a plain window-nav jump
  (`<C-w>w`, mouse click) straight into an already-open sidekick split.
  Fix sketch: in the `SidekickCliAttach` handler (`ai.lua`), register a
  second, buffer-local `WinEnter` autocmd on `term.bufnr` that unconditionally
  calls `vim.cmd.startinsert()` — since `SidekickCliAttach` fires after
  `terminal:start()` has already registered sidekick's own `WinEnter` handler,
  ours registers later and runs after it on the same event, so it wins. Not
  yet applied/tested; low priority since the common paths already work.

## See dedicated specs

These have their own plan files — pointers only, not re-listed here:

- **Persistent file bookmarks (harpoon)** → `plans/harpoon2.md`
- **Quickfix / problems-list ergonomics** → `plans/quickfix-improvements.md`
- **Semantic text objects (`af`/`if`/`ac`/… select, move, swap)** →
  `plans/treesitter-textobjects.md` (LazyVim's mini.ai delta folded in there)
- **Picker migration (telescope → snacks — done 2026-07), filter-preset rework,
  and symbols-picker eval** → `plans/telescope-vs-snacks-picker.md`
- **GUI-launched Neovide PATH/env** → `plans/neovide-path-env.md`
- **Go debug + test stack** (delve, neotest-golang) → `plans/go-run-debug-test.md`
  — **shipped**; the `nvim-dap` / `neotest` install traces back to it.
- **Go run/debug targets picker** → `plans/go-targets-picker.md` — **shipped**
  (`<leader>dR` in Go buffers). Narrows the `overseer.nvim` ask above.
- **Startup performance** → `plans/nvim-startup-performance.md`
- **Unified sidebar / edgebar (docking nvim-tree + aerial + trouble)** →
  `plans/unified-sidebar-panel.md`
- **cmux-inspired agent event pipeline (needs-input/done status per sidekick
  session)** → `plans/sidekick-agent-event-pipeline.md` — look into soon.
  Event pipeline only (Claude Code hooks → per-session registry); UI (status
  bar, signs, desktop notification) is a follow-on once the pipeline exists.

## Learning / practice notes

Not build tasks — personal practice reminders kept from `TODO.md` so they
aren't lost:

- Learn jump-word / sentence / paragraph motions; consider writing a short
  "vim basics" cheatsheet md.
- Learn fold collapse/expand and the less-used text objects (sentences,
  paragraphs, blocks).

## Rejected — don't re-litigate

Merged from the LazyVim and LunarVim passes (and one TODO musing). Recorded so
they aren't proposed again.

- **Distro machinery** — lazy.nvim / `LazyFile` event / LazyExtras /
  `opts_extend`; LunarVim's global `lvim` table, `:LvimReload`, `User
  FileOpened`/`DirOpened` lazy-load events, snapshot commit pinning,
  template-generated ftplugin LSP startup, none-ls bridge, mason
  `automatic_installation`. All serve deferred-loading/distro concerns; this
  config is eager `vim.pack` with `nvim-pack-lock.json` pinning and native
  `vim.lsp.enable`.
- **UI swaps already decided against** — snacks explorer/dashboard/notifier/
  lazygit, noice, bufferline, neo-tree, alpha dashboard, navic winbar,
  vim-illuminate, indent-blankline, Comment.nvim, project.nvim, lir.nvim,
  floating lazygit. Deliberate counter-choices exist (nvim-tree, mini.notify,
  lualine-only, Neogit + diffview, native documentHighlight, aerial +
  treesitter-context, snacks.indent, native `gc`, `vim.fs.root`).
  Note: snacks' *picker* is **not** in this list — it was adopted (migration
  done 2026-07, `plans/telescope-vs-snacks-picker.md`), replacing Telescope.
  Only the other snacks UI modules were declined.
- **barbar.nvim** — TODO's own note said "I should not, but if I did"; no
  bufferline is a deliberate choice.
- **dropbar.nvim breadcrumbs** — tried and removed 2026-07-03; didn't like it.
- **mini.pairs / Copilot-as-cmp-source / smart `<Tab>`/`<CR>` chains** —
  nvim-autopairs + the existing blink Tab chain (menu → Copilot ghost →
  literal) already cover these; switching buys nothing.
- **`<leader>u*` Snacks.toggle suite** — the `<leader>t*` toggle set already
  covers diagnostics/inlay/format/lint/spell/numbers/indent/AI/blame/hover.
- **Root-dir detection abstraction** (LazyVim `util/root.lua`) — big lift,
  moderate payoff unless monorepo (cwd ≠ project root) work becomes common.
  Revisit on demand, don't port speculatively. Reconfirmed 2026-07-13 during
  the snacks.picker pass: LazyVim gives *every* file/grep map a root-dir and a
  cwd variant (`<leader>ff` vs `<leader>fF`, detected LSP-workspace → root
  patterns → cwd) plus an `<a-c>` toggle inside the picker. That doubles the
  keymap surface to solve a problem that only exists when you launch nvim from
  somewhere other than the project root — not the case here. Every picker in
  this config uses cwd, deliberately.
- **dial.nvim / yanky / inc-rename** — inc-rename is redundant with core `grn`
  + `inccommand`; the others don't earn a slot yet.
- **structlog / `:LvimInfo` / nlsp-settings** — `:checkhealth` + mini.notify +
  native `exrc` (`.nvim.lua`) cover these at personal scale.
- ~~**Big-file protection**~~ — **shipped 2026-07-13**, moved out of Rejected;
  see "Done: big-file protection" under Options & autocmds.

---

## Sources

- Zed editing / multibuffers — https://zed.dev/docs/editing-code
- Zed 2025 recap — https://zed.dev/2025
- Zed git panel — https://zed.dev/docs/git
- VS Code sticky scroll — https://dev.to/robole/vs-code-sticky-code-sections-for-improved-contextual-browsing-sticky-scroll-1o6
- VS Code user interface (minimap, peek) — https://code.visualstudio.com/docs/getstarted/userinterface
- nvim sticky scroll discussion — https://neovim.discourse.group/t/is-there-a-function-plugin-works-like-vs-codes-sticky-scroll/3173
- LazyVim — `/Users/dhruv/src/LazyVim` (core v16, 2026-07); specs cited inline
  by file (`lua/lazyvim/plugins/…`, `config/keymaps.lua`, `config/options.lua`).
- LunarVim — `/Users/dhruv/src/LunarVim` (core, 2026-07); `lua/lvim/core/…`,
  `lua/lvim/keymappings.lua`, `lua/lvim/lsp/providers/…`.
