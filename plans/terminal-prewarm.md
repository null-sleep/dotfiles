# Plan: Pre-warm terminals on startup

## Problem

The first `<leader>aa` (Claude CLI) and `<C-\>` / `<leader>tt` (toggleterm)
freeze the editor for 1-2 seconds while the process spawns. Subsequent toggles
are instant because the process stays alive — only the cold start hurts.

## Goal

Spawn both terminals in the background during startup so the first keypress is
a fast show/hide toggle instead of a cold start, and do it without a visible
flicker on every nvim launch.

## Investigation

### Sidekick (Claude CLI)

Sidekick's `Terminal:start()` calls `Terminal:open_win()` synchronously, and
`open_win()` always creates a real visible window. There is no documented
"spawn in background" API. Two viable workarounds:

1. **Visible flicker**: call `cli.show()`, poll until the window appears,
   then call `cli.hide()`. Right split flashes for ~1–2s on every launch.
2. **Hidden float (chosen)**: replace the terminal instance's `open_win`
   method with one that creates a *hidden* floating window (`hide = true`,
   supported on Neovim 0.10+). `jobstart{ term = true }` only requires that
   the buffer be shown in *some* current window — visibility is irrelevant,
   so the claude job runs against a hidden float. After it's spawned we
   close the float (sidekick's `cli.hide` keeps the job alive) and clear
   the per-instance override so subsequent toggles use the normal split path.

Sidekick exposes a per-instance `win.config(terminal)` callback that runs
inside `Terminal:init()` before `:start()` is called — that's the natural
hook for swapping in the override. The callback is gated by a global flag
(`_G.__sidekick_prewarm`) because `cli.show` defers its work through
`vim.schedule_wrap` twice, so the override needs to survive the async gap.

**Gate on git repo:** Only pre-warm in git repos (`vim.fn.finddir('.git', '.;') ~= ''`)
since Claude CLI is only useful in project contexts.

### Toggleterm

Toggleterm has `Terminal:spawn()` which creates the buffer and starts the shell
process without opening a window. Clean background spawn, no flicker.

### Mouse-hover info (not viable)

Investigated whether hover info could trigger on mouse position (VS Code-style)
instead of cursor position. Not possible in terminal Neovim or Neovide —
Neovim has no `MouseMove` autocmd event. Even a mouse-click trigger would
require neovim/neovim#9152. This applies to both hover and click — Neovim only
sees mouse events for clicks/scrolls, not position. Revisit when/if that
feature lands.

## Changes

### `nvim/.config/nvim/lua/ai.lua` (implemented)

Two pieces, both inside this file:

**1. `win.config` callback** inside `require('sidekick').setup({ ... })`.
While `_G.__sidekick_prewarm` is set, swap the terminal's `open_win` method
for one that creates a hidden float sized to roughly match the eventual
right split (width=80, height=vim.o.lines). Stash the terminal instance in
a file-local `prewarm_term` so cleanup can find it without walking sidekick's
internals.

**2. Pre-warm trigger** at the bottom of the file, gated on `finddir('.git')`.
Set the flag, call `cli.show({ name = 'claude', focus = false })`, then 300ms
later clear the flag, restore `prewarm_term.open_win = nil`, and call
`cli.hide()` to close the invisible float. The job stays alive; subsequent
`<leader>aa` goes through sidekick's normal path and creates a real split.

The 300ms budget covers `State.with`'s scheduled callback chain dispatching
through `init() → start() → open_win()`. Polling for `prewarm_term` would be
tighter but isn't worth the complexity at this latency.

The full implementation (with rationale comments) lives in `ai.lua`.

### `nvim/.config/nvim/lua/terminal.lua` (implemented)

Toggleterm's `Terminal:spawn()` creates the buffer and runs `termopen` without
opening any window — clean background spawn, no flicker, no monkey-patch.
Spawning id=1 (the lowest-id terminal) means `:ToggleTerm` with no args (which
`<C-\>` is bound to) attaches to it on first press.

## Tradeoffs

- **No more sidekick flicker.** The hidden-float trick eliminates the
  visible right-split-then-hide animation that the simpler approach caused.
- **Couples to sidekick internals.** We rely on `term.open_win` being a
  method on the instance and `term.opts.float` flowing through to
  `nvim_open_win`. If sidekick refactors how it constructs windows, this
  needs to be revisited. The pcall/nil-check guards mean the worst case is
  reverting to a visible-split flicker, never a broken editor.
- **Startup cost:** Both terminals spawn 100ms after init. Shell startup is
  fast (~50ms). Claude CLI takes longer but runs async — the editor is not
  blocked.
- **First-show reflow:** claude renders into the hidden float's geometry
  (80 cols), then receives SIGWINCH when the real split opens. The hidden
  float is sized close to the real split to minimize visible artifacts on
  first show.
- **Memory:** Two extra processes (shell + Claude CLI) running from
  startup. Negligible on modern machines.

## Verification

1. Open Neovim in a git repo. Confirm **no visible flicker** on startup.
2. Press `<leader>aa` — Claude CLI right split should appear instantly with
   the prompt already responsive (no cold-start freeze).
3. Press `<leader>aa` again — split hides instantly. Press once more — re-shows
   instantly. Job is the same process throughout.
4. Open Neovim outside a git repo. Confirm sidekick does not pre-warm (no
   process spawned, `<leader>aa` falls back to cold-start behavior).
5. With claude binary missing/renamed: confirm nvim still starts cleanly and
   `<leader>aa` surfaces sidekick's normal "not installed" error rather than
   a broken state from leaked overrides.
6. (After toggleterm pre-warm is added): `<C-\>` should show the float
   instantly.
