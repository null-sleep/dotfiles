# Telescope vs snacks.nvim picker — research & swap assessment

> **Status: MIGRATED (2026-07).** The full migration shipped: every picker
> (including the custom `pickers/*.lua` and the multi-LSP `symbols.lua`) now
> runs on snacks.picker, `vim.ui.select` is snacks, and telescope +
> telescope-fzf-native + telescope-ui-select were removed (no more compiled
> `make` dep). Global picker setup lives in `nvim/.config/nvim/lua/picker.lua`;
> the commit series carries `Part-of: telescope -> snacks.picker migration`
> trailers. Frecency is on; the `smart` picker was deliberately deferred — see
> [Post-migration TODO](#post-migration-todo). The snacks **explorer** was
> evaluated separately ([§6](#explorer-eval)) and **declined** — we keep
> nvim-tree, held back by window ergonomics rather than migration cost. The
> research below is kept as the decision record.

Research doc comparing our current **telescope** stack against **folke's
snacks.nvim picker**, with a focus on (1) the search-syntax / file-filter gap
that motivated this, (2) what each is built on and how they perform, (3) each
picker's sales pitch + features we might not know, and (4) whether there's a
*serious blocker* to swapping. **Not** a migration plan — see "Verdict" for
where an actual migration would get mapped out.

This is the **single tracking doc** for the whole picker effort (telescope →
live-grep-args/snacks). Two narrower plans that used to circle this topic have
been folded in here:
- The glob-filter friction in the (now removed) `pickers/filter.lua` — static
  Lua presets, couldn't refine filters mid-grep — see
  [§2](#search-syntax-filtering) and the
  [rebuild design](#filter-picker--rebuild-design).
- The `<leader>ss` symbols-picker eval (snacks vs fzf-lua) — see
  [§5](#symbols-picker-eval).

The old standalone `filter-picker-rethink.md` and `symbol-picker-alternatives.md`
have been removed; their content lives below.

## Decision (current thinking)

Framed around the actual question: **assuming we add telescope-live-grep-args,
is migrating to snacks a real win?** Two priorities set this: `field:value`
filters and `file:line:col` jump syntax (snacks-only) are **not** wanted, and
the migration cost is treated as **low** (AI can do the `symbols.lua` port).

**+lga removes the forcing function.** The original pain was the *file-filter*
half — "grep only in `*.go`," changeable mid-search, refine the filter live.
telescope-live-grep-args closes that entirely (`-g`/`-t`/`--glob` in the prompt
+ freeze-then-fuzzy-refine). With that solved, migrating drops from "fixes a
pain point" to a **discretionary upgrade**.

**What's genuinely left as the pro-snacks case** (after discounting `field:` and
`file:line:col`):
1. **Frecency + the `smart` picker** — the one you'd feel daily: a single
   frecency-ranked buffers + recent + files list (`<leader><space>`). Telescope
   needs a second plugin (`telescope-frecency` + SQLite) and still doesn't give
   the unified `smart` source cleanly. This is the strongest remaining win.
2. **Suite coherence** — migrating fully puts `explorer`, `git_*`, `gh_*`, and
   our pickers on one config/keymap/layout language instead of telescope + N
   extensions. Value is consistency, not any single feature.
3. **Two dotfiles-specific structural wins** — drop the compiled `fzf-native`
   `make` step (one less cross-machine build dep), and bet on the
   actively-developed project (telescope's cadence has slowed; snacks is very
   active). At low port cost, longevity is a legitimate tiebreaker.

Performance is **not** on this list — negligible at our repo sizes (see §1).

**Honest counterweight:** "AI makes the port cheap" lowers the *writing* cost,
not the *ownership* cost. We'd still own/maintain the ported `symbols.lua`
(multi-LSP fan-out, gopls scrubbing, lua_ls cwd filter, dual-mode toggle — all
still custom), eat the `<leader>s*` muscle-memory + GUIDE.md/keymap doc churn,
and retrain the grep live-mode default (`<c-g>`). None of the remaining wins is
a blocker — they're conveniences.

**Recommendation — coexist first, don't go all-or-nothing.** snacks and
telescope run side by side (both just Lua). Highest value-per-effort path:

1. Add **telescope-live-grep-args** and rebind `<leader>sg` — closes the actual
   pain today, near-zero risk.
2. Bind **only** snacks `smart` + `explorer` (leave everything else on
   telescope, don't touch `symbols.lua`) — harvests the two wins we'd actually
   feel without the one real cost.
3. Live with it, then decide on a full migration only if those daily wins land.

The decision is now **taste + longevity, not capability**: worth migrating fully
only if a frecency-ranked `smart` picker + explorer genuinely appeal as daily
drivers; otherwise +lga is the stopping point.

## Status: `pickers/filter.lua` removed

`nvim/.config/nvim/lua/pickers/filter.lua` has been **deleted** to unencumber
the picker design ahead of a live-grep-args/snacks decision. `<leader>sf` /
`<leader>sg` now call plain `telescope.builtin.find_files` / `live_grep`
(hidden-file inclusion + `.git/`/`node_modules/` exclusion still come from the
global `require('telescope').setup` config in `plugins.lua`, so no default
behavior was lost). `<leader>sF` is gone. Its behavior is captured below as a
rebuild spec, followed by the
["rebuild it better" design](#filter-picker--rebuild-design).

### Removed: `filter.lua` functional spec (for a future rebuild)

What the deleted 163-line module did, so it can be reconstructed from this doc
alone:

- **Presets** — a static ordered Lua table, each with a session-lifetime
  `enabled` flag (default off, reset on nvim quit):
  - `go_src = { '*.go', '!*_test.go', '!vendor/*' }`
  - `frontend = { '*.ts', '*.tsx', '!*.test.*' }`
  - `protos = { '*.proto' }`

  (`!`-prefixed globs are ripgrep excludes.)
- **`<leader>sF` toggle picker** — vertical layout, no previewer:
  - `<Tab>` flips the highlighted preset's `enabled` in place — the finder is
    rebuilt so the `[x]`/`[ ]` checkbox updates live, and the cursor row is
    saved/restored so it doesn't jump to row 1.
  - `<CR>` confirms and persists the current toggle state.
  - `<Esc>` reverts every toggle to the snapshot taken when the picker opened,
    via the `close_windows`-override + `need_restore`-flag pattern (still
    documented in GUIDE.md → "Picker state with revert-on-cancel", shared with
    `pickers/theme.lua`).
- **Wrappers** that `<leader>sf` / `<leader>sg` routed through:
  - `M.get()` collected the globs of all enabled presets (or `nil` if none).
  - `live_grep` received them as `glob_pattern`.
  - `find_files` built a custom command
    `rg --files --hidden --glob '!.git/' --glob '!node_modules/' [--glob <g>…]`
    — a custom `find_command` bypasses telescope's `file_ignore_patterns`, so
    `.git/`/`node_modules/` had to be re-excluded explicitly.
  - No preset active → both fell back to the plain builtins (identical to the
    current post-removal behavior).

<a id="filter-picker--rebuild-design"></a>
### Filter picker — rebuild design (if we rebuild instead of migrating)

The design worked out before the removal, for a *better* preset picker than the
deleted one — kept here in case we rebuild presets rather than adopting
live-grep-args / snacks inline glob syntax (`foo -- -g '*.go'`), which would
obsolete presets entirely (the thrust of this doc).

**The two friction points to fix:**
1. **Static presets in Lua** — adding/changing a preset meant editing Lua and
   reloading. The preset list is plain data (names + globs); shouldn't require
   code changes.
2. **Filters only settable before `<leader>sg`** — once in `live_grep` there
   was no way to refine the active filter set without escaping, re-toggling,
   re-grepping.

**1. Externalize presets.** Move the `filter_sets` table out into a config
file. Options: `filters.toml` (clean, but Neovim ships no TOML parser),
`filters.json` (`vim.json.decode`, zero-dep but ugly to hand-edit), or
`pickers/filters_data.lua` (pure-data Lua table). **Recommendation:**
`filters_data.lua` — zero parsing cost, syntax highlighting, comments allowed.

**2. Dynamic reload.** Read-on-open (re-read the file each `M.pick()` /
`M.live_grep()` call) beats an autocmd watcher — file I/O is negligible at
picker-open frequency. Preserve the per-preset `enabled` flag across reloads in
a separate in-memory table keyed by preset name; merge after reload (new preset
→ default `enabled = false`; removed preset → drop its state).

**3. Filter from within `live_grep`.** Attach a mapping (e.g. `<C-f>`) in
`M.live_grep()` that: (a) captures the current prompt via
`action_state.get_current_picker(bufnr):_get_prompt()`, (b) closes live_grep,
(c) opens `M.pick()`, (d) on close (confirm *or* revert) reopens
`builtin.live_grep({ default_text = saved_prompt, glob_pattern = … })`. Verify
`default_text` actually populates the *search term* in live_grep (not just the
buffer). Always reopen live_grep even on Esc — the user's intent was to stay in
grep, just check filters. Cursor position in the results list is not preserved
(acceptable). Skip the more-ambitious in-place finder-swap (`picker:refresh()`
with a new `glob_pattern` while the window stays open) — fragile across
telescope versions, and the close/reopen flicker is barely noticeable.

**Open questions:** a "clear all filters" shortcut? negative (exclude) toggles
without removing a preset? The same dynamic mechanism applies to `<leader>sf`
(find_files) for free, since it also routed through `M.get()`.

**Alternatives considered:** switch to fzf-lua / snacks (native inline glob
filtering) — obsoletes the preset system entirely, larger migration but
eliminates the problem rather than improving the workaround (this doc's main
thrust). Or telescope-live-grep-args for ad-hoc globs *alongside* presets —
adds a plugin dep and creates two ways to filter; not recommended as a pair.

## TL;DR

- **Your instinct is right, and it's not a skill gap.** Stock telescope really
  is fuzzy-only. The fzf operator syntax (`'exact`, `^prefix`, `suffix$`,
  `!negate`, `|OR`) only exists once you add **telescope-fzf-native**, and even
  then it filters the *displayed lines*, not the ripgrep search. True "grep
  only in `*.go`" needs picker opts (`type_filter`/`glob_pattern`) or the
  **telescope-live-grep-args** extension — none of which you currently have
  installed. The (now removed) `pickers/filter.lua` was essentially a
  hand-rolled substitute for live-grep-args.
- **Snacks ships all of that in the box, in pure Lua, zero extensions:** fzf
  syntax + a `field:value` filter syntax + `-- <rg args>` passthrough +
  frecency. This is the single strongest reason to look at it.
- **What they're built on:** telescope = Lua + plenary async, default matcher
  is a pure-Lua **fzy** port; fzf-native is an optional **compiled C** fzf
  binding. Snacks = zero-dependency, its matcher is a pure-Lua **port of fzf's
  scoring**, streaming/async by a custom 1 ms-yield coroutine scheduler. On
  huge repos snacks/fzf-lua stay snappier; telescope's known weak spot is
  100k+ file trees.
- **Serious blocker to swap? No.** Snacks' custom-picker API is *lighter* than
  telescope's, and it has built-in equivalents (or better) for every picker we
  run. The real cost is **porting effort**, concentrated almost entirely in
  the ~712-line multi-LSP `symbols.lua`. Everything else (gitstatus, buffer,
  theme, keybindings, sidekick send) ports cleanly. We already have snacks
  installed as a dependency, so there's no new plugin to add.

---

## 1. What each is built on + performance

### Telescope

- **Pure Lua**, hard-depends on **plenary.nvim**. Needs `ripgrep` for
  grep/find. Requires Neovim ≥ 0.11.7 + LuaJIT.
- **Async = plenary coroutines, not OS threads.** The picker main loop is an
  `async.void` coroutine that yields to Neovim's event loop via
  `vim.schedule`, with a debounce. External `rg`/`fd` run as `plenary.job`
  subprocesses.
- **Pipeline:** finder (static table or streaming job) → sorter
  (`scoring_function` + `filter_function` + `highlighter`, lower score = better,
  negative = filtered) → previewer.
- **Default sorter = fzy**: a pure-Lua port of John Hawthorn's fzy algorithm
  (favors consecutive matches, word/slash/camelCase/dot boundaries). It's a
  subsequence matcher — **no operator syntax**.
- **telescope-fzf-native** is a **compiled C port of fzf's algorithm** bound
  over LuaJIT FFI (that's the `make` build step we compile in `plugins.lua`).
  When loaded it *overrides* fzy entirely and adds (a) faster C scoring, (b)
  fzf extended-search syntax in the prompt.
- **Single-threaded / main-loop bound.** Sorting + entry processing run in Lua
  on the one main loop (cooperatively yielded). Only the finder subprocess and
  (if installed) the C sorter run off it.
- **Large-repo weak spot:** documented as markedly slower than fzf-lua/snacks
  on 100k+ file trees (telescope#2884) because entries are streamed into Lua
  tables and sorted on the main loop. Mitigations: fzf-native, `fd`/`rg`
  finder, limit previews.

### Snacks picker

- **From-scratch, zero-dependency.** No telescope, no plenary, no fzf/fzf-lua.
  One module of folke's larger snacks.nvim QoL suite (which we already load).
- **Pipeline:** finder (`core/finder.lua`, plain table fast-path *or* async
  `fun(cb)` producer streaming items; `rg`/`fd`/`find` spawned as async uv
  procs) → matcher (`core/matcher.lua`) → sorter (default
  `score:desc, #text, idx`).
- **Matcher is pure Lua and an explicit port of fzf's scoring** —
  `core/score.lua` literally says *"port of the scoring logic from fzf"*, same
  constants (`SCORE_MATCH`, `BONUS_BOUNDARY`, `BONUS_CAMEL_123`, …). Fuzzy
  match does a forward scan + backward re-scan to find the *best* alignment,
  not the first. *(Verified firsthand in the clone.)*
- **How it stays fast** (all cooperative single-thread, not uv workers):
  - Custom coroutine scheduler yields every **1 ms** so the UI never blocks;
    finder + matcher run **concurrently** and stream (matcher resumes as items
    arrive).
  - **top-k first** — previously-visible items re-scored first for instant
    feedback.
  - **Subset optimization** — typing another char only re-tests items that
    didn't already match (disabled when a negation is present).
  - **Entropy ordering** — AND-terms tested rarest-first (fail fast), OR-terms
    likeliest-first.
  - `collectgarbage("stop")` during the find phase; empty-pattern and
    single-pattern fast paths.
- **Frecency built in** (`core/frecency.lua`): Mozilla-style exponential
  decay, 30-day half-life, persisted to SQLite (KV `.dat` fallback). Opt-in
  (`frecency = false` default). Plus `cwd_bonus` and a filename bonus.

### Performance bottom line

Both do the actual fuzzy scoring in a single Lua thread — the difference is
**architecture, not threads**. Snacks' streaming/incremental matcher + subset
+ top-k + entropy tricks make it feel snappier out of the box, and it needs no
compiled extension to get there. Telescope closes most of the raw-speed gap
*only* once fzf-native's C sorter is loaded (which we do have). On very large
repos (100k+), community consensus favors snacks/fzf-lua; for our repo sizes
the difference is unlikely to be dramatic either way, but snacks won't need
the `make`-compiled fzf-native to stay fast.

---

<a id="search-syntax-filtering"></a>
## 2. Search syntax / filtering — the actual pain point

This is the crux of the whole question, so it gets the most detail.

### What stock telescope gives you (what we have today)

We load `telescope-fzf-native` (compiled) + `ui-select`, **not**
live-grep-args, frecency, or egrepify. So today:

- **fzf operator syntax works in the prompt** (because fzf-native is loaded):

  | Token | Match | Example |
  |---|---|---|
  | `sbtrkt` | fuzzy (default) | `confg` → `config` |
  | `'wild` | exact substring | `'main` |
  | `^src` | prefix | starts with `src` |
  | `.go$` | suffix | ends with `.go` |
  | `!test` | negation | exclude `test` |
  | `foo bar` | AND | both terms |
  | `\|` | OR | `^core go$ \| rb$` |

- **But the load-bearing caveat:** in `live_grep`, ripgrep does the content
  search *first*; fzf-native syntax then only filters the `file:line:text`
  lines rg already returned. So `.go$` in a live_grep prompt matches the end of
  the *displayed line*, **not** "only search `.go` files." It's a fragile
  proxy.
- **True file-type restriction** in telescope needs one of:
  - picker opts at launch — `live_grep{ type_filter='go' }` or
    `live_grep{ glob_pattern='*.go' }` (fixed per-invocation, can't change
    mid-search). *This is exactly what `pickers/filter.lua` automated* by
    building `--glob` args from toggle presets.
  - the **telescope-live-grep-args** extension — type raw rg args live:
    `"my term" -g *.go` / `"foo" --type lua` / `"foo" -g '!*_test.go'`. This is
    the community-standard fix for our exact complaint, and **we don't have it
    installed.**

So: part of the "telescope only fuzzy-matches" feeling is that stock telescope
*is* fuzzy-only, and part is that we never added live-grep-args — our
`filter.lua` was a partial hand-rolled version of it (presets instead of
free-form, and only settable before the grep starts, which is precisely the
friction the [rebuild design](#filter-picker--rebuild-design) is about).

### What snacks gives you out of the box

Everything above, in pure Lua, **no extensions**. Verified against
`core/matcher.lua`:

| Token | Meaning |
|---|---|
| `foo bar` | AND (space-separated) |
| `foo \| bar` | OR |
| `!foo` | negation (non-fuzzy substring) |
| `'foo` | exact substring |
| `'foo'` | exact **word** (boundaries) |
| `^foo` | exact prefix |
| `foo$` | exact suffix |
| `field:value` | **field-scoped filter** (field ≥ 2 chars) |
| `file:12:5` / `file:12` | file position (jump to line/col) |
| `… -- <args>` | raw args passed to the underlying `rg`/`fd` |

Two of these are things telescope has **no OOTB answer** for:

1. **`field:value` filters.** `file:foo` matches only the item's `file` field;
   `text:foo` only the `text` field. Combine freely:
   `file:lua$ 'function` = "path ends in `.lua` AND contains exact substring
   `function`". Press `<a-d>` (inspect) in the picker to see an item's fields.
   This is the "richer than fuzzy" querying you were missing — and it's a
   *general* mechanism, not a grep-only hack.
2. **`-- <rg args>` passthrough** — the ergonomic "grep only in `*.go`" live:
   - `myFunc -- -tgo` (ripgrep `--type go`)
   - `myFunc -- -g=*.go`
   - `myFunc -- --glob=!*_test.go` (exclude)

   This is live-grep-args, built in.

Plus per-source config opts (`ft`, `glob`, `hidden`, `ignored`, `exclude`,
`dirs`) if you'd rather bind a preset key like the old filter toggles.

**One wrinkle to know:** the `grep` source defaults to `live = true` — every
keystroke goes straight to `rg` (regex), so the *fuzzy* syntax above applies to
the `files` picker and to grep *after* you hit `<c-g>` (`toggle_live`) to
buffer results into the Lua matcher. This trips people up ("fzf syntax isn't
working") — they were in live mode. Worth internalizing before judging it.

### The gap, explicitly: stock telescope vs. +live-grep-args vs. snacks

The question this doc keeps circling is "how much of the snacks advantage is
just *missing telescope plugins*, and how much is genuinely telescope-can't?"
This table answers it. **"stock"** = what we run today (telescope + fzf-native +
ui-select). **"+lga"** = the same, plus adding **telescope-live-grep-args**
(one plugin, no build step). **snacks** = out of the box.

| Capability | stock | +lga | snacks |
|---|:--:|:--:|:--:|
| Fuzzy subsequence matching | yes | yes | yes |
| fzf operators in prompt — `'exact` `^pre` `suf$` `!neg` OR [1] | yes | yes | yes |
| Live raw `rg` args in the grep prompt (`-g`/`-t`) | no | yes | yes |
| True "grep only in `*.go`", changeable mid-search [2] | no | yes | yes |
| Refine the file filter mid-grep (`filter.lua` friction) [3] | no | yes | yes |
| Freeze results → fuzzy-refine them [4] | no | yes | yes |
| `field:value` filters (`file:lua$`, `text:…`) | no | no | yes |
| `file:line:col` jump syntax in the prompt | no | no | yes |
| Frecency ranking [5] | no | no | yes |
| Zero extra plugins / build steps [6] | yes | no | yes |

1. Telescope's operators exist only because `telescope-fzf-native` is compiled
   in (snacks has them natively). In `live_grep` they filter the *displayed*
   `file:line:text` lines, not the rg search — `.go$` there ≈ "line ends in
   `.go`", a fragile proxy, **not** a file-type restriction.
2. Stock can do this only via opts passed at *launch* (`live_grep{
   type_filter='go' }` / `glob_pattern='*.go'`) — fixed per-invocation, can't
   change once running. That's what `pickers/filter.lua` automated.
3. live-grep-args edits args in the live prompt, refining the filter without
   escaping/re-toggling/re-grepping — the exact friction the
   [rebuild design](#filter-picker--rebuild-design) describes.
4. live-grep-args ships `to_fuzzy_refine()`; snacks does it via the live/fuzzy
   toggle (`<c-g>`).
5. Telescope frecency needs a *second* plugin, `telescope-frecency` (+ SQLite
   DB); snacks has it in-tree.
6. live-grep-args is one extra plugin (no build step); snacks is already a
   loaded dependency, so adopting its picker adds none.

### What adding telescope-live-grep-args would (and wouldn't) fix

**Would close** — the entire top half of the table, i.e. the *file-filter*
half of the pain point:
- Live `-g`/`-t`/`--glob` args typed straight into the grep prompt →
  `"myFunc" -g '*.go'`, `"foo" -t lua`, `"foo" -g '!*_test.go'`.
- Genuine "grep only in these file types," changeable mid-search — which
  **would have made `pickers/filter.lua` largely redundant** (free-form args
  replace the preset toggler) and resolves the core complaint the
  [rebuild design](#filter-picker--rebuild-design) addresses.
- Freeze-then-fuzzy-refine via `to_fuzzy_refine()`.

**Would NOT close** — the bottom half, i.e. the *richer-query* and *ranking*
half:
- **`field:value` filters.** There is no telescope equivalent to
  `file:lua$ 'function`. This is a snacks-matcher feature; no telescope
  plugin provides it. This is the biggest capability telescope simply lacks.
- **`file:line:col` jump syntax** in the prompt.
- **Frecency** — still needs the separate `telescope-frecency` plugin.
- **Performance profile** — live-grep-args changes nothing about telescope's
  main-loop-bound sorting on huge repos.

**Cost:** one plugin, no build step, ~10 lines to wire + rebind `<leader>sg`.
It is the **cheapest, lowest-risk step** and a good "try before you migrate":
it closes the file-filter half of
the gap without touching any of our custom pickers, and tells you whether the
remaining snacks-only wins (`field:` filters, frecency, the suite) are worth a
migration.

### Side-by-side query examples

Same goal, expressed in each setup. **stock** = what you type today; **+lga**
= after adding telescope-live-grep-args (grep prompt); **snacks** = the snacks
`grep`/`files` picker. Two rules to keep straight:

- In **snacks grep**, everything before ` -- ` is the ripgrep *search
  pattern*; everything after ` -- ` is passed as raw `rg` flags. Grep is
  *live* (regex), so fzf operators / `field:` apply only after `<c-g>` toggles
  it to fuzzy — or in the **files** picker, which is fuzzy by default.
- In **+lga**, tokens starting with `-`/`--` go to ripgrep; quote a
  multi-word pattern (`"foo bar"`) so it isn't split into flags.

**Grep for `handleRequest` everywhere (baseline)**
- stock: `handleRequest`
- +lga: `handleRequest`
- snacks: `handleRequest`

**Grep `handleRequest`, only in Go files**
- stock: *not possible from the prompt* — launch `live_grep{ type_filter='go' }`
  first, then type `handleRequest` (the old `filter.lua` `go_src` preset was the
  toggle-driven version of this).
- +lga: `handleRequest -tgo`
- snacks: `handleRequest -- -tgo`

**Grep `handleRequest`, in `*.go` but excluding `*_test.go`**
- stock: *not from the prompt* — this is exactly the old `go_src` preset
  (`{'*.go', '!*_test.go'}`) that `filter.lua` existed to automate.
- +lga: `handleRequest -tgo -g '!*_test.go'`
- snacks: `handleRequest -- -tgo -g '!*_test.go'`

  Mixing `-tgo` with `-g` works here because `!*_test.go` is an **exclude**
  glob — it only removes files, so `-tgo` stays in effect. An **include** glob
  (`-g '*.go'`) would instead *override* `-tgo` and ignore the type entirely;
  see the Rust-name example below for that trap.

**Grep `TODO`, only under a `handlers/` folder, in TS/TSX**
- stock: *not from the prompt.*
- +lga: `TODO -g '**/handlers/**' -g '*.{ts,tsx}'`
- snacks: `TODO -- -g '**/handlers/**' -g '*.{ts,tsx}'`

**Grep `foo` only in Rust files whose *name* contains `price`**
- stock: *not from the prompt.*
- +lga: `foo -g '*price*.rs'`
- snacks: `foo -- -g '*price*.rs'`

  **Gotcha — combining a name filter with a type is trickier than it looks.**
  The obvious `-g 'price*' -trs` is wrong *two* ways. Below, each variant with
  what it actually returns against files
  `price.rs  get_price.rs  price.py  price.txt`:

  - **`price*` is *starts-with*, not *contains*.**
    `-g 'price*'` → `price.rs`, `price.py`, `price.txt` — misses `get_price.rs`.
    Use `*price*` for "name contains price".
  - **An include `-g` glob overrides `-t`.**
    `-g '*price*' -trs` → `price.rs`, `get_price.rs`, `price.py`, `price.txt` —
    the `-trs` is *ignored*, so the non-Rust files leak in. An include glob
    defines the file set outright; you cannot AND it with a type.
    **Fix: fold the extension into the glob** → `-g '*price*.rs'` →
    `price.rs`, `get_price.rs` only.
  - **Exclude globs *do* combine with `-t`.**
    `-tgo -g '!*_test.go'` correctly means "Go files, minus tests" — an
    exclude glob only *removes* files, so the type filter still applies. It's
    only *include* globs that override `-t`.

  Fuller treatment — glob anchoring, include vs exclude, more examples — is in
  the ripgrep guide: [`docs/ripgrep.md`](../docs/ripgrep.md#globs).

**Grep the exact phrase `res.status(500)` (literal, not regex)**
- stock: `'res.status(500)` (fzf exact filters the *displayed lines* rg
  returned — fragile; `(`/`)` are still regex to rg, so rg may error).
- +lga: `"res.status(500)" -F` (`-F` = ripgrep fixed-strings / literal).
- snacks: `res.status(500) -- -F`

**Grep `parse`, whole word only, case-sensitive**
- stock: `parse` then rely on fzf filtering — no true `\bparse\b` or case flag.
- +lga: `parse -w -s` (`-w` word-boundary, `-s` case-sensitive).
- snacks: `parse -- -w -s`

**Find files named like `config` under `lua/`, ending in `.lua`**
- stock (find_files, fzf ops work on the path here): `config lua/ .lua$`
- +lga: n/a — lga is a *grep* extension; use find_files: `config lua/ .lua$`
  (same as stock).
- snacks (files picker, fuzzy): `config lua/ .lua$` — or scoped:
  `file:^lua/ config .lua$`

**Find a symbol/text where the path ends in `.lua` AND the line has the exact
word `function`** (the `field:` showcase)
- stock: not expressible (no field scoping).
- +lga: not expressible (no field scoping).
- snacks (fuzzy — files picker, or grep after `<c-g>`):
  `file:.lua$ 'function'`

**Jump straight to `keymaps.lua` line 120, col 4** (paste a `file:line:col`)
- stock: not a prompt feature — open the file, then `:120`.
- +lga: not a prompt feature.
- snacks (files picker): `keymaps.lua:120:4` → filters to that file and opens
  at 120:4 on `<CR>`.

Takeaway: **+lga makes every file-type / path / rg-flag grep goal typeable**
(rows 2–6) — that's the whole file-filter half. The last three rows
(`field:` scoping, path-scoped fuzzy, `file:line:col`) stay **snacks-only**.

### Custom filter shorthands (a reusable `-tcustom`)

Can you avoid retyping `-tgo -g '!*_test.go'` and instead have a single
shorthand? Yes — but the clean "one token = include **and** exclude" version
lives at the picker layer, not in ripgrep syntax. Three tiers, cheapest first:

**1. ripgrep custom types — native, works in both pickers, no plugin code.
✅ Done — implemented as the `ripgrep` stow package.** Both telescope+lga and
snacks shell out to `rg`, and `rg` reads custom file types from the file at
`$RIPGREP_CONFIG_PATH`. Most common types are **already built in** (`-tgo`,
`-tlua`, `-tpy`, `-tts`, `-tprotobuf`, … — run `rg --type-list`), so you only
`--type-add` to *rename* an awkward one or *bundle* globs under a new name.
`ripgrep/.config/ripgrep/ripgreprc` (env var exported in `zsh`) now adds:

```
--type-add=rs:*.rs                    # alias: -trs (rg's Rust type is `rust`)
--type-add=gotest:*_test.go           # + rusttest/pytest/jstest/tstest/…
--type-add=test:include:gotest,pytest,…   # umbrella, composes the above
```

So in any grep prompt: `handleRequest -tgo -Ttest` = Go **minus** the `test`
type (`-T` = `--type-not`), or `-ttest` = only tests, any language. See
`README.md` → `## ripgrep`.

Caveat: ripgrep types are **name-matched, include-only globs** — directory
components are ignored (Rust's `tests/`, Go's `testdata/` can't be captured),
and you *cannot* fold a `!*_test.go` exclusion into one type
(`--type-add=gosrc:!*_test.go` does **not** work). The best ripgrep gives you
is **two composable tokens** (`-tgo -Ttest`), not one. Also put *only*
`--type-add` lines in that file — any other flag applies to every picker search.

**2. A keybound named preset — the real "one action" answer.** This is exactly
what `pickers/filter.lua` encoded: its `go_src = {'*.go','!*_test.go'}`
preset *was* a `-tcustom`, just invoked as a toggle rather than typed. To make
it a dedicated key:

- telescope+lga — bind a key to
  `live_grep({ additional_args = { '-tgo', '-g', '!*_test.go' } })` (what the
  `go_src` preset already builds).
- snacks — register a named source and bind it:

  ```lua
  -- opts.picker.sources
  gosrc = { finder = "grep", ft = "go", glob = { "!*_test.go" } },
  -- then: function() Snacks.picker.gosrc() end
  ```

  (snacks `grep` opts include `ft`, `glob`, `exclude`, `dirs`, `hidden`,
  `ignored`, `args`.)

**3. A literal typed `-tcustom` token that expands in the prompt.** Possible but
you build it — neither picker has a native alias mechanism. You intercept the
prompt and rewrite `-tcustom` → the real flags before it reaches ripgrep
(snacks: wrap the `grep` finder + preprocess before `snacks.picker.util.parse`;
lga: a custom action / parser patch). Moderate effort, and ergonomically worse
than tier 2 — you'd type-and-remember an alias instead of hitting one key.

**Recommendation:** use tier 1 (`--type-add`) for reusable include-only
shorthands that work everywhere today, and tier 2 (keybound preset / named
source) for anything with an exclusion. Don't invent in-prompt token aliases;
the named-source/keybind path is the lower-friction version of the same idea.
On telescope that would mean rebuilding a `filter.lua`-style preset; on snacks
it's a ~2-line source.

### Verdict on the pain point

For the full ask — file filters *and* richer-than-fuzzy query syntax *and*
ranking — **snacks is a clear, material upgrade with zero plugin plumbing**,
and it makes the `filter.lua` friction moot. But if the immediate itch is just
"filter grep by file type," **telescope-live-grep-args closes that specific
half today for near-zero cost** — the snacks-only remainder is `field:`
filters, `file:line:col`, and built-in frecency.

---

## 3. Sales pitches + features you might not know

### Telescope's pitch

The mature, ubiquitous, deeply extensible fuzzy-finder *framework* — "Find,
Filter, Preview, Pick, all Lua." Its edge isn't raw speed; it's a clean
finder/sorter/previewer architecture + a first-class `actions`/`action_state`
API, which spawned by far the **largest extension ecosystem**
(live-grep-args, frecency, undo, file-browser, fzf-native, hundreds more).
Wins on extensibility, docs, and battle-tested maturity. **Status (2026):**
actively maintained but at a slower cadence (jamestrew co-maintaining with TJ
DeVries); no official "maintenance mode," but development has visibly slowed
and there's a real migration wave toward fzf-lua/snacks driven by the
large-repo perf gap.

**Telescope features we have but may underuse:**
- **Multi-select → quickfix** — `<Tab>`/`<S-Tab>` tag, `<C-q>` send *all*
  results to quickfix, `<M-q>` send only *tagged*. The backbone of "act on
  many results at once."
- **`builtin.resume`** — reopen the last picker with prompt + results intact
  (we bind `<leader>sr`).
- **`builtin.pickers`** — a picker *of your recent pickers*, resume any.
- **`command_history` / `search_history`** — fuzzy-pick past `:` cmds and `/`
  searches.
- **`<C-/>` (insert) / `?` (normal)** — which-key help listing the current
  picker's mappings. (We alias this to `<C-h>`.)
- **Extensions we could add:** `live-grep-args` (biggest win for the pain
  point), `frecency` (frecency ranking + `:tag:` workspace filters), `undo`
  (undo-tree with diff preview + fuzzy-in-preview), `file-browser`.
- **Layout strategies** — `horizontal`/`vertical`/`flex`/`center`/`cursor`/
  `bottom_pane` (we use `flex`).

### Snacks' pitch

A **zero-dependency, pure-Lua** fuzzy finder whose matcher is a direct fzf
scoring port, running fully async (finder + matcher stream concurrently,
yielding every 1 ms) so it's snappy on huge repos with no compiled extension.
OOTB it gives what telescope needs 3+ plugins for — **fzf syntax + field
filters + in-prompt rg args + native frecency** — plus ~65 built-in sources, a
rich layout-preset system, an explorer file-browser, and git/gh/LSP pickers.
Part of folke's very actively developed suite; integrates cleanly with lazy /
LazyVim. **Status (2026):** very active (folke = LazyVim/lazy.nvim author).

**Snacks features new-to-us worth knowing:**
- **`smart`** source — combined buffers + recent + files, frecency-ranked, one
  list. (Bind to `<leader><space>`.) Telescope needs a plugin for this.
- **`explorer`** — a full file browser *implemented as a picker* (create/
  rename/move/delete). Could replace or complement nvim-tree flows.
- **Built-in frecency** — no plugin; the thing linkarzu's "why I moved from
  Telescope to Snacks" post is mostly about.
- **Layout presets** — `ivy`, `telescope`, `vscode` (command-palette),
  `dropdown`, `sidebar`, `left/right/top/bottom`, `select`; swappable
  per-source or at runtime. Far more than telescope's layout options.
- **`gh_*` pickers** — `gh_pr`, `gh_issue`, `gh_actions`, `gh_diff`,
  `gh_reactions` via the `gh` CLI. No telescope OOTB equivalent.
- **git pickers built in** — `git_status`, `git_diff`, `git_log`,
  `git_log_file`, `git_log_line`, `git_branches`, `git_stash`, `git_files`,
  `git_grep` (telescope needs extras for parity).
- **In-input toggles/flags** — `<a-h>` hidden, `<a-i>` ignored, `<a-p>`
  preview, `<a-m>` maximize, `<a-d>` inspect fields, `<c-g>` toggle live.
  Rendered as flags in the title.
- **`undo`, `notifications` (searchable history), `treesitter`, `zoxide`,
  `projects`, `icons`, `spelling`, `registers`, `jumps`, `marks`** — all
  built-in sources.
- **Full source list (~65):** autocmds, buffers, cliphist, colorschemes,
  command_history, commands, diagnostics(_buffer), explorer, files, gh_*,
  git_*, grep(_buffers/_word), help, highlights, icons, jumps, keymaps, lazy,
  lines, loclist, lsp_* (definitions/references/implementations/type_defs/
  incoming+outgoing_calls/document+workspace symbols), man, marks,
  notifications, projects, qflist, recent, registers, resume, scratch,
  search_history, select, smart, spelling, tags, treesitter, undo, zoxide.

---

## 4. Swap assessment — is there a serious blocker?

**No serious blocker.** Snacks is already a loaded dependency, its custom-picker
API is lighter than telescope's, and it has a built-in equivalent (or better)
for every telescope surface we use. The cost is *porting effort*, not a wall.

### Our telescope surface (what a migration must cover)

Inventory of what we've actually built on telescope:

| Surface | File | Snacks path | Effort |
|---|---|---|---|
| Global config (layout, mappings, path_display, git icons, file_ignore) | `plugins.lua` `require('telescope').setup` | `Snacks.setup({ picker = {...} })` + per-source opts | Low — mostly 1:1 config translation |
| File-filter toggle presets | `pickers/filter.lua` (removed) | Largely obsolete: `field:`/`--` syntax + `ft`/`glob` opts; or a custom `toggle_*` action | None — already deleted |
| Modified-files git picker | `pickers/gitstatus.lua` (176) | built-in `git_status` (+ custom finder if needed) | Low |
| Buffer picker | `pickers/buffer.lua` (97) | built-in `buffers` | Low |
| Theme picker | `pickers/theme.lua` (119) | built-in `colorschemes` or custom finder + live preview | Low–Med |
| Keybindings picker | `pickers/keybindings.lua` (255) | built-in `keymaps` or custom finder | Low–Med |
| **Workspace/document symbols** | `pickers/symbols.lua` (712) | custom finder; multi-LSP fan-out is custom either way | **Med–High — the real cost** |
| `send_to_sidekick` action | `plugins.lua` mappings | `win.input.keys` → custom action (snacks has a *native* `<a-a>` sidekick send this replicates) | Low — snacks makes it easier |
| `vim.ui.select` via telescope | `ui-select` extension | `ui_select = true` (built in) | Trivial |
| LSP "go to" via `telescope.builtin` | `lsp.lua` | `lsp_definitions`/`lsp_references`/… | Low |
| aerial integration | `outline.lua` `load_extension('aerial')` | aerial has a snacks source too; or keep aerial's own | Low |

### The custom-picker API is not a blocker

Telescope custom pickers = finder + sorter + previewer + `attach_mappings` +
`action_state` boilerplate (see `symbols.lua`). Snacks is one call:

```lua
Snacks.picker.pick({
  finder = fn,        -- returns Item[] (static) OR fun(cb) (async/live)
  format = fn,        -- item -> {text, hlgroup} tuples / extmarks
  preview = fn|preset,
  confirm = fn,       -- <CR> handler
  actions = { my_action = fn },
  win = { input = { keys = { ["<Tab>"] = "my_action" } } },
})
```

Items are any table with a `text` field plus arbitrary fields (which
`field:` filters can then target — e.g. our symbols could expose `kind:`,
`client:`). Live vs static is decided purely by return type. No registration,
no separate sorter/previewer modules. **This is strictly less boilerplate than
what we maintain now.**

### Where the actual work is

`symbols.lua` (712 lines) is ~90% of the porting effort, and its hard parts —
multi-LSP fan-out across all session clients, gopls path-prefix scrubbing,
lua_ls cwd filtering, name-only match highlighting, dual-mode toggle — are
**custom on any picker** (telescope, snacks, or fzf-lua all route through
`buf_request_all` for the fan-out). So the migration cost there is
*re-expressing custom logic on a new API*, not *losing a capability*.
[§5](#symbols-picker-eval) time-boxes exactly
this question.

### Risks / watch-items (none are blockers)

- **`grep` live-mode default** — need to decide default live vs fuzzy and
  document `<c-g>`, or muscle memory will feel "broken."
- **Two-picker transition** — snacks and telescope can coexist during a
  migration (both are just Lua), so it can be incremental, source by source.
- **Config surface differs** — our telescope `layout_config`/mappings/
  `path_display` all have snacks equivalents but the translation is manual.
- **`GUIDE.md` + keymap docs** — a swap touches many `<leader>s*` bindings;
  per the repo's own rules that's a real doc-maintenance chunk (Keymap index,
  per-feature tables).

---

<a id="symbols-picker-eval"></a>
## 5. Symbols picker port — snacks/fzf-lua eval (`<leader>ss`)

A time-boxed evaluation (≤2 h) of whether **snacks.picker** or **fzf-lua** can
replace the bespoke `pickers/symbols.lua` end-to-end, replace only its display
layer, or doesn't justify the swap. This is the concentrated cost §4 flags — so
it gets its own scoped plan. **Not** an immediate migration.

### Why the file is big

`pickers/symbols.lua` (~712 lines) is custom because telescope's default
LSP-symbol pipeline (`vim.lsp.util.symbols_to_items` →
`make_entry.gen_from_lsp_symbols`) makes formatting choices that clash with what
we want. Its hard parts are picker-agnostic — they'd be re-solved on *any*
picker.

### What we keep regardless of picker

Real requirements, each either solved already or needing a re-solve on whatever
picker we land on:

1. **Multi-LSP fan-out across all session clients** — search Go symbols from a
   markdown buffer when gopls is alive elsewhere. Neither candidate solves this
   OOTB; both still route through `buf_request_all`. *(Custom either way.)*
2. **gopls name cleanup** — strip the `_/Users/.../pkg.` prefix from
   path-qualified names. Server-specific; same shape of fix in any picker.
3. **lua_ls cwd filter** — drop neovim-runtime + mason library symbols.
4. **VSCode-style columns** — kind icon, name, lsp, path; vertical layout with
   preview below.
5. **Buffer-only toggle** (`<leader>ts`) with the LSP column hidden — flips the
   mode persistently in-session.
6. **Match highlighting on the name column only** — no spurious path highlights.

### Candidate 1: snacks.picker

- Install: already loaded (`folke/snacks.nvim`); enable `picker`.
- OOTB to test: `Snacks.picker.lsp_workspace_symbols()` — column layout, gopls
  `containerName` leak, whether buffer-attached-only is the default. Source:
  `snacks/picker/source/lsp.lua`. Display config is a declarative `format`
  function (text+hl pairs) — closer to what we want than telescope's
  `entry_display`.
- Custom hooks: `format` (4-column layout in ~10 lines); `confirm`/`actions`
  (keymap parity with `<c-space>` fuzzy-refine); `live = true` (re-fires request
  on prompt change, replacing `finders.new_dynamic`); custom `finder` fn to plug
  in the multi-LSP fan-out (`request_all` lifts from current code).
- Risk: snacks is a meta-plugin, but unused submodules are `enabled = false`;
  some default keymaps may differ from muscle memory.

### Candidate 2: fzf-lua

- Install: `{ src = gh('ibhagwan/fzf-lua') }` (heavier for our use — we'd use no
  other fzf-lua picker; fzf binary already on this host via Homebrew).
- OOTB to test: `:FzfLua lsp_live_workspace_symbols` — live re-query; already
  does icon+name+path columns; check gopls parsing + layout configurability.
  Source: `fzf-lua/providers/lsp.lua`.
- Custom hooks: `winopts`/`previewer` (preview-below parity); `actions` (keymap
  remap); whether `lsp_live_workspace_symbols` accepts a custom requester
  (`query_fn`) — if yes, multi-LSP fan-out is a one-liner; if not, same effort as
  today.

### Evaluation rubric

| Criterion | Weight | Notes |
|---|---|---|
| Symbol name renders cleanly for gopls + lua_ls + ts_ls | 3 | Hard requirement |
| Display config in <30 lines (icon, name, lsp, path) | 2 | Replaces ~80 lines of current `entry_display` |
| Multi-LSP fan-out feasible without forking | 3 | Monkey-patching internals = no win |
| Buffer-only toggle stays simple | 2 | Persistent module-level flag should stay trivial |
| Per-keystroke re-query latency feels fine | 2 | `<300 ms` round-trip on this repo |
| Plugin "blast radius" (other features pulled in) | 1 | Lower is better |

A swap wins only if total ≥ current by a clear margin *and* the gopls/lua_ls
quirks stay cleanly solved.

### Test plan (scratch branch `evaluate-symbol-pickers`; keep `symbols.lua` until a winner is confirmed)

- **Phase 1 — snacks (≤45 min):** enable the picker; temp-bind `<leader>sX` to
  `Snacks.picker.lsp_workspace_symbols()`; run from Go, Lua, and markdown
  buffers in a mixed repo (this dotfiles repo works — `nvim/lua` for lua_ls, any
  `*.go` dir for gopls); inspect gopls name/containerName/layout; if display
  works but multi-LSP doesn't, lift `request_all`/`make_requester` verbatim into
  a custom snacks finder; score.
- **Phase 2 — fzf-lua (≤45 min):** add the plugin; temp-bind `<leader>sY` to
  `:FzfLua lsp_live_workspace_symbols`; same buffer matrix; read
  `providers/lsp.lua` for the requester hook; score.
- **Phase 3 — decision (≤30 min):** both lower than current → keep
  `symbols.lua`, note "stays bespoke." One higher → migrate `<leader>ss`/`sd`,
  delete `symbols.lua`, keep `request_all`/`make_requester` in a small helper if
  fan-out needed manual wiring. Display-only better but fan-out ugly → don't
  migrate (the complexity is the fan-out, not the display).

### Files & references

- `plugins.lua` — add a candidate as a `vim.pack` source.
- `keymaps.lua` — temp bindings during test; permanent rebind on migration.
- `pickers/symbols.lua` — untouched during eval; the
  `request_all`/`make_requester`/`convert_symbols`/`clean_symbol_name` helpers
  are picker-agnostic and lift cleanly into either candidate.
- Upstream gap: neovim/neovim#24799 (`workspace/symbol` across all clients).
- snacks LSP source: `snacks/picker/source/lsp.lua`; fzf-lua LSP source:
  `fzf-lua/providers/lsp.lua` (both under `~/.local/share/nvim/site/pack/...`).

---

## Verdict / recommendation

1. **The pain point is real and snacks solves it best** — `field:` filters +
   `-- <rg args>` + native frecency, zero extensions. Even the fzf syntax you
   *do* have in telescope only works because fzf-native is compiled in, and it
   can't restrict grep to a file type.
2. **Cheapest path if staying on telescope:** add
   **telescope-live-grep-args** and rebind `<leader>sg`. Closes most of the
   file-filter gap; does not add `field:` filters or frecency. Good as a "try
   before you migrate" step.
3. **No serious blocker to swapping to snacks.** It's already installed, the
   API is lighter, and every surface has a built-in or easy-port equivalent.
   The one concentrated cost is re-expressing `symbols.lua`'s multi-LSP logic
   on the snacks finder API — bounded, already scoped in
   [§5](#symbols-picker-eval).
4. **Suggested next step (not done here):** a time-boxed spike — stand up
   snacks picker alongside telescope (they coexist), rebind `<leader>sf`/`sg`/
   `sm`/`sb` to snacks sources, live with it for a few days, and only then map
   the full migration (config translation + `symbols.lua` port + GUIDE.md/
   keymap doc updates). If you want, the actual migration plan gets written as
   a follow-up doc once you've decided.

---

<a id="explorer-eval"></a>
## 6. Explorer — nvim-tree vs snacks explorer

Resolves TODO item #1 below. Evaluation only — no migration steps. Verified
against the installed snacks source (`~/.local/share/nvim/site/pack/core/opt/
snacks.nvim`), not just the docs.

**Verdict up front: keep nvim-tree — but it's closer than expected, and the
cost was never the reason.** The migration is genuinely *cheap*; what holds the
line is window ergonomics. Details below.

### 6.1 Import-rewriting on rename — a non-issue, and lsp-file-operations loses

The obvious worry ("we'd lose import rewriting") inverts on inspection:

- **nvim-lsp-file-operations cannot work with snacks.** Its README says it
  subscribes to events emitted by **nvim-tree, neo-tree, and triptych**. Snacks
  explorer emits no events at all (`snacks/explorer/actions.lua` only calls
  `Tree:refresh()`). That's structural, not a config gap — an integration would
  mean wrapping snacks' `explorer_*` actions, not subscribing to anything.
- **Snacks does it natively.** `explorer_rename` / `explorer_move` route through
  `Snacks.rename.rename_file()`, and `snacks/rename.lua` sends
  `workspace/willRenameFiles`, applies the returned workspace edit, then
  notifies `didRenameFiles`. So a migration **deletes**
  nvim-lsp-file-operations rather than porting it — which also retires the
  two-halves, silently-desyncable invariant between `lsp.lua` (capability half)
  and `filetree.lua` (event half) that our own comments flag as a footgun.
- **The regression is one thing, not a capability class.** Snacks does *not*
  send will/did **Create** or **Delete** (`explorer_add` / `explorer_del` make
  no LSP calls); nvim-lsp-file-operations does. But checking every server we
  actually run against its own capability source: ts_ls and rust-analyzer
  advertise `willRename` only; lua_ls `didRename` only (snacks sends that too);
  pyright, elixirls, kotlin_ls, eslint advertise nothing. **No server we run
  implements `willCreateFiles` or `willDeleteFiles`** — that coverage is dead
  code here. The single real loss is **gopls' `didCreate`** (auto package clause
  on a new `.go` file). Note gopls advertises *no* `willRename` at all
  (golang/go#51037, open since 2022), so neither tool gives Go import rewriting.
- Snacks' `rename.lua` still uses the deprecated dot-notation
  `client.supports_method` / `client.request_sync` (snacks #2839), which breaks
  on Neovim 0.13 — but 0.13 is unreleased, the fix is four call sites, and a PR
  (#2862) already exists. **Not a serious argument.** If plugin staleness
  matters it points the other way: nvim-lsp-file-operations was last touched
  2026-01.

<a id="explorer-cost"></a>
### 6.2 The migration is *cheaper* than it looks

Our sidebar machinery keys on the `NvimTree` filetype across nine files, so the
instinct is that all of it must be re-plumbed onto snacks. It mostly must not.
Snacks' picker windows are a virtual list in floats over unnamed scratch
buffers, so the bug classes those fixes exist to dodge **cannot recur** — they
get deleted, not ported:

- `filetree.lua`'s `TreeOpen`-by-winid scrolloff fix (written to dodge
  `aucmd_win`) — **deleted.** Snacks already does it by winid:
  `picker/core/list.lua` calls `Snacks.util.wo(win, { scrolloff = 0 })`, and
  `win.lua` defaults `sidescrolloff = 0`.
- `autocmds.lua`'s `clamped_panels` WinScrolled topline/leftcol clamp — **entry
  removed, nothing added.** The list is virtual: it rebuilds the buffer to
  exactly `state.height` lines and pins `winrestview{topline=1,leftcol=0}` on
  every render. There is no content past the bottom to scroll into.
- `session.lua`'s `NvimTree_%d+` buffer-name wipe — **the hack half
  disappears.** It exists because nvim-tree buffers carry filenames that
  `mksession` `badd`s. Snacks uses `nvim_create_buf(false, true)` (unnamed,
  unlisted) plus floats, which `mksession` skips. A one-call close-before-save
  is still needed for the layout's root split box, but the loop goes.
- `themes.lua`'s eight `NvimTreeGit*HL` overrides — **deleted.** Snacks ships
  `SnacksPickerGitStatus*` defaults.
- stickybuf (`plugins.lua`) — **probably nothing to do.** It pins real windows
  against `:e` hijack; the only real window in a snacks layout is
  `focusable = false`.
- `buffers.lua`, `outline.lua`, `keymaps.lua`, `builtins.lua`, `whichkey.lua` —
  **genuinely just filetype string swaps**, plus a two-line API swap
  (`nvim_tree_api.tree.is_visible()` → `Snacks.picker.get({ source =
  'explorer' })`). Roughly ten mechanical lines.

Honest ledger: three files gain a string, three lose code, one keeps a simpler
hook. **Net, the config gets smaller.** Likewise the global
`confirm = confirm_and_scroll` override in `picker.lua` is not a landmine:
snacks merges `defaults < user < source < opts` last-wins and the explorer
source sets its own `confirm`, so it simply wins. The only effect is losing the
20%-from-top scroll on explorer opens.

### 6.3 Feature comparison

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

[2] The load-bearing con — see §6.4.

### 6.4 The real blocker: window ergonomics

`keymaps.lua` maps `<C-h>`/`<C-l>` to `<C-w>h`/`<C-w>l`. nvim-tree is a normal
split, so hopping into the tree and back just works. A snacks sidebar is **not**
a normal split: in the installed source, the layout's root box is a split with
`focusable = false` (`snacks/layout.lua`) and the input and list are
`relative = "win"` floats. `<C-w>h` does not enter floating windows. **The
everyday "hop into the tree, hop back" motion dies** and would need a dedicated
focus key.

It also turns a one-window sidebar into a three-window layout (box + input +
list), which the "quit when only sidebars remain" arithmetic in `autocmds.lua`
has to absorb.

Together with the two config-unfixable display losses — no open-buffer
highlight, no modified marker, both deliberately configured here (the latter
with a colour-measured `ColorColumn` chip in `themes.lua`) — this is the case
against.

### 6.5 nvim-tree is not rotting

There's no decay argument to lean on. Its README says "stable, no new major
features," but it shipped v1.15 (Jan), v1.16 (Mar), v1.17 (Apr) and v1.18 (Jul
2026), ~50 commits in 2026. Its newest work is an experimental
`session_restore_nvim` (nvim-tree #3343) which, if it lands, obsoletes our
`session.lua` hack upstream.

<a id="explorer-verdict"></a>
### 6.6 Verdict

**Keep nvim-tree — but it's closer than expected, and the cost was never the
reason.**

The migration is cheap: it deletes two plugins, eight highlight overrides, a
scroll clamp, an `aucmd_win` workaround and a cross-file LSP invariant, in
exchange for ~10 lines of filetype string swaps. The create/delete LSP
"regression" is one gopls nicety. The 0.13 deprecation is noise.

What actually holds the line is **ergonomics**: `<C-h>`/`<C-l>` can't reach a
floating sidebar, and the open-buffer / modified-file highlighting we
deliberately tuned has no snacks equivalent at any amount of config. Those are
daily-driver regressions, traded for daily-driver gains
(fuzzy-filter-in-tree, multi-select bulk ops plus `<M-a>`
send-selection-to-sidekick, diagnostics, file watching). That's a matter of
taste, not capability — the same standard the picker migration was held to, and
this one clears it less convincingly.

**Two things would flip it:** a focus key for the floating sidebar that doesn't
feel worse than `<C-h>`, or snacks gaining open-buffer / modified highlighting.
Both are plausible, so this stays open (TODO #1).

**The cheap experiment that would settle it:** snacks is already loaded, so
`Snacks.explorer()` on a spare key runs side by side with nvim-tree, zero
plumbing touched. Live with both for a week and let the `<C-h>` reflex decide.

---

<a id="scroll-profiling"></a>
## 7. Picker scroll-perf profiling plan (Snacks.profiler)

Plan for chasing the "holding `<C-j>` in a picker feels sluggish" report
(TODO #7). Context from TODO #5: an 0.8 vs 0.9 height A/B showed the feel
does **not** track window size. The mechanic is real — a scroll tick that
moves `top` marks the list dirty, and the dirty branch of
`core/list.lua:render()` re-renders every visible row and calls
`win:redraw()` — so per-tick Lua cost scales with visible rows. The open
question is whether that Lua cost is what's *felt*, or whether it's C-side
redraw the profiler can't see. Snacks ships an instrumentation profiler
(`Snacks.profiler`, read `docs/profiler.md`) to settle it.

<a id="preview-off-result"></a>
### Result (2026-07-13): the preview is NOT the bottleneck

**Run first, because it costs one keypress and halves the hypothesis space.**
This is also the first thing folke asks people to try on the upstream report
of this exact symptom ([discussion #950](https://github.com/folke/snacks.nvim/discussions/950),
"holding down J or K" sluggish): toggle the preview off with `<a-p>` and see
if the scroll is still slow.

We did it the blunt way — `preview = false` in `picker.lua`'s `pick_layout()`,
restart, open `<leader>sf`, hold `<C-j>`. **Verdict: "seems similar."** With
the preview pane gone entirely, the scroll feels the same.

That is a strong, cheap result, and it kills a lot of work:

- **Every preview-side fix is dead.** The buffer cache, the bulk read, the
  async read, the throttle tuning — none of them can explain a sluggishness
  that persists with the preview *not rendering at all*.
- **The remaining suspect is the list renderer**, which is the one piece of
  per-tick work that is **unthrottled and synchronous**: `list:_move`
  (`core/list.lua:271-289`) sets `dirty` whenever `top` changes — i.e. on
  every tick once you're scrolling past the window edge — and calls
  `list:render()` (`:550-600`) inline, which re-formats and re-extmarks
  **every visible row** (~40 at `height = 0.9`) and then redraws. By contrast
  the preview is throttled to ~16/sec (`core/picker.lua:134-139`, hardcoded
  `ms = 60`) and dispatched via `vim.schedule` (`core/list.lua:628`).
- **The height A/B did not exonerate the list**, contrary to what this section
  used to assert. 0.9 → 0.8 changes the row count by ~10%, far below the noise
  floor of a feel test. It was never evidence for the preview branch.

Next step is therefore **profiler attribution against `core.list` / `format`**
(below), not any of the preview work — and an upstream issue against
`core/list.lua`'s per-tick full re-render, with the trace attached.

Note for anyone re-reading the preview research below: it remains accurate as
a *description of the two previewers*, and it correctly killed the "snacks
attaches an LSP / uses treesitter where telescope didn't" theories. But its
**conclusions about the cause of the sluggishness were wrong**, and are struck
through in [What this predicts](#preview-predictions) below. Kept as the
decision record, not as live guidance.

<a id="list-render-result"></a>
### Result (2026-07-13): the list render IS O(visible rows) — but it is only ~0.9ms/tick

Protocol 2 below, run headlessly against a 16k-file repo
(`~/src/google-apis-rs`) with the preview off. `<C-j>` in a picker is
`actions.list_down` → `picker.list:move(1)` (`actions.lua:813-815`), so a
scripted `list:move(1)` loop drives *exactly* the key's code path — the loop
this plan rejects as a preview benchmark is the correct list benchmark, and
this is it. Steady-state was reached first (scroll past the window edge, where
`top` starts moving and every tick goes dirty), then 300 ticks were timed with
`vim.uv.hrtime()`, with `list._render` shadowed on the instance to count the
rows each tick actually re-renders.

| picker height | visible rows | rows re-rendered per tick | Lua ms per tick | ms per row |
|---|---|---|---|---|
| 0.30 | 14 | 14.0 | 0.253 | 0.018 |
| 0.60 | 32 | 32.0 | 0.519 | 0.016 |
| 0.95 | 53 | 53.0 | 0.886 | 0.017 |

**The mechanism is confirmed, exactly as read from source.** Rows-re-rendered
per tick equals the visible row count to the decimal — every scroll tick past
the window edge re-formats and re-extmarks *every visible row*, and the cost is
linear in that count (~0.017ms/row, flat across a 3.8× row spread). Item count
is irrelevant (10.8k vs 13.8k items, same per-row cost), as it should be:
`render()` only touches `self.top .. self.top + height - 1`.

**But the magnitude exonerates Lua.** At our `height = 0.9` that is ~0.9ms of
Lua per tick. Even at macOS's fastest key repeat (~15ms), that is ~6% of the
frame budget. A 0.9ms tick does not feel sluggish. So this is the third
[interpretation](#interpretation) branch, not the first: **the Lua render is
O(rows) and small; the felt cost is C-side.**

<a id="flush-hypothesis"></a>
**Which sharpens the suspect to `win:redraw()`.** The dirty branch of
`render()` (`core/list.lua:550-600`) does not scroll the list window — it
*rewrites* it: `nvim_buf_clear_namespace`, `nvim_buf_set_lines` over the whole
buffer, all visible rows re-extmarked, and then `win:redraw()`, which is
`nvim__redraw({ win = ..., valid = false, flush = true })`
(`snacks/win.lua:509-515`) — a full-window invalidate plus a **synchronous UI
flush**, every tick. The headless bench cannot see any of that (no UI attached,
nothing to flush to), which is precisely why the Lua number came back small.

<a id="scroll-asymmetry"></a>
### Did telescope do this differently? Yes — architecturally (source-verified)

This is the asymmetry the whole investigation has been looking for, and it is
not a small one. Read firsthand from a fresh telescope clone (2026-07-13), since
the earlier telescope read in this doc covered only the *previewer*:

| per scroll tick | telescope | snacks |
|---|---|---|
| rows rewritten | 2 (old + new selection) | every visible row (~53) |
| window scroll | native cursor scroll | none possible (virtual list) |
| forced redraw/flush | no (none anywhere in its tree) | yes, synchronous, every tick |

**Telescope's results buffer is a scrollable document, not a viewport.** It is
pre-filled with `max_results = temp__scrolling_limit = 250` blank lines up front
(`pickers.lua:324`, `:575-577`) — i.e. *bigger than the window*. So moving the
selection is just `nvim_win_set_cursor(self.results_win, { row + 1, 0 })`
(`pickers.lua:1158`) and **nvim scrolls the window itself**, which is the path
that lets the terminal use a scroll-region update. Per tick, `set_selection`
(`:1107-1142`) touches exactly two rows: `update_prefix` + `hi_multiselect` on
the old selection row, and `update_prefix` + `hi_selection` + `hi_sorter` +
`hi_multiselect` on the new one. No namespace clear, no buffer rewrite. And
telescope **never forces a redraw at all** — `nvim__redraw`, `vim.cmd('redraw')`
and `:redraw` do not appear anywhere in its `lua/` tree. It mutates the buffer
and lets nvim's normal redraw cycle coalesce the ticks.

**Snacks' list buffer *is* the viewport** — exactly `state.height` lines
(`core/list.lua:116`, `:129`), a virtualized window onto an unbounded item list.
A virtual list *cannot* scroll: there is nothing below the fold to scroll into.
So to move the view it must rewrite the buffer in place, which is precisely why
the dirty branch clears the namespace, re-sets every line, re-extmarks every
visible row, and then has to force the invalidate + flush to get it on screen.

**This is a real trade, not an oversight.** Telescope buys its 2-row,
no-flush tick by *capping the scrollable set at 250 entries* — past that you
simply cannot scroll further. Snacks virtualizes, so it scrolls a 16k-item list
at constant buffer size. It pays for that with a full repaint per tick — and
when a repaint costs more than the key-repeat interval, the input queue backs up,
which is exactly the "keeps scrolling after I let go" shape of upstream
[#950](https://github.com/folke/snacks.nvim/discussions/950).

Note what this does and does not establish: it verifies the **asymmetry** (snacks
does dramatically more per-tick work, of exactly the C-side kind the headless
bench is blind to), not yet the **culprit**. The terminal test below is still
what decides it — but if that comes back smooth, this is the *why*.

**Next test (cheap, and it halves the space again):** in the real terminal,
neuter the forced flush and see if the feel changes — e.g. shadow
`Snacks.win.redraw` with a no-op (or with a plain `vim.cmd('redraw')`, i.e. no
`valid = false` invalidate) and hold `<C-j>` again. If it gets smooth, the
forced full-window flush is the bottleneck and the upstream issue writes itself
(the render path could set only the changed lines, or drop `flush`, and let
nvim batch). If it stays sluggish with both the preview *and* the flush out of
the picture, the remaining cost is the terminal itself and the probe moves
outside snacks (different terminal, `lazyredraw`, cursor-animation plugins).
The profiler run (protocol 1) is still worth doing to confirm from the real
session that Lua totals are as small as the bench says — but it is now a
*confirmation*, not the primary probe, and it can only ever see the Lua half.

<a id="flush-result"></a>
### Result (2026-07-14): the forced flush is NOT the culprit either — it *helps*

Ran the terminal test. **B (no-op `Snacks.win.redraw`) is *slower* than A
(stock).** Not "no better" — worse. Same with a trackpad scroll, which doesn't
go through key repeat at all, so this isn't a key-repeat artifact.

That doesn't just fail to confirm the hypothesis, it **inverts** it. The forced
`nvim__redraw({ valid = false, flush = true })` is what puts each tick on screen
*immediately*. Take it away and nvim defers the repaint to its own idle point,
so while a key is held the list stops updating and then catches up in a lurch —
which reads as *more* lag, not less. snacks forces the flush deliberately, and
it's buying responsiveness with it. **Do not file this upstream, and do not
"fix" it locally.**

So the whole hypothesis chain is now exhausted:

| suspect | verdict |
|---|---|
| preview pane (cache / read / treesitter) | ruled out — `<a-p>` off, still sluggish |
| Lua list render, O(visible rows) | mechanism confirmed, magnitude irrelevant (~0.9ms/tick) |
| forced full-window flush | ruled out — removing it makes it **worse** |

<a id="the-actual-answer"></a>
### What the sluggishness actually was: `<C-j>` is the wrong tool

The thing that was never questioned is the premise. **`<C-j>` moves the
selection exactly one row, so scroll speed is bounded by the OS key-repeat
rate, not by anything snacks does.** macOS's "Fast" setting is ~30ms/repeat
(already maxed here), i.e. ~33 rows/sec — crossing a 16k-file list that way
takes about eight minutes. No render optimization can fix that, because the
render was never the bottleneck: *the input rate is*. It felt "slower than
telescope" partly because telescope's list only ever held 250 entries
([the asymmetry](#scroll-asymmetry)) — there was far less list to be slow at.

The fix is a keymap that already exists. Stock snacks binds `<C-d>`/`<C-u>` to
`list_scroll_down`/`list_scroll_up` (`config/defaults.lua:248,258`, both the
input and list windows), which call `list:scroll(state.scroll)` where
`state.scroll` is the window's `'scroll'` option (`core/list.lua:208`) — half
a window, ~26 rows at our `height = 0.9`. **One keypress, one render, ~26× the
distance of a `<C-j>` tick, for identical per-tick cost.** Documented in
GUIDE.md's picker keymap table.

<a id="scroll-residual"></a>
### Open residual: the intermittent hang

Not explained, and honestly recorded rather than waved off: **both A and B
"sometimes hang"** during a scroll. Since it survives the no-op-redraw patch, it
is not the flush, and since it survives `<a-p>`, it is not the preview. It is
therefore *not* the same phenomenon as the key-repeat-bound slowness above —
that one is fully explained and has a fix.

Not chased further because `<C-d>`/`<C-u>` makes the whole area a non-problem in
daily use (2026-07-14 decision: **parked, not solved**). If it resurfaces and is
worth picking up, the untested candidates, in order:

- **the matcher/finder still streaming.** A 16k-file finder runs async; ticks
  that land while items are still arriving contend with match+sort work. Test:
  wait for the count to settle *completely*, then scroll. If the hang only
  happens early, this is it.
- **`frecency`** (we enable it) adds per-item scoring at match time — an A/B
  with it off is one line in `picker.lua`.
- **GC pauses.** Every dirty tick allocates a fresh line table + extmarks;
  `collectgarbage('count')` sampled across a scroll would show it.

<a id="preview-mechanism"></a>
### How the file preview is actually built — snacks vs telescope

Read firsthand (2026-07) at the installed snacks commit and a fresh telescope
clone, because the preview pane is the leading suspect and the two pickers
turn out to build it *differently in exactly the ways that matter for scroll*.
Both were running stock defaults: the pre-migration `plugins.lua`
(`b5ccd8b^`) passed **no** `preview = {}` overrides to `telescope.setup()`,
and `picker.lua` passes none to snacks today.

**The part that is identical in both** — and which therefore explains nothing
about the regression, but does kill a whole family of hypotheses:

- Neither opens a real file buffer. No `:edit`, no `bufadd`/`bufload`, no
  `nvim_buf_set_name`. The file is read as *text* and pushed into an
  unlisted scratch buffer (`nvim_create_buf(false, true)` → `buftype=nofile`)
  with `nvim_buf_set_lines`.
- **Neither ever sets `filetype` on that buffer**, so `FileType` never fires:
  no LSP client, no `LspAttach`, no ftplugin, no diagnostics, no folds-by-ft.
  Snacks leaves the buffer's ft as the literal `snacks_picker_preview`
  (`picker/core/preview.lua:262`) and wraps every option write in
  `vim.o.eventignore = "all"`; telescope swaps the buffer into the preview
  window via `utils.win_set_buf_noautocmd` (`previewers/buffer_previewer.lua:412,420`),
  which is `eventignore = "all"` around `nvim_win_set_buf`. The detected
  filetype is used *only* to choose a treesitter language.
- Highlighting in both is `vim.treesitter.start(buf, lang)` attached to the
  **whole buffer** (snacks `picker/core/preview.lua:307`, telescope
  `previewers/utils.lua:170-176`), with a regex `bo.syntax = ft` fallback
  when no parser exists. Actual parsing is viewport-driven by Neovim's core
  highlighter, running as C-invoked decoration providers.

So "snacks attaches an LSP to previews" and "snacks uses treesitter where
telescope didn't" are both **false** — strike them from the hypothesis list.
The difference is entirely in *buffer lifecycle*, *when the read happens*,
and *how often the preview fires*:

| Behavior [1] | telescope (`vim_buffer_cat` → `file_maker`) | snacks (`previewers.file`) |
| --- | --- | --- |
| Buffer per previewed file | one new scratch buf per file | one scratch buf per *picker*, rewritten in place |
| Buffer cache | yes: path → bufnr, unbounded, no eviction | no cache |
| Re-preview of a file seen earlier | cache hit: swap the buf back in, no re-read, no re-parse | full re-read + full re-parse |
| File read | async (plenary `Path:_read_async`, libuv) | synchronous `io.open`/`io.lines` on the main loop |
| Treesitter lifecycle | parser stays attached to the cached buf | `treesitter.stop` on every reset, re-`start` per file |
| Preview throttle | none | 60ms, leading + trailing |
| No-preview size cap | 25MB | 1MB |
| No-highlight size cap | 1MB (text still shown) | n/a (no preview at all past 1MB) |
| Line-splitting budget | 250ms, else "Previewer timed out" | none |
| Long-line handling | none | truncated at 500 chars |
| Binary detection | `file --mime-type` shell call | per-line control-char regex |
| Buffer cleanup | all cached bufs deleted at picker teardown | scratch buf lives for the picker; force-loaded bufs swept on `WinClosed` |

[1] snacks: `picker/preview.lua:80-181` (`M.file`), `picker/core/preview.lua`
(`reset` 244-268, `scratch` 274-286, `highlight` 288-310, `set_lines` 396-401),
`picker/core/picker.lua:134-139, 469-480` (throttle),
`picker/config/defaults.lua:197-201` (`max_size`, `max_line_length`).
telescope: `previewers/buffer_previewer.lua` (`preview_fn` 402-462, `file_maker`
238-274, `handle_file_preview` 147-232, cache 333-365, `teardown` 375-400),
`previewers/utils.lua:115-178` (`highlighter`), `config.lua:599-608` (defaults),
`pickers.lua:1150, 1199-1209` (`refresh_previewer`, un-debounced).

Two snacks details worth spelling out, because they cut in opposite
directions:

- **Same-path short-circuit** (`picker/preview.lua:123`): if the newly
  selected item resolves to the same path as the previous one, snacks does
  *not* re-read or re-highlight — only `loc()` moves the cursor. So scrolling
  through many grep hits *within one file* is cheap. This is the one case
  snacks matches telescope's cache.
- **No cache across files**: scrolling a `files` list, every tick that lands
  on a new path pays a blocking read + a fresh `treesitter.stop`/`start`
  cycle + a full parse of the new buffer. Telescope paid that once per file,
  ever, for the life of the picker.

The `item.buf` path is the exception in snacks and is already noted in TODO
#5: buffers/`lines`/LSP pickers carry a real loaded buffer, which snacks
previews by pointing the preview window straight at it (`picker/preview.lua:107`)
— no re-read, no new parse. That's why `<leader>sb` scrolling feels fine and
`<leader>sf` doesn't, and it's a useful control: **if the sluggishness is
absent in `lines` and present in `files`, the read+parse path is implicated,
not the list renderer** (which is identical in both).

<a id="preview-predictions"></a>
### What this predicted about the sluggishness — and why it was wrong

**Superseded by the [preview-off result](#preview-off-result).** Kept because
the reasoning error is instructive and worth not repeating.

The three hypotheses this section originally ranked were (1) the missing
preview-buffer cache, "best fit"; (2) the synchronous read; (3) C-side
decoration providers. An adversarial review plus the one-keypress `<a-p>` test
killed all three as explanations of the reported symptom:

- **The cache hypothesis was a reasoning error, independent of the `<a-p>`
  result.** A `path → bufnr` cache only helps *revisits*. Holding `<C-j>` down
  a fresh file list is 100% cache **misses** — and **telescope missed on every
  one of those ticks too**, paying *more* per miss than snacks does (a brand-new
  buffer per file, plus the read, plus `treesitter.start`). There is no
  amortization when every tick is an unseen path. The old claim ("snacks pays
  full price forever while telescope amortized") is only true of the scroll-*back*
  leg, which nobody complained about. A cache is a fine optimization for the
  `<C-j>`/`<C-k>` oscillation case; it is *not* a fix for this bug.
- **The read and the decoration providers are moot**, because the sluggishness
  survives the preview being switched off entirely.

What actually remains: **`list:render()`'s per-tick, unthrottled, full-visible-row
re-render** (`core/list.lua:271-289` → `:550-600`). It was in front of us the
whole time — `picker.lua:15-17` already carries a comment describing exactly
this mechanic — and it got wrongly demoted because the 0.8-vs-0.9 height A/B
was read as exculpating it. That A/B was underpowered (~10% row-count delta,
well inside feel-test noise) and proved nothing.

Also worth recording: the upstream thread ([#950](https://github.com/folke/snacks.nvim/discussions/950))
notes that users who *did* fix a similar sluggishness got it from **async
treesitter in nvim 0.11+**. We're on 0.12, so we already have that — another
reason the treesitter-parse theories were weak here.

If the cache is ever built anyway (for the oscillation case), four defects were
found in the draft design and must not be rebuilt:
`Snacks.win:on` is **not idempotent** (registering teardown from inside the
previewer adds an autocmd *per tick* — guard it, as snacks' own `colorscheme`
previewer does at `picker/preview.lua:351-359`); the teardown must `vim.schedule`
its `nvim_buf_delete` calls and skip the still-displayed buffer (snacks' own
sweep does both, `core/preview.lua:104-121`); it must preserve snacks'
same-path short-circuit (`picker/preview.lua:123`) or consecutive grep hits in
one file get *slower* than stock; and `buftype = ''` + `nvim_buf_set_lines`
leaves **modified** buffers that make `:qa` fail with `E162`, so set
`modified = false` after filling.

### What the profiler can and can't see (verified against source)

- Starting mid-session **does** instrument already-loaded modules
  (`profiler/core.lua` walks `package.loaded` on start), so
  `snacks.picker.*` gets wrapped even though it loaded long ago.
- The default `filter_fn` drops every `_`-prefixed function
  (`^.*%._[^%.]*$`) — which is most of the hot path: `_render`, `_move`,
  `_scroll`, `_show_preview`, `_throttled_preview`. By default their time
  folds into the public caller, so module-level buckets (`core.list`,
  `core.preview`) are trustworthy but render-internal vs preview-internal
  isn't split. To split it, start with `filter_fn = { default = true }`
  (drops the underscore rule).
- **Blind entirely:** the preview buffer's treesitter highlighting runs as
  C-invoked decoration providers (`on_win`/`on_line`), not Lua module
  functions — invisible to instrumentation. So is the `win:redraw()`
  screen paint. Still a real blind spot, but see
  [the mechanism comparison](#preview-mechanism): telescope highlighted
  previews with the *same* `vim.treesitter.start` over the *same* whole
  buffer, so decoration-provider cost alone can't explain a snacks-specific
  regression — what changed is how often snacks re-pays it (no buffer cache,
  `treesitter.stop`/`start` per file).
- **Visible, and now the thing to look for:** the synchronous file read
  (`io.open`/`io.lines` inside `snacks.picker.preview`, `M.file`) *is* Lua on
  the main loop, so it lands in the trace under the `snacks.picker.preview`
  module bucket. If `core.preview` outweighs `core.list` in a preview-on run,
  read that as the blocking read + parse attach, not as list rendering.
- "Zero overhead when off" holds only until the first run: `stop()` doesn't
  un-wrap modules, so a light per-call guard persists until nvim restarts.
  The *bind* is free to land permanently; a *run* leaves residue.

### Setup (one-time, ~3 lines)

- Bind `<leader>tp` → `Snacks.toggle.profiler():map('<leader>tp')` in
  `picker.lua` after `setup()` (needs the `Snacks` global; same pattern as
  scratch.lua owning its keymaps). `<leader>tp` is free (`<leader>t*` =
  toggle family); snacks' suggested `<leader>pp/ph` collide with the
  goto-preview peek keys.
- No `setup()` change for a first pass — `start()` applies defaults and
  `on_stop.pick` auto-opens the trace picker on stop. Use
  `Snacks.profiler.scratch()` to tweak `group`/`filter`/`filter_fn` per run.
- Document the keymap in GUIDE.md in the same change (repo rule).

### Measurement protocol

Step 0 — the `<a-p>` preview-off test — is **done**, and it points at the list
renderer ([result above](#preview-off-result)). Protocol 2 is **done** too, and
it confirmed the O(visible-rows) re-render while showing the Lua cost is far too
small to be what's felt ([result above](#list-render-result)) — so the live
question is now the forced synchronous flush, and protocol 1 is a confirmation
run rather than the primary probe. What follows is kept as written.

Pin the variables: same repo (the work monorepo), same starting query, same
item count.

1. **Profiler attribution on the list path (primary).** `<leader>tp` →
   `<leader>sf` → hold `<C-j>` ~10s → `<leader>tp` (trace picker opens). Group
   flat by module (`scratch()` → `{ group = 'def_modname', sort = 'time' }`)
   and record time + counts for `snacks.picker.core.list`,
   `snacks.picker.format`, `util.highlight`, `core.matcher`. Run it with the
   preview **off** (`<a-p>`) so the trace isn't diluted — the preview is
   already exonerated, and excluding it makes the list numbers legible. Close
   the trace picker before the next run: it's itself a snacks picker, and an
   open one would land in the next trace.
   Remember the default `filter_fn` drops `_`-prefixed functions — most of the
   hot path (`_render`, `_move`, `_scroll`) — so start with
   `filter_fn = { default = true }` to split render-internal from move-internal.
2. **Per-row cost, measured directly — DONE, see
   [the result](#list-render-result).** Answered headlessly rather than by feel:
   `height` 0.3 / 0.6 / 0.95 (a 3.8× row spread, unlike the useless 0.8-vs-0.9
   A/B), 300 timed `list:move(1)` ticks each. Per-tick cost is exactly linear in
   visible rows, and every visible row *is* re-rendered per tick — but at
   ~0.017ms/row the Lua total is ~0.9ms/tick, too small to feel. Still worth
   doing **as a feel test in the real terminal** (0.3 vs 0.95), because the
   repaint volume scales with rows too: if 0.3 feels dramatically smoother while
   the Lua delta is only ~0.6ms, that gap is the C-side flush cost, quantified.
3. **Telescope control (the cross-tool claim).** The complaint is "slower than
   telescope," and telescope is gone, so memory isn't a baseline.
   `git stash && git checkout <pre-migration commit>`, open the equivalent
   telescope picker on the *same* repo, hold `<C-j>`, then
   `git checkout main && git stash pop` — the pinned-commit trick from TODO #4.
   Telescope re-rendered its results buffer differently *and* previewed on
   **every** selection change with no throttle at all, so if it still wins with
   both previews off, the difference is squarely in list rendering.

**Do not** use a scripted `for _ = 1, N do list:move(1) end` + `hrtime` loop as
a *preview* benchmark — an earlier draft of this plan did, and it's invalid:
the 60ms throttle (`core/picker.lua:134-139`) plus the `vim.schedule` dispatch
(`core/list.lua:628`) mean such a loop fires roughly **one** preview and
silently times list movement instead. It is, however, a perfectly good *list*
benchmark — which is now the thing we care about. If a scripted preview number
is ever wanted, drive `picker.preview:show(picker, { force = true })` directly
to bypass the throttle.

### Interpretation

With the preview ruled out, the outcomes worth distinguishing are — and the
headless bench has already picked one, so the first two are kept only as the
record of what *didn't* happen:

- ~~**`core.list` / `format` dominate the trace, and the cost tracks visible-row
  count (protocol 2)**~~ → **half right, and the wrong half is the important
  one.** The cost *does* track visible-row count, exactly (protocol 2), and our
  own format wrappers are O(1) over stock (`sb`'s line-number recolor, `sm`'s
  status columns), so it is stock snacks behavior. But `core.list` + `format`
  add up to only ~0.9ms/tick, so they cannot *dominate* anything that is felt at
  a 15-30ms key-repeat interval. Do not file an upstream issue about Lua render
  cost; that would be a real mechanism with an irrelevant magnitude.
- ~~**`core.matcher` dominates**~~ → ruled out by construction: the pattern
  doesn't change while scrolling, so the matcher doesn't re-run. Per-row cost in
  the bench was flat across a 3k-item spread, as expected. `frecency` scores at
  *match* time, not scroll time, so it is not implicated either.
- ~~**Lua time is small but the lag persists → it's C-side.**~~ → **also wrong,
  and instructively so.** The bench sharpened this into a specific claim — the
  forced synchronous full-window flush ([above](#flush-hypothesis)) — and the
  terminal test then **inverted** it: removing the flush makes scrolling *worse*
  ([result](#flush-result)). The flush is load-bearing for perceived
  responsiveness, not a drag on it.

**None of the three branches was right, because the question was wrong.** Every
branch above assumes the per-tick *cost* is the problem. It isn't: `<C-j>` moves
one row per key repeat, so the traversal is bounded by the OS input rate, and no
per-tick saving can touch that. See [the actual answer](#the-actual-answer) —
it's `<C-d>`/`<C-u>`, which already exist. Keep the branches as the record of a
hunt that produced three correct mechanisms and zero relevant ones; the lesson
worth carrying is that "make the tick cheaper" was never going to work, and two
days of source-verified mechanism could not tell us that. The first cheap
end-to-end test could have.

Caveats (profiler docs + source): the session slows while profiling and
instrumentation inflates hot tiny functions, so treat *relative* differences as
signal, never absolute ms. The headless bench has the opposite blind spot — its
absolute Lua ms are trustworthy (no instrumentation overhead), but it has no UI,
so it measures none of the C-side cost that is now the suspect. Neither tool can
see the thing the other is best at; that is why the next test is a feel test.

<a id="live-mode-audit"></a>
## 8. Live mode (`<c-g>`) — where it actually pays

Resolves TODO item #6. Source-verified against the installed snacks, plus two
headless probes. **Outcome: one picker gains a real capability (`<leader>sf`),
it needs no config, and every other picker we bind is a fixed list where live
mode is meaningless.** The deliverable was a GUIDE.md correction.

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

<a id="post-migration-todo"></a>
## Post-migration TODO

Deferred follow-ups from the migration (decided during implementation review,
2026-07):

1. **~~Reconsider switching to the snacks `explorer`~~ — CLOSED (2026-07-14):
   keep nvim-tree.** The evaluation ([§6](#explorer-eval)) found the migration
   *cheap* — it deletes two plugins and shrinks the config
   ([§6.2](#explorer-cost)) — and declined it anyway, on ergonomics: a snacks
   sidebar is floating windows that `<C-h>`/`<C-l>` can't reach, and it has no
   open-buffer / modified-file highlighting. Those are daily-driver
   regressions, and no amount of config removes them. Decided rather than left
   open; the side-by-side week wasn't worth spending to re-derive a verdict
   §6 already reached. Revisit only if snacks ships those highlights or a
   focus key that beats `<C-h>` — reopen this item then.
2. **Review snacks' default picker keymaps for inspiration** — the migration
   preserved our keymap vocabulary; snacks ships bindings we don't surface
   (`<a-f>` follow, `<c-r>`-register inserts, `<s-cr>` pick-window, layout
   rotation via `<c-w>HJKL`, ...). Worth a pass over `defaults.lua` /
   `Snacks.picker.picker_actions()` to steal the good ones.
3. **Bind `Snacks.picker.smart()`** (frecency-ranked buffers + recent + files
   in one list) — tentative `<leader><leader>`, key TBD. Note the conflict:
   `<leader><leader>` is currently the alternate-buffer toggle (see GUIDE.md
   Keymap index), so either pick another key or decide `smart` supersedes it.
4. **~~Visual side-by-side of `<leader>sm` against the old telescope look~~ —
   CLOSED (2026-07-14): the picker is good, the comparison isn't owed.** Three
   review rounds landed (status glyph columns + `syntax` diff style;
   header-stripped `nowrap` preview; real file line numbers in the preview
   gutter, derived from hunk headers — something telescope never had) and it
   reads better than what it replaced. The screenshot diff was only ever a
   check for regressions nobody has felt in daily use, so it's dropped rather
   than deferred.
5. **Look into re-orienting some pickers** — ✅ **done (2026-07).** Every
   picker was compared against the pre-migration telescope screenshots
   (`sf`/`sb`/`sd`/`sm`). Outcome: `sf`/`sg`/`sm`/`sd`/`ss` already matched
   the old structure; the chrome difference (telescope's three separate
   titled boxes vs snacks' merged single box) was deliberately kept
   snacks-style — tighter, more result rows. The one real regression was
   `<leader>sb`: the `lines` source ships its own source-level layout
   (bottom-docked full-width ivy strip, `preview = "main"` scrolling the
   real buffer) that silently beats the global layout — on an ultrawide it
   rendered as a shallow full-width banner. Fixed in `picker.lua` by
   assigning the shared `pick_layout` *function* to `sources.lines` —
   snacks replaces (rather than deep-merges) function layouts, which both
   kills the inherited `preview = "main"` and avoids leaking global keys
   into pickers that pin compact presets. Global height was also raised
   0.8 → 0.9 (the old telescope look); briefly reverted on a scroll-feels-
   slower report — a scroll tick at the list edge re-renders every visible
   row, so per-tick cost scales with height — then restored once the
   sluggishness turned out not to track window size (likely snacks
   itself). The `lines` preview pane is free either way — snacks previews
   a loaded `item.buf` by pointing the preview window at it (no re-read,
   no new treesitter parse).
6. **~~Set up `<C-g>` (live mode) on more pickers~~ — AUDITED (2026-07-14).
   One picker gains something (`<leader>sf`), it already works, and the fix
   was documentation.** See [§8](#live-mode-audit) for the mechanism and the
   per-picker table. Summary: `<c-g>` (`toggle_live`) is a generic action any
   source opts into with `supports_live`, and of the ten built-ins that set it
   we bind exactly two — `grep` (live by default) and `files` (fuzzy by
   default, and the one real find: `<c-g>` there turns the prompt into an `fd`
   query, which is the *only* way to reach the ` -- <fd args>` passthrough).
   `<leader>ss` was already live+`supports_live` from the migration.
   Everything else we bind is a fixed list with nothing to re-query, so no
   custom picker should set `supports_live`. No config change; GUIDE.md's
   live-vs-fuzzy note now covers `<leader>sf` and the ` -- `-is-live-only rule.
7. **~~Profile the sluggish picker scroll~~ — CLOSED (2026-07-14). The answer
   was `<C-d>`/`<C-u>`, and no code changed.** Holding `<C-j>` felt slower than
   telescope did, so this went hunting for the expensive thing. Three suspects,
   each verified against source, each *real*, and none of them the cause:
   the **preview** (ruled out by `<a-p>`: scroll is just as slow with no preview
   pane at all — which killed a fully-designed preview-cache module *before it
   landed*, on a premise that was a reasoning error); the **Lua list render**
   (confirmed to re-format every visible row per tick, exactly linear in row
   count — and to cost all of ~0.9ms/tick, far too little to feel); and the
   **forced redraw flush** (which turned out to make things *better*, not worse
   — removing it is slower, because it's what puts each tick on screen
   immediately).
   The premise was the bug: **`<C-j>` moves one row per key repeat, so traversal
   is bounded by the OS input rate (~33 rows/s, already maxed), not by anything
   snacks does** — no per-tick saving could ever have fixed it. Stock
   `<C-d>`/`<C-u>` scroll half a window per press (~26 rows, one render, same
   cost as a single `<C-j>` tick) and make the whole thing a non-issue. Now
   documented in GUIDE.md's picker keymap table; that's the entire fix.
   Nothing to file upstream. Left behind: `<leader>tp` (profiler toggle, useful
   in its own right) and one **unexplained residual** — an intermittent hang
   that survives both `<a-p>` and the no-op-redraw patch, parked with its
   candidate list in [§7](#scroll-residual). Full record, including what each
   dead end taught, in [§7](#scroll-profiling).
8. **Read and evaluate linkarzu's "Why I moved from Telescope to Snacks
   Picker"** — <https://linkarzu.com/posts/neovim/snacks-picker/>. It's cited in
   Sources below but was only skimmed for the *decision*; it was never mined for
   **setup ideas**. Worth a proper read now that we're fully on snacks, to lift
   any config/keymap/layout tricks we missed. Overlaps items 2 and 5 — fold
   whatever it turns up into those.

## Sources

- snacks picker docs: <https://github.com/folke/snacks.nvim/blob/main/docs/picker.md>
  (+ read firsthand: `core/matcher.lua`, `core/score.lua`, `core/finder.lua`,
  `core/frecency.lua`, `util/init.lua`, `source/grep.lua`, `source/files.lua`,
  `config/defaults.lua`, `config/layouts.lua`)
- telescope source: `lua/telescope/{sorters,config,finders,pickers,mappings,algos/fzy,builtin/__files}.lua`

Preview mechanism ([§7](#preview-mechanism)) — both read firsthand, 2026-07:

- snacks: `picker/preview.lua` (`M.file`), `picker/core/preview.lua`
  (`reset`/`scratch`/`highlight`/`set_lines`), `picker/core/picker.lua`
  (`show_preview` + the 60ms throttle), `picker/config/defaults.lua`
  (`previewers.file`), `util/init.lua` (`get_lang`, `throttle`)
- telescope (clone of `nvim-telescope/telescope.nvim`, not installed anymore):
  `previewers/buffer_previewer.lua` (`new_buffer_previewer`, `file_maker`,
  the bufname cache + `teardown`), `previewers/utils.lua` (`highlighter`,
  `ts_highlighter`, `regex_highlighter`, `timed_split_lines`), `config.lua`
  (`preview` defaults, `file_previewer`), `pickers.lua` (`refresh_previewer`)
- the pre-migration telescope config that was actually in use (no `preview`
  overrides, so all of the above defaults applied): `git show
  b5ccd8b^:nvim/.config/nvim/lua/plugins.lua`

Scroll/render mechanism ([the asymmetry](#scroll-asymmetry)) — both read
firsthand, 2026-07-13, and distinct from the previewer read above:

- snacks: `picker/core/list.lua` (`_move`/`render`, the dirty branch, and
  `state.height` — the buffer *is* the viewport), `picker/actions.lua`
  (`list_down`), `snacks/win.lua:509-515` (`redraw` = `nvim__redraw({ valid =
  false, flush = true })`)
- telescope (fresh clone): `pickers.lua` (`set_selection` at `:1048-1158` —
  two rows re-prefixed/re-highlighted, then `nvim_win_set_cursor`;
  `__scrolling_limit = 250` at `:324` and the pre-filled 250-line results
  buffer at `:575-577`), `pickers/scroller.lua`, `actions/init.lua`
  (`move_selection_next`). Also grepped its whole `lua/` tree for
  `nvim__redraw` / `vim.cmd('redraw')` / `:redraw` — **zero hits**, which is
  the load-bearing negative result.
- upstream report of the same symptom ("holding down J or K" sluggish), where
  folke's first diagnostic is the `<a-p>` preview-off test we ran, and where the
  users who resolved it did so via async treesitter in nvim 0.11+ (we're on
  0.12): <https://github.com/folke/snacks.nvim/discussions/950>
- fzf search syntax: <https://junegunn.github.io/fzf/search-syntax/>
- telescope-fzf-native: <https://github.com/nvim-telescope/telescope-fzf-native.nvim>
- telescope-live-grep-args: <https://github.com/nvim-telescope/telescope-live-grep-args.nvim>
- telescope large-repo perf: <https://github.com/nvim-telescope/telescope.nvim/issues/2884>
- "Why I moved from Telescope to Snacks Picker": <https://linkarzu.com/posts/neovim/snacks-picker/>
- snacks file-type/glob discussions: [#1685](https://github.com/folke/snacks.nvim/discussions/1685),
  [#1990](https://github.com/folke/snacks.nvim/discussions/1990),
  [#957](https://github.com/folke/snacks.nvim/discussions/957)
- fzf-lua: <https://github.com/ibhagwan/fzf-lua> (LSP source:
  `lua/fzf-lua/providers/lsp.lua`)
- snacks.picker LSP source: `lua/snacks/picker/source/lsp.lua`

Live-mode audit ([§8](#live-mode-audit)) — read firsthand, 2026-07-14:

- snacks: `picker/core/input.lua` (the `search` vs `pattern` split — `:36`,
  `:83-91`, `:133`, `:197`), `picker/actions.lua:745` (`toggle_live`),
  `picker/config/defaults.lua:250` (`<c-g>`), `picker/config/sources.lua`
  (which sources set `supports_live` / `live`), `picker/source/files.lua`
  (`get_cmd` → `util.parse(filter.search)` — why ` -- ` is live-only)
- our side: `lua/picker.lua` (sources), `lua/keymaps.lua` (`<leader>s*`),
  `lua/pickers/symbols.lua` (already `live` + `supports_live`)

Explorer eval ([§6](#explorer-eval)):

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
</content>
</invoke>
