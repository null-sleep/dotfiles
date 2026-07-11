# Plan: Tree-sitter text objects (select / move / swap)

**Status:** research / not started
**Date:** 2026-07-03

## Context

Part of a 3-item plan to port Helix's editing-model gains into this Neovim
config instead of switching editors (see `~/.claude/plans/i-am-considering-trying-calm-parrot.md`
for the full Helix-vs-nvim delta). The other two items are **done**:

1. **This plan** — `nvim-treesitter-textobjects` (select/move/swap).
2. ~~Sticky scope header~~ — `nvim-treesitter-context`, implemented in
   `lua/treesitter_context.lua` (commit `a0c67c5`). Also closes the "sticky
   scroll" gap listed under VS Code in `plans/nvim-backlog.md`.
3. ~~Structural/incremental selection~~ (Helix `Alt-o`/`Alt-i`) — implemented
   in `lua/structural_select.lua` (commit `a0c67c5`).

Multiple cursors (the other big VS Code/Helix gap) was explicitly declined —
not in scope here or elsewhere.

## Problem

Vim's native text objects are character/pair based: `iw` (inner word), `i(`
(inside parens), `ip` (paragraph). There's no semantic "a function," "inner
class body," "a parameter," "a loop" — the things Helix's `mi`/`ma` give you
for free via tree-sitter. This config already parses every buffer with
tree-sitter (highlighting, folding, the two features above) but doesn't use
that tree for text objects yet.

## Goal

Add semantic, tree-sitter-driven text objects that compose with every
existing operator/count (`daf`, `yif`, `caa`, `>if`, `.` to repeat), plus
move-to-next/prev and parameter-swap — closing the last real editing-model
gap versus Helix without adopting its selection-first grammar wholesale.

## Approach

Install `nvim-treesitter-textobjects`, pinned to the **`main`** branch.

This config's `nvim-treesitter` is already on `main` (the incompatible
rewrite that dropped the old `require('nvim-treesitter.configs').setup{}`
module system — see the inline setup in `init.lua` ~216-299). The textobjects
plugin has a matching `main` branch that is a **compatible** rewrite; its
`master` branch is frozen for the old config style and will not work here.
This must not be a plain `gh(...)` add — pin the branch explicitly, same
pattern as the existing `nvim-treesitter` entry in `plugins.lua`.

Config shape (post-rewrite): `require('nvim-treesitter-textobjects').setup{}`
plus manual keymaps calling into `.select` / `.move` / `.swap` submodules —
there's no more declarative `textobjects = { select = {...} }` block.

### Keymap plan

| Action | Keys | Notes |
|---|---|---|
| select a/inner **function** | `af` / `if` | signature+body / body only |
| select a/inner **class** | `ac` / `ic` | |
| select a/inner **parameter** | `aa` / `ia` | argument in a call/def |
| select a/inner **loop** | `al` / `il` | |
| move to next/prev **function** start | `]f` / `[f` | end variants `]F` / `[F` |
| move to next/prev **class** start | `]k` / `[k` | **not** `]c`/`[c` — gitsigns owns those for hunk nav |
| swap parameter with next/prev | `<leader>a` / `<leader>A` | needs a `whichkey.lua` group label |
| peek | — | skipped; `goto-preview` already covers this role |

`]f`/`[f`/`]k`/`[k` need an entry in `lua/whichkey.lua`'s trigger/description
list (it only intercepts `<leader>`, `g`, `[`, `]` — same reason gitsigns'
`]c`/`[c` are registered there). `af`/`if`/etc. are operator-pending text
objects and need no which-key registration.

### File layout

New module `lua/treesitter_textobjects.lua` (matches the existing
one-module-per-concern convention — same pattern as the just-added
`treesitter_context.lua` / `structural_select.lua`), required from `init.lua`
in the same block as those two. Keep it separate from the inline treesitter
setup in `init.lua` rather than growing that block further.

### Sketch

```lua
-- lua/plugins.lua — add near the existing nvim-treesitter entry
{ src = gh('nvim-treesitter/nvim-treesitter-textobjects'), version = 'main' },
```

```lua
-- lua/treesitter_textobjects.lua (new)
require('nvim-treesitter-textobjects').setup({})

local select = require('nvim-treesitter-textobjects.select')
local move = require('nvim-treesitter-textobjects.move')
local swap = require('nvim-treesitter-textobjects.swap')

-- select
vim.keymap.set({ 'x', 'o' }, 'af', function() select.select_textobject('@function.outer', 'textobjects') end)
vim.keymap.set({ 'x', 'o' }, 'if', function() select.select_textobject('@function.inner', 'textobjects') end)
-- ...ac/ic, aa/ia, al/il follow the same shape

-- move
vim.keymap.set({ 'n', 'x', 'o' }, ']f', function() move.goto_next_start('@function.outer', 'textobjects') end)
vim.keymap.set({ 'n', 'x', 'o' }, '[f', function() move.goto_previous_start('@function.outer', 'textobjects') end)
vim.keymap.set({ 'n', 'x', 'o' }, ']k', function() move.goto_next_start('@class.outer', 'textobjects') end)
vim.keymap.set({ 'n', 'x', 'o' }, '[k', function() move.goto_previous_start('@class.outer', 'textobjects') end)

-- swap
vim.keymap.set('n', '<leader>a', function() swap.swap_next('@parameter.inner') end)
vim.keymap.set('n', '<leader>A', function() swap.swap_previous('@parameter.inner') end)
```

(Exact API surface should be checked against the installed `main`-branch
README at implementation time — the module has been iterating.)

## Verification

1. `:checkhealth nvim-treesitter` — confirm no master/main mismatch (same
   check used for `nvim-treesitter-context`).
2. `vaf` / `vif` on a function selects signature+body / body only; `daf`
   deletes a whole function and undoes cleanly.
3. `vac`/`vic`, `vaa`/`via`, `val`/`vil` select the expected node on a
   representative Lua and Go file (two languages already in
   `ensure_installed`).
4. `]f` / `[f` jump between function starts in a multi-function file; `]k`
   / `[k` jump between classes without touching gitsigns' `]c`/`[c`.
5. `<leader>a` on a parameter inside `foo(a, b, c)` swaps it with the next
   one; `<leader>A` swaps back.
6. `<leader>sk` (keybinding picker) shows the new `]f`/`[f`/`]k`/`[k` entries
   with descriptions, confirming the which-key registration took.

## LazyVim delta to fold in (from the LazyVim comparison pass)

Folded here from the LazyVim comparison pass (item 2) when the wishlist docs
were consolidated into `plans/nvim-backlog.md` — LazyVim wires this same plugin
plus a `mini.ai` layer, and its extras are worth considering when this plan
lands:

- **Layer `nvim-mini/mini.ai` on top** for what treesitter-textobjects alone
  doesn't give: **arguments** (already `aa`/`ia` above), **digits** (`d`),
  and **next/last variants** (`vinq` = "inside next quotes", `il`/`al` next/
  last). LazyVim's mini.ai spec adds custom specs for buffer (`ag`/`ig`),
  digits (`d`), and a treesitter-driven `o` object (blocks/conditionals/loops).
  Source: `lua/lazyvim/plugins/coding.lua` (mini.ai section).
- **`ai_whichkey` integration** — LazyVim registers every text object in
  which-key so pressing `va` pops a menu of what's selectable. Source:
  `lua/lazyvim/util/mini.lua`.
- **Wiring pattern reference** — main-branch textobjects needs explicit keymap
  wiring (no module system), exactly as sketched above. LazyVim's per-FileType
  buffer-local `select()`/`move()` pattern lives in
  `lua/lazyvim/plugins/treesitter.lua` if a per-language approach is wanted.
- Pairs with (does not replace) the existing `<M-o>`/`<M-i>` structural select.

⚠ **Keymap collision to resolve first:** this plan's `<leader>a` / `<leader>A`
parameter-swap keys predate the sidekick AI-CLI `<leader>a*` namespace, which
now owns that prefix. Re-key the swap maps (e.g. `<leader>sw`/`<leader>sW` or a
`g`-prefixed pair) before implementing — the sketch above is stale on this
point.
