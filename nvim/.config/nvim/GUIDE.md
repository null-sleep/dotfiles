# Neovim Config Guide

> **This guide may be outdated.** The code is always the truth -- read the
> source files listed below before relying on anything here. Also check
> official docs for anything version-sensitive:
> - `:help lsp`, `:help vim.lsp.config`, `:help vim.pack` (nvim built-in)
> - `:help mason.nvim` / mason-lspconfig README
> - Individual server docs (e.g. gopls, rust-analyzer settings references)
> - blink.cmp README for completion/signature behavior
> - Plugin READMEs for gitsigns, satellite, persistence, which-key, etc.

Neovim 0.12+ with native `vim.pack` (not lazy.nvim), Mason for LSP server
installs, blink.cmp for completion, snacks.picker for fuzzy finding, treesitter
for highlighting/folding, lspconfig v3 API (`vim.lsp.config` + `vim.lsp.enable`).
Requires a Nerd Font for statusline separators and completion icons.

## Contents

- **Part 1: Essentials**
  - [Architecture](#architecture)
  - [Design Decisions](#design-decisions)
  - [Keymap index](#keymap-index)
- **Part 2: Reference**
  - [LSP](#lsp)
  - [Autocompletion (blink.cmp)](#autocompletion)
  - [Format-on-save](#format-on-save)
  - [Linting (nvim-lint)](#linting-nvim-lint)
  - [Themes](#themes)
  - [Treesitter](#treesitter)
  - [Picker (snacks.nvim)](#picker-snacks)
  - [Clipboard split](#clipboard-split)
  - [Structural selection](#structural-selection)
  - [Editing utilities](#editing-utilities)
  - [Markdown](#markdown)
  - [Session (persistence.nvim)](#session)
  - [Spell checking](#spell-checking)
  - [Window/tab title](#window-tab-title)
  - [File Explorer (nvim-tree)](#file-explorer)
  - [Outline (aerial)](#outline-aerial)
  - [Terminal (toggleterm.nvim)](#terminal)
  - [Scratch buffers (snacks.nvim)](#scratch-buffers)
  - [Indent guides (snacks.nvim)](#indent-guides)
  - [Git (Neogit)](#git-neogit)
  - [Reviewing diffs (diffview.nvim)](#reviewing-diffs)
  - [AI (sidekick.nvim)](#ai-sidekick)
  - [Rust (rustaceanvim + DAP + neotest)](#rust)
  - [Neovide](#neovide)


# Part 1: Essentials

## Architecture

### File responsibilities

- **`init.lua`** — Sets leader key, requires all modules in dependency order
- **`configs.lua`** — Core vim options (`updatetime`, `scrolloff`, tabs, undo, splits, `diffopt` with `linematch:60` + histogram, etc.), auto-reload for external file changes (focus/idle/buffer-switch + leaving a terminal, plus a 2s poll timer), nvim update check
- **`autocmds.lua`** — General editor autocmds not owned by a feature module, all under one `UserAutocmds` augroup: create missing parent dirs on save (skips `scheme://` buffers); restore last cursor position on file open (see [Design Decisions](#design-decisions) → "Cursor-restore rides BufReadPost"); flash yanked text (`vim.hl.on_yank`); map `q` to close transient help/quickfix windows (skips any buffer already binding `q`); quit nvim when only sidebars remain (see [Design Decisions](#design-decisions) → "Quit nvim when only sidebars remain")
- **`plugins.lua`** — `vim.pack.add` declarations for all plugins (including theme sources from `themes.lua`), orphan plugin detection, treesitter parser management (plus `nvim-treesitter-textobjects`, packadd'd here so sidekick's `{function}`/`{class}` context queries land on the runtimepath — no dedicated config module), render-markdown, autopairs (`check_ts = true`: treesitter-aware, skips pairing inside strings/comments), flatten.nvim (nested-nvim routing — see Design Decisions)
- **`treesitter_context.lua`** — nvim-treesitter-context: sticky scope header (VS Code-style sticky scroll) — pins the enclosing function/class/if/loop signature to the top of the window while scrolling. No keymaps; passive display feature
- **`keymaps.lua`** — Global keymaps: pickers (`<leader>s*`, snacks), clipboard-aware yank, split navigation, buffer navigation (`H`/`L`/`<leader><leader>`/`<leader>m`/`<leader>bb`/`<leader>bo`), visual indent, diagnostic toggle, yank helpers (`yp`, `yc`, `yu`, etc.)
- **`edit.lua`** — Editing utilities consumed by keymaps.lua (required from there, not init.lua — no Load-order entry): strip-trailing-whitespace (`<leader>us`, `:StripWS`) and pasted-terminal-text reflow (`<leader>uc`, `:CleanPaste`)
- **`outline.lua`** — aerial.nvim symbol-outline setup: docked sidebar (`<leader>o`) and floating nav popup (`<leader>O`) with code preview; buffer-local `]a`/`[a` symbol nav (no aerial picker keymap — `<leader>sd` covers picker-style symbol search)
- **`structural_select.lua`** — Helix-style structural (treesitter) selection: `<M-o>`/`<M-i>` grow/shrink the visual selection by syntax node, via the core `vim.treesitter` API (no extra plugin — replaces the incremental-selection module removed by nvim-treesitter's `main`-branch rewrite)
- **`pickers/buffer.lua`** — Custom snacks buffer picker (`<leader>bb`, aliased as `<leader>m`): row-index column replaces the bufnr column, `<M-1>`..`<M-9>` jumps to that row, `<C-d>` deletes the highlighted/selected buffers; stable bufnr row order (`sort_lastused` off)
- **`pickers/gitstatus.lua`** — snacks git-status picker (`<leader>sm`): wraps the builtin `git_status` source (diff preview, `<tab>` staging toggle with auto-refresh) adding a row-index column, `<M-1>`..`<M-9>` quick-pick, repo resolution from the current buffer's directory, and a "No changes found" notify instead of an empty picker
- **`pickers/common.lua`** — Shared picker utilities: `quick_pick_actions()` returns `<M-1>`..`<M-9>` row-jump actions/keys for snacks pickers, used by the buffer and gitstatus pickers
- **`pickers/symbols.lua`** — Custom snacks symbol pickers: `M.workspace` (`<leader>ss`) is a live picker fanning `workspace/symbol` to all active LSP clients (snacks' builtin only queries buffer-attached ones) with a two-token prompt (first token = name query sent to LSP, remainder = file path filter via matchfuzzy), custom kind icons, vertical layout; `M.document` (`<leader>sd`) wraps the builtin `lsp_symbols` flat and kind-unfiltered — kind is in the match text so typing "function"/"variable" filters by kind; `M.toggle_buffer_only` (`<leader>ts`) switches workspace mode between all-LSPs and buffer-only
- **`completion.lua`** — blink.cmp: keymap preset (Tab priority: blink menu → Copilot ghost text → literal Tab), sources, auto-brackets, signature hints, fuzzy backend. Ghost text disabled — Copilot inline completion provides its own.
- **`lsp.lua`** — Mason setup, mason-lspconfig, goto-preview setup (VS Code-style peek floats, `<leader>p*`), LspAttach autocmd (buffer-local keymaps + capability-gated features), diagnostic config, per-server `vim.lsp.config`, a `'*'` merge of nvim-lsp-file-operations' file-operation capabilities (rename-fixes-imports — capability half; event half in `filetree.lua`, see [Design Decisions](#design-decisions) → "Renaming a file rewrites its imports"), `vim.lsp.enable`. Note: `rust_analyzer` is intentionally absent — rustaceanvim (`rust.lua`) owns the Rust client (see the Rust section)
- **`rust.lua`** — rustaceanvim: Rust LSP layer over rust-analyzer (started here, not in `lsp.lua`). Sets `vim.g.rustaceanvim` before `packadd` — rustup `server.cmd`, clippy-on-save, codelldb DAP auto-detect; buffer-local Rust keymaps on `FileType rust` (`<leader>cR` runnables, `<leader>cm` expand macro, `<leader>dR` debuggables, `K`/`<leader>ca` grouped hover/actions)
- **`debugging.lua`** — nvim-dap + nvim-dap-ui + nvim-nio: debug engine and docked UI (auto-opens/closes with the session), breakpoint signs, `<leader>d*` + `<F5>`/`<F9>`–`<F12>` keymaps. Named to avoid shadowing `require('dap')` / `require('debug')`
- **`testing.lua`** — neotest (extensible framework): test runner UI. Rust via rustaceanvim's adapter; `<leader>n*` keymaps (run nearest/file/last, debug nearest, summary, output)
- **`format.lua`** — conform.nvim: per-filetype formatter chains, format-on-save toggle (`<leader>tf`), manual format (`<leader>cf`)
- **`linting.lua`** — nvim-lint: CLI linters that catch what the LSP servers don't (ruff, golangci-lint, credo, yamllint, checkmake), run on save/read; lint-on-save toggle (`<leader>tl`), manual lint (`<leader>cl`). Named `linting.lua`, not `lint.lua` — the plugin's own module is `lint`
- **`statusline.lua`** — lualine: sections (mode, path, branch, diff, diagnostics, Copilot/NES activity, lsp_status, location), powerline separators, global statusline. The Copilot/NES indicator (in `lualine_x`, left of `lsp_status`) reads `sidekick.status.get()` — hidden when idle, robot glyph while the Copilot LSP is busy (NES requests flow through it), red on error
- **`session.lua`** — persistence.nvim: branch-aware session save/restore, `<leader>q*` keymaps
- **`git.lua`** — gitsigns: hunk signs, hunk navigation (`]c`/`[c`), staging/reset/blame keymaps (`<leader>h*`); satellite.nvim scrollbar with git/diagnostic/search marks; FileType autocmd for `gitcommit`/`gitrebase` adds `<leader>w` (`:write \| bd`, confirm) and `<leader>x` (`:cq`, abort with non-zero exit)
- **`gitui.lua`** — Neogit (Magit-style git dashboard) + diffview.nvim: on-demand status buffer, shell-aligned `<leader>g*` popups, `kind='tab'`, signs disabled (gitsigns owns the gutter). Named `gitui` not `neogit` to avoid shadowing the plugin's own `neogit` Lua module
- **`filetree.lua`** — nvim-tree: sidebar file tree with git status, LSP diagnostics, modified indicators, trash-on-delete; custom `on_attach` adds `l`/`h` navigation; `<leader>e` toggles tree and reveals current file. Also wires nvim-lsp-file-operations (event half — subscribes to nvim-tree's rename/move/delete events so in-tree renames rewrite imports; capability half in `lsp.lua`). (The "quit nvim when only sidebars remain" autocmd used to live here nvim-tree-only; it's now generalized to all sidebars in `autocmds.lua`.)
- **`terminal.lua`** — toggleterm.nvim: floating terminal (85% of window), `<C-\>` toggle from any mode, `<leader>Tt` discoverable alias; VS Code-style bottom panel (dedicated horizontal terminal, `<C-`>` / `<C-/>` / `<leader>Tb`, pre-warmed, hides from within); TermOpen autocmd (toggleterm only, skips sidekick) sets terminal-mode keymaps (`<Esc>` exits to normal, `<C-h/j/k/l>` navigate splits, `<C-]>` cycle next terminal)
- **`scratch.lua`** — Keymaps for the snacks.nvim scratch module: floating, persistent scratchpad keyed by cwd/branch/count (`<leader>bs` toggle, `<leader>bS` select/list). Module options live in `picker.lua`'s shared snacks setup
- **`picker.lua`** — snacks.nvim setup (the single `require('snacks').setup()` call): `picker` module global config (flex-parity layout flipping at 160 columns, frecency ranking, custom `<CR>` confirm that scrolls the cursor ~20% from the top, `<M-a>` send-to-sidekick action, `<Esc>` one-press cancel, `<C-h>` help alias, hidden-files/`node_modules` source opts) plus the `scratch` and `indent` module options (keymaps for those stay in `scratch.lua`/`keymaps.lua`)
- **`titling.lua`** — Sets `'title'`/`'titlestring'` to `<project> — <file> [+]` for iTerm2/Neovide; `<leader>ut` / `:Title <name>` sets a manual override
- **`whichkey.lua`** — which-key: group labels, explicit trigger list, yank-prefix documentation; exports `keywords` (search aliases) and a slim `tags` override table (only non-derivable extras) consumed by `pickers/keybindings.lua`
- **`pickers/keybindings.lua`** — snacks picker that walks which-key's tree to fuzzy-search all keymaps; merges in `builtins.lua` so built-in motions are searchable too; displays 4 columns: key (dynamic width), icon+group breadcrumb (dim), desc, tag pills (dim). Tags are derived from the desc prefix (`"Git hunk: Stage"` → `git hunk`) and merged with `whichkey.lua`'s small override table for non-derivable extras (rust/diff/debug/lsp/ai cross-references); a derived tag that just repeats the row's own group breadcrumb is hidden from the pills (still searchable)
- **`builtins.lua`** — Curated built-in normal-mode commands (motions, scroll, jumps) consumed by `pickers/keybindings.lua` since nvim has no API to enumerate built-ins
- **`autosave.lua`** — auto-save.nvim: triggers on BufLeave/FocusLost (immediate) and InsertLeave/TextChanged (debounced 1s); excluded filetypes: oil, snacks_picker_input, mason, gitcommit, gitrebase, harpoon
- **(mini.notify)** — mini.notify: floating notification popups for `vim.notify()` calls (outline's guard declines, etc.); `lsp_progress.enable = false` suppresses noisy `$/progress` notifications from language servers; `:Notifications` reopens dismissed ones (like `:messages` but for mini.notify). No keymaps, no dedicated config file — set up inline in `plugins.lua`
- **`ai.lua`** — sidekick.nvim setup: NES (Copilot LSP next-edit suggestions) + CLI integration (Claude, Copilot). snacks as picker, right-split layout
- **`themes.lua`** — Theme registry (all theme plugins, variants, setup functions, overrides), persistence to `stdpath('data')/theme.txt`, `apply()` and `all_variants()`
- **`pickers/theme.lua`** — Custom snacks picker for live theme preview with restore-on-cancel
- **`spell.lua`** — Spell helpers: `add_word()` wraps `zg` to skip duplicates before appending to the personal dictionary
- **`utils.lua`** — `gh()` URL builder, async nvim update check via Homebrew, `confirm()` floating yes/no popup for destructive keymaps (`<leader>qq`/`<leader>ad`; single-keypress `y` confirms, anything else — `n`/`q`/`<Esc>`/`<CR>`/losing focus — is No)
- **`buffers.lua`** — Shared buffer classification: `special_filetypes` registry + `is_special(buf)` — "is this a non-code panel/terminal/CLI buffer?" Canonical home for the guard used by `<leader>o`/`<leader>O` (outline.lua) and `<leader><leader>` (keymaps.lua). Also a narrower `sidebar_filetypes` + `is_sidebar(buf)` (docked nav panels only — a strict subset that excludes terminals/CLI), used by the sidebar auto-quit autocmd
- **`yank.lua`** — Yank helpers: relative/absolute paths, Claude @-references, GitHub permalinks
- **`neovide.lua`** — Neovide GUI-only config (gated by `vim.g.neovide`): animation tuning, `option_key_is_meta = 'both'` so `<M-...>` keymaps work, proxy icon, floating corner radius, hide-mouse-when-typing, plus `<D-c>`/`<D-v>`/`<D-s>` clipboard/save and `<D-=>`/`<D-->`/`<D-0>` zoom keymaps. Startup-time settings (fork, frame, title-hidden, font) live in `neovide.toml` instead, since Neovide reads them before nvim launches.

### Plugin loading pattern

`plugins.lua` calls `vim.pack.add()` to register and download all plugins.
Each feature file then calls `vim.cmd.packadd('plugin-name')` to load its own
dependencies at the right time. Where order matters (e.g. `lsp.lua` does
`packadd` for mason -> mason-lspconfig -> lspconfig in dependency order),
the file handles sequencing itself.

Plugin versions are pinned in `nvim-pack-lock.json` (commit SHAs). Commit
this file after updating plugins to keep versions consistent across machines.

### Load order

From `init.lua`: configs -> autocmds -> plugins -> picker -> treesitter_context ->
outline -> structural_select -> keymaps -> completion -> lsp -> rust -> debugging ->
testing -> ai -> format -> linting -> statusline -> session ->
git -> gitui -> terminal -> scratch -> titling -> whichkey -> autosave -> filetree -> neovide.

`rust` must precede `testing` (`testing.lua` does `require('rustaceanvim.neotest')`,
which needs rustaceanvim on the runtimepath).


## Design Decisions

### Why vim.pack over lazy.nvim

This config uses `vim.pack` (nvim 0.12 native package manager), not
lazy.nvim. All plugins load eagerly at startup. This is a deliberate choice
-- manual lazy-loading via autocmds is possible but adds complexity
(boilerplate per plugin, ordering issues, silent failures, scattered logic)
that isn't worth it for the current plugin count.

If startup ever becomes slow, check `nvim --startuptime /tmp/startup.log`
before adding lazy-loading machinery.

### Re-source safety

The config guards against issues from re-sourcing (`:source %`, `:luafile`,
or config reloads):

- **Timers** use globals with stop-before-create: `if _G._checktime_timer then _G._checktime_timer:stop() end` before creating a new one. Prevents timer leaks on re-source. `ai.lua`'s `_sidekick_prewarm_timer` follows the same pattern, plus self-closes once it fires (it's a re-schedulable one-shot, not a repeating timer), plus an identity guard in the fire callback (`_G._sidekick_prewarm_timer ~= timer → return`): the uv fire and the scheduled callback are a main-loop hop apart, so a cancel + re-arm landing in that gap (a `<leader>qs` at the wrong instant) would otherwise let the stale callback close the *replacement* timer and fire early. Copy all three parts when adding a cancellable one-shot.
- **Autocmds** use `nvim_create_augroup` with `clear = true`. The augroup is wiped before re-adding its autocmds, so re-source never duplicates handlers.
- **Comma-list options** that append (e.g. `diffopt` in `configs.lua`) filter out their own prior value before re-adding it, so re-sourcing doesn't accumulate duplicate entries (`linematch:60,linematch:60,…`).
- **Append-only event subscriptions** that can't dedup (e.g. nvim-tree's `api.events.subscribe`, used by the lsp-file-operations wiring) are guarded by a run-once global flag (`filetree.lua`'s `_lsp_file_ops_setup`), so re-sourcing doesn't stack duplicate handlers that fire twice per event.

### Startup stagger timeline

Several eager background tasks are deliberately staggered across the first
seconds of a session so no single window absorbs every process spawn —
especially the `<leader>qs` restore window, where claude + shells + LSP
indexing used to land together (full rationale and measurements:
`plans/nvim-startup-performance.md`). The delays were chosen *relative to
each other*; this table is the one place they're visible together. Adding a
new deferred task or pre-warm? Slot it consciously against these and update
this table in the same change.

| Fires at | Task | Owner |
|----------|------|-------|
| 2000ms, then every 2s | First all-buffer `checktime` sweep, then steady poll | `configs.lua` |
| 2000ms | Shell pre-warms (toggleterm float + bottom panel) | `terminal.lua` |
| 3000ms, restore-aware | Claude CLI pre-warm (sidekick) | `ai.lua` |
| 5000ms | Neovim update check (`brew info` spawn) | `configs.lua` |
| 30000ms | mason-tool-installer daily update check (`start_delay`) | `lsp.lua` |

Only the claude pre-warm is restore-aware: `PersistenceLoadPre`/`LoadPost`
cancel and re-arm its timer so it fires 3s after a restore *completes*
instead of racing it. The others accept landing near a restore because
they're cheap (shells) or fully async and debounced (update checks).

A shared "startup scheduler" abstraction for these was proposed and rejected
(2026-07 design review, recorded in `plans/nvim-startup-performance.md`):
the only non-trivial shared machinery — the restore pause/re-arm pair — has
exactly one consumer, and the other sites are bare `vim.defer_fn` calls.
Re-evaluate extraction only if a **second restore-aware task** appears, and
only after the sidekick windowless rework
(`plans/sidekick-windowless-prewarm.md` Phase D) simplifies `ai.lua`.

### Quit nvim when only sidebars remain

Closing your last code window shouldn't leave a lone nvim-tree or aerial
panel sitting there — the `QuitPre` handler in `autocmds.lua` closes any
remaining sidebar windows so nvim actually exits. It counts windows: if
`total − floating − sidebars == 1`, the single remaining normal window is the
one being quit, so the sidebars are closed. This replaced an nvim-tree-only
version in `filetree.lua`. It keys off `buffers.is_sidebar()`, which is
deliberately narrower than `is_special()`: a lone `toggleterm` is special but
must **not** trigger a quit, so terminals/CLI panels are excluded from the
sidebar list. Adding a new docked nav panel? Add its filetype to
`sidebar_filetypes` in `buffers.lua` (separate from `special_filetypes`).

### Cursor-restore rides BufReadPost

The "restore last cursor position" autocmd in `autocmds.lua` fires on
`BufReadPost` — the event for a file being *read from disk*. This is worth
knowing before adding logic near it: synthetic panels (nvim-tree, aerial,
sidekick, `:terminal`) are built in memory and never fire `BufReadPost`, so
they never reach it and need no exclusion. Disk-backed snacks scratch buffers
*can* fire it, but restoring their cursor is harmless. The only real files
deliberately skipped are `gitcommit`/`gitrebase` (always want line 1). It is
intentionally not guarded by `buftype`/`is_special()`; if a future plugin
abuses `BufReadPost` on a synthetic buffer, add a `buftype == ''` guard there
rather than reaching for the shared predicate. The in-code comment carries
the same warning for anyone editing the file directly.

### Picker state with revert-on-cancel

`pickers/theme.lua` uses this pattern: the picker mutates session state live as
the cursor moves (theme switches), but `<Esc>` reverts to the snapshot taken at
open time. On snacks this is all public API: `on_change` applies the
highlighted item live (it also fires for the initial selection, and with a
nil item when the list filters to empty — guard it), a `need_restore`
upvalue is flipped to false in `confirm` *before* `picker:close()`, and
`on_close` — which fires on every close path — restores the snapshot when
the flag is still set. New pickers that need preview-style live state
should follow the same shape.

### Why `builtins.lua` exists

`pickers/keybindings.lua` walks which-key's internal tree to enumerate keymaps.
That covers user mappings and which-key's own preset groups (operators, motions,
text objects, z/g/window/nav) but misses fundamental built-ins like `Ctrl+d`
or `gg` that are hardcoded in C and have no Lua representation. `builtins.lua`
is a manually curated list cross-referenced against `:help normal-index`,
fed into the picker so the same fuzzy search surfaces both layers.

### Capability gating

All optional LSP features are gated on
`client:supports_method('textDocument/...')`. Keymaps and features only
appear when the attaching server actually supports them. This keeps
which-key clean (no dead keymaps) and avoids errors from calling
unsupported methods.

Features gated this way: inlay hints, document highlight, codelens,
declaration, type definition, implementation.

### Reveal mode expands, never collapses

`filetree.lua`'s `update_focused_file = { enable = true }` expands the
ancestor directories of the active file on every switch and scrolls it into
view — it never collapses anything else already open. This matches VS Code's
`explorer.autoReveal` and Zed's `auto_reveal_entries`; neither auto-collapses
siblings either (confirmed against both editors' source/issue trackers). An
earlier design assumed Zed did auto-collapse and explored a "solo mode" to
match — that premise was wrong, so it wasn't pursued; nvim-tree's default
`update_focused_file` already matched the real target behavior, and
nvim-tree has no public API for "collapse only the siblings" anyway.

`renderer.highlight_opened_files = 'all'` is a separate, unrelated addition:
it highlights every file with an open buffer (not just the focused one) via
a background chip (`NvimTreeOpenedHL` linked to `ColorColumn` in
`themes.lua`, not a text color — the default links to `Special`, which
clashes with git-status text coloring). `CursorLine` was tried first but was
too low-contrast against the tree's own background in `catppuccin-latte` to
be visible.

### Renaming a file rewrites its imports

Renaming a file has two independent problems, solved by different machinery:

- **The stale buffer** — an open buffer keeps pointing at the old path, and
  re-saving it recreates the old file. Renaming *inside* nvim-tree (`r`) avoids
  this: the tree moves the file and repoints the open buffer for you. Nothing
  extra needed.
- **Broken imports** — every file that imported the old path is now wrong. Only
  the language server can fix these, and only if it's *told a rename happened*
  before it happens (`workspace/willRenameFiles` is client-initiated). This is
  what `nvim-lsp-file-operations` provides.

The plugin is wired in **two halves that are useless apart** — keep them in
sync (grep `lsp-file-operations`):

- **Capability half** (`lsp.lua`) — merges the plugin's `default_capabilities()`
  onto the `'*'` `vim.lsp.config` so every server advertises willRename/didRename
  (also create/delete). Done via deep-extend, not a plain `capabilities =`
  assignment, so it layers with blink.cmp's own `'*'` completion capabilities
  instead of clobbering them (disjoint subtrees: `workspace.fileOperations` vs
  `textDocument.completion`).
- **Event half** (`filetree.lua`) — `require('lsp-file-operations').setup()`,
  which subscribes to nvim-tree's rename/move/delete events and fires the LSP
  requests. Must run *after* `nvim-tree.setup()` (it hooks the tree's event
  API). Without the capability half it still runs but every server returns
  nothing, so it no-ops silently — that's the failure mode to remember if
  renames stop fixing imports.

**Only renames done inside nvim are caught.** An external `git mv` never
announces the rename to nvim (from the outside a rename is indistinguishable
from a delete-plus-create), so no editor — this config or VS Code — can
auto-rewrite imports for it. The server will still *flag* the now-broken
imports as diagnostics once it re-indexes; you fix those by hand. The
takeaway: to get automatic import fixing, rename via the tree (`r`), not from
the shell.

Correctness of the rewrite is the language server's, not the plugin's — the
plugin only relays the workspace-edit the server returns (rock-solid with
`ts_ls`; only as good as the server elsewhere). Those edits land in files you
don't have open, *outside* your undo tree, so `u` won't revert them — git is
the safety net. Glance at `git diff` after a rename before committing.

Two upstream caveats worth knowing (neither is our wiring): the `willRename`
request is sent **synchronously**, bounded by the plugin's timeout (~10s), so a
hung server can briefly block the rename. And the pinned rev still calls the
deprecated `vim.lsp.get_active_clients()`, so the *first* in-tree rename of a
session prints a one-time deprecation warning — harmless on 0.12.4, but it will
hard-break whenever nvim removes the stub. Watch the pin / upstream for a fix
(this config is otherwise strict about deprecations).

### Special/sidebar windows need pinning

Any plugin that owns a persistent, special-purpose window (a file tree,
outline, terminal panel, test summary, etc.) is vulnerable to a stray `:e`,
`gf`, or buffer-jump landing in that window and hijacking it — the window
then shows an unrelated file instead of the tree/outline/panel, and looks
broken until closed and reopened.

`stickybuf.nvim` (`plugins.lua`) fixes this globally: it pins special windows
by filetype/buftype so foreign buffers get rerouted to the nearest normal
window instead. It already has built-in support for `nvim-tree`, `aerial`,
`toggleterm`, and `neotest` (see its README's "Plugin support" list) — nothing
extra to configure for those. **When adding a new plugin that opens its own
persistent window, check that list first**; if the plugin isn't covered, wrap
`get_auto_pin` in `setup()` to add it on top of the built-in defaults (see
`plugins.lua`'s `sidekick_terminal` entry, added because sidekick's CLI
filetype isn't in stickybuf's built-in list) rather than leaving the new
sidebar unprotected. (A `BufEnter` + `winfixwidth`/`winfixheight` autocmd
calling `stickybuf.pin()` is the README's alternative recipe for one-off,
conditional pinning that doesn't fit the filetype-list model.)

Note stickybuf only protects the window from being hijacked *by* a foreign
buffer — it doesn't stop you from deliberately switching *to* a special buffer
(e.g. via the alternate-buffer register). `<leader><leader>` in `keymaps.lua`
guards against that separately, using `buffers.is_special()` (see below) to
skip non-code buffers before jumping.

### Non-code buffer exceptions need a shared predicate

Several features need to answer "is this buffer a real code/text buffer, or a
special panel/CLI?" — the alternate-buffer jump above, and toggles like
`<leader>o`/`<leader>O` (outline.lua) that are meaningless from a terminal or
the sidekick CLI. This used to be a hand-rolled filetype list
inlined at each call site (and one such list was actually missing entries).
`buffers.lua` is now the single home for this: a `special_filetypes` registry
(`aerial`, `NvimTree`, `toggleterm`, `sidekick_terminal`) plus
`is_special(buf)`, which also treats `buftype == 'terminal'`/`'prompt'` as
special. New panel/terminal plugins register their filetype here (see
CLAUDE.md "Non-code buffer exceptions").

Two deliberate boundaries:

- **`buftype == 'nofile'` is NOT treated as special** — it over-matches
  (dashboards, Neogit/diffview, quickfix, help all use it too), so it's left
  out rather than risk silently capturing buffers no one meant to exclude. One
  consequence: `<leader>o` pressed from one of those `nofile` buffers doesn't
  decline — aerial's `attach_mode = 'global'` just shows the outline for
  whichever code buffer was last focused. Accepted, not a bug.
- **`autosave.lua`, `statusline.lua`, and `git.lua`'s satellite scrollbar keep
  their own separate exclusion lists** and deliberately do NOT route through
  `is_special()` — they're answering different questions ("should I save
  this", "is this a dashboard", "hide the scrollbar here"), not "is this a
  code buffer". Autosave's list, for instance, includes `gitcommit`/
  `gitrebase` — editable code buffers, not panels, just ones you don't want
  auto-saved mid-message. Folding these onto one shared list would couple
  unrelated concerns: adding a filetype for one consumer's benefit would
  silently change behavior for the others.

`outline.lua`'s guard has two built-in exemptions: `aerial` and `NvimTree` are
both in the registry (needed so the alt-buffer jump skips them), but
`<leader>o`/`<leader>O` explicitly exempt both `filetype == 'aerial'` and
`filetype == 'NvimTree'` from their own guard — see "File tree and outline
swap into each other" below for why. When adding a similar code-only-keymap
guard for a toggle that owns its own registered panel, apply the same kind of
exemption for that panel's own filetype.

### File tree and outline swap into each other

`<leader>e` (file tree) and `<leader>o` (outline) both want the true left
edge of the tabpage (aerial's `placement = 'edge'`, see "Special/sidebar
windows need pinning" above) — without coordination they'd stack side by
side instead of one replacing the other. Both keymaps check the other
plugin's visibility before opening:

- `outline.lua`'s `<leader>o`: if aerial isn't already open (i.e. this press
  is going to open it), close the file tree first via
  `nvim-tree.api`'s `tree.is_visible()`/`tree.close()`.
- `keymaps.lua`'s `<leader>e`: symmetric — if the tree isn't already visible,
  close aerial first via `aerial.is_open()`/`aerial.close()`.

Each check only fires on the *opening* edge of that key's own toggle —
closing one panel never reaches into the other. This is what makes the
sidebars swap: pressed from inside the file tree, `<leader>o` closes the tree
and opens the outline (and vice versa for `<leader>e` from inside the
outline), while pressing a key from a plain code buffer just toggles that
one panel normally.

This is why `NvimTree` must be exempted from `outline.lua`'s `is_special`
guard (previous section) — without the exemption, pressing `<leader>o` from
inside the file tree would hit the guard's notify-and-decline path instead of
reaching the swap logic. Terminal and sidekick CLI buffers are deliberately
**not** exempted: there's no "other panel" for a terminal to swap into, so
`<leader>o` pressed there still just declines.

No shared "sidebar coordination" module was introduced for this — it's a
symmetric pair between exactly two plugins, each already owning its own
keymap file, so the check lives directly in both `outline.lua` and
`keymaps.lua` rather than behind a new abstraction.

### Panels stop at their last entry

The file tree and outline are lists, not documents: scrolling a 19-entry tree
until three files sit at the top and twenty blank rows fill the rest is just
dead space. Two separate mechanisms are needed, and conflating them cost this
config a commit that did nothing at all (`38a7c0a`, since reverted):

**`scrolloff` does not stop scrolling past the last line.** It has no effect at
EOF — dead rows below the last entry are identical with `scrolloff` at 0 and at
10. The only thing that stops it is clamping the view, which is what the
`WinScrolled` handler in `autocmds.lua` does: it pins `topline` to at most
`line_count - winheight + 1`, so the last entry can never rise above the bottom
row. It keeps its own two-entry filetype list rather than reusing
`buffers.lua`'s `sidebar_filetypes` — that list answers "is this a docked
sidebar" for the quit handler, and registering a future panel there shouldn't
silently opt it into scroll clamping.

**What `scrolloff`/`sidescrolloff` *do* fix** is the padding: `sidescrolloff = 8`
leaves phantom columns to the right of the longest filename, and `scrolloff = 10`
pulls the list out from under the cursor near the panel edges. Both are set to
`0` per panel — see the next section for the trap in *how*.

### Window options for a panel must be set by window id

A `FileType` autocmd that sets `vim.wo.scrolloff = 0` for a panel looks obviously
correct and is silently a no-op for nvim-tree. `vim.wo` writes to whichever window
is **current at that instant**, and nvim-tree sets its buffer's filetype while the
buffer is displayed in *no* window — so `FileType` fires inside Neovim's
`aucmd_win`, the scratch window Neovim temporarily switches to for events on
undisplayed buffers (`win_gettype() == 'autocmd'`). The write lands there and dies
with it; the real tree window, created afterwards, keeps the global value.

So set window options from a hook that runs **after** the panel's window exists,
and address that window **by id**:

- `filetree.lua` subscribes to nvim-tree's `Event.TreeOpen` (dispatched after
  `open_window()`) and writes `vim.wo[api.tree.winid()]`.
- `outline.lua` uses aerial's own `layout.win_opts`, which aerial applies by
  window id on every open — so it survives close/reopen and new tabs for free.

Prefer the plugin's own window hook when it has one. Reach for an autocmd only
when it doesn't (nvim-tree), and never assume `FileType` runs in the window you
think it does.

### Nested nvim routes into the parent (flatten.nvim)

Shells inside an nvim-owned terminal (toggleterm, the sidekick CLI) inherit
`$NVIM`. When something there runs `nvim file` — or `$EDITOR` fires for
`git commit` — flatten.nvim (configured in `plugins.lua`) intercepts the
child process and opens its buffer in the *parent* instance instead of
nesting an editor inside a terminal window. Pieces that make this work:

- **`block_for` gitcommit/gitrebase** — for git editor buffers the guest
  process stays alive until the buffer is deleted, so git sees the edit
  complete. `git.lua`'s `<leader>w` confirm map ends with `bwipeout`, which
  is what unblocks the guest.
- **Float handling** — flatten's `pre_open`/`post_open` hooks snapshot and
  close any open toggleterm floats, then restore them when the edit is done.
  All of it runs through `vim.schedule` because opening/closing floats
  synchronously during buffer transitions raises E1159.
- **`should_nest` via `NVIM_NEST=1`** — escape hatch: prefix a command with
  `NVIM_NEST=1` to genuinely nest instead of routing to the parent.
- **`nvim-editor`** (zsh package) is just `exec nvim "$@"` — the routing
  intelligence lives here, in the host, not in the shim.
- **claude-nvim** (zsh package) deliberately *defeats* flatten with
  `env -u NVIM` for its isolated headless runs — a bare `nvim +qa` from a
  Claude session would otherwise be routed to, and quit, the live editor.

### Synthetic sidebar buffers can't be session-serialized

`mksession` serializes a window by the *file* its buffer points at. Aerial's
outline buffer and nvim-tree's explorer buffer have no backing file, so a
saved session restores their windows as bare `enew` scratch buffers — junk
blank splits where the panels used to be. `session.lua` closes both
(`aerial.close_all()`, `api.tree.close_in_all_tabs()`) in persistence's
`PersistenceSavePre` hook so the synthetic windows are simply absent from the
saved layout; you reopen them with `<leader>o` / `<leader>e` on demand. Any
future plugin owning a synthetic sidebar buffer needs the same
close-before-save treatment.

(nvim-tree was originally left out of this hook on the unverified assumption
it was "handled some other way" — it wasn't, and hit the same blank-buffer
bug. Lesson: verify each panel individually, don't extrapolate from the one
that was actually tested.)

**Closing the window isn't enough — the hook also wipes stale `NvimTree_N`
buffers by name.** A session saved *before* the close-before-save hook existed
baked in a `badd NvimTree_N` line. On restore that recreates a buffer named
`NvimTree_N` as a plain *listed* buffer with an empty filetype (not a live
nvim-tree buffer), so `tree.close_in_all_tabs()` never touches it and
`mksession` re-records it on every quit — a self-perpetuating loop that
outlives the window-close fix, and which nvim-tree's `NvimTree_*` name-matching
later latches onto (the tree "reappearing" on session restore). So `session.lua`
additionally deletes any buffer whose name matches `NvimTree_%d+$` in the same
hook. Pre-existing session files self-heal on their next clean quit once this
runs; a session already corrupted this way can also be fixed by hand-deleting
its `NvimTree_N` line.

We deliberately **don't** remember aerial's open state and auto-reopen it. The
tempting way — a session-baked global (`let g:AerialWasOpen` via
`sessionoptions+=globals`) — has a broad side effect: `globals` isn't scoped to
one flag, it serializes *every* qualifying (capitalized-name, String/Number)
global into every session file and restores them on load, so any unrelated
plugin global gets its stale value resurrected on each restore. Not worth it for
a one-keystroke panel. (See `session.lua`'s posterity comment for the full
rationale, including why the flag would've had to be stored `0`/`1` rather than
a boolean.)


## Keymap index

All keymaps have `desc` strings. To discover them:
- `<leader>?` shows all global mappings via which-key
- which-key popup appears after 300ms on `<leader>`, `g`, `[`, `]`
- `<leader>sk` fuzzy-searches every keymap (including built-ins)
- `:map` / `:nmap <leader>` for the full raw list

Which-key uses an explicit trigger list (see `whichkey.lua`). If you add a
new single-char group in `wk.add()`, add its trigger too.

Visual-mode maps use `'x'` (visual-only), never `'v'` (visual **and**
select) — blink.cmp's LSP snippet placeholders land in select mode, where
typing should replace the placeholder with literal text; a `'v'` mapping
would hijack that keystroke instead.

### By prefix

Each feature's full keymap table lives in its own Part 2 section (linked
below) next to the prose that explains it — this table is just an index to
get you there, plus the *defined in* file for a quick source jump.

| Prefix | Purpose | Defined in | Full list |
|---|---|---|---|
| `<leader>s*` | Search / pickers (snacks) | keymaps.lua, `pickers/*.lua` | [Picker (snacks.nvim)](#picker-snacks) → Keymaps |
| `<C-\>`, `<leader>T*` | Terminal (toggleterm) — own prefix so gitsigns/LSP buffer-local `<leader>t*` toggles can't shadow it | terminal.lua | [Terminal (toggleterm.nvim)](#terminal) |
| `<leader>p*`, `gd`/`gD`/`gy`/`gri`/`grr` | LSP goto / peek floats | lsp.lua | [LSP](#lsp) → Keymaps |
| `<leader>ca`/`ce`/`cd`, `K`, `<C-s>` | LSP hover / actions / diagnostics | lsp.lua | [LSP](#lsp) → Keymaps |
| `<leader>o`/`O`, `]a`/`[a`, `zh` | Symbol outline (aerial) | outline.lua | [Outline (aerial)](#outline-aerial) |
| `<leader>h*` | Git hunk stage/reset/blame | git.lua | [Git (Neogit)](#git-neogit) → Which git tool to use |
| `<leader>g*` | Neogit popups | gitui.lua | [Git (Neogit)](#git-neogit) → Opening it |
| `<leader>v*` | Diffview entry points | gitui.lua | [Reviewing diffs](#reviewing-diffs) → Command reference |
| `<leader>a*`, `<C-.>`, `<Tab>` | AI (sidekick CLI + NES) | ai.lua | [AI (sidekick.nvim)](#ai-sidekick) |
| `<leader>c*` (Rust ft), `K` (Rust ft) | Rust actions | rust.lua | [Rust](#rust) → Keymaps |
| `<leader>d*`, `<F5>`-`<F12>` | Debug (nvim-dap) | debugging.lua | [Rust](#rust) → Keymaps (Debug table) |
| `<leader>n*` | Test (neotest) | testing.lua | [Rust](#rust) → Keymaps (Test table) |
| `<leader>e` | File tree toggle | filetree.lua | [File Explorer (nvim-tree)](#file-explorer) |
| `<leader>tf`/`cf` | Format-on-save toggle / manual format | format.lua | [Format-on-save](#format-on-save) |
| `<leader>tl`/`cl` | Lint-on-save toggle / manual lint | linting.lua | [Linting (nvim-lint)](#linting-nvim-lint) |
| `<leader>us`/`uc` | Strip whitespace / reflow pasted text | keymaps.lua / edit.lua | [Editing utilities](#editing-utilities) |
| `<D-…>` (Cmd keys) | Neovide-only macOS shortcuts | neovide.lua | [Neovide](#neovide) |
| `<leader>tz`, `]s`/`[s`, `zg`, `z=`, `1z=`, `zw` | Spell checking | built-in + spell.lua | [Spell checking](#spell-checking) |
| `<leader>tg` | Toggle indent guides + current-scope highlight | keymaps.lua (options in picker.lua) | [Indent guides (snacks.nvim)](#indent-guides) |
| `<leader>q*` | Session save/restore | session.lua | [Session (persistence.nvim)](#session) |
| `<Tab>`/`<S-Tab>`/`<CR>`/`<C-u>`/`<C-d>`/`<C-space>`/`<C-e>` (completion menu) | Autocompletion | completion.lua | [Autocompletion (blink.cmp)](#autocompletion) |
| `<leader>ut` / `:Title` | Window/tab title override | titling.lua | [Window/tab title](#window-tab-title) |
| `y`/`Y`/`d`/`x`/`c`/`dd`, `"+d` | Clipboard split | keymaps.lua | [Clipboard split](#clipboard-split) |
| `<M-o>`/`<M-i>` | Structural (treesitter) selection grow/shrink | structural_select.lua | [Structural selection](#structural-selection) |

### Global keymaps

Keys with no single feature section of their own — mostly `keymaps.lua`:

| Key | Action | Defined in |
|---|---|---|
| `H` / `L` | Previous / next buffer | keymaps.lua |
| `<Esc>` (normal mode) | Close any floating windows (hover, peek, diagnostics) and clear search highlights | keymaps.lua |
| `q` (in help/quickfix windows) | Close the window — buffer-local, auto-mapped; skips any buffer that already binds `q` | autocmds.lua |
| `:Q` | Quit all (`qa`) | keymaps.lua |
| `<leader><leader>` | Alternate buffer (skips non-code buffers, see `buffers.lua`) | keymaps.lua |
| `<leader>bd` | Close buffer, keep split (via mini.bufremove) | keymaps.lua |
| `<leader>bo` | Close all other listed buffers (skips modified and special/non-code buffers, reports counts) | keymaps.lua |
| `<leader>qq` | Quit all (`:qa`, behind a floating confirm popup — `y` confirms, anything else is No) — grouped under the `Session/Quit` which-key label alongside `<leader>qs/qS/ql/qd` (see [Session](#session)) | keymaps.lua |
| `<C-h/j/k/l>` | Split navigation | keymaps.lua |
| Visual-mode indent | Indent selection, keeps it selected for repeat | keymaps.lua |
| `<leader>td` | Toggle diagnostics (virtual_text + signs) | keymaps.lua |
| `<leader>ts` | Toggle symbol-picker scope (workspace / buffer-only) | keymaps.lua / `pickers/symbols.lua` |
| `<leader>ta` | Toggle AI completions globally (inline ghost text + NES) | keymaps.lua |
| `yp` / `yc` / `yu` | Yank relative path / Claude @-reference / GitHub permalink | keymaps.lua / yank.lua |
| `<leader>uo` / `:Typora` | Open the current file in the Typora app (saves pending changes first) | keymaps.lua |
| `jj` / `jk` (insert mode) | Exit to normal mode | keymaps.lua |
| `<M-a>` (in any picker) | Send selection(s) to the AI CLI | see [AI (sidekick.nvim)](#ai-sidekick) |

Toggling a comment has no dedicated `<leader>t*` map — use nvim's native
`gc` (operator, e.g. `gcip`) / `gcc` (current line), which are shorter and
already which-key-discoverable under the `g` group.


# Part 2: Reference

## LSP

### How LspAttach works

`vim.api.nvim_create_autocmd('LspAttach', ...)` fires once per (client,
buffer) pair. It early-returns if the client is nil (guard against detach
race). Optional features and keymaps are capability-gated (see above).
Universally supported keymaps (definition, rename, code action, references)
are always mapped.

### Keymaps

Buffer-local, set on `LspAttach` (from `lsp.lua`). Each *jump* map has a *peek*
counterpart under `<leader>p` that opens the **same target in a scrollable float**
(goto-preview) instead of moving the main window — VS Code / GoLand-style peek.
Peek is additive; jumps are unchanged.

| Jump | Peek | Target |
|---|---|---|
| `gd` | `<leader>pd` | Definition |
| `gy` | `<leader>pt` | Type definition |
| `gri` | `<leader>pi` | Implementation |
| `grr` | `<leader>pr` | References (opens a picker, then peeks) |
| `gD` | — | Declaration |
| — | `<leader>pq` | Close all open peek floats |

`gy`/`gri` (and their `pt`/`pi` peeks) and `gD` are capability-gated — they only
map when the server supports the method. `gd`/`gD`/`gy`/`gri`/`grr` all use
snacks pickers (falling back to the plain LSP handler if snacks fails to
load) — a single result still jumps straight there (via the pickers'
`auto_confirm`, so it lands ~20% from the top like every picker jump), but a
server resolving to several targets (e.g. a trait method with multiple
impls, or a type with several bounds) shows a picker instead of dumping into
the quickfix list.

**Hover, actions & diagnostics:**

| Keymap | Action |
|---|---|
| `K` | Hover — docs/type/signature float (not the source; use peek for that) |
| `<C-s>` (normal + insert) | Signature help |
| `<leader>th` | Toggle auto-hover on CursorHold |
| `<leader>ca` | Code action |
| `grn` (nvim core default, not remapped) | Rename symbol |
| `<leader>ce` | Show diagnostic float under cursor |
| `<leader>cd` | Diagnostic list (loclist) |
| `[d` / `]d` | Previous / next diagnostic (nvim default; supports a count) — auto-opens a cursor-scoped float on the diagnostic it lands on, since virtual text/signs are off |
| `<leader>ti` | Toggle inlay hints |

### Adding a new LSP server

Example: adding `clangd` (C/C++).

1. **`lsp.lua` -- `mason-tool-installer`'s `ensure_installed`** -- add `'clangd'`
   so Mason installs (and later auto-updates) it. This list is now the single
   source of truth for installing/updating every Mason package, servers
   included -- mason-lspconfig no longer carries its own `ensure_installed`
   (see "Things to watch out for" -> Mason auto-update).

2. **`lsp.lua` -- `vim.lsp.enable()`** -- add `'clangd'` to the list.
   This is the single source of truth for active servers (`automatic_enable`
   is set to `false` in mason-lspconfig).

3. **`lsp.lua` -- `vim.lsp.config`** -- (optional) add a config block if
   non-default settings are needed. Place it before the `vim.lsp.enable()` call.

4. **`plugins.lua` -- treesitter `ensure_installed`** -- add the parser(s)
   (e.g. `'c', 'cpp'`).

5. **Verify** -- restart nvim -> `:Mason` (confirm installed) -> open a file ->
   check statusline for server name -> `:checkhealth lsp`.

### Removing a server

Reverse the steps: remove from `vim.lsp.enable()`, remove from
`ensure_installed`, delete any `vim.lsp.config()` block, optionally remove
the treesitter parser and run `:MasonUninstall server_name`, restart nvim.

### Notes

- **Server name** must be the lspconfig name (e.g. `lua_ls` not
  `lua-language-server`). These sometimes differ from the Mason package name.
- **LspAttach fires automatically** -- all keymaps, inlay hints, document
  highlight, and codelens apply to the new server with zero extra config.
- The **`settings` key structure** varies per server: gopls uses
  `settings.gopls`, rust-analyzer uses `settings['rust-analyzer']`, lua_ls
  uses `settings.Lua`. Check the server's documentation.

### Things to watch out for

- **`automatic_enable = false`** -- mason-lspconfig does NOT auto-enable
  installed servers. The explicit `vim.lsp.enable()` list in `lsp.lua` is
  authoritative. If you add a server to `ensure_installed` but forget
  `vim.lsp.enable()`, it will be installed but won't attach.

- **`<C-s>` terminal freeze** -- terminal XOFF flow control captures this
  keystroke. `stty -ixon` in `.bashrc`/`.zshrc` fixes it.

- **Inlay hints** -- gated on `textDocument/inlayHint`. gopls has all hint
  categories off by default -- this config enables them all explicitly.
  `<leader>ti` toggles per-buffer.

- **Diagnostics default to minimal** -- virtual_text and signs are OFF.
  `<leader>td` toggles them on. Underline is always on.

- **Mason auto-update** -- `mason-tool-installer`'s `ensure_installed` (in
  `lsp.lua`) covers every Mason package, servers included; mason-lspconfig
  only enables them now. `auto_update` + `debounce_hours = 24` re-checks for
  updates at most once/day on startup and updates in place, async.
  `start_delay = 30000` pushes that check 30s past startup so it doesn't
  collide with session restore or LSP indexing. The plugin notifies
  per-package on install/failure itself; `:Mason` still works for manual
  inspection/retry.

- **Document highlight** -- gated on `textDocument/documentHighlight`.
  Driven by `updatetime` (300ms) in `configs.lua`.

- **Codelens** -- gated on `textDocument/codeLens`. `grx` (nvim 0.12
  default) runs the codelens under cursor.

- **Format-on-save** is OFF by default — auto-formatting rewrites the buffer
  on every `:w`, which clears NES suggestions and inline completions mid-flow.
  `<leader>tf` toggles it on globally; `<leader>cf` formats manually at any
  time. Configured filetypes: Python, Go, Rust, JS/TS/JSON/YAML via
  conform.nvim; Lua is formatted by lua_ls via LSP fallback.
  `vim.g.disable_autoformat` (global) and `vim.b.disable_autoformat`
  (per-buffer) are the underlying flags. Run `:ConformInfo` to see which
  formatter binaries are detected on `$PATH`.

- **Nvim 0.12 built-in keymaps** -- `K` (hover), `[d`/`]d` (diagnostic jump),
  `grn` (rename), `gra` (code action), `grx` (codelens) are nvim defaults,
  not mapped in this config. `grr`/`gri` are overridden to use snacks pickers.

- **Peek floats (`<leader>p*`)** — VS Code / GoLand-style peek via
  goto-preview; see the LSP *Keymaps* table for the jump/peek pairs. Tuned in
  `lsp.lua`: `focus_on_open = true` (cursor enters the float to scroll
  immediately) and `dismiss_on_move = false` (stays open while you look around)
  — flip either if the float feels too eager.

- **`<C-.>` terminal compatibility** — `<C-.>` (focus sidekick CLI)
  requires a terminal that sends CSI u sequences (kitty, iTerm2 with CSI u,
  WezTerm, Ghostty). macOS Terminal.app and some other terminals do not
  transmit `<C-.>` — use `<leader>ai` as a cross-terminal fallback.

- **Shift+Enter → newline in terminals** — inside `<C-\>` / `<leader>Tt`
  terminals (and the bottom panel), `<S-CR>` sends a linefeed so CLIs like
  Claude/Codex insert a newline instead of submitting (`terminal.lua`).
  This only works if the terminal transmits Shift+Enter distinctly via CSI u.
  **In iTerm2**, enable *Settings → Profiles → Keys → General → "Report
  modifiers using CSI u"*. kitty, WezTerm, Ghostty and Neovide do it natively;
  Terminal.app cannot. `<leader>aa` (sidekick) needs no `<S-CR>` map of its own
  — Claude reads the key directly — but it shares the same prerequisite: the
  terminal must transmit Shift+Enter distinctly.

- **Mouse back/forward buttons** — browser-style jumplist navigation
  on the side buttons. Two paths reach the same result:

  1. **Logi Options+ keystrokes** (primary, works in iTerm2 and
     Neovide). Open Logi Options+ → select mouse → **Buttons** → add
     per-app assignments for **iTerm2** and **Neovide**:
     - Back side button → **Keystroke Assignment** → `Ctrl+O`
     - Forward side button → `Ctrl+I` (= Tab; collides with the
       sidekick NES `<Tab>` mapping in insert mode, where it will
       insert a literal tab — assign only if you can live with that)

     Per-app scope leaves Safari/Chrome/Finder Back/Forward intact.

  2. **Raw mouse events** (fallback). `<X1Mouse>`/`<X2Mouse>` are
     mapped to `<C-o>`/`<C-i>` in keymaps.lua. iTerm2 does not
     forward these by default and Apple Terminal never will, but the
     mapping is harmless and serves as a fallback if Logi Options+
     is disabled (Neovide forwards them natively, iTerm2 only if
     manually bound under Settings → Pointer → Bindings).

  Non-Logitech mouse: use Karabiner-Elements or BetterTouchTool for
  the same keystroke remap.

- **Ctrl+click → LSP go-to-definition** (VS Code-style). Mapped in
  keymaps.lua via `<C-LeftMouse>`: places the cursor at the click,
  then calls `vim.lsp.buf.definition()`. Use `<C-o>` to jump back.

  Works in Neovide out of the box. **In iTerm2**, by default Ctrl+click
  opens iTerm2's own context menu — it is not forwarded to nvim. Enable
  *Settings → Pointer → "^-Click reported to apps, does not open menu"*
  to forward it. (Right-click context menu is still available via
  right-click or the configured pointer binding.)

- **`<leader>ad` kills the session** — unlike `<leader>aa` (toggle, which
  just hides the window), `<leader>ad` calls `close()` which terminates the
  CLI process and deletes the buffer. Use `<leader>aa` to temporarily hide
  the chat; `<leader>ad` when you're done with the conversation. Guarded by
  a floating confirm popup (`utils.confirm` — single-keypress `y` confirms,
  anything else is No) — it sits one key from `<leader>aa`/`<leader>as`,
  so a typo can't silently discard a running conversation.

  With **multiple sessions** running, killing the active one (via `<leader>ad`
  or the `<leader>al` picker's `<C-d>`) repoints "active" to a *surviving*
  session — preferring the one you were last on (`<C-]>`'s alt-tab target),
  else the first by name. So a follow-up `<leader>aa` reattaches to that live
  instance rather than spawning a brand-new session; it only spawns fresh when
  no session is left alive. (Implemented by `fallback_active` in `ai.lua`,
  routed through every teardown site so the same holds when a session self-exits.)

### Troubleshooting

**Server doesn't start:**
`:Mason` -- is it installed? `:checkhealth lsp` -- any errors?
`:set filetype?` -- correct filetype? Use `:set filetype=<type>` to force it manually (e.g. `:set filetype=yaml`). Some servers need a root marker (`go.mod`
for gopls, `Cargo.toml` for rust_analyzer) to detect the project root.

**Diagnostics not visible:**
virtual_text and signs are OFF by default. `<leader>td` toggles them on.
Jumping with `[d`/`]d` auto-opens a float on the landed diagnostic, and
`<leader>ce` opens one on demand — so a message is always reachable without
turning virtual text back on.

**Completion not working:**
Check statusline for the LSP server name (is it attached?). Large projects
may take seconds for the server to initialize.

**Log inspection:**
`:lua vim.cmd.edit(vim.lsp.get_log_path())` to open the LSP log. For verbose
output, temporarily add `vim.lsp.set_log_level('debug')` to `lsp.lua`.

**Formatter not running:**
`:ConformInfo` shows configured formatters per filetype and which binaries are detected on `$PATH`. `:checkhealth conform` runs the plugin's full health check. If format-on-save is off globally, `vim.g.disable_autoformat` is `true` — use `<leader>tf` to toggle it back on.

**Useful commands:**

| Command | Purpose |
|---|---|
| `:Mason` | Server installer UI |
| `:checkhealth lsp` | Verify server attachment and config |
| `:lua vim.print(vim.lsp.get_clients())` | List active LSP clients |
| `:lua vim.print(vim.lsp.get_clients()[1].server_capabilities)` | Inspect capabilities |
| `:lua vim.cmd.edit(vim.lsp.get_log_path())` | Open LSP log file |


<a id="autocompletion"></a>
## Autocompletion (blink.cmp)

Completion engine written in Rust, set up in `completion.lua`. Sources:
LSP, file paths, snippets, buffer words. Ghost text is disabled — Copilot's
inline completion (`textDocument/inlineCompletion`) supplies its own; see
[AI (sidekick.nvim)](#ai-sidekick) → NES vs Copilot inline completion for how
`<Tab>` arbitrates between the completion menu, Copilot ghost text, and a
literal tab.

### Keymaps (inside the completion menu)

| Key | Action |
|---|---|
| `<Tab>` | Next item (see the AI section for the full priority chain when Copilot ghost text is also showing) |
| `<S-Tab>` | Previous item |
| `<CR>` | Accept selected item (falls back to normal Enter) |
| `<C-u>` / `<C-d>` | Scroll documentation popup up / down |
| `<C-space>` | Manually trigger completion |
| `<C-e>` | Cancel / close completion menu |

Signature help is enabled automatically — shows parameter hints while typing
inside `()`.

### Fuzzy matcher fallback

On first launch blink.cmp downloads a pre-built Rust fuzzy-matcher binary
(requires `curl`; see the top-level first-launch steps). If the download
fails (no internet, corporate proxy, etc.), it silently falls back to a pure
Lua implementation — no action required. To force a re-download:

```
:lua require('blink.cmp.fuzzy.download').ensure_downloaded(function() end)
```

### Commands

| Command | Purpose |
|---|---|
| `:checkhealth blink.cmp` | Verify blink.cmp and fuzzy-binary status |


## Format-on-save

conform.nvim runs CLI formatters per filetype on every `BufWritePre`
(manual `:w` and auto-save writes both). Setup lives in `format.lua`.

`formatters_by_ft[ft]` is a list of formatter names that run sequentially.
Append `stop_after_first = true` for "first available wins" (used for
prettierd → prettier so prettier doesn't run when prettierd already
formatted the buffer). Filetypes not listed fall through to
`default_format_opts.lsp_format = 'fallback'`, which calls
`vim.lsp.buf.format()` if a formatting-capable LSP is attached — this is
how Lua is formatted (by lua_ls).

### Adding a formatter for a new language

Example: adding `shfmt` for shell scripts.

1. **Install the binary** -- e.g. `brew install shfmt`. conform shells
   out, so it must be on `$PATH`. Run `:ConformInfo` to confirm
   detection after installing.

2. **`format.lua` -- `formatters_by_ft`** -- add an entry:
   ```lua
   sh = { 'shfmt' },
   ```
   For chains, list formatters in run order (e.g.
   `python = { 'ruff_organize_imports', 'ruff_format' }`). For "first
   available wins" (e.g. daemon + binary), add `stop_after_first = true`.

3. **`README.md` -- "Format-on-save tools"** -- add the install command
   so other machines can replicate.

4. **Verify** -- restart nvim -> `:ConformInfo` (formatter listed and
   binary detected?) -> open a file of that filetype, edit, `:w` ->
   confirm it formatted.

If the formatter needs non-default args or a custom command, define an
override under conform's `formatters` setup key (see `:help
conform-formatters`).

### Removing a formatter

Reverse: remove the `formatters_by_ft` entry, remove the README install
line, optionally uninstall the binary. Filetypes with no entry fall back
to LSP formatting via `lsp_format = 'fallback'`.


<a id="linting-nvim-lint"></a>
## Linting (nvim-lint)

Setup lives in `linting.lua`. nvim-lint runs CLI linters on save/read
(deliberately not InsertLeave — slow linters like golangci-lint would re-run
on every insert exit) and publishes results as regular diagnostics, flowing
into the shared `vim.diagnostic` config (`<leader>td` toggles display).

| Keymap | Action |
|---|---|
| `<leader>cl` | Lint the buffer now (works even when lint-on-save is off) |
| `<leader>tl` | Toggle lint-on-save globally — turning it off also clears nvim-lint's existing diagnostics |

**Diagnostics come from TWO subsystems, not just this one.** LSP servers
(lsp.lua) publish their own diagnostics — lua_ls, clippy via rust-analyzer,
eslint — which is why lua/rust/js/ts are intentionally absent from
`linters_by_ft`. nvim-lint covers what the LSPs don't: `ruff` (python),
`golangci-lint` (go), `credo` (elixir, via the project's `mix credo`),
`yamllint`, `checkmake`. When adding or auditing a linter, check lsp.lua too.

The `<leader>tl` toggle clears only nvim-lint's namespaces (named per linter,
e.g. "ruff") and never touches LSP-delivered diagnostics (`nvim.lsp.*`
namespaces). Per-buffer opt-out for vendored files:
`:lua vim.b.disable_lint = true`. Linter binaries install via
mason-tool-installer (lsp.lua's `ensure_installed`), except credo which runs
from the project.


## Themes

Theme configuration lives in `themes.lua`. Each theme entry has a `src`
(GitHub repo), optional `variants` (colorscheme names the plugin provides),
and optional `setup`/`overrides` for per-theme customization.

- **Persistence:** The active theme is saved to `stdpath('data')/theme.txt`
  and restored on startup. Delete the file to reset to the default
  (`catppuccin`).
- **Live picker:** `<leader>st` opens a snacks picker (`pickers/theme.lua`)
  with live preview. Scrolling applies themes in real-time; `<CR>` confirms
  and persists, `<Esc>` restores the original.
- **Background switching:** Some themes (gruvbox, solarized, oxocarbon,
  everforest, vscode) use `vim.opt.background` for light/dark instead of
  separate colorscheme names. These use virtual variant names (e.g.
  `gruvbox-light`) mapped to the real colorscheme name in `M.colorscheme`.
- **Adding a theme:** Add one entry to `M.themes` with at minimum `src`.
  Variants, setup, and overrides are optional. The theme's sources are
  automatically included in `vim.pack.add` via `M.sources`.


## Treesitter

Configured using nvim 0.12's native API — no plugin config table needed.
`nvim-treesitter` (registered via `vim.pack`) is used solely for parser
management (installing/updating parsers); highlighting and folding are
attached directly in `plugins.lua`.

- **Highlighting** — `vim.treesitter.start()` is attached per buffer via a
  `FileType` autocmd (`ts_filetypes`, derived from `ensure_installed`).
- **Folding** — AST-based via `vim.treesitter.foldexpr()`; files open fully
  expanded (`foldlevel = 99`).
- **Large files are skipped** — buffers over 50k lines or 1.5MB get neither
  highlighting nor folding attached, to avoid UI lag.
- **Auto-install on startup** — parsers missing from `ensure_installed` are
  installed the next time nvim starts. There is **no** auto-install when
  opening a file whose language isn't in that list — for those, run
  `:TSInstall <lang>` once and add the language to `ensure_installed` in
  `plugins.lua` for future machines.
- **Auto-recompile on update** — a `PackChanged` autocmd detects when
  `nvim-treesitter` itself is updated and re-runs `:TSUpdate` to recompile
  parsers against the new version.

Parser versions are pinned in `nvim-pack-lock.json` (see [Architecture](#architecture)
→ Plugin loading pattern).

### Commands

| Command | Description |
|---|---|
| `:TSUpdate` | Update all installed parsers |
| `:TSUpdate <lang>` | Update a specific parser |
| `:TSInstall <lang>` | Install a parser manually |
| `:InspectTree` | View the parsed AST for the current buffer |
| `:Inspect` | Show highlight groups under the cursor |
| `:checkhealth nvim-treesitter` | Verify installed parsers and requirements |


<a id="picker-snacks"></a>
## Picker (snacks.nvim)

Fuzzy finder for files, text search, buffers, symbols, and help —
snacks.picker, pure Lua, no compiled extension. Global setup (layout,
frecency, shared actions) lives in `picker.lua`; the custom pickers live in
`pickers/*.lua`. Replaced telescope in 2026-07 — background and decision
record in `plans/telescope-vs-snacks-picker.md`.

### Keymaps

| Keymap | Action |
|---|---|
| `<leader>sf` | Find files by name |
| `<leader>sg` | Live grep (search file contents; see the live-vs-fuzzy note below) |
| `<leader>bb` / `<leader>m` | Buffer picker (numbered rows; `<M-1>`..`<M-9>` jumps to that row; `<C-d>` deletes) — see `pickers/buffer.lua` in Architecture. `<leader>m` is a permanent alias, one key shorter |
| `<leader>sh` | Search help tags |
| `<leader>sr` | Resume last picker (query, results, and selection restored) |
| `<leader>s/` / `<leader>sb` | Fuzzy search inside current buffer |
| `<leader>so` | Recent files |
| `<leader>sm` | Modified files (git status; `<Tab>` stages/unstages) — see [Git (Neogit)](#git-neogit) → Which git tool to use |
| `<leader>ss` | Symbols (workspace) — fans query to all active LSPs; two-token prompt: first word is the name query sent to the LSP, remainder filters by file path (e.g. `render utils` finds symbols named "render" in files matching "utils"). Columns: icon, name, kind, client, path:line, source line. `<leader>ts` toggles to buffer-only mode; `<c-g>` freezes results for fuzzy refinement over all columns |
| `<leader>sd` | Symbols (document) — columns: icon, name, kind, line, source line (treesitter-highlighted); opens preselected on the symbol enclosing the cursor; type `function` / `variable` to filter by kind |
| `<leader>st` | Theme picker (live preview) — see [Themes](#themes) |
| `<leader>sk` | Keymap picker — columns: key (dynamic width), icon+group breadcrumb (dim), desc, tag pills (dim) |

**Live vs fuzzy (`<leader>sg` and `<leader>ss`):** these two are *live*
pickers — every keystroke re-runs the search (ripgrep regex for grep, an LSP
round-trip for symbols) instead of fuzzy-filtering a fixed list. In grep,
raw rg flags pass through after ` -- `: `handleRequest -- -tgo -g
'!*_test.go'` (ripgreprc custom types like `-ttest` work too — see README →
ripgrep). Press `<c-g>` to freeze the current results into the fuzzy
matcher: fzf-style operators (`'exact`, `^prefix`, `suffix$`, `!negate`,
`|` OR) and `field:value` filters (`file:lua$`, and in the symbols picker
`kind:class`, `client_name:gopls`) work there. Every other picker is fuzzy
from the start.

**Inside a picker** (press `<C-h>` in any picker for its full live keymap
list — bindings below are the daily set):

| Key | Action |
|---|---|
| Type anything | Filter results (fuzzy, or live — see above) |
| `<C-n>`/`<C-p>` or `<C-j>`/`<C-k>` | Move down / up |
| `<CR>` | Open highlighted entry — cursor line lands ~20% from the window top (custom confirm in `picker.lua`; `scrolloff=10` is the floor in short windows) |
| `<C-v>` | Open in vertical split |
| `<C-x>` / `<C-s>` | Open in horizontal split (`<C-s>` overrides the global LSP signature-help key while a picker is focused) |
| `<C-t>` | Open in new tab |
| `<Tab>` / `<S-Tab>` | Toggle multi-select on the current row, move down / up |
| `<C-q>` | Send multi-selection (or all results if none selected) to the quickfix list and open it |
| `<C-d>` | In the buffer picker: delete the highlighted buffer (or all multi-selected) |
| `<M-a>` | Send the highlighted entry (or multi-selection) to the active sidekick CLI as `path:line` refs |
| `<a-h>` / `<a-i>` | Toggle hidden / ignored files (files and grep; shown as flags in the title) |
| `<a-p>` / `<a-m>` | Toggle preview / maximize the picker |
| `<c-g>` | Toggle live ↔ fuzzy (see above) |
| `?` (normal) / `<C-h>` | Show this picker's live keymaps in a popup (`<C-h>` is a custom alias, shadowing the global left-split key while a picker is focused) |
| `<Esc>` | Close in one press, even from insert mode (custom `cancel` binding; focus returns to the launch window) |

**Multi-select workflows:**
- `<Tab>` marks an entry (a dot appears in the gutter) and moves the cursor down; `<S-Tab>` marks and moves up. Repeat to build up a set.
- With a multi-selection: `<CR>` opens them all (first into the current window, the rest as buffers); `<C-v>`/`<C-x>`/`<C-t>` fan them into splits or tabs.
- `<C-q>` sends the selection to qflist — or the entire result list when nothing is marked (handy after a grep when you want every match).
- Common pattern: `<leader>sg` → search → `<Tab>` the matches you want → `<C-q>` → `:cdo s/old/new/g | update`.

**Per-picker notes:**
- `<leader>bb`/`<leader>m` (buffer picker) — Tab a few buffers and press `<C-d>` to bulk-close them; the picker stays open.
- `<leader>sm` (gitstatus) — `<Tab>` is **overridden** to stage / unstage the file under the cursor (no multi-select in this picker); the list refreshes in place.

**Tips:**
- Both file search and live grep include hidden files/directories (e.g. `.github/`); `.git/` and `node_modules/` are excluded (source opts in `picker.lua`).
- Frecency ranking is on: files you open often (and recently) float toward the top of file-ish pickers. The store lives under `stdpath('data')`; delete it to reset.
- `<leader>sr` reopens the last picker with query and results intact — useful when you close it and want to get back.
- In the files picker, pasting `path:12:4` jumps to that line/column on `<CR>` (`file:line:col` prompt syntax).

### Commands

| Command | Purpose |
|---|---|
| `:checkhealth snacks` | Verify snacks and the picker's optional deps (sqlite, etc.) |


## Clipboard split

`y`/`Y` copy to the system clipboard, but `d`, `x`, `c`, and `dd` stay in
Neovim's default register. Visual-mode `p` pastes without clobbering the
clipboard either. This is non-standard -- most configs use
`clipboard=unnamedplus` (everything goes to system clipboard) or don't touch
it. The failure mode is silent: if you `dd` a line expecting it on your
system clipboard, you'll paste whatever was there before. Use `"+d`
explicitly when you need to cut-to-clipboard.


## Structural selection

`structural_select.lua`: Helix-style expand/shrink selection, built directly
on the core `vim.treesitter` API (no extra plugin — nvim-treesitter's
`main`-branch rewrite removed the old built-in incremental-selection module).

| Key | Action |
|---|---|
| `<M-o>` | Grow: select the smallest syntax node that strictly contains the current selection |
| `<M-i>` | Shrink: pop back to the previous (smaller) selection |

Works from normal mode too — a first `<M-o>` starts a visual selection at the
node under the cursor. State is a buffer-local stack of past ranges; it
resets automatically whenever a grow starts from a selection that doesn't
match the stack top (e.g. you moved the cursor or made a fresh selection),
so it can never go stale.


## Editing utilities

Helpers in `edit.lua`, bound in `keymaps.lua` under the `<leader>u`
(Utilities) group.

| Keymap / command | Action |
|---|---|
| `<leader>us` (normal) | Strip trailing whitespace, whole file (preserves view/jumplist) |
| `<leader>us` (visual) | Strip trailing whitespace in the selection |
| `:StripWS` | Same, over a `:range` (defaults to whole file) |
| `<leader>uc` (visual) | Reflow pasted Claude/terminal text — see below |
| `:CleanPaste` | Same, over a `:range` (defaults to whole buffer) |

**CleanPaste** normalizes text copied out of terminals/Claude Code: converts
NBSP to spaces, strips indent and `⏺` turn markers, and joins soft-wrapped
continuation lines back into paragraphs while preserving structural lines
(bullets, headings, tables, numbered items, blockquotes). The result also
lands on the system clipboard.

Gotcha (documented at the keymap): the visual `<leader>uc` mapping uses a `:`
RHS, not `<cmd>` — `:` exits visual mode first, which is what updates the
`'<`/`'>` marks before the range evaluates. Don't "modernize" it to `<cmd>`.


## Markdown

`render-markdown.nvim` (set up in `plugins.lua`) renders markdown inline as you
edit — headings, fenced code, tables, list bullets — so the many interlinked
docs in this repo (this guide, `plans/*.md`, the various `CLAUDE.md`) read
cleanly in-editor without a separate preview. For the full GUI editor, open the
current file in Typora with `<leader>uo` (see the Keymap index → Global
keymaps).

### Following links between docs

Markdown links like `[label](other.md)` are followed with native **`gf`**
("goto file") — there's no plugin for this, it's built in:

| Keys | Action |
|---|---|
| `gf` | Open the file under the cursor in the current window |
| `<C-w>f` | Open it in a horizontal split |
| `<C-w>gf` | Open it in a new tab |
| `<C-o>` | Jump back to where you were |

Put the cursor on the **path inside the parens** (the `other.md`, not the
`[label]` text) before pressing `gf`. This works with no extra config because
vim's default `path` includes `.` (the current file's own directory) and the
links in these docs are same-folder relative names that already carry the
`.md` extension — so `gf` from any `plans/*.md` resolves its sibling docs
directly. Gotcha: if the cursor sits on the link *label* instead of the path,
`gf` grabs the wrong word — move into the `(...)`.


<a id="session"></a>
## Session (persistence.nvim)

Setup lives in `session.lua`. Sessions save automatically on quit and restore
per directory; `branch = true` gives each git branch its own session, so
switching branches doesn't mix up open files.

| Keymap | Action |
|---|---|
| `<leader>qs` | Restore session for the current directory |
| `<leader>qS` | Pick from all saved sessions |
| `<leader>ql` | Restore the last session (regardless of directory) |
| `<leader>qd` | Stop saving — quit without persisting current state |

The which-key `Session/Quit` group (`<leader>q`) also holds `<leader>qq` —
quit-all behind a floating confirm popup, defined in `keymaps.lua` rather than here
since it's a plain `:qa`, not a persistence.nvim feature (see the
[Global keymaps](#global-keymaps) table).

Terminal windows are excluded from saved sessions (`sessionoptions:remove('terminal')`)
— restoring one would only re-spawn an empty shell with no scrollback, and a
restored sidekick CLI buffer wouldn't be in sidekick's runtime registry, so
`<leader>aa` could no longer manage it. Aerial's outline sidebar is also
excluded (closed before save, not restored) — see
[Design Decisions](#design-decisions) → "Synthetic sidebar buffers can't be
session-serialized".


## Spell checking

Off by default. Toggle with `<leader>tz` (US English). Built into Neovim — no plugin needed.

| Key | Action |
|---|---|
| `]s` / `[s` | Next / previous misspelled word |
| `1z=` | Accept top suggestion instantly (no menu) |
| `z=` | Open correction menu for word under cursor |
| `zg` | Add word to personal dictionary |
| `zw` | Mark word as misspelled (add to wrong-words list) |

**Personal dictionary** is stored at `nvim/.config/nvim/spell/en.utf-8.add`
inside the dotfiles repo — commit it to persist custom words (code terms,
names, jargon) across machines. `zg` appends to this file automatically.

`]s`/`[s` appear in the `[`/`]` which-key popup. `zg`, `z=`, `1z=`, and
`zw` are not in the popup (adding `z` as a trigger would add 300ms latency to
all fold and scroll commands), but all spell commands are searchable via
`<leader>sk` — type "spell", "typo", or "spelling".


<a id="window-tab-title"></a>
## Window/tab title

`titling.lua` sets `'title'`/`'titlestring'` to `<project> — <file> [+]`,
where project is the git toplevel (or cwd) basename. `<leader>ut` (or
`:Title <name>`) sets a manual override; empty input reverts to automatic.
This one nvim mechanism drives both surfaces:

- **iTerm2** — the TUI emits title escape codes for whatever `titlestring`
  evaluates to.
- **Neovide** — same value, via the `set_title` UI event (the same protocol
  Neovide already uses for its default filename-based title).

The zsh side (`title` function + `chpwd` hook in `.zshrc_config.zsh`) mirrors
this with the same auto/override behavior for when nvim isn't running, so cwd
and nvim agree. It redefines oh-my-zsh's own `title` function, so
`DISABLE_AUTO_TITLE=true` is set before `antigen apply` to stop
`termsupport.zsh`'s precmd/preexec hooks from fighting it (they still fire,
now as no-ops, since they call `title` too).

**iTerm2 preference required:** by default iTerm2 composites its own title
from Session Name + Job Name (Preferences → Profiles → General → Title —
looks like `Name (Job)`), which is why a tab running nvim shows `nvim (zsh)`
regardless of what any escape sequence sets. To make the title above actually
visible, open that Title dropdown and uncheck **Job Name** (leave **Session
Name** checked — that's the component our escape-sequence title lands in).
This is a live app preference, not a file in this repo, so it's a one-time
manual step per machine.


<a id="file-explorer"></a>
## File Explorer (nvim-tree)

Setup lives in `filetree.lua`. A sidebar file tree with VS Code-style git
and diagnostic decorations.

### Features

- **Git status** — file names are highlighted by git status (green=new,
  yellow=modified, red=deleted) with a right-aligned letter indicator
  (`M`/`S`/`U`/`R`/`D`). Directories roll up their children's status so
  you can see at a glance which parts of the tree have changes. Colors
  link to `DiagnosticOk`/`DiagnosticWarn`/`DiagnosticError` so they
  adapt to any colorscheme.
- **LSP diagnostics** — error/warn/info/hint icons next to files with
  issues. `show_on_dirs = true` propagates to parent directories.
- **Modified indicator** — buffers with unsaved changes are marked in the
  tree (`highlight_modified = 'name'` highlights the filename).
- **Open-buffer highlight** — files with a currently loaded buffer (any
  window, not just the active one) get a background highlight behind their
  icon+name (`highlight_opened_files = 'all'`, `NvimTreeOpenedHL` linked to
  `ColorColumn` — bg-only, so it doesn't recolor the text). See
  [Design Decisions](#design-decisions) → "Reveal mode expands, never
  collapses" for how this combines with auto-reveal.
- **Auto-reveal, not auto-collapse** — switching buffers expands the tree
  down to the active file and scrolls it into view
  (`update_focused_file = { enable = true }`); it never collapses anything
  else that's open. See [Design Decisions](#design-decisions) → "Reveal mode
  expands, never collapses".
- **Trash** — `D` in the tree sends files to macOS trash (`trash.cmd = 'trash'`,
  uses `/usr/bin/trash`). `d` remains permanent delete.
- **Polished prompts** — `select_prompts = true` routes rename/delete
  confirmations through `vim.ui.select` (snacks picker).
- **Rename fixes imports** — renaming (`r`) or moving a file in the tree fires
  the LSP file-operation requests via nvim-lsp-file-operations, so files that
  imported the old path get rewritten (VS Code's "update imports?" behavior).
  Only works for renames done *in the tree* — an external `git mv` can't be
  caught. See [Design Decisions](#design-decisions) → "Renaming a file rewrites
  its imports".
- **Auto-close** — a `QuitPre` autocmd closes the tree when it's the last
  non-floating window, avoiding an orphaned tree buffer.

### Keymaps

Global:

| Keymap | Action |
|---|---|
| `<leader>e` | Toggle file tree (opens and reveals current file, or closes) |

Inside the tree (buffer-local, set by `on_attach`):

| Key | Action |
|---|---|
| `l` / `<CR>` | Open file / expand directory |
| `h` | Collapse directory |
| `<C-v>` | Open file in vertical split |
| `<C-x>` | Open file in horizontal split |
| `<C-d>` | Close the buffer for the file under the cursor |
| `a` | Create file or directory (append `/` for dir) |
| `d` | Delete (permanent) |
| `D` | Trash (sends to macOS trash) |
| `r` | Rename (fixes imports in referencing files via LSP — see Features) |
| `x` / `c` / `p` | Cut / copy / paste |
| `f` | Live filter — type to narrow tree to matching filenames |
| `F` | Clear live filter |
| `W` | Collapse all directories |
| `H` | Toggle dotfiles visibility |
| `I` | Toggle git-ignored files visibility |
| `U` | Toggle custom-filtered files (`.git`, `.DS_Store`, `node_modules`) |
| `R` | Refresh tree |
| `q` | Close tree |
| `g?` | Show all nvim-tree keybindings |

### Usage notes

- The tree is a **spatial map**, not a search tool. Use `<leader>sf` (find
  files) and `<leader>sg` (grep) for search — they are faster.
- `<leader>e` always reveals the current file when opening, so it doubles
  as "where am I?" after jumping to a file via a picker.
- `f` (live filter) narrows the tree to matching filenames — useful for
  large directories. `F` clears it. This is tree-scoped filtering, not
  project-wide search.
- `<leader>e` is not registered as a which-key group to avoid intercepting
  the keypress (which-key would wait for a second key). Both explorer
  keymaps are registered as plain descriptions so they appear in
  `<leader>sk`.
- `<leader>e` and the outline's `<leader>o` (`outline.lua`) swap into each
  other: pressed from inside the outline sidebar, `<leader>e` closes it and
  opens the tree instead (and vice versa). Only one left-edge sidebar is ever
  open at a time. See [Design Decisions](#design-decisions) → "File tree and
  outline swap into each other".


<a id="outline-aerial"></a>
## Outline (aerial)

Setup lives in `outline.lua`: aerial.nvim provides a symbol outline, either
as a docked sidebar or a floating nav popup with an inline code preview.

| Key | Action |
|---|---|
| `<leader>o` | Toggle the docked outline sidebar |
| `<leader>O` | Toggle the nav popup (floating, with code preview) |
| `<leader>sb` | Fuzzy search inside current buffer (alias for `<leader>s/`) — use `<leader>ss`/`sd` for symbol search |
| `]a` / `[a` | Next / previous symbol (buffer-local, on attached buffers) |
| `zh` | Toggle highlight-on-hover of the source line (sidebar-local) |

Aerial's outline buffer is synthetic (no backing file) and can't be
session-restored — see [Design Decisions](#design-decisions) →
"Synthetic sidebar buffers can't be session-serialized" for why `session.lua`
closes it before saving instead of trying to preserve its open state. Reopen
with `<leader>o` after a session restore.

`<leader>o`/`<leader>O` no-op (with a `vim.notify` warning) when pressed from a
terminal or the sidekick CLI, where toggling the outline is never useful. From
the **file tree**, `<leader>o` instead swaps: it closes the tree and opens the
outline (and `<leader>e` does the reverse from inside the outline) — only one
left-edge sidebar is ever open at a time. Pressed from inside the aerial
sidebar itself, `<leader>o`/`<leader>O` just close it (normal toggle-off). See
[Design Decisions](#design-decisions) → "Non-code buffer exceptions need a
shared predicate" and "File tree and outline swap into each other".


<a id="terminal"></a>
## Terminal (toggleterm.nvim)

Setup lives in `terminal.lua`. A togglable floating terminal (85% of window)
that persists state across hides, plus a VS Code-style bottom panel.

### Keymaps

| Keymap | Action |
|---|---|
| `<C-\>` | Toggle floating terminal (normal, insert, or terminal mode) |
| `<leader>Tt` | Toggle floating terminal (discoverable via which-key) |
| `<leader>Th` / `<leader>Tv` | Open a horizontal / vertical split terminal |
| `` <C-`> `` / `<C-/>` / `<leader>Tb` | Toggle the bottom-panel terminal (dedicated horizontal split, pre-warmed) |
| `<Esc>` / `jj` / `jk` (in terminal) | Exit terminal mode → normal mode |
| `<C-h/j/k/l>` (in terminal) | Navigate to adjacent splits |
| `<C-]>` (in terminal) | Cycle to next terminal (wraps, so repeated presses reach every terminal) |

**Tips:**
- **Hide vs close**: `<C-\>` hides the terminal (state persists). `<C-d>` sends EOF to the shell and closes it entirely — faster than typing `exit`.
- **Multiple terminals**: prefix `<C-\>` with a count — `2<C-\>` opens terminal #2, `3<C-\>` opens #3. Each is independent.
- **Cycle between terminals**: `<C-]>` cycles to the next open terminal and wraps around. Works in both terminal and normal mode within the terminal buffer. (There is deliberately no cycle-previous key — `<C-[>` is the same keycode as `<Esc>` and shadowed it.)
- **Switch between terminals**: `:TermSelect` opens a picker over all open terminals.
- **Run a command**: `:TermExec cmd="make test"` — runs the command in terminal #1 and returns focus to your buffer.
- **Override direction ad-hoc**: `:ToggleTerm direction=horizontal` opens a split instead of a float for that toggle.
- **`<Esc>` caveat**: the `<Esc>` mapping exits terminal mode in all terminal buffers. TUI programs opened inside the terminal (e.g. `vim`, `htop`, `fzf`) also need `<Esc>` for their own UI — use `<C-\><C-n>` manually in those cases, or add a filetype guard in `terminal.lua`.
- **`<S-CR>` sends a literal newline** instead of submitting, inside these terminals and the bottom panel — see [LSP](#lsp) → Things to watch out for, "Shift+Enter → newline in terminals" for the CSI-u terminal requirement.


<a id="scratch-buffers"></a>
## Scratch buffers (snacks.nvim)

Keymaps live in `scratch.lua`; the module's options live in `picker.lua`'s
shared `require('snacks').setup()` call. A floating, persistent scratchpad
for throwaway notes or quick code — no need to create a real file. Only the
`picker`, `scratch`, and `indent` modules of snacks.nvim are enabled; the
rest (dashboard, notifier, etc.) stay off since this config already has its
own equivalents (mini.notify, ...).

### Keymaps

| Keymap | Action |
|---|---|
| `<leader>bs` | Toggle the scratch buffer (float) |
| `<leader>bS` | Select/list scratch buffers (recent first) |
| `<c-x>` (in `<leader>bS` picker) | Delete the scratch buffer under cursor |
| `<c-n>` (in `<leader>bS` picker) | Create a new scratch buffer |

Under `<leader>b` (Buffer) rather than `<leader>u` (Utilities) — open to
remapping these if they stop feeling right. The `<leader>b` which-key popup
now tells the whole buffer story: `<leader>bb` picker, `<leader>bd` close,
`<leader>bo` close others, plus these two scratch maps.

**Tips:**
- **Persistence**: content auto-saves to disk when the buffer is hidden
  (`autowrite`) and reloads next time you toggle it open — it's a real file
  under `stdpath("data")/scratch`, not a synthetic buffer.
- **Multiple scratchpads**: each scratch buffer is keyed by name, filetype,
  cwd, git branch, and an optional count prefix (`filekey`), so different
  projects/branches get their own scratchpad automatically, and `2<leader>bs`
  opens a distinct pad #2 from the default.
- **Run Lua inline**: set the buffer's filetype to `lua` (`:set ft=lua`),
  write some code, and press `<cr>` to execute it via `Snacks.debug.run()` —
  output appears inline, errors show as diagnostics. Handy for quick nvim API
  experiments without leaving the buffer.
- **Deleting a scratchpad**: there's no direct delete-current-buffer keymap —
  open `<leader>bS`, move to the entry, and press `<c-x>` (works in both
  normal and insert/prompt mode inside the picker). It removes the file and
  its `.meta` sidecar immediately and refreshes the list.
- **Zero scratchpads is fine**: if every scratchpad has been deleted,
  `<leader>bs` just creates a fresh one — there's no "no scratch buffers
  exist" error state.


<a id="indent-guides"></a>
## Indent guides (snacks.nvim)

Setup lives in `picker.lua`, in the same `require('snacks').setup({...})`
call as the `scratch` module above — all snacks modules share one setup call
since that's how snacks.nvim is configured. The `indent` module draws a vertical
guide line at every indent level, plus a distinct highlight on the guide for
the block the cursor is currently inside (its "scope").

Guides are **off by default** — the module is configured with `enabled =
false`, which survives snacks' auto-enable (setup only forces `enabled` on when
it's left `nil`), so nothing activates on `BufReadPost` and
`Snacks.indent.enabled` stays `false` until you turn it on. Press `<leader>tg`
to toggle guides for the session; the char/scope/animate settings below are
still registered up front, so `enable()` applies them the moment it first
fires.

The guide character is `▏` (a thin vertical bar) for both the regular indent
guides and the current-scope guide — a plain, unobtrusive glyph that reads as
a ruled line rather than decoration. Animation is disabled (`animate.enabled
= false`): the cursor-scope highlight jumps instantly to the new block
instead of easing into it, matching this config's general preference for
snappy, non-animated UI feedback.

Highlight colors are defined in `themes.lua`'s `M.global_overrides` (applied
after every colorscheme, so they survive theme switching):
- `SnacksIndent` links to `NonText` — same treatment as nvim-tree's
  `NvimTreeIndentMarker`, visible but unobtrusive.
- `SnacksIndentScope` links to `CursorLineNr`, not snacks' own default of
  `Special` — `Special` is already reassigned elsewhere in this config's
  overrides (aerial's Class icon/text groups) and tends to be a loud accent
  color in most themes, more than a steady-state indent guide warrants.
  `CursorLineNr` is calibrated by every theme to be a readable-but-restrained
  accent, which fits a steady "you are here" scope marker better.

The default filter already excludes panel buffers (anything with
`buftype ~= ''`), so nvim-tree, aerial, toggleterm, and other sidebars/floats
never grow indent guides — no extra config needed here.

**Escape hatch**: to turn off guides for one buffer, set
`vim.b.snacks_indent = false`; to turn them off everywhere without touching
the toggle below, set `vim.g.snacks_indent = false`.

### Keymaps

| Keymap | Action |
|---|---|
| `<leader>tg` | Toggle indent guides + current-scope highlight |


<a id="git-neogit"></a>
## Git (Neogit)

Setup lives in `gitui.lua`. Neogit is a Magit-style git dashboard: a
**transient, on-demand status buffer** — open it, stage/commit/push/pull
right there, then `q` to close and you're back to editing. It is not an
always-on window; the persistent gutter signs stay owned by gitsigns
(`git.lua`). diffview.nvim (also set up in `gitui.lua`) supplies rich
side-by-side diffs.

The module is named `gitui.lua`, not `neogit.lua` — Neogit's own Lua module
is also called `neogit`, so a topic file with that name would shadow it and
make `require('neogit')` recurse into itself. Same reasoning as
`outline.lua` wrapping aerial.nvim and `filetree.lua` wrapping nvim-tree.lua
under a descriptive, non-colliding name.

### Opening it

| Keymap | Opens | ≈ shell alias | Then press |
|---|---|---|---|
| `<leader>gg` | Neogit status | — | — |
| `<leader>gc` | Commit popup | `gc` | `c` to commit |
| `<leader>gp` | Push popup | `gp` | `p` (pushRemote) / `u` (upstream) |
| `<leader>gu` | Pull popup | `gu` | `p` / `u` similarly |
| `<leader>gl` | Log popup | `gl` | `l` for current branch log |
| `<leader>gd` | Diff popup | `gd` | pick what to diff against |
| `<leader>gb` | Branch popup | `gcb` / `gnb` | `b` checkout / `c` create / `x` delete |
| `<leader>gr` | Rebase popup | `grb` | pick target (onto branch, interactive, ...) |
| `<leader>gw` | Worktree popup | `gw` | `c` create / `d` delete / etc. |

**These are only mnemonic parallels, not equivalent actions.** Every alias
above runs its git command immediately; every `<leader>g*` mapping opens a
**popup** — Magit's core UX — landing on a menu of related sub-actions
rather than executing anything. `<leader>gp` does not push by itself; it
opens the push menu, and you press a letter (shown in the popup) to push.
The upside: the popup surfaces flags your aliases hardcode (e.g. the push
popup offers force-with-lease inline, matching `gpf`, without a separate
keymap).

A `kind='floating'` variant and a `<leader>gG` floating opener are written
but commented out in `gitui.lua`; uncomment to switch the default tab-page
dashboard for a floating overlay.

### Inside the status buffer

All of the following work with no leader prefix once the buffer is open —
the leader maps above are just fast entry points; everything is also
reachable from here:

| Key | Action | Key | Action |
|---|---|---|---|
| `s` / `S` / `<C-s>` | Stage / stage-all-unstaged / stage-everything | `c` | Commit popup |
| `u` / `U` | Unstage / unstage-all-staged | `p` / `P` | Pull / push popup |
| `x` | Discard | `f` | Fetch popup |
| `<Tab>` | Toggle fold | `b` | Branch popup |
| `<CR>` | Open file | `l` | Log popup |
| `<C-v>` / `<C-x>` / `<C-t>` | Open file in vsplit / split / tab | `d` | Diff popup |
| `Z` | Stash popup | `r` | Rebase popup |
| `m` / `t` / `w` | Merge / tag / worktree popup | `?` | Help (all popups) |
| `q` | Close | | |

### Commit flow + GPG signing

Committing (`c` then `c` in the commit popup, or `<leader>gc`) opens a real
**`gitcommit`-filetype buffer** — the existing `git.lua` FileType maps and
signing flow apply unchanged: `<leader>w` confirms (write + close),
`<leader>x` aborts (`:cq`). If this ever fights the flow, `commit_editor.kind`
in `gitui.lua`'s `setup()` is the escape hatch.

### Diffs

`d` in the status buffer (or the diff popup) renders a side-by-side diff via
diffview.nvim (`integrations.diffview = true`). `:DiffviewOpen` also works
standalone, outside of Neogit — see the "Reviewing diffs (diffview.nvim)"
section below for the full set of review workflows.

### Which git tool to use

- **gitsigns** (`git.lua`) — gutter signs, per-hunk actions, always on, no
  buffer to open: `<leader>hs` stage/unstage (a toggle — press again on a
  staged hunk to unstage it; there is no separate undo-stage key),
  `<leader>hr` reset, `<leader>hp` preview, `<leader>hb` blame line,
  `<leader>tb` toggle the inline current-line blame annotation,
  `]c`/`[c` hunk nav.
- **Git-status picker** (`<leader>sm`, snacks) — quick jump to a changed
  file with a diff preview.
- **Neogit** (`<leader>gg`) — full staging/commit/branch/rebase/worktree
  operations from one dashboard.

**Gutter sign legend** (gitsigns):

| Sign | Meaning |
|---|---|
| `▎` | Added line |
| `▎` | Changed line |
| `▂` / `▔` | Deleted line (below / above) |
| `▎` | Changed and deleted |
| `░` | Untracked file |

**satellite.nvim** adds a scrollbar on the right edge of the focused window
with color-coded marks for git changes (matches the gitsigns colors above),
LSP diagnostics, search results, and quickfix list items — useful for seeing
at a glance where changes/errors/matches are in a large file without scrolling.

| Command | Purpose |
|---|---|
| `:SatelliteRefresh` | Force refresh scrollbar if out of sync |
| `:SatelliteDisable` / `:SatelliteEnable` | Toggle scrollbar |


<a id="reviewing-diffs"></a>
## Reviewing diffs (diffview.nvim)

Setup lives alongside Neogit in `gitui.lua` (`packadd('diffview.nvim')`).
There is **no `require('diffview').setup()` call** — none is needed:
diffview lazily initializes its own defaults the first time any view opens,
and `plugin/diffview.lua` registers all commands and default keymaps
unconditionally on load. Everything below works with zero extra config.

`gitui.lua` also binds direct entry points under `<leader>v` ("Diffview"),
kept as its own which-key group rather than folded into Neogit's `<leader>g*`
so the two tools stay visually distinct:

| Keymap | Opens |
|---|---|
| `<leader>vv` | Uncommitted changes (flow 1 below) |
| `<leader>vp` | PR vs base branch — diffs against the merge-base, not a plain two-point diff (flow 2 below) |
| `<leader>vn` | Last N commits, squashed (flow 3 below) |
| `<leader>vh` | Walk each of the last N commits (flow 3 below) |
| `<leader>vf` | Current file's history |
| `<leader>vq` | Close the active Diffview |

**Feeding N to `vn`/`vh`:** a Vim count prefix wins — `5<leader>vn` opens
`HEAD~5..HEAD` directly, no prompt. With no count, both fall back to a
`vim.ui.input` prompt ("Commits back: ") that starts empty rather than
defaulting to some arbitrary N; empty or non-numeric input cancels quietly.

**Base-branch detection (`<leader>vp`):** mirrors the zsh `git_base_branch()`
function's two-tier lookup — fast path `git symbolic-ref refs/remotes/origin/HEAD`,
falling back to `git remote show origin` (a network call) if the local ref
isn't populated. Unlike the shell function there is **no final `main`
fallback**: if both tiers fail, `<leader>vp` warns and does nothing rather
than silently guessing a branch name. Run `git remote set-head origin --auto`
once per clone to populate the fast path and skip the network round-trip.

Three review shapes map to three different invocations:

### 1. Uncommitted local changes

```vim
:DiffviewOpen
```

Keymap: `<leader>vv`.

No args diffs against the index. The file panel splits into two sections —
**Changes** (working tree vs index, i.e. unstaged) and **Staged changes**
(index vs HEAD) — shown at the same time. Stage/unstage right from the
panel; writing an index buffer (`:w`) updates the index directly.

| Key | Action | Key | Action |
|---|---|---|---|
| `<Tab>` / `<S-Tab>` | Next / previous file | `s` / `-` | Toggle stage on entry |
| `[F` / `]F` | First / last file | `S` / `U` | Stage all / unstage all |
| `<CR>` / `o` | Open entry's diff | `X` | Restore entry (discard) |
| `<leader>e` | Focus file panel | `R` | Refresh file list |

Neogit shortcut: `<leader>gg` → `d` → `u` (unstaged only) / `s` (staged
only) / `w` (worktree — both sections, equivalent to the bare command above).

### 2. A branch you checked out to review (PR review)

```vim
:DiffviewOpen origin/main...HEAD
```

Keymap: `<leader>vp` — runs exactly this, with the base branch resolved at
runtime (`origin/<detected base>`, never hardcoded `main`; see above).

**Triple-dot, not double-dot.** `a...b` diffs against the merge-base — "what
did this branch add since it forked from main" — matching the `gdm` shell
alias's semantics (`git diff $(git_base_branch)...`). `a..b` is a plain
two-point diff with no merge-base resolution; wrong tool here unless main
hasn't moved. `origin/main` works directly as a remote-tracking ref;
diffview doesn't auto-fetch, so `git fetch` first if it might be stale.
There is no "Staged changes" section for a rev-range diff — it's read-only.

Append `--imply-local` to swap the `HEAD` side for your real local files
(live LSP) while still diffing against the merge-base on the other side.
`<leader>vp` doesn't append this — type the full command when you need it.

Neogit shortcut: `<leader>gg` → `d` → `r` (range) → choose **2. Symmetric
Difference (a...b)** → supply `origin/main` and `HEAD` via the prompts.

### 3. Past N commits (less common)

Two different questions, two different commands:

- **"What changed, total?"** — `:DiffviewOpen HEAD~4..HEAD` (two-dot): one
  squashed diff across the range, browsed file-by-file like flows 1 & 2.
  Closest match to the `gd`/`gds` shell functions. Note `HEAD~4` alone (no
  `..`) diffs your *working tree* against that single rev, not a range.
  Keymap: `4<leader>vn` (count prefix) or bare `<leader>vn` (prompts for N).
- **"Walk me through each commit"** — `:DiffviewFileHistory --range=HEAD~4..HEAD`:
  a genuine git-log browser (commit list panel). No shell equivalent today.
  Keymap: `4<leader>vh` (count prefix) or bare `<leader>vh` (prompts for N).

  | Key | Action |
  |---|---|
  | `j` / `<Down>` | Next commit |
  | `k` / `<Up>` | Previous commit |
  | `<CR>` / `o` / `l` | Open the diff for the selected commit |
  | `<Tab>` / `<S-Tab>` | Next/previous file within that commit's diff (only matters if the commit touched multiple files) |
  | `gf` | Open the file in the previous tabpage |
  | `y` | Yank the commit hash |
  | `L` | Show full commit details |

  The walk: `j`/`k` to pick a commit, `<CR>` to view its diff, `<Tab>`/`<S-Tab>`
  only if that commit touched more than one file.
- **One commit only** (≈ `gdn`) — `:DiffviewOpen <hash>^!` ("just this
  commit," like `git show`). No keymap — type the hash.
- **Just this file's history** — `:DiffviewFileHistory %`, or `<leader>vf`
  from any buffer — same commit-browser UI as the range command above, but
  scoped to the current file's log.

Neogit's `d` → `r` popup covers the squashed-range case too — choose
**1. Range (a..b)** instead of symmetric difference. `:DiffviewFileHistory`
has no Neogit popup binding; reach it from `<leader>v*`, the command line,
or via `L` ("open commit log") inside any file panel.

### Command reference

| Command | Purpose |
|---|---|
| `:DiffviewOpen [rev] [-- paths]` | Open a diff against `rev` (defaults to the index) |
| `:DiffviewFileHistory [paths] [opts]` | Browse git log commit-by-commit; `--range=`, `--base=`, `-g` (reflogs, for stash) |
| `:DiffviewClose` | Close the active Diffview (`:tabclose` also works) |
| `:DiffviewToggleFiles` | Toggle the file panel |
| `:DiffviewFocusFiles` | Focus the file panel (opens it if closed) |
| `:DiffviewRefresh` | Re-scan the current file list |
| `:DiffviewLog` | Open the plugin's debug log |

### Gotchas

- **Closing** — `<leader>vq` (bound in `gitui.lua`) or `:DiffviewClose` /
  `:tabclose`.
- **Live index refresh** — `watch_index` defaults on, so staging a file in
  Neogit while a Diffview tab is open updates that tab's buffers
  automatically.
- **Merge conflicts** switch the layout to a 3-way diff automatically
  (`diff3_horizontal`), with their own file-panel section and a live
  unresolved-conflict counter.

### Visual walkthrough

A fully worked, interactive version of the three flows above — mockups
built from this repo's actual working-tree diff and real git log (not
placeholder content), plus the keymap tables and Neogit cross-references —
is published here: <https://claude.ai/code/artifact/6c06c439-077a-422e-97b7-5037c49e5de5>.
It's a private Claude artifact by default; share it from claude.ai if you
want it visible on another machine or to someone else.


<a id="ai-sidekick"></a>
## AI (sidekick.nvim)

Setup lives in `ai.lua`. Uses `folke/sidekick.nvim` for two features:

1. **NES (Next Edit Suggestion)** — powered by Copilot LSP. After edits,
   diff overlays appear suggesting follow-on changes. `<Tab>` in normal mode
   jumps to or applies the next suggestion. Falls through to literal `<Tab>`
   when no suggestion is active.

   Caveat: in a terminal that can't distinguish `Tab` from `Ctrl-I` (they
   share ASCII 9 without the kitty keyboard protocol / CSI u), this mapping
   also captures `<C-i>` — jumplist *forward* — so `<C-i>` triggers NES
   instead of jumping. Not an issue in this setup's environments (kitty,
   iTerm2 with CSI u, Neovide, all of which disambiguate), only in legacy
   terminals (Apple Terminal, ssh without protocol support). Fallbacks that
   always work: mouse forward button (`<X2Mouse>`) and Neovide's
   `<D-M-Right>`.

2. **CLI integration** — runs one or more Claude (and other CLI) sessions in
   terminal splits, organized around the **active session**: the CLI session
   whose window you last entered (default: the pre-warmed `claude`).
   `<leader>aa` toggles it, `<leader>ad` kills it, and **all send keys,
   `<leader>ao`, `<M-a>`, and `<C-.>`/`<leader>ai` target it** — with several
   sessions running, sends never stop to ask which one.

   `<leader>an` spawns a **new** session: a blank prompt auto-numbers it
   (`claude 2`, `claude 3`, …) — the counter climbs monotonically and never
   refills a freed number, so deleting `claude 2` and forking again gives
   `claude 4`, not `claude 2`. A typed label makes a reusable named session
   (`claude: tests`) that re-attaches if you type the same label again.
   `<leader>al` opens a snacks picker over running sessions to **switch**
   (`<CR>`, which also makes that session active) or **kill** (`<C-d>`) one.
   Inside the CLI, `<M-]>`/`<M-[>` cycle to the next/previous running session in
   place without leaving terminal mode (no `jj`/`jk` + `<leader>al` round-trip);
   `<M-l>` opens the same switch/kill picker in place; `<C-]>` toggles back to
   the last-used session (alt-tab style), `<M-n>` forks a new auto-numbered
   session in place, and `<M-a>` hides the panel (the `<leader>aa` toggle)
   without first escaping terminal mode. Kill stays on the deliberate
   `<leader>ad` path — there's no fast in-panel teardown.
   `<leader>as` stays the **tool launcher** — start a different CLI tool
   (Copilot, Gemini, etc.) — distinct from `<leader>al`.

   Sessions are keyed by `(tool name, cwd)`; each extra session is a
   dynamically-registered tool name cloned from the `claude` preset (so
   context sends stay claude-formatted). Only `claude` #1 is pre-warmed —
   sessions 2+ cold-start (~1–2s) on first open. Killing a session
   auto-unregisters its dynamic name (a detach sweep), and re-creating that
   name starts a **fresh** conversation (no resume). A very long label
   (≥16 chars) warns that reusing it from a different project dir collapses to
   the same session. Nothing persists across an nvim restart without the mux
   backend.

| Keymap | Action |
|---|---|
| `<Tab>` (insert) | Priority: blink menu selection → Copilot ghost text accept → literal Tab (matches VS Code/Zed) |
| `<Tab>` (normal) | NES: jump to or apply next edit suggestion |
| `<leader>ta` | Toggle all AI completions globally (inline ghost text + NES) |
| `<C-.>` | Focus active CLI (any mode; CSI u terminals only) |
| `<leader>ai` | Focus active CLI (cross-terminal fallback for `<C-.>`) |
| `<leader>aa` | Toggle active CLI session (session stays alive when hidden) |
| `<leader>an` | New Claude session — blank prompt = auto-numbered, label = named/reusable |
| `<leader>al` | Switch (`<CR>`) or kill (`<C-d>`) a running CLI session (snacks picker) |
| `<M-]>` / `<M-[>` (in CLI) | Cycle to next / previous running session in place (stays in terminal mode) |
| `<M-l>` (in CLI) | Open the switch/kill session picker in place (the `<leader>al` picker) |
| `<C-]>` (in CLI) | Toggle to the last-used session (alt-tab style) |
| `<M-n>` (in CLI) | New auto-numbered session in place (labels stay on `<leader>an`) |
| `<M-a>` (in CLI) | Hide the panel in place (the `<leader>aa` toggle, no `jj`/`jk` first) |
| `<leader>as` | Launch a CLI tool (copilot, gemini, …) |
| `<leader>ad` | Kill active CLI session (tears down process + buffer; floating confirm popup) |
| `<leader>ao` | Select prompt |
| `<leader>at` | Send position (normal) or selection (visual) to CLI |
| `<leader>ap` | Send file path to CLI (`p` = path, matches `yp`/`yP` yanks) |
| `<leader>af` | Send enclosing function (needs nvim-treesitter-textobjects) |
| `<leader>ac` | Send enclosing class (needs nvim-treesitter-textobjects) |
| `<leader>ae` | Send buffer diagnostics (`e`, mirrors `<leader>ce`) |
| `<leader>ab` | Send list of open buffers |
| `<leader>aq` | Send quickfix list |
| `<M-a>` (in picker) | Send picker selection(s) to CLI |

`<leader>af`/`<leader>ac` send a *position reference* (type + name +
`file:line`) for the function/class at the cursor, not the code body; outside
any function/class the send is a benign no-op. They resolve via
`nvim-treesitter-textobjects` (packadd'd in `plugins.lua`); the other send
targets come from sidekick's own `cli/context` module.

### NES vs Copilot inline completion

Two separate Copilot features, both powered by the Copilot LSP:

- **NES** (normal mode) — after you edit and leave insert mode, Copilot
  suggests follow-on edits as diff overlays. Press `<Tab>` to jump/apply.
  Reactive: "you changed X, here's what else should change."
  LSP method: `textDocument/copilotInlineEdit`.
- **Inline completion** (insert mode) — while typing, Copilot renders ghost
  text at the cursor showing what to type next. Press `<Tab>` to accept.
  Proactive: "here's what you probably want to write next."
  LSP method: `textDocument/inlineCompletion`.
  Uses `vim.lsp.inline_completion` (Neovim 0.12 built-in). `<leader>ta`
  toggles globally. Ghost text styled via `ComplHint` highlight group
  (linked to `Comment` in `themes.lua` for visibility).

blink.cmp's ghost text is disabled to avoid dual overlays — Copilot's
inline completion provides its own ghost text via the same extmark
mechanism (`virt_text_pos='inline'`).

### First-run setup

1. Restart Neovim — sidekick.nvim installs via `vim.pack`.
2. `:Mason` — confirm `copilot-language-server` is installed.
3. `:LspCopilotSignIn` — complete the device-code flow in a browser.
4. Install `claude` CLI if not already present.


<a id="rust"></a>
## Rust (rustaceanvim + DAP + neotest)

IDE-grade run/debug/test for Rust, split across three modules: `rust.lua`
(rustaceanvim), `debugging.lua` (nvim-dap + dap-ui), `testing.lua` (neotest).
rustaceanvim is the keystone — it takes over rust-analyzer and, in doing so:

1. **Registers the Run/Debug codelens handlers.** rust-analyzer emits `▶ Run`
   / `⚙ Debug` codelens, but plain LSP has no client-side handler for the
   `rust-analyzer.runSingle` / `debugSingle` commands, so `grx` on them used to
   error. rustaceanvim provides the handlers — the codelens now execute.
2. **Auto-wires the codelldb DAP adapter.** No hand-written `dap.adapters.codelldb`
   — rustaceanvim finds Mason's codelldb and builds the adapter itself.
3. **Ships a neotest adapter** (`rustaceanvim.neotest`) that reuses rust-analyzer's
   runnables and integrates with nvim-dap for debugging tests.

### rust-analyzer ownership

rust-analyzer is **not** in `lsp.lua`'s `vim.lsp.enable` list, and **not** in
Mason (`rust_analyzer` was removed from `ensure_installed`). rustaceanvim starts
it, pointed explicitly at the **rustup proxy** `~/.cargo/bin/rust-analyzer`.

Why the explicit path: Mason prepends its `bin/` to `PATH`, and that dir sorts
**before** `~/.cargo/bin`, so a bare `rust-analyzer` would resolve to Mason's
copy — which can drift from the active rustup toolchain and cause proc-macro /
version noise. The rustup proxy is toolchain-matched and honors per-project
`rust-toolchain.toml`. If you ever *do* want Mason's, override
`vim.g.rustaceanvim.server.cmd` in `rust.lua`.

### Standalone `.rs` files (no Cargo project)

Opening a lone `.rs` file with no `Cargo.toml` up the tree — e.g. the
`fixtures/` demo files — starts rust-analyzer in **detached/standalone mode**.
By default that used to dump a screenful of cargo backtrace into mini.notify on
every open: clippy-on-save shells out to `cargo check` on the single file, and
cargo (1.85+) treats a bare `.rs` as a nightly-only single-file *script*
(`-Zscript`/frontmatter) it refuses to build on stable.

`rust.lua`'s `server.settings` function turns `checkOnSave` **off** whenever no
Rust *project marker* is found up the tree (it probes the resolved root dir,
which in detached mode is just the file's own directory), which kills that
backtrace. The markers it looks for are `{ 'Cargo.toml', 'rust-project.json' }` —
`Cargo.toml` for normal crates, `rust-project.json` for non-Cargo (buck/bazel-style)
projects, both of which are real projects where clippy-on-save should stay on.
**If Rust's project conventions change** — a new manifest/workspace-marker
filename appears, or rust-analyzer starts recognizing a different discovery
file — **add it to that list in `rust.lua`** (and update this line), otherwise
such a project would be misdetected as a standalone file and lose clippy-on-save.
Real Cargo projects still get full clippy-on-save. What remains is a short,
expected `INFO` ("detached mode, reduced functionality") plus a one-line health
`WARN` that rust-analyzer couldn't discover a workspace — that WARN is
rust-analyzer core behavior for any Cargo-less file and isn't suppressed
per-file on purpose (rustaceanvim's `status_notify_level` is global, so silencing
it would also hide genuine "can't find your Cargo.toml" errors in real projects).

### Running a program

- **`<leader>cR`** — runnables picker; select the binary → runs `cargo run` in a
  terminal split. Workspace-aware (rust-analyzer picks the right `-p` package).
- **`grx`** on the `fn main` line — runs the `▶ Run` codelens directly.
- **`:RustLsp run`** — re-run the *last* runnable (fast edit-run loop).
- Or just a terminal: `<leader>Tb`, then `cargo run -p <crate>`.

### Debugging

1. Set a breakpoint: **`<leader>db`** (or `<F9>`) — a `●` appears in the sign column.
2. Start the session: **`<leader>dR`** (Rust debuggables) → pick the target →
   rustaceanvim compiles it in debug mode, launches under codelldb, and stops at
   the breakpoint. dap-ui opens automatically (scopes, stack, breakpoints, REPL)
   and closes when the session ends.
3. Drive it: `<F5>`/`<leader>dc` continue, `<F10>` over, `<F11>` into, `<F12>` out.

`<leader>dR` is the reliable entry point (it asks rust-analyzer for the exact
cargo target). `<F5>`/`<leader>dc` (`dap.continue`) is for *resuming* a paused
session — starting cold from it relies on rustaceanvim's auto-loaded configs.

### Testing

`<leader>nn` runs the test under the cursor; results show as signs + a summary
tree. `<leader>nd` debugs the nearest test (breakpoints honored via dap).

### Keymaps

**Rust actions** (buffer-local, `rust` filetype only — from `rust.lua`):

| Keymap | Action |
|---|---|
| `K` | Rust hover actions (richer than plain LSP hover) |
| `<leader>ca` | Code action (rustaceanvim grouped variant) |
| `<leader>cR` | Runnables — run a binary/target |
| `<leader>cm` | Expand macro under cursor |
| `<leader>cC` | Open the crate's `Cargo.toml` |
| `<leader>dR` | Debuggables — start a Rust debug session |
| `grx` | Run/Debug codelens under cursor (native codelens, now functional) |

**Debug** (global, `<leader>d*` = Debug group — from `debugging.lua`):

| Keymap | Action |
|---|---|
| `<leader>db` / `<F9>` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint (prompts for condition) |
| `<leader>dc` / `<F5>` | Continue / start |
| `<leader>di` / `<F11>` | Step into |
| `<leader>do` / `<F10>` | Step over |
| `<leader>dO` / `<F12>` | Step out |
| `<leader>dl` | Run last |
| `<leader>dq` | Terminate |
| `<leader>dr` | Toggle REPL |
| `<leader>du` | Toggle dap-ui |
| `<leader>de` | Eval expression (normal: under cursor; visual: selection) |

**Test** (global, `<leader>n*` = Test group — from `testing.lua`):

| Keymap | Action |
|---|---|
| `<leader>nn` | Run nearest test |
| `<leader>nf` | Run all tests in file |
| `<leader>nl` | Run last |
| `<leader>nd` | Debug nearest test (via dap) |
| `<leader>nq` | Stop running test(s) |
| `<leader>ns` | Toggle summary tree |
| `<leader>no` | Show output for nearest |
| `<leader>nO` | Toggle output panel |

### Extending neotest to other languages

`testing.lua` sets up neotest as a framework. To add a language: add its adapter
plugin to `plugins.lua`, `require` it in `testing.lua`'s `adapters` list, and
ensure the treesitter parser is installed. E.g. for Go:

```lua
-- plugins.lua:  { src = gh('fredrikaverpil/neotest-golang') },
-- testing.lua:  require('neotest-golang'),
```

### Troubleshooting

- **Debug session dies instantly** (Apple Silicon): codelldb is found on `PATH`
  so rustaceanvim uses the plain-command adapter without explicitly pairing
  `liblldb.dylib`. If `:messages` shows a liblldb error, replace `dap = {}` in
  `rust.lua` with an explicit adapter:
  ```lua
  dap = {
    adapter = require('rustaceanvim.config').get_codelldb_adapter(
      vim.fn.expand('~/.local/share/nvim/mason/packages/codelldb/extension/adapter/codelldb'),
      vim.fn.expand('~/.local/share/nvim/mason/packages/codelldb/extension/lldb/lib/liblldb.dylib'))
  }
  ```
- **Two rust-analyzer clients / wrong version**: check `:checkhealth vim.lsp` —
  the command should be the rustup proxy, not a Mason path. If it's Mason's, you
  skipped step 3 above.
- **`require('rustaceanvim.neotest')` errors on startup**: `rust` must load
  before `testing` in `init.lua` (see Load order).


## Neovide

Runtime config and keymaps live in `neovide.lua`, gated by
`if not vim.g.neovide then return end` — terminal nvim skips the file
entirely. Startup-time settings (fork, frame, font) live in `neovide.toml`
instead, since Neovide reads them before nvim launches. Install/symlink steps
are in the repo README → "Neovide".

**macOS-style keymaps** (terminal nvim can't receive `<D-...>`):

| Keymap | Action |
|---|---|
| `Cmd+C` (visual) | Copy to system clipboard |
| `Cmd+V` | Paste from system clipboard — normal mode puts, visual replaces the selection without clobbering registers (`"_d"+P`), insert/cmdline use `<C-r>+`, terminal exits to normal, puts, re-enters |
| `Cmd+S` | Save (`:w`) |
| `Cmd+=` / `Cmd+-` | Zoom in / out (`neovide_scale_factor`) |
| `Cmd+0` | Reset zoom to 1.0 |
| `Cmd+Opt+Left` / `Cmd+Opt+Right` | Jumplist back / forward |

Other Neovide-only behavior:

- `option_key_is_meta = 'both'` — Option acts as Meta so `<M-...>` keymaps
  (buffer-picker rows, `<M-1>`..`<M-9>` quick-pick, structural selection) work.
- **Force Click** on the trackpad triggers `:NeovideForceClick` — macOS
  "Look Up" popover for text, Quick Look for file paths/URLs. No setup.
- Animations are tuned short (cursor 0.05s, scroll 0.1s); floating shadow is
  off so floats match terminal nvim's flat edges.
