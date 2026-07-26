# Plan: Add Harpoon2 Plugin

## Context

Harpoon2 (ThePrimeagen/harpoon, branch `harpoon2`) is a file bookmarking plugin that lets you mark files and jump to them instantly by index. Unlike the buffer picker (`<leader>m`), harpoon maintains a persistent, ordered list of files per project that survives across sessions. This is useful for quickly switching between 3-5 files you're actively working on without fuzzy-finding every time.

plenary.nvim is already installed (a shared dependency of several plugins, e.g. gitsigns and neotest-golang). The `autosave.lua` file already excludes the `harpoon` filetype, so that's pre-handled.

**Branch note:** The `harpoon2` branch has NOT been merged into `master` — both exist as separate branches. We must pin to `version = 'harpoon2'`.

## Files to Modify

| File | Change |
|---|---|
| `nvim/.config/nvim/lua/plugins.lua` | Add `vim.pack.add` entry for harpoon |
| `nvim/.config/nvim/lua/marks.lua` | **New file** — packadd, setup, extensions, keymaps |
| `nvim/.config/nvim/init.lua` | Add `require('marks')` between `require('git')` and `require('terminal')` |
| `nvim/.config/nvim/lua/whichkey.lua` | Rename `<leader>h` group, add `[h`/`]h` descriptions, add keywords |
| `nvim/.config/nvim/GUIDE.md` | Add Harpoon section, file-responsibilities entry, Keymap-index prefix row (README gets nothing — keymaps are GUIDE-owned per the repo ownership rule) |

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

-- UI: add split keymaps inside the harpoon menu (matches the snacks pickers' <C-v>/<C-s> split keys)
harpoon:extend({
  UI_CREATE = function(cx)
    vim.keymap.set('n', '<C-v>', function()
      harpoon.ui:select_menu_item({ vsplit = true })
    end, { buffer = cx.bufnr })
    vim.keymap.set('n', '<C-s>', function()
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
- `<C-n>` = common picker move-down convention
- `<C-e>` = scroll down / blink.cmp cancel (already mapped)

**Chosen keymaps:**
- `<leader>ha` — add file. Mnemonic: **h**arpoon **a**dd.
- `<leader>hh` — toggle menu. Double-tap `h` after leader is fast.
- `<leader>1`-`<leader>5` — direct file jump by number. Fast, memorable, no conflicts.
- `[h` / `]h` — previous/next harpoon file. Follows `[c`/`]c` (git hunk), `[d`/`]d` (diagnostic) bracket convention.

**`<leader>h` group sharing:** Currently `<leader>h` is "Git hunk" (`<leader>hs` stage, `<leader>hr` reset, etc.). No actual key collisions exist (`ha` and `hh` are unused in git). The which-key group label changes to "Git hunk / Harpoon".

**Why built-in menu over a snacks picker:** harpoon's built-in menu is an editable buffer — you can reorder files by moving lines and delete with `dd`. A fuzzy picker can't replicate this editability. For a list of 3-5 files, the built-in menu is more practical.

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

### 5. `README.md` — no changes

Keymaps are documented in `nvim/.config/nvim/GUIDE.md` only (see the repo
ownership rule in both CLAUDE.md files); harpoon needs no install/binary step,
so README is untouched. The which-key prefix table also lives in GUIDE.md's
Keymap index — update the `<leader>h` row there ("Git hunk / Harpoon") as part
of step 6.

### 6. Update `GUIDE.md`

**Add to the "File responsibilities" table**:
```
| `marks.lua` | Harpoon2: file bookmarks — persistent per-project file list, direct navigation by index (1-5), quick menu with split support, highlight + number extensions |
```

**Update the "Keymaps" section** to mention harpoon keymaps under marks.lua.

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

Inside the quick menu: `<C-v>` opens in vsplit, `<C-s>` in hsplit, `dd` removes
a file, rearrange lines to reorder. (A future revision could bind `<C-x>` to
remove-entry to match the repo-wide "delete item under cursor" convention.) `1`-`9` number keys select directly
(via `navigate_with_number` extension).

### Why built-in menu over a snacks picker

Harpoon's built-in menu is an editable buffer — you can reorder files by
moving lines and delete with `dd`. A fuzzy picker can't replicate this
editability. For a list of 3-5 files, the built-in menu is more practical
than a fuzzy finder.

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
