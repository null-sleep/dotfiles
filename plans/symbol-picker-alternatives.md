# Evaluate `<leader>ss` alternatives: snacks.picker and fzf-lua

## Context

`pickers/symbols.lua` is now ~300 lines of custom code: VSCode-style display,
multi-LSP fan-out, gopls path-prefix scrubbing, lua_ls cwd filter, name-only
match highlighting, dual-mode toggle. Most of that exists because telescope's
default LSP-symbol pipeline (`vim.lsp.util.symbols_to_items` →
`make_entry.gen_from_lsp_symbols`) makes opinionated formatting choices that
clash with what we want.

Two pickers in the nvim ecosystem ship with different defaults:
- **snacks.picker** (folke) — modern, tightly integrated picker.
- **fzf-lua** (ibhagwan) — fzf-backed, very fast, polished LSP defaults.

The goal of this plan is **time-boxed evaluation** (≤2 hours) to decide
whether either replaces the custom file end-to-end, replaces the display
layer only, or doesn't justify the swap. Not an immediate migration.

## What we want to keep regardless of picker

These are real requirements; they're either solved already or need to be
re-solved on whatever picker we land on:

1. **Multi-LSP fan-out across all session clients** — search Go symbols from
   a markdown buffer when gopls is alive elsewhere. Neither candidate solves
   this OOTB; both still route through `buf_request_all`. *(Custom code
   needed in either world.)*
2. **gopls name cleanup** — strip `_/Users/.../pkg.` prefix from
   path-qualified names. Server-specific quirk; same shape of fix needed in
   any picker.
3. **lua_ls cwd filter** — drop neovim runtime + mason library symbols.
4. **VSCode-style columns** — kind icon, symbol name, lsp, path. Vertical
   layout with preview below.
5. **Buffer-only toggle** with LSP column hidden — `<leader>ts` flips the
   mode persistently in-session.
6. **Match highlighting on the name column only** — no spurious highlights
   in the path.

## Candidate 1: snacks.picker

### Install (vim.pack one-liner in `lua/plugins.lua`)
```lua
{ src = gh('folke/snacks.nvim') },
```
Then in setup: `require('snacks').setup({ picker = { enabled = true } })`.

### Out-of-the-box behavior to test
- `Snacks.picker.lsp_workspace_symbols()` — confirm column layout, whether
  containerName leaks (gopls), and whether buffer-attached-only is the
  default. Source:
  https://github.com/folke/snacks.nvim/blob/main/lua/snacks/picker/source/lsp.lua
- Display config is declarative (a `format` function returning text+hl
  pairs), which is closer to what we want than telescope's entry_display.

### Custom hooks to evaluate
- `format` callback: replicates our 4-column layout in ~10 lines.
- `confirm` / `actions`: keymap parity with current `<c-space>` fuzzy-refine.
- `live = true`: re-fires the request on prompt change (replaces our
  `finders.new_dynamic`).
- Custom `finder` function: snacks lets you provide raw items, so the
  multi-LSP fan-out (`request_all` from current code) plugs in here.

### Risk
- Adds ~1MB plugin we don't otherwise use. Snacks is a meta-plugin (notifier,
  dashboard, etc.) but `enabled = false` for unused submodules is supported.
- Different keymap conventions; muscle memory carries `<c-space>` over but
  some other defaults may differ.

## Candidate 2: fzf-lua

### Install
```lua
{ src = gh('ibhagwan/fzf-lua') },
```

### Out-of-the-box behavior to test
- `:FzfLua lsp_live_workspace_symbols` — live-re-query workspace symbols.
- Already does icon + name + path columns by default; ask whether they're
  parsed cleanly for gopls, and whether the layout is configurable.
- Source:
  https://github.com/ibhagwan/fzf-lua/blob/main/lua/fzf-lua/providers/lsp.lua

### Custom hooks
- `winopts` and `previewer` give us layout parity (preview-below).
- `actions` for keymap remapping.
- `lsp_live_workspace_symbols` accepts `query_fn` / custom requester? Need
  to read source — if it does, multi-LSP fan-out is a one-liner; if not,
  we'd write a parallel custom command (similar effort to current).

### Risk
- fzf-lua is a heavier dependency than snacks for our use case (we don't
  use any of its other pickers).
- fzf binary required (already installed via Homebrew on this machine; not
  an issue for this dotfiles host).

## Evaluation rubric (score each candidate)

| Criterion | Weight | Notes |
|---|---|---|
| Symbol name renders cleanly for gopls + lua_ls + ts_ls | 3 | Hard requirement |
| Display config in <30 lines (icon, name, lsp, path) | 2 | Replaces ~80 lines of current entry_display setup |
| Multi-LSP fan-out feasible without forking | 3 | If we have to monkey-patch internals, no win |
| Buffer-only toggle stays simple | 2 | Persistent module-level flag should remain trivial |
| Per-keystroke re-query latency feels fine | 2 | `<300ms` round-trip on this dotfiles repo |
| Plugin "blast radius" (other features pulled in) | 1 | Lower is better |

A swap is worth it if total ≥ current implementation by a clear margin,
*and* the gopls/lua_ls quirks are still cleanly solved.

## Test plan

Do this on a **scratch branch** (`evaluate-symbol-pickers`). Do **not** delete
`pickers/symbols.lua` until a winner is confirmed.

### Phase 1 — snacks.picker (≤45 min)
1. Add `folke/snacks.nvim` to `lua/plugins.lua`. Restart nvim, `:lua
   require('snacks').setup({ picker = { enabled = true } })`.
2. Bind `<leader>sX` (temp) to
   `function() Snacks.picker.lsp_workspace_symbols() end`.
3. In a Go+Lua repo (the current dotfiles works — `nvim/lua` for lua_ls,
   any `*.go` directory for gopls), open both languages. Run the picker
   from each language buffer and from a markdown buffer.
4. Inspect: gopls name-with-path? containerName leak? layout?
5. If display works but multi-LSP doesn't, write a custom snacks finder
   using the existing `request_all`/`make_requester` from
   `pickers/symbols.lua` (lift verbatim).
6. Score against the rubric.

### Phase 2 — fzf-lua (≤45 min)
1. Add `ibhagwan/fzf-lua`, restart, `require('fzf-lua').setup({})`.
2. Bind `<leader>sY` (temp) to `:FzfLua lsp_live_workspace_symbols`.
3. Same matrix of buffers as Phase 1.
4. Read `lua/fzf-lua/providers/lsp.lua` to find the requester hook (likely
   `query` callback or `actions` table).
5. Score against the rubric.

### Phase 3 — decision (≤30 min)
- If both score lower than the current setup → keep `pickers/symbols.lua`,
  abandon the branch. Update `plans/smart-symbol-search.md` (or this file)
  with a "stays bespoke" note.
- If one scores higher → migrate `<leader>ss` and `<leader>sS`, delete
  `pickers/symbols.lua`, keep `request_all`/`make_requester` in a smaller
  helper module if multi-LSP needed manual wiring.
- If only the **display** is better in a candidate but multi-LSP fan-out is
  ugly there → **don't migrate**. The current file's complexity is mostly
  the fan-out, not the display.

## Files involved

- `nvim/.config/nvim/lua/plugins.lua` — add candidate as `vim.pack` source.
- `nvim/.config/nvim/lua/keymaps.lua:15-18` — temp bindings during test;
  permanent rebind on migration.
- `nvim/.config/nvim/lua/pickers/symbols.lua` — left alone during eval; only
  modified if a candidate wins.
- This plan file — annotate with results in a "Findings" section after each
  phase, so the reasoning survives a "why didn't we migrate" question 6
  months from now.

## Reference

- Upstream gap: neovim/neovim#24799 (`workspace/symbol` across all clients).
- snacks.picker LSP source:
  `~/.local/share/nvim/site/pack/core/opt/snacks.nvim/lua/snacks/picker/source/lsp.lua`
  (after install).
- fzf-lua LSP source:
  `~/.local/share/nvim/site/pack/core/opt/fzf-lua/lua/fzf-lua/providers/lsp.lua`
  (after install).
- Current implementation: `nvim/.config/nvim/lua/pickers/symbols.lua` —
  the `request_all` / `make_requester` / `convert_symbols` / `clean_symbol_name`
  helpers are picker-agnostic and lift cleanly into either candidate.
