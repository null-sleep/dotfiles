# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

```bash
brew install stow
cd ~/src/dotfiles
# Install dependencies for each tool
stow nvim
stow zsh
```

Stow reads `.stowrc` in this repo which sets `--target` to `~`, so you don't need to pass `-t ~` manually.

To add a new config (e.g. tmux), mirror the home-relative path:

```
dotfiles/tmux/.config/tmux/tmux.conf
```

Then run `stow tmux`.

## Neo Vim

Neo Vim >= 12.0

```bash
brew install nvim rg fzf fd font-hack-nerd-font tree-sitter-cli curl git
```

On first launch nvim will:
1. Download all plugins via `vim.pack` (native package manager)
2. Compile `telescope-fzf-native` via `make`
3. Install treesitter parsers for configured languages
4. Download the `blink.cmp` fuzzy binary (pre-built, requires `curl`)
5. Install LSP servers via mason (requires internet)

### Treesitter

Treesitter is configured using nvim 0.12's native API — no plugin config table needed.
The `nvim-treesitter` plugin is registered via `vim.pack` (nvim's built-in package manager)
and is used solely for parser management (installing/updating parsers).

Highlighting and folding are handled natively:
- **Highlighting**: `vim.treesitter.start()` is attached per buffer via a `FileType` autocmd
- **Folding**: AST-based folding via `vim.treesitter.foldexpr()` (files open fully expanded)
- **Large files**: treesitter is skipped for buffers >50k lines or >1.5MB to prevent UI lag
- **Auto-install on startup**: missing parsers from `ensure_installed` are installed automatically on startup
- **Auto-install on open**: if a file is opened and its parser isn't installed, `TSInstall` is triggered automatically
- **Auto-recompile on update**: a `PackChanged` autocmd detects when `nvim-treesitter` is updated and re-runs `TSUpdate` to recompile parsers

Parsers are locked in `nvim-pack-lock.json` — commit this file to pin versions across machines.

**Commands:**

| Command | Description |
|---|---|
| `:TSUpdate` | Update all installed parsers |
| `:TSUpdate <lang>` | Update a specific parser |
| `:TSInstall <lang>` | Install a parser manually |
| `:InspectTree` | View the parsed AST for the current buffer |
| `:Inspect` | Show highlight groups under the cursor |
| `:checkhealth nvim-treesitter` | Verify installed parsers and requirements |

### Telescope

Fuzzy finder for files, text search, buffers, and help. Uses `telescope-fzf-native` (compiled C extension) for faster sorting. Leader key is `<Space>`.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<Space>sf` | Find files by name |
| `<Space>sg` | Live grep (search file contents) |
| `<Space>sb` | Switch between open buffers |
| `<Space>sh` | Search help tags |
| `<Space>sr` | Resume last search |

**Inside the telescope window:**

| Key | Action |
|---|---|
| Type anything | Fuzzy filter results |
| `<C-n>` / `<C-p>` | Move down / up |
| `<CR>` | Open in current window |
| `<C-v>` | Open in vertical split |
| `<C-x>` | Open in horizontal split |
| `<C-t>` | Open in new tab |
| `<Esc>` | Close |

**Tips:**
- In `<Space>sg` (live grep), type a space after your search term to filter by filename, e.g. `vim.pack plugins` searches for `vim.pack` only in files matching `plugins`
- `<Space>sr` reopens the last search with the same query — useful when you close telescope and want to get back

**Commands:**

| Command | Description |
|---|---|
| `:checkhealth telescope` | Verify telescope and fzf-native are working |

### LSP (Language Server Protocol)

IDE features powered by nvim's built-in LSP client. Three plugins work together:
- **mason.nvim** — installs and manages language servers (`:Mason` to open UI)
- **mason-lspconfig.nvim** — bridges mason and lspconfig, auto-installs servers on startup
- **nvim-lspconfig** — pre-configured setups for each language server

Configured servers: `lua_ls`, `pyright`, `ts_ls`, `gopls`, `rust_analyzer`

To add a new server: add it to `ensure_installed` in `lua/lsp.lua` and add a `vim.lsp.config()` call.

**Mason commands:**

| Command | Description |
|---|---|
| `:Mason` | Open mason UI to install/update/remove servers |
| `:MasonInstall <server>` | Install a specific server |
| `:MasonUninstall <server>` | Remove a server |
| `:MasonUpdate` | Update all installed servers |

**LSP keymaps** (active only in buffers with an attached server):

| Keymap | Action |
|---|---|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gi` | Go to implementation |
| `gy` | Go to type definition |
| `gr` | References (opens in telescope) |
| `K` | Hover docs |
| `<C-k>` | Signature help |
| `<Space>rn` | Rename symbol |
| `<Space>ca` | Code actions |
| `<Space>e` | Show diagnostic float |
| `[d` / `]d` | Jump to previous / next diagnostic |
| `<Space>q` | Send diagnostics to location list |

**Diagnostic commands:**

| Command | Description |
|---|---|
| `:checkhealth lsp` | Verify LSP health and active clients |
| `:lua print(vim.inspect(vim.lsp.get_clients()))` | Show all active LSP clients |

### Autocompletion (blink.cmp)

Completion engine written in Rust — faster than nvim-cmp with better fuzzy matching.
Installed via `vim.pack` pinned to the latest `v1.x.x` release tag.

On first launch, blink.cmp automatically downloads a pre-built Rust binary for fuzzy matching
(requires `curl` and `git`). You'll see a notification while it downloads. No manual steps needed.

**Sources:** LSP, file paths, snippets, buffer words

**Keymaps (inside completion menu):**

| Key | Action |
|---|---|
| `<Tab>` | Next item (falls back to normal Tab when menu is closed) |
| `<S-Tab>` | Previous item |
| `<CR>` | Accept selected item (falls back to normal Enter) |
| `<C-u>` / `<C-d>` | Scroll documentation popup up / down |
| `<C-space>` | Manually trigger completion |
| `<C-e>` | Cancel / close completion menu |

**Signature help** is enabled automatically — shows function parameter hints when typing inside `()`.

**If the binary fails to download** (no internet, corporate proxy, etc.), blink.cmp silently falls
back to a pure Lua implementation with no action required. To force a re-download:
```
:lua require('blink.cmp.fuzzy.download').ensure_downloaded(function() end)
```

**Commands:**

| Command | Description |
|---|---|
| `:checkhealth blink.cmp` | Verify blink.cmp and fuzzy binary status |

## ZSH

TODO: Add ZSH install steps

Add `source ~/.zshrc_config.zsh` in you `zshrc`

Note: Secrets are stored in `~/.zshenv` which is not managed by stow.

## Stow

To exclude files or folders from being symlinked, create a `.stow-local-ignore` file in the package directory (e.g. `nvim/.stow-local-ignore`):

```
node_modules
*.zwc
```

Patterns are Perl-style regex, one per line. Note: adding this file overrides stow's default ignore list (which skips `.git`, `README.*`, etc.), so include those if needed. See `man stow` under "IGNORE LISTS" for the full defaults.

If stow already created symlinks before you added the ignore (e.g. `node_modules` was already symlinked), restow the package to pick up the change:

```bash
cd ~/src/dotfiles
stow -R nvim
```

`-R` (restow) unstows and re-stows, recreating symlinks while respecting the updated `.stow-local-ignore`.
