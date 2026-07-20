# Plan: adapt neotest to the actual workflow

**Status:** not started (2026-07-20). Goal is to use neotest more by removing
the friction that keeps it from being reached for.

## Context

`testing.lua` calls `require('neotest').setup({ adapters = adapters })` and
configures **nothing else** — every panel runs on stock defaults that were
never chosen for this config. Three consequences, none of them obvious until
you look at where the windows land:

| Panel | Default (`neotest/config/init.lua`) | Where it lands |
|---|---|---|
| summary (`<leader>ns`) | `botright vsplit \| vertical resize 50` :244 | **right edge, 50 cols** |
| output panel (`<leader>nO`) | `botright split \| resize 15` :279 | bottom, 15 rows |
| output (`<leader>no`) | `floating`, 0.6×0.6 :227 | float |

So the summary opens on the **right edge — the same edge sidekick's CLI
split owns** (`ai.lua:74`, `layout = 'right'`), with no coordination between
them. And none of neotest's filetypes (`neotest-summary`,
`neotest-output-panel`, `neotest-output`) is registered in any of the three
panel registries: `buffers.lua`'s `special_filetypes` / `sidebar_filetypes`,
or `autocmds.lua:158`'s `clamped_panels`. stickybuf is the one exception —
neotest is in its built-in list already, so nothing to do there.

What already works, and shouldn't be rebuilt: `<leader>ns`'s summary tree
lists every test in the project and runs an individual test, file, or
directory from it. The gap is that the tree is **navigable but not
searchable**, and there is no run-the-whole-suite key.

## Workstream 1 — fuzzy test picker

A `pickers/tests.lua` mirroring `pickers/gotargets.lua`, which already
reserves this ground (`gotargets.lua:147-150`: *"main packages only … tests
stay with neotest"*).

**Enumeration API.** Use the `state` consumer, not the client:

```lua
for _, id in ipairs(require('neotest').state.adapter_ids()) do
  local tree = require('neotest').state.positions(id)  -- whole suite
  -- walk tree:iter_nodes(), keep node:data().type == 'test'
end
```

`consumers/state/init.lua:79-82` says outright that this consumer exists so
callers don't have to write async code — it's a synchronous snapshot, which
is what a snacks finder wants. The alternative (`client:get_position`) is
`---@async`, not exposed on the `neotest` module (`init.lua:115-119` only
surfaces consumers), and `_ensure_started()` can block.

**The one real trap:** discovery is project-wide but *progressive*
(`client/init.lua:437` walks the root when `discovery.enabled`, parsing files
concurrently in the background). A synchronous snapshot taken right after
startup **under-reports** — the tree holds dir/file nodes whose test children
aren't parsed yet. Either use the gotargets async finder shape so the picker
fills in, or re-trigger on neotest's `discover_positions` listener. A
one-shot sync read will silently show a partial list, which is worse than
slow.

Item shape: `text` = the fuzzy key (test name + relpath), plus `file`/`lnum`
from `node:data()` for a free preview. Confirm follows gotargets'
`close → vim.schedule → act` dance (`gotargets.lua:198-212`) — `neotest.run.run`
may open the output panel, and doing that while the picker's floats are up
lands the window wrong.

Two confirm actions worth having: run the selected test, and jump to it.
Multi-select → run several.

**Check first:** whether snacks ships a test source already. Cheap to verify,
and it would replace most of this.

## Workstream 2 — panel placement

The ask is to fold the summary into the `<leader>e`/`<leader>o` swap group.
The coordinator is explicitly **left-edge only** (GUIDE.md:411-453), and its
closing note says the registry "is now the only thing a third has to touch" —
which is true, but only for a panel that wants the *left* edge.

Two ways, and this is the plan's main open decision:

- **A — move the summary to the left edge** and register it as a third
  sidebar: override `summary.open` to `topleft vsplit | vertical resize N`,
  add `['neotest-summary'] = true` to `sidebar_filetypes` and a
  `sidebar_closers` entry, and have `<leader>ns` call
  `close_other_sidebars('neotest-summary')` gated on "am I already visible?"
  like `outline.lua:144-168`. Reuses everything; the tree/outline/summary
  become one mutually-exclusive group. Cost: the summary is now competing for
  the edge you use for navigation, and it's a 50-col panel.
- **B — generalize the coordinator to per-edge groups**, so the right edge
  (summary + sidekick CLI) coordinates independently of the left. Truer to
  what's actually on screen, but the registry currently has no notion of
  which edge a panel wants, and sidekick is deliberately *not* a coordinated
  sidebar today. Bigger change, touches a working abstraction.

**Recommendation: A**, unless using it reveals that the summary and the file
tree are genuinely wanted at the same time — in which case B is the honest
answer and A was wasted work. Try A first precisely because it's cheap to
reverse.

Either way, also register the summary in `autocmds.lua:158`'s
`clamped_panels` (scroll clamp) and consider `special_filetypes` so
code-only keymaps decline inside it.

The bottom output panel and the floating output are fine as-is — neither
contests an edge. Leave them.

## Workstream 3 — small gaps

- **Run the whole suite** — `neotest.run.run(vim.uv.cwd())`, no key today
  (`<leader>nf` stops at file scope). Suggest `<leader>na`.
- **Run the nearest *file's* failed tests only** — neotest supports
  re-running failures; worth a key if the suite gets slow.
- **`<leader>nf` naming** — it runs the file but opens nothing, which reads
  as a no-op when every test passes. Consider surfacing a summary notify.

## Verification

Per the nested `CLAUDE.md`, prefix every shell `nvim` with `env -u NVIM`.

1. Picker on a **cold start** against a real Go and Rust project — the whole
   point of the discovery trap above. Open nvim, immediately run the picker,
   confirm the count matches `go test ./... -list .` / `cargo test -- --list`
   rather than a partial tree.
2. Picker confirm actually runs the test (watch `<leader>nO`), and jump lands
   on the right line.
3. Swap behavior: `<leader>ns` from the file tree replaces it, from a code
   buffer just toggles, and closing never reaches into the others — the three
   cases GUIDE.md:411-453 describes.
4. Auto-quit still works with only the summary left open (`close_all_sidebars`
   sweeps every tabpage).
5. Suite run on a repo big enough that it takes a while — confirm `<leader>nq`
   still stops it.
