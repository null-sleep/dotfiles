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
installs, blink.cmp for completion, Telescope for fuzzy finding, treesitter
for highlighting/folding, lspconfig v3 API (`vim.lsp.config` + `vim.lsp.enable`).
Requires a Nerd Font for statusline separators and completion icons.


## Architecture

### File responsibilities

| File | Responsibility |
|---|---|
| `init.lua` | Sets leader key, requires all modules in dependency order |
| `configs.lua` | Core vim options (`updatetime`, `scrolloff`, tabs, undo, splits, etc.), auto-reload timer for external file changes, nvim update check |
| `plugins.lua` | `vim.pack.add` declarations for all plugins (including theme sources from `themes.lua`), orphan plugin detection, treesitter parser management, Telescope setup, render-markdown, autopairs |
| `keymaps.lua` | Global keymaps: Telescope pickers (`<leader>s*`), clipboard-aware yank, split navigation, buffer navigation (`H`/`L`/`<leader><leader>`/`<leader>m`), visual indent, diagnostic toggle, yank helpers (`yp`, `yc`, `yu`, etc.) |
| `pickers/buffer.lua` | Custom Telescope buffer picker (`<leader>m`): row-index column replaces telescope's bufnr column, `<M-1>`..`<M-9>` jumps to that row |
| `pickers/gitstatus.lua` | Custom Telescope git-status picker (`<leader>sm`): row-index column, XY status icons, `<M-1>`..`<M-9>` quick-pick, `<tab>` staging toggle |
| `pickers/common.lua` | Shared picker utilities: `bind_quick_pick(map)` binds `<M-1>`..`<M-9>` row-jump keys, used by buffer and gitstatus pickers |
| `pickers/symbols.lua` | Custom symbol pickers: `M.workspace` (`<leader>ss`) fans `workspace/symbol` to all active LSP clients with a two-token prompt (first token = name query sent to LSP, remainder = file path filter via matchfuzzy), custom kind icons, vertical layout; `M.document` (`<leader>sS`) wraps `lsp_document_symbols` with kind in the ordinal so typing "function"/"variable" filters by kind; `M.toggle_buffer_only` (`<leader>ts`) switches workspace mode between all-LSPs and buffer-only |
| `completion.lua` | blink.cmp: keymap preset (Tab priority: blink menu → Copilot ghost text → literal Tab), sources, auto-brackets, signature hints, fuzzy backend. Ghost text disabled — Copilot inline completion provides its own. |
| `lsp.lua` | Mason setup, mason-lspconfig, goto-preview setup (VS Code-style peek floats, `<leader>p*`), LspAttach autocmd (buffer-local keymaps + capability-gated features), diagnostic config, per-server `vim.lsp.config`, `vim.lsp.enable`. Note: `rust_analyzer` is intentionally absent — rustaceanvim (`rust.lua`) owns the Rust client (see the Rust section) |
| `rust.lua` | rustaceanvim: Rust LSP layer over rust-analyzer (started here, not in `lsp.lua`). Sets `vim.g.rustaceanvim` before `packadd` — rustup `server.cmd`, clippy-on-save, codelldb DAP auto-detect; buffer-local Rust keymaps on `FileType rust` (`<leader>cR` runnables, `<leader>cm` expand macro, `<leader>dR` debuggables, `K`/`<leader>ca` grouped hover/actions) |
| `debugging.lua` | nvim-dap + nvim-dap-ui + nvim-nio: debug engine and docked UI (auto-opens/closes with the session), breakpoint signs, `<leader>d*` + `<F5>`/`<F9>`–`<F12>` keymaps. Named to avoid shadowing `require('dap')` / `require('debug')` |
| `testing.lua` | neotest (extensible framework): test runner UI. Rust via rustaceanvim's adapter; `<leader>n*` keymaps (run nearest/file/last, debug nearest, summary, output) |
| `format.lua` | conform.nvim: per-filetype formatter chains, format-on-save toggle (`<leader>tf`), manual format (`<leader>cf`) |
| `statusline.lua` | lualine: sections (mode, path, branch, diff, diagnostics, lsp_status, location), powerline separators, global statusline |
| `session.lua` | persistence.nvim: branch-aware session save/restore, `<leader>q*` keymaps |
| `git.lua` | gitsigns: hunk signs, hunk navigation (`]c`/`[c`), staging/reset/blame keymaps (`<leader>h*`); satellite.nvim scrollbar with git/diagnostic/search marks; FileType autocmd for `gitcommit`/`gitrebase` adds `<leader>w` (`:write \| bd`, confirm) and `<leader>x` (`:cq`, abort with non-zero exit) |
| `gitui.lua` | Neogit (Magit-style git dashboard) + diffview.nvim: on-demand status buffer, shell-aligned `<leader>g*` popups, `kind='tab'`, signs disabled (gitsigns owns the gutter). Named `gitui` not `neogit` to avoid shadowing the plugin's own `neogit` Lua module |
| `filetree.lua` | nvim-tree: sidebar file tree with git status, LSP diagnostics, modified indicators, trash-on-delete, auto-close when last window; custom `on_attach` adds `l`/`h` navigation; `<leader>e` toggles tree and reveals current file |
| `terminal.lua` | toggleterm.nvim: floating terminal (85% of window), `<C-\>` toggle from any mode, `<leader>tt` discoverable alias; VS Code-style bottom panel (dedicated horizontal terminal, `<C-`>` / `<C-/>` / `<leader>tb`, pre-warmed, hides from within); TermOpen autocmd (toggleterm only, skips sidekick) sets terminal-mode keymaps (`<Esc>` exits to normal, `<C-h/j/k/l>` navigate splits, `<C-]>` cycle next terminal) |
| `whichkey.lua` | which-key: group labels, explicit trigger list, yank-prefix documentation; exports a `keywords` table consumed by `pickers/keybindings.lua` for aliasing keymaps whose `desc` lacks searchable terms |
| `pickers/filter.lua` | Telescope picker for toggling file-type presets (`go_src`, `frontend`, `protos`) that scope `<leader>sf` (find files) and `<leader>sg` (live grep) |
| `pickers/keybindings.lua` | Telescope picker that walks which-key's tree to fuzzy-search all keymaps; merges in `builtins.lua` so built-in motions are searchable too |
| `builtins.lua` | Curated built-in normal-mode commands (motions, scroll, jumps) consumed by `pickers/keybindings.lua` since nvim has no API to enumerate built-ins |
| `autosave.lua` | auto-save.nvim: triggers on BufLeave/FocusLost (immediate) and InsertLeave/TextChanged (debounced 1s); excluded filetypes: oil, TelescopePrompt, mason, gitcommit, gitrebase, harpoon |
| `ai.lua` | sidekick.nvim setup: NES (Copilot LSP next-edit suggestions) + CLI integration (Claude, Copilot). Telescope as picker, right-split layout |
| `themes.lua` | Theme registry (all theme plugins, variants, setup functions, overrides), persistence to `stdpath('data')/theme.txt`, `apply()` and `all_variants()` |
| `pickers/theme.lua` | Custom Telescope picker for live theme preview with restore-on-cancel |
| `spell.lua` | Spell helpers: `add_word()` wraps `zg` to skip duplicates before appending to the personal dictionary |
| `utils.lua` | `gh()` URL builder, async nvim update check via Homebrew |
| `yank.lua` | Yank helpers: relative/absolute paths, Claude @-references, GitHub permalinks |
| `neovide.lua` | Neovide GUI-only config (gated by `vim.g.neovide`): animation tuning, `option_key_is_meta = 'both'` so `<M-...>` keymaps work, proxy icon, floating corner radius, hide-mouse-when-typing, plus `<D-c>`/`<D-v>`/`<D-s>` clipboard/save and `<D-=>`/`<D-->`/`<D-0>` zoom keymaps. Startup-time settings (fork, frame, title-hidden, font) live in `neovide.toml` instead, since Neovide reads them before nvim launches. |

### Plugin loading pattern

`plugins.lua` calls `vim.pack.add()` to register and download all plugins.
Each feature file then calls `vim.cmd.packadd('plugin-name')` to load its own
dependencies at the right time. Where order matters (e.g. `lsp.lua` does
`packadd` for mason -> mason-lspconfig -> lspconfig in dependency order),
the file handles sequencing itself.

Plugin versions are pinned in `nvim-pack-lock.json` (commit SHAs). Commit
this file after updating plugins to keep versions consistent across machines.

### Load order

From `init.lua`: configs -> plugins -> keymaps -> completion -> lsp ->
rust -> debugging -> testing -> ai -> format -> linting -> statusline ->
session -> git -> gitui -> terminal -> whichkey -> autosave -> filetree -> neovide.

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

- **Timers** use globals with stop-before-create: `if _G._checktime_timer then _G._checktime_timer:stop() end` before creating a new one. Prevents timer leaks on re-source.
- **Autocmds** use `nvim_create_augroup` with `clear = true`. The augroup is wiped before re-adding its autocmds, so re-source never duplicates handlers.

### Picker state with revert-on-cancel

`pickers/theme.lua` and `pickers/filter.lua` share a pattern: the picker mutates
session state live as the cursor moves (theme switches, preset toggles), but
`<Esc>` reverts to the snapshot taken at open time. The trick is overriding
`close_windows` on the picker so cancellation runs before windows tear down,
plus a `need_restore` flag flipped to false in the confirm action. New
pickers that need preview-style live state should follow the same shape.

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
guards against that separately, by skipping terminal/aerial/nvim-tree buffers
before jumping.

### Synthetic sidebar buffers can't be session-serialized

`mksession` serializes a window by the *file* its buffer points at. Aerial's
outline buffer has no backing file, so a saved session restores its window as a
bare `enew` scratch buffer — a junk blank split where the outline used to be.
`session.lua` closes aerial in persistence's `PersistenceSavePre` hook so the
synthetic window is simply absent from the saved layout; you reopen it with
`<leader>o` on demand. This mirrors the nvim-tree explorer (`<leader>e`), which
also isn't session-restored — you just toggle it back. Any future plugin owning
a synthetic sidebar buffer needs the same close-before-save treatment.

We deliberately **don't** remember aerial's open state and auto-reopen it. The
tempting way — a session-baked global (`let g:AerialWasOpen` via
`sessionoptions+=globals`) — has a broad side effect: `globals` isn't scoped to
one flag, it serializes *every* qualifying (capitalized-name, String/Number)
global into every session file and restores them on load, so any unrelated
plugin global gets its stale value resurrected on each restore. Not worth it for
a one-keystroke panel. (See `session.lua`'s posterity comment for the full
rationale, including why the flag would've had to be stored `0`/`1` rather than
a boolean.)


## LSP

### How LspAttach works

`vim.api.nvim_create_autocmd('LspAttach', ...)` fires once per (client,
buffer) pair. It early-returns if the client is nil (guard against detach
race). Optional features and keymaps are capability-gated (see above).
Universally supported keymaps (definition, rename, code action, references)
are always mapped.

### Keymaps

Buffer-local, set on `LspAttach` (from `lsp.lua`). Each *jump* map has a *peek*
counterpart under `<Space>p` that opens the **same target in a scrollable float**
(goto-preview) instead of moving the main window — VS Code / GoLand-style peek.
Peek is additive; jumps are unchanged.

| Jump | Peek | Target |
|---|---|---|
| `gd` | `<Space>pd` | Definition |
| `gy` | `<Space>pt` | Type definition |
| `gri` | `<Space>pi` | Implementation |
| `grr` | `<Space>pr` | References (opens a Telescope picker, then peeks) |
| `gD` | — | Declaration |
| — | `<Space>pq` | Close all open peek floats |

`gy`/`gri` (and their `pt`/`pi` peeks) and `gD` are capability-gated — they only
map when the server supports the method. `grr`/`gri` use Telescope pickers.

**Hover, actions & diagnostics:**

| Keymap | Action |
|---|---|
| `K` | Hover — docs/type/signature float (not the source; use peek for that) |
| `<C-s>` | Signature help |
| `<Space>th` | Toggle auto-hover on CursorHold |
| `<Space>ca` | Code action |
| `<Space>rn` | Rename symbol |
| `<Space>ce` | Show diagnostic float under cursor |
| `<Space>cd` | Diagnostic list (loclist) |
| `[d` / `]d` | Previous / next diagnostic (nvim default; supports a count) |
| `<Space>ti` | Toggle inlay hints |

### Adding a new LSP server

Example: adding `clangd` (C/C++).

1. **`lsp.lua` -- `ensure_installed`** -- add `'clangd'` so Mason auto-installs it.

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
  not mapped in this config. `grr`/`gri` are overridden to use Telescope.

- **Peek floats (`<leader>p*`)** — VS Code / GoLand-style peek via
  goto-preview; see the LSP *Keymaps* table for the jump/peek pairs. Tuned in
  `lsp.lua`: `focus_on_open = true` (cursor enters the float to scroll
  immediately) and `dismiss_on_move = false` (stays open while you look around)
  — flip either if the float feels too eager.

- **`<C-.>` terminal compatibility** — `<C-.>` (focus sidekick CLI)
  requires a terminal that sends CSI u sequences (kitty, iTerm2 with CSI u,
  WezTerm, Ghostty). macOS Terminal.app and some other terminals do not
  transmit `<C-.>` — use `<leader>ai` as a cross-terminal fallback.

- **Shift+Enter → newline in terminals** — inside `<C-\>` / `<leader>tt`
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
  the chat; `<leader>ad` when you're done with the conversation.

### Troubleshooting

**Server doesn't start:**
`:Mason` -- is it installed? `:checkhealth lsp` -- any errors?
`:set filetype?` -- correct filetype? Use `:set filetype=<type>` to force it manually (e.g. `:set filetype=yaml`). Some servers need a root marker (`go.mod`
for gopls, `Cargo.toml` for rust_analyzer) to detect the project root.

**Diagnostics not visible:**
virtual_text and signs are OFF by default. `<leader>td` toggles them on.

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


## Themes

Theme configuration lives in `themes.lua`. Each theme entry has a `src`
(GitHub repo), optional `variants` (colorscheme names the plugin provides),
and optional `setup`/`overrides` for per-theme customization.

- **Persistence:** The active theme is saved to `stdpath('data')/theme.txt`
  and restored on startup. Delete the file to reset to the default
  (`catppuccin`).
- **Live picker:** `<leader>st` opens a Telescope picker (`pickers/theme.lua`)
  with live preview. Scrolling applies themes in real-time; `<CR>` confirms
  and persists, `<Esc>` restores the original.
- **Background switching:** Some themes (gruvbox, solarized, oxocarbon,
  everforest, vscode) use `vim.opt.background` for light/dark instead of
  separate colorscheme names. These use virtual variant names (e.g.
  `gruvbox-light`) mapped to the real colorscheme name in `M.colorscheme`.
- **Adding a theme:** Add one entry to `M.themes` with at minimum `src`.
  Variants, setup, and overrides are optional. The theme's sources are
  automatically included in `vim.pack.add` via `M.sources`.


## Keymaps

Keymaps are split across files by feature:

- **`keymaps.lua`** -- global keymaps: Telescope search (`<leader>s*`),
  clipboard yank, split navigation (`<C-h/j/k/l>`), buffer navigation
  (`H`/`L` for prev/next, `<leader><leader>` for alternate, `<leader>m`
  for the buffer picker — `<M-1>`..`<M-9>` jumps to a row by number,
  `<leader>bd` / `<leader>qq` to close a buffer without collapsing its
  split via mini.bufremove), visual indent, toggle keymaps (`<leader>td`
  diagnostics, `<leader>ts` symbol scope), yank helpers (`yp`, `yc`,
  `yu`), `<leader>uo` / `:Typora`
  (open the current file in the Typora app — writes pending changes first;
  pairs with the `typora` shell alias), `jk` in insert mode to exit to
  normal mode. Custom pickers live in `pickers/`.
- **`lsp.lua`** (LspAttach) -- buffer-local LSP keymaps: go-to
  (`gd`, `gD`, `gy`), peek floats (`<leader>p*` — `pd`/`pt`/`pi`/`pr` for
  definition/type/impl/references, `pq` close-all; goto-preview), actions
  (`<leader>ca`, `<leader>rn`), diagnostics (`<leader>ce`, `<leader>cd`),
  Telescope references (`grr`, `gri`)
- **`format.lua`** -- global keymaps: `<leader>cf` (manual format via conform.nvim, not LSP-gated, works in all buffers), `<leader>tf` (toggle format-on-save)
- **`outline.lua`** -- aerial symbol outline: `<leader>o` (toggle the
  docked sidebar), `<leader>O` (toggle the nav popup with code preview),
  `<leader>sb` (Telescope fuzzy over symbols); buffer-local `]a`/`[a`
  (next/prev symbol) on attached buffers; sidebar-local `zh` (toggle
  highlight-on-hover of the source line)
- **`git.lua`** (gitsigns on_attach) -- buffer-local git keymaps: hunk
  navigation (`]c`/`[c`), staging/reset (`<leader>h*`), blame (`<leader>hb`)
- **`gitui.lua`** -- Neogit `<leader>g*` popups (status/commit/push/pull/log/
  diff/branch/rebase/worktree). See the Git (Neogit) section for details
- **`session.lua`** -- session keymaps (`<leader>q*`)
- **`rust.lua`** (FileType rust) -- buffer-local Rust keymaps: runnables
  (`<leader>cR`), expand macro (`<leader>cm`), open Cargo.toml (`<leader>cC`),
  debuggables (`<leader>dR`), grouped hover/actions (`K`, `<leader>ca`).
  See the Rust section for the full tables.
- **`debugging.lua`** -- global debug keymaps: `<leader>d*` (breakpoint,
  continue, step, REPL, UI, eval) plus `<F5>` / `<F9>`–`<F12>`
- **`testing.lua`** -- global neotest keymaps: `<leader>n*` (run
  nearest/file/last, debug nearest, summary, output)
- **`keymaps.lua`** (AI section) -- `<Tab>` (NES jump/apply), `<C-.>`
  (focus CLI, CSI u terminals), `<leader>ai` (focus CLI fallback),
  `<leader>aa` (toggle Claude CLI), `<leader>as`
  (select different CLI tool), `<leader>ad` (kill CLI session), `<leader>ap`
  (select prompt), `<leader>at` (send position/selection), `<leader>af`
  (send file). `<M-a>` in any Telescope picker sends selection(s) to CLI.

All keymaps have `desc` strings. To discover them:
- `<leader>?` shows all global mappings via which-key
- which-key popup appears after 300ms on `<leader>`, `g`, `[`, `]`
- `:map` / `:nmap <leader>` for the full list

Which-key uses an explicit trigger list (see `whichkey.lua`). If you add a
new single-char group in `wk.add()`, add its trigger too.

### Clipboard split

`y`/`Y` copy to the system clipboard, but `d`, `x`, `c`, and `dd` stay in
Neovim's default register. Visual-mode `p` pastes without clobbering the
clipboard either. This is non-standard -- most configs use
`clipboard=unnamedplus` (everything goes to system clipboard) or don't touch
it. The failure mode is silent: if you `dd` a line expecting it on your
system clipboard, you'll paste whatever was there before. Use `"+d`
explicitly when you need to cut-to-clipboard.

### Spell checking

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

### Window/tab title

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
- **Trash** — `D` in the tree sends files to macOS trash (`trash.cmd = 'trash'`,
  uses `/usr/bin/trash`). `d` remains permanent delete.
- **Polished prompts** — `select_prompts = true` routes rename/delete
  confirmations through `vim.ui.select` (telescope-ui-select).
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
| `a` | Create file or directory (append `/` for dir) |
| `d` | Delete (permanent) |
| `D` | Trash (sends to macOS trash) |
| `r` | Rename |
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
  as "where am I?" after jumping to a file via Telescope.
- `f` (live filter) narrows the tree to matching filenames — useful for
  large directories. `F` clears it. This is tree-scoped filtering, not
  project-wide search.
- `<leader>e` is not registered as a which-key group to avoid intercepting
  the keypress (which-key would wait for a second key). Both explorer
  keymaps are registered as plain descriptions so they appear in
  `<leader>sk`.


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
`<leader>x` aborts (`:cq`), and `gpg_watch`'s YubiKey-touch "Signed ✓" notice
fires the same as for `git commit` from the shell. If this ever fights the
flow, `commit_editor.kind` in `gitui.lua`'s `setup()` is the escape hatch.

### Diffs

`d` in the status buffer (or the diff popup) renders a side-by-side diff via
diffview.nvim (`integrations.diffview = true`). `:DiffviewOpen` also works
standalone, outside of Neogit — see the "Reviewing diffs (diffview.nvim)"
section below for the full set of review workflows.

### Which git tool to use

- **gitsigns** (`git.lua`) — gutter signs, per-hunk stage/reset/blame
  (`<leader>h*`, `]c`/`[c`). Always on, no buffer to open.
- **Telescope git-status picker** (`<leader>sm`) — quick jump to a changed
  file with a diff preview.
- **Neogit** (`<leader>gg`) — full staging/commit/branch/rebase/worktree
  operations from one dashboard.


## Reviewing diffs (diffview.nvim)

Setup lives alongside Neogit in `gitui.lua` (`packadd('diffview.nvim')`).
There is **no `require('diffview').setup()` call** — none is needed:
diffview lazily initializes its own defaults the first time any view opens,
and `plugin/diffview.lua` registers all commands and default keymaps
unconditionally on load. Everything below works with zero extra config.

Three review shapes map to three different invocations:

### 1. Uncommitted local changes

```vim
:DiffviewOpen
```

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

**Triple-dot, not double-dot.** `a...b` diffs against the merge-base — "what
did this branch add since it forked from main" — matching the `gdm` shell
alias's semantics (`git diff $(git_base_branch)...`). `a..b` is a plain
two-point diff with no merge-base resolution; wrong tool here unless main
hasn't moved. `origin/main` works directly as a remote-tracking ref;
diffview doesn't auto-fetch, so `git fetch` first if it might be stale.
There is no "Staged changes" section for a rev-range diff — it's read-only.

Append `--imply-local` to swap the `HEAD` side for your real local files
(live LSP) while still diffing against the merge-base on the other side.

Neogit shortcut: `<leader>gg` → `d` → `r` (range) → choose **2. Symmetric
Difference (a...b)** → supply `origin/main` and `HEAD` via the prompts.

### 3. Past N commits (less common)

Two different questions, two different commands:

- **"What changed, total?"** — `:DiffviewOpen HEAD~4..HEAD` (two-dot): one
  squashed diff across the range, browsed file-by-file like flows 1 & 2.
  Closest match to the `gd`/`gds` shell functions. Note `HEAD~4` alone (no
  `..`) diffs your *working tree* against that single rev, not a range.
- **"Walk me through each commit"** — `:DiffviewFileHistory --range=HEAD~4..HEAD`:
  a genuine git-log browser (commit list panel, `j`/`k` between commits,
  `<CR>` opens that commit's diff). No shell equivalent today.
- **One commit only** (≈ `gdn`) — `:DiffviewOpen <hash>^!` ("just this
  commit," like `git show`).

Neogit's `d` → `r` popup covers the squashed-range case too — choose
**1. Range (a..b)** instead of symmetric difference. `:DiffviewFileHistory`
has no Neogit popup binding; reach it from the command line, or via `L`
("open commit log") inside any file panel.

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

- **No default close keymap** — every flow above ends with
  `:DiffviewClose` or `:tabclose` typed out; nothing in `gitui.lua` binds
  this yet.
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


## AI (sidekick.nvim)

Setup lives in `ai.lua`. Uses `folke/sidekick.nvim` for two features:

1. **NES (Next Edit Suggestion)** — powered by Copilot LSP. After edits,
   diff overlays appear suggesting follow-on changes. `<Tab>` in normal mode
   jumps to or applies the next suggestion. Falls through to literal `<Tab>`
   when no suggestion is active.

2. **CLI integration** — opens Claude in a terminal split.
   `<leader>aa` toggles Claude (defaults to Claude, session stays alive
   when hidden). `<leader>as` switches to a different CLI tool.
   `<leader>ad` tears down the session entirely.

| Keymap | Action |
|---|---|
| `<Tab>` (insert) | Priority: blink menu selection → Copilot ghost text accept → literal Tab (matches VS Code/Zed) |
| `<Tab>` (normal) | NES: jump to or apply next edit suggestion |
| `<Space>tc` | Toggle all AI completions globally (inline ghost text + NES) |
| `<C-.>` | Focus CLI split (any mode; CSI u terminals only) |
| `<Space>ai` | Focus CLI split (cross-terminal fallback for `<C-.>`) |
| `<Space>aa` | Toggle Claude CLI (defaults to Claude, session stays alive when hidden) |
| `<Space>as` | Select a different CLI tool (copilot, gemini, etc.) |
| `<Space>ad` | Kill CLI session (tears down process + buffer) |
| `<Space>ap` | Select prompt |
| `<Space>at` | Send position (normal) or selection (visual) to CLI |
| `<Space>af` | Send file path to CLI |
| `<M-a>` (in picker) | Send picker selection(s) to CLI |

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

### Running a program

- **`<leader>cR`** — runnables picker; select the binary → runs `cargo run` in a
  terminal split. Workspace-aware (rust-analyzer picks the right `-p` package).
- **`grx`** on the `fn main` line — runs the `▶ Run` codelens directly.
- **`:RustLsp run`** — re-run the *last* runnable (fast edit-run loop).
- Or just a terminal: `<leader>tb`, then `cargo run -p <crate>`.

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
| `<Space>ca` | Code action (rustaceanvim grouped variant) |
| `<Space>cR` | Runnables — run a binary/target |
| `<Space>cm` | Expand macro under cursor |
| `<Space>cC` | Open the crate's `Cargo.toml` |
| `<Space>dR` | Debuggables — start a Rust debug session |
| `grx` | Run/Debug codelens under cursor (native codelens, now functional) |

**Debug** (global, `<Space>d*` = Debug group — from `debugging.lua`):

| Keymap | Action |
|---|---|
| `<Space>db` / `<F9>` | Toggle breakpoint |
| `<Space>dB` | Conditional breakpoint (prompts for condition) |
| `<Space>dc` / `<F5>` | Continue / start |
| `<Space>di` / `<F11>` | Step into |
| `<Space>do` / `<F10>` | Step over |
| `<Space>dO` / `<F12>` | Step out |
| `<Space>dl` | Run last |
| `<Space>dq` | Terminate |
| `<Space>dr` | Toggle REPL |
| `<Space>du` | Toggle dap-ui |
| `<Space>de` | Eval expression (normal: under cursor; visual: selection) |

**Test** (global, `<Space>n*` = Test group — from `testing.lua`):

| Keymap | Action |
|---|---|
| `<Space>nn` | Run nearest test |
| `<Space>nf` | Run all tests in file |
| `<Space>nl` | Run last |
| `<Space>nd` | Debug nearest test (via dap) |
| `<Space>nS` | Stop running test(s) |
| `<Space>ns` | Toggle summary tree |
| `<Space>no` | Show output for nearest |
| `<Space>nO` | Toggle output panel |

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
