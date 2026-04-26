# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

```bash
brew install stow
cd ~/src/dotfiles
# Install dependencies for each tool
stow nvim
stow zsh
stow kitty
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

## Languages

Language runtimes required by nvim LSP servers and treesitter.

```bash
# Go
brew install go

# Node (for ts_ls)
brew install node

# Python (for pyright)
brew install python

# Elixir (includes Erlang)
brew install elixir

# Rust (via rustup — do not use brew install rust)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup component add clippy rustfmt rust-analyzer rust-src
```

Rust tools installed by rustup: `cargo`, `rustc`, `clippy`, `rustfmt`, `rust-analyzer`, `rust-src`. The `~/.cargo/bin` PATH entry in `.zshrc_config.zsh` makes them available in the shell.

## Colima

Free container runtime for macOS — a Docker Desktop alternative.

```bash
brew install colima docker

# Apple Silicon
colima start --cpu 8 --memory 8 --arch aarch64 --vm-type=vz --vz-rosetta

# Intel
colima start --cpu 2 --memory 4
```

The `docker` CLI talks to Colima's daemon automatically. The `.zshrc_work.zsh` file includes a `colima_start` helper and an auto-check that warns if Colima isn't running.

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
| `<Space>sm` | Modified files (git status) |
| `<Space>ss` | Symbols (workspace) |
| `<Space>sS` | Symbols (document) |
| `<Space>st` | Theme picker (live preview) |

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

IDE features powered by nvim's built-in LSP client. Four plugins work together:
- **mason.nvim** — installs and manages language servers (`:Mason` to open UI)
- **mason-lspconfig.nvim** — bridges mason and lspconfig, auto-installs servers on startup
- **nvim-lspconfig** — pre-configured setups for each language server
- **lazydev.nvim** — provides Neovim API type annotations to lua_ls (no manual workspace config needed)

Configured servers: `lua_ls`, `pyright`, `ts_ls`, `gopls`, `rust_analyzer`, `elixirls`

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
| `gri` | Go to implementation (opens in telescope) |
| `gy` | Go to type definition |
| `grr` | References (opens in telescope) |
| `grx` | Run codelens under cursor |
| `K` | Hover docs |
| `<C-s>` | Signature help |
| `<Space>rn` | Rename symbol |
| `<Space>ca` | Code actions |
| `<Space>cf` | Format buffer or selection |
| `<Space>e` | Show diagnostic float |
| `[d` / `]d` | Jump to previous / next diagnostic |
| `<Space>cd` | Send diagnostics to location list |

**Diagnostic commands:**

| Command | Description |
|---|---|
| `:checkhealth lsp` | Verify LSP health and active clients |
| `:lua print(vim.inspect(vim.lsp.get_clients()))` | Show all active LSP clients |

**Diagnostic toggles:**

Diagnostic virtual text and gutter signs are **off by default** — underlines remain active
so diagnostics are still visible on hover (`K` or `<Space>e`).

**LSP features** (enabled automatically when the server supports them):

- **Inlay hints** — parameter names, inferred types (useful for Rust/Go/TS). Toggle with `<Space>ti` when noisy.
- **Document highlight** — when cursor pauses on a symbol (~300ms), other occurrences in the buffer are highlighted.
- **Codelens** — virtual text annotations (run tests, implement interface, etc.). `grx` runs the codelens under cursor.

| Keymap | Action |
|---|---|
| `<Space>td` | Toggle diagnostic virtual text and gutter signs on/off |
| `<Space>ti` | Toggle inlay hints on/off |
| `<Space>tb` | Toggle inline git blame |

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
| `▎` | Added line |
| `▎` | Changed line |
| `▂` / `▔` | Deleted line (below / above) |
| `▎` | Changed and deleted |
| `░` | Untracked file |

**Git hunk keymaps:**

| Keymap | Action |
|---|---|
| `]c` / `[c` | Jump to next / previous hunk |
| `<Space>hs` | Stage hunk |
| `<Space>hr` | Reset hunk |
| `<Space>hu` | Undo stage hunk |
| `<Space>hp` | Preview hunk |
| `<Space>hb` | Blame line (full commit info) |

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


### Auto-save (auto-save.nvim)

Buffers are saved automatically on focus loss, leaving insert mode, and after text changes (1s debounce).
Special buffers (telescope, mason, gitcommit) are excluded. No keymaps — it just works in the background.

### Auto-pairs (nvim-autopairs)

Automatically closes brackets, quotes, and other pairs. Treesitter-aware — won't auto-pair inside
strings or comments where it would be wrong.

### Notifications (mini.notify)

Floating notification windows that auto-dismiss. Replaces vim's default `vim.notify` which echoes
to the command line and prompts on long messages. LSP progress notifications are suppressed to
avoid noise from language servers scanning the workspace.

### Markdown Rendering (render-markdown.nvim)

Renders markdown files in the buffer with formatted headings, bold, italic, code blocks, and lists.
Active automatically when opening `.md` files.

### General Keymaps

| Keymap | Action |
|---|---|
| `:Q` / `<Space>qq` | Quit all |
| `y` / `Y` | Yank to system clipboard (dd, x, c stay in Neovim register) |
| `p` (visual) | Paste without clobbering register |
| `<` / `>` (visual) | Indent/dedent and stay in visual mode |
| `Ctrl+h/j/k/l` | Navigate between splits |
| `<Esc>` | Clear search highlights |
| `<Space>?` | Show all keymaps (which-key) |
| `yp` | Yank relative file path |
| `yP` | Yank absolute file path |
| `yc` | Yank Claude @-reference with line numbers |
| `yC` | Yank Claude @-reference (absolute path) |
| `yu` | Yank GitHub permalink |

### Keymap Discovery (which-key.nvim)

Press `<Space>` and wait — a popup appears showing all available keymaps for that prefix,
grouped by category. Helps discover keymaps without needing to remember them all.

| Prefix | Group |
|---|---|
| `<Space>s` | Search |
| `<Space>q` | Session/Quit |
| `<Space>t` | Toggle |
| `<Space>h` | Git hunk |
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
- Theme updates automatically when you switch themes (via `<Space>st` or `lua/themes.lua`)

### Themes

All themes are configured in `lua/themes.lua`. Switch themes interactively with `<Space>st` (live preview as you scroll), or edit `M.active` directly:

```lua
M.active = 'catppuccin'        -- default dark
M.active = 'catppuccin-latte'  -- light variant
M.active = 'tokyonight-day'    -- light variant
M.active = 'rose-pine-dawn'    -- light variant
```

The active theme is persisted to `~/.local/share/nvim/theme.txt` and restored on next launch. The theme picker (`<Space>st`) saves automatically on selection.

See `M.variants` in `lua/themes.lua` for all available colorscheme names with descriptions.

To customise a theme, edit its `setup` function or `overrides` table in `lua/themes.lua`.

**Tip:** position the cursor on any UI element and run `:Inspect` to find its highlight group name for overrides.

**Installed themes:** catppuccin, tokyonight, gruvbox, rose-pine, kanagawa, nightfox, cyberdream, dracula, solarized,
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

**Remaps not yet configured** — listed here for reference when customising `keymaps.lua`:

| Remap | What it does | Why |
|---|---|---|
| `jk` → `<Esc>` | Exit insert mode without reaching for Escape | Faster than `<Esc>`, keeps hands on home row |
| `H` / `L` → prev/next buffer | Cycle open buffers | Default H/L (screen top/bottom) are rarely used |
| `J` in visual → move lines down | Move selected lines down | More intuitive than `:m '>+1` |
| `K` in visual → move lines up | Move selected lines up | More intuitive than `:m '<-2` |
| `n` → `nzzzv` | Center screen after search jump | Keeps match in the middle of the viewport |

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

## Kitty

GPU-accelerated terminal emulator. Config is managed via stow.

```bash
brew install --cask kitty
cd ~/src/dotfiles
stow kitty
```

Settings are ported from the iTerm2 profile (Hack Nerd Font Mono 15pt, 125×25 window, bar cursor). To pick a color theme interactively:

```bash
kitten themes
```

This writes `~/.config/kitty/current-theme.conf` which kitty auto-includes. The config lives at `~/.config/kitty/kitty.conf` (symlinked by stow).

### Keymaps

| Shortcut | Action |
|---|---|
| `Cmd+N` | New window |
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab/window |
| `Cmd+Enter` | New OS window |
| `Cmd+D` | No built-in split — use tabs or launch a second window |
| `Cmd+1-9` | Jump to tab by number |
| `Cmd+Shift+]` / `Cmd+Shift+[` | Next / previous tab |
| `Ctrl+Shift+Enter` | New window (split within tab, requires layout change) |
| `Ctrl+Shift+]` / `Ctrl+Shift+[` | Next / previous window in tab |

**Layouts** (cycle with `Ctrl+Shift+L`): tall, fat, grid, horizontal, vertical, stack.

### Commands

| Command | Description |
|---|---|
| `kitten themes` | Browse and apply color themes |
| `kitten diff file1 file2` | Side-by-side diff |
| `kitten ssh host` | SSH with full kitty features on remote |
| `kitty +kitten icat image.png` | Display image in terminal |

## ZSH

```bash
# Dependencies
brew install fzf ripgrep direnv

# Install Antigen (zsh plugin manager). Antigen will clone oh-my-zsh and all
# configured plugins into ~/.antigen/bundles on first shell launch — no need
# to install oh-my-zsh separately.
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

Open a new shell. On the first launch antigen clones every bundle (takes ~20s) and writes a cached loader to `~/.antigen/init.zsh`. Subsequent launches just source the cache.

### Per-machine config

`.zshrc_config.zsh` conditionally sources two optional files:

- **`~/.zshrc_shared.zsh`** — stowed from this repo. Shared per-project tooling. Lives in version control.
- **`~/.zshrc_work.zsh`** — *not* stowed. `zsh/.stow-local-ignore` excludes it so each work machine drops its own copy at `~/.zshrc_work.zsh`. The repo copy is a reference template.

Secrets go in `~/.zshenv`, which is not managed by stow.

### Troubleshooting antigen

If you see `tee: /completions/_docker: No such file or directory` on shell startup, or your prompt shows a literal `$(git_prompt_info)` instead of rendering, antigen has cached an empty `$ZSH` / `$ZSH_CACHE_DIR`. Wipe and rebuild the cache:

```bash
rm -f ~/.antigen/init.zsh ~/.antigen/init.zsh.zwc ~/.antigen/.zcompdump ~/.antigen/.zcompdump.zwc
exec zsh
```

`.zshrc_config.zsh` exports those vars explicitly before `antigen apply` so the regenerated cache captures the right paths.

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
