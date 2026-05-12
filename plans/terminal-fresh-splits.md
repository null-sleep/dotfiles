# Plan: separate `<leader>tv` / `<leader>th` from the float terminal

## Key findings (read this first)

**The core change**: stop routing every keymap through `:ToggleTerm` no-args
(which always picks id=1 and stomps its `direction` on each press). Instead:
- `<C-\>` / `<leader>tt` → `require('toggleterm').toggle(1)` (id-stable, pre-warmed float).
- `<leader>tv` / `<leader>th` → `Terminal:new({ id = next_id(), direction = ... }):open()` (fresh terminal each press).

**Decisions already made (open to revisit)**:
- *Fresh per press* over *one-dedicated-per-direction*. Means each
  `<leader>tv`/`<leader>th` press is a cold-start shell. If that becomes
  annoying, switch to fixed ids (e.g. id=2 vertical, id=3 horizontal) and
  optionally pre-warm them.
- *No pre-warm for splits*. Float (id=1) stays the only pre-warmed terminal.

**Sharp edges surfaced by critique** — the implementation has to handle these
or the change regresses something:
1. `open_mapping` installs **three** mappings (n, i, t-buffer-local). Re-binding
   only n-mode would silently drop insert-mode toggle.
2. A **global** t-mode `<C-\>` binding would eat the `<C-\><C-n>` chord in
   plain `:terminal` and lazygit. The t-mode binding must be buffer-local
   (gated on `vim.b.toggle_number`).
3. `require('toggleterm').toggle(1, nil, nil, 'float')` is **buggy**:
   `change_direction` clears `self.window` even when direction is unchanged.
   Pass no direction arg — `toggle(1)` is correct.
4. `cycle_term` (`<C-]>`) re-opens each next terminal with its own direction,
   so cycling float → split is visually jarring. Functionally fine; just a
   UX note for the user.

**Confirmed safe** (critique investigated and cleared):
- `next_id()` skips ids of window-closed-but-process-alive terminals
  (registry cleans up only on `TermClose`).
- `__add` auto-rotates ids on collision, so two same-tick `<leader>tv`
  presses don't share a Terminal instance.
- Saved-view state stays coherent: float goes through `M.toggle` (which
  saves view); splits bypass it entirely.

**If the user later wants…**
- *Toggle behavior on splits*: switch to fixed ids per direction and call
  `M.toggle(2, …, 'vertical')` / `M.toggle(3, …, 'horizontal')`.
- *A "hide all splits" escape hatch*: bind `<leader>tT` to walk
  `terminal.get_all(true)` and `:close()` each non-float entry.
- *Pre-warmed splits*: add `Terminal:new({ id = 2, direction='vertical' }):spawn()`
  and id=3 horizontal alongside the existing id=1 pre-warm.

## Context

Today all four terminal keymaps (`<C-\>`, `<leader>tt`, `<leader>th`,
`<leader>tv`) resolve to the same command (`:ToggleTerm` no-args, with an
optional `direction=` arg). They all go through toggleterm's `smart_toggle`,
which picks the lowest-id terminal — id=1, the pre-warmed float. The
direction arg mutates id=1's `direction` field on each press, so
`<leader>tv` "steals" the float into a vertical split, and a subsequent
`<C-\>` either closes that split or reopens it as a vertical split. The
float is no longer reliably the float.

The user wants:
- `<C-\>` and `<leader>tt` → consistently toggle the pre-warmed float (id=1).
- `<leader>tv` → spawn a **brand new** vertical-split terminal each press.
- `<leader>th` → spawn a **brand new** horizontal-split terminal each press.
- No mutual interference.

Fresh-per-press means each `<leader>tv` / `<leader>th` invocation pays a
cold-start shell cost (~50–200ms). Accepted.

## Critical files

- `nvim/.config/nvim/lua/terminal.lua` — the only file that changes.

## Toggleterm APIs used

- `require('toggleterm').toggle(count, size, dir, direction, name)`
  (`toggleterm.lua:314`) — when `count >= 1` dispatches to
  `toggle_nth_term`, which calls `get_or_create_term(count)` and
  `term:toggle()`. Stable, id-based, no `open_terminal_view` resurrection
  fallback.
- `require('toggleterm.terminal').Terminal:new({ id, direction })`
  (`terminal.lua:198`) — returns the existing terminal for that id, or
  constructs a new one. With `next_id()` (`terminal.lua:109`) we get a
  fresh, unused id.
- `Terminal:open(size, direction)` (`terminal.lua:487`) — opens the
  window and lazily calls `:spawn()` if the buffer is missing. `__add`
  (line 230) auto-rotates the id if a collision is detected on register,
  so two same-tick presses don't share state.

## Changes to `nvim/.config/nvim/lua/terminal.lua`

### 1. Remove `open_mapping` from `toggleterm.setup`

`open_mapping = [[<c-\>]]` is consumed by toggleterm's setup to install
**three** mappings (n-mode global, i-mode global, t-mode buffer-local on
each toggleterm buffer). We replace it with explicit bindings so we have
full control over which terminal id is targeted and which buffers are
affected.

### 2. Bind the float toggle in `n` and `i` modes (global) and `t` mode
(buffer-local, toggleterm-only)

```lua
local function toggle_float()
  -- Pass nil for direction: change_direction() clears self.window
  -- unconditionally even if the direction is unchanged. Letting the term
  -- object keep its existing direction='float' avoids that churn.
  require('toggleterm').toggle(1)
end

-- n + i mode are global; <C-\> in a non-toggleterm terminal buffer (sidekick,
-- lazygit, plain :terminal) would otherwise eat the <C-\><C-n> chord, so the
-- t-mode binding lives in the existing TermOpen autocmd, gated on
-- vim.b.toggle_number ~= nil (set only on toggleterm buffers).
vim.keymap.set({ 'n', 'i' }, '<C-\\>', toggle_float, { desc = 'Toggle: Terminal (float, id=1)' })
vim.keymap.set('n', '<leader>tt', toggle_float, { desc = 'Toggle: Terminal (float, id=1)' })
```

In the existing TermOpen autocmd (currently lines 61–76), add inside the
non-sidekick branch:

```lua
if vim.b.toggle_number then
  vim.keymap.set('t', '<C-\\>', toggle_float, { buffer = 0 })
end
```

This preserves `<C-\><C-n>` (exit terminal mode) in plain `:terminal` /
lazygit / any non-toggleterm terminal buffer — only toggleterm buffers map
`<C-\>` to "close this float."

### 3. Replace `<leader>tv` / `<leader>th` with fresh-spawn callbacks

```lua
local function open_fresh(direction)
  local terms = require('toggleterm.terminal')
  terms.Terminal:new({
    id = terms.next_id(),
    direction = direction,
  }):open()
end
vim.keymap.set('n', '<leader>th', function() open_fresh('horizontal') end,
  { desc = 'Open: New terminal (horizontal split)' })
vim.keymap.set('n', '<leader>tv', function() open_fresh('vertical') end,
  { desc = 'Open: New terminal (vertical split)' })
```

`next_id()` walks `get_all(true)` and returns the first gap or `count+1`.
Terminals only leave the registry when their **process** exits (via
`TermClose` autocmd in toggleterm) — closing a window does not. So a
window-closed-but-process-alive terminal still occupies its id and
`next_id()` skips past it. After a shell `:exit`, that id frees up and the
next `<leader>tv` may reuse it (semantically fine; only the cycle ordering
shifts).

### 4. Pre-warm stays unchanged

`Terminal:new({ id = 1 }):spawn()` already targets id=1, which the new
float keymap toggles.

### 5. `cycle_term` (`<C-]>`) keeps working unmodified

It walks `get_all(true)` sorted by id and toggles between terminals. With
fresh-per-press the cycle list grows over the session.

## Side-effects / things to watch

- The user can accumulate many terminals over a session. Only
  `close_on_exit = true` (already set) cleans them up, when the shell
  process exits. Stale window-closed-but-process-alive terminals are
  reachable via `<C-]>`.
- `<leader>th` / `<leader>tv` no longer "toggle" — they only open. The
  `desc` field reflects this (`Open: ...`) so which-key users see the
  difference. To hide a split, use normal window commands (`<C-w>q`,
  `<Esc>:q`).
- `cycle_term` calls `:close()` on the current then `:open()` on the
  next. When cycling float → split → split, the window destroys and
  re-opens with each terminal's own direction. This is visually jarring
  but functionally correct; not a regression.
- The pre-warmed id=1 is the float; the first split press is always a
  cold start. The user explicitly chose fresh-per-press over
  dedicated-per-direction, so we don't pre-warm splits.

## Verification

1. Open Neovim in a git repo.
2. `<C-\>` → float opens with the pre-warmed shell (no cold start).
3. `<C-\>` again → float hides.
4. `<leader>tv` → new vertical split with a fresh shell (id=2, visible
   ~50–200ms cold start).
5. `<leader>tv` again → second vertical split (id=3); id=2 stays put.
6. `<leader>th` → horizontal split (id=4).
7. `<C-\>` → float toggles independently of all splits; reopens the same
   pre-warmed shell as in step 2.
8. `<C-]>` inside any terminal → cycles through all terminals in id order.
9. Plain `:terminal` (or lazygit), then `<C-\><C-n>` → exits terminal
   mode normally. `<C-\>` alone in such a buffer is **not** captured by
   the new mapping (verifies the buffer-local gate).
10. `:exit` in a split → that terminal's buffer is deleted, its id frees
    for reuse by the next `<leader>tv` / `<leader>th`.
