# Quickfix window improvements

**Status:** research / not started
**Date:** 2026-07-07

A survey of quickfix-enhancement plugins (styling, preview, editable buffer,
fzf filtering) and a recommendation for what to add to this config, mapped to
this repo's existing conventions.

---

## Current state (for gap reference)

Nothing in this config enhances the quickfix window itself today — it's
Neovim's plain built-in UI. What does touch quickfix:

- `satellite.lua` — `handlers.quickfix.enable = true` puts quickfix-item
  marks in the scrollbar. Cosmetic only, no relation to the window itself.
- `stickybuf.nvim` — already auto-pins quickfix windows (`buftype ==
  "quickfix"` is handled by stickybuf's built-in defaults, confirmed in
  `stickybuf.lua`), so a stray `:e`/buffer-jump can't hijack a quickfix
  split. No config needed for any candidate below.
- `lsp.lua` — `gd`/`gy` route multi-result LSP jumps through a Telescope
  picker instead of letting Neovim dump them into quickfix (see the comment
  at `lsp.lua:204`). Quickfix is still the fallback when Telescope isn't
  available, and still what `:grep`/`:vimgrep`/`:make`/`:cfdo` and any
  quickfix-populating command use directly.
- `<leader>q*` is already claimed by `session.lua` (persistence.nvim —
  save/restore/quit), grouped as "Session/Quit" in `whichkey.lua`. Every
  candidate below defaults its docs to a `<leader>q` toggle keymap — that
  collides here and needs remapping (see "Keymap collision" below).

The gap: no context lines, no syntax highlighting in the list, no
inline-editable quickfix buffer, no fzf-style filtering, no preview window.

---

## Candidates

### Top pick: `stevearc/quicker.nvim`

Modern, actively developed, UI + workflow focused.

- **Syntax highlighting** of the matched line using treesitter/LSP, so grep
  results don't look like plain text.
- **Context lines** — press `>` to show N lines of surrounding code above/
  below a match inline in the list, `<` to collapse back. Good for judging a
  grep hit without opening the file.
- **Editable quickfix buffer** — edit the list like a normal buffer (rename
  across every result line) and it writes the changes back to the source
  files, with an `autosave` option (default `"unmodified"`: only buffers
  with no other pending edits autosave).
- Custom icons for diagnostic severities (E/W/I/N/H), responsive filename
  column width.
- Requires Neovim 0.10+ (this config already assumes 0.12 for `vim.pack`,
  so no floor issue).

```lua
{ src = gh('stevearc/quicker.nvim') },
```
```lua
vim.cmd.packadd('quicker.nvim')
require('quicker').setup({
  -- keep buflisted/number/relativenumber/etc. at quicker's defaults;
  -- override only what this config's theme/statusline needs
})
```

- https://github.com/stevearc/quicker.nvim

### `kevinhwang91/nvim-bqf`

Older, more feature-dense, window-behavior focused rather than buffer-editing
focused. **Explicitly compatible with quicker.nvim** (README calls it out as
a complementary bundle) — they solve different problems, so this isn't
either/or.

- **Preview window** — float showing the target file with syntax
  highlighting as you move through the list, without leaving quickfix.
- **fzf-mode filtering** (`zf`) — fuzzy-filter the list down live, requires
  the `fzf` binary (already on this machine via Homebrew, same as fzf-lua's
  dependency in `symbol-picker-alternatives.md`) — optional, degrades
  gracefully without it.
- **Sign-based multi-select** (`<Tab>`) to build a new filtered quickfix list
  from a subset of items.
- Recommends pairing with `nvim-treesitter` for preview highlighting — already
  installed here.
- Requires Neovim 0.6.1+ (no floor issue).

```lua
{ src = gh('kevinhwang91/nvim-bqf') },
```

- https://github.com/kevinhwang91/nvim-bqf

### `yorickpeterse/nvim-pqf` — skip, superseded

Lightweight styling-only plugin (aligned columns, diagnostic-style type
markers). This is a strict subset of what quicker.nvim's syntax-highlighting
+ icon config already does, and **both plugins claim `quickfixtextfunc`** —
only one can own it. Not worth installing alongside quicker.nvim; mentioned
here only because it's a common recommendation in "quickfix plugin" lists.

- https://github.com/yorickpeterse/nvim-pqf

### `romainl/vim-qf` — skip, redundant with what's proposed

A mappings/behavior layer (open-on-populate toggles, `<C-n>`/`<C-p>` list
cycling, adjust-window-height). Quicker.nvim's README lists it as compatible,
but its value-add mostly duplicates config this plan already covers via
quicker.nvim + bqf's own keymaps and `auto_resize_height`. Worth a second
look only if a specific mapping/behavior gap shows up after using
quicker.nvim + bqf for a while.

- https://github.com/romainl/vim-qf

### Other notables surveyed, not recommended

- `folke/trouble.nvim` — a full alternative *UI* for quickfix/diagnostics/
  references (its own floating list, not the native quickfix window). Not a
  quickfix enhancement so much as a replacement surface; already tracked as
  a candidate for the diagnostics/references panel gap in
  `plans/features-from-other-editors.md` (Zed "problems panel" section) —
  don't duplicate that discussion here. Quicker.nvim's README confirms no
  conflict if both end up installed later.
- `ashfinal/qfview.nvim`, `niuiic/quickfix.nvim` — smaller, less-maintained
  alternatives covering subsets of the above (path-shortening/folding;
  store/restore/remove list management). No feature either offers isn't
  already covered by quicker.nvim + bqf; not worth the extra plugin surface.
- "replacer.nvim" / "quickfix-reflector.vim" — both provide editable-quickfix
  functionality that **directly conflicts** with quicker.nvim (same
  `quickfixtextfunc` ownership problem as nvim-pqf, per quicker.nvim's own
  compatibility table). Skip — quicker.nvim's built-in editable buffer
  already covers this.

---

## Recommendation

Install **quicker.nvim** first (styling + context lines + editable buffer —
the highest-value, lowest-risk addition, no conflicts with anything
currently installed). Add **nvim-bqf** afterward if the preview window /
fzf-filtering is missed in practice — they're confirmed compatible, so this
can be staged as two small changes instead of one larger evaluation.

Do **not** add nvim-pqf, vim-qf, or the editable-quickfix alternatives —
each is either redundant with or directly conflicts with quicker.nvim.

---

## Integration notes for this repo

### Keymap collision

Every candidate's README suggests `<leader>q` for "toggle quickfix" — already
the "Session/Quit" group (`session.lua`, `whichkey.lua`). Don't reuse it.
`<leader>x` is unclaimed globally (only bound buffer-locally inside
gitcommit/gitrebase buffers in `git.lua:78`, for `:cq` abort) and matches the
community convention other Neovim configs use for quickfix/diagnostics lists
(e.g. trouble.nvim's `<leader>xx`). Proposed:

- `<leader>xq` — toggle quickfix (`require('quicker').toggle()`)
- `<leader>xl` — toggle loclist (`require('quicker').toggle({ loclist = true })`)

Add a `{ '<leader>x', group = 'Quickfix' }` entry to `whichkey.lua`'s
`wk.add()` list and a `<leader>x*` row to GUIDE.md's `By prefix` table.

### Files to touch

- `nvim/.config/nvim/lua/plugins.lua` — `vim.pack.add` entries (quicker.nvim,
  later bqf) grouped under a new `-- Quickfix` comment block, near the
  `-- Workflow` or `-- UI` sections.
- New `nvim/.config/nvim/lua/quickfix.lua` — follows this config's
  topic-file-per-concern pattern (see `nvim/.config/nvim/CLAUDE.md`'s "avoids
  shadowing a plugin's own Lua module name" convention — `quickfix.lua` is
  safe since neither plugin's own module is named that: quicker.nvim's is
  `quicker`, bqf's is `bqf`). `require()` it from `init.lua`.
- `nvim/.config/nvim/lua/whichkey.lua` — new `<leader>x` group.
- `nvim/.config/nvim/GUIDE.md` — per this directory's `CLAUDE.md`: an
  Architecture file-responsibilities entry + `Load order` update, a new Part
  2 section (`## Quickfix`) with its own keymap table, and a `By prefix` row
  pointing to it. Follow the "Update GUIDE.md in the same change" rule —
  don't land the plugin without this.
- `nvim/.config/nvim/nvim-pack-lock.json` — commit after `vim.pack.add`
  pulls the new plugins (per this directory's CLAUDE.md "recurring
  conventions").

### Test plan

1. Add quicker.nvim only, restart, run `:grep` or a Telescope live-grep that
   sends results to quickfix (`<C-q>` in Telescope, if used) — confirm
   syntax highlighting, `>`/`<` context lines, and that editing a result line
   and `:w`-ing the quickfix buffer updates the source file.
2. Bind `<leader>xq`/`<leader>xl`, confirm no clash with existing `<leader>x`
   git-abort buffer-local map (different buffers, shouldn't collide, but
   verify in a gitcommit buffer specifically).
3. If context lines / editable buffer feel sufficient, stop here for a few
   days of real use before adding bqf.
4. Add nvim-bqf, confirm `zf` fzf-filter mode works (needs the `fzf` binary)
   and the preview float doesn't fight quicker.nvim's own window (should be
   fine per the compatibility note above, but verify visually).
5. Update GUIDE.md + whichkey.lua + nvim-pack-lock.json in the same commit
   per this repo's CLAUDE.md rules.
