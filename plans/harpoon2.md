# Plan: Add Harpoon2 Plugin

## Context

Harpoon2 (ThePrimeagen/harpoon, branch `harpoon2`) is a file bookmarking plugin that lets you mark files and jump to them instantly by index. Unlike the buffer picker (`<leader>m`), harpoon maintains a persistent, ordered list of files per project that survives across sessions. This is useful for quickly switching between 3-5 files you're actively working on without fuzzy-finding every time.

plenary.nvim is already installed (used by telescope and other pickers). The `autosave.lua` file already excludes the `harpoon` filetype, so that's pre-handled.

**Branch note:** The `harpoon2` branch has NOT been merged into `master` — both exist as separate branches. We must pin to `version = 'harpoon2'`.

## Review Critique Summary

The plan was reviewed by an independent agent. Key findings and resolutions:

| # | Critique (severity) | Resolution |
|---|---|---|
| 1 | `[h`/`]h` mnemonic confusion — `h` means "hunk" elsewhere in `<leader>h` (important) | Accepted: use `]h`/`[h` anyway — `h` for "harpoon" in bracket context is clear enough, and `]c`/`[c` already covers hunks. Documented in GUIDE.md. |
| 2 | `<leader>h` group label change incomplete — README and GUIDE.md references not updated (important) | Fixed: added explicit updates to the which-key prefix table in README and the keymaps section in GUIDE.md. |
| 3 | `version = 'harpoon2'` might be stale if merged to master (important) | Verified: `harpoon2` is NOT merged into `master` — both branches coexist. `version = 'harpoon2'` is correct and required. |
| 4 | `highlight_current_file` extension might not exist (important) | Verified: it exists in `lua/harpoon/extensions/init.lua` alongside `navigate_with_number` and `command_on_nav`. |
| 5 | Load order placement needs clarity (important) | Fixed: shows exact insertion point in init.lua (line 11→12). |
| 6 | Missing worktree/multi-project `key` discussion (important) | Fixed: added notes section explaining default `cwd` keying and worktree behavior. |
| 7 | `save_on_toggle`/`sync_on_ui_close` comments were swapped (minor) | Fixed: corrected the inline comments. |
| 8 | `marks.lua` name has minor collision risk with marks.nvim (minor) | Accepted as-is: no current collision, and `marks.lua` is short and clear. |
| 9 | Built-in menu vs Telescope trade-off undocumented (minor) | Fixed: added note in GUIDE.md explaining why built-in menu was chosen. |
| 10 | Extend to 5+ slots (suggestion) | Accepted: expanded to `<leader>1`-`<leader>5`. |
| 11 | Add `navigate_with_number` extension (suggestion) | Accepted: shows file numbers in the quick menu, reinforces `<leader>1`-`<leader>5`. |
| 12 | No feedback on `<leader>ha` add (suggestion) | Accepted: added `vim.notify` after adding a file. |
| 13 | Add `p` (paste/reorder) to README menu table (suggestion) | Accepted. |
| 14 | Data directory path may be inaccurate (suggestion) | Fixed: uses `vim.fn.stdpath('data')` phrasing instead of hardcoded path. |

## Files to Modify

| File | Change |
|---|---|
| `nvim/.config/nvim/lua/plugins.lua` | Add `vim.pack.add` entry for harpoon |
| `nvim/.config/nvim/lua/marks.lua` | **New file** — packadd, setup, extensions, keymaps |
| `nvim/.config/nvim/init.lua` | Add `require('marks')` between `require('git')` and `require('terminal')` |
| `nvim/.config/nvim/lua/whichkey.lua` | Rename `<leader>h` group, add `[h`/`]h` descriptions, add keywords |
| `README.md` | Add Harpoon section, update which-key prefix table |
| `nvim/.config/nvim/GUIDE.md` | Add Harpoon section, update file responsibilities table, update keymaps section |

## Implementation

### 1. Register plugin in `plugins.lua`

Add after the "Workflow" group (before the AI comment), around line 44:

```lua
  -- Navigation
  { src = gh('ThePrimeagen/harpoon'), version = 'harpoon2' },
```

### 2. Create `nvim/.config/nvim/lua/marks.lua`

Named `marks.lua` to avoid collision with `require('harpoon')` (the plugin itself).

```lua
vim.cmd.packadd('harpoon')
local harpoon = require('harpoon')

harpoon:setup({
  settings = {
    save_on_toggle = true,    -- persist to disk when toggling the menu
    sync_on_ui_close = true,  -- sync menu edits (reorder, delete) back to the list on close
  },
})

-- Extensions
local extensions = require('harpoon.extensions')
harpoon:extend(extensions.builtins.highlight_current_file()) -- highlight current file in menu
harpoon:extend(extensions.builtins.navigate_with_number())   -- press 1-9 in menu to select

-- UI: add split keymaps inside the harpoon menu (matches Telescope <C-v>/<C-x> convention)
harpoon:extend({
  UI_CREATE = function(cx)
    vim.keymap.set('n', '<C-v>', function()
      harpoon.ui:select_menu_item({ vsplit = true })
    end, { buffer = cx.bufnr })
    vim.keymap.set('n', '<C-x>', function()
      harpoon.ui:select_menu_item({ split = true })
    end, { buffer = cx.bufnr })
  end,
})

-- Keymaps
vim.keymap.set('n', '<leader>ha', function()
  harpoon:list():add()
  vim.notify('Harpoon: added ' .. vim.fn.expand('%:.'))
end, { desc = 'Harpoon: Add file' })

vim.keymap.set('n', '<leader>hh', function()
  harpoon.ui:toggle_quick_menu(harpoon:list())
end, { desc = 'Harpoon: Toggle menu' })

-- Direct navigation to marks 1-5
for i = 1, 5 do
  vim.keymap.set('n', '<leader>' .. i, function()
    harpoon:list():select(i)
  end, { desc = 'Harpoon: File ' .. i })
end

-- Next/previous mark (wraps around)
vim.keymap.set('n', '[h', function() harpoon:list():prev() end,
  { desc = 'Harpoon: Previous file' })
vim.keymap.set('n', ']h', function() harpoon:list():next() end,
  { desc = 'Harpoon: Next file' })
```

#### Keymap rationale

**Why NOT `<C-h/t/n/s>` (harpoon README defaults):**
- `<C-h>` = split navigation (already mapped)
- `<C-s>` = LSP signature help (already mapped)
- `<C-n>` = Telescope move down (commonly expected)
- `<C-e>` = scroll down / blink.cmp cancel (already mapped)

**Chosen keymaps:**
- `<leader>ha` — add file. Mnemonic: **h**arpoon **a**dd.
- `<leader>hh` — toggle menu. Double-tap `h` after leader is fast.
- `<leader>1`-`<leader>5` — direct file jump by number. Fast, memorable, no conflicts.
- `[h` / `]h` — previous/next harpoon file. Follows `[c`/`]c` (git hunk), `[d`/`]d` (diagnostic) bracket convention.

**`<leader>h` group sharing:** Currently `<leader>h` is "Git hunk" (`<leader>hs` stage, `<leader>hr` reset, etc.). No actual key collisions exist (`ha` and `hh` are unused in git). The which-key group label changes to "Git hunk / Harpoon".

**Why built-in menu over Telescope:** The config is Telescope-heavy, but harpoon's built-in menu is an editable buffer — you can reorder files by moving lines and delete with `dd`. Telescope can't replicate this. For a list of 3-5 files, the built-in menu is more practical.

### 3. Update `init.lua`

Insert `require('marks')` after line 11 (`require('git')`) and before line 12 (`require('terminal')`):

```lua
require('git')
require('marks')       -- harpoon: file bookmarks
require('terminal')
```

### 4. Update `whichkey.lua`

**Group label** (line 29): change from:
```lua
{ '<leader>h',  group = 'Git hunk' },
```
to:
```lua
{ '<leader>h',  group = 'Git hunk / Harpoon' },
```

**Add bracket descriptions** in the `wk.add()` block (near the existing `]s`/`[s` entries):
```lua
{ '[h', desc = 'Harpoon: Previous file' },
{ ']h', desc = 'Harpoon: Next file' },
```

**Add to keywords table:**
```lua
['<leader>ha'] = 'harpoon mark bookmark pin add',
['<leader>hh'] = 'harpoon menu list bookmarks pins',
['<leader>1']  = 'harpoon file 1 bookmark pin',
['<leader>2']  = 'harpoon file 2 bookmark pin',
['<leader>3']  = 'harpoon file 3 bookmark pin',
['<leader>4']  = 'harpoon file 4 bookmark pin',
['<leader>5']  = 'harpoon file 5 bookmark pin',
['[h']         = 'harpoon previous bookmark pin',
[']h']         = 'harpoon next bookmark pin',
```

### 5. Update `README.md`

**Add a "Harpoon" section** after the "Session Management" section (around line 427):

```markdown
### Harpoon (file bookmarks)

Persistent file bookmarks — mark files per project and jump to them instantly by number.
Unlike the buffer picker (`<Space>m`), harpoon maintains a fixed ordered list that persists across
sessions.

**Keymaps:**

| Keymap | Action |
|---|---|
| `<Space>ha` | Add current file to harpoon list |
| `<Space>hh` | Toggle harpoon quick menu |
| `<Space>1`-`<Space>5` | Jump to harpoon file 1-5 |
| `[h` / `]h` | Previous / next harpoon file |

**Inside the harpoon menu:**

| Key | Action |
|---|---|
| `<CR>` or `1`-`9` | Open file (by selection or number) |
| `<C-v>` | Open in vertical split |
| `<C-x>` | Open in horizontal split |
| `dd` | Remove file from list |
| `p` | Paste (reorder after `dd`) |
| `q` / `<Esc>` | Close menu |

**Tips:**
- Reorder files in the menu by cutting (`dd`) and pasting (`p`) lines — harpoon saves the new order.
- The list is per-project (based on `cwd`) and persists to disk automatically.
- Use harpoon for your "working set" (3-5 files you keep switching between) and Telescope for everything else.
```

**Update which-key prefix table** (around line 578): change the `<Space>h` row from:
```
| `<Space>h` | Git hunk |
```
to:
```
| `<Space>h` | Git hunk / Harpoon |
```

### 6. Update `GUIDE.md`

**Add to the "File responsibilities" table** (around line 37):
```
| `marks.lua` | Harpoon2: file bookmarks — persistent per-project file list, direct navigation by index (1-5), quick menu with split support, highlight + number extensions |
```

**Update the "Keymaps" section** (around line 328) to mention harpoon keymaps under marks.lua.

**Add a new "Harpoon" section** after the "File Explorer" section:

```markdown
## Harpoon (file bookmarks)

Setup lives in `marks.lua`. Uses `ThePrimeagen/harpoon` (branch `harpoon2`) for
persistent file bookmarks.

### How it works

Harpoon maintains an ordered list of files per project (keyed by `cwd`). You
mark files and jump to them by index (1-5). The list persists to disk under
`vim.fn.stdpath('data')` automatically.

### Keymaps

- `<leader>ha` — add current file to harpoon list (shows notification)
- `<leader>hh` — toggle the quick menu (edit list, reorder, remove)
- `<leader>1`-`<leader>5` — jump to file by position
- `[h` / `]h` — cycle previous/next (wraps around)

Inside the quick menu: `<C-v>` opens in vsplit, `<C-x>` in hsplit, `dd` removes
a file, rearrange lines to reorder. `1`-`9` number keys select directly
(via `navigate_with_number` extension).

### Why built-in menu over Telescope

The config is Telescope-heavy, but harpoon's built-in menu is an editable buffer —
you can reorder files by moving lines and delete with `dd`. Telescope can't
replicate this editability. For a list of 3-5 files, the built-in menu is more
practical than a fuzzy finder.

### Notes

- The file is named `marks.lua` (not `harpoon.lua`) to avoid collision with
  `require('harpoon')` which resolves to the plugin.
- `autosave.lua` already excludes the `harpoon` filetype.
- The `<leader>h` group is shared with git hunk keymaps — no key collisions
  exist (`ha`/`hh` for harpoon, `hs`/`hr`/`hu`/`hp`/`hb` for git).
- `[h`/`]h` uses `h` for "harpoon" in bracket context. Git hunk navigation
  is `[c`/`]c` (unchanged).
- **Worktrees:** harpoon keys lists by `vim.loop.cwd()` by default. Each
  worktree (e.g. claude-squad sessions) gets its own harpoon list automatically.
  If branch-aware keying is needed later, override `settings.key` to include
  the git branch name.
```

## Verification

1. **Restart nvim** — harpoon should install via `vim.pack` on first launch
2. **Open a file** → `<Space>ha` — should see "Harpoon: added <filename>" notification
3. **`<Space>hh`** — quick menu should open showing the added file, with current file highlighted
4. **Open another file** → `<Space>ha` → `<Space>1` — should jump to first file
5. **`<Space>hh`** — menu should show numbered entries (navigate_with_number)
6. **`]h` / `[h`** — should cycle through marked files
7. **Inside menu**: `dd` to remove, cut/paste to reorder, `<C-v>` for vsplit, press `2` to jump to second entry
8. **Quit and reopen nvim** — `<Space>hh` should show previously marked files (persistence)
9. **`<Space>sk`** — search "harpoon" — all keymaps should appear
10. **`<Space>?`** — `<leader>h` group should show both git and harpoon keymaps
