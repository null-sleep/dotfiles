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

## Fonts

```bash
# Hack Nerd Font (used by nvim for icons and glyphs)
brew install font-hack-nerd-font

# SF Mono Square (SF Mono patched with Nerd Font glyphs and square CJK characters)
brew tap delphinus/sfmono-square
brew install sfmono-square
```

## Neo Vim

Requires Neovim >= 0.12 (uses `vim.pack`, `vim.lsp.config`, native treesitter API).

```bash
brew install nvim rg fzf fd tree-sitter-cli curl git
```

Compile tools: `telescope-fzf-native` needs `make` (ships with Xcode Command Line Tools — run `xcode-select --install` if missing).

Then stow and launch:

```bash
cd ~/src/dotfiles
stow nvim
nvim
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
| `<Space>s/` | Fuzzy search inside current buffer |
| `<Space>so` | Recent files |

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
- Both file search and live grep include hidden files/directories (e.g. `.github/`). The `.git/` directory and `node_modules/` are excluded via `file_ignore_patterns`.
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

**Diagnostic toggles:**

Diagnostic virtual text and gutter signs are **off by default** — underlines remain active
so diagnostics are still visible on hover (`K` or `<Space>e`).

| Keymap | Action |
|---|---|
| `<Space>td` | Toggle diagnostic virtual text and gutter signs on/off |

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

### Git Signs and Scrollbar (gitsigns.nvim + satellite.nvim)

**gitsigns.nvim** shows changed, added, and deleted lines in the gutter next to line numbers:

| Sign | Meaning |
|---|---|
| `┃` | Added line |
| `┃` | Changed line |
| `_` / `‾` | Deleted line (below / above) |
| `~` | Changed and deleted |
| `┆` | Untracked file |

**satellite.nvim** adds a scrollbar on the right edge of the focused window with colour-coded marks showing where things are across the whole file:

- Git changes (add/change/delete) — matches gitsigns colours
- LSP diagnostics (error/warn/info/hint)
- Search results
- Quickfix list items

Useful for navigating large files — you can see at a glance where modified code, errors, and search matches are without scrolling.

**Commands:**

| Command | Description |
|---|---|
| `:SatelliteRefresh` | Force refresh scrollbar if out of sync |
| `:SatelliteDisable` / `:SatelliteEnable` | Toggle scrollbar |

### Session Management (persistence.nvim)

Automatically saves and restores open buffers per directory. Sessions are saved on quit and
can be restored on next launch. With `branch = true`, each git branch gets its own session —
switching branches won't mix up your open files.

**Sessions are saved automatically on quit.** To restore, use the keymaps below after opening
nvim in the same directory.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<Space>qs` | Restore session for the current directory |
| `<Space>qS` | Pick from all saved sessions |
| `<Space>ql` | Restore the last session (regardless of directory) |
| `<Space>qd` | Stop saving — quit without persisting current state |


### General Keymaps

| Keymap | Action |
|---|---|
| `:Q` / `<Space>qq` | Quit all |
| `y` / `Y` | Yank to system clipboard (dd, x, c stay in Neovim register) |
| `p` (visual) | Paste without clobbering register |
| `<` / `>` (visual) | Indent/dedent and stay in visual mode |
| `Ctrl+h/j/k/l` | Navigate between splits |
| `<Space>yp` | Yank relative file path |
| `<Space>yP` | Yank absolute file path |

### Keymap Discovery (which-key.nvim)

Press `<Space>` and wait — a popup appears showing all available keymaps for that prefix,
grouped by category. Helps discover keymaps without needing to remember them all.

| Prefix | Group |
|---|---|
| `<Space>s` | Search |
| `<Space>q` | Session |
| `<Space>t` | Toggle |
| `<Space>h` | Git hunk |
| `<Space>y` | Yank |
| `<Space>r` | Refactor |
| `<Space>c` | Code |
| `g` | Go to |
| `[` / `]` | Previous / Next |

Dismiss the popup with `<Esc>`. The popup appears after 300ms by default.

### Statusline (lualine.nvim)

Statusline that automatically matches the active colorscheme. Shows mode, filename, git branch,
diff counts, diagnostics, LSP status, search count, progress, and cursor position.

**Layout:**

```
| mode | filename | branch diff diagnostics | ... | lsp_status | searchcount progress | line:col |
```

- **LSP status** — only visible when a language server is attached to the current buffer
- **Search count** — only visible while a `/` search is active
- Theme updates automatically when you change `M.active` in `lua/themes.lua`

### Themes

All themes are configured in `lua/themes.lua`. To switch themes, change `M.active`:

```lua
M.active = 'catppuccin'        -- default dark
M.active = 'catppuccin-latte'  -- light variant
M.active = 'tokyonight-day'    -- light variant
M.active = 'rose-pine-dawn'    -- light variant
```

See `M.variants` in `lua/themes.lua` for all available colorscheme names with descriptions.

To customise a theme, edit its `setup` function or `overrides` table in `lua/themes.lua`.

**Tip:** position the cursor on any UI element and run `:Inspect` to find its highlight group name for overrides.

**Installed themes:** catppuccin, tokyonight, gruvbox, rose-pine, kanagawa, dracula, solarized,
github-nvim-theme, zenbones, oxocarbon, modus-themes, midnight, onedark, vscode, everforest, nordic.

### Navigation

**Scrolling:**

| Key | Action |
|---|---|
| `Ctrl+d` | Scroll down half page |
| `Ctrl+u` | Scroll up half page |
| `Ctrl+f` | Scroll down full page |
| `Ctrl+b` | Scroll up full page |

**Jumping:**

| Key | Action |
|---|---|
| `gg` | Top of file |
| `G` | Bottom of file |
| `{number}G` | Jump to line number |
| `%` | Jump to matching bracket |
| `{` / `}` | Previous / next blank line |

**Viewport (move screen, cursor stays):**

| Key | Action |
|---|---|
| `zz` | Center current line on screen |
| `zt` | Current line to top |
| `zb` | Current line to bottom |

**Search:**

| Key | Action |
|---|---|
| `/term` | Search forward |
| `n` / `N` | Next / previous match |
| `*` / `#` | Next / previous occurrence of word under cursor |

**Common remaps:**

| Remap | What it does | Why |
|---|---|---|
| `jk` → `<Esc>` | Exit insert mode without reaching for Escape | Faster than `<Esc>`, keeps hands on home row |
| `<C-h/j/k/l>` → split nav | Navigate between splits | Default `<C-w>h` is two keystrokes |
| `H` / `L` → prev/next buffer | Cycle open buffers | Default H/L (screen top/bottom) are rarely used |
| `<` / `>` in visual → stay in visual | Indent without losing selection | Default drops you back to normal mode |
| `J` in visual → move lines down | Move selected lines down | More intuitive than `:m '>+1` |
| `K` in visual → move lines up | Move selected lines up | More intuitive than `:m '<-2` |
| `n` → `nzzzv` | Center screen after search jump | Keeps match in the middle of the viewport |
| `p` in visual → paste without yanking | Paste over selection, keep register | Default replaces your clipboard with deleted text |

These are not configured yet — listed here for reference when customising `keymaps.lua`.

## iTerm2

### Setup

Color themes (Dracula, Nord) and an exported settings snapshot are stored in `iterm2/`.

To sync settings automatically across machines:

1. **iTerm2 → Settings → General → Preferences**
2. Check **"Load preferences from a custom folder or URL"**
3. Set path to `~/src/dotfiles/iterm2`
4. Check **"Save changes to folder when iTerm2 quits"**

This writes a `com.googlecode.iterm2.plist` to the folder. On a new machine, clone the repo and point iTerm2 to the same path — all profiles, keybindings, and appearance settings will load automatically.

To import color themes manually: **iTerm2 → Settings → Profiles → Colors → Color Presets → Import** and select the `.itermcolors` files.

### Panes

**Splitting:**

| Shortcut | Action |
|---|---|
| `Cmd+D` | Split vertically (side by side) |
| `Cmd+Shift+D` | Split horizontally (top/bottom) |

**Switching panes:**

| Shortcut | Action |
|---|---|
| `Cmd+[` / `Cmd+]` | Cycle through panes |
| `Cmd+Option+Arrow` | Move to pane in that direction |

**Tabs:**

| Shortcut | Action |
|---|---|
| `Cmd+T` | New tab |
| `Cmd+W` | Close current pane/tab |
| `Cmd+1-9` | Jump to tab by number |
| `Cmd+Left/Right` | Previous/next tab |

**Resizing panes:**

| Shortcut | Action |
|---|---|
| `Cmd+Ctrl+Arrow` | Resize pane in that direction |

## ZSH

```bash
# Dependencies
brew install fzf ripgrep direnv go

# Install Antigen (zsh plugin manager)
mkdir -p ~/.antigen
curl -L git.io/antigen > ~/.antigen/antigen.zsh

# Install zsh-direnv plugin
git clone https://github.com/ptavares/zsh-direnv.git ~/.zsh-direnv
```

Then stow and create your `~/.zshrc`:

```bash
cd ~/src/dotfiles
stow zsh

# Create ~/.zshrc if it doesn't exist
echo 'source ~/.zshrc_config.zsh' >> ~/.zshrc
```

### Company-specific config

The general config conditionally sources `~/.zshrc_work.zsh` if it exists. On machines where you don't want it, exclude it from stow by creating `zsh/.stow-local-ignore`:

```
\.zshrc_work\.zsh
```

Then restow to apply: `stow -R zsh`. This file is gitignored so it stays local to each machine.

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
