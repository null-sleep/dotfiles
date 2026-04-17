# Plan: Custom telescope entry_maker for git_status

## Context
Telescope's `git_status` picker shows staged/unstaged files but the two-column status codes
(`MM`, `M `, ` M`) are hard to read — same symbol, same colour, no labels. The goal is to
learn how `entry_maker` works and use it to make git status output visually clearer.

---

## How entry_maker works

Each telescope picker accepts an `entry_maker` function. It receives a raw item (a line of
output, a file path, etc.) and returns a table describing how to display it:

```lua
entry_maker = function(raw)
  return {
    value   = raw,           -- the raw value, passed back on selection
    ordinal = raw.filename,  -- string telescope filters against when you type
    display = function(entry)
      local line = ...       -- build the display string
      local highlights = {   -- highlight regions applied over the string
        { { start_col, end_col }, 'HighlightGroup' },
      }
      return line, highlights
    end,
  }
end
```

Key points:
- `ordinal` is what fuzzy matching runs against — keep it as the filename/search term
- `display` can be a plain string or a function returning `(string, highlights)`
- "Columns" are just fixed-width padded strings: `string.format('%-8s', value)`
- Highlights are `{ {start, end}, 'HlGroup' }` pairs — multiple can overlap
- The display function receives the full entry table, not just the raw value

### Real example from telescope source

The built-in `git_status` entry maker lives in:
```
~/.local/share/nvim/site/pack/core/opt/telescope.nvim/lua/telescope/make_entry.lua
```
Look for `gen_from_git_status` — this is the function to study and override.

---

## What the two-char git status codes mean

Git status uses a two-character code: `[staged][worktree]`

| Code | Meaning |
|------|---------|
| `M ` | Staged modified, worktree clean |
| ` M` | Not staged, worktree modified |
| `MM` | Staged and worktree both modified |
| `A ` | Staged new file |
| `D ` | Staged deleted |
| ` D` | Unstaged deleted |
| `??` | Untracked |
| `R ` | Renamed (staged) |

So `entry.status` in the entry maker is a two-char string — parse `entry.status:sub(1,1)` for
staged status and `entry.status:sub(2,2)` for worktree status.

---

## Goal: improved git_status display

Replace the default two-column `[X][Y] filename` format with something clearer:

**Option A — Labelled columns:**
```
staged   ~ packages/app/.../service.go
worktree ~ packages/client/.../presenter.ts
both     ~ README.md
```

**Option B — Colour-coded single icon:**
- Staged changes → green icon
- Unstaged changes → yellow icon
- Both → orange icon
- Untracked → grey icon

Option B is cleaner. Use a single icon but vary the highlight group by status:

```lua
local status_hl = {
  staged   = 'diffAdded',     -- green
  unstaged = 'diffChanged',   -- yellow
  both     = 'WarningMsg',    -- orange
  untracked = 'Comment',      -- grey
}
```

---

## Implementation sketch

```lua
local entry_maker = function(entry)
  local staged   = entry.status:sub(1, 1)
  local worktree = entry.status:sub(2, 2)

  local icon, hl
  if staged ~= ' ' and staged ~= '?' and worktree ~= ' ' then
    icon, hl = '●', 'WarningMsg'       -- both staged and unstaged changes
  elseif staged ~= ' ' and staged ~= '?' then
    icon, hl = '●', 'diffAdded'        -- staged only
  elseif worktree ~= ' ' then
    icon, hl = '●', 'diffChanged'      -- unstaged only
  else
    icon, hl = '?', 'Comment'          -- untracked
  end

  local display_str = icon .. ' ' .. entry.filename

  return {
    value   = entry,
    ordinal = entry.filename,
    display = function(_)
      return display_str, { { { 0, 2 }, hl } }
    end,
    path    = entry.filename,  -- needed for previewer
  }
end

-- Use it:
require('telescope.builtin').git_status({ entry_maker = entry_maker })
```

Wire it up as a keymap replacement for `<leader>sm`.

---

## Files to change
- `nvim/.config/nvim/lua/keymaps.lua` — replace `builtin.git_status` with a custom picker call

---

## Custom previewers

Telescope also supports fully custom previewers — not just entry display but the entire right
pane. Two types:

- **`new_buffer_previewer`** — renders into a nvim buffer (syntax highlighting works, can use
  `nvim_buf_set_lines` to write anything)
- **`new_termopen_previewer`** — runs a shell command and streams stdout into the pane

```lua
local previewers = require('telescope.previewers')

local my_previewer = previewers.new_buffer_previewer({
  title = 'My Preview',

  dyn_title = function(self, entry)
    return entry.filename  -- shown in preview border, updates per selection
  end,

  define_preview = function(self, entry, status)
    -- self.state.bufnr is the preview buffer — write into it freely
    -- load the file with syntax highlighting:
    conf.buffer_previewer_maker(entry.path, self.state.bufnr, {
      bufname = self.state.bufname,
    })
    -- or write custom content:
    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
      'File: ' .. entry.filename,
      string.rep('─', 40),
      -- ... diff lines etc
    })
  end,
})

-- pass it to a picker:
pickers.new({}, {
  previewer = my_previewer,
}):find()
```

### Showing filename at the bottom of the preview

One approach: in `define_preview`, after loading the diff content, append a separator and the
full filename as the last lines of the buffer:

```lua
define_preview = function(self, entry, status)
  -- load diff first (existing content)
  ...
  -- then append filename footer
  local line_count = vim.api.nvim_buf_line_count(self.state.bufnr)
  vim.api.nvim_buf_set_lines(self.state.bufnr, line_count, -1, false, {
    string.rep('─', 60),
    entry.filename,
  })
end
```

This effectively creates a "status bar" at the bottom of the preview buffer showing the full
path, which solves the truncation problem without needing a second window.

---

## Learning resources
- `make_entry.lua` in telescope source — read `gen_from_git_status` first
- `previewers/buffer_previewer.lua` in telescope source — read `git_file_diff` previewer
- `:h telescope.entry` — entry table fields documented here
- telescope wiki: "Customizing the display" section

---

## Verification
1. `<leader>sm` — staged files show green icon, unstaged show yellow, both show orange
2. Fuzzy filtering still works (ordinal is set to filename)
3. Opening a file from the picker works (path field set correctly)
4. Preview still shows the file diff
5. Full filename visible at bottom of preview pane
