# Telescope vs snacks.nvim picker — research & swap assessment

Research doc comparing our current **telescope** stack against **folke's
snacks.nvim picker**, with a focus on (1) the search-syntax / file-filter gap
that motivated this, (2) what each is built on and how they perform, (3) each
picker's sales pitch + features we might not know, and (4) whether there's a
*serious blocker* to swapping. **Not** a migration plan — see "Verdict" for
where an actual migration would get mapped out.

Two narrower plans already circle this topic; this doc is the umbrella over
both:
- [filter-picker-rethink.md](filter-picker-rethink.md) — the glob-filter
  friction in `pickers/filter.lua` (static Lua presets, can't refine filters
  mid-grep). Snacks makes most of that friction disappear (see §2).
- [symbol-picker-alternatives.md](symbol-picker-alternatives.md) — time-boxed
  eval of snacks/fzf-lua specifically for the `<leader>ss` symbols picker.

## TL;DR

- **Your instinct is right, and it's not a skill gap.** Stock telescope really
  is fuzzy-only. The fzf operator syntax (`'exact`, `^prefix`, `suffix$`,
  `!negate`, `|OR`) only exists once you add **telescope-fzf-native**, and even
  then it filters the *displayed lines*, not the ripgrep search. True "grep
  only in `*.go`" needs picker opts (`type_filter`/`glob_pattern`) or the
  **telescope-live-grep-args** extension — none of which you currently have
  installed. Your `pickers/filter.lua` is essentially a hand-rolled substitute
  for live-grep-args.
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
  the ~712-line multi-LSP `symbols.lua`. Everything else (filter, gitstatus,
  buffer, theme, keybindings, sidekick send) ports cleanly. We already have
  snacks installed as a dependency, so there's no new plugin to add.

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
    mid-search). *This is exactly what our `pickers/filter.lua` automates* by
    building `--glob` args from toggle presets.
  - the **telescope-live-grep-args** extension — type raw rg args live:
    `"my term" -g *.go` / `"foo" --type lua` / `"foo" -g '!*_test.go'`. This is
    the community-standard fix for our exact complaint, and **we don't have it
    installed.**

So: part of the "telescope only fuzzy-matches" feeling is that stock telescope
*is* fuzzy-only, and part is that we never added live-grep-args — our
`filter.lua` is a partial hand-rolled version of it (presets instead of
free-form, and only settable before the grep starts, which is precisely the
friction [filter-picker-rethink.md](filter-picker-rethink.md) is about).

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
`dirs`) if you'd rather bind a preset key like our filter toggles.

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

Legend: **stock** = telescope + fzf-native + ui-select (today); **+lga** =
stock + telescope-live-grep-args.

1. Telescope's operators exist only because `telescope-fzf-native` is compiled
   in (snacks has them natively). In `live_grep` they filter the *displayed*
   `file:line:text` lines, not the rg search — `.go$` there ≈ "line ends in
   `.go`", a fragile proxy, **not** a file-type restriction.
2. Stock can do this onlyevi  opts passed at *launch* (`live_grep{
   type_filter='go' }` / `glob_pattern='*.go'`) — fixed per-invocation, can't
   change once running. That's what `pickers/filter.lua` automates.
3. live-grep-args edits args in the live prompt, refining the filter without
   escaping/re-toggling/re-grepping — the exact friction
   [filter-picker-rethink.md](filter-picker-rethink.md) describes.
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
  **makes `pickers/filter.lua` largely redundant** (free-form args replace the
  preset toggler) and resolves the core complaint in
  [filter-picker-rethink.md](filter-picker-rethink.md).
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

**Cost:** one plugin, no build step, ~10 lines to wire + rebind `<leader>sg`
(and probably retire or slim `filter.lua`). It is the **cheapest, lowest-risk
step** and a good "try before you migrate": it closes the file-filter half of
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
  or toggle the `go_src` preset in `filter.lua` first, then type `handleRequest`.
- +lga: `handleRequest -tgo`
- snacks: `handleRequest -- -tgo`

**Grep `handleRequest`, in `*.go` but excluding `*_test.go`**
- stock: *not from the prompt* — this is exactly the `go_src` preset
  (`{'*.go', '!*_test.go'}`) your `filter.lua` exists to automate.
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
what `pickers/filter.lua` already encodes: its `go_src = {'*.go','!*_test.go'}`
preset *is* your `-tcustom`, just invoked as a toggle rather than typed. To make
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
On telescope that's extending the `filter.lua` you already have; on snacks it's
a ~2-line source.

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
| File-filter toggle presets | `pickers/filter.lua` (163) | Largely obsolete: `field:`/`--` syntax + `ft`/`glob` opts; or a custom `toggle_*` action | Low — and *deletes* code |
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
`action_state` boilerplate (see our `filter.lua`/`symbols.lua`). Snacks is one
call:

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
[symbol-picker-alternatives.md](symbol-picker-alternatives.md) already
time-boxes exactly this question.

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
   [symbol-picker-alternatives.md](symbol-picker-alternatives.md).
4. **Suggested next step (not done here):** a time-boxed spike — stand up
   snacks picker alongside telescope (they coexist), rebind `<leader>sf`/`sg`/
   `sm`/`sb` to snacks sources, live with it for a few days, and only then map
   the full migration (config translation + `symbols.lua` port + GUIDE.md/
   keymap doc updates). If you want, the actual migration plan gets written as
   a follow-up doc once you've decided.

---

## Sources

- snacks picker docs: <https://github.com/folke/snacks.nvim/blob/main/docs/picker.md>
  (+ read firsthand: `core/matcher.lua`, `core/score.lua`, `core/finder.lua`,
  `core/frecency.lua`, `util/init.lua`, `source/grep.lua`, `source/files.lua`,
  `config/defaults.lua`, `config/layouts.lua`)
- telescope source: `lua/telescope/{sorters,config,finders,pickers,mappings,algos/fzy,builtin/__files}.lua`
- fzf search syntax: <https://junegunn.github.io/fzf/search-syntax/>
- telescope-fzf-native: <https://github.com/nvim-telescope/telescope-fzf-native.nvim>
- telescope-live-grep-args: <https://github.com/nvim-telescope/telescope-live-grep-args.nvim>
- telescope large-repo perf: <https://github.com/nvim-telescope/telescope.nvim/issues/2884>
- "Why I moved from Telescope to Snacks Picker": <https://linkarzu.com/posts/neovim/snacks-picker/>
- snacks file-type/glob discussions: [#1685](https://github.com/folke/snacks.nvim/discussions/1685),
  [#1990](https://github.com/folke/snacks.nvim/discussions/1990),
  [#957](https://github.com/folke/snacks.nvim/discussions/957)
</content>
</invoke>
