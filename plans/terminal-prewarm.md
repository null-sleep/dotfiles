# Plan: Pre-warm terminals on startup

## Problem

The first `<leader>aa` (Claude CLI) and `<C-\>` / `<leader>tt` (toggleterm) freeze the editor for 1-2 seconds while the process spawns. Subsequent toggles are instant because the process stays alive — only the cold start hurts.

## Goal

Spawn both terminals in the background during startup so the first keypress is a fast show/hide toggle instead of a cold start.

## Investigation

### Sidekick (Claude CLI)

Sidekick's `terminal:start()` always calls `open_win()` — window creation and process spawning are coupled. There is no "spawn in background" API. The approach is:

1. Call `cli.show({ name = 'claude', focus = false })` to spawn the terminal
2. Poll for the sidekick terminal window to appear (`vim.b[buf].sidekick_cli`)
3. Call `cli.hide()` once detected

This causes a brief visual flicker (~1-2s) as the right split appears then hides.

**Gate on git repo:** Only pre-warm in git repos (`vim.fn.finddir('.git', '.;') ~= ''`) since Claude CLI is only useful in project contexts.

### Toggleterm

Toggleterm has `Terminal:spawn()` which creates the buffer and starts the shell process without opening a window. Clean background spawn, no flicker.

### Mouse-hover info (not viable)

Investigated whether hover info could trigger on mouse position (VS Code-style) instead of cursor position. Not possible in terminal Neovim or Neovide — Neovim has no `MouseMove` autocmd event. Even a mouse-click trigger would require neovim/neovim#9152. This applies to both hover and click — Neovim only sees mouse events for clicks/scrolls, not position. Revisit when/if that feature lands.

## Changes

### `nvim/.config/nvim/lua/ai.lua`

Add after the `FileType` autocmd block (line 33):

```lua
-- Pre-warm Claude CLI in git repos: spawn the sidekick terminal on startup
-- so the first <leader>aa is instant (toggle) instead of a cold start.
-- Sidekick's start() always creates a visible split, so we poll until the
-- window appears and then hide it. The split flickers briefly (~1-2s).
if vim.fn.finddir('.git', '.;') ~= '' then
  vim.defer_fn(function()
    local cli = require('sidekick.cli')
    cli.show({ name = 'claude', focus = false })
    -- Poll until sidekick creates the terminal window, then hide it.
    local timer = assert(vim.uv.new_timer())
    local attempts = 0
    timer:start(200, 200, vim.schedule_wrap(function()
      attempts = attempts + 1
      -- Look for a sidekick terminal window to confirm it's up.
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.b[buf].sidekick_cli then
          cli.hide({ name = 'claude' })
          timer:stop()
          timer:close()
          return
        end
      end
      -- Give up after 5s (25 attempts x 200ms) -- CLI may have failed to start.
      if attempts >= 25 then
        timer:stop()
        timer:close()
      end
    end))
  end, 100)
end
```

### `nvim/.config/nvim/lua/terminal.lua`

Add after the `<leader>tt` keymap (line 74):

```lua
-- Pre-warm: spawn the default shell in the background so the first
-- <leader>tt / <C-\> is instant (no shell startup delay).
vim.defer_fn(function()
  local Terminal = require('toggleterm.terminal').Terminal
  local term = Terminal:new({ id = 1 })
  term:spawn()
end, 100)
```

## Tradeoffs

- **Sidekick flicker:** The right split appears for ~1-2s on startup then hides. No clean workaround without upstream API changes (a `spawn_hidden()` or decoupled `start()`).
- **Startup cost:** Both terminals spawn 100ms after init. Shell startup is fast (~50ms). Claude CLI takes longer but runs async — the editor is not blocked.
- **Memory:** Two extra processes (shell + Claude CLI) running from startup. Negligible on modern machines.

## Verification

1. Open Neovim in a git repo. Observe the sidekick split flash briefly then disappear.
2. Press `<leader>aa` — Claude CLI should appear instantly (no freeze).
3. Press `<C-\>` — toggleterm float should appear instantly.
4. Open Neovim outside a git repo. Confirm sidekick does not pre-warm (no flash).
5. Confirm toggleterm still pre-warms outside git repos.
