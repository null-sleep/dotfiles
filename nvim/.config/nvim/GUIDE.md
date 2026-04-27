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
| `bufferpicker.lua` | Custom Telescope buffer picker (`<leader>m`): row-index column replaces telescope's bufnr column, `<M-1>`..`<M-9>` jumps to that row |
| `completion.lua` | blink.cmp: keymap preset, sources, ghost text, auto-brackets, signature hints, fuzzy backend |
| `lsp.lua` | Mason setup, mason-lspconfig, LspAttach autocmd (buffer-local keymaps + capability-gated features), diagnostic config, per-server `vim.lsp.config`, `vim.lsp.enable` |
| `format.lua` | conform.nvim: per-filetype formatter chains, format-on-save toggle (`<leader>tf`), manual format (`<leader>cf`) |
| `statusline.lua` | lualine: sections (mode, path, branch, diff, diagnostics, lsp_status, location), powerline separators, global statusline |
| `session.lua` | persistence.nvim: branch-aware session save/restore, `<leader>q*` keymaps |
| `git.lua` | gitsigns: hunk signs, hunk navigation (`]c`/`[c`), staging/reset/blame keymaps (`<leader>h*`); satellite.nvim scrollbar with git/diagnostic/search marks |
| `whichkey.lua` | which-key: group labels, explicit trigger list, yank-prefix documentation; exports a `keywords` table consumed by `keypicker.lua` for aliasing keymaps whose `desc` lacks searchable terms |
| `filterpicker.lua` | Telescope picker for toggling file-type presets (`go_src`, `frontend`, `protos`) that scope `<leader>sf` (find files) and `<leader>sg` (live grep) |
| `keypicker.lua` | Telescope picker that walks which-key's tree to fuzzy-search all keymaps; merges in `builtins.lua` so built-in motions are searchable too |
| `builtins.lua` | Curated built-in normal-mode commands (motions, scroll, jumps) consumed by `keypicker.lua` since nvim has no API to enumerate built-ins |
| `autosave.lua` | auto-save.nvim: triggers on BufLeave/FocusLost (immediate) and InsertLeave/TextChanged (debounced 1s), filetype exclusions |
| `themes.lua` | Theme registry (all theme plugins, variants, setup functions, overrides), persistence to `stdpath('data')/theme.txt`, `apply()` and `all_variants()` |
| `themepicker.lua` | Custom Telescope picker for live theme preview with restore-on-cancel |
| `utils.lua` | `gh()` URL builder, async nvim update check via Homebrew |
| `yank.lua` | Yank helpers: relative/absolute paths, Claude @-references, GitHub permalinks |

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
format -> statusline -> session -> git -> whichkey -> autosave.


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

`themepicker.lua` and `filterpicker.lua` share a pattern: the picker mutates
session state live as the cursor moves (theme switches, preset toggles), but
`<Esc>` reverts to the snapshot taken at open time. The trick is overriding
`close_windows` on the picker so cancellation runs before windows tear down,
plus a `need_restore` flag flipped to false in the confirm action. New
pickers that need preview-style live state should follow the same shape.

### Why `builtins.lua` exists

`keypicker.lua` walks which-key's internal tree to enumerate keymaps. That
covers user mappings and which-key's own preset groups (operators, motions,
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


## LSP

### How LspAttach works

`vim.api.nvim_create_autocmd('LspAttach', ...)` fires once per (client,
buffer) pair. It early-returns if the client is nil (guard against detach
race). Optional features and keymaps are capability-gated (see above).
Universally supported keymaps (definition, rename, code action, references)
are always mapped.

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

- **Format-on-save** is ON by default for configured filetypes (Lua, Python, Go, Rust, JS/TS/JSON/YAML) via conform.nvim. `<leader>tf` toggles format-on-save globally; `vim.g.disable_autoformat` (global) and `vim.b.disable_autoformat` (per-buffer) are the underlying flags. Run `:ConformInfo` to see which formatter binaries are detected on `$PATH`.

- **Nvim 0.12 built-in keymaps** -- `K` (hover), `[d`/`]d` (diagnostic jump),
  `grn` (rename), `gra` (code action), `grx` (codelens) are nvim defaults,
  not mapped in this config. `grr`/`gri` are overridden to use Telescope.

### Troubleshooting

**Server doesn't start:**
`:Mason` -- is it installed? `:checkhealth lsp` -- any errors?
`:set filetype?` -- correct filetype? Some servers need a root marker (`go.mod`
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


## Themes

Theme configuration lives in `themes.lua`. Each theme entry has a `src`
(GitHub repo), optional `variants` (colorscheme names the plugin provides),
and optional `setup`/`overrides` for per-theme customization.

- **Persistence:** The active theme is saved to `stdpath('data')/theme.txt`
  and restored on startup. Delete the file to reset to the default
  (`catppuccin`).
- **Live picker:** `<leader>st` opens a Telescope picker (`themepicker.lua`)
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
  for the buffer picker — `<M-1>`..`<M-9>` jumps to a row by number),
  visual indent, diagnostic toggle (`<leader>td`), yank helpers
  (`yp`, `yc`, `yu`)
- **`lsp.lua`** (LspAttach) -- buffer-local LSP keymaps: go-to
  (`gd`, `gD`, `gy`), actions (`<leader>ca`, `<leader>rn`),
  diagnostics (`<leader>e`, `<leader>cd`), Telescope references (`grr`, `gri`)
- **`format.lua`** -- global keymaps: `<leader>cf` (manual format via conform.nvim, not LSP-gated, works in all buffers), `<leader>tf` (toggle format-on-save)
- **`git.lua`** (gitsigns on_attach) -- buffer-local git keymaps: hunk
  navigation (`]c`/`[c`), staging/reset (`<leader>h*`), blame (`<leader>hb`)
- **`session.lua`** -- session keymaps (`<leader>q*`)

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
