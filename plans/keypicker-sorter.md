# Keypicker: Custom sorter to prioritize key-command matches

## Context
When searching in the keypicker (`<leader>sk`), typing a key command like "u"
should prioritize the actual `u` keybinding (undo) over entries where "u"
happens to appear in the description or group name.

**Done so far:** Reordered the ordinal to put `keys` first (lines 59, 76 of
`keypicker.lua`). This helps because fzy penalizes later positions, but the
penalty is only `-0.005` per character — not enough weight on its own.

## Remaining work: custom sorter with tiered key-field boosting

Replace `conf.generic_sorter({})` on line 108 of `keypicker.lua` with a
wrapper that boosts entries where the prompt matches the `keys` field.

### Design

Wrap Telescope's generic sorter (same pattern as Telescope's own
`fuzzy_with_index_bias` in `telescope/sorters.lua:412`). The wrapper:

1. Delegates to the base sorter for the fuzzy score on the full ordinal.
2. If the prompt matches the entry's `keys` field, multiplies the score by a
   boost factor (lower score = better rank in Telescope).

Tiered boosting:
- **Exact match** (prompt `u`, keys `u`) → `score * 0.1`
- **Prefix match** (prompt `<leader>s`, keys `<leader>sf`) → `score * 0.4`
- **Substring match** (prompt `q`, keys `<leader>qq`) → `score * 0.7`
- **No key match** → score unchanged

### Implementation (inline in keypicker.lua)

```lua
local function keys_boosted_sorter()
  local base = conf.generic_sorter({})
  local FILTERED = -1

  return require('telescope.sorters').Sorter:new({
    scoring_function = function(_, prompt, line, entry)
      local score = base:scoring_function(prompt, line, entry)
      if score == FILTERED then return FILTERED end

      local keys = (entry.value and entry.value.keys or ''):lower()
      local p = prompt:lower()
      if keys == p then
        score = score * 0.1      -- exact match on key
      elseif keys:find(p, 1, true) == 1 then
        score = score * 0.4      -- prefix match
      elseif keys:find(p, 1, true) then
        score = score * 0.7      -- substring match
      end

      return score
    end,
    highlighter = base.highlighter,
  })
end
```

Then on line 108:
```lua
sorter = keys_boosted_sorter(),
```

### Why wrap instead of writing from scratch
- Preserves fzy/fzf-native fuzzy matching and highlighting.
- Follows Telescope's own composition pattern (`fuzzy_with_index_bias`).
- Only adds ~20 lines; no new modules needed.

### Open questions
- Are the boost multipliers (0.1 / 0.4 / 0.7) the right feel? Tune after testing.
- The ordinal reorder (already done) is still helpful — it improves base scores
  for key matches even before the boost multiplier kicks in. Keep both.

## Files to modify
- `nvim/.config/nvim/lua/keypicker.lua` — add `keys_boosted_sorter()`, use it

## Verification
1. `<leader>sk` → type `u` → `u` (Undo) should be first or very near top
2. `<leader>sk` → type `dd` → `dd` (Delete N lines) should rank high
3. `<leader>sk` → type `search` → search-related entries still appear
4. `<leader>sk` → type `quit` → `<leader>qq` still appears (keyword matching works)
5. Highlighting of matched characters still works in the picker
