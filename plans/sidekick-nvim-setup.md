# Plan: Configure folke/sidekick.nvim with NES (Copilot) + Claude CLI

## Context

Add `folke/sidekick.nvim` to this Neovim config to get two things:

1. **NES (Next Edit Suggestion)** powered by Copilot LSP — multi-line refactor suggestions surfaced via diff overlays, applied with `<Tab>`. Requires the Copilot language server, which isn't currently installed. (See also `next-edit-suggestion.md` for prior research on this feature.)
2. **AI chat in Neovim**, with **Claude** as the primary CLI integration plus the standard send-context keymaps.

Prior attempt at AI integration (`nvim-ai-integration.md`) used codecompanion.nvim with the ACP adapter and was rolled back due to flaky ACP init in some repos. Sidekick takes a different approach: a raw terminal split for the CLI (no JSON-RPC adapter), plus a separate LSP-driven NES feature. Different surface area, different failure modes.

The config uses `vim.pack` (Neovim 0.12+ native), not `lazy.nvim`, so the README's lazy spec needs translating: plugin spec lives in `plugins.lua`, plugin setup in a dedicated `lua/sidekick.lua`, keymaps in `lua/keymaps.lua`, group label in `lua/whichkey.lua`. Telescope stays as the daily-driver picker; we add a custom Telescope action to replicate the README's Snacks-only `<a-a>` send-from-picker workflow without installing Snacks.

## Locked-in decisions

- **Copilot LSP**: install via Mason (`copilot-language-server`) and configure with `vim.lsp.config('copilot', ...)`. Matches the existing pattern in `lsp.lua`.
- **Snacks.nvim**: not installed. Sidekick's `cli.picker = "telescope"`. The `<a-a>` send-to-CLI feature is replicated as a custom Telescope action — works in **all** Telescope pickers including the custom ones in `lua/pickers/*` and the LSP `grr`/`gri` pickers.
- **PR #277 (alvarosevilla95/sidekick.nvim, branch `fix/nes-missing-request-id`)**: pin `vim.pack` `src` to the fork until upstream merges. TODO marker in `plugins.lua` to flip back to `folke/sidekick.nvim` after merge. Without this fix, NES silently filters all suggestions as "stale".
- **AI prefix `<leader>a`**: matches the prefix the previous AI plan used. No collision with current keymaps (`<leader>ca` is LSP code action, in a different group).

## Files to modify

| File | Change |
|---|---|
| `nvim/.config/nvim/lua/plugins.lua` | Add sidekick to `vim.pack.add()` (pinned to PR fork); add `<a-a>` Telescope action in `defaults.mappings` |
| `nvim/.config/nvim/lua/lsp.lua` | Add `copilot` to `mason-lspconfig` `ensure_installed`; add `vim.lsp.config('copilot', {...})`; add `'copilot'` to `vim.lsp.enable({...})` |
| `nvim/.config/nvim/lua/sidekick.lua` | **New file** — packadd + `require('sidekick').setup({...})` |
| `nvim/.config/nvim/lua/keymaps.lua` | Add `<Tab>` (NES jump/apply), `<C-.>` (focus CLI), and the `<leader>a*` group |
| `nvim/.config/nvim/lua/whichkey.lua` | Register `<leader>a` group as "AI" |
| `nvim/.config/nvim/init.lua` | `require('sidekick')` after `require('lsp')` |

## Step-by-step

### 1. Add sidekick plugin spec — `lua/plugins.lua`

In the `vim.pack.add({...})` list (around line 39 after `toggleterm`), insert:

```lua
-- AI: NES (Copilot LSP) + Claude/Copilot CLI integration.
-- TODO: flip src back to 'folke/sidekick.nvim' once PR #277 merges
-- (https://github.com/folke/sidekick.nvim/pull/277).
{
  src = 'https://github.com/alvarosevilla95/sidekick.nvim',
  version = 'fix/nes-missing-request-id',
},
```

`gh()` from `utils.lua` only handles `folke/...`-style shorthand, so we use the full URL here.

### 2. Add `<a-a>` send-to-sidekick Telescope action — `lua/plugins.lua`

In the Telescope `defaults.mappings` block (around line 219, alongside the existing `<CR>` `select_and_scroll`), extend it with an `<M-a>` action. Keep the existing `<CR>` behavior. The action handles both single-entry and multi-selection (`<Tab>`-marked) cases:

```lua
mappings = (function()
  local CURSOR_TOP_RATIO = 0.20
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local function select_and_scroll(prompt_bufnr)
    actions.select_default(prompt_bufnr)
    local offset = math.floor(vim.api.nvim_win_get_height(0) * CURSOR_TOP_RATIO)
    vim.fn.winrestview({ topline = math.max(1, vim.fn.line('.') - offset) })
  end

  -- Send the picker's current entry (or multi-selection) to the active sidekick CLI
  -- session as space-separated path:line refs. Replicates the snacks-only <a-a>
  -- integration from the sidekick README so we keep telescope as the primary picker.
  local function send_to_sidekick(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    local picks = picker:get_multi_selection()
    if vim.tbl_isempty(picks) then
      picks = { action_state.get_selected_entry() }
    end
    local refs = {}
    for _, e in ipairs(picks) do
      if e then
        local path = e.path or e.filename or e.value
        if path then
          table.insert(refs, e.lnum and (path .. ':' .. e.lnum) or path)
        end
      end
    end
    actions.close(prompt_bufnr)
    if not vim.tbl_isempty(refs) then
      require('sidekick.cli').send({ msg = table.concat(refs, ' ') })
    end
  end

  return {
    i = { ['<CR>'] = select_and_scroll, ['<M-a>'] = send_to_sidekick },
    n = { ['<CR>'] = select_and_scroll, ['<M-a>'] = send_to_sidekick },
  }
end)(),
```

### 3. Add Copilot LSP — `lua/lsp.lua`

- Append `'copilot'` to the `ensure_installed` table (line 25–32). `mason-lspconfig` resolves this to the `copilot-language-server` Mason package.
- Add a `vim.lsp.config('copilot', {})` block (around line 165, alongside the other server configs). The default lspconfig entry from `nvim-lspconfig`'s `lsp/copilot.lua` is sufficient — no settings overrides needed.
- Append `'copilot'` to the `vim.lsp.enable({...})` list on line 168.
- First-run auth: user runs `:LspCopilotSignIn` once after Mason installs the server.

### 4. Create sidekick setup — `lua/sidekick.lua` (new file)

```lua
vim.cmd.packadd('sidekick.nvim')

require('sidekick').setup({
  cli = {
    -- Use telescope for cli.select() (tool list) and cli.prompt() (prompt library)
    -- so the sidekick UI matches the rest of the config.
    picker = 'telescope',
    win = {
      layout = 'right',  -- CLI opens as a right split; switch to 'float' if preferred
    },
    -- mux: leave disabled. Enable with backend = 'tmux' or 'zellij' if you want
    -- sessions to persist across nvim restarts.
  },
  nes = {
    -- defaults are good: enabled = true, debounce = 100, diff.inline = 'words'
  },
})
```

### 5. Add keymaps — `lua/keymaps.lua`

Append a new section at the end (after the yank helpers):

```lua
-- AI (sidekick.nvim): NES + Claude/Copilot CLI
-- <Tab> in normal mode jumps to or applies the next NES suggestion; falls
-- through to a literal <Tab> when none is active. blink.cmp's <Tab> is insert-
-- mode only, so there's no conflict.
vim.keymap.set('n', '<Tab>', function()
  if not require('sidekick').nes_jump_or_apply() then
    return '<Tab>'
  end
end, { expr = true, desc = 'AI: NES jump or apply' })

vim.keymap.set({ 'n', 't', 'i', 'x' }, '<C-.>',
  function() require('sidekick.cli').focus() end, { desc = 'AI: Focus CLI' })

vim.keymap.set('n', '<leader>aa',
  function() require('sidekick.cli').toggle() end, { desc = 'AI: Toggle CLI' })
vim.keymap.set('n', '<leader>ac',
  function() require('sidekick.cli').toggle({ name = 'claude', focus = true }) end,
  { desc = 'AI: Toggle Claude' })
vim.keymap.set('n', '<leader>as',
  function() require('sidekick.cli').select() end, { desc = 'AI: Select CLI tool' })
vim.keymap.set('n', '<leader>ad',
  function() require('sidekick.cli').close() end, { desc = 'AI: Detach session' })
vim.keymap.set('n', '<leader>ap',
  function() require('sidekick.cli').prompt() end, { desc = 'AI: Select prompt' })
vim.keymap.set({ 'n', 'x' }, '<leader>at',
  function() require('sidekick.cli').send({ msg = '{this}' }) end,
  { desc = 'AI: Send this (selection or file)' })
vim.keymap.set('n', '<leader>af',
  function() require('sidekick.cli').send({ msg = '{file}' }) end,
  { desc = 'AI: Send file' })
vim.keymap.set('x', '<leader>av',
  function() require('sidekick.cli').send({ msg = '{selection}' }) end,
  { desc = 'AI: Send visual selection' })
```

### 6. Register which-key group — `lua/whichkey.lua`

Add to the `wk.add({...})` call (around line 25):

```lua
{ '<leader>a',  group = 'AI' },
```

### 7. Wire into init.lua — `nvim/.config/nvim/init.lua`

Insert `require('sidekick')` after `require('lsp')` (between lines 6 and 7):

```lua
require('lsp')
require('sidekick')
require('format')
```

### 8. Snacks.nvim Picker Integration — explicitly skipped

We are **not** installing Snacks. The README's `<a-a>` "send picker selection to CLI" feature is replicated against Telescope in step 2 and works across:

- All built-in pickers used in `keymaps.lua`: `<leader>sf`, `<leader>sg`, `<leader>sh`, `<leader>sr`, `<leader>s/`, `<leader>so`, `<leader>sk`.
- All custom pickers in `lua/pickers/` (`filter.lua`, `gitstatus.lua`, `symbols.lua`, `theme.lua`, `buffer.lua`, `keybindings.lua`).
- The LSP pickers in `lsp.lua` (`grr`, `gri`).

Multi-select via `<Tab>` works automatically — `get_multi_selection()` returns marked entries; falls back to the cursor entry when none are marked. Sidekick receives them as space-separated `path:line` refs.

If we ever migrate to Snacks pickers, this action stays useful as a Telescope-side fallback during the transition.

## Verification

1. **Fresh install resolves:** Restart Neovim. Confirm `:lua print(vim.inspect(vim.pack.get({'sidekick.nvim'})))` shows the plugin as `active = true` and no orphan warning fires.
2. **Mason picks up Copilot:** `:Mason` — confirm `copilot-language-server` is installed (or installing). After it lands, `:LspInfo` in any buffer should list `copilot` as a running client.
3. **Copilot auth:** Run `:LspCopilotSignIn` once and complete the device-code flow in a browser. `:checkhealth vim.lsp` should show `copilot` as authenticated.
4. **NES end-to-end:** Open a real source file, make an edit that has obvious follow-on edits (e.g., rename a variable in one place), leave insert mode. A diff overlay should appear; press `<Tab>` to jump/apply. Confirm `:Sidekick nes toggle` disables/enables.
5. **Claude CLI toggles:** With `claude` CLI installed, `<leader>ac` opens it in a right split. `<leader>at` from a visual selection sends the highlighted text. `<C-.>` focuses back.
6. **`<a-a>` send-from-picker:** Run `<leader>sg`, search for a string, mark a few hits with `<Tab>`, press `<M-a>`. Picker closes; the active CLI session receives `path:line path:line ...`. Repeat with `<leader>sf` and `grr` to confirm coverage.
7. **Which-key group:** Press `<leader>a` and confirm the popup shows "AI" as the group label with all `<leader>a*` mappings listed.
8. **No regressions:** `<leader>sf`/`<leader>sg`/`grr` still scroll-on-select (the existing `<CR>` mapping is preserved); `<Tab>` in insert mode still navigates blink.cmp completions.

## Follow-ups (not in this plan)

- After PR #277 merges upstream, change the `vim.pack` spec back to `src = gh('folke/sidekick.nvim')` and remove the TODO comment.
- If session persistence across nvim restarts becomes desirable, enable `cli.mux = { backend = 'tmux'|'zellij', enabled = true }` in `lua/sidekick.lua`.
