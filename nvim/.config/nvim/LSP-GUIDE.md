# LSP Guide

> **This guide may be outdated.** Before relying on it, diff it against the
> actual source files (`lsp.lua`, `completion.lua`, `keymaps.lua`,
> `plugins.lua`) — the code is always the truth. Also check the official docs
> for anything version-sensitive:
> - `:help lsp` and `:help vim.lsp.config` (nvim built-in LSP)
> - `:help mason.nvim` / mason-lspconfig README
> - Individual server docs (e.g. gopls, rust-analyzer settings references)
> - blink.cmp README for completion/signature behavior
>
> Last verified against: nvim 0.12.2, mason-lspconfig 2.x, blink.cmp 1.x.

Neovim 0.12+ with native `vim.pack` (not lazy.nvim), Mason for server
installs, blink.cmp for completion, lspconfig v3 API (`vim.lsp.config` +
`vim.lsp.enable`).

**Prerequisites:**
- Nerd Font installed (statusline separators, completion icons)
- `stty -ixon` in your `.bashrc`/`.zshrc` (prevents `<C-s>` terminal freeze)


## Architecture

### File responsibilities

| File | LSP responsibility |
|---|---|
| `configs.lua` | `updatetime = 300` (drives CursorHold → document highlight), leader key |
| `plugins.lua` | `vim.pack.add` declarations (mason, lspconfig, blink.cmp), treesitter `ensure_installed` list (~line 91) |
| `completion.lua` | blink.cmp: sources, keymaps, ghost text, auto-brackets, signature hints |
| `lsp.lua` | Mason setup, mason-lspconfig, LspAttach autocmd, diagnostic config, per-server `vim.lsp.config`, `vim.lsp.enable` |
| `keymaps.lua` | `<leader>td` diagnostic toggle, `<leader>ss`/`<leader>sS` symbol search (Telescope, no fallback) |
| `statusline.lua` | `lsp_status` component (active server name in statusline), `diagnostics` summary |
| `git.lua` | satellite.nvim scrollbar with diagnostic marks |
| `whichkey.lua` | Group labels for `<leader>c` (Code), `<leader>r` (Refactor), `g` (Go to) |

### Plugin loading pattern

`plugins.lua` calls `vim.pack.add()` to register and download all plugins.
Each feature file then calls `vim.cmd.packadd('plugin-name')` to load its own
dependencies at the right time. `lsp.lua` does `packadd` for mason →
mason-lspconfig → lspconfig in dependency order.

### Load order

From `init.lua`: configs → plugins → keymaps → completion → lsp → statusline
→ session → git → whichkey → autosave.

### How LspAttach works

`vim.api.nvim_create_autocmd('LspAttach', ...)` fires once per (client,
buffer) pair. It early-returns if the client is nil (guard against detach
race). It sets up buffer-local keymaps, inlay hints, document highlight
(capability-gated on `textDocument/documentHighlight`), and codelens.
Server-agnostic — the same features apply to all servers with no per-server
keymap wiring.


## Feature Inventory

### Navigation (from `lsp.lua` LspAttach)

| Keymap | Mode | Action | Notes |
|---|---|---|---|
| `gd` | n | Go to definition | |
| `gD` | n | Go to declaration | Not all servers support this (gopls, pyright don't) |
| `gy` | n | Go to type definition | |
| `grr` | n | References | Telescope picker; falls back to `vim.lsp.buf.references` if Telescope unavailable |
| `gri` | n | Implementations | Telescope picker; falls back to `vim.lsp.buf.implementation` |

### Nvim 0.12 built-in defaults (not mapped in this config)

These exist in the nvim runtime `defaults.lua`. This config leaves them as-is
except for `grr`/`gri` which are overridden to use Telescope.

| Keymap | Mode | Action | Notes |
|---|---|---|---|
| `K` | n | Hover documentation | Only when LSP with hover support attaches |
| `[d` / `]d` | n | Previous/next diagnostic | Supports count: `3]d`. Also `[D`/`]D` for first/last |
| `grn` | n | Rename | Same as `<leader>rn` — both work |
| `gra` | n, v | Code action | Same as `<leader>ca` — both work |
| `grt` | n | Type definition | Same as `gy` — both work |
| `grx` | n | Run codelens | Only keybinding for this action |
| `gO` | n | Document symbols | |
| `<C-S>` | i, s | Signature help | Insert/select mode counterpart to our normal-mode `<C-s>` |

### Actions (from `lsp.lua` LspAttach)

| Keymap | Mode | Action | Notes |
|---|---|---|---|
| `<leader>rn` | n | Rename symbol | |
| `<leader>ca` | n, v | Code action | Visual mode: action on selection |
| `<leader>cf` | n, v | Format | Visual mode: format selection only |
| `<C-s>` | n | Signature help (manual) | Normal mode only. blink.cmp provides automatic signature hints in insert mode when you type a trigger character like `(` |

### Diagnostics

| Keymap | Mode | Action | Source |
|---|---|---|---|
| `<leader>e` | n | Jump to diagnostic + show float | `lsp.lua` — `jump = true` moves cursor to the diagnostic |
| `<leader>cd` | n | Diagnostic location list | `lsp.lua` |
| `<leader>td` | n | Toggle virtual_text + signs | `keymaps.lua` |

Defaults: virtual_text OFF, signs OFF, underline ON,
`update_in_insert = false` (no flicker while typing),
`severity_sort = true` (errors shown above warnings).
Float has rounded border and shows diagnostic source only when multiple LSP
clients produce diagnostics on the same line (`source = 'if_many'`).

### Search (from `keymaps.lua`, Telescope — no fallback)

| Keymap | Mode | Action |
|---|---|---|
| `<leader>ss` | n | Workspace symbols (dynamic) |
| `<leader>sS` | n | Document symbols |

### Inlay hints (from `lsp.lua` LspAttach)

Auto-enabled on attach for all buffers. `<leader>ti` toggles per-buffer.

The server must support `textDocument/inlayHint`. pyright does not. gopls has
all hint categories off by default — this config enables them all in
`vim.lsp.config('gopls')`.

### Document highlight (from `lsp.lua` LspAttach)

When the cursor pauses on a symbol (300ms idle, controlled by `updatetime` in
`configs.lua`), other occurrences in the buffer are highlighted.
Capability-gated: only activates if the server supports
`textDocument/documentHighlight`. Uses `LspReferenceText/Read/Write` highlight
groups (styled by colorscheme).

### Codelens (from `lsp.lua` LspAttach)

Auto-enabled via `vim.lsp.codelens.enable(true)`, which uses
`nvim_buf_attach` with `on_lines` to auto-refresh on buffer changes. `grx`
runs the codelens under cursor (nvim 0.12 default). Most useful in Go (run
test) and Rust (run test, implementations).

### Completion (from `completion.lua`, blink.cmp)

| Keymap | Mode | Action |
|---|---|---|
| `Tab` / `S-Tab` | i | Next/previous completion |
| `CR` | i | Accept |
| `C-e` | i | Cancel |
| `C-space` | i | Cycle: show menu → show docs → hide docs |
| `C-u` / `C-d` | i | Scroll documentation |

Sources in order: lsp, path, snippets, buffer. Ghost text shows the top
suggestion inline (blink.cmp built-in behavior). Auto-brackets after function
completions. Automatic signature hints when you type a trigger character like
`(` (via blink.cmp's `show_on_trigger_character` default).

blink.cmp downloads a Rust fuzzy matcher binary on first launch
(`fuzzy.implementation = 'prefer_rust'`). Falls back to Lua silently if the
download hasn't completed yet.

### Statusline

`lsp_status` in lualine section x shows the active LSP server name. Quick way
to verify LSP is attached and which server is running.


## Adding a New LSP Server

Example: adding `clangd` (C/C++).

### Checklist

1. **`lsp.lua` ~line 20** — add `'clangd'` to mason-lspconfig `ensure_installed`:
   ```lua
   ensure_installed = {
     'lua_ls',
     'pyright',
     'ts_ls',
     'gopls',
     'rust_analyzer',
     'elixirls',
     'clangd',        -- add here
   },
   ```

2. **`lsp.lua` ~line 152** — add `'clangd'` to `vim.lsp.enable()`:
   ```lua
   vim.lsp.enable({ 'lua_ls', 'pyright', 'ts_ls', 'gopls', 'rust_analyzer', 'elixirls', 'clangd' })
   ```

3. **`lsp.lua`** — (optional) add a `vim.lsp.config` block if non-default
   settings are needed. Place it between the existing config blocks and the
   `vim.lsp.enable()` call:
   ```lua
   vim.lsp.config('clangd', {
     settings = { ... },
   })
   ```

4. **`plugins.lua` ~line 91** — add treesitter parser:
   ```lua
   local ensure_installed = {
     'lua', 'python', 'javascript', 'typescript', 'go',
     'rust', 'elixir', 'markdown', 'json', 'yaml', 'ini', 'graphql',
     'c', 'cpp',      -- add here
   }
   ```

5. **Verify** — restart nvim → `:Mason` (confirm installed) → open a `.c`
   file → check statusline for `clangd` → `:checkhealth lsp`

### Notes

- **Server name** must be the lspconfig name (e.g. `lua_ls` not
  `lua-language-server`). These sometimes differ from the Mason package name.
- **LspAttach fires automatically** — all keymaps, inlay hints, document
  highlight, and codelens apply to the new server with zero extra config.
- The **`settings` key structure** varies per server: gopls uses
  `settings.gopls`, rust-analyzer uses `settings['rust-analyzer']`, lua_ls
  uses `settings.Lua`. Check the server's documentation.

### Per-server configuration reference

Currently customized:

- **lua_ls** — LuaJIT runtime, workspace includes nvim runtime files, `vim`
  global recognized, telemetry off.
- **gopls** — `unusedparams` + `shadow` analyses, `staticcheck`,
  workspace-scoped symbols, ALL inlay hint categories enabled (gopls has them
  off by default).
- **rust_analyzer** — `checkOnSave` runs clippy instead of plain cargo check.

Using defaults (no `vim.lsp.config` block): **pyright**, **ts_ls**,
**elixirls**.

### Removing a server

Reverse the checklist: remove from `vim.lsp.enable()`, remove from
`ensure_installed`, delete any `vim.lsp.config()` block, optionally remove the
treesitter parser and run `:MasonUninstall server_name`, restart nvim.


## Troubleshooting

**Server doesn't start:**
`:Mason` — is it installed? `:checkhealth lsp` — any errors?
`:set filetype?` — correct filetype? Some servers need a root marker (`go.mod`
for gopls, `Cargo.toml` for rust_analyzer, etc.) to detect the project root.
If you open a file outside a project, the server may not attach.

**Inlay hints missing:**
Server must support `textDocument/inlayHint` — pyright doesn't. Some servers
need explicit opt-in in settings (gopls has all hints off by default; this
config enables them). Check `<leader>ti` hasn't toggled them off.

**`<C-s>` freezes terminal:**
Terminal XOFF flow control. Add `stty -ixon` to your `.bashrc`/`.zshrc`.

**Document highlight not working:**
Server must support `textDocument/documentHighlight`. Check `updatetime` is
low (300ms in `configs.lua`). Check highlight groups: `:hi LspReferenceText`.

**Diagnostics not visible:**
virtual_text and signs are OFF by default. `<leader>td` toggles them on.
Underline is always on — look for squiggly lines under errors. `<leader>e`
shows the diagnostic in a float and jumps to it.

**Completion not working:**
Check statusline for the LSP server name (is it attached?). Large projects
may take seconds for the server to initialize. Ghost text should appear as you
type if blink.cmp is loaded.

**Codelens not appearing:**
Not all servers provide codelens. Check:
`:lua print(vim.inspect(vim.lsp.codelens.get(0)))`.

**Log inspection:**
`:lua vim.cmd.edit(vim.lsp.get_log_path())` to open the LSP log. For verbose
output, temporarily add `vim.lsp.set_log_level('debug')` to `lsp.lua`.


## Auto-save Interaction

Format-on-save is NOT configured — `<leader>cf` is manual only. Auto-save
won't trigger reformatting.

`update_in_insert = false` means diagnostics don't refresh while typing. They
update when you leave insert mode or after auto-save fires (~1s debounce).


## Useful Commands

| Command | Purpose |
|---|---|
| `:Mason` | Server installer UI (rounded borders, ✓/➜/✗ icons) |
| `:checkhealth lsp` | Verify server attachment and config |
| `:lua vim.print(vim.lsp.get_clients())` | List active LSP clients |
| `:lua vim.print(vim.lsp.get_clients()[1].server_capabilities)` | Inspect server capabilities |
| `:Inspect` | Show highlight group under cursor |
| `:lua vim.cmd.edit(vim.lsp.get_log_path())` | Open LSP log file |
