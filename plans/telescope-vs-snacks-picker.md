# Telescope vs snacks.nvim picker — research & swap assessment

> **Status: MIGRATED (2026-07).** The full migration shipped: every picker
> (including the custom `pickers/*.lua` and the multi-LSP `symbols.lua`) now
> runs on snacks.picker, `vim.ui.select` is snacks, and telescope +
> telescope-fzf-native + telescope-ui-select were removed (no more compiled
> `make` dep). Global picker setup lives in `nvim/.config/nvim/lua/picker.lua`;
> the commit series carries `Part-of: telescope -> snacks.picker migration`
> trailers. Frecency is on, and `Snacks.picker.smart()` later landed on
> `<leader><leader>` (2026-07-15). The snacks **explorer** was evaluated
> separately ([§6](#explorer-eval)) and **declined** — we keep nvim-tree, held
> back by window ergonomics rather than migration cost.
>
> **Shrunk to its decision-record core (2026-07-18).** With the migration
> shipped, the code is the source of truth; the full research narrative — the
> tech/perf comparison (old §1, §3), the search-syntax gap analysis (§2), the
> swap assessment (§4), the `<leader>ss` symbols-picker eval (§5 — snacks won,
> the port shipped), the `filter.lua` rebuild spec, and the closed scroll-perf
> investigation (most of §7) — lives in git history:
> `git log -p -- plans/telescope-vs-snacks-picker.md`. What remains below: the
> declined explorer eval ([§6](#explorer-eval)) with its reopen conditions,
> the load-bearing kernels of the scroll-perf hunt ([§7](#scroll-profiling)),
> the live-mode audit ([§8](#live-mode-audit)), and the still-open
> [post-migration TODOs](#post-migration-todo) #9/#10. Section numbers keep
> their original values because code comments and other plans cite them by
> number (`picker.lua` cites §7 twice).

---

<a id="explorer-eval"></a>
## §6 Explorer — nvim-tree vs snacks explorer

Evaluated 2026-07-14 (this closed TODO #1). Verified against the installed
snacks source (`~/.local/share/nvim/site/pack/core/opt/snacks.nvim`), not just
the docs. Condensed to verdict + reopen conditions + key evidence; the full
file-by-file migration walk-through is in git history.

**Verdict: keep nvim-tree — but it's closer than expected, and the cost was
never the reason.** The migration is genuinely cheap: it deletes two plugins
(nvim-tree + nvim-lsp-file-operations), eight highlight overrides, a scroll
clamp, an `aucmd_win` workaround and a cross-file LSP invariant, in exchange
for ~10 lines of filetype string swaps. What holds the line is **window
ergonomics**: a snacks sidebar is floating windows that `<C-h>`/`<C-l>`
(`<C-w>h`/`<C-w>l`) can't reach — the everyday "hop into the tree, hop back"
motion dies — and it has no open-buffer highlight or modified-buffer marker,
both deliberately tuned here, with no snacks equivalent at any amount of
config. Daily-driver regressions, traded for daily-driver gains
(fuzzy-filter-in-tree, multi-select bulk ops plus `<M-a>`
send-selection-to-sidekick, diagnostics, file watching). Taste, not
capability — the same standard the picker migration was held to, and this one
clears it less convincingly.

**Reopen conditions (the live part):** revisit the snacks explorer if it ships
open-buffer / modified-file highlighting, or a focus key for the floating
sidebar that doesn't feel worse than `<C-h>`. Both are plausible. The cheap
experiment that would settle it: snacks is already loaded, so
`Snacks.explorer()` on a spare key runs side by side with nvim-tree, zero
plumbing touched — live with both for a week and let the `<C-h>` reflex
decide.

### Key evidence

- **Import-rewriting on rename is a non-issue — and inverts.**
  nvim-lsp-file-operations structurally cannot work with snacks (it subscribes
  to nvim-tree/neo-tree/triptych events; snacks emits none), but snacks does
  rename natively: `explorer_rename`/`explorer_move` route through
  `Snacks.rename.rename_file()`, which sends `workspace/willRenameFiles`,
  applies the edit, then notifies `didRenameFiles`. A migration *deletes* the
  plugin — retiring the silently-desyncable two-halves invariant between
  `lsp.lua` and `filetree.lua`. The only real loss is gopls' `didCreate`
  (auto package clause on a new `.go` file): no server we run implements
  `willCreateFiles`/`willDeleteFiles`, and gopls has no `willRename` at all
  (golang/go#51037), so neither tool gives Go import rewriting.
- **The migration is cheaper than it looks.** Our sidebar machinery keys on
  the `NvimTree` filetype across nine files, but snacks' picker windows are a
  virtual list in floats over unnamed scratch buffers, so the bug classes our
  fixes dodge cannot recur — the scrolloff fix, the WinScrolled clamp, most of
  the `session.lua` buffer-name wipe, and the `NvimTreeGit*HL` overrides get
  deleted, not ported. Net, the config gets smaller.
- **nvim-tree is not rotting.** "Stable, no new major features," but v1.15
  through v1.18 shipped in 2026 (~50 commits), and its experimental
  `session_restore_nvim` (nvim-tree #3343) would obsolete our `session.lua`
  hack upstream.

### Feature comparison

| Feature | nvim-tree (today) | snacks explorer |
|---|---|---|
| Model | classic split sidebar | a picker in disguise (floating list over a non-focusable split box) |
| Git status | yes (right-aligned `M`/`S`/`U` letters) | yes (plus aggregate status on dirs, `]g`/`[g` jump) |
| LSP diagnostics | off in our config | yes (`]d`/`[d`, `]e`/`[e`) |
| Modified-buffer marker | yes | no |
| Open-buffer highlight | yes (`NvimTreeOpenedHL`) | no |
| Fuzzy filter in the tree | weak (`live_filter`) | strong — it *is* the picker input; `<leader>/` greps the dir |
| Multi-select bulk ops | no | yes (`<Tab>` select, then `m`/`c`/`d`) |
| Send files to sidekick | no | yes — `<M-a>` inherited free, on a multi-selection |
| Trash on delete | yes | yes, but silent hard-delete fallback if no trash cmd resolves [1] |
| File watching | no | yes |
| Preview pane | no | yes (`P`) |
| Import-rewrite on rename | via a second plugin | native |
| Import-rewrite on create/delete | yes, but no server uses it | no |
| File nesting | no | no |
| `<C-h>`/`<C-l>` split-nav reaches it | yes | no [2] |
| Plugins required | 2 | 0 (snacks already loaded) |

[1] macOS resolves `/usr/bin/trash`, so we're fine — but `explorer/actions.lua`
degrades to `vim.fn.delete(path, 'rf')` silently, not loudly.

[2] The load-bearing con — see the verdict above.

---

<a id="scroll-profiling"></a>
## §7 Picker scroll performance — kept kernels + open residual

The 2026-07-13/14 hunt for "holding `<C-j>` in a picker feels sluggish"
(TODO #7) is **closed, no code changed**. Condensed here to the three
load-bearing records; the full investigation — the preview-mechanism
comparison, the headless per-row benchmarks, the telescope scroll-asymmetry
read, and the struck-through wrong hypotheses — is in git history.

**The answer was the premise, not the renderer.** `<C-j>` moves one row per OS
key repeat (~30ms at macOS's maxed "Fast" setting, ~33 rows/s), so traversal
is bounded by the input rate — no per-tick saving could ever have fixed it.
Stock `<C-d>`/`<C-u>` (`list_scroll_down`/`list_scroll_up`) scroll half a
window per press (~26 rows at our `height = 0.9`) for the cost of a single
tick; documented in GUIDE.md's picker keymap table, and that's the entire
fix. Along the way, three suspects were each verified as real mechanisms and
ruled out as the cause: the preview (`<a-p>` off, still sluggish), the Lua
list render (every scroll tick past the window edge does re-render every
visible row, but at ~0.017ms/row that's ~0.9ms/tick at height 0.9 — too small
to feel), and the forced flush (below).

### The forced flush is deliberate — do not "fix" it

(This is what `picker.lua:19`'s height comment points at.) The dirty branch of
`core/list.lua:render()` rewrites the whole list buffer and then calls
`win:redraw()` = `nvim__redraw({ valid = false, flush = true })`
(`snacks/win.lua:509-515`) — a full-window invalidate plus a synchronous UI
flush, every tick. A/B'd in the real terminal (2026-07-14): **B (no-op
`Snacks.win.redraw`) is *slower*-feeling than A (stock)** — with key repeat
and with trackpad scroll alike. The forced flush is what puts each tick on
screen immediately; take it away and nvim defers the repaint to its own idle
point, so the list stalls under a held key and catches up in a lurch. snacks
is buying responsiveness with it. Do not neuter it locally, and do not file
it upstream.

### Profiler harness (`<leader>tp`)

Standing tool left behind by the hunt (see `picker.lua:278`'s comment):

- `<leader>tp` → `Snacks.toggle.profiler():map('<leader>tp')`, bound in
  `picker.lua` after `setup()` (needs the `Snacks` global). Stopping opens a
  picker over the trace; close it before the next run or it lands in the next
  trace.
- The default `filter_fn` drops every `_`-prefixed function — most of the hot
  path (`_render`, `_move`, `_scroll`) — so start via
  `Snacks.profiler.scratch()` with `filter_fn = { default = true }` to split
  render-internal from move-internal.
- Starting mid-session **does** instrument already-loaded modules
  (`profiler/core.lua` walks `package.loaded`).
- Blind to C-side work: decoration-provider highlighting and the
  `win:redraw()` screen paint never appear. Treat *relative* Lua differences
  as signal, never absolute ms — instrumentation inflates hot tiny functions.
- "Zero overhead when off" holds only until the first run: `stop()` doesn't
  un-wrap modules, so a profiled *run* leaves residue until nvim restarts.
  The bind is free to land permanently.

<a id="scroll-residual"></a>
### Open residual: the intermittent hang

Not explained, and honestly recorded rather than waved off: **both A and B
"sometimes hang"** during a scroll. Since it survives the no-op-redraw patch,
it is not the flush, and since it survives `<a-p>`, it is not the preview. It
is therefore *not* the same phenomenon as the key-repeat-bound slowness above
— that one is fully explained and has a fix.

Not chased further because `<C-d>`/`<C-u>` makes the whole area a non-problem
in daily use (2026-07-14 decision: **parked, not solved**). If it resurfaces
and is worth picking up, the untested candidates, in order:

- **the matcher/finder still streaming.** A 16k-file finder runs async; ticks
  that land while items are still arriving contend with match+sort work.
  Test: wait for the count to settle *completely*, then scroll. If the hang
  only happens early, this is it.
- **`frecency`** (we enable it) adds per-item scoring at match time — an A/B
  with it off is one line in `picker.lua`.
- **GC pauses.** Every dirty tick allocates a fresh line table + extmarks;
  `collectgarbage('count')` sampled across a scroll would show it.

---

<a id="live-mode-audit"></a>
## §8 Live mode (`<c-g>`) — where it actually pays

Closed TODO item #6 (2026-07-14). Source-verified against the installed
snacks, plus two headless probes. **Outcome: one picker gains a real
capability (`<leader>sf`), it needs no config, and every other picker we bind
is a fixed list where live mode is meaningless.** The deliverable was a
GUIDE.md correction.

### The mechanism (this is the part that was misunderstood)

A snacks filter carries **two** queries, not one:

- `filter.search` — feeds the **finder** (the external tool: `rg`, `fd`, an
  LSP request).
- `filter.pattern` — feeds the **matcher** (snacks' in-Lua fzf port).

`opts.live` decides only *which one the prompt box is currently editing*
(`core/input.lua:36`, `:83-91`, `:197`). `<c-g>` (`toggle_live`,
`actions.lua:745`) flips that. The other query is **not discarded** — it stays
in the filter, keeps applying, and is rendered to the left of the prompt
(`core/input.lua:133`). So live and fuzzy **stack**, and `<c-g>` is
freeze-then-refine in *both* directions, not a one-way "freeze the results".

The consequence that matters: **` -- <args>` passthrough is live-only.** Both
`source/grep.lua` and `source/files.lua` build their command by calling
`Snacks.picker.util.parse(filter.search)` — `filter.search`, never
`filter.pattern`. In fuzzy mode the prompt writes to `pattern`, `search` stays
empty, and the flags never reach the tool; they just become more text for the
matcher to fuzzy-match. Verified headlessly in this repo:

| picker mode | prompt | result |
|---|---|---|
| `files`, live (`<c-g>`) | `conf -- -e lua` | runs `fd -e lua conf` → 1 item (`configs.lua`) |
| `files`, fuzzy (default) | `conf -- -e lua` | fuzzy-matches the string against the whole file list → 137 items |
| `files`, live + a kept fuzzy pattern | search `conf`, pattern `lua$` | fd returns 6, the matcher filters to 1 — both queries applied |

### Per-picker verdict

Ten built-in sources set `supports_live` (`picker/config/sources.lua`):
`explorer`, `files`, `gh_issue`, `gh_pr`, `git_grep`, `git_log`, `grep`,
`grep_buffers`, `grep_word`, `lsp_workspace_symbols`. Note it is
`lsp_workspace_symbols`, **not** `lsp_symbols` — TODO #6 named the wrong one,
and the distinction is right: document symbols are a fixed list.

| our picker | source | live? | `<c-g>` verdict |
|---|---|---|---|
| `<leader>sg` | `grep` | live by default | already used — toggle to fuzzy-refine an rg result set |
| `<leader>sf` | `files` | fuzzy by default | **the find.** `<c-g>` makes the prompt an `fd` regex over the path and unlocks ` -- ` args (`-e lua`, `-g '*.go'`, `--changed-within 1d`). Fuzzy can *approximate* "only `.lua`" (`lua$`); only live can *ask* for it |
| `<leader>ss` | custom (`pickers/symbols.lua`) | live by default | already live + `supports_live` since the migration; freezes the LSP result set for fuzzy refinement |
| `<leader>sd` | `lsp_symbols` | n/a | fixed list — the LSP request doesn't depend on the query. Correctly has no `supports_live` |
| `<leader>sb` / `<leader>s/` | `lines` | n/a | fixed list (the buffer's lines) |
| `<leader>sm`, `<leader>bb`, `<leader>st`, `<leader>sk`, Go targets | custom `pickers/*.lua` | n/a | all static finders — the item set doesn't depend on the prompt, so a re-query would return the same list. **None should set `supports_live`** |

Unbound built-ins that do support live (`git_grep`, `git_log`, `grep_buffers`,
`grep_word`, `gh_*`, `explorer`) are a separate question — whether to bind
those pickers at all, not whether to give them live mode. Not pursued here.

---

<a id="post-migration-todo"></a>
## Post-migration TODO

Deferred follow-ups from the migration (decided during implementation review,
2026-07). Items 1, 3, 4, 5, 6 and 7 are **closed** — their records were pruned
2026-07-18 and live in git history; item 1's residue is [§6](#explorer-eval)'s
reopen conditions (revisit the snacks explorer if it ships buffer/modified
highlights or a focus key), and item 7's is [§7](#scroll-profiling). Items 2
(review snacks' default picker keymaps for inspiration) and 8 (mine
linkarzu's snacks-picker post for setup ideas) were hoisted to
`plans/README.md`'s TODO checklist. Still open here:

9. **Progressive narrowing — make `<c-g>` universal (a corpus stack).** *(This
   item was rewritten 2026-07-14; the first draft asked for "freeze the results
   and filter them," which is what `<c-g>` already does. What follows is the
   part that's actually missing.)*

   **The gap is not filtering — it's re-anchoring.** In a fixed-list picker
   you're already fuzzy-filtering the items, and the matcher ANDs
   space-separated terms, so you narrow by *appending*: `foo`, then `foo bar`,
   then `foo bar !test`. That works. What you can't do is **bank** a narrowing
   and start a clean query against what survived. So the wanted primitive is:

   > `<c-g>` = take what's on screen *right now* (the matched subset), make it
   > the picker's new item set, clear the prompt.

   Repeat to drill down. Note this makes the keybinding's *behavior* uniform
   even though the mechanism differs: in grep, `<c-g>` already freezes rg's
   output and hands you an empty fuzzy prompt over it ([§8](#live-mode-audit));
   in a fixed-list picker there is no tool to freeze, so we freeze the matched
   subset instead. Same sentence describes both. Every picker gains `<c-g>`.

   **Be honest about the payoff: it is ergonomics, not capability.** For a
   fixed-list picker, `foo` → `<c-g>` → `bar` lands in nearly the same place as
   typing `foo bar`. What you gain is a banked query instead of an
   ever-growing pattern string, a clean prompt, ranking by the *new* term
   rather than the accumulated one, and repeatability. Worth building for the
   workflow, not for a missing filter.

   **Sketch.** Override the `toggle_live` action: if `picker.opts.supports_live`,
   defer to the stock action; otherwise snapshot `picker:items()` (the matched
   set), swap in a static finder over the snapshot, reset `filter.pattern` to
   empty, re-find. Do it *in place* so layout, format, preview, multi-select and
   `confirm` all survive. Push each snapshot on a stack and bind a companion key
   to pop — without an undo, one stray `<c-g>` traps you in a subset with no way
   out but reopening the picker. Open questions: what `<leader>sr` (resume)
   restores; whether the banked queries show in the title; and the one real
   collision — in **grep**, should a second `<c-g>` toggle back to live (stock)
   or push a corpus (new)? Those are two different meanings on one key.

   Check upstream first: snacks may have a primitive for this, and if not, it's
   a plausible feature request.
10. **Re-grep within the surviving files (tool-side drill-down)** — the one
    thing item 9 still won't do, split out because it needs the *finder*, not
    the matcher. Grep `foo` and you hold 200 lines *that contain foo*. Now ask
    "which of those files also contain `bar`?" — impossible: `bar` sits on a
    line ripgrep never emitted, and the matcher can only test the strings it was
    handed ([§8](#live-mode-audit): the finder decides what exists). Same for any
    second query with real rg semantics — case sensitivity, word boundaries,
    multiline, `-A`/`-B` context.

    Wanted: collect the distinct paths from the current result set and hand them
    back to `rg` as its corpus for a fresh query. The `grep` source takes `dirs`;
    a *file list* needs either `args` or a custom finder along the lines of
    `grep_buffers`. Decide whether the corpus is all results or just the
    multi-selection. Today's workaround is `<C-q>` → quickfix → re-search it,
    which is lossy and leaves the picker.

## Sources

Sources for the pruned sections (§1-§5 and the cut bulk of §7) live with them
in git history. What backs the kept sections:

Scroll/render mechanism (§7) — read firsthand, 2026-07-13/14:

- snacks: `picker/core/list.lua` (`_move`/`render`, the dirty branch, and
  `state.height` — the buffer *is* the viewport), `picker/actions.lua`
  (`list_down`), `config/defaults.lua:248,258` (`<C-d>`/`<C-u>`),
  `snacks/win.lua:509-515` (`redraw` = `nvim__redraw({ valid = false,
  flush = true })`)
- telescope (fresh clone, for the cross-tool claim): `pickers.lua`
  (`set_selection` — two rows re-highlighted, then `nvim_win_set_cursor`;
  the pre-filled 250-line results buffer). Also grepped its whole `lua/` tree
  for `nvim__redraw` / `vim.cmd('redraw')` / `:redraw` — **zero hits**, the
  load-bearing negative result.
- upstream report of the same symptom ("holding down J or K" sluggish), where
  folke's first diagnostic is the `<a-p>` preview-off test we ran:
  <https://github.com/folke/snacks.nvim/discussions/950>

Live-mode audit (§8) — read firsthand, 2026-07-14:

- snacks: `picker/core/input.lua` (the `search` vs `pattern` split — `:36`,
  `:83-91`, `:133`, `:197`), `picker/actions.lua:745` (`toggle_live`),
  `picker/config/defaults.lua:250` (`<c-g>`), `picker/config/sources.lua`
  (which sources set `supports_live` / `live`), `picker/source/files.lua`
  (`get_cmd` → `util.parse(filter.search)` — why ` -- ` is live-only)
- our side: `lua/picker.lua` (sources), `lua/keymaps.lua` (`<leader>s*`),
  `lua/pickers/symbols.lua` (already `live` + `supports_live`)

Explorer eval (§6):

- snacks explorer docs: <https://github.com/folke/snacks.nvim/blob/main/docs/explorer.md>
  (+ read firsthand at the installed commit: `explorer/actions.lua`,
  `explorer/tree.lua`, `rename.lua`, `layout.lua`, `win.lua`,
  `picker/core/list.lua`, `picker/source/explorer.lua`, `picker/format.lua`,
  `picker/config/{defaults,sources,init}.lua`)
- nvim-lsp-file-operations (supported explorers = nvim-tree, neo-tree,
  triptych): <https://github.com/antosha417/nvim-lsp-file-operations>
- snacks rename + explorer issues:
  [#2709](https://github.com/folke/snacks.nvim/issues/2709) (rename with an
  explorer + vtsls, closed not-planned),
  [#2839](https://github.com/folke/snacks.nvim/issues/2839) (deprecated
  `client.request_sync`, breaks on nvim 0.13) +
  [#2862](https://github.com/folke/snacks.nvim/pull/2862) (fix),
  [#1965](https://github.com/folke/snacks.nvim/issues/1965) (thin docs for
  action/keymap overrides), [#793](https://github.com/folke/snacks.nvim/issues/793)
  (original explorer feature issue)
- LSP fileOperations capability sources: ts_ls `src/lsp-server.ts`,
  rust-analyzer `crates/rust-analyzer/src/lsp/capabilities.rs`, lua_ls
  `script/provider/provider.lua`, gopls `gopls/internal/server/general.go` +
  <https://github.com/golang/go/issues/51037> (gopls has no `willRename`)
- nvim-tree activity + upstream session restore:
  <https://github.com/nvim-tree/nvim-tree.lua/issues/3343>
