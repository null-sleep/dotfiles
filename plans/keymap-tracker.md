# Plan: Keymap usage tracker

Track every explicit keymap invocation to a persistent flat log file. Goal: answer "which keymaps
do I never use?" and "which do I reach for most?" over time.

---

## Requirements

- Every invocation gets its own log line with timestamp + basic metadata
- Persists across Neovim restarts
- Scope: all explicitly mapped keys — `<leader>`, `<C->`, `<M->`, `<S->`, `yp`, `zg`, etc.
- Log format (one line per invocation):
  ```
  2026-05-03T14:22:01 n <leader>sf [Search: Files]
  ```
  Fields: ISO timestamp, mode, lhs, desc

---

## Implementation options

### Option A — vim.keymap.set shim (recommended)

Monkey-patch `vim.keymap.set` early in `init.lua` with a thin wrapper. The wrapper records
`{ mode, lhs, desc }` at definition time, then wraps the `rhs` so each invocation appends a
log line before executing.

```lua
-- lua/keymap_tracker.lua
local log_path = vim.fn.stdpath('data') .. '/keymap_usage.log'
local queue = {}

local orig_set = vim.keymap.set
vim.keymap.set = function(mode, lhs, rhs, opts)
  opts = opts or {}
  local desc = opts.desc or ''
  local modes = type(mode) == 'table' and mode or { mode }
  -- only wrap callable/string rhs (not expr mappings — those return strings, not actions)
  if not opts.expr then
    local orig_rhs = rhs
    rhs = function(...)
      table.insert(queue, string.format('%s %s %s [%s]\n',
        os.date('%Y-%m-%dT%H:%M:%S'),
        vim.api.nvim_get_mode().mode,
        lhs,
        desc
      ))
      if type(orig_rhs) == 'function' then
        return orig_rhs(...)
      else
        vim.cmd(orig_rhs)
      end
    end
  end
  orig_set(mode, lhs, rhs, opts)
end

-- Flush queue to disk periodically and on exit
local function flush()
  if #queue == 0 then return end
  local f = io.open(log_path, 'a')
  if f then
    f:write(table.concat(queue))
    f:close()
  end
  queue = {}
end

vim.api.nvim_create_autocmd({ 'VimLeave', 'FocusLost' }, { callback = flush })
-- Also flush every N seconds to avoid data loss on crashes
local timer = vim.uv.new_timer()
timer:start(30000, 30000, vim.schedule_wrap(flush))

return { flush = flush, log_path = log_path }
```

Load before anything else in `init.lua`:
```lua
require('keymap_tracker')  -- must be first, before keymaps.lua
```

**Pros:** zero changes to existing keymaps, covers everything defined via vim.keymap.set
**Cons:** doesn't cover native unmapped motions (j, w, etc.) — that's fine for this use case.
expr mappings skipped to avoid breaking them (they return strings, not actions).

---

### Option B — vim.on_key global listener

`vim.on_key(fn)` fires on every raw keypress. Filter against a table of registered lhs strings.

```lua
local tracked = {}  -- populated by iterating vim.api.nvim_get_keymap for each mode

vim.on_key(function(key)
  local mode = vim.api.nvim_get_mode().mode
  local entry = tracked[mode .. key]
  if entry then log(entry) end
end)
```

**Pros:** catches everything including native motions if desired
**Cons:** raw key bytes don't reliably match lhs strings (e.g. `<leader>` expands, multi-key
sequences need buffering). High complexity for little gain over Option A. Performance risk.

---

### Option C — manual map() helper

Define a `map(mode, lhs, rhs, opts)` helper and migrate all `vim.keymap.set` calls to use it.

**Pros:** most explicit, easy to audit
**Cons:** requires touching every keymap definition; easy to miss plugin-defined keymaps;
maintenance burden as new keymaps are added

---

## Log file location

`vim.fn.stdpath('data') .. '/keymap_usage.log'`  
Typically `~/.local/share/nvim/keymap_usage.log` on macOS/Linux.

---

## Analysis ideas (future)

- Shell alias `kmap-top` → `sort keymap_usage.log | uniq -c | sort -rn | head -30`
- Shell alias `kmap-unused` → cross-reference log against registered keymaps, show never-used ones
- Telescope picker over the log for in-Neovim analysis
- Weekly summary script (count by day, show trends)

---

## Files to create/change

- `nvim/.config/nvim/lua/keymap_tracker.lua` — new module
- `nvim/.config/nvim/init.lua` — add `require('keymap_tracker')` as first line after options
