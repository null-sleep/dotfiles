# LSP Guide

> **This guide may be outdated.** The code is always the truth — read the
> source files listed below before relying on anything here. Also check
> official docs for anything version-sensitive:
> - `:help lsp` and `:help vim.lsp.config` (nvim built-in LSP)
> - `:help mason.nvim` / mason-lspconfig README
> - Individual server docs (e.g. gopls, rust-analyzer settings references)
> - blink.cmp README for completion/signature behavior

Neovim 0.12+ with native `vim.pack` (not lazy.nvim), Mason for server
installs, blink.cmp for completion, lspconfig v3 API (`vim.lsp.config` +
`vim.lsp.enable`).


## Architecture

### File responsibilities

| File | LSP responsibility |
|---|---|
| `configs.lua` | `updatetime = 300` (drives CursorHold → document highlight), leader key |
| `plugins.lua` | `vim.pack.add` declarations (mason, lspconfig, blink.cmp), treesitter `ensure_installed` list |
| `completion.lua` | blink.cmp: sources, keymaps, ghost text, auto-brackets, signature hints |
| `lsp.lua` | Mason setup, mason-lspconfig, LspAttach autocmd, diagnostic config, per-server `vim.lsp.config`, `vim.lsp.enable` |
| `keymaps.lua` | `<leader>td` diagnostic toggle, `<leader>ss`/`<leader>sS` symbol search (Telescope) |
| `statusline.lua` | `lsp_status` component (active server name), `diagnostics` summary |
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
(capability-gated), and codelens. Server-agnostic — the same features apply
to all servers with zero per-server keymap wiring.


## Adding a New LSP Server

Example: adding `clangd` (C/C++).

1. **`lsp.lua` — `ensure_installed`** — add `'clangd'` so Mason auto-installs it.

2. **`lsp.lua` — `vim.lsp.enable()`** — add `'clangd'` to the list.
   This is the single source of truth for active servers (`automatic_enable`
   is set to `false` in mason-lspconfig).

3. **`lsp.lua` — `vim.lsp.config`** — (optional) add a config block if
   non-default settings are needed. Place it before the `vim.lsp.enable()` call.

4. **`plugins.lua` — treesitter `ensure_installed`** — add the parser(s)
   (e.g. `'c', 'cpp'`).

5. **Verify** — restart nvim → `:Mason` (confirm installed) → open a file →
   check statusline for server name → `:checkhealth lsp`.

### Removing a server

Reverse the steps: remove from `vim.lsp.enable()`, remove from
`ensure_installed`, delete any `vim.lsp.config()` block, optionally remove
the treesitter parser and run `:MasonUninstall server_name`, restart nvim.

### Notes

- **Server name** must be the lspconfig name (e.g. `lua_ls` not
  `lua-language-server`). These sometimes differ from the Mason package name.
- **LspAttach fires automatically** — all keymaps, inlay hints, document
  highlight, and codelens apply to the new server with zero extra config.
- The **`settings` key structure** varies per server: gopls uses
  `settings.gopls`, rust-analyzer uses `settings['rust-analyzer']`, lua_ls
  uses `settings.Lua`. Check the server's documentation.


## Things to Watch Out For

- **`automatic_enable = false`** — mason-lspconfig does NOT auto-enable
  installed servers. The explicit `vim.lsp.enable()` list in `lsp.lua` is
  authoritative. If you add a server to `ensure_installed` but forget
  `vim.lsp.enable()`, it will be installed but won't attach.

- **`<C-s>` terminal freeze** — terminal XOFF flow control captures this
  keystroke. `stty -ixon` in `.bashrc`/`.zshrc` fixes it.

- **Inlay hints** — auto-enabled on attach for all buffers. pyright doesn't
  support them. gopls has all hint categories off by default — this config
  enables them all explicitly. `<leader>ti` toggles per-buffer.

- **Diagnostics default to minimal** — virtual_text and signs are OFF.
  `<leader>td` toggles them on. Underline is always on.

- **Document highlight** — capability-gated on `textDocument/documentHighlight`.
  Driven by `updatetime` (300ms) in `configs.lua`.

- **Codelens** — auto-enabled via `vim.lsp.codelens.enable(true)`. `grx`
  (nvim 0.12 default) runs the codelens under cursor. Not all servers
  provide codelens.

- **Format-on-save is NOT configured** — `<leader>cf` is manual only.

- **Nerd Font required** — statusline separators and completion icons need one.

- **Nvim 0.12 built-in keymaps** — `K` (hover), `[d`/`]d` (diagnostic jump),
  `grn` (rename), `gra` (code action), `grx` (codelens) are nvim defaults,
  not mapped in this config. `grr`/`gri` are overridden to use Telescope.


## Troubleshooting

**Server doesn't start:**
`:Mason` — is it installed? `:checkhealth lsp` — any errors?
`:set filetype?` — correct filetype? Some servers need a root marker (`go.mod`
for gopls, `Cargo.toml` for rust_analyzer) to detect the project root.

**Diagnostics not visible:**
virtual_text and signs are OFF by default. `<leader>td` toggles them on.

**Completion not working:**
Check statusline for the LSP server name (is it attached?). Large projects
may take seconds for the server to initialize.

**Log inspection:**
`:lua vim.cmd.edit(vim.lsp.get_log_path())` to open the LSP log. For verbose
output, temporarily add `vim.lsp.set_log_level('debug')` to `lsp.lua`.

**Useful commands:**

| Command | Purpose |
|---|---|
| `:Mason` | Server installer UI |
| `:checkhealth lsp` | Verify server attachment and config |
| `:lua vim.print(vim.lsp.get_clients())` | List active LSP clients |
| `:lua vim.print(vim.lsp.get_clients()[1].server_capabilities)` | Inspect capabilities |
| `:lua vim.cmd.edit(vim.lsp.get_log_path())` | Open LSP log file |
