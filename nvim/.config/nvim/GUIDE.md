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
  - [Large files](#large-files)
  - [Picker (snacks.nvim)](#picker-snacks)
    - [Path display](#picker-path-display)
  - [grug-far](#grug-far)
  - [Quickfix & location lists](#quickfix-loclist)
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
  - [Debugging (nvim-dap)](#debugging)
  - [Testing (neotest)](#testing)
  - [Rust (rustaceanvim)](#rust)
  - [Go (delve + neotest)](#go)
  - [Animations](#animations)
  - [Neovide](#neovide)
  - [On-disk state](#on-disk-state)


# Part 1: Essentials

## Architecture

### File responsibilities

- **`init.lua`** — Sets leader key, requires all modules in dependency order
- **`configs.lua`** — Core vim options (`updatetime`, `scrolloff`, tabs, undo, splits, `diffopt` with `linematch:60` + histogram, etc.), auto-reload for external file changes (focus/idle/buffer-switch + leaving a terminal, plus a 2s poll timer), nvim update check
- **`autocmds.lua`** — General editor autocmds not owned by a feature module, all under one `UserAutocmds` augroup: create missing parent dirs on save (skips `scheme://` buffers); restore last cursor position on file open (see [Design Decisions](#design-decisions) → "Cursor-restore rides BufReadPost"); flash yanked text (`vim.hl.on_yank`); map `q` to close transient help/quickfix windows (skips any buffer already binding `q`); quit nvim when only sidebars remain (see [Design Decisions](#design-decisions) → "Quit nvim when only sidebars remain")
- **`plugins.lua`** — `vim.pack.add` declarations for all plugins (including theme sources from `themes.lua`), orphan plugin detection, treesitter parser management (plus `nvim-treesitter-textobjects`, packadd'd here so sidekick's `{function}`/`{class}` context queries land on the runtimepath — no dedicated config module), render-markdown, autopairs (`check_ts = true`: treesitter-aware, skips pairing inside strings/comments), flatten.nvim (nested-nvim routing — see Design Decisions)
- **`treesitter_context.lua`** — nvim-treesitter-context: sticky scope header (VS Code-style sticky scroll) — pins the enclosing function/class/if/loop signature to the top of the window while scrolling. No keymaps; passive display feature
- **`keymaps.lua`** — Global keymaps: pickers (`<leader>s*`, `<leader><leader>` smart, snacks), clipboard-aware yank, split navigation, buffer navigation (`H`/`L`/`gb`/`<leader>m`/`<leader>bb`/`<leader>bo`), visual indent, diagnostic toggle, yank helpers (`yp`, `yc`, `yu`, etc.)
- **`edit.lua`** — Editing utilities consumed by keymaps.lua (required from there, not init.lua — no Load-order entry): strip-trailing-whitespace (`<leader>us`, `:StripWS`) and pasted-terminal-text reflow (`<leader>uc`, `:CleanPaste`)
- **`outline.lua`** — aerial.nvim symbol-outline setup: docked sidebar (`<leader>o`) and floating nav popup (`<leader>O`) with code preview; buffer-local `]a`/`[a` symbol nav (no aerial picker keymap — `<leader>sd` covers picker-style symbol search)
- **`quickfix.lua`** — quicker.nvim setup: an editable, better-styled quickfix/loclist window (the `<leader>tq`/`<leader>tl` toggles in `keymaps.lua` route through its `toggle()`). Editable buffer — `dd` + `:w` prunes an entry, editing item text + `:w` writes back to the file (`autosave = 'unmodified'`); `>`/`<` expand/collapse context lines. Browsing/filtering still goes through the snacks pickers (`pickers/qfhistory.lua`). Named `quickfix.lua`, not `quicker.lua`, so `require('quicker')` resolves to the plugin
- **`structural_select.lua`** — Helix-style structural (treesitter) selection: `<M-o>`/`<M-i>` grow/shrink the visual selection by syntax node, via the core `vim.treesitter` API (no extra plugin — replaces the incremental-selection module removed by nvim-treesitter's `main`-branch rewrite)
- **`pickers/buffer.lua`** — Custom snacks buffer picker (`<leader>bb`, aliased as `<leader>m`): row-index column replaces the bufnr column, `<M-1>`..`<M-9>` jumps to that row, `<C-x>` deletes the highlighted/selected buffers; stable bufnr row order (`sort_lastused` off)
- **`pickers/gitstatus.lua`** — snacks git-status picker (`<leader>sm`): wraps the builtin `git_status` source (diff preview, `<tab>` staging toggle with auto-refresh) adding a row-index column, `<M-1>`..`<M-9>` quick-pick, repo resolution from the current buffer's directory, and a "No changes found" notify instead of an empty picker; a count prefix (`5<leader>sm`) switches to the builtin `git_diff` source instead, for the last N commits' diff plus uncommitted changes
- **`pickers/common.lua`** — Shared picker utilities: `quick_pick_actions()` returns `<M-1>`..`<M-9>` row-jump actions/keys for snacks pickers (buffer, gitstatus, go-targets); `indexed_select()` builds on it — a compact switch-or-kill picker (row-index column, `<M-1>`..`<M-9>` quick-pick, optional `<C-x>` kill) used by the terminal (`terminal.lua`) and sidekick session (`ai.lua`) pickers
- **`pickers/symbols.lua`** — Custom snacks symbol pickers: `M.workspace` (`<leader>ss`) is a live picker fanning `workspace/symbol` to all active LSP clients (snacks' builtin only queries buffer-attached ones) with a two-token prompt (first token = name query sent to LSP, remainder = file path filter via matchfuzzy), custom kind icons, vertical layout; `M.document` (`<leader>sd`) wraps the builtin `lsp_symbols` flat and kind-unfiltered — kind is in the match text so typing "function"/"variable" filters by kind; `M.toggle_buffer_only` (`<leader>ts`) switches workspace mode between all-LSPs and buffer-only
- **`pickers/grepselection.lua`** — Custom snacks picker (`<leader>ss` in visual mode): literal, multi-line-aware grep of the visual selection via `rg --json --multiline`. See [Picker (snacks.nvim)](#picker-snacks) → "Multi-line selection search"
- **`completion.lua`** — blink.cmp: keymap preset (Tab priority: blink menu → snippet placeholder jump → literal Tab), sources, auto-brackets, signature hints, fuzzy backend. Ghost text disabled — near-inert against `preselect = false`.
- **`lsp.lua`** — Mason setup, mason-lspconfig, goto-preview setup (VS Code-style peek floats, `<leader>p*`), actions-preview.nvim setup (`backend = { 'snacks' }` — diff-preview code actions, global `<leader>ca`/`gra`), LspAttach autocmd (buffer-local keymaps + capability-gated features), diagnostic config, per-server `vim.lsp.config`, a `'*'` merge of nvim-lsp-file-operations' file-operation capabilities (rename-fixes-imports — capability half; event half in `filetree.lua`, see [Design Decisions](#design-decisions) → "Renaming a file rewrites its imports"), `vim.lsp.enable`. Note: `rust_analyzer` is intentionally absent — rustaceanvim (`rust.lua`) owns the Rust client (see the Rust section)
- **`rust.lua`** — rustaceanvim: Rust LSP layer over rust-analyzer (started here, not in `lsp.lua`). Sets `vim.g.rustaceanvim` before `packadd` — rustup `server.cmd`, clippy-on-save, codelldb DAP auto-detect; buffer-local Rust keymaps set on `LspAttach`, not `FileType` (see [Design Decisions](#design-decisions) → "Rust keymaps fire on LspAttach, not FileType") — `<leader>cR` runnables, `<leader>cm` expand macro, `<leader>cs` SSR (`n`+`x`), `<leader>cF` batch clippy-fix, `<leader>cp` code action diff preview, `<leader>dR` debuggables, `K`/`<leader>ca` grouped hover/actions
- **`debugging.lua`** — nvim-dap + nvim-dap-ui + nvim-dap-virtual-text + nvim-nio: debug engine and docked UI (auto-opens/closes with the session), inline variable values during a session, breakpoint signs, `<leader>d*` + `<F5>`/`<F9>`–`<F12>` keymaps. Owns only the generic engine, UI, signs, and keymaps — no language's adapter lives here; Rust's comes from rustaceanvim (`rust.lua`), Go's from nvim-dap-go (`golang.lua`). Named to avoid shadowing `require('dap')` / `require('debug')`
- **`golang.lua`** — Go's language module, the mirror of `rust.lua`: pcall-guarded `nvim-dap-go` setup (the delve adapter + seven `dap.configurations.go` launch configs) plus buffer-local `FileType go` keymaps (`<leader>dR` debug targets, `<leader>cR` run targets). Named `golang.lua`, not `go.lua` — `require('go')` is ray-x/go.nvim's own module name, so taking it would shadow that plugin (same rule as `debugging.lua`-not-`dap.lua`)
- **`pickers/gotargets.lua`** — custom snacks picker: an async `go list -e` enumerates the current module's `main` packages, then confirm either launches the picked one under delve (`dap.run`) or `go run`s it in a toggleterm float
- **`testing.lua`** — neotest (extensible framework): test runner UI. Rust via rustaceanvim's adapter, Go via neotest-golang (gotestsum runner); `<leader>n*` keymaps (run nearest/file/last, debug nearest, summary, output)
- **`format.lua`** — conform.nvim: per-filetype formatter chains, format-on-save toggle (`<leader>tf`), manual format (`<leader>cf`)
- **`linting.lua`** — nvim-lint: CLI linters that catch what the LSP servers don't (ruff, golangci-lint, credo, yamllint, checkmake), run on save/read; lint-on-save toggle (`<leader>tL`), manual lint (`<leader>cl`). Named `linting.lua`, not `lint.lua` — the plugin's own module is `lint`
- **`statusline.lua`** — lualine: sections (mode, path, branch, diff, diagnostics, lsp_status, location), powerline separators, global statusline
- **`session.lua`** — persistence.nvim: branch-aware session save/restore, `<leader>q*` keymaps
- **`git.lua`** — gitsigns: hunk signs, hunk navigation (`]c`/`[c`), staging/reset/blame keymaps (`<leader>h*`); satellite.nvim scrollbar with git/diagnostic/search marks; FileType autocmd for `gitcommit`/`gitrebase` adds `<leader>w` (confirm) and `<leader>x` (abort)
- **`gitui.lua`** — Neogit (Magit-style git dashboard) + diffview.nvim: on-demand status buffer, shell-aligned `<leader>G*` popups, `kind='tab'`, signs disabled (gitsigns owns the gutter). Named `gitui` not `neogit` to avoid shadowing the plugin's own `neogit` Lua module
- **`filetree.lua`** — nvim-tree: sidebar file tree with git status, LSP diagnostics, modified indicators, trash-on-delete; custom `on_attach` adds `l`/`h` navigation; `<leader>e` toggles tree and reveals current file. Also wires nvim-lsp-file-operations (event half — subscribes to nvim-tree's rename/move/delete events so in-tree renames rewrite imports; capability half in `lsp.lua`). (The "quit nvim when only sidebars remain" autocmd used to live here nvim-tree-only; it's now generalized to all sidebars in `autocmds.lua`.)
- **`terminal.lua`** — toggleterm.nvim: floating terminal (85% of window), `<C-\>` toggle from any mode; VS Code-style bottom panel (dedicated horizontal terminal, `<C-/>` / `<C-_>`, pre-warmed, hides from within, deliberately a single instance with no cycle/new/select keys); TermOpen autocmd (toggleterm only, skips sidekick) sets terminal-mode keymaps (`<Esc>` exits to normal, `<C-h/j/k/l>` navigate splits; float-only: `<M-]>`/`<M-[>` cycle floats, `<M-n>` new auto-numbered float, `<M-l>` indexed terminal picker)
- **`scratch.lua`** — Keymaps for the snacks.nvim scratch module: floating, persistent scratchpad keyed by cwd/branch/count (`<leader>bs` toggle, `<leader>bS` select/list). Module options live in `picker.lua`'s shared snacks setup
- **`grugfar.lua`** — grug-far.nvim setup + the `<leader>sR` (`n`+`x`) entry key for interactive project-wide find & replace (the editable counterpart to the read-only snacks grep pickers). Lazy-loads the plugin (`packadd` + `setup()`) on first press, keeping only the keymap eager; close remapped to `q`, in-buffer editing on `<localleader>` (`\`). See the [grug-far](#grug-far) section. Named `grugfar` (no hyphen) to avoid shadowing the plugin's own `grug-far` Lua module
- **`picker.lua`** — snacks.nvim setup (the single `require('snacks').setup()` call): `picker` module global config (flex-parity layout flipping at 160 columns, frecency ranking, left-truncated + width-capped file paths + full path in the preview border — see [Path display](#picker-path-display), custom `<CR>` confirm that scrolls the cursor ~20% from the top, `<C-CR>` send-to-sidekick action, `<C-y>` copy-path action, `<Esc>` one-press cancel, `<C-h>` help alias, hidden-files/`node_modules` source opts) plus the `scratch` and `indent` module options (keymaps for those stay in `scratch.lua`/`keymaps.lua`)
- **`titling.lua`** — Sets `'title'`/`'titlestring'` to `<project> — <file> [+]` for iTerm2/Neovide; `<leader>ut` / `:Title <name>` sets a manual override
- **`whichkey.lua`** — which-key: group labels, explicit trigger list, yank-prefix documentation; exports `keywords` (search aliases) and a slim `tags` override table (only non-derivable extras) consumed by `pickers/keybindings.lua`
- **`pickers/keybindings.lua`** — snacks picker that walks which-key's tree to fuzzy-search all keymaps; merges in `builtins.lua` so built-in motions are searchable too; displays 5 columns: key (dynamic width), modes (dim), icon+group breadcrumb (dim), desc, tag pills (dim). All six modes are walked, and a key mapped the same way across modes collapses into one row (`<D-s>` → `n x i`). The group column prefers a desc's own `Group: Action` prefix over the which-key ancestor group — the ancestor says where a key lives, the prefix says what it's for, and that's what you scan for (`grn` sits under the `g` prefix, so which-key calls it "Go to", but you look it up as `LSP ›`). It also covers keys with no ancestor at all (`<D-…>`, `jj`). The ancestor wins back when it already names the prefix in one of its segments, being the richer label there (`Session/Quit ›` beats the bare `Session` that `Session: Stop saving` would impose). The desc then displays without that prefix, since the column already says it (the full desc stays searchable). A prefix is only trusted when it looks like a group label — not trailing whitespace, bracket-free, short — or `Scroll down N lines (default: half screen)` would promote its sentence fragment to a heading. Tags are derived from that same prefix (`"Git hunk: Stage"` → `git hunk`) and merged with `whichkey.lua`'s small override table for non-derivable extras (rust/diff/debug/lsp/ai cross-references); a derived tag that just repeats the row's own group is hidden from the pills (still searchable), leaving pills to mean "cross-reference"
- **`builtins.lua`** — Curated built-in normal-mode commands (motions, scroll, jumps) consumed by `pickers/keybindings.lua` since nvim has no API to enumerate built-ins
- **`autosave.lua`** — auto-save.nvim: triggers on BufLeave/FocusLost/QuitPre/VimSuspend (immediate) and InsertLeave/TextChanged (debounced 1s, cancelled by InsertEnter); excluded filetypes: oil, snacks_picker_input, mason, gitcommit, gitrebase, harpoon
- **(mini.notify)** — mini.notify: floating notification popups for `vim.notify()` calls (outline's guard declines, etc.); `lsp_progress.enable = false` suppresses noisy `$/progress` notifications from language servers; `:Notifications` reopens dismissed ones (like `:messages` but for mini.notify). No keymaps, no dedicated config file — set up inline in `plugins.lua`
- **`ai.lua`** — sidekick.nvim setup: Claude CLI integration (NES pinned off). snacks as picker, right-split layout
- **`ai_context.lua`** — overrides sidekick's `{position}`/`{function}`/`{class}` context vars (wired as `cli.context` in `ai.lua`) to emit Claude-native `@relpath#L<n>` / `@relpath#L<a>-<b>` mentions instead of sidekick's column-off-by-one, type/name-prefixed refs. No `require('sidekick.*')`, so it loads during sidekick's first-launch download; lazy-required — no Load-order entry
- **`pickers/aibuffers.lua`** — `<leader>ab`'s multi-select picker: open file buffers, all preselected (bare `<CR>` = old send-everything; `<Tab>` toggle, `<C-a>` all), confirm sends the chosen `@relpath` mentions. Lazy-required — no Load-order entry
- **`themes.lua`** — Theme registry (all theme plugins, variants, setup functions, overrides), persistence to `stdpath('data')/theme.txt`, `apply()` and `all_variants()`
- **`pickers/theme.lua`** — Custom snacks picker for live theme preview with restore-on-cancel
- **`pickers/qfhistory.lua`** — snacks picker over the quickfix / location-list history stack (`<leader>sQ` / `<leader>sL`): lists all N remembered lists (title + size, current marked `●`) and activates the chosen one via `:{nr}chistory` / `:{nr}lhistory`; built on `common.indexed_select`, captures the origin window so the window-local loclist opens in the right place. Lazy-required
- **`spell.lua`** — Spell helpers: `add_word()` wraps `zg` to skip duplicates before appending to the personal dictionary
- **`utils.lua`** — `gh()` URL builder, async nvim update check via Homebrew, `is_tmp_path()` — shared throwaway-directory test used by `session.lua` (don't save a session there) and `cleanup.lua` (sweep the ones already saved), `confirm()` floating yes/no popup for destructive keymaps (`<leader>qq`/`<leader>ax`; single-keypress `y` confirms, anything else — `n`/`q`/`<Esc>`/`<CR>`/losing focus — is No), `float_terminal_action()` — reusable run-in-a-floating-terminal keymap action shared by `rust.lua`'s clippy-fix and `pickers/gotargets.lua`'s Go run terminal (toggles an already-running job instead of killing it, and notifies when that drops a fresh picker selection)
- **`cleanup.lua`** — `:Cleanup` and the weekly unattended sweep (`auto()`, armed in `configs.lua`): prunes stale undo files, sessions, leftover shada temps, and oversized logs. Rules are mtime-based on purpose — see [On-disk state](#on-disk-state) for why undo can't be pruned by "is the source gone?"
- **`buffers.lua`** — Shared buffer classification: `special_filetypes` registry + `is_special(buf)` — "is this a non-code panel/terminal/CLI buffer?" Canonical home for the guard used by `<leader>o`/`<leader>O` (outline.lua) and `gb` (alternate-buffer toggle, keymaps.lua). Also a narrower `sidebar_filetypes` + `is_sidebar(buf)` (docked nav panels only — a strict subset that excludes terminals/CLI), used by the sidebar auto-quit autocmd, plus the left-edge sidebar coordinator (`is_sidebar_visible`/`close_other_sidebars`) the panel toggles swap through
- **`yank.lua`** — Yank helpers: relative/absolute paths, Claude @-references, GitHub permalinks
- **`animations.lua`** — Terminal-only Neovide-style animation (gated by
  `if vim.g.neovide then return end` — the inverse of `neovide.lua`'s guard,
  since Neovide already animates natively): smear-cursor.nvim (animated
  cursor trail, `:SmearCursorToggle`) and cinnamon.nvim (`keymaps.basic`
  animates existing scroll/jump motions)
- **`neovide.lua`** — Neovide GUI-only config (gated by `vim.g.neovide`): animation tuning, `option_key_is_meta = 'both'` so `<M-...>` keymaps work, proxy icon, floating corner radius, hide-mouse-when-typing, window-edge padding (4px sides / 4px bottom, matching iTerm2's pane margins), plus `<D-c>`/`<D-v>`/`<D-s>` clipboard/save and `<D-=>`/`<D-->`/`<D-0>` zoom keymaps. Startup-time settings (fork, frame, title-hidden, font) live in `neovide.toml` instead, since Neovide reads them before nvim launches.

### Plugin loading pattern

`plugins.lua` calls `vim.pack.add()` to register and download all plugins.
Each feature file then calls `vim.cmd.packadd('plugin-name')` to load its own
dependencies at the right time. Where order matters (e.g. `lsp.lua` does
`packadd` for mason -> mason-lspconfig -> lspconfig in dependency order),
the file handles sequencing itself.

Plugin versions are pinned in `nvim-pack-lock.json` (commit SHAs). It's a
native `vim.pack` lockfile (nvim writes it automatically; no code in this
repo touches it), living in the config dir so stow syncs it. `vim.pack.add()`
installs each plugin at the lockfile's pinned `rev` on a fresh machine.

### Updating plugins

`:lua vim.pack.update()` (all) or `:lua vim.pack.update({ 'name' })` (one)
fetches remotes and opens a review buffer listing the pending commits between
the locked rev and the newest one matching each plugin's `version` constraint
(`[[`/`]]` jump between plugins, `gO` lists them). Confirm with `:w` to apply
and bump the lockfile; `:q` discards and keeps the pin. `{ offline = true }`
reviews already-fetched changes without hitting the network. An unpinned
plugin (`version` omitted, e.g. grug-far) moves to its default branch's HEAD;
a ranged pin (`vim.version.range('1.*')`) only moves within that range.
**Commit `nvim-pack-lock.json` after confirming** — that's what propagates
the new pin to other machines.

**Skip the review buffer:** `<leader>up` (or `:PackUpdate`, both in
`plugins.lua`) runs `vim.pack.update(nil, { force = true })` — updates every
plugin with no confirmation, straight to rewriting the lockfile. No changelog
preview, so `git diff` the lockfile before committing; to undo,
`git checkout HEAD -- nvim-pack-lock.json` then `:restart`.

**Reminder to update:** `plugins.lua` nudges via `vim.notify` on the **2nd and
last Friday of each month at 10:00** local. nvim isn't a daemon, so it's
best-effort — a timer fires it if a session spans the instant, else a startup
catch-up shows it at the next launch past it. A cache stamp
(`nvim-pack-update-nudge`) dedupes to once per scheduled Friday; off when
headless / under claude-nvim.

### Load order

From `init.lua`: configs -> autocmds -> plugins -> picker -> treesitter_context ->
outline -> quickfix -> structural_select -> keymaps -> completion -> lsp -> rust -> debugging ->
golang -> testing -> ai -> format -> linting -> statusline -> session ->
git -> gitui -> terminal -> scratch -> grugfar -> titling -> whichkey -> autosave -> filetree ->
animations -> neovide -> cleanup.

`rust` must precede `testing` (`testing.lua` does `require('rustaceanvim.neotest')`,
which needs rustaceanvim on the runtimepath). `golang` must follow `debugging`:
`golang.lua`'s `require('dap-go').setup()` mutates `dap.adapters` /
`dap.configurations`, so nvim-dap needs to already be on the runtimepath —
`debugging.lua` is what `packadd`s it.


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
| 1000ms | Orphaned-plugin scan (`vim.pack.get` + notify) | `plugins.lua` |
| 2000ms, then every 2s | First all-buffer `checktime` sweep, then steady poll | `configs.lua` |
| 2000ms | Shell pre-warms (toggleterm float + bottom panel) | `terminal.lua` |
| 3000ms, restore-aware | Claude CLI pre-warm (sidekick) | `ai.lua` |
| 5000ms | Neovim update check (`brew info` spawn) | `configs.lua` |
| 30000ms | mason-tool-installer daily update check (`start_delay`) | `lsp.lua` |
| 120000ms | Weekly on-disk-state sweep (`cleanup.auto()`) | `configs.lua` |

The cleanup sweep sits last on purpose: mason-tool-installer *starts* at 30s
but downloads for minutes past it, so 2 minutes keeps a disk walk off a busy
disk. Only its auto-run is deferred — `:Cleanup` registers at startup.

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

### The keymap picker walks every mode, but only runs normal-mode maps

`<leader>sk` walking normal mode only used to hide exactly the keys worth
looking up (visual `Cmd+C`, insert `jk`). It now walks all six modes.

`<CR>` still executes normal-mode maps only: the picker closes back into normal
mode, so feeding a visual lhs would silently run whatever those keys mean in
normal mode. Other modes report where to press them instead, and so do scoped
rows (keys confined to a picker/panel) — feeding those chords would run their
*global* meaning, e.g. `<C-l>` moving to the right split instead of
send-to-loclist.

Ranking is on typed input alone: it opts out of `picker.lua`'s global frecency
boost (a keymap you keep picking is one you already know), and mode names stay
out of the search text, where they'd dilute short fuzzy patterns.

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
(e.g. via the alternate-buffer register). `gb` in `keymaps.lua` guards against
that separately, using `buffers.is_special()` (see below) to skip non-code
buffers before jumping.

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
`<leader>o`/`<leader>O` exempt every registered sidebar from their own guard
via `is_sidebar()` — see "Left-edge sidebars swap into each other" below for
why. When adding a similar code-only-keymap guard for a toggle that owns its
own registered panel, apply the same kind of exemption for that panel's own
filetype.

### Left-edge sidebars swap into each other

`<leader>e` (file tree) and `<leader>o` (outline) both want the true left edge
of the tabpage (aerial's `placement = 'edge'`, see "Special/sidebar windows
need pinning" above) — without coordination they'd stack side by side instead
of replacing each other. Each keymap calls
`buffers.close_other_sidebars(<its own filetype>)`, guarded on "am I already
visible?" so it fires on the *opening* edge only: closing a panel never
reaches into the others. Pressed from inside the other sidebar the keys swap;
from a code buffer they just toggle their own panel.

The coordinator lives in `buffers.lua` beside the `sidebar_filetypes`
registry that drives it, and splits its two jobs:

- **Visibility** comes from windows, not plugin APIs — uniform, and it works
  for a panel that exposes no `is_open()`. Floats are excluded, so aerial's
  nav popup doesn't count as owning the edge.
- **Closing** goes through each plugin's own API (`sidebar_closers`), since
  nvim-tree and aerial desync if their window closes behind their back. A
  window sweep follows anyway — a closer that errors would otherwise leave
  the panel open and silently break the swap — and warns if anything survives
  it. A panel may own several edge windows, so every match closes, not the
  first.

Scope differs by caller: a swap is current-tab, while `autocmds.lua`'s
auto-quit handler counts windows globally and uses `close_all_sidebars()`,
which sweeps every tabpage — otherwise it could strand a sidebar alone in
another tab, the thing it exists to prevent.

This is why sidebars are exempt from `outline.lua`'s `is_special` guard
(previous section): otherwise `<leader>o` from the file tree would decline
instead of swapping. The guard asks `is_special(0) and not is_sidebar(0)`
rather than naming filetypes, so a new sidebar is exempt automatically.
Terminals and the sidekick CLI stay **not** exempt — nothing to swap into.

**On the abstraction.** This was two inlined pairwise checks for a long time,
deliberately un-factored while it was a symmetric pair between exactly two
plugins. It was extracted when a third sidebar briefly landed (atone's undo
tree, since reverted — see `plans/README.md`) and kept afterwards: the
inlined version closed only the current tabpage, so the auto-quit handler
could strand a sidebar in another tab. Two panels don't need the indirection,
but they do need that fix, and the registry is now the only thing a third has
to touch.

### Panels stop at their last entry

The file tree, outline, and sidekick CLI panel are lists, not documents:
scrolling until the last entry sits at the top and the rest of the window is
blank is just dead space (sidekick hits it once its terminal-mode view
freezes into a regular buffer in normal/visual mode). `scrolloff`/
`sidescrolloff` do NOT fix this — no effect at EOF, and don't apply to a mouse
scroll at all (a past commit shipped that as a no-op: `38a7c0a`, reverted).
The `WinScrolled` handler in `autocmds.lua` clamps `topline`/`leftcol`
directly instead, via its own `clamped_panels` filetype list (kept separate
from `buffers.lua`'s `sidebar_filetypes`, which answers a different question
for the quit handler). scrolloff/sidescrolloff are still useful for their
actual job — padding around the cursor — which is why they're zeroed per
panel (see the next section for the trap in *how*).

### Regular buffers cap overscroll instead of clamping it to zero

Ordinary code buffers get a softer version in a second `WinScrolled` handler:
capped at ~30% of window height of blank rows below the last line, instead of
Vim's default (scrollable up to the last line at the very top row) — you
still want to pull the last line away from the bottom edge near EOF, just not
that far. Two gotchas vs. the panel version:

- This config wraps by default, so `topline` arithmetic doesn't hold (a
  wrapped line spans multiple screen rows). `screenpos()` gives the last
  line's real on-screen row directly; the target `topline` is found by
  search (decrement + recheck) instead.
- Correct via `winrestview()`, not a scroll command like `<C-y>` — the first
  version used `<C-y>` and it silently undershot the target, because
  cursor-relative scrolling is constrained by the global `scrolloff = 10`
  whenever the cursor sits on the last line. `winrestview()` sets `topline`
  directly and ignores `scrolloff`.

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

- **`block_for` gitcommit/gitrebase** — the guest process stays alive until the
  buffer is deleted, so git sees the edit complete. `git.lua`'s `<leader>w`
  wipes the buffer to unblock it; `<leader>x` empties + writes + wipes (git
  aborts on an empty message/todo) — `:cq` would quit the host.
- **Float handling** — flatten's `pre_open`/`post_open` hooks snapshot and
  close any open toggleterm floats, then restore them when the edit is done.
  All of it runs through `vim.schedule` because opening/closing floats
  synchronously during buffer transitions raises E1159.
- **Layout restore** — `'smart'` lands the guest in a code window, so
  `post_open` records the buffer it displaced (`flatten_prev_buf`) and `git.lua`
  shows it before wiping the guest — wiping a still-displayed buffer closes its
  window when another exists (e.g. the sidekick split). A fresh window `'smart'`
  spawned has no `flatten_prev_buf`, so the wipe closes it.
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
blank splits where the panels used to be. `session.lua` closes them
(`aerial.close_all()`, `api.tree.close_in_all_tabs()`, and any grug-far window
via a direct `nvim_win_close`) in persistence's `PersistenceSavePre` hook so the
synthetic windows are simply absent from the saved layout; you reopen them with
`<leader>o` / `<leader>e` / `<leader>sR` on demand. Any future plugin owning a
synthetic sidebar buffer needs the same close-before-save treatment. grug-far's
buffer is a *named* nofile buffer, so it's closed by an inline window sweep (not
its own `close`/`kill_instance`, which can pop a confirm prompt at quit).

(nvim-tree was originally left out of this hook on the unverified assumption
it was "handled some other way" — it wasn't, and hit the same blank-buffer
bug. Lesson: verify each panel individually, don't extrapolate from the one
that was actually tested.)

(Historical note: sessions saved *before* this hook existed baked in a `badd
NvimTree_N` line, which restored as a plain *listed*, empty-filetype buffer the
API close couldn't touch — a phantom `mksession` re-recorded every quit. A
temporary by-name buffer-wipe in the same hook self-healed those; it was removed
once every machine's sessions had been rewritten. If an ancient session file
ever resurfaces, hand-delete its `NvimTree_N` line.)

We deliberately **don't** remember aerial's open state and auto-reopen it. The
tempting way — a session-baked global (`let g:AerialWasOpen` via
`sessionoptions+=globals`) — has a broad side effect: `globals` isn't scoped to
one flag, it serializes *every* qualifying (capitalized-name, String/Number)
global into every session file and restores them on load, so any unrelated
plugin global gets its stale value resurrected on each restore. Not worth it for
a one-keystroke panel. (See `session.lua`'s posterity comment for the full
rationale, including why the flag would've had to be stored `0`/`1` rather than
a boolean.)

### Big files get a filetype rename, not a per-feature guard

`snacks.bigfile` doesn't disable anything. It renames the buffer's filetype to
`bigfile`, and *that* is the protection — every filetype-keyed subsystem then
never matches: LSP (`vim.lsp.enable` is ft-matched, so document-highlight and
codelens go with it, since they only register inside `LspAttach`), nvim-lint
(`linters_by_ft` — killing both its BufReadPost and BufWritePost runs), conform,
aerial, render-markdown, treesitter-context, and native treesitter (whose
`FileType` autocmd in `plugins.lua` is patterned on `ts_filetypes`, which
doesn't include `bigfile`).

The alternative was an exported `is_large(buf)` predicate threaded through every
attach site. It would keep the real filetype — so `gc` and ftplugin survive —
but it costs ~8 edit sites, each with a different attach lifecycle (LSP
per-client, gitsigns per-buffer, aerial per-backend, satellite per-window), and
every future ft-keyed plugin would need a fresh guard. The rename gets six
subsystems for free and stays correct as plugins are added. LazyVim reaches the
same conclusion: `bigfile = { enabled = true }` and no file-size logic of its
own anywhere.

The trade is real, and the price is paid in two places: `gc` breaks (no
`commentstring`, since no ftplugin ran), and the subsystems that *aren't*
ft-keyed — gitsigns, satellite, auto-save — keep running. Both are
accepted for now; `plans/large-file-protection.md` records the per-subsystem fix
if one bites.

**Two tiers, deliberately not unified.** snacks measures **bytes** (>1.5MB) and
**average line length** (>1000, the minified case). `is_large_buffer` in
`plugins.lua` measures **lines** (>50k) and gates treesitter only. Snacks has no
line-count criterion at all, and the gap is real: a 60k-line file of short lines
(~700KB) is not a snacks bigfile — its filetype stays `python`, LSP and
completion still work, correctly, because they cope fine — but a treesitter
parse plus `foldexpr` over 60k lines is the pathological part, and that guard
already blocks exactly it. The size arm of `is_large_buffer` is now largely
redundant, but it stays as the backstop for buffers snacks *can't* classify
(no on-disk file → `getfsize <= 0` → never renamed).

**`bigfile` is not in `buffers.lua`'s `special_filetypes`.** That registry means
"not a real editable code buffer" and its consumers *decline to act* — the
`<leader>o`/`<leader>O` outline guards, the quit-when-only-sidebars autocmd. A
big file **is** a real code buffer, just an expensive one; registering it would
make `<leader>o` refuse to open the outline on it. Same separation described in
[Non-code buffer exceptions need a shared predicate](#non-code-buffer-exceptions-need-a-shared-predicate).

### Sidekick's session backends shell out on every lookup

`State.get()` runs **every registered backend's `sessions()`** synchronously on
the UI thread, and two of them shell out — neither of which we asked for:

- **opencode** registers itself as a *load side-effect* of its tool spec, which
  sidekick `dofile`s merely because `opencode` is in the default `cli.tools`.
  Its `sessions()` runs a system-wide `lsof -iTCP -sTCP:LISTEN`: **40ms**.
- **tmux / zellij** register on `executable(name) == 1` *alone* — **not** on
  `cli.mux.enabled`, which only picks the backend for *new* sessions. Disabling
  mux does not stop their discovery. Installing tmux (the README recommends it
  for claude-squad) adds a full `ps` scan: 41ms → 63ms, measured with a stub
  `tmux` on `PATH`.

So `State.get` cost 40.8ms, and the detach sweep — 9 of them with 3 forked
sessions — froze nvim for **~370ms**. `ai.lua` stubs those backends'
`sessions()` to `{}` and prunes `cli.tools` to the two agents (`claude`,
`cursor`): now **0.05ms**. Stubbing only disables discovery of *externally
started* sessions; starting and attaching from nvim is untouched.

Three traps if you revisit this:

- **There is no config-level opt-out.** `cli.tools.opencode = false` leaves the
  key in `cli.tools`, so `Config.tools()` still `dofile`s and registers it.
- **Order.** `ai.lua` calls `Session.setup()` (normally lazy) so registration
  precedes the stub, which also warms `tool.lua`'s dofile cache — the spec then
  can't reload and quietly restore the real `sessions()`. Prune *after* the
  stub: pruning first leaves that cache cold, and one `tool.get('opencode')`
  brings the 40ms back with no signal.
- **Stub, never `nil`.** `Session.new` asserts `backends[name]` exists, so
  nil-ing tmux would hard-error if mux is ever enabled.

Pruning to the two agents also means no other spec is ever `dofile`d, so no
future upstream tool can reintroduce this. `cursor`'s spec is safe to keep —
bare `cmd`/`is_proc`/`url`, no `sessions()` scanner; check that before ever
keeping a third preset. The tool launcher (formerly `<leader>as`) stays
unbound even with two tools — a UX choice now, not a perf one (see
[AI (sidekick.nvim)](#ai-sidekick)).

### Rust keymaps fire on LspAttach, not FileType

`rust.lua`'s overrides (`K`, `<leader>ca`, etc.) used to be set on
`FileType == 'rust'` — silently broken, since `lsp.lua`'s `LspAttach`
handler rebinds the same keys on **every** attaching client, and a Rust
buffer attached *two* clients (rust-analyzer, then copilot — the latter removed
2026-07-20), both after
`FileType` already fired. The global handler always won, clobbering Rust's
richer variants back to plain LSP defaults — undetected until the
actions-preview.nvim work below surfaced it.

Fixed by triggering on `LspAttach` instead, filtered by
`vim.bo[buf].filetype == 'rust'` — not the client's name, since a
rust-analyzer-only filter still loses to any later-attaching client. `init.lua`
requires `lsp` before `rust` (Load order), so this handler always
registers, and fires, last — the winning write on every attach.

### Run output can't be re-shown, only re-run

`<leader>cR`'s output float can be **dismissed** (`q`/`<C-\>`) but not re-shown,
so `<leader>co` **re-runs** the last target rather than restoring old output.
Two dead ends, kept so they aren't re-attempted:

1. **toggleterm delists on job-exit** — a `TermClose` autocmd calls
   `delete(term.id)`, so `get(id)` is `nil` for any finished run (even with
   `close_on_exit = false`). Holding the `Terminal` object sidesteps this.
2. **The buffer is wiped on hide anyway.** Closing the float fires
   `BufWinLeave → BufHidden → BufUnload → BufWipeout` — Neovim's C-level
   teardown of a finished-terminal buffer (no Lua caller in the trace).
   `bufhidden = 'hide'` doesn't stop it, and it only happens interactively, not
   headless — which is why it survived every headless repro. (`stickybuf`
   ruled out: `prev_bufhidden` stayed `unset`.)

So `<leader>co` maps to a no-picker re-run (`RustLsp! run` for Rust,
`gotargets.rerun_last` for Go) — reliable, and a fast edit→re-run loop. True
peek-after-dismiss would need a buffer we own, never routed through a closing
window (snapshot the lines into a scratch buffer on exit) — not built; see
`plans/nvim-backlog.md`.


## Keymap index

All keymaps have `desc` strings. To discover them:
- `<leader>?` shows all global mappings via which-key
- which-key popup appears after 300ms on `<leader>`, `g`, `[`, `]`
- `<leader>sk` fuzzy-searches every keymap in every mode (including built-ins)
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
| `]q`/`[q`, `]Q`/`[Q` (and `]l`/`]L` for the loclist) | Quickfix / location-list navigation — entries and history stack | keymaps.lua | [Quickfix & location lists](#quickfix-loclist) |
| `<C-\>`, `<C-/>` (also `<C-_>`) | Terminal (toggleterm) — `<C-\>` floating terminal, `<C-/>` bottom panel | terminal.lua | [Terminal (toggleterm.nvim)](#terminal) |
| `<leader>p*`, `gd`/`gD`/`gy`/`gri`/`grr`/`gai`/`gao` | LSP goto / peek floats / call hierarchy | lsp.lua | [LSP](#lsp) → Keymaps |
| `<leader>ca`/`ce`/`cd`, `K`, `<C-s>` | LSP hover / actions / diagnostics | lsp.lua | [LSP](#lsp) → Keymaps |
| `<leader>o`/`O`, `]a`/`[a`, `zh` | Symbol outline (aerial) | outline.lua | [Outline (aerial)](#outline-aerial) |
| `<leader>h*` | Git hunk stage/reset/blame | git.lua | [Git (Neogit)](#git-neogit) → Which git tool to use |
| `<leader>G*` | Neogit popups | gitui.lua | [Git (Neogit)](#git-neogit) → Opening it |
| `<leader>v*` | Diffview entry points | gitui.lua | [Reviewing diffs](#reviewing-diffs) → Command reference |
| `<leader>a*`, `<C-.>` | AI (sidekick CLI) | ai.lua | [AI (sidekick.nvim)](#ai-sidekick) |
| `<leader>c*` (Rust ft), `K` (Rust ft) | Rust actions | rust.lua | [Rust](#rust) → Keymaps |
| `<leader>cR`/`<leader>dR` (Go ft) | Go run/debug targets | golang.lua | [Go](#go) → Keymaps |
| `<leader>d*`, `<F5>`-`<F12>` | Debug (nvim-dap) | debugging.lua | [Debugging (nvim-dap)](#debugging) → Keymaps |
| `<leader>n*` | Test (neotest) | testing.lua | [Testing (neotest)](#testing) → Keymaps |
| `<leader>e` | File tree toggle | filetree.lua | [File Explorer (nvim-tree)](#file-explorer) |
| `<leader>tf`/`cf` | Format-on-save toggle / manual format | format.lua | [Format-on-save](#format-on-save) |
| `<leader>tL`/`cl` | Lint-on-save toggle / manual lint | linting.lua | [Linting (nvim-lint)](#linting-nvim-lint) |
| `<leader>us`/`uc` | Strip whitespace / reflow pasted text | keymaps.lua / edit.lua | [Editing utilities](#editing-utilities) |
| `<leader>uu` | Undo history picker | keymaps.lua | [Picker (snacks.nvim)](#picker-snacks) → Undo history |
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
| `gb` | Toggle to the alternate buffer (deterministic `<C-^>`, but skips non-code buffers — see `buffers.lua`) | keymaps.lua |
| `<leader><leader>` | Smart picker (frecency-ranked buffers + recent + files, cwd-scoped) — see [Picker (snacks.nvim)](#picker-snacks) | keymaps.lua |
| `<leader>bx` | Close buffer, keep split (via mini.bufremove) | keymaps.lua |
| `<leader>bo` | Close all other listed buffers (skips modified and special/non-code buffers, reports counts) | keymaps.lua |
| `<leader>qq` | Quit all (`:qa`, behind a floating confirm popup — `y` confirms, anything else is No) — grouped under the `Session/Quit` which-key label alongside `<leader>qs/qS/ql/qd` (see [Session](#session)) | keymaps.lua |
| `<C-h/j/k/l>` | Split navigation | keymaps.lua |
| `<A-h/j/k/l>` | Resize split (narrower / shorter / taller / wider), repeatable without re-pressing `<C-w>` | keymaps.lua |
| Visual-mode indent | Indent selection, keeps it selected for repeat | keymaps.lua |
| `<leader>td` | Toggle diagnostics (virtual_text + signs) | keymaps.lua |
| `<leader>tn` | Toggle relative line numbers (`number` stays on, so the cursor line shows its absolute number) | keymaps.lua |
| `<leader>ts` | Toggle symbol-picker scope (workspace / buffer-only) | keymaps.lua / `pickers/symbols.lua` |
| `<leader>tq` | Toggle the quickfix window — `]q`/`[q` walk entries, `]Q`/`[Q` the history stack; see [Quickfix & location lists](#quickfix-loclist) | keymaps.lua |
| `<leader>tl` | Toggle the location-list window (window-local; `<leader>cd` fills it) — see [Quickfix & location lists](#quickfix-loclist) | keymaps.lua |
| `<leader>tp` | Toggle the snacks Lua profiler — stopping opens a picker over the trace (group/sort/filter it with `Snacks.profiler.scratch()`); the session runs slower while it's on, and the instrumentation stays wrapped until you restart nvim | picker.lua |
| `yp`/`yP` / `yc`/`yC` / `yu` | Yank relative / absolute path (`yp`/`yP`); Claude @-reference, relative / absolute path (`yc`/`yC`); GitHub permalink (`yu`) — in a picker, `<C-S-U>` yanks the item under the cursor | keymaps.lua / yank.lua |
| `<leader>uo` / `:Typora` | Open the current file in the Typora app (saves pending changes first) | keymaps.lua |
| `<leader>up` / `:PackUpdate` | Update all plugins with no confirmation, then commit the lockfile — see [Updating plugins](#updating-plugins) | plugins.lua |
| `jj` / `jk` (insert mode) | Exit to normal mode | keymaps.lua |
| `<M-b>` / `<M-f>` | Word back / forward — Option+Left/Right, which the terminal sends as literal Meta+b/Meta+f (see keymaps.lua comment) | keymaps.lua |
| `<M-BS>` (insert mode) | Delete word left — Option+Backspace, sent as Meta+Backspace by the terminal | keymaps.lua |
| `<M-d>` (insert mode) | Delete word forward — Option+D, readline convention | keymaps.lua |
| `<C-CR>` (in any picker) | Send selection(s) to the AI CLI | see [AI (sidekick.nvim)](#ai-sidekick) |

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

**Call hierarchy:** `gai` (calls incoming — who calls this) / `gao` (calls
outgoing — what this calls) open `Snacks.picker.lsp_incoming_calls()` /
`lsp_outgoing_calls()`. `a` is from "calls" (`c` was already taken by
comment.nvim's `gc`). No `vim.lsp.buf` fallback exists for call hierarchy, so
unlike the other `g*` maps above these are skipped entirely (not bound) when
snacks fails to load; gated on `textDocument/prepareCallHierarchy` support
(rust-analyzer and gopls both implement it).

**Hover, actions & diagnostics:**

`<leader>ca`/`gra` route through `aznhe21/actions-preview.nvim`
(`backend = { 'snacks' }`, `lsp.lua`) instead of plain
`vim.lsp.buf.code_action` — picking an action shows a diff before applying
it. A global upgrade for every language; Rust is the one exception with its
own key — see [Rust](#rust) → Keymaps for why.

| Keymap | Action |
|---|---|
| `K` | Hover — docs/type/signature float (not the source; use peek for that) |
| `<C-s>` (normal + insert) | Signature help |
| `<leader>th` | Toggle auto-hover on CursorHold |
| `<leader>ca` / `gra` | Code action (diff preview) |
| `grn` | Rename symbol |
| `grt` | Go to type definition (same as `gy`, without the picker) |
| `grx` | Run codelens under cursor |
| `gO` | Document symbols |
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

- **Format-on-save** is OFF — **formatting is manual, on `<leader>cf`**. The
  reason is the auto-save coupling, not `:w`: auto-save.nvim writes with a plain
  `silent! write`, so `BufWritePre` fires and conform runs on its writes too,
  and with auto-save's `InsertLeave`/`TextChanged` triggers plus a 1s debounce
  the buffer would reformat about a second after you stop typing, mid-edit. It
  was tried on for a day (2026-07-20) and turned back off. Not a quirk of this
  config — no editor ships debounced auto-save with format-on-save; VS Code
  refuses to format on a delayed auto-save and enforces it in source, and Zed
  documents the same rule. Don't simply flip `disable_autoformat` back: that's
  the arrangement that was rejected. Re-enabling means gating formatting off for
  auto-save's writes first — format on `BufLeave`/`FocusLost` and explicit `:w`,
  never on the debounced save (`format.lua`'s comment has the mechanism).
  `<leader>tf` toggles it on for the session, `vim.b.disable_autoformat` scopes
  it per-buffer, and `<leader>cf` formats manually regardless of both.
  Configured filetypes: Lua, Python, Go, Rust, JS/TS/JSON/YAML, TOML, XML, just
  via conform.nvim; anything else with a formatting-capable LSP goes through
  `lsp_format = 'fallback'`. Run `:ConformInfo` to see which formatter binaries
  are detected on `$PATH`.

- **Nvim 0.12 built-in keymaps** -- `K` (hover), `[d`/`]d` (diagnostic jump),
  `grn` (rename), `gra` (code action), `grt` (type definition), `grx` (codelens)
  and `gO` (document symbols) are nvim defaults. `grr`/`gri` are overridden to
  use snacks pickers; the rest are re-bound to the same functions purely to give
  them a `desc` — nvim sets them without one, so which-key and `<leader>sk` label
  them with their raw callee (`vim.lsp.buf.rename()`) and file them under no group.

- **Peek floats (`<leader>p*`)** — VS Code / GoLand-style peek via
  goto-preview; see the LSP *Keymaps* table for the jump/peek pairs. Tuned in
  `lsp.lua`: `focus_on_open = true` (cursor enters the float to scroll
  immediately) and `dismiss_on_move = false` (stays open while you look around)
  — flip either if the float feels too eager.

- **`<C-.>` terminal compatibility** — `<C-.>` (focus sidekick CLI)
  requires a terminal that sends CSI u sequences (kitty, iTerm2 with CSI u,
  WezTerm, Ghostty). macOS Terminal.app and some other terminals do not
  transmit `<C-.>` — use `<leader>ai` as a cross-terminal fallback.

- **Shift+Enter → newline in terminals** — inside `<C-\>` terminals (and the
  bottom panel), `<S-CR>` sends a linefeed so CLIs like Claude/Codex insert a
  newline instead of submitting (`terminal.lua`).
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
     - Forward side button → `Ctrl+I` (= Tab: they share ASCII 9, so in
       insert mode this button hits blink's `<Tab>` chain rather than
       jumping the jumplist — assign only if you can live with that.
       Normal mode works as intended: since NES's `<Tab>` map was removed
       it falls through to cinnamon.nvim's `<C-i>`, i.e. a smooth-scrolled
       jumplist-forward)

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

- **`<leader>ax` kills the session** — unlike `<leader>aa` (toggle, which
  just hides the window), `<leader>ax` calls `close()` which terminates the
  CLI process and deletes the buffer. Use `<leader>aa` to temporarily hide
  the chat; `<leader>ax` when you're done with the conversation. Guarded by
  a floating confirm popup (`utils.confirm` — single-keypress `y` confirms,
  anything else is No) — it sits one key from `<leader>aa`, so a typo can't
  silently discard a running conversation.

  With **multiple sessions** running, killing the active one (via `<leader>ax`
  or the `<leader>al` picker's `<C-x>`) repoints "active" to a *surviving*
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
LSP, file paths, snippets, buffer words.

Ghost text is disabled. It used to be, to avoid overlapping Copilot's inline
completion; since Copilot's removal (2026-07-20) the reason is different —
blink's `show_without_selection` defaults to `false` and this config sets
`preselect = false`, so ghost text would only render *after* you've `<Tab>`-ed
onto an item, where the menu already highlights it. Enabling it usefully means
setting `show_without_selection = true` **and** flipping `preselect = true`, so
`<CR>` accepts what's being previewed rather than nothing.

### Keymaps (inside the completion menu)

| Key | Action |
|---|---|
| `<Tab>` | Next item (then snippet placeholder jump, then a literal tab) |
| `<S-Tab>` | Previous item (or previous snippet placeholder when a snippet is active) |
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
| `<leader>tL` | Toggle lint-on-save globally — turning it off also clears nvim-lint's existing diagnostics |

**Diagnostics come from TWO subsystems, not just this one.** LSP servers
(lsp.lua) publish their own diagnostics — lua_ls, clippy via rust-analyzer,
eslint — which is why lua/rust/js/ts are intentionally absent from
`linters_by_ft`. nvim-lint covers what the LSPs don't: `ruff` (python),
`golangci-lint` (go), `credo` (elixir, via the project's `mix credo`),
`yamllint`, `checkmake`. When adding or auditing a linter, check lsp.lua too.

The `<leader>tL` toggle clears only nvim-lint's namespaces (named per linter,
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
  highlighting nor folding attached, to avoid UI lag. This is the *line-count*
  tier of large-file handling; the bytes tier belongs to snacks.bigfile, which
  disables far more than treesitter. See [Large files](#large-files).
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


## Large files

`snacks.bigfile` (enabled in `picker.lua`, which owns the single
`snacks.setup()`) protects you from opening a huge or minified file. It trips
when a file is **over 1.5MB**, or when its **average line length exceeds
1000** — the minified case, which a one-line 2MB `.js` hits despite being a
single line.

What it does is rename the buffer's **filetype to `bigfile`**. That rename *is*
the protection: everything keyed on filetype — LSP (and with it
document-highlight and codelens), nvim-lint, conform, aerial, render-markdown,
treesitter — simply never matches. On top of that you get `foldmethod=manual`,
no statuscolumn, no conceal, completion off, and matchparen off. Regex `syntax`
highlighting is re-enabled with the real filetype, so the file is still
readable, just not treesitter-highlighted.

You'll know it fired: a notification on open, and `:set ft?` says `bigfile`
(the statusline shows it too).

**Why `gc` doesn't work in a big file** — no ftplugin ran, so `commentstring`
is unset. `:setf lua` (the real filetype) brings commenting back, and
re-attaches LSP with it. There's no dedicated restore command; treesitter still
won't attach on a >1.5MB file, because the line/size guard in `plugins.lua` is
independent.

**What still runs on a big file** — gitsigns, satellite and auto-save are not
filetype-keyed, so the rename doesn't reach them. This is
a known, accepted gap; `plans/large-file-protection.md` records the fix for each
if one ever bites. Note gitsigns' own `max_file_length` is 40000 *lines*, which
a one-line minified file sails straight through.

**Two limits of the mechanism:** it needs a real on-disk file (a pasted or
`:enew` buffer is never classified), and it classifies at filetype-detection
time only — a buffer that's already open needs `:e` to be re-checked.

See Design Decisions →
[Big files get a filetype rename, not a per-feature guard](#big-files-get-a-filetype-rename-not-a-per-feature-guard).


<a id="picker-snacks"></a>
## Picker (snacks.nvim)

Fuzzy finder for files, text search, buffers, symbols, and help —
snacks.picker, pure Lua, no compiled extension. Global setup (layout,
frecency, shared actions) lives in `picker.lua`; the custom pickers live in
`pickers/*.lua`. Replaced telescope in 2026-07 — background and decision
record in `plans/telescope-vs-snacks-picker.md`.

**Layout:** pickers use a two-pane look — input on top, results below,
preview right — flipping to vertical (preview below) under 160 columns,
decided per open by `pick_layout` in `picker.lua`. Exceptions pin their
own layout: theme/keybindings use the compact `select` popup, the symbols
pickers vertical at 0.9×0.9. The `lines` source (`<leader>sb`) would
otherwise use snacks' bottom-docked ivy strip previewing in the *main
window* — `picker.lua` overrides it back to two panes and makes it start
empty like grep (see the keymap table). Both the global default and that
override are *functions*, not tables: snacks deep-merges layout tables
key-by-key (a table would inherit the ivy source's `preview = "main"` and
leak global keys into the compact popups) but replaces function layouts
wholesale.

<a id="picker-path-display"></a>
### Path display

Long paths in the results list are **left-truncated and width-capped**
(`…/websocket/marketdata/worker.go`) so the filename and nearest directories
stay visible without filling a wide list pane. Stock snacks center-truncates
(`packages/…/order.go`) and expands the path to the full list width, so on a
wide picker almost nothing truncates. Configured via
`formatters.file.truncate = 'left'` plus a wrap of `format.filename` that
clamps display width — **40 cells** by default, **60 for the files source**
(`<leader>sf`, path-only rows) — in `picker.lua`.

The **selected row's full cwd-relative path** is shown in the preview
window's border title (stock snacks puts only the basename there).
Implemented by wrapping `Snacks.picker.preview.file` after setup — not a
global `on_change` (that runs *before* the previewer and gets overwritten)
and not a top-level `preview` fn (would fight sources that pin their own:
diff, man, undo). An item that pins its own title (`preview_title`/`title`)
keeps it — same precedence stock gives those over the basename. Files
outside the project fall back to a `~`-shortened absolute path so the border
doesn't overflow.

`<C-y>` still copies the full relative path to the clipboard (same as the
list would show untruncated).

**Options still to experiment with** (parked in `plans/README.md` TODO;
knobs are under snacks' `formatters.file` unless noted):

- **Filename-first** — `filename_first = true` → `order.go packages/…/`;
  basename always visible, path truncated after. Good when many hits share
  a name and you scan by file first.
- **Tune `PATH_MAX` / `PATH_MAX_BY_SOURCE`** — default 40-cell cap in
  `picker.lua`, with `files = 60` for `<leader>sf`; raise/lower per source
  if a list feels too tight or too long.
- **On-demand notify** — flash/notify the full path for the current row
  without changing list or border chrome (you already have `<C-y>` yank).
- **LSP-only custom format** — per-source `format` on `lsp_references` /
  `lsp_definitions` only (two-line path + snippet, or left-truncate only
  there). Isolates experiments from files/grep.

### Keymaps

| Keymap | Action |
|---|---|
| `<leader><leader>` | Smart picker — buffers + recent + files merged into one frecency-ranked list (`sort_empty`, so it's ranked before you type), scoped to the cwd so files from unrelated repos don't show up. The alternate file is flagged `#` and usually near the top, but frecency isn't a deterministic row 1 — for the blind one-key jump-to-previous use `gb` ([Global keymaps](#global-keymaps)) instead |
| `<leader>sf` | Find files by name — fuzzy over the file list; `<c-g>` flips it to a live `fd` search (see below) |
| `<leader>sg` | Live grep (search file contents; see the live-vs-fuzzy note below) |
| `<leader>sw` (normal + visual) | Grep the word under the cursor, or the visual selection — exact match (`--word-regexp`, not fuzzy/live), jumps straight to usages without the `sg`-then-type step |
| `<leader>ss` (visual only) | Grep the **exact** visual selection, literal and multi-line included — see [Multi-line selection search](#multiline-selection-search). Normal-mode `<leader>ss` is workspace symbols (above); the visual binding is a separate command |
| `<leader>bb` / `<leader>m` | Buffer picker (numbered rows; `<M-1>`..`<M-9>` jumps to that row; `<C-x>` deletes) — see `pickers/buffer.lua` in Architecture. `<leader>m` is a permanent alias, one key shorter |
| `<leader>sh` | Search help tags |
| `<leader>sr` | Resume last picker (query, results, and selection restored) |
| `<leader>s/` / `<leader>sb` | Fuzzy search inside current buffer — starts empty until you type, like grep; line numbers use grep's file-name highlight |
| `<leader>so` | Recent files |
| `<leader>sm` | Modified files (git status; `<Tab>` stages/unstages; count prefix = last N commits + uncommitted) — see [Git (Neogit)](#git-neogit) → Which git tool to use |
| `<leader>ss` | Symbols (workspace) — fans query to all active LSPs; two-token prompt: first word is the name query sent to the LSP, remainder filters by file path (e.g. `render utils` finds symbols named "render" in files matching "utils"). Columns: icon, name, kind, client, path:line, source line. `<leader>ts` toggles to buffer-only mode; `<c-g>` freezes results for fuzzy refinement over all columns. Coverage gotchas: after a session restore only the LSPs of *visited* files join the fan-out ([Session](#session)), and servers match declaration names only — `impl` blocks and fields show up in `<leader>sd`, never here |
| `<leader>sd` | Symbols (document) — columns: icon, name, kind, line, source line (treesitter-highlighted); opens preselected on the symbol enclosing the cursor; type `function` / `variable` to filter by kind |
| `<leader>st` | Theme picker (live preview) — see [Themes](#themes) |
| `<leader>sq` / `<leader>sl` | Fuzzy-filter + preview entries of the quickfix / location list — see [Quickfix & location lists](#quickfix-loclist) |
| `<leader>sQ` / `<leader>sL` | Pick a whole list from the quickfix / location-list **history** stack — see [Quickfix & location lists](#quickfix-loclist) |
| `<leader>sk` | Keymap picker — columns: key (dynamic width), mode/scope (the vim mode(s) — `n`/`x`/`i`/… — or, for keys confined to a picker, that picker's name like `undo` in a distinct color), icon+group breadcrumb (dim), desc, tag pills (dim). Covers all modes. Keys display as `<Space>…` (which-key's spelling) but `<leader>…` searches too |
| `<leader>uu` | Undo history — browse this buffer's undo states, fuzzy-matched by the *content* of each change. See below; it's the one picker not under `<leader>s*` |

### Undo history

`<leader>uu` opens `Snacks.picker.undo()` over the current buffer's undo
tree — the payoff for `undofile`/`undolevels = 10000` in `configs.lua`, which
were writing history nothing ever read.

Rows are undo states — seq number, relative time, `+added`/`-removed` counts,
and a save icon on states where the file was **written to disk** — so only
some rows carry one, and it's how you spot "what this looked like at my last
save". Newest first. The prompt
fuzzy-matches the **text of the added and removed lines**, not the metadata:
type a word you remember deleting and you land on the state that deleted it.
The preview is a real unified diff.

**It is a real tree, not a flat list.** The finder recurses into each entry's
`alt` branches and tags every item with its parent, which the formatter draws
as the tree gutter down the left. So a branch you made and undid away from is
visible here — you don't need a separate graph UI to find it. (Worth stating
plainly because the opposite was assumed once, and an undo-tree plugin got
installed and reverted on the strength of it — see `plans/README.md`.)

**The reason to reach for it is yank-without-restore.** `<C-y>` puts the
state's *added* lines in a register, `<C-S-Y>` the *removed* lines — the
buffer is never touched. Recovering a deleted function means yanking it and
pasting where it belongs now, instead of time-travelling the whole file
backwards and losing everything since. `<CR>` does restore the state, when
that's genuinely what you want.

Three things are customized in `picker.lua`'s `sources.undo`, all of them
fighting stock layout rather than behavior:

- **A custom `format`.** Stock pads the seq column by `8 - gutter - #seq`,
  which goes negative once a branch nests deep enough, so nested rows shift
  right and stop lining up. Ours gives the gutter a fixed-width right-aligned
  field — glyphs still grow leftward with depth, but every column after it
  lands in the same place at any depth.
- **`previewers.diff.style = 'syntax'`** plus a `preview` wrapper that strips
  the git header and puts the filename in the preview window's border
  instead. The stock "fancy" renderer opens with a boxed filename and a boxed
  file icon — ~6 lines before content. One line of border beats six lines of
  chrome. The trade is losing the dual line-number columns and in-hunk syntax
  highlighting; diff colors only.
- **`SnacksPickerTree`** relinked to `Delimiter` in `themes.lua`'s
  `global_overrides` — it defaults to `LineNr`, which is tuned to disappear,
  leaving the branch shape unreadable.

Two notes on how it sits in the config:

- **Bound under `<leader>u`, documented under the pickers.** Every other
  picker is `<leader>s*`, and `<leader>su` was free. The keymap follows
  intent, the docs follow implementation: you press this because you *lost*
  something, not because you're searching for something, and `<leader>s*` is
  muscle memory for "find a thing in the project".
- `<C-y>` is bound globally to `copy_path` in `picker.lua`, but snacks applies
  per-source config after the global layer, so the undo source's `yank_add`
  wins here. `<C-CR>` (send to sidekick) still works and sends the *file* path —
  it says nothing about which undo state you were looking at.

<a id="multiline-selection-search"></a>
### Multi-line selection search

`<leader>ss` in **visual** mode greps the exact highlighted span, literal
(`--fixed-strings`, no word boundaries) and multi-line-aware, into a
read-only picker. Rows show `relpath:line` + the first matched line; a
`+N↵` badge marks a match spanning `N` extra lines. Lives in
`pickers/grepselection.lua`.

**Why not `Snacks.picker.grep_word` with a flag.** Snacks' grep source can't
render a multi-line match — it parses `rg`'s output one physical line at a
time, so a match containing a newline breaks the parser. This picker uses
`rg --json --multiline` instead, where each match is one JSON line
regardless of span, keeping line-by-line parsing safe. Flags otherwise
mirror the grep source (`--hidden`, `--smart-case`, exclude
`.git`/`node_modules`).

**The prompt fuzzy-filters the fixed hit list**, matched against
`relpath:line` + the first matched line only — a word on a match's 2nd/3rd
line won't narrow it (open TODO in `plans/README.md`). The preview still
highlights the whole span (`pos`→`end_pos`).

**vs. `<leader>sw`.** `sw` is whole-word (`--word-regexp`): jumps to
standalone identifier usages, skipping substrings. `ss` has no word
boundary, so it's the pick for multi-word, punctuation-terminated, or
multi-line selections — exactly where `--word-regexp` drops matches. For an
**editable** find/replace, use [grug-far](#grug-far) (`<leader>sR`) instead.

<a id="picker-query-syntax"></a>
### Query syntax: live vs fuzzy

Every picker is a **finder → matcher** pipeline. The finder produces the
candidates — `rg` for grep, `fd` for files, an LSP request for symbols, or just
a static list (buffers, git status, keymaps). The matcher then fuzzy-filters
that list in Lua. There are **two separate query slots, both always applied**,
and the only question is which one your keystrokes go into:

- **live** — the prompt feeds the *finder*, in that tool's own language.
- **fuzzy** — the prompt feeds the *matcher* (snacks' fzf-style engine).

`<c-g>` toggles between them. Grep and symbols **start live** (their finder
needs a query — there's no way to hold every line in the repo, or every
workspace symbol, in memory up front); files **starts fuzzy** (`fd` hands over
the whole file list at once, and fuzzy-matching a path beats regex-ing it);
fixed-list pickers are **fuzzy-only** (nothing to re-query, so `<c-g>` just
warns). The rule in one line: *live when the finder can't give you everything,
fuzzy when it can.*

**The title tells you where you are.** `󰐰 LIVE` shows while live; a `󰐰 <c-g>`
chip shows while fuzzy *in a picker that can flip* (grep, files). One or the
other, never both, and neither in a fixed-list picker. The query you're *not*
typing into sits to the left of the prompt, still filtering.

Two consequences worth internalizing:

- **The finder decides what *exists*; the matcher only decides what you *see*.**
  No fuzzy pattern brings back a result the tool never emitted. Grep `foo`, and
  the matcher can only ever narrow those foo-lines — it can't find a line with
  `bar` on it.
- **The two queries stack**, so `<c-g>` is freeze-then-refine in both
  directions: grep, then fuzzy-narrow the hits; or fuzzy-filter files, then flip
  to `fd` for a real file predicate.

<a id="picker-and-or"></a>
### AND, OR, and literals

The catch is that a space (and `|`) mean **different things in each mode**,
because the string goes to a different reader. This is the table to keep:

| goal | fuzzy (matcher) | live grep / files (regex) |
|---|---|---|
| A **and** B | `animal dog` (space = AND) | no operator — see below |
| A **or** B | `animal \| dog` (spaced `\|`) | `animal\|dog` (regex alternation, no spaces) |
| literal substring | `'animal` (leading quote) | already literal-ish; it's a regex |
| starts / ends with | `^src` / `.go$` | `^src` / `\.go$` (regex anchors) |
| exclude | `!test` | `-- -g '!*test*'` or a negative lookahead |

Two traps fall straight out of that table:

- **Fuzzy OR needs the spaces.** `animal | dog` is OR; `animal|dog` (no spaces)
  is a *single* fuzzy term containing a literal `|`, which matches nothing.
  Live grep is the reverse — `animal|dog` is the OR, and spaces would be
  literal. `|` also binds tighter than fuzzy's space-AND, so `dog animal | cat`
  reads `dog AND (animal OR cat)`.
- **Fuzzy terms are subsequences, not substrings.** `dog` matches `d`…`o`…`g`
  scattered across a path, so `.rs` will pull in `Nord.itermcolors`. Quote it —
  `'dog`, `'.rs` — when you mean the literal.

**AND on one line in live grep** has no regex operator, so pick one:

- **`<c-g>` then a space** — grep the rarer word, freeze, then fuzzy `animal dog`
  (space = AND) over the frozen lines. Usually the least typing. This is the
  seam the toggle exists for: rg has no AND, the matcher does.
- **spell out both orders** — `animal.*dog|dog.*animal`, staying live.
- **PCRE2 lookahead** — `(?=.*animal)(?=.*dog) -- -P` (the `-P` switches rg to
  the PCRE2 engine; its default engine has no lookahead and will error). This is
  the real order-independent AND, and it scales to three+ terms.

(All three are AND *within a line*. "Files containing A somewhere and B
elsewhere" is a different question grep can't answer in one pass.)

<a id="picker-tool-flags"></a>
### Live-mode tool flags (` -- `)

In **live** mode only, everything after ` -- ` is passed as raw flags to the
underlying tool — this is the whole point of flipping `<leader>sf` to live, and
it's already on in grep. In fuzzy mode these are just more characters for the
matcher to chew on.

- **grep (`rg`):** `handleRequest -- -tgo` (only Go files), `-tgo -Ttest` (Go
  **minus** the test type — `-T` is `--type-not`), `-g '!*_test.go'` (exclude
  glob), `-w` (word boundary), `-s` (case-sensitive), `-F` (literal, not regex).
  `-ttest`/`-Ttest` and other bundled types come from `ripgreprc` — see
  [README → ripgrep](../../../README.md) for the full type list and the
  include-vs-exclude glob gotchas.
- **files (`fd`):** `conf -- -e lua` runs `fd -e lua conf` (extension `lua`),
  `-g '*.go'` (glob), `--changed-within 1d`, `-t f` / `-t d` (files vs dirs).

The tell for when you need this: if a query is really a question about the
*file* rather than its name — "only `.lua`", "changed today", "not a test" —
that's a live-mode flag, not something fuzzy can express. Fuzzy can only
*approximate* it (`lua$` tests the path string); `fd`/`rg` can actually ask.

<a id="picker-matcher-text"></a>
### What the matcher actually matches

The matcher matches an item's `text`, which is usually **more than the name you
see**: a grep item's text is the whole `path:line:col:matched line`, and an
`<leader>ss` item's is `name kind client_name relpath`. So a bare fuzzy term
filters across all of it at once — type `handler` in grep and you keep rows
whose *path or matched line* contains it. When you need to scope to one field,
use `field:value`: `file:`, `text:`, and in symbols `kind:` / `client_name:` /
`relpath:` (e.g. `file:lua$ 'function`, `client_name:gopls kind:method`).

<a id="picker-worked-examples"></a>
### Worked examples

- **`<leader>sg`** — `foo -- -tmd` greps markdown only, say 200 hits. `<c-g>`
  freezes them (`foo -- -tmd` moves left of the prompt, still applying); now
  `todo` filters those hits by path *or* matched line, `file:todo` by path
  alone, `!test` drops anything with "test" in the row. No `.go` file can come
  back — rg never emitted one.
- **`<leader>sf`** — `animal | dog` (spaced) fuzzy-matches either name in the
  path. Want actual Go files named ~animal? `<c-g>`, then `animal -- -e go`
  (name matches `animal` AND extension `go`). `animal|dog` unspaced does nothing
  in fuzzy mode; it's the *live* OR after `<c-g>`.
- **`<leader>sd`** — always fuzzy, so just type: `animal | cat` for either name,
  `foo function` for a symbol named ~foo whose kind is function (kind is in the
  item text).
- **`<leader>ss`** — its live prompt is two tokens by our design: first token is
  the LSP name query, **the rest filters by file path**. So `animal .go` =
  symbols named "animal" in Go files, and `animal gopls` does **not** filter by
  client (it looks for "animal" in paths matching "gopls"). For the client,
  `<c-g>` then `client_name:gopls`. `animal | cat` is **not expressible**: the
  LSP answered one query, so the frozen set has no cats to OR with — run it
  twice, or use `<leader>sd` if both live in one file.

**Inside a picker** (press `<C-h>` in any picker for its full live keymap
list — bindings below are the daily set):

| Key | Action |
|---|---|
| Type anything | Filter results (fuzzy, or live — see above) |
| `<C-n>`/`<C-p>` or `<C-j>`/`<C-k>` | Move down / up — **one row per key repeat**, so holding these is a bad way to cross a long list (see `<C-u>`/`<C-d>`) |
| `<C-u>` / `<C-d>` | Scroll the list up / down by half a window (`'scroll'`, ~26 rows here) — one keypress covers ~26× what a `<C-j>` repeat tick does, for the *same* render cost. This is the answer to "the list scrolls too slowly", not a faster key repeat. Stock snacks, and **never overridden** — delete/kill lives on `<C-x>` (below), not `<C-d>` |
| `<CR>` | Open highlighted entry — cursor line lands ~20% from the window top (custom confirm in `picker.lua`; `scrolloff=10` is the floor in short windows) |
| `<C-v>` | Open in vertical split |
| `<C-s>` | Open in horizontal split (overrides the global LSP signature-help key while a picker is focused) |
| `<C-t>` | Open in new tab |
| `<Tab>` / `<S-Tab>` | Toggle multi-select on the current row, move down / up |
| `<C-q>` / `<C-l>` | Send multi-selection (or all results if none selected) to the **quickfix** / **location** list and open it. `<C-l>` shadows the global move-to-right-split while the picker is focused |
| `<C-x>` | Delete the item under the cursor (or all multi-selected) in the pickers whose source supports it — buffer picker (close buffer), session/terminal pickers (kill), scratch / marks / git-branches. The picker stays open and refreshes; a no-op in sources with nothing to delete (files, grep) |
| `<C-CR>` | Send the highlighted entry (or multi-selection) to the active sidekick CLI as `@path`/`@path#L<n>` refs (Ctrl+Enter = send; joins the `<CR>`/`<S-CR>` Enter family) |
| `<C-y>` / `<C-S-Y>` | Copy the highlighted entry's path to the system clipboard — `<C-y>` cwd-relative (the string the list shows, and what `yp` yanks for the open buffer), `<C-S-Y>` absolute. A `:line` suffix is appended on rows that carry a position (grep, LSP, symbols). Closes the picker; no-ops on path-less rows (help tags, keymaps) |
| `<C-S-U>` | Copy the highlighted entry's **GitHub permalink** (HEAD-pinned SHA, `#L<line>` on positioned rows) — the picker twin of the `yu` buffer yank, sharing `yank.lua`'s URL builder. Notifies an error outside a GitHub repo |
| `<a-h>` / `<a-i>` | Toggle hidden / ignored files (files and grep; shown as flags in the title) |
| `<a-p>` / `<a-m>` | Toggle preview / maximize the picker |
| `<c-g>` | Toggle live ↔ fuzzy — grep, symbols, and files only (see above) |
| `?` (normal) / `<C-h>` | Show this picker's live keymaps in a popup (`<C-h>` is a custom alias, shadowing the global left-split key while a picker is focused) |
| `<Esc>` | Close in one press, even from insert mode (custom `cancel` binding; focus returns to the launch window) |

**Multi-select workflows:**
- `<Tab>` marks an entry (a dot appears in the gutter) and moves the cursor down; `<S-Tab>` marks and moves up. Repeat to build up a set.
- With a multi-selection: `<CR>` opens them all (first into the current window, the rest as buffers); `<C-s>`/`<C-v>`/`<C-t>` fan them into splits or tabs.
- `<C-q>` sends the selection to the quickfix list — or the entire result list when nothing is marked (handy after a grep when you want every match). `<C-l>` does the same into the window-local **location** list.
- Common pattern: `<leader>sg` → search → `<Tab>` the matches you want → `<C-q>` → `:cdo s/old/new/g | update`.

**Per-picker notes:**
- `<leader>bb`/`<leader>m` (buffer picker) — Tab a few buffers and press `<C-x>` to bulk-close them; the picker stays open.
- `<leader>sm` (gitstatus) — `<Tab>` is **overridden** to stage / unstage the file under the cursor (no multi-select in this picker); the list refreshes in place. Count-prefix it for a last-N-commits range mode — see [Reviewing diffs (diffview.nvim)](#reviewing-diffs) → "Past N commits".

**Tips:**
- Both file search and live grep include hidden files/directories (e.g. `.github/`); `.git/` and `node_modules/` are excluded (source opts in `picker.lua`).
- Frecency ranking is on: files you open often (and recently) float toward the top of file-ish pickers. The store lives under `stdpath('data')`; delete it to reset.
- Each row's score can be shown as a leading number via `picker.lua`'s `debug.scores` (off by default) — flip it to `true` to make the frecency boost above visible when tuning it.
- `<leader>sr` reopens the last picker with query and results intact — useful when you close it and want to get back.
- In the files picker, pasting `path:12:4` jumps to that line/column on `<CR>` (`file:line:col` prompt syntax).

### Commands

| Command | Purpose |
|---|---|
| `:checkhealth snacks` | Verify snacks and the picker's optional deps (sqlite, etc.) |


## grug-far

Interactive, buffer-based find & replace across the project — the editable
counterpart to the read-only snacks grep pickers. `<leader>sg` finds and
jumps; grug-far turns a search into an editable results buffer you tweak
(delete the rows you don't want) and then apply as a real replacement, with
live preview and per-line control. Setup lives in `grugfar.lua`; the plugin
lazy-loads on the first `<leader>sR` press. For a walkthrough (video + recipes),
see the [linkarzu guide](https://linkarzu.com/posts/neovim/grug-far/).

### Opening it

| Keymap | Mode | Action |
|---|---|---|
| `<leader>sR` | normal | Open a search & replace buffer, closing one already open |
| `<leader>sR` | visual | Same, prefilling the selection as the Search and setting `--fixed-strings`, so regex metacharacters in the selection stay literal |

The buffer has labelled fields, each on its own line — **Search**, **Replace**,
**Files Filter**, **Flags**, **Paths**. Navigate to a field's line and type;
results populate live below. The buffer is `transient` (unlisted, wiped on
close); search *history* persists separately (`\t`).

### The mental model: curate, then apply

**`\r` always replaces *every* match currently in the buffer — there is no
per-match confirm.** So you don't pick matches at apply time; you curate the
results buffer first, then apply what remains:

**search → curate the results buffer → `\r` applies exactly what's left.**

Two ways to curate, and they compose:

- **Subtractive — `dd` the rows you *don't* want.** The results buffer is a
  normal buffer, so `dd` a match row (or `dd` a file's header/path line to drop
  *all* its matches at once), Visual + `d` a range, `u` to bring a row back.
  Best for one-off "not that one" exclusions.
- **Rules — narrow with the fields.** `Files Filter` (`*.py`, `!*_test.go`) or
  `Paths` (`fixtures/animal.py`) shrink the match set before it ever appears.
  Best for "never the tests / only this subtree."

Then `\r`. `\s` (Sync All) is a *different* tool — see the note under the key
table.

**Undo is not a global safety net.** `\r` writes changes **straight to disk**
(libuv, bypassing the undo history) and reloads open buffers via `checktime`.
So there's no single `u` that reverts the whole replacement:

- A file that was **open** when you applied → `u` in *that* buffer reverts it
  (the reload preserves undo via `'undoreload'`, default < 10000 lines).
- A file that was **not open** → no in-editor undo; the change is disk-only.

The reliable revert is **git** — review the diff and `git restore <file>`. Run
big renames against a clean working tree so the diff *is* the undo.

### In-buffer keys

In-buffer actions hang off `<localleader>` (`\`) — this config's only
`<localleader>` consumer. The authoritative, always-current list is `g?`
in-buffer; this is a summary:

| Key | Action |
|---|---|
| `\r` | Apply the replacement to **every match in the buffer** (curate first — see above) |
| `\s` | Sync your **manual edits** to result lines back to source (not the same as `\r`) |
| `\l` | Sync only the **current result line**'s manual edit back to its file |
| `\v` | Sync only the manual edits within the **current file** |
| `\q` | Send the results to the **quickfix list** |
| `\e` | Swap engine (ripgrep ↔ ast-grep) |
| `\t` | Open search history |
| `\x` | Swap the replacement interpreter (string ↔ Lua/Vimscript) |
| `\S` | **Swap** the Search and Replace inputs (custom — see below) |
| `q` | Close the buffer |
| `g?` | Full in-buffer help |

`\l` / `\v` are finer-grained cousins of `\s` (Sync All) — sync just the line
under the cursor, or just the file it belongs to, when you don't want to push
*every* manual edit at once.

`\q` bridges to the [quickfix workflow](#quickfix-loclist): dump the matches to
the quickfix list, then walk them with `]q` / `[q` or batch-edit with `:cdo`.

`\S` is a **custom** key (defined in `grugfar.lua`, not a grug-far built-in): it
swaps the Search and Replace inputs. Handy as a one-key reverse — after applying
`a`→`b`, press `\S` then `\r` to turn it back into `b`→`a`. That's the closest
thing to "undo the last replace" for files that weren't open (recall `\r` writes
to disk — see the undo note above).

`q` is remapped from grug-far's default `\c` and runs the plugin's real
teardown (aborts an in-flight search + cleans up the instance), not a bare
window close. `:q` / `:close` also close it like any window.

### Engines: ripgrep vs. ast-grep

The default engine is **ripgrep** — line-oriented, regex. `\e` swaps to
**ast-grep**, a syntax-aware engine: patterns match the parse tree, so
`console.log($A)` matches regardless of whitespace and `$A` is a metavariable
capturing any argument. ast-grep is apply-only — `\r` works, `\s` (line sync)
does not.

### Scoping a search

A search is project-wide by default — we deliberately don't pre-fill any scope
(a silent `*.<ext>` filter would hide cross-language matches, a bad default for
a rename tool). Narrow it with one of two fields:

- **Files Filter** — *which* files, ripgrep-glob / gitignore syntax, one
  pattern per line: `*.lua`, `*.{ts,tsx,js}`, a subtree `lua/**`. Negate with
  `!` (`!*_test.go`, `!README.md`). "Same filetype as this buffer" = type
  `*.<ext>` here.
- **Paths** — *where* to search: directories or files, e.g. `lua/pickers`.
  Supports `~`, and the special `<buflist>` (open buffers) / `<qflist>`
  (quickfix entries).

Flags typed in **Flags** pass straight to the engine: `-i` ignore case, `-w`
whole word, `--hidden`, `--no-ignore`.

### Worked examples

Fields are lines in the buffer; navigate to one and type, then `\r` applies.
To revert, see the undo caveat above — `\r` writes to disk, so `git restore`,
not a global `u`, is the reliable undo.

1. **Project-wide rename.** `<leader>sR` → Search `getUserId`, Replace
   `getUserID` → `\r`.
2. **Replace highlighted text.** Visually select `user.profile.name`,
   `<leader>sR` — it prefills the selection and sets `--fixed-strings`, so the
   `.`s are literal → set Replace → `\r`.
3. **Restrict to one filetype.** Files Filter `*.lua` (or `*.{ts,tsx}`) →
   Search/Replace as usual.
4. **Exclude tests / a file.** Files Filter `!*_test.go` (or `!*.test.ts`,
   `!README.md`); `!` negates, stack multiple patterns one per line.
5. **Scope to a subdirectory.** Paths `lua/pickers` (searches only there), or
   Files Filter `lua/pickers/**`.
6. **Case-insensitive / whole word.** Flags `-i` (ignore case), `-w` (word
   boundary).
7. **Selective apply.** Run the search, then `dd` the result rows you *don't*
   want changed; `\r` only touches the rows that remain. Easier than crafting a
   perfect exclusion pattern.
8. **Include hidden / ignored files.** Flags `--hidden` and/or `--no-ignore`.
9. **Structural (ast-grep).** `\e` to swap engine → Search `console.log($A)`,
   Replace `logger.debug($A)` → `\r`. `$A` is an ast-grep metavariable matching
   any argument. (ast-grep is apply-only: `\r`, no `\s`.)

### Power move: multiline + Lua interpreter

grug-far's most powerful mode:

- Add `--multiline` in the **Flags** field so a single search/replace can span
  line breaks (patterns and replacements may contain `\n`).
- Press `\x` to swap the replacement input to the **Lua interpreter**: the
  replacement is then Lua code with the current match available as `match`, so
  you can compute replacements a static string can't express (case conversion,
  arithmetic, conditional rewrites).
- Caveats: `\s` (Sync all) is **disabled** under `--multiline`, and the
  ast-grep engine supports `\r` but not `\s` either — so multiline / ast-grep
  work is apply-only, with no line-sync.


<a id="quickfix-loclist"></a>
## Quickfix & location lists

A **quickfix list** is a persistent, navigable list of `file:line` locations —
grep hits, every caller of a function, a file's diagnostics — that you walk one
at a time, editing as you go. It's a worklist the editor holds for you so you
don't lose your place across thirty edits in a dozen files. If you've only ever
jumped around with the picker, this is what turns "find" into "find, then
methodically fix every one."

### The mental model

Two lists, told apart by *scope*, each with a history behind it:

- **Quickfix = your one main worklist.** There is exactly one, shared by every
  window; whatever you send to it replaces what was there.
- **Location list = a per-window scratch list.** Each window has its *own*,
  independent one. Use it for a side-task (this file's warnings) so it doesn't
  clobber the quickfix worklist you're partway through.
- **Both keep a 10-deep history** (`:help :chistory`) — a back-button for
  result sets. A second search doesn't erase the first; it's pushed one slot
  down the stack, still there to return to.

So "can I have more than one?" splits two ways: **one quickfix active at a
time** (with the last 10 remembered), but **many location lists at once**, one
per window. That's the whole reason both exist — quickfix for the shared task,
the loclist for something local to the window in front of you.

One idea covers the entire keymap: **lowercase walks entries** inside the
active list, **capital walks whole lists** in the stack.

|  | Quickfix (one, global) | Location list (per window) |
|---|---|---|
| Fill it | `<C-q>` from any picker · `grr` (LSP refs) · `:grep` | `<leader>cd` (diagnostics) · `:lgrep` |
| Next / previous **entry** | `]q` / `[q` | `]l` / `[l` |
| Newer / older **list** in the stack | `]Q` / `[Q` | `]L` / `[L` |
| Pick a list from the stack | `<leader>sQ` | `<leader>sL` |
| Fuzzy-filter + preview entries | `<leader>sq` | `<leader>sl` |
| Open the list window | `<leader>tq` | `<leader>tl` |

`:grep`/`:lgrep` run ripgrep (`grepprg`, `configs.lua`) — fast, smart-case,
`.gitignore`-aware — and auto-open the list. Quote a phrase (`:grep 'foo bar'`),
since a bare second word is read as a path.

All of `]q`/`[q`/`]Q`/`[Q` (and the loclist twins) wrap around at the ends and
notify on an empty list instead of raising a raw `E42`/`E553`. Entry moves
take a count like the built-ins they shadow (`3]q` skips three). A stack hop
(`]Q`/`[Q`) also announces the list it landed on — title and size — since
switching the active list is otherwise invisible.

### Example — a project-wide rename

You're renaming `parseConfig` everywhere.

1. `<leader>sg parseConfig` — live grep, say 30 hits across a dozen files.
2. `<C-q>` — all 30 land in the quickfix list and its window opens at the
   bottom.
3. `]q` jumps to the first hit; you edit it, `]q` to the next. The quickfix
   window stays open on the side as a checklist, marking which hit you're on;
   `[q` steps back if you overshoot.
4. Thirty edits later you've visited every one — none missed, place never lost.

Why the **window** and not the `<leader>sq` **picker** here: the picker closes
on every jump, so it can't be a standing checklist; the window can. The flip
side — the grep returned 200 hits and you only want the auth-related ones — is
exactly when `<leader>sq` wins: fuzzy-type `auth` down to 12 with a preview,
then jump. Haystack-narrowing vs. worklist-grinding, over the same list.

### Example — a side-quest that doesn't lose your place

Partway through that rename (quickfix holds your 30 hits), a file you open has
five warnings you'd rather clear first.

1. `<leader>cd` — this file's diagnostics go into *this window's* location
   list, a separate scratch list.
2. `]l` / `[l` walk the five warnings; you fix each.
3. Your quickfix rename list is untouched — `]q` resumes it exactly where you
   left off.

That's the payoff of the loclist being window-local: a detour that never
overwrites the main worklist.

### Example — bring back your last search

1. `<leader>sg TODO` → `<C-q>` — quickfix list #1.
2. Later, `<leader>sg FIXME` → `<C-q>` — list #2, now active; #1 is pushed into
   the history, not lost.
3. You weren't actually done with the TODOs: `[Q` — list #1 is active again,
   and `]q` / `[q` now walk the TODO hits. No re-running the grep.

`<leader>sQ` opens the whole stack as a picker instead — every remembered list
with its title (`:grep TODO`) and size, the current one marked `●` — to jump
straight to any of the last 10. `]L` / `[L` and `<leader>sL` do the same for a
window's location-list stack.

### Window mechanics

`<C-q>` already opens the quickfix window, so the first `<leader>tq` after it
*hides* it — `<leader>tq` is a toggle. `q` inside the window closes it too
(auto-mapped; see `autocmds.lua`). On an empty list `<leader>tq` notifies
instead of opening a blank split, and `<leader>sq` shows snacks' own "No
results found".

### The list window is editable (quicker.nvim)

`<leader>tq`/`<leader>tl` open a [quicker.nvim](https://github.com/stevearc/quicker.nvim)
window (setup in `quickfix.lua`): the same list, better styled, and **editable**.

- **`dd` / visual `d`** — prune entries, applied immediately (no `:w`, no file
  touched). quicker only removes, never adds or reorders.
- **Edit an item's text, then `:w`** — writes the change back to the source
  file, a visual `:cdo`. `autosave = 'unmodified'` saves that file too unless
  it has unsaved changes, which it leaves for you.
- **`>` / `<`** — expand/collapse ±2 context lines around each match.

A text edit only reaches the file on `:w`, and the `:w` must be **in the list
window** (deletion is the exception — it self-applies). The qf buffer is
excluded from auto-save (`autosave.lua`) so that save gate isn't bypassed on an
idle timer. Browse/filter with the snacks pickers (`<leader>sq`/`<leader>sQ`);
mutate in the quicker window.

`follow` is on: while the window is open, the list highlights the entry nearest
your cursor (scrolling it into view) as you move through the code — a live
"you are here" in the result set.

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

**Restored buffers load — and start their LSPs — lazily.** `mksession`
recreates background buffers with `badd`, which doesn't read the file, so
filetype detection and the LSP autostart chain only run when a buffer is
first *visited* (buffers shown in restored windows load immediately); once
started, a client stays alive for the whole session. So right after
`<leader>qs`, `<leader>ss` covers only the languages of files you've
focused at least once. Deliberately not "fixed" by eager-loading every
session buffer — that would launch every server in the session at startup
(rust-analyzer indexing alone can run 10s+).


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
| `<C-s>` | Open file in horizontal split |
| `<C-v>` | Open file in vertical split |
| `<C-t>` | Open file in new tab |
| `<C-x>` | Close the buffer for the file under the cursor (mirrors the picker's `<C-x>`; separate from `x` cut / `d` delete-file below) |
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
- `<leader>e` swaps with the other left-edge sidebars: pressed from inside the
  outline or the undo tree, it closes that panel and opens the tree instead
  (and vice versa). Only one left-edge sidebar is ever open at a time. See
  [Design Decisions](#design-decisions) → "Left-edge sidebars swap into each
  other".


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
shared predicate" and "Left-edge sidebars swap into each other".


<a id="terminal"></a>
## Terminal (toggleterm.nvim)

Setup lives in `terminal.lua`. A togglable floating terminal (85% of window)
that persists state across hides, plus a VS Code-style bottom panel.

### Keymaps

| Keymap | Action |
|---|---|
| `<C-\>` | Toggle floating terminal (normal, insert, or terminal mode) |
| `<C-/>` (also `<C-_>`, same physical chord — see Tips) | Toggle the bottom-panel terminal (dedicated horizontal split, pre-warmed) |
| `<Esc>` / `jj` / `jk` (in terminal) | Exit terminal mode → normal mode |
| `<C-h/j/k/l>` (in terminal) | Navigate to adjacent splits |
| `<M-]>` / `<M-[>` (in a float terminal) | Cycle to next / previous float (wraps) |
| `<M-n>` (in a float terminal) | Open a new auto-numbered float (lowest free id) |
| `<M-l>` (in a float terminal) | Indexed terminal picker — `<CR>`/`<M-1>`..`<M-9>` jump, `<C-x>` kill |

**Tips:**
- **Hide vs close**: `<C-\>` hides the terminal (state persists). `<C-d>`
  sends EOF to the shell and closes it entirely — faster than typing `exit`.
- **Multiple terminals**: prefix `<C-\>` with a count — `2<C-\>` opens
  terminal #2, `3<C-\>` opens #3. Each is independent.
- **Two encodings, one chord**: `<C-/>` and `<C-_>` are bound identically.
  Neovim receives `<C-_>` for this physical keypress inside terminal mode,
  and `<C-/>` from normal mode / the GUI — binding both means the toggle
  works regardless of which byte arrives.
- **Cycle between terminals**: `<M-]>`/`<M-[>` cycle to the next/previous
  open float, wrapping, in terminal and normal mode. (M-based because
  `<C-[>` is the same keycode as `<Esc>`, so a C-based pair would shadow it.)
- **Open a new terminal in place**: `<M-n>` opens the lowest free id in the
  1-99 pool without leaving the float buffer.
- **Switch between terminals**: `<M-l>` opens an indexed picker over the open
  floats — `<M-1>`..`<M-9>` jumps to that row, `<C-x>` kills and refreshes
  (same shape as the sidekick session picker; both use `pickers/common.lua`'s
  `indexed_select()`). `:TermSelect` remains the plain built-in.
- **`<M-]>`/`<M-[>`/`<M-n>`/`<M-l>` are float-only**: the bottom panel is
  deliberately a single dedicated terminal, so none of these bind inside it —
  only `<Esc>`/`jj`/`jk`, `<C-h/j/k/l>`, and `<S-CR>` do.
- **`<M-]>`/`<M-[>`/`<M-n>`/`<M-l>` mirror the sidekick CLI**: the same
  session keys as [AI (sidekick.nvim)](#ai-sidekick), for muscle-memory
  symmetry; each set is buffer-local to its own terminal kind.
- **Run a command**: `:TermExec cmd="make test"` — runs the command in
  terminal #1 and returns focus to your buffer.
- **Override direction ad-hoc**: `:ToggleTerm direction=horizontal` opens a
  split instead of a float for that toggle.
- **`<Esc>` caveat**: the `<Esc>` mapping exits terminal mode in all terminal
  buffers. TUI programs opened inside the terminal (e.g. `vim`, `htop`,
  `fzf`) also need `<Esc>` for their own UI — use `<C-\><C-n>` manually in
  those cases, or add a filetype guard in `terminal.lua`.
- **`<S-CR>` sends a literal newline** instead of submitting, inside these
  terminals and the bottom panel — see [LSP](#lsp) → Things to watch out for,
  "Shift+Enter → newline in terminals" for the CSI-u terminal requirement.


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
now tells the whole buffer story: `<leader>bb` picker, `<leader>bx` close,
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
| `<leader>Gg` | Neogit status | — | — |
| `<leader>Gc` | Commit popup | `gc` | `c` to commit |
| `<leader>Gp` | Push popup | `gp` | `p` (pushRemote) / `u` (upstream) |
| `<leader>Gu` | Pull popup | `gu` | `p` / `u` similarly |
| `<leader>Gl` | Log popup | `gl` | `l` for current branch log |
| `<leader>Gd` | Diff popup | `gd` | pick what to diff against |
| `<leader>Gb` | Branch popup | `gcb` / `gnb` | `b` checkout / `c` create / `x` delete |
| `<leader>Gr` | Rebase popup | `grb` | pick target (onto branch, interactive, ...) |
| `<leader>Gw` | Worktree popup | `gw` | `c` create / `d` delete / etc. |
| `<leader>Gq` | Closes Neogit — not a popup; the leader-namespaced twin of plain `q`, so both git views close alike | — | — |

**These are only mnemonic parallels, not equivalent actions.** Every alias
above runs its git command immediately; every `<leader>G*` mapping opens a
**popup** — Magit's core UX — landing on a menu of related sub-actions
rather than executing anything. `<leader>Gp` does not push by itself; it
opens the push menu, and you press a letter (shown in the popup) to push.
The upside: the popup surfaces flags your aliases hardcode (e.g. the push
popup offers force-with-lease inline, matching `gpf`, without a separate
keymap).

A `kind='floating'` variant and a `<leader>GG` floating opener are written
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

Committing (`c` then `c` in the commit popup, or `<leader>Gc`) opens a real
**`gitcommit`-filetype buffer** — the existing `git.lua` FileType maps and
signing flow apply unchanged: `<leader>w` confirms (write + close),
`<leader>x` aborts. If this ever fights the flow, `commit_editor.kind` in
`gitui.lua`'s `setup()` is the escape hatch.

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
  file with a diff preview; count-prefix it (`5<leader>sm`) for a last-N-commits
  range mode — see [Reviewing diffs (diffview.nvim)](#reviewing-diffs) → "Past N commits".
- **Neogit** (`<leader>Gg`) — full staging/commit/branch/rebase/worktree
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
kept as its own which-key group rather than folded into Neogit's `<leader>G*`
so the two tools stay visually distinct:

| Keymap | Opens |
|---|---|
| `<leader>vv` | Uncommitted changes (flow 1 below) |
| `<leader>vp` | PR vs base branch — diffs against the merge-base, not a plain two-point diff (flow 2 below) |
| `<leader>vn` | Last N commits, squashed (flow 3 below) |
| `<leader>vh` | Walk each of the last N commits (flow 3 below) |
| `<leader>vf` | Current file's history |
| `<leader>vc` | Cycle the 2-way layout, side-by-side ↔ stacked (leader-namespaced alternative to the default `g<C-x>`) |
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

Neogit shortcut: `<leader>Gg` → `d` → `u` (unstaged only) / `s` (staged
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

Neogit shortcut: `<leader>Gg` → `d` → `r` (range) → choose **2. Symmetric
Difference (a...b)** → supply `origin/main` and `HEAD` via the prompts.

### 3. Past N commits (less common)

Three ways to ask "what changed over the last N commits," each answering a
slightly different question:

- **"What changed, total?" (commit history only)** — `:DiffviewOpen
  HEAD~4..HEAD` (two-dot): one squashed diff across the range, browsed
  file-by-file like flows 1 & 2. Two-dot means both sides are commits —
  **uncommitted changes are not included**, unlike the `gd` shell function.
  Note `HEAD~4` alone (no `..`) diffs your *working tree* against that
  single rev, not a range. Keymap: `4<leader>vn` (count prefix) or bare
  `<leader>vn` (prompts for N).
- **"What changed, total — including anything I haven't committed yet?"**
  — the `<leader>sm` git-status picker, count-prefixed (`4<leader>sm`):
  exact `gd N` semantics (`git diff HEAD~4`), in the same numbered-row
  file list + diff preview as `<leader>sm`'s normal mode. Bare `<leader>sm`
  keeps today's uncommitted-only view; no prompt-for-N fallback here. Each
  row shows the newest commit that touched the file (blank if none did),
  with a trailing `~` if it's also still dirty on top.
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

Setup lives in `ai.lua`. Uses `folke/sidekick.nvim` for its **CLI integration**.

Sidekick's other feature, NES (Copilot-LSP next-edit suggestions), was removed
2026-07-20 — it went unused, and dropping it took Copilot's inline completion
with it. `ai.lua` pins `nes = { enabled = false }` rather than deleting the
block, because sidekick's default is on and the literal `false` is what stops it
registering a per-keystroke `vim.on_key` handler for a dead feature.

**CLI integration** — runs one or more agent CLI sessions (Claude Code and
Cursor's `cursor-agent`) in terminal splits, organized around the **active
session**: the CLI session whose window you last entered (default: the
pre-warmed `claude`). The pool is flat — a session's *name prefix* carries
its agent (`claude 2`, `cursor: tests`) and drives which binary spawns, and
every key below works the same on both agents. `<leader>aa` toggles the
active session, `<leader>ax` kills it, and **all send keys, `<leader>ao`,
`<M-a>`, and `<C-.>`/`<leader>ai` target it** — with several sessions
running, sends never stop to ask which one.

`<leader>an` spawns a **new** session in two steps: an agent picker
(the first item is highlighted, so plain `<CR>` confirms it — one extra
Enter vs the old claude-only flow, accepted; `cursor` is currently ranked
first as a trial, TODO in `ai.lua` to revisit), then a label prompt; `<Esc>`
cancels either step. A blank label auto-names the session: the bare agent
name (`cursor`) if nothing is running under it, else a number from a counter
shared across agents that never refills a freed number — so per-agent
sequences are non-contiguous by design (`cursor 3`). A typed label makes a
reusable named session (`claude: tests`, `cursor: docs`) that re-attaches if
you type the same label again.
`<leader>al` opens a snacks picker over running sessions to **switch**
(`<CR>`, which also makes that session active) or **kill** (`<C-x>`) one;
rows are numbered and `<M-1>`..`<M-9>` confirms that row directly.
Inside the CLI, `<M-]>`/`<M-[>` cycle to the next/previous running session in
place without leaving terminal mode (no `jj`/`jk` + `<leader>al` round-trip);
`<M-l>` opens the same switch/kill picker in place; `<C-]>` toggles back to
the last-used session (alt-tab style), `<M-n>` forks a new auto-named session
of the **active session's agent** in place (the one agent-scoped nav key —
cycling and the picker are pool-wide; bare-first naming applies, so it can
resurrect a dead bare `cursor` rather than numbering), and `<M-a>` hides the
panel (the `<leader>aa` toggle)
without first escaping terminal mode. Kill stays on the deliberate
`<leader>ax` path — there's no fast in-panel teardown.
In the CLI's **normal** mode, a few keys forward raw bytes to Claude's TUI
instead of hitting the unmodifiable terminal buffer: `u` sends Ctrl+_
(Claude's input-undo — vim's own `u` would just throw E21 here; the
binding is pinned in the stowed `claude/.claude/keybindings.json`),
`p`/`P` bracketed-paste a register into the prompt (yank in a code
buffer, paste straight into Claude), and `<C-u>`/`<C-d>` send
PageUp/PageDown to scroll Claude's view. `u` only means undo while
Claude's input box has focus; mid-stream or dialog states may ignore it.
These byte-forwards are bound in every sidekick terminal but tuned for
Claude's TUI — in a cursor panel `u` sends Ctrl+U (kill-line) instead:
cursor-agent has no true input-undo, and Claude's Ctrl+_ byte would cycle
the model there. The kill is unrecoverable and takes one line per press on
multi-line drafts.
There is **no tool launcher**: even with two agents in `cli.tools`,
sidekick's launcher (formerly `<leader>as`) stays unbound — `<leader>an`'s
agent picker is the single creation door, and a per-agent summon key would
break the flat-pool symmetry. See "Sidekick's session backends shell out on
every lookup" for why every other preset is dropped rather than merely
unused.

Sessions are keyed by `(tool name, cwd)`; each extra session is a
dynamically-registered tool name cloned from **its own agent's preset** —
the name's leading token picks the preset (strictly anchored, so
`claude: cursor-migration` stays claude). A missing agent binary notifies
and aborts instead of spawning a terminal that dies instantly. Only the
primary `claude` is pre-warmed — cursor sessions and claude forks cold-start
(~1–2s) on first open. Killing a session auto-unregisters its dynamic name
(a detach sweep); re-creating that name starts a **fresh** conversation (no
resume), and killing the last cursor session falls back to claude — the
deliberate home-base asymmetry (see `plans/sidekick-cursor-support.md`). A
very long label (≥16 chars) warns that reusing it from a different project
dir collapses to the same session. Nothing persists across an nvim restart
without the mux backend.

| Keymap | Action |
|---|---|
| `<C-.>` | Focus active CLI (any mode; CSI u terminals only) |
| `<leader>ai` | Focus active CLI (cross-terminal fallback for `<C-.>`) |
| `<leader>aa` | Toggle active CLI session (session stays alive when hidden) |
| `<leader>an` | New agent session — agent picker, blank label = auto-named, typed = reusable |
| `<leader>al` | Switch (`<CR>`/`<M-1>`..`<M-9>`) or kill (`<C-x>`) a running CLI session (indexed picker) |
| `<M-]>` / `<M-[>` (in CLI) | Cycle to next / previous running session in place (stays in terminal mode) |
| `<M-l>` (in CLI) | Open the switch/kill session picker in place (the `<leader>al` picker) |
| `<C-]>` (in CLI) | Toggle to the last-used session (alt-tab style) |
| `<M-n>` (in CLI) | Fork the active session's agent, auto-named, in place (labels stay on `<leader>an`) |
| `<M-a>` (in CLI) | Hide the panel in place (the `<leader>aa` toggle, no `jj`/`jk` first) |
| `u` (in CLI, normal mode) | Undo prompt input — Ctrl+_ in claude; Ctrl+U kill-line in cursor (no true undo there) |
| `p` / `P` (in CLI, normal mode) | Bracketed-paste a register into Claude's prompt (`"ap` pastes `@a`; default unnamed) — newlines insert, never submit |
| `<C-u>` / `<C-d>` (in CLI, normal mode) | Forward PageUp / PageDown so Claude's TUI scrolls |
| `<leader>ax` | Kill active CLI session (tears down process + buffer; floating confirm popup) |
| `<leader>ao` | Select prompt |
| `<leader>at` | Send `@file#L<n>` cursor ref (normal) or `@file#L<a>-<b>` selection ref (visual) |
| `<leader>ap` | Send file path to CLI (`p` = path, matches `yp`/`yP` yanks) |
| `<leader>af` | Send enclosing function as `@file#L<start>-<end>` (needs nvim-treesitter-textobjects) |
| `<leader>ac` | Send enclosing class as `@file#L<start>-<end>` (needs nvim-treesitter-textobjects) |
| `<leader>ae` | Send buffer diagnostics (`e`, mirrors `<leader>ce`) |
| `<leader>aE` | Send workspace-wide diagnostics (capital `ae`, wider scope) |
| `<leader>ab` | Pick open buffers to send as `@relpath` mentions (all preselected; `<Tab>` toggle, `<C-a>` all) |
| `<leader>as` (visual) | Send the literal selected text (visual `<leader>at` sends a ref instead) |
| `<leader>aq` | Send quickfix list |
| `<C-CR>` (in picker) | Send picker selection(s) to CLI as `@path`/`@path#L<n>` refs |

`<leader>af`/`<leader>ac` send a `@file#L<start>-<end>` ref for the
function/class at the cursor (resolved via `nvim-treesitter-textobjects`,
packadd'd in `plugins.lua`), not the code body; outside any function/class
the send is a benign "Nothing to send." no-op. The refs come from
`ai_context.lua`, which replaces sidekick's own renderer (off-by-one column,
unreliable cross-language name extraction) with Claude Code's native `#L`
mention shape (`{quickfix}` included); diagnostics and `{buffers}`/`{file}`
still use sidekick's stock `cli/context` module.

### There is no inline AI completion

Removed 2026-07-20, along with NES. Both were Copilot features on the same
`copilot-language-server` client, and neither is configured anymore: the LSP is
gone from `lsp.lua`, `vim.lsp.inline_completion` is never enabled, and the
`<leader>ta` toggle that covered both is unbound.

blink.cmp's own ghost text stays off too, but for a different reason now — see
[Autocompletion (blink.cmp)](#autocompletion).

### First-run setup

1. Restart Neovim — sidekick.nvim installs via `vim.pack`.
2. Install `claude` CLI if not already present.
3. Optional: install `cursor-agent` for Cursor sessions (README →
   "Cursor CLI (cursor-agent)").


<a id="debugging"></a>
## Debugging (nvim-dap)

nvim-dap + nvim-dap-ui + nvim-dap-virtual-text: the shared debug engine, its
docked UI (scopes, call stack, breakpoints, watches, REPL), and inline
variable values, wired in `debugging.lua`. nvim-dap itself registers **no
adapters or configurations** — every language's debug support comes from
something else declaring them (see the language-support table below).
`debugging.lua` only owns the generic engine, the UI, the signs, and the
global keymaps.

### UI and signs

dap-ui opens automatically when a session launches or attaches, and closes
automatically when it terminates or exits (`dap.listeners.before[...]` hooks
for `launch`/`attach`/`event_terminated`/`event_exited`). Breakpoint and
stopped-line signs reuse theme-styled diagnostic highlights: `●`
(`DapBreakpoint`, `DiagnosticError`) marks a breakpoint, `▶` (`DapStopped`,
`DiagnosticWarn` + `Visual` line highlight) marks the current stopped line.

nvim-dap-virtual-text shows each in-scope variable's current value inline on
its source line while stopped (e.g. ` = 42`), so you read state in the code
buffer instead of the Scopes pane; changed values highlight differently on
the next stop. It registers its own `nvim-dap` listeners and needs no
adapter/configuration, so it works for any language with a treesitter
`locals` query (Rust and Go both have one). This is unrelated to the LSP
*diagnostic* virtual text toggled by `<leader>td` — that's a different
feature entirely. Set up with defaults (bare `setup()`) — the plugin's own
defaults already fit: `virt_text_pos = 'inline'` places the value right after
the identifier rather than at end-of-line, `only_first_definition = true`
annotates a multi-line `let` chain once on its first line (not on every
continuation line), and `clear_on_continue = false` leaves values visible
(greyed) between stops instead of clearing them.

Its highlight groups are theme-driven, not `setup()` options:
`NvimDapVirtualText` (linked to `Comment`) for a normal value,
`NvimDapVirtualTextChanged` (linked to `DiagnosticVirtualTextWarn`) for a
value that just changed, `NvimDapVirtualTextError` (linked to
`DiagnosticVirtualTextError`) for an eval error (e.g. an optimized-out
variable). **Known interaction to watch**: on the currently-stopped line, this
`Comment`-colored text renders on top of the `DapStopped` sign's `Visual`
line highlight (above) — legible in the themes tested so far, but if a future
theme makes it hard to read, override `NvimDapVirtualText` with
`vim.api.nvim_set_hl` in `debugging.lua` rather than changing the sign's
highlight.

### Language support

nvim-dap needs an **adapter** (how to speak DAP to the debugger binary) and a
**configuration** (what to launch) before `<F5>`/`<leader>dc` can start
anything from a cold buffer:

| Language | Adapter | Supplied by | Cold-start entry point |
|---|---|---|---|
| Rust | codelldb | rustaceanvim (`rust.lua`) | `<leader>dR` / `grx` / `<leader>nd` |
| Go | delve | nvim-dap-go (`golang.lua`) | `<leader>dR` / `<F5>` / `<leader>dc` |
| Everything else | none | — | `<F5>` does nothing — nvim-dap has no configuration registered for the filetype |

**`<leader>dR` is the "start a session by picking a target" key in both
languages**, mapped buffer-locally by each: in Rust it opens rustaceanvim's
*debuggables* (real cargo targets); in Go it opens the [Go targets
picker](#go) (`golang.lua` → `pickers/gotargets.lua`), which enumerates real
`main` packages via `go list`. Both languages now enumerate actual targets —
rust-analyzer supplies Rust's, `go list` supplies Go's. `<F5>`/`<leader>dc`
(`dap.continue`) remains the raw-config path in Go: a cold start there still
opens the seven-entry launch-config picker (Attach, Debug (Arguments), etc. —
see [Go](#go)). The `<leader>dR` key is unmapped in any other filetype.

Rust's reliable entry point is `<leader>dR`, not `<F5>` — see
[Rust](#rust) for why. Go's seven launch configurations (registered by
`nvim-dap-go`) are listed in [Go](#go).

### Keymaps

**Debug** (global, `<leader>d*` = Debug group):

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

### Extending DAP to other languages

Debugging a new language needs an **adapter** and a **configuration**, both
keyed by filetype. Register them in `debugging.lua`, or in a language module
if the plugin supplies its own (rustaceanvim does this in `rust.lua`;
nvim-dap-go does it in `golang.lua`). Python via `nvim-dap-python` is the one-liner
case — it registers both itself:

```lua
-- plugins.lua:    { src = gh('mfussenegger/nvim-dap-python') },
-- debugging.lua:  require('dap-python').setup('uv')   -- or a python path
```

For a language with no such wrapper, register them by hand —
`dap.adapters.<x>` plus a `dap.configurations.<filetype>` list; see nvim-dap's
wiki for per-language recipes. Note that Mason already installs **codelldb**
(`lsp.lua`), which is a C/C++ debugger as much as a Rust one, so those two
need only a configuration — no new adapter binary. If the language also has a
neotest adapter, add it (see [Testing](#testing) → Extending neotest to other
languages) and `<leader>nd` starts working for it too.

<a id="testing"></a>
## Testing (neotest)

neotest: the shared test runner UI, set up as an extensible framework in
`testing.lua` — each language plugs in an adapter, its plugin goes in
`plugins.lua`, and its treesitter parser must be installed.

### Registered adapters

| Language | Adapter | Debug via |
|---|---|---|
| Rust | `rustaceanvim.neotest` — reuses rust-analyzer runnables | nvim-dap (`<leader>nd`) |
| Go | `neotest-golang`, runner `gotestsum` | nvim-dap via delve (`<leader>nd`) |

`<leader>nd` (debug nearest test) routes through the shared nvim-dap engine
either way — see [Debugging](#debugging) for that engine, and [Go](#go) →
`dap_mode = 'manual'` for a Go-specific wrinkle in how that wiring is kept
from corrupting the `<F5>` config picker.

### Keymaps

**Test** (global, `<leader>n*` = Test group):

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

To add a language: add its adapter plugin to `plugins.lua`, `require` it in
`testing.lua`'s `adapters` list, and ensure the treesitter parser is
installed. E.g. for Python:

```lua
-- plugins.lua:  { src = gh('nvim-neotest/neotest-python') },
-- testing.lua:  require('neotest-python'),
```

<a id="rust"></a>
## Rust (rustaceanvim)

IDE-grade Rust support, primarily via `rust.lua` (rustaceanvim), which plugs
into the shared [Debugging](#debugging) and [Testing](#testing) engines
rather than owning its own. rustaceanvim is the keystone — it takes over
rust-analyzer and, in doing so:

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
  **floating terminal** (workspace-aware `-p`). One float, reused across runs;
  dismiss with `<C-\>`/`q`. A custom `tools.executor` in `rust.lua` routed
  through `utils.float_terminal_action` (id 102), shared with Go's `<leader>cR`.
  `cargo test` runnables still go to neotest (`test_executor` unchanged).
- **`<leader>co`** — re-run the *last* runnable in that float, no picker
  (`RustLsp! run`); falls back to the picker if nothing's run yet. Re-run, not
  re-show — a dismissed run's output is gone (see [Design
  Decisions](#design-decisions) → "Run output can't be re-shown, only re-run").
  Same in Go.
- **`grx`** on the `fn main` line — runs the `▶ Run` codelens directly.
- **`:RustLsp run`** — run the runnable *at the cursor* (`:RustLsp! run` re-runs
  the last one — what `<leader>co` maps to).
- Or just a terminal: `<C-/>`, then `cargo run -p <crate>`.

### Debugging entry point

1. Set a breakpoint: **`<leader>db`** (or `<F9>`) — a `●` appears in the sign column.
2. Start the session: **`<leader>dR`** (Rust debuggables) → pick the target →
   rustaceanvim compiles it in debug mode, launches under codelldb, and stops at
   the breakpoint. dap-ui opens automatically (scopes, stack, breakpoints, REPL)
   and closes when the session ends — see [Debugging](#debugging).
3. Drive it with the shared Debug keymaps ([Debugging](#debugging) → Keymaps):
   `<F5>`/`<leader>dc` continue, `<F10>` over, `<F11>` into, `<F12>` out.

`<leader>dR` is the reliable entry point (it asks rust-analyzer for the exact
cargo target). `<F5>`/`<leader>dc` (`dap.continue`) is for *resuming* a paused
session — starting cold from it relies on rustaceanvim's auto-loaded configs
(see [Debugging](#debugging) → Language support).

### Testing entry point

`<leader>nn` runs the test under the cursor via `rustaceanvim.neotest`;
`<leader>nd` debugs the nearest test through nvim-dap (breakpoints honored).
See [Testing](#testing) for the full keymap table and the adapter list.

<a id="structural-search-replace-ssr"></a>
### Structural search & replace (SSR)

Semantic, project-wide find-and-replace for Rust — no plugin to install,
it's rust-analyzer's own SSR feature (`experimental/ssr` over LSP),
`<leader>cs` just wires a keymap to it. The key advantage over plain
regex/grep: it's **name-resolution-aware**, so a pattern only rewrites code
that actually resolves to the item you meant, not just anything that looks
the same by shape (see the UFCS example below).

`<leader>cs` prompts for a query and rewrites the whole workspace. Syntax:
`<search> ==>> <replace>`. Run it from visual mode to scope the rewrite to
the selection instead of the whole workspace.

**Placeholders.** `$name` matches — and captures — a whole AST node: an
**expression, type, path, pattern, or item**, so a placeholder works in type
position (`Option<$t>`) and pattern position (`Some($x)`), not just in
expressions. Reference the same `$name` on the replace side to reuse the
captured text. Constrain a placeholder by writing it as
`${name:constraint}` — the constraints are `kind(literal)` (match only a
literal, e.g. `42` or `"s"`) and `not(...)` (negate another constraint), so
`${x:not(kind(literal))}` matches any argument that isn't a literal. There is
**no** linear-pattern rule: repeating a placeholder does not require the two
occurrences to be equal — each binds independently and the last write wins,
so `$a == $a` matches any `x == y`, not just `x == x`.

**Examples** (pass the whole `<search> ==>> <replace>` string at the prompt):

- `foo($a, $b) ==>> ($a).foo($b)` — free function to method form:
  `foo(x, y)` becomes `(x).foo(y)`.
- `Foo{a: $a, b: $b} ==>> Foo::new($a, $b)` — struct literal to constructor;
  it matches by field *name*, so `Foo{b: 2, a: 1}` still rewrites correctly to
  `Foo::new(1, 2)`.
- `Result<(), $a> ==>> Option<$a>` — rewrites in type position:
  a signature `-> Result<(), Vec<Error>>` becomes `-> Option<Vec<Error>>`.
- `Foo::do_stuff($a, $b)` — an inherent method written in UFCS form also
  matches ordinary method-call syntax: it matches `f.do_stuff(2)` (where
  `f: Foo`), but **not** `b.do_stuff(1)` even though `Bar` has an
  identically-named `do_stuff` — the payoff of name resolution over a
  purely syntactic match. Drives a rewrite the same way as the other
  examples here; shown as a match to keep the receiver-type distinction visible.
- `try_!($a) ==>> $a?` — rewrites *inside* a macro invocation:
  `try_!(read(buf))` becomes `read(buf)?`. Within a macro call a placeholder
  matches tokens up to the next literal token in the pattern.

Unlike a purely syntactic tool (ast-grep, treesitter query search), paths in
the pattern must **resolve** — SSR only rewrites code that actually resolves
to the matched item (hence the UFCS example above discriminates by type), and
it auto-inserts `*`/`&`/`&mut` in the replacement to mirror autoderef/autoref
when the rewrite changes reference-ness. Inherent method calls are best
written in UFCS form (`Type::method($self, $arg)`) so the pattern resolves
unambiguously.

No query argument is passed from the keymap — rustaceanvim's `ssr` command
already falls back to `vim.ui.input` when called with none
(`rustaceanvim/commands/ssr.lua`), so `<leader>cs` is a thin wrapper around
`:RustLsp ssr`.

### Batch-fixing clippy lints

Fixes clippy lints across the **entire workspace in one shot**, instead of
fixing diagnostics one at a time as you happen to visit each file.

`<leader>cF` runs `cargo clippy --fix --workspace --allow-dirty
--allow-staged` in a floating terminal (fixed id 102, outside the 1-99 pool
`terminal.lua`'s count-addressable float terminals use, same convention as
the Go run terminal in `pickers/gotargets.lua` (101)) from the nearest
`Cargo.toml`'s directory.
This applies every lint rustc marks `Applicability::MachineApplicable`
across the whole workspace in one pass — it skips ambiguous or
semantics-changing suggestions, which still need a manual look. `checkOnSave`
(clippy) already reports diagnostics workspace-wide as you edit; this is the
batch-apply half of that loop.

Re-pressing `<leader>cF` while a fix is still running just toggles the
terminal's visibility instead of restarting it — deliberately: `--fix`
rewrites source files on disk, so killing it mid-write (the naive
shutdown-and-recreate a second press would otherwise do) risks leaving a
file partially rewritten. It only shuts down and starts a fresh run once the
previous one has actually exited (`utils.lua`'s `float_terminal_action`,
shared with the Go run terminal in `pickers/gotargets.lua` — which notifies
when it drops a fresh selection this way; a bare re-press here stays silent,
since toggling visibility is the point).

### Code action preview

`<leader>ca` and `<leader>cp` are two different UIs over the same
rust-analyzer actions, not a redundant pair: `actions-preview.nvim` (every
other language's `<leader>ca`, see [LSP](#lsp) → Keymaps) can't render
rustaceanvim's grouped-by-kind list — they're separate pickers with no hook
to compose. Use `<leader>ca` for the grouped picker, `<leader>cp` when a
diff preview matters more than grouping.

### Automatic workspace reload

rust-analyzer occasionally shows **stale diagnostics** after a crate-graph
change with no in-buffer edit to trigger reanalysis (branch switch,
pull/rebase, `Cargo.toml`/`Cargo.lock` edit) — an upstream limitation, not a
config bug. `rust.lua` auto-fires `:RustLsp reloadWorkspace` on focus/
terminal-leave when something relevant changed (session-wide, not
buffer-local — a backgrounded rust buffer can still trigger it), throttled
and self-healing if rust-analyzer hangs. See the comments above
`current_signature()`/`reload()` for the mechanics; `<leader>cw` (below) is
the manual, on-demand fallback.

### Keymaps

**Rust actions** (buffer-local, `rust` filetype only — from `rust.lua`):

| Keymap | Action |
|---|---|
| `K` | Rust hover actions (richer than plain LSP hover) |
| `<leader>ca` | Code action (rustaceanvim grouped variant) |
| `<leader>cp` | Code action preview — flat list, diff shown before applying |
| `<leader>cR` | Runnables — run a binary/target |
| `<leader>co` | Re-run the last runnable in the float, no picker (`RustLsp! run`) |
| `<leader>cm` | Expand macro under cursor |
| `<leader>cC` | Open the crate's `Cargo.toml` |
| `<leader>cs` | Structural search & replace (SSR) — prompts for a query |
| `<leader>cF` | Batch-fix clippy lints across the whole workspace |
| `<leader>cw` | Reload workspace — fixes stale diagnostics (see Automatic workspace reload above) |
| `<leader>dR` | Debuggables — start a Rust debug session |
| `grx` | Run/Debug codelens under cursor (native codelens, now functional) |

The global Debug and Test keymap tables live in
[Debugging](#debugging) → Keymaps and [Testing](#testing) → Keymaps.

### Troubleshooting

- **Stale diagnostics**: press `<leader>cw` (usually auto-fires on its own —
  see Automatic workspace reload above).
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

<a id="go"></a>
## Go (delve + neotest)

Debug and test support for Go, layered onto the shared engines the same way
Rust is: `golang.lua` is Go's language module — the mirror of `rust.lua` —
and owns the pcall-guarded `nvim-dap-go` setup (the delve adapter that feeds
`debugging.lua`'s shared engine) plus the buffer-local `FileType go` keymaps
(`<leader>dR`, `<leader>cR`). If `nvim-dap-go` ever fails to load,
`<leader>cR` keeps working and `<leader>dR` stays mapped — to a notify stub
saying Go debugging is disabled — rather than silently vanishing.
`neotest-golang` supplies the neotest adapter for `testing.lua` separately. Named `golang.lua`, not `go.lua`: `require('go')`
is ray-x/go.nvim's own module name, and taking it would either block adopting
that plugin later or force a rename — same shadowing rule as
`debugging.lua`-not-`dap.lua`. gopls (`lsp.lua`), goimports-on-save (conform),
and golangci-lint (nvim-lint) already cover editing, so `golang.lua` stays
narrowly scoped to debug/run targets.

### What Mason installs

- **`delve`** (exe `dlv`) — the Go debugger, consumed by nvim-dap via
  nvim-dap-go.
- **`gotestsum`** — the test runner neotest-golang shells out to instead of
  plain `go test`; plain `go test -json` interleaves test JSON with program
  stdout, which corrupts neotest's parsing.

Both are **source-built via `go install`** (same failure mode as any
`go install`-based Mason tool — see README's Mason callout); the Go toolchain
is already a documented prerequisite.

### Launch configurations

`require('dap-go').setup()` (called once, in `golang.lua`) registers
`dap.adapters.go` plus seven `dap.configurations.go` entries, by their exact
upstream names: `Debug`, `Debug (Arguments)`,
`Debug (Arguments & Build Flags)`, `Debug Package`, `Attach`, `Debug test`,
`Debug test (go.mod)`. These are what populate the picker on a cold-start
`<F5>`/`<leader>dc` in a `.go` buffer.

### You need a `go.mod`

Everything below builds a Go *package*, so it needs a module — a lone `.go` file
with no `go.mod` anywhere up the tree fails at the build step, both for delve and
for `go test`. This is why `fixtures/` carries a `go.mod`: without it `animal.go`
is editable (gopls, formatting, linting all work) but not runnable, debuggable, or
testable.

Outside a module, `<leader>dR`/`<leader>cR` don't even try: `pickers/gotargets.lua`
resolves the module root from the current buffer's directory
(`vim.fs.root(dir, 'go.mod')`); when that comes back `nil` it fires one WARN
notify (`Not in a Go module (no go.mod up the tree)`) and returns — no picker
opens, and there is no fallback to the seven-config picker (which would just
fail at the build step anyway).

### Common workflows

Keys are canonical in [Debugging](#debugging) → Keymaps, [Testing](#testing)
→ Keymaps, and this section's own Keymaps table below (`<leader>dR`/`<leader>cR`,
buffer-local to `go`); this is what to reach for, when.

**Run the test under the cursor** — `<leader>nn`. A pass/fail sign appears in the
gutter next to the test. `<leader>nf` runs every test in the file;
`<leader>nl` re-runs whatever you ran last (the fast edit-test loop);
`<leader>nq` stops a run in progress.

**See why a test failed** — `<leader>no` opens the output for the test under the
cursor (this is where `t.Log`, `t.Errorf`, and panics land). `<leader>ns` toggles
the summary tree, which lists every test in the file under a `neotest-golang`
root with its status, and lets you jump to or re-run individual tests;
`<leader>nO` toggles the persistent output panel if you'd rather keep it open
while you edit.

**Debug the test under the cursor** — put a breakpoint on the line you care about
(`<leader>db` or `<F9>`), then `<leader>nd`. neotest builds the test binary and
runs it under delve, stopping at your breakpoint with dap-ui open. Continue with
`<F5>`; the test's own output (`t.Log` and friends) prints into the `dap>` REPL
pane as it runs — that's what `outputMode = 'remote'` below buys, and it's easy to
miss because it only appears once execution moves past the logging line.

**Debug a program (not a test)** — breakpoint, then **`<leader>dR`**: the [Go
targets picker](#go) (`pickers/gotargets.lua`) runs `go list -e ./...` rooted
at the current buffer's module, lists every `main` package it finds — from
*any* buffer, including a library file — and on confirm launches the picked
one under delve (`require('dap').run(...)`, `outputMode = 'remote'` so the
program's stdout reaches dap's REPL). Breakpoint in `cmd/bar/main.go`, buffer
open in `internal/util/util.go`, `<leader>dR` → pick `cmd/bar` → delve stops
at the breakpoint, dap-ui opens.

**`<F5>`/`<leader>dc`** still opens dap-go's seven `dap.configurations.go`
entries — these are *tools*, not targets. Every one that *launches* something
is anchored to the current file (`program` derives from `${file}` or
`${fileDirname}`, `dap-go.lua`); `Attach` doesn't launch at all. That is
exactly why the picker above exists:

- **Debug** — the common case. `program = "${file}"`: builds and launches from the
  file you're in.
- **Debug Package** — `program = "${fileDirname}"`: the *directory* of the file
  you're in.
- **Debug (Arguments)** — like Debug, but prompts for command-line args first. Use
  **Debug (Arguments & Build Flags)** when you also need `-tags`, `-ldflags`, etc.
- **Attach** — attach to an already-running process instead of launching one.
- **Debug test** / **Debug test (go.mod)** — debug the test under the cursor
  directly through dap-go, bypassing neotest. `<leader>nd` is the better path;
  these exist for when you want the dap session without neotest in the loop.

**None of these seven can launch a *different* `main` package than the one
you're already sitting in** — in a `cmd/foo`-style repo you must be inside
the package you want to debug; from a library file there is no config that
will build your binary. `<leader>dR`'s targets picker above is the answer to
exactly that gap.

**Run a program** — **`<leader>cR`**: the same picker, titled *Go
runnables*; pick a `main` package and it runs `go run <import-path>` in a
float terminal (toggleterm) from the module root — reaching any main package
in the module, from any buffer, including a library file (the case a
hand-rolled `go run .` could never serve). The terminal is reused, never
stacked — but what a second `<leader>cR` does depends on whether the previous
run is still alive. Still running (say, a server): your new selection is
**not** launched — the existing terminal is toggled back into view with a
notify saying so; exit the running program first to actually start the new
one (deliberate, via `utils.lua`'s `float_terminal_action` — the same
no-kill guard that protects Rust's clippy `--fix` from being killed
mid-write). Already exited: the old terminal is shut down and the new
selection runs in a fresh one. It does **not** close on exit
(`close_on_exit = false`), so the program's output stays on screen after it
finishes; dismiss it with `<C-\>`/`q`. **`<leader>co`** re-runs the *last* target
in that float, no picker (`gotargets.rerun_last`) — the Go mirror of Rust's
`<leader>co`; re-run, not re-show (see [Design Decisions](#design-decisions) →
"Run output can't be re-shown, only re-run").

**It passes no arguments.** `<leader>cR` runs the package bare. For a program
that needs argv, open a terminal (`<C-/>`) and run `go run ./cmd/foo -flag`
yourself — or, if you want to *debug* it with arguments, use `<F5>` →
**Debug (Arguments)**, which prompts.

**Inspect while stopped** — dap-ui's Locals pane updates automatically. `<leader>de`
evaluates the expression under the cursor (or the visual selection); `<leader>dr`
toggles the `dap>` REPL, where you can run delve commands directly. Step with
`<F10>` (over), `<F11>` (into), `<F12>` (out).

**Finish** — `<leader>dq` terminates the session and dap-ui closes itself. If it
ever lingers, `<leader>du` toggles it.

### Keymaps

**Go actions** (buffer-local, `go` filetype only — from `golang.lua`):

| Keymap | Action |
|---|---|
| `<leader>dR` | Debuggables — pick a `main` package, debug it under delve |
| `<leader>cR` | Runnables — pick a `main` package, `go run` it in a terminal |
| `<leader>co` | Re-run the last `run` target in the float, no picker |

The global Debug and Test keymap tables live in
[Debugging](#debugging) → Keymaps and [Testing](#testing) → Keymaps.

### Targets picker: scope and limits

`pickers/gotargets.lua` is deliberately narrow. Read the source for the exact
behavior; the honest summary:

- **`main` packages only** — tests stay with neotest (`<leader>nn`/`<leader>nd`
  above); a package-granularity "debug all tests" would be strictly coarser
  (no `-test.run` filter, so delve stops at whichever test hits the
  breakpoint first) and would bury the short binaries list in noise.
- **Outside a Go module, it warns and does nothing** — see "You need a
  `go.mod`" above; no fallback to the seven-config picker.
- **A module with zero `main` packages closes the picker with one WARN**
  ("No main packages in this module") — a library-only module is a normal
  state, not an error. Only a `go list` run that *fails* and yields no
  targets reports an ERROR carrying `go list`'s stderr.
- **A broken package elsewhere in the module does not hide the good
  targets** — the enumerator runs `go list -e ./...`, so one unresolved
  import anywhere in the module still leaves every buildable `main` package
  on the list (with a WARN carrying `go list`'s stderr).
- **Nested modules aren't descended into** — `go list ./...` stops at any
  directory that has its own `go.mod`; open a buffer inside that module
  instead to enumerate it.
- **Build-tag-excluded packages don't appear** — a `//go:build linux`-only
  `main` is simply invisible on macOS, exit 0, no error to explain why.

### `dap_mode = 'manual'`

`testing.lua`'s `neotest-golang` adapter is configured with
`dap_mode = 'manual'`. This is load-bearing, not a preference: the default
(`dap_mode = 'dap-go'`) makes neotest-golang call `dap-go`'s `setup()` again
on every test debug — once from its own `setup_debugging()`, and once more
from a `dap.listeners.after.event_terminated` listener that restores the
original opts. `dap-go.setup()` **appends** its seven configurations instead
of replacing them (it only guards `dap.configurations.go == nil`), so under
the default mode, each debugged test would permanently add 14 stale entries
to the `<F5>` config picker. `'manual'` makes neotest build its own DAP
config from `dap_manual_config` and never call `dap-go.setup()` again — the
picker stays at seven.

`dap_manual_config` is passed as a **function returning a fresh table**, not as
a table literal, and that matters for the same reason: neotest-golang *mutates*
whatever it gets back (it sets `.program` and appends `-test.run <regex>` to
`.args`). A literal would be the same shared table on every run, so the
`-test.run` filters would pile up and a stale filter could silently debug the
previous test. The table it returns supplies `name`, `type = 'go'` (the adapter
dap-go registered), `request = 'launch'`, `mode = 'test'` (delve's test-binary
mode), and `outputMode = 'remote'` — without that last key the debuggee's own
stdout (`t.Log`, `fmt.Println`) never reaches dap's output, since delve defaults
to local mode. neotest injects `program`, `args`, and `cwd` itself.

### Troubleshooting

- **`-race` errors or crawls**: it's in neotest-golang's default
  `go_test_args`, and needs cgo + a C compiler (Xcode CLT covers it on
  macOS).
- **delve prompts for codesigning approval (macOS)**: run `dlv debug` once
  from a shell, in a real Go module, before trusting the editor path — it
  surfaces the one-time approval prompt somewhere legible.
- **`:checkhealth dap` can't validate the Go adapter**: `dap.adapters.go` is
  a *function*, not a table, and dap's health check just prints "Adapter is
  a function. Can't validate it." Use `:checkhealth neotest-golang` instead —
  it checks `go`/`dlv`/`gotestsum` on `PATH`, `go.mod` discovery, the parser
  version, and the `-race`-without-cgo case.
- **Don't put a scratch Go module under `/tmp`**: neotest-golang's health
  check flags `/tmp` and `/private/tmp` on macOS as known-problematic paths.
- **Restart nvim after Mason's first install.** If `gotestsum` isn't on `PATH`
  when a test runs, neotest-golang warns once, falls back to plain `go test`,
  and — importantly — *rewrites the `runner` option for the rest of the
  session*, so it keeps using `go test` even after Mason finishes installing
  gotestsum. On a fresh machine Mason installs ~30s into the first launch (see
  `start_delay` in `lsp.lua`), so that first session can silently run in the
  very stdout-interleaving mode gotestsum exists to avoid. One restart fixes it
  permanently.


## Animations

Neovide-style smooth cursor/scroll animation for terminal nvim. A terminal
(Ghostty included) has no concept of partial scrolling — it only redraws
cells from ANSI escapes — so this can't be done at the terminal layer; both
plugins animate by redrawing real text/extmarks in nvim itself. Setup lives
in `animations.lua`, gated by `if vim.g.neovide then return end` — the
inverse of `neovide.lua`'s guard, since Neovide already animates natively
(see [Neovide](#neovide) below) and running both would double-animate.

- **smear-cursor.nvim** — animated/smeared cursor trail. One off-default
  option: `legacy_computing_symbols_support = true` (smoother sub-cell smear
  glyphs; Ghostty renders that Unicode block natively, no font support
  needed). `smear_terminal_mode` defaults `false`, so toggleterm/sidekick
  terminal buffers are already excluded. `:SmearCursorToggle`
  disables/re-enables it. Tuning knobs live as commented-out defaults in
  `animations.lua`.
- **cinnamon.nvim** — animates cursor + window movement (`mode = "cursor"`,
  the default) for the keys below. `keymaps.basic = true`; `keymaps.extra`
  (which would also animate raw `h`/`j`/`k`/`l`) is left off — remapping
  basic motion keys is a bigger behavior change than "add animation" alone.

| Keymap | Action |
|---|---|
| `<C-u>` / `<C-d>` | Animated half-window scroll |
| `<C-b>` / `<C-f>`, `<PageUp>` / `<PageDown>` | Animated page scroll |
| `{` / `}` | Animated paragraph jump |
| `n` / `N` / `*` / `#` / `g*` / `g#` | Animated search-result jump |
| `<C-o>` / `<C-i>` | Animated jumplist navigation |

These are existing native motions re-bound to animated versions, not new
keys — per the keymap ownership rule, they're documented here only, not in
the Keymap index.

## Neovide

Runtime config and keymaps live in `neovide.lua`, gated by
`if not vim.g.neovide then return end` — terminal nvim skips the file
entirely. Startup-time settings (fork, frame, font) live in `neovide.toml`
instead, since Neovide reads them before nvim launches. Install/symlink steps
are in the repo README → "Neovide".

**Launch it bare (`neovide`, or the `neo` / `neok` aliases), not `neovide .`** —
the shell's cwd is inherited already, and the `.` reaches nvim as a directory
buffer that nvim-tree hijacks (netrw is off, `hijack_directories` on by
default), landing you in the file explorer instead of the startup screen. Same
as `nvim .` vs `nvim`; open the tree on demand with `<leader>e`.

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


## On-disk state

What this config persists between sessions, and what prunes it. Three roots:
`stdpath('state')` for things you'd miss if lost, `stdpath('data')` for what
can be re-fetched, `stdpath('cache')` for what regenerates. The spellfile is
the deliberate exception — it lives *inside* this repo so it can be committed.

| What | Where | Configured in |
|---|---|---|
| Persistent undo | `state/nvim/undo/` | `configs.lua` (`undofile`, `undolevels`) |
| Sessions | `state/nvim/sessions/` | [Session](#session) — `session.lua` |
| Marks, registers, `:`/`/` history, jumplist | `state/nvim/shada/` | nvim default, never overridden |
| Personal dictionary | `~/.config/nvim/spell/en.utf-8.add` | [Spell checking](#spell-checking) |
| Active theme | `data/nvim/theme.txt` | [Themes](#themes) — `themes.lua` |
| Picker frecency | `data/nvim/snacks/` | [Picker](#picker-snacks) — `picker.lua` |
| Scratch buffers | `data/nvim/scratch/` | [Scratch buffers](#scratch-buffers) |
| LSP servers, formatters, linters, DAP | `data/nvim/mason/` | `lsp.lua` (`ensure_installed`) |
| Plugin clones | `data/nvim/site/pack/core/opt/` | `plugins.lua`; versions pinned in `nvim-pack-lock.json` |
| Treesitter parsers | inside the nvim-treesitter plugin dir | `plugins.lua` |
| blink.cmp rust matcher + frecency | plugin dir, `data/nvim/blink/` | `completion.lua` |
| Update-check stamp | `cache/nvim/nvim-update-check` | `utils.lua` — mtime *is* the payload |
| Cleanup-sweep stamp | `cache/nvim/nvim-cleanup` | `cleanup.lua` — same idiom |
| Deleted files (`D` in the tree) | macOS `~/.Trash` | [File Explorer](#file-explorer) |

Each plugin also drops its own logfile under `stdpath('state')` (`lsp.log`,
`mason.log`, …). None are configured; the sweep truncates any that get large.

### Deliberately not persisted

- **Swapfiles** — off in `configs.lua`: crash `:recover` traded for auto-save
  writing ~1s after the last change (`autosave.lua`). Distinct from
  `undofile`, which is history for files already on disk.
- **Backups** (`backup`/`writebackup`) — off; the working tree and git cover it.
- **Folds and views** — no `mkview`/`viewdir`; folds recompute from treesitter.
- **Session auto-restore** — always explicit (`<leader>qs`). `sessionoptions`
  drops `terminal` and never adds `globals` — see [Session](#session).
- **Sidekick CLI sessions** — die with nvim; surviving would need the
  tmux/zellij backend left off in `ai.lua`.
- **DAP breakpoints** — cleared on exit.
- **Notification history** — mini.notify's `:Notifications` is in-memory only.

### Cleanup

`:Cleanup` shows what it would remove in a split, then asks to confirm;
`:Cleanup dry` previews without prompting. The same sweep runs unattended
weekly, 2 minutes after startup (see [Startup stagger
timeline](#startup-stagger-timeline)), and always notifies what it did — even
when that's nothing, so a quiet week looks different from a broken one.

| Rule | Threshold |
|---|---|
| Undo history untouched | 90d |
| Sessions untouched | 30d |
| Sessions whose branch is gone | 7d |
| Sessions for temp directories | 7d |
| Leftover `shada` temp files | 24h |
| Logs over 5MB | truncated, not deleted |

Sessions expire faster than undo because they're a clutter problem (the
`<leader>qS` list), not a disk one. `session.lua` also refuses to *write* a
session for a temp cwd, so the 7d rule only sweeps ones saved before that
guard existed.

**Why undo is pruned by age, not by "is the source file gone?"** — that rule
is unimplementable. Nvim names an undo file by replacing `/` with `%` and
doesn't escape a `%` already in the path, so `/a/b%c/d` and `/a/b/c/d` share
one file. Decoding can therefore point at a nonexistent path while the real
file is alive, destroying history. Age can't be fooled that way, collects
orphans anyway, and won't mistake a temporarily unreachable path (unmounted
volume, network share, rustup mid-upgrade) for a deleted one.

The dead-branch rule is the one place a name *is* decoded, and it stays
conservative: split on the last `%%`, require the decoded cwd to be a real
git repo, normalize branches through the same `gsub('[\\/:]+', '%%')`
persistence writes them with — without it every `feature/foo` reads as
deleted and its live session gets swept — and treat any git failure as keep.

**Not swept: Mason.** Largest dir by far (~1.1G) but it holds no version
history — each package dir *is* the current version, so age-based deletion
just re-downloads. An installed-vs-`ensure_installed` report also needs a
name map (`ensure_installed` has `lua_ls`; Mason's dir is
`lua-language-server`) or it flags healthy servers. Prune with `:Mason`.
