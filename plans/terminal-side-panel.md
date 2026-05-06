# Plan: Terminal side-panel via sidekick (`<leader>a;`)

## Context

`<leader>aa` opens the Claude CLI as a right-side split via `sidekick.cli.toggle({ name = 'claude', focus = true })`. The user wants the same side-panel behaviour for a plain shell terminal. Sidekick supports arbitrary CLI tools in its `tools` config table — adding a `shell` entry reuses the same right-split infrastructure without needing a separate plugin or custom terminal management.

The existing `<C-\>` / `<leader>tt` toggleterm setup opens a **floating** window and is unrelated — it stays untouched.

## Approach

Two file changes. No new files.

1. Register a `shell` tool in sidekick's `tools` config (`ai.lua`)
2. Bind `<leader>a;` to toggle it (`keymaps.lua`)
3. Optionally add a whichkey keyword for discoverability (`whichkey.lua`)

## Changes

### `nvim/.config/nvim/lua/ai.lua`

Add a `tools` table inside the `cli` config block (after `win`):

```lua
require('sidekick').setup({
  cli = {
    picker = 'telescope',
    win = {
      layout = 'right',
    },
    tools = {
      shell = { cmd = { vim.o.shell } },
    },
  },
  nes = {},
})
```

Notes:
- `cmd` must be `string[]` per `sidekick.cli.Config` — `{ vim.o.shell }` evaluates to `{ "/bin/zsh" }` at load time (safe: `vim.o.shell` is always set before plugins load).
- No `is_proc` — avoids matching every shell process on the system in the tool selector.
- No other fields needed; defaults handle env, scrollback, and focus correctly.

### `nvim/.config/nvim/lua/keymaps.lua`

Add after the `<leader>aa` binding (around line 140):

```lua
vim.keymap.set('n', '<leader>a;',
  function() require('sidekick.cli').toggle({ name = 'shell', focus = true }) end,
  { desc = 'AI: Toggle shell panel' })
```

### `nvim/.config/nvim/lua/whichkey.lua` (optional)

Add a keyword entry so the binding surfaces in the keybinding search picker:

```lua
['<leader>a;'] = 'shell terminal side panel sidekick',
```

## What does NOT need to change

- **`ai.lua` FileType autocmd (lines 27–33):** The `sidekick_terminal` pattern covers all sidekick terminals. The shell tool's buffer gets the `jj` exit binding automatically.
- **`terminal.lua`:** The `TermOpen` autocmd already skips `sidekick_terminal` buffers — no conflict with toggleterm keymaps.

## Behaviour notes

- **Two panels can coexist.** If Claude is open and you press `<leader>a;`, a second right split opens for the shell. This is sidekick's intended multi-tool design. Use `<leader>as` (select tool) to switch, or `<leader>ad` to kill the focused session.
- **`<leader>a;` is a toggle** — press once to open, again to hide. The shell session persists in the background until killed with `<leader>ad`.
- **`<C-.>` / `<leader>ai` (focus CLI)** focuses whichever sidekick terminal was most recently active.

## Verification

1. Open Neovim. Press `<leader>a;` — a right split should open running `$SHELL`.
2. Type `jj` — should exit to normal mode (confirming the `sidekick_terminal` autocmd applies).
3. Press `<leader>a;` again — panel hides. Shell session stays alive.
4. Press `<leader>a;` once more — panel reappears with the shell session intact.
5. Press `<leader>aa` — Claude opens as a second right split alongside the shell.
6. Press `<leader>as` — tool selector should list both "claude" and "shell".
7. Press `<leader>ad` while focused on the shell panel — kills the shell session and closes the panel.
