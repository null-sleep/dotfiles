# Fix `<leader>af`/`<leader>ac` context bugs via sidekick's context override

## Context

Testing sidekick.nvim's `<leader>a*` commands against the `fixtures/*` demo
files surfaced two real bugs in how `<leader>af` (send enclosing function)
and `<leader>ac` (send enclosing class) format their output — both traced to
sidekick.nvim's own source
(`~/.local/share/nvim/site/pack/core/opt/sidekick.nvim`), not this repo, not
aerial, not the fixtures. Examples seen:

```
function Max @fixtures/animal.go :L78:C2      -- should be col 1 (or the name's own col)
class @fixtures/animal.go :L4:C2               -- missing "Animal", wrong col
```

We don't want to patch the plugin directly — it's installed via `vim.pack`
and any edit there gets clobbered on update. sidekick ships an official
extension point for exactly this (`opts.cli.context`), so the fix is a local
override registered from this repo's own `ai.lua`, the existing home for all
sidekick config.

## Root causes (confirmed via headless nvim + source reading)

1. **Off-by-one column.** `sidekick/cli/context/location.lua`'s
   `M.get()` (position-kind branch, ~line 76/80) always does `from[2] + 1`,
   assuming a 0-based input column. That's correct for visual-selection
   ranges (`context/init.lua:224-233`'s `M.selection()`, built from
   `nvim_buf_get_mark`, which *is* 0-based) — but wrong for plain
   cursor/textobject positions, which arrive **already 1-based**
   (`context/init.lua:211`: `col = cursor[2] + 1`; `textobject.lua:141`:
   `col = start_col + 1`). The extra `+1` double-converts, landing the
   reported column one character into the `type`/`func`/`impl` keyword
   instead of at its true start. This is why the accurate examples we found
   earlier (the `Dog` selection, the `Describe` range start) both came from
   the *range* path, not the plain-position path.

2. **Missing name on Go struct/interface.**
   `sidekick/cli/context/textobject.lua`'s `get_textobject_name()` only
   checks `name`/`identifier`/`field` fields (and then direct children) on
   the exact node `vim.treesitter.get_node()` resolves at the textobject's
   start — no recursion. For Go, `type X struct{}`/`interface{}` resolve to
   a `type_declaration` node, which tree-sitter-go gives no `name` field
   (it can hold multiple comma-separated specs) — the name lives one level
   down, in a child `type_spec` node, which *does* have a `name` field.
   Confirmed directly:
   ```
   type_declaration:field('name')  → nil
   type_spec:field('name')         → "Animal"
   ```
   `method_declaration` (backing `function Name`) has `name` as a direct
   field, which is why that case already worked.

**Out of scope:** Rust's `impl Trait for Type` naming (currently labels
using the trait name, e.g. `class Animal` for `impl Animal for Bird`) is a
labeling *preference*, not a bug — not touched here.

## Approach

Override the two named context providers via sidekick's documented
extension point:
- `sidekick/config.lua:120-122` — `cli.context = {}`, doc comment "Add
  custom context. See `lua/sidekick/context/init.lua`".
- `sidekick/cli/context/init.lua:189-191` — `M.fn(name)` resolves
  `Config.cli.context[name] or M.context[name] or nil`, i.e. a user-supplied
  `cli.context["function"]`/`["class"]` fully replaces the built-ins for
  those names. No plugin file is touched.

The replacement re-implements the relevant slice of `textobject.lua` (same
`nvim-treesitter-textobjects.shared.textobject_at_point` call sidekick uses)
but:
- passes the **raw 0-based** treesitter column into `Loc.get` instead of
  pre-incrementing it, so `Loc.get`'s own `+1` performs the single correct
  conversion instead of double-converting;
- looks up the name with a small **depth-bounded (2-level) recursive**
  search — check fields on the node itself, then descend into its named
  children only — which finds `Animal`/`Dog` through
  `type_declaration → type_spec → name field`;
- as a deliberate improvement (not just parity with upstream's intent):
  once a name node is found, reports *that node's own position* rather than
  the declaration's start — e.g. `<leader>af` on `Max` points at the `Max`
  identifier itself, not at the `func` keyword. Falls back to the
  declaration's start position if no name is found (same as today).
- preserves existing failure semantics: outside any function/class, or on a
  filetype without a textobjects query, returns `nil` → benign no-op, same
  as now (already documented in GUIDE.md).

This was manually validated end-to-end in a headless nvim session against
`fixtures/animal.go` during investigation (correct column + correct names
for `Max`, `Animal`, `Dog`, `Cat.Name`); the plan is to land the same logic
properly in `ai.lua` and re-verify.

## Implementation

**File: `nvim/.config/nvim/lua/ai.lua`** (inline, not a new module —
`ai.lua` is already the home for all sidekick config, and this is ~50 lines
only ever used from its own `setup()` call).

- Add a local helper above the existing `require('sidekick').setup({...})`
  call (~line 33):

  ```lua
  -- Override sidekick's built-in {function}/{class} context providers
  -- (leader af/ac): upstream has a column off-by-one and a missing-name bug
  -- for wrapped declarations (e.g. Go's `type X struct{}`) — see
  -- sidekick/cli/context/{location,textobject}.lua. Fixed here via the
  -- documented cli.context override point instead of patching the plugin.
  local function textobject_context(kind)
    return function(ctx)
      local ok_shared, shared = pcall(require, 'nvim-treesitter-textobjects.shared')
      if not ok_shared or not pcall(vim.treesitter.get_parser, ctx.buf) then
        return nil
      end
      local ok_range, range = pcall(
        shared.textobject_at_point,
        ('@%s.outer'):format(kind), 'textobjects', ctx.buf, { ctx.row, ctx.col }
      )
      if not ok_range or not range then return nil end
      local start_row, start_col = range[1], range[2] -- 0-based

      local node = vim.treesitter.get_node({ bufnr = ctx.buf, pos = { start_row, start_col } })
      local function find_name_node(n, depth)
        if not n or depth > 2 then return nil end
        for _, f in ipairs({ 'name', 'identifier', 'field' }) do
          local fld = n:field(f)[1]
          if fld then return fld end
        end
        for child in n:iter_children() do
          if child:named() then
            local found = find_name_node(child, depth + 1)
            if found then return found end
          end
        end
      end

      local name_node = node and find_name_node(node, 0)
      local name
      if name_node then
        name = vim.treesitter.get_node_text(name_node, ctx.buf)
        start_row, start_col = name_node:range()
      end

      -- Loc.get's position formatter adds its own +1, so pass the raw
      -- 0-based column here (not start_col + 1) to avoid double-converting.
      local loc_text = require('sidekick.cli.context.location').get(
        { buf = ctx.buf, cwd = ctx.cwd, row = start_row + 1, col = start_col },
        { kind = 'position' }
      )
      if not loc_text or #loc_text == 0 then return nil end

      local ret = { { kind, 'Type' } }
      if name then
        ret[#ret + 1] = { ' ', 'Normal' }
        ret[#ret + 1] = { name, 'Function' }
      end
      ret[#ret + 1] = { ' ', 'Normal' }
      vim.list_extend(ret, loc_text[1])
      return { ret }
    end
  end
  ```

- Inside the `cli = { ... }` table passed to `setup()`, add a `context`
  entry alongside the existing `picker`/`win` keys:

  ```lua
  cli = {
    picker = 'telescope',
    context = {
      ['function'] = textobject_context('function'),
      class = textobject_context('class'),
    },
    win = { ... }, -- unchanged
  },
  ```

**File: `nvim/.config/nvim/GUIDE.md`** (same change, per repo convention) —
extend the existing paragraph right after the AI keymap table (~line
1674-1678, the one that already explains `af`/`ac` resolve via
`nvim-treesitter-textobjects`) to note: the position/name are produced by a
local override in `ai.lua` (not sidekick's built-in `{function}`/`{class}`
context), fixing upstream's column/name bugs, and that it now points at the
identifier itself rather than the declaration's start.

No new Architecture entry or Load-order change — `ai.lua` is already
documented there, and this doesn't add a new `require()`.

## Verification

1. **Headless smoke test** (re-run the manual validation done during
   investigation, now against the real code path in `ai.lua`): open
   `fixtures/animal.go`, `fixtures/animal.rs`, `fixtures/animal.py`,
   simulate `<leader>af`/`<leader>ac` at cursor positions inside `Max`,
   `Animal` (interface), `Dog` (struct), `Cat.Name` (method), and Rust's
   `impl Animal for Bird`; print the rendered text and confirm:
   - column lands exactly on the reported identifier, no off-by-one;
   - Go's `class` entries now include `Animal`/`Dog`/`Bird`;
   - Rust/Python behavior unchanged or improved (still finds a name, no
     column drift).
2. **Interactive check** (per this repo's `/verify` convention — drive the
   real keymap, not just a script): in real nvim, put the cursor at a few
   spots inside `fixtures/animal.go`/`.rs` and press `<leader>af`/`<leader>ac`
   for real; confirm the text landing in the sidekick prompt bar looks
   correct before sending. Also confirm the *no-op* case still works
   (cursor outside any function/class).
3. Re-source `ai.lua` (or restart nvim) and check `:messages` for errors.

---

## Also: `<leader>ab` becomes an interactive buffer picker

### Context

Today `<leader>ab` (`keymaps.lua:360-362`) unconditionally sends *every*
open buffer via sidekick's `{buffers}` context. Wanted instead: open a
telescope picker so you can choose which open buffers to share, kept small
(this is a quick "pick a few files" action, not the full buffer switcher —
don't want a large window for it).

### Key finding: the "send" mechanism already exists, for free

`plugins.lua:392-414` already defines a **global telescope default mapping**,
`<M-a>` (`send_to_sidekick`), wired into telescope's `defaults.mappings` —
i.e. it's active in *every* telescope picker unless a picker's own
`attach_mappings` overrides that key. It reads the picker's current
multi-selection (falling back to the entry under cursor), builds
space-separated `path`/`path:lnum` refs, and sends them via
`require('ai').send({ msg = ... })`. This is the exact mechanism GUIDE.md's
keymap table already documents as `<M-a>` (in picker) → "Send picker
selection(s) to CLI".

`pickers/buffer.lua` (the existing `<leader>bb`/`<leader>m` buffer picker,
built on `telescope.builtin.buffers`) only overrides `<C-d>` and the
`<M-1>..<M-9>` quick-pick in its `attach_mappings` — it never touches
`<M-a>`, so the global send-to-sidekick mapping already works inside it
today. **No new "send" code is needed** — just point `<leader>ab` at this
picker instead of at sidekick's bulk `{buffers}` send, and multi-select
(`<Tab>`) + `<M-a>` does the rest.

Note this changes the exact text shape sent to the AI: today's `{buffers}`
send is a markdown bullet list (`- @path`, one per line, via sidekick's own
`Loc.get(kind="file")`); the `<M-a>` path instead sends one line of
space-separated `path`/`path:lnum` refs (`send_to_sidekick` in
`plugins.lua`). Both are equally parseable context for me — just flagging
the format changes.

### Approach

1. **`pickers/buffer.lua`** — give `M.open()` an optional `opts` param,
   merged (`vim.tbl_deep_extend('force', defaults, opts)`) into the
   `builtin.buffers({...})` call, so callers can override `layout_config`/
   `previewer` without duplicating the picker. `<leader>bb`/`<leader>m` keep
   calling `M.open()` with no args (unchanged, full-size picker with
   preview).

2. **`keymaps.lua`** — change `<leader>ab`'s handler (currently
   `require('ai').send({ msg = '{buffers}' })`) to:
   ```lua
   function() require('pickers.buffer').open({
     layout_config = { height = 0.3 },
     previewer = false,
   }) end,
   { desc = 'AI: Pick open buffers to send' }
   ```
   Small (`height = 0.3`) and preview-off, since this is "pick file names to
   attach," not "browse buffer contents" — keeps it compact per your ask.
   `<CR>` still does the picker's normal jump-to-buffer; `<Tab>` multi-selects;
   `<M-a>` sends the selection (or, with nothing multi-selected, just the
   entry under cursor) to the active CLI session.

### Doc updates

- `GUIDE.md`'s AI keymap table (~line 1670): change the `<leader>ab` row
  from "Send list of open buffers" to something like "Pick open buffers to
  send (telescope; `<Tab>` multi-select, `<M-a>` to send, `<CR>` jumps to
  buffer as usual)".
- The prose paragraph right after the table (~line 1674-1678, already being
  edited for the af/ac fix above) gets one more sentence noting `ab` now
  routes through `pickers.buffer` + the existing global `<M-a>` send
  mapping, rather than sidekick's own `{buffers}` context.

### Verification

1. Open a few files, press `<leader>ab` — confirm a compact picker opens
   (no preview pane, noticeably shorter than `<leader>bb`'s).
2. `<Tab>` to multi-select 2-3 buffers, `<M-a>` — confirm exactly those
   paths land in the sidekick prompt bar, not all open buffers.
3. With no multi-selection, `<M-a>` on the entry under the cursor — confirm
   it sends just that one buffer.
4. `<leader>bb`/`<leader>m` still open the original full-size picker with
   preview — confirm unaffected.
5. `<CR>` inside the `ab` picker still jumps to the selected buffer (normal
   picker behavior, unchanged).
