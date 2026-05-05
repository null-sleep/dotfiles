# Git Diff Review Picker for Neovim

## Context

The shell functions `gd`, `gds`, `gdn` show git diffs in the terminal. The goal is to create nvim-native equivalents that open a file list with diffs — so you can navigate between changed files and review interactively.

Two approaches considered below: a custom Telescope picker vs diffview.nvim.

## Workflow (same for both approaches)

| Shell | Nvim command | Keymap | What it shows |
|-------|-------------|--------|---------------|
| `nvd` | `:Gd` | `<leader>sd` | Unstaged changes (like `gd`) |
| `nvd 3` | `:Gd 3` | — | Diff from HEAD~3 to working tree |
| `nvds` | `:Gds` | `<leader>sD` | Staged changes (like `gds`) |
| `nvds 3` | `:Gds 3` | — | Staged diff from HEAD~3 |
| `nvdn` | `:Gdn` | — | Last commit's diff (like `gdn`) |
| `nvdn 2` | `:Gdn 2` | — | 2nd-to-last commit's diff |

Shell functions launch nvim into the view. Commands/keymaps work from inside nvim.

---

## Option A: Custom Telescope Picker

### Pros
- Consistent with existing picker patterns (`<M-1>..<M-9>` quick-pick, numbered rows)
- Lightweight — no new plugin, reuses gitstatus.lua patterns
- Fuzzy filtering on file names

### Cons
- ~130 lines of custom code including a custom buffer previewer
- Preview pane only — no side-by-side diff view of the file
- Can't stage/unstage from this picker (gitstatus.lua already handles that)

### Changes

**NEW: `nvim/.config/nvim/lua/pickers/gitdiff.lua`** (~130 lines)

Single `M.open(opts)` with `opts.mode` (`'unstaged'`|`'staged'`|`'commit'`) and `opts.n` (number).

- `build_diff_args(mode, n)` — maps mode/n to git diff CLI args
- File list via `git diff <args> --name-status` (oneshot job finder)
- Entry maker: parse `<status>\t<path>`, numbered rows, status icon
- Custom `new_buffer_previewer` running `git diff <args> -- <file>` with diff highlighting
- `on_complete` for "No changes found" notification
- `<M-1>..<M-9>` quick-pick via `common.bind_quick_pick`
- Dynamic prompt title

**MODIFY: `nvim/.config/nvim/lua/git.lua`** — add `:Gd`, `:Gds`, `:Gdn` commands
**MODIFY: `nvim/.config/nvim/lua/keymaps.lua`** — add `<leader>sd`, `<leader>sD`
**MODIFY: `zsh/.zshrc_config.zsh`** — add `nvd`, `nvds`, `nvdn` shell functions

---

## Option B: diffview.nvim

### What it is

[sindrets/diffview.nvim](https://github.com/sindrets/diffview.nvim) — a dedicated diff review UI. Opens in a new tab with a file panel on the left and side-by-side diffs on the right. Supports staging, hunk navigation, and arbitrary git rev ranges.

### Command mapping

diffview.nvim commands map directly to gd/gds/gdn:

| gd/gds/gdn | diffview command |
|-------------|-----------------|
| `gd` | `:DiffviewOpen` (unstaged vs index) |
| `gd 3` | `:DiffviewOpen HEAD~3` (HEAD~3 vs working tree) |
| `gds` | `:DiffviewOpen --cached` (staged vs HEAD) |
| `gds 3` | `:DiffviewOpen --cached HEAD~3` (staged vs HEAD~3) |
| `gdn` | `:DiffviewOpen HEAD~1..HEAD` (single commit) |
| `gdn 2` | `:DiffviewOpen HEAD~2..HEAD~1` (specific commit) |

Close with `:DiffviewClose` or `q` in the file panel.

### Pros
- Purpose-built for exactly this workflow — side-by-side diffs with file navigation
- Full diff view (not just a preview pane) — shows both sides of the file
- File panel with staging/unstaging (`s`/`S`/`U`)
- Hunk-level navigation within files
- Battle-tested, widely used plugin
- Minimal config needed — the commands already accept the right arguments
- Very little custom code: just thin wrappers (`:Gd`, `:Gds`, `:Gdn`) and shell functions

### Cons
- New plugin dependency (~3k lines)
- Different UI paradigm from Telescope pickers — tab-based, not floating picker
- No `<M-1>..<M-9>` quick-pick or fuzzy filter on file names (uses a tree-style panel)
- Original repo maintenance slowed (last commit June 2024), though active forks exist
- No numbered file list — navigate with `j`/`k` or `]f`/`[f`

### Changes

**MODIFY: `nvim/.config/nvim/lua/plugins.lua`** — add diffview.nvim:

```lua
vim.pack.add({ url = 'https://github.com/sindrets/diffview.nvim' })
```

**NEW: `nvim/.config/nvim/lua/diffview.lua`** (~40 lines) — setup + user commands:

```lua
vim.cmd.packadd('diffview.nvim')
require('diffview').setup({
  -- minimal config, mostly defaults
})

vim.api.nvim_create_user_command('Gd', function(cmd)
  local n = tonumber(cmd.args)
  if n then
    vim.cmd('DiffviewOpen HEAD~' .. n)
  else
    vim.cmd('DiffviewOpen')
  end
end, { nargs = '?' })

vim.api.nvim_create_user_command('Gds', function(cmd)
  local n = tonumber(cmd.args)
  if n then
    vim.cmd('DiffviewOpen --cached HEAD~' .. n)
  else
    vim.cmd('DiffviewOpen --cached')
  end
end, { nargs = '?' })

vim.api.nvim_create_user_command('Gdn', function(cmd)
  local n = tonumber(cmd.args) or 1
  vim.cmd('DiffviewOpen HEAD~' .. n .. '..HEAD~' .. (n - 1))
end, { nargs = '?' })
```

**MODIFY: `nvim/.config/nvim/init.lua`** — add `require('diffview')` after git module
**MODIFY: `nvim/.config/nvim/lua/keymaps.lua`** — add `<leader>sd`, `<leader>sD`

```lua
vim.keymap.set('n', '<leader>sd', '<cmd>Gd<CR>',  { desc = 'Search: Diff (unstaged)' })
vim.keymap.set('n', '<leader>sD', '<cmd>Gds<CR>', { desc = 'Search: Diff (staged)' })
```

**MODIFY: `zsh/.zshrc_config.zsh`** — add `nvd`, `nvds`, `nvdn` shell functions:

```bash
nvd() {
  nvim -c "${1:+DiffviewOpen HEAD~$1}${1:-DiffviewOpen}"
}
nvds() {
  nvim -c "${1:+DiffviewOpen --cached HEAD~$1}${1:-DiffviewOpen --cached}"
}
nvdn() {
  local n="${1:-1}"
  nvim -c "DiffviewOpen HEAD~${n}..HEAD~$(($n - 1))"
}
```

---

## Recommendation

**Option B (diffview.nvim)** is the better fit. The core use case is *reviewing diffs across multiple files* — that's exactly what diffview was built for. Side-by-side diffs with a file panel is a much better review experience than a Telescope preview pane. The implementation is also simpler (~40 lines of wrappers vs ~130 lines of custom picker + previewer).

The Telescope approach is better for *finding and opening* a changed file. But `<leader>sm` (gitstatus picker) already serves that purpose.

## Verification

1. `:Gd` — opens diffview tab with unstaged changes, file panel on left, side-by-side diff on right
2. `:Gds` — same but for staged changes
3. `:Gdn` — shows last commit's diff
4. `:Gd 3` — shows all changes in last 3 commits vs working tree
5. `<leader>sd` / `<leader>sD` — same as `:Gd` / `:Gds`
6. `q` in file panel closes the view
7. Navigate files with `j`/`k`, hunks with `]c`/`[c`
8. From terminal: `nvd`, `nvds`, `nvdn` launch nvim into diffview
