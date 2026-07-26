# Treesitter Text Objects & Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `nvim-treesitter-textobjects` to add semantic text objects (`af`/`if`, `ac`/`ic`, `aa`/`ia`, `al`/`il`) and `]f`/`[f`/`]k`/`[k` navigation keymaps.

**Architecture:** New module `lua/treesitter_textobjects.lua` calls the plugin's `select` and `move` submodules directly (the `main`-branch rewrite dropped the old declarative config style). Registered in `init.lua` beside `treesitter_context.lua` and `structural_select.lua`. Which-key gets entries for `]f`/`[f`/`]k`/`[k` so they appear in the `]`/`[` popup.

**Tech Stack:** `nvim-treesitter/nvim-treesitter-textobjects` (already installed, `main` branch, `plugins.lua:13`). `pcall(vim.cmd.packadd, 'nvim-treesitter-textobjects')` already runs in `plugins.lua:289` — no install step needed.

## Global Constraints

- Plugin is pinned to `main` branch — do not change this; `master` is the frozen old API and is incompatible with this config's treesitter setup.
- `]c`/`[c` are owned by gitsigns (hunk nav, `git.lua:23,30`) — never use them for class navigation. Use `]k`/`[k` for class jumps.
- `<leader>a*` namespace is fully owned by AI/sidekick (`keymaps.lua` — `<leader>aa`, `<leader>ai`, `<leader>an`, `<leader>al`, `<leader>ax`, `<leader>ao`, `<leader>at`, `<leader>ap`, `<leader>af`, `<leader>ac`, `<leader>ae`, `<leader>ab`, `<leader>aq`). Parameter swap must use a different prefix.
- One module per concern — new code goes in `lua/treesitter_textobjects.lua`, not inlined into `plugins.lua` or `init.lua`'s treesitter block.
- Every keymap must have a `desc` string (surfaces in which-key and `<leader>sk`).
- Update `GUIDE.md` in the same commit as the implementation (nvim CLAUDE.md rule).

---

## Shortlist of shortcuts to consider

This is the full design space. The plan below implements the **bold** ones. The rest are listed for future consideration.

| Keys | Captures | Notes |
|---|---|---|
| **`af`/`if`** | `@function.outer`/`@function.inner` | Core — select whole function vs. body only |
| **`ac`/`ic`** | `@class.outer`/`@class.inner` | Core — select whole class vs. body only |
| **`aa`/`ia`** | `@parameter.outer`/`@parameter.inner` | Argument in a call or definition |
| **`al`/`il`** | `@loop.outer`/`@loop.inner` | for/while/range loops |
| **`]f`/`[f`** | `@function.outer` | Jump to next/prev function start |
| **`]F`/`[F`** | `@function.outer` | Jump to next/prev function end |
| **`]k`/`[k`** | `@class.outer` | Jump to next/prev class start (`]c`/`[c` taken by gitsigns) |
| `ai`/`ii` | `@conditional.outer`/`@conditional.inner` | if/else blocks — deferred: `ii` conflicts with insert mode muscle memory |
| `]a`/`[a` | `@parameter.outer` | Jump between parameters — deferred: `]a`/`[a` owned by aerial |
| swap next param | `<leader>cA`/`<leader>ca` | Swap parameter with next/prev — deferred: good key TBD, whole `<leader>a*` namespace is taken |
| `o` (via mini.ai) | `@block.outer` + conditionals + loops | LazyVim's combined `o` text object via `mini.ai` — deferred: needs `mini.ai` dependency |
| `d` (via mini.ai) | digits/numbers | `mini.ai` only — deferred |
| `vinq`/`vil`/`val` | next/last variants | `mini.ai` "next/last" modifier — deferred |

---

## File Map

- **Create:** `nvim/.config/nvim/lua/treesitter_textobjects.lua` — all setup, select, and move keymaps
- **Modify:** `nvim/.config/nvim/lua/init.lua` — add `require('treesitter_textobjects')` in the treesitter block
- **Modify:** `nvim/.config/nvim/lua/whichkey.lua` — register `]f`/`[f`/`]F`/`[F`/`]k`/`[k` descriptions and search keywords
- **Modify:** `nvim/.config/nvim/GUIDE.md` — document new keymaps

---

## Task 1: Create `treesitter_textobjects.lua` with select and move keymaps

**Files:**
- Create: `nvim/.config/nvim/lua/treesitter_textobjects.lua`

**Interfaces:**
- Produces: module that can be `require()`d from `init.lua` with no return value needed
- Consumes: `nvim-treesitter-textobjects` already packadd'd in `plugins.lua:289`

- [ ] **Step 1: Verify the actual API surface of the installed main-branch plugin**

```bash
ls ~/.local/share/nvim/site/pack/packer/opt/nvim-treesitter-textobjects/lua/nvim-treesitter-textobjects/
```

Expected output: directory listing including `select.lua`, `move.lua`, `swap.lua` (or similar). If the structure differs, adjust the `require()` paths in step 2 accordingly.

- [ ] **Step 2: Create `lua/treesitter_textobjects.lua`**

```lua
-- lua/treesitter_textobjects.lua
-- Semantic text objects and navigation via nvim-treesitter-textobjects.
-- Plugin is packadd'd in plugins.lua; this module only configures keymaps.
-- select: x+o modes so operators (d, y, c, >, <) and visual selection both work.
-- move: n+x+o modes so jumps work in normal, visual-extend, and operator-pending.

require('nvim-treesitter-textobjects').setup({})

local select = require('nvim-treesitter-textobjects.select')
local move   = require('nvim-treesitter-textobjects.move')

-- ── Text objects (select) ────────────────────────────────────────────────────
-- Composable with every operator and count: daf, yif, caa, >if, . to repeat.

-- function: af = signature+body (outer), if = body only (inner)
vim.keymap.set({ 'x', 'o' }, 'af',
  function() select.select_textobject('@function.outer', 'textobjects') end,
  { desc = 'TS: Select outer function' })
vim.keymap.set({ 'x', 'o' }, 'if',
  function() select.select_textobject('@function.inner', 'textobjects') end,
  { desc = 'TS: Select inner function' })

-- class: ac = whole class, ic = body only
vim.keymap.set({ 'x', 'o' }, 'ac',
  function() select.select_textobject('@class.outer', 'textobjects') end,
  { desc = 'TS: Select outer class' })
vim.keymap.set({ 'x', 'o' }, 'ic',
  function() select.select_textobject('@class.inner', 'textobjects') end,
  { desc = 'TS: Select inner class' })

-- parameter/argument: aa = with surrounding comma, ia = value only
vim.keymap.set({ 'x', 'o' }, 'aa',
  function() select.select_textobject('@parameter.outer', 'textobjects') end,
  { desc = 'TS: Select outer parameter' })
vim.keymap.set({ 'x', 'o' }, 'ia',
  function() select.select_textobject('@parameter.inner', 'textobjects') end,
  { desc = 'TS: Select inner parameter' })

-- loop: al = whole loop incl. keyword, il = body only
vim.keymap.set({ 'x', 'o' }, 'al',
  function() select.select_textobject('@loop.outer', 'textobjects') end,
  { desc = 'TS: Select outer loop' })
vim.keymap.set({ 'x', 'o' }, 'il',
  function() select.select_textobject('@loop.inner', 'textobjects') end,
  { desc = 'TS: Select inner loop' })

-- ── Navigation (move) ────────────────────────────────────────────────────────
-- Note: ]c/[c are owned by gitsigns (hunk nav) — use ]k/[k for classes.

-- function start
vim.keymap.set({ 'n', 'x', 'o' }, ']f',
  function() move.goto_next_start('@function.outer', 'textobjects') end,
  { desc = 'Next: Function start' })
vim.keymap.set({ 'n', 'x', 'o' }, '[f',
  function() move.goto_previous_start('@function.outer', 'textobjects') end,
  { desc = 'Previous: Function start' })

-- function end
vim.keymap.set({ 'n', 'x', 'o' }, ']F',
  function() move.goto_next_end('@function.outer', 'textobjects') end,
  { desc = 'Next: Function end' })
vim.keymap.set({ 'n', 'x', 'o' }, '[F',
  function() move.goto_previous_end('@function.outer', 'textobjects') end,
  { desc = 'Previous: Function end' })

-- class start (]c/[c taken by gitsigns)
vim.keymap.set({ 'n', 'x', 'o' }, ']k',
  function() move.goto_next_start('@class.outer', 'textobjects') end,
  { desc = 'Next: Class start' })
vim.keymap.set({ 'n', 'x', 'o' }, '[k',
  function() move.goto_previous_start('@class.outer', 'textobjects') end,
  { desc = 'Previous: Class start' })
```

- [ ] **Step 3: Verify the file saved correctly**

```bash
wc -l nvim/.config/nvim/lua/treesitter_textobjects.lua
```

Expected: ~65 lines.

---

## Task 2: Wire into `init.lua` and register which-key entries

**Files:**
- Modify: `nvim/.config/nvim/lua/init.lua`
- Modify: `nvim/.config/nvim/lua/whichkey.lua`

**Interfaces:**
- Consumes: `lua/treesitter_textobjects.lua` from Task 1

- [ ] **Step 1: Find the treesitter block in `init.lua`**

```bash
grep -n "treesitter_context\|structural_select" nvim/.config/nvim/lua/init.lua
```

Expected: two lines showing `require('treesitter_context')` and `require('structural_select')`. Note the line numbers — add the new require on the line after `structural_select`.

- [ ] **Step 2: Add the require to `init.lua`**

In `init.lua`, after the `require('structural_select')` line, add:

```lua
require('treesitter_textobjects')
```

- [ ] **Step 3: Add which-key descriptions for the navigation keys**

In `whichkey.lua`, inside the `wk.add({...})` block, after the `]a`/`[a` aerial entries (lines 53-54), add:

```lua
  -- Treesitter navigation
  { ']f', desc = 'Next: Function start' },
  { '[f', desc = 'Previous: Function start' },
  { ']F', desc = 'Next: Function end' },
  { '[F', desc = 'Previous: Function end' },
  { ']k', desc = 'Next: Class start' },
  { '[k', desc = 'Previous: Class start' },
```

- [ ] **Step 4: Add search keywords in whichkey.lua's keywords table**

In `whichkey.lua`, inside the `keywords` table, add:

```lua
  [']f']  = 'treesitter function navigation jump semantic',
  ['[f']  = 'treesitter function navigation jump semantic',
  [']k']  = 'treesitter class navigation jump semantic',
  ['[k']  = 'treesitter class navigation jump semantic',
```

---

## Task 3: Verify end-to-end and update GUIDE.md

**Files:**
- Modify: `nvim/.config/nvim/GUIDE.md`

- [ ] **Step 1: Health check**

Open nvim and run:
```
:checkhealth nvim-treesitter
```

Expected: no errors about `nvim-treesitter-textobjects`. The `main`-branch plugin should report as healthy alongside the main treesitter plugin.

- [ ] **Step 2: Verify text objects on a Lua file**

Open any Lua file with functions (e.g. `lua/keymaps.lua`). In normal mode:
- `vaf` — should visually select the whole function under cursor (signature + body)
- `vif` — should select body only (no `function` keyword line)
- `daf` — delete a function; undo with `u`
- `vaa` on a function argument — should select the argument including surrounding comma
- `val` on a loop body — should select the loop

- [ ] **Step 3: Verify navigation on a multi-function file**

In `lua/keymaps.lua`:
- `]f` — jumps to the next function definition start
- `[f` — jumps back to the previous one
- `]F` — jumps to end of next function
- `]k` / `[k` — in a file with classes (e.g. a Go or Python fixture) jump between class starts

- [ ] **Step 4: Verify which-key popup**

In normal mode, press `]` and wait 300ms. The popup should include:
- `f` → Next: Function start
- `F` → Next: Function end
- `k` → Next: Class start

- [ ] **Step 5: Update GUIDE.md**

In `GUIDE.md`, find the treesitter section (search for `treesitter_context` or `structural_select`). Add a new subsection or extend the existing one with the new keymaps:

```markdown
### Treesitter text objects

Semantic text objects driven by the AST — compose with every operator and count.

| Keys | Object | Notes |
|---|---|---|
| `af`/`if` | Function | outer (signature+body) / inner (body only) |
| `ac`/`ic` | Class | outer / inner |
| `aa`/`ia` | Parameter | outer (with comma) / inner (value only) |
| `al`/`il` | Loop | outer / inner |
| `]f`/`[f` | Function start | next / previous |
| `]F`/`[F` | Function end | next / previous |
| `]k`/`[k` | Class start | next / previous (`]c`/`[c` are gitsigns hunk nav) |
```

- [ ] **Step 6: Commit**

```bash
git add nvim/.config/nvim/lua/treesitter_textobjects.lua \
        nvim/.config/nvim/lua/init.lua \
        nvim/.config/nvim/lua/whichkey.lua \
        nvim/.config/nvim/GUIDE.md
git commit -m "feat(nvim): add treesitter text objects and ]f/[f/]k/[k navigation"
```

---

## API surface note

The `main`-branch `nvim-treesitter-textobjects` API should be verified at implementation time (Step 1 of Task 1). If the submodule paths differ from the sketch above (e.g. `nvim-treesitter-textobjects.move` vs. `nvim-treesitter-textobjects/move`), adjust the `require()` calls accordingly. The plugin's own README on `main` is the authoritative source.
