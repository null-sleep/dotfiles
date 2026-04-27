# Buffer Quick-Pick: Options & Comparison

## Problem

The current Telescope buffer picker (`<leader>sb` → `builtin.buffers`) requires
fuzzy-typing or `j`/`k` + `<CR>` to pick a buffer. Want a faster path: ideally
hit a single number/letter to jump to a buffer.

Telescope itself doesn't natively support "press N to pick row N" because
typing into the prompt consumes keystrokes.

## Options (ordered by effort)

### 1. Use vim's built-in buffer numbers
Telescope's buffer picker already shows the `bufnr` in the left column. Skip
the picker entirely:
- `:b 5<CR>` jumps to buffer 5
- `5<C-^>` also works

No config needed. Downside: vim's bufnrs are not stable/sequential.

### 2. Map `<M-1>`..`<M-9>` inside the picker
Add `attach_mappings` on `builtin.buffers` so meta+digit selects row N.
Still requires opening the picker first, then pressing `<M-3>`.

### 3. `bufferline.nvim` pick mode
Each visible buffer in the bufferline gets a letter overlay (easymotion-style).
Press the letter to jump. Closest to "no menu, mash a key, done" without
switching buffer-management paradigm.

### 4. Dedicated plugin: `buffer_manager.nvim` or `harpoon`
See comparison below.

---

## buffer_manager.nvim vs harpoon

### buffer_manager.nvim

**Mental model:** "a better `:ls`" — shows actual open buffers in a floating
window, ordered by buffer number.

**Experience:**
- Press shortcut → floating window with all open buffers, one per line,
  numbered `1`, `2`, `3`...
- Press `1` (or `2`, `3`...) → jumps to that buffer instantly. No `<CR>`.
- Or use `j`/`k` + `<CR>` to navigate.
- **Reorder** buffers by editing the buffer-list buffer like text (`dd` to
  close, move lines around to reorder).
- Numbers are positional in the list, not vim's `bufnr` — stay small and
  stable-ish.
- Closing buffers: `dd` on a line, then `:w` to apply.

**Feel:** lightweight, minimal, basically a hotkey-driven `:ls`. Never curate
anything — every buffer you've opened shows up.

### harpoon (v2)

**Mental model:** "bookmarks for files I'm actively working on" — explicitly
*mark* files; unmarked buffers are invisible to harpoon.

**Experience:**
- Working on `auth.go`? Press `<leader>a` → harpoon slot 1.
- Open `user.go`, `<leader>a` → slot 2. Then `db.go` → slot 3.
- Now `<M-1>` jumps to auth, `<M-2>` to user, `<M-3>` to db — **from
  anywhere, no menu**.
- Press `<leader>h` → tiny floating list of marked files. Edit it like text to
  reorder/remove.
- Buffers opened but not marked (random files grepped into, etc.) don't
  pollute the list.
- Slots are *persistent per project* — close nvim, reopen, harpoon remembers.

**Feel:** opinionated, project-scoped, optimized for the 3–5 files actively
bouncing between. "Mash a number, teleport" is the whole point.

---

## Recommendation

- **"Show me everything I have open, let me pick by number"** →
  `buffer_manager.nvim`. Closest to current `<leader>sb` flow, just faster.
- **"3 files I'm ping-ponging between, get me there in one keystroke with no
  menu"** → `harpoon`. Menu is the fallback, not the primary path.

Many people run both: harpoon for the hot 3–5, buffer_manager (or telescope
buffers) for everything else.

## Open questions / next steps

- Decide: pick one plugin, run both, or just add `<M-1>..<M-9>` mappings to
  the existing telescope buffer picker?
- If harpoon: pick keymaps for add/menu/jump that don't conflict with current
  `<leader>` setup (see `nvim/.config/nvim/lua/keymaps.lua`).
- If buffer_manager: decide whether to keep `<leader>sb` for telescope and
  bind the manager to a different key, or replace.
