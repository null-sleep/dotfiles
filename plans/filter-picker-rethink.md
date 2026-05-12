# Rethink: Filter Picker System

## Problem

Current filter system (`nvim/.config/nvim/lua/pickers/filter.lua`) has two friction points:

1. **Static presets in Lua** — adding/changing a preset requires editing Lua code and reloading the config. The preset list is plain data (names + globs); shouldn't require code changes.
2. **Filters can only be toggled before `<leader>sg`** — once in `live_grep`, there's no way to refine the active filter set. Have to escape, re-toggle, re-grep.

## Goals

- Define filter presets in a plain text/data file (TOML, YAML, or JSON) so they can be edited without touching Lua.
- Neovim picks up changes dynamically — either on each picker open, or on file save (autocmd). No `:source` or restart required.
- While inside `<leader>sg` (live_grep), a keypress (e.g. `<C-f>`) opens the filter picker to add/remove filters, then returns to live_grep with the prompt preserved and new globs applied.

## Design Sketch

### 1. Externalize presets

Move the `filter_sets` table out of `pickers/filter.lua` into a config file. Candidates:

- `~/.config/nvim/filters.toml` — clean syntax, easy to edit by hand
- `~/.config/nvim/filters.json` — universal but verbose
- `~/.config/nvim/lua/pickers/filters_data.lua` — still Lua but pure data, no logic

Example TOML:

```toml
[[preset]]
name = "go_src"
globs = ["*.go", "!*_test.go", "!vendor/*"]

[[preset]]
name = "frontend"
globs = ["*.ts", "*.tsx", "!*.test.*"]

[[preset]]
name = "protos"
globs = ["*.proto"]
```

Neovim ships with no TOML parser; would need a small dep or pick JSON/Lua-data instead. JSON via `vim.json.decode` is zero-dep but ugly to edit. **Recommendation**: start with `filters_data.lua` (pure-data Lua table) — zero parsing cost, syntax highlighting, comments allowed.

### 2. Dynamic reload

Two options:

- **Read-on-open**: re-read the file every time `M.pick()` or `M.live_grep()` is called. Simplest, no autocmd needed.
- **Autocmd watcher**: `BufWritePost` on the filters file invalidates a cached table. Avoids re-reading on every call, but adds complexity.

**Recommendation**: read-on-open. File I/O is negligible at picker-open frequency.

State to preserve across reloads: the `enabled` flag per preset. Keep that in a separate in-memory table keyed by preset name; merge after reload. If a preset is removed from the file, drop its enabled state. If a new preset appears, default `enabled = false`.

### 3. Filter from within live_grep

In `M.live_grep()`, attach a mapping (e.g. `<C-f>`) that:

1. Captures the current prompt text via `action_state.get_current_picker(bufnr):_get_prompt()`.
2. Closes the live_grep picker.
3. Opens `M.pick()` (filter preset picker).
4. After the filter picker closes (either confirm or revert), reopens `builtin.live_grep({ default_text = saved_prompt, glob_pattern = ... })`.

Tricky parts:

- Telescope's `default_text` parameter exists but interacts with `live_grep`'s prompt — verify it actually populates the search term, not just inserts into the buffer.
- Cursor position in the results list won't be preserved (acceptable).
- If the user presses Esc in the filter picker (revert), should we still reopen live_grep? **Yes** — the user's intent was to stay in live_grep, just check the filters. Always reopen.

### 4. Optional: live filter refresh in-place

More ambitious: instead of closing/reopening, rebuild the live_grep finder with the new `glob_pattern` while keeping the picker window open. Requires reaching into Telescope's `picker:refresh()` and replacing the finder. Possible but fragile across Telescope versions.

**Recommendation**: skip this. Close-and-reopen flicker is barely noticeable and the code is far simpler.

## Open Questions

- Do we want a way to *exclude* a preset (negative toggle) without removing it entirely? Current `[x]`/`[ ]` model is fine for now.
- Should there be a "clear all filters" shortcut in the filter picker?
- Does this same dynamic mechanism apply to `<leader>sf` (find_files)? Probably yes for free, since it uses `M.get()`.

## Migration Path

1. Extract `filter_sets` into `pickers/filters_data.lua` as a pure-data return.
2. Update `M.pick()` and `M.get()` to read from that module each call (preserving in-memory enabled state across reads).
3. Add `<C-f>` mapping in `M.live_grep()` for in-flight filter editing.
4. Document in README or as a comment in `filters_data.lua` how to add a preset.

## Effort Estimate

- Steps 1–2 (externalize + dynamic reload): ~1 hour
- Step 3 (in-flight filter edit): ~1 hour
- Testing and polish: ~30 min

Total: half a day.

## Alternatives Considered

- **Switch to fzf-lua or Snacks.picker** which both support inline glob filtering natively (`foo -- -g *.go`). Would obsolete the preset system entirely. Larger migration (half-day to full day) but eliminates the problem rather than improving the workaround.
- **Use telescope-live-grep-args.nvim** for ad-hoc globs alongside the preset system. Adds a plugin dep and creates two ways to filter. Not recommended.
