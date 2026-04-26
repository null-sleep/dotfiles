# Telescope Filter Preset Picker

## Context

When using Telescope's `find_files` or `live_grep`, narrowing results to specific file types requires manually typing glob patterns. The goal is a toggle-based filter system: presets have defaults (all disabled), the picker lets you toggle them on/off for the session, and the existing `<leader>sf` / `<leader>sg` keymaps silently apply whatever's enabled. The Telescope search experience stays unchanged — no modified titles or prompts.

## Usage Example

On startup, all presets are disabled (no filters active — searches work normally):

1. **`<leader>sF`** opens the filter picker:
   ```
   Filter Presets  (Tab toggle, Enter confirm, Esc revert)
   > [ ] go_src       *.go  !*_test.go  !vendor/*
     [ ] frontend     *.ts  *.tsx  !*.test.*
     [ ] protos       *.proto
   ```
2. **Tab** on `go_src` → `[x]`, **Tab** on `protos` → `[x]`, then **Enter** to confirm
3. **`<leader>sg`** now searches only Go and proto files (looks like normal live_grep)
4. **`<leader>sf`** finds only Go and proto files
5. **`<leader>sr`** resumes with the same filters and query
6. To disable: **`<leader>sF`**, Tab off checked items, Enter
7. **Esc** in the picker reverts all toggles made during that session

## Implementation (completed)

### `nvim/.config/nvim/lua/filterpicker.lua` (new)

Module state: ordered list of presets with `enabled` flags (all `false` by default). Exports:

- **`M.pick()`** — Telescope toggle picker. Tab toggles via `picker:refresh(new_finder)` with `vim.schedule`'d cursor restore. Esc reverts via snapshot/`close_windows` override (same pattern as `themepicker.lua`). Enter confirms.
- **`M.get()`** — returns `{ names, globs }` of enabled presets, or `nil`.
- **`M.find_files()`** — applies filters to `telescope.builtin.find_files`. When filters active, overrides `find_command` with `rg --files --hidden --glob ...` (includes `!.git/` and `!node_modules/` since `find_command` bypasses `file_ignore_patterns`).
- **`M.live_grep()`** — applies filters to `telescope.builtin.live_grep` via `glob_pattern`. Existing `additional_args` and `file_ignore_patterns` from `plugins.lua` still apply.

### `nvim/.config/nvim/lua/keymaps.lua` (modified)

- `<leader>sf` → `require('filterpicker').find_files()`
- `<leader>sg` → `require('filterpicker').live_grep()`
- `<leader>sF` → `require('filterpicker').pick()` (new)

All keymaps stay as one-liners. Filter logic lives in `filterpicker.lua`.

### Implementation notes

- `picker:refresh()` is async — `set_selection` is wrapped in `vim.schedule()` to run after refresh completes
- `action_state.get_current_picker(prompt_bufnr)` used instead of outer `picker` variable inside `attach_mappings` (which runs during `pickers.new()` before assignment)
- Picker uses `previewer = false` and `height = math.max(#filter_sets, 7) + 4` for compact layout
- `ordinal` is name-only for fuzzy matching; `display` includes checkbox + padded name + globs

## Verification

1. No filters set (default): `<leader>sf` and `<leader>sg` work exactly as before
2. `<leader>sF` → toggle on `go_src` → Enter → `<leader>sg` results limited to Go files
3. `<leader>sf` results limited to Go files, `.git/` and `node_modules/` still excluded
4. `<leader>sF` → toggle on `protos` too → Enter → both Go and proto files in results
5. `<leader>sF` → toggle off everything → Enter → searches are unfiltered again
6. `<leader>sF` → toggle some things → Esc → filters unchanged (reverted)
7. `<leader>sr` resumes filtered search with query intact
8. Cursor position preserved when toggling multiple items in the picker

## Follow-up

- **Active filter display**: Show active filters visibly — prompt_title, results_title, prompt_prefix, and/or statusline indicator. High priority for v1.1.
- **Persistence across sessions**: Save filter state to a file or integrate with persistence.nvim / `<leader>ql` session restore
