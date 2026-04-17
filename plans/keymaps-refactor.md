# Plan: Keymaps reorganisation, which-key enrichment, and cheatsheet

## Context
Keymaps are currently scattered across multiple files (keymaps.lua, lsp.lua, session.lua) with
inconsistent desc formats and no central overview. which-key only has 4 group labels. There is
no personal cheatsheet. This plan consolidates everything, enriches which-key, and adds a
cheatsheet keymap.

---

## TODO

### 1. Reorganise keymaps.lua

**Problems:**
- Keymaps spread across keymaps.lua, lsp.lua, session.lua
- Inconsistent desc format (`'Search: Files'` vs `'LSP: Go to definition'` vs `'Session: Restore'`)
- No sections or comments grouping by purpose
- `<leader>q` is used both for session (persistence) AND for LSP diagnostic list — conflict

**Changes:**
- Standardise all desc strings to `'Group: Action'` format (already mostly there, just make it consistent)
- Add section comments in keymaps.lua grouping by: Search, Toggle, LSP (note: LSP keymaps stay in lsp.lua since they're buffer-local, but document this)
- Resolve `<leader>q` conflict — LSP diagnostic list (`vim.diagnostic.setloclist`) should move to `<leader>dq`, freeing `<leader>q` prefix for session exclusively
- Move session keymaps from session.lua into keymaps.lua for a single source of truth (session.lua keeps only the setup() call)

---

### 2. Enrich which-key with icons and LSP group

**Changes to whichkey.lua:**
- Add missing group labels: `<leader>r` (Rename/Refactor), `<leader>c` (Code), `<leader>d` (Diagnostics), `<leader>g` (Go to)
- Add icons to groups using which-key's icon support
- Register buffer-local LSP keymaps with which-key from lsp.lua's on_attach so they appear in the popup

Example enriched group:
```lua
wk.add({
  { '<leader>s', group = 'Search',      icon = '' },
  { '<leader>q', group = 'Session',     icon = '' },
  { '<leader>t', group = 'Toggle',      icon = '' },
  { '<leader>h', group = 'Git hunk',    icon = '' },
  { '<leader>r', group = 'Rename',      icon = '󰑕' },
  { '<leader>c', group = 'Code',        icon = '' },
  { '<leader>d', group = 'Diagnostics', icon = '' },
})
```

---

### 3. Cheatsheet keymap

Create `nvim/.config/nvim/cheatsheet.md` — a personal reference file with:
- All leader keymaps grouped by category
- Useful normal mode motions
- Plugin-specific tips (telescope, gitsigns, etc.)

Add keymap `<leader>?` that opens the cheatsheet in a split:
```lua
vim.keymap.set('n', '<leader>?', function()
  vim.cmd('vsplit ' .. vim.fn.stdpath('config') .. '/cheatsheet.md')
end, { desc = 'Open cheatsheet' })
```

Add `<leader>?` as a top-level which-key entry (not a group, just a single key).

---

### 4. Audit conflicts and establish opinionated prefix conventions

**Goal:** `<Space>x_` prefixes should be semantically consistent. Not pedantic — flexibility
where it makes sense — but the prefix should give a strong hint about what the key does.

**Proposed prefix map:**

| Prefix | Purpose | Notes |
|---|---|---|
| `<leader>s` | Search (telescope) | Already consistent |
| `<leader>t` | Toggle | Already in use for diagnostics. Should be the only toggle prefix |
| `<leader>g` | Go to (LSP navigation) | `gd`, `gr` etc are unprefixed — reserve `<leader>g` for broader git/go-to actions |
| `<leader>h` | Git Hunk | Already planned for gitsigns |
| `<leader>c` | Code actions | `<leader>ca` already in use |
| `<leader>r` | Rename/Refactor | `<leader>rn` already in use |
| `<leader>d` | Diagnostics | Float, list, jump |
| `<leader>q` | Session (Quit/restore) | Free `<leader>q` for session exclusively |
| `<leader>?` | Help/Cheatsheet | Top-level, no subgroup needed |

**Conflicts to resolve:**
- `<leader>q` — used by both persistence (session) and `vim.diagnostic.setloclist` (LSP). Fix: move diagnostic list to `<leader>dl`
- `<leader>td` — planned for gitsigns toggle_deleted but already used for diagnostics toggle. Fix: rename diagnostics toggle to `<leader>td` stays, gitsigns toggle_deleted moves to `<leader>tD` (capital D)
- `<leader>e` — currently LSP show diagnostic float. Could move to `<leader>de` to sit under diagnostics prefix

**How others approach this:**

The most widely referenced community convention is **LazyVim's keymap scheme** (folke's opinionated
nvim distribution). It uses:
- `<leader>b` — buffers
- `<leader>c` — code (LSP actions)
- `<leader>f` — find/files (telescope)
- `<leader>g` — git
- `<leader>l` — LSP
- `<leader>q` — quit/session
- `<leader>s` — search
- `<leader>t` — terminal (not toggles — toggles live under `<leader>u` for "UI")
- `<leader>u` — UI toggles (line numbers, wrap, diagnostics, etc.)
- `<leader>w` — windows
- `<leader>x` — diagnostics/quickfix (trouble.nvim)

**Key insight from LazyVim:** toggles live under `<leader>u` (UI), not `<leader>t` (terminal).
This is worth considering — if you ever add a terminal plugin, `<leader>t` would conflict.
Options:
1. Keep `<leader>t` for toggles and use `<leader>T` or another prefix for terminal
2. Move toggles to `<leader>u` (UI) following LazyVim convention

Recommendation: keep `<leader>t` for toggles for now (no terminal plugin yet), but note the
potential conflict and decide when adding one.

---

### 5. Learn and optimise which-key usage

**Goal:** Understand which-key well enough to use it as a live keymap reference, then configure
it so it surfaces as much useful information as possible.

#### How which-key works

- Press `<Space>` and wait 300ms — a popup appears showing all registered leader keymaps
- Press a prefix (e.g. `<Space>s`) — popup narrows to show only that group
- Works for any key sequence, not just `<leader>` — try `g`, `[`, `]`, `z` in normal mode
- Keys with a `desc` field in `vim.keymap.set` show up automatically — no extra registration needed
- `wk.add()` only needs to be called for group labels and buffer-local keymaps (which don't auto-register)

**Other useful triggers:**
- `g` — shows all `g*` motions (gd, gr, gc, etc.)
- `[` / `]` — shows all bracket jumps (diagnostics, hunks, buffers)
- `z` — shows fold commands and spell operations
- `"` / `@` — shows registers and macros

which-key intercepts any key press in normal mode and waits to see if you type more — it's not
specific to `<leader>`. Keys with built-in Neovim bindings (like `g`, `[`, `z`) will already
show up automatically. The `group = 'name'` label in `wk.add` adds a heading to that section
of the popup, making it easier to scan. Without it, the keys still appear but under a generic
`+g` header.

#### What makes a which-key setup great

1. **Every keymap has a `desc`** — which-key shows the raw key if desc is missing, which is unhelpful.
   All `vim.keymap.set` calls should have `desc = 'Group: Action'` format.

2. **Group labels for all prefixes** — without a group label, the prefix just shows as `+prefix`.
   Register every `<leader>x` prefix you use with `wk.add({ '<leader>x', group = 'Name' })`.

3. **Icons on groups** — which-key v3 supports per-group icons (Nerd Font glyphs). Makes the
   popup scannable at a glance. Add `icon = ''` to each group entry.

4. **Buffer-local keymaps registered explicitly** — LSP keymaps set with `buffer = buf` in
   `on_attach` don't appear in which-key unless registered. Fix: call `wk.add()` from inside
   `on_attach`, passing `buffer = buf`.

5. **`noremap = true` everywhere** — which-key respects this; inconsistency causes unexpected behaviour.

#### Changes needed to whichkey.lua

- Add icons to existing 4 groups
- Add group labels for all LSP/diagnostic prefixes: `<leader>r`, `<leader>c`, `<leader>d`
- Add `g` prefix group to document LSP navigation keys (`gd`, `gr`, `gi`, `gy`)
- Add `[` / `]` group for jump keys

#### Register LSP keymaps buffer-locally

In `lsp.lua` `on_attach`, after the `map()` calls:
```lua
local wk = require('which-key')
wk.add({
  { 'gd',          desc = 'LSP: Go to definition',     buffer = buf },
  { 'gD',          desc = 'LSP: Go to declaration',    buffer = buf },
  { 'gi',          desc = 'LSP: Go to implementation', buffer = buf },
  { 'gy',          desc = 'LSP: Go to type definition',buffer = buf },
  { 'gr',          desc = 'LSP: References',           buffer = buf },
  { 'K',           desc = 'LSP: Hover docs',           buffer = buf },
  { '<C-k>',       desc = 'LSP: Signature help',       buffer = buf },
  { '<leader>r',   group = 'Rename',    icon = '󰑕',    buffer = buf },
  { '<leader>c',   group = 'Code',      icon = '',    buffer = buf },
  { '<leader>d',   group = 'Diagnostics', icon = '',  buffer = buf },
})
```

This ensures `<Space>r`, `<Space>c`, `<Space>d` only appear in the popup when a LSP server
is active (buffer-local = not shown globally), which avoids noise in non-code files.

#### Final whichkey.lua target state

```lua
wk.add({
  -- Global groups (always visible)
  { '<leader>s', group = 'Search',    icon = '' },
  { '<leader>q', group = 'Session',   icon = '' },
  { '<leader>t', group = 'Toggle',    icon = '' },
  { '<leader>h', group = 'Git hunk',  icon = '' },
  { '<leader>?', desc  = 'Open cheatsheet' },

  -- Non-leader prefixes (normal mode)
  { 'g',  group = 'Go to / LSP nav' },
  { '[',  group = 'Jump prev' },
  { ']',  group = 'Jump next' },
  { 'z',  group = 'Fold / spell' },
})
```

LSP groups (`<leader>r`, `<leader>c`, `<leader>d`) registered buffer-locally from `on_attach`
so they only show when a language server is attached.

---

## Files to change
- `nvim/.config/nvim/lua/keymaps.lua` — reorganise, add sections, move session keymaps here
- `nvim/.config/nvim/lua/session.lua` — remove keymaps (keep only setup)
- `nvim/.config/nvim/lua/lsp.lua` — fix `<leader>q` conflict → `<leader>dq`
- `nvim/.config/nvim/lua/whichkey.lua` — add groups, icons, register LSP group
- `nvim/.config/nvim/cheatsheet.md` — new file

---

## Verification
1. `<Space>` + wait — which-key popup shows all groups with icons
2. `<Space>s` — shows Search subgroup with all telescope keymaps
3. `<Space>q` — shows Session subgroup only (no LSP conflict)
4. `<Space>?` — opens cheatsheet in a vertical split
5. `:checkhealth which-key` — no conflicts reported
