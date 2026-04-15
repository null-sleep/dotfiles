# Plan: Install gitsigns.nvim and conform.nvim

## Context
Adding two quality-of-life plugins to complete the editor setup:
- **gitsigns.nvim**: in-buffer git decorations (hunk highlights, blame) + hunk-level staging/navigation
- **conform.nvim**: format-on-save with per-filetype formatters, falling back to LSP formatting

Both follow the established pattern: register in `plugins.lua` via `vim.pack.add`, then `packadd` + setup in dedicated module files loaded from `init.lua`.

## Files to change
- `lua/plugins.lua` — add 2 entries to `vim.pack.add`
- `init.lua` — append `require('git')` and `require('formatting')`
- `lua/git.lua` — new file, gitsigns setup + keymaps
- `lua/formatting.lua` — new file, conform setup + format-on-save autocmd

---

## Step 1 — plugins.lua: add gitsigns and conform

Add inside the existing `vim.pack.add({...})` table:

```lua
{ src = gh('lewis6991/gitsigns.nvim') },
{ src = gh('stevearc/conform.nvim') },
```

No build hooks needed — neither plugin requires compilation.

---

## Step 2 — init.lua: append two requires

```lua
require('configs')
require('plugins')
require('keymaps')
require('completion')
require('lsp')
require('git')
require('formatting')
```

---

## Step 3 — create lua/git.lua

```lua
vim.cmd.packadd('gitsigns.nvim')

require('gitsigns').setup({
  signs = {
    add          = { text = '┃' },
    change       = { text = '┃' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
    untracked    = { text = '┆' },
  },
  on_attach = function(buf)
    local gs = package.loaded.gitsigns
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    -- Hunk navigation
    map('n', ']c', function()
      if vim.wo.diff then vim.cmd.normal({ ']c', bang = true })
      else gs.next_hunk() end
    end, 'Git: Next hunk')

    map('n', '[c', function()
      if vim.wo.diff then vim.cmd.normal({ '[c', bang = true })
      else gs.prev_hunk() end
    end, 'Git: Previous hunk')

    -- Hunk actions
    map({'n','v'}, '<leader>hs', gs.stage_hunk,        'Git: Stage hunk')
    map({'n','v'}, '<leader>hr', gs.reset_hunk,        'Git: Reset hunk')
    map('n',       '<leader>hS', gs.stage_buffer,      'Git: Stage buffer')
    map('n',       '<leader>hR', gs.reset_buffer,      'Git: Reset buffer')
    map('n',       '<leader>hu', gs.undo_stage_hunk,   'Git: Undo stage hunk')
    map('n',       '<leader>hp', gs.preview_hunk,      'Git: Preview hunk')
    map('n',       '<leader>hb', function() gs.blame_line({ full = true }) end, 'Git: Blame line')
    map('n',       '<leader>hd', gs.diffthis,          'Git: Diff this')

    -- Toggles
    map('n', '<leader>tb', gs.toggle_current_line_blame, 'Git: Toggle line blame')
    map('n', '<leader>td', gs.toggle_deleted,            'Git: Toggle deleted')

    -- Text object
    map({'o','x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>', 'Git: Select hunk')
  end,
})
```

Key decisions:
- `on_attach` callback pattern — same as lsp.lua's `on_attach`, keeps keymaps buffer-local
- `]c`/`[c` with `vim.wo.diff` guard — works correctly in both diff mode and normal buffers
- `<leader>h` prefix for hunk operations, `<leader>t` for toggles — mnemonic and consistent with LSP keymaps
- `ih` text object — lets you operate on a hunk with `vih`, `dih`, `cih`

---

## Step 4 — create lua/formatting.lua

```lua
vim.cmd.packadd('conform.nvim')

require('conform').setup({
  formatters_by_ft = {
    lua        = { 'stylua' },
    python     = { 'isort', 'black' },
    javascript = { 'prettier' },
    typescript = { 'prettier' },
    go         = { 'goimports', 'gofmt' },
    rust       = { 'rustfmt' },
    json       = { 'prettier' },
    yaml       = { 'prettier' },
    markdown   = { 'prettier' },
  },

  format_on_save = {
    timeout_ms = 500,
    lsp_format = 'fallback',  -- use LSP if no formatter configured for the ft
  },
})

-- Manual format keymap
vim.keymap.set({'n','v'}, '<leader>f', function()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end, { desc = 'Format: Format buffer' })
```

Key decisions:
- `lsp_format = 'fallback'` — uses LSP formatting when no conform formatter is configured for a filetype (e.g. rust_analyzer can format Rust even without rustfmt installed)
- `timeout_ms = 500` — prevents save from hanging if a formatter is slow
- `isort` before `black` — isort sorts imports first, black reformats everything
- `goimports` before `gofmt` — goimports adds missing imports, gofmt normalises formatting
- Manual `<leader>f` — async format on demand without triggering save

---

## Step 5 — install formatters via Mason

After restarting nvim, run:
```
:MasonInstall stylua black isort prettier goimports
```

`rustfmt` and `gofmt` come with the Rust and Go toolchains respectively — Mason doesn't manage them.

### Adding a new formatter later

conform does **not** auto-discover formatters. When you install a new formatter via Mason (or any other method), you must also add it to `formatters_by_ft` in `lua/formatting.lua`.

Example: if you later run `:MasonInstall shfmt` to format shell scripts, add this line:

```lua
sh = { 'shfmt' },
```

A nvim restart is needed for the new entry to take effect (since `formatting.lua` is loaded at startup).

To check what formatters are installed and available: `:checkhealth conform`

---

## Verification

1. Restart nvim in a git repo — gutter signs should appear on changed lines
2. `:Gitsigns toggle_signs` to confirm gitsigns is loaded
3. Navigate hunks with `]c` / `[c`
4. Stage a hunk with `<leader>hs`, unstage with `<leader>hu`
5. Open a `.lua` file, make a change, save — stylua should format on save
6. `<leader>f` in a Python file — black + isort should run
7. `:checkhealth conform` — verify formatters are found
