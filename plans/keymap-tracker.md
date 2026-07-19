# Plan: Keymap usage tracker

Primary goal: track every explicit keymap invocation to a persistent log file.
Build on top of a reusable "all keymaps" enumeration primitive so future features
(never-used analysis, usage-aware pickers, weekly summaries) layer on cheaply.

---

## Status

- **Shrunk to spec core 2026-07-18.** The deep-dive internals sections (Neovim
  resolver walkthrough, which-key internals, the atomization problem, the full
  prior-art survey, the upstream-fix recommendation) and the pinned
  code-reference appendix live in git history. Their conclusions survive in
  [Findings (condensed)](#findings-condensed). On revival, re-derive internals
  detail against current nvim/which-key source rather than trusting old
  citations — they drifted once already.
- Research: **complete** — see [Findings (condensed)](#findings-condensed).
- Architecture: **proposed** — two primitives (`keymap_snapshot.lua`,
  `keymap_tracker.lua`) with file-based outputs, integrated via two small edits
  to existing files. Recommended approach recorded; alternatives rejected with
  reasoning.
- Decisions pending: see
  [Open questions / decisions pending](#open-questions--decisions-pending) —
  three small choices remain before implementation.
- Code: **not yet written.** No files created or modified in `nvim/.config/nvim/`.

To resume: read the Status, the Architecture section, and the Open questions;
pick answers for the three pending decisions; then implement Primitive 1 first
(it's independent and immediately useful even without the tracker), Primitive 2
second, then the two integration edits.

---

## Goals (in priority order)

1. **Primary — usage log**: every explicit keymap invocation appends one line to a
   persistent file with timestamp, mode, lhs, desc. Persists across nvim restarts.
2. **Primitive — enumeration**: a separate, reusable module that returns the full set
   of currently-registered keymaps across **all modes** (not just normal). The existing
   `<leader>sk` picker becomes a consumer; future features that combine the universe
   with the log become trivial.
3. **Future, kept in mind but not solved here in detail**: reconciliation ("which
   keymaps do I never use?"), usage counts surfaced in pickers, weekly trend
   summaries, suggestion engines, multi-machine sync (see
   [Future: multi-machine sync](#future-multi-machine-sync)).

Scope: all explicitly mapped keys — `<leader>`, `<C->`, `<M->`, `<S->`, `yp`, `zg`,
etc. Native unmapped motions (`j`, `w`) are out of scope.

Log line format (NDJSON, one line per invocation):

```
{"t":"2026-05-04T14:22:01","m":"n","lhs":"<leader>sf","desc":"Search: Files"}
```

NDJSON over flat text because `lhs` and `desc` can contain spaces, brackets, and
quotes — quoting via JSON is cheaper than re-parsing later.

---

<a id="findings-condensed"></a>
## Findings (condensed)

Conclusions from the deep-dive research; full walkthroughs are in git history.

- **Hook `vim.keymap.set`, not `vim.on_key`.** Wrapping the rhs runs *after*
  Vim's resolver has settled partial/full/timeout/noremap, so the wrapper fires
  exactly when a mapping fires. `vim.on_key` sits one layer too low: it sees
  raw bytes before resolution, so telling "`j` as prefix of `jj`" apart from
  "`j` as motion" would mean reimplementing the resolver's FULL/PARTIAL/NONE
  trichotomy plus `timeoutlen` in Lua.
- **No "keymap fired" event exists, and none is coming.** Neovim's event model
  fires on consequences (TextChanged, CursorMoved), not command dispatch.
  neovim/neovim#30803 asks for exactly this and is blocked on unscheduled
  "atomize input" architecture work (tied to multicursor, #30741); core's
  demonstrated preference is existing query primitives over new events (#24475
  closed with "use `reg_executing()`"; the `KeyInputPre` port #30061 stalled).
  The wrapper is the long-term design, not a stopgap awaiting a core feature.
- **The atomization ambiguity is context, not a blocker.** For composed actions
  (`ci{`) there is no single "whole action" boundary anywhere in Neovim's code
  — the normal-mode engine is a flat one-resolved-key-per-iteration loop, with
  the operator/motion grouping held in side-band globals (`oparg_T`,
  `finish_op`) across iterations. That's the deep reason core has no fired
  event, and why the hook must never be pushed lower into the keystream. This
  tracker sidesteps the problem by construction: it only wraps flat,
  individually-registered mappings (`<leader>ff` *is* the whole action), logged
  once, at the real firing, after any `<Plug>` chain has collapsed.
- **No prior-art plugin does a persistent structured usage log.**
  key-report.nvim (conceptually identical) is archived with the logging feature
  never implemented; keymaps.nvim is tiny/unproven with undocumented
  persistence; keystats.nvim and keylog.nvim log raw keystrokes with no mapping
  semantics; which-key's maintainer declined the feature outright (issue #969,
  closed not-planned). Enumeration, by contrast, is well-covered ground.
  Building the log custom is justified.
- **hardtime.nvim externally validates both hook decisions.** Its hjkl
  restriction owns keys via `vim.keymap.set` and re-resolves against a
  `nvim_get_keymap` snapshot — the same "wrap the rhs, don't observe the
  stream" principle as this plan. Its soft-hints feature *does* use
  `vim.on_key` and (confirmed by source read) skips timeout/partial-match
  disambiguation, tolerating false positives — fine for nagging, disqualifying
  for an accurate persistent log.
- **which-key implications.** `nvim_get_keymap` + `nvim_buf_get_keymap` is the
  canonical enumeration path. which-key never reimplements the resolver — it
  re-feeds resolved prefixes back to Vim ("stay above the resolver"), the same
  principle the rhs wrapper inherits. Its `desc`-tag filtering
  (`which-key-trigger`, `which_key_ignore`) is precedent for tagging the
  wrapper so future re-introspection can identify and skip wrapped entries. Its
  trie + lazy-rebuild machinery is overkill for a logger, but the right shape
  if an in-Neovim usage-sorted picker is ever built (tree from
  `nvim_get_keymap`, joined against the log).

---

## Background: enumerating keymaps in Neovim

Reliable enumeration is the foundation of the second primitive. Findings drawn from
`/Users/dhruv/src/neovim/` (line numbers pinned at research time — see
[Resuming notes](#resuming-notes) before trusting them).

### The canonical API

`nvim_get_keymap(mode)` (`src/nvim/api/vim.c:1601`) and `nvim_buf_get_keymap(buf, mode)`
(`src/nvim/api/buffer.c:859`) both delegate to `keymap_array(mode, buf, arena)`
(`src/nvim/mapping.c:2878`). This walks **all 256 maphash buckets exhaustively**,
filtering by `int_mode & m_mode` so a single `mapblock_T` can match multiple mode
queries.

Each entry, populated by `mapblock_fill_dict`, contains: `lhs`, `lhsraw`,
`lhsrawalt`, `rhs` *xor* `callback`, `desc`, `mode`, `mode_bits`, `noremap`,
`script`, `expr`, `silent`, `nowait`, `replace_keycodes`, `sid`, `lnum`, `buffer`,
`abbr`.

Buffer-local maps live on `b_maphash[]` per `buf_T` and are **not** returned by the
global call — query each loaded buffer separately. Abbreviations live in a separate
linked list (`first_abbr` / `b_first_abbr`); access via mode `"ia"`, `"ca"`, or `"!a"`.

### Mode coverage

Atomic vs alias mode letters (per `get_map_mode`):

| Letter | Bits | Notes |
|---|---|---|
| `n` | NORMAL | atomic |
| `i` | INSERT | atomic |
| `c` | CMDLINE | atomic |
| `o` | OP_PENDING | atomic |
| `t` | TERMINAL | atomic |
| `l` | LANGMAP | atomic |
| `x` | VISUAL | atomic |
| `s` | SELECT | atomic |
| `v` | VISUAL\|SELECT | alias for x+s |
| `!` | INSERT\|CMDLINE | alias for i+c |
| `''` | NORMAL\|VISUAL\|SELECT\|OP_PENDING | `:map` default — **note: no `i`/`c`/`t`/`l`** |

**Practical rule**: query the eight atomic letters (`n,i,c,o,t,l,x,s`); dedupe by
`(lhsraw, mode_bits, buffer)` since one `nvo` mapping shows up under three queries.

The user's `<leader>sk` picker (`pickers/keybindings.lua:40`) currently passes
`mode = 'n'` to `which-key.buf.get`, so it sees normal-mode mappings only — a real
coverage gap that a separate enumeration primitive would close.

### Filtering

| Class | Filter rule |
|---|---|
| `<Plug>...` | `lhs:sub(1,6) == "<Plug>"`. Stored in maphash; not directly user-invokable. Drop. |
| `<SNR>...` | `lhs:sub(1,5) == "<SNR>"` (Vimscript script-local). Drop. |
| `<Nop>` | `m_str == ""` and no callback. Real binding (user explicitly disabled the lhs); keep but mark. |
| `expr` mappings | rhs evaluated per keystroke; **don't wrap**. |
| Default Neovim maps (e.g. `Y` → `y$`) | Real maphash entries, `desc:match(':help')`. Keep. |

which-key applies the same `<Plug>`/`<SNR>` filter (`lua/which-key/buf.lua:129`).

### Definition-time vs query-time

A `vim.keymap.set` shim (a thin Lua wrapper over `nvim_set_keymap`) catches
Lua-level sets only. **Misses**:

- Direct `vim.api.nvim_set_keymap` callers (some plugins use this for marginal speed).
- `:map`/`:nmap` Ex commands and Vimscript `map` (path is `buf_do_map` in C; no Lua
  hook).
- `vim.cmd.map(...)` (resolves to the Ex command path).
- `nvim_buf_set_keymap`.

All four still land in `maphash[]`. **Query-time `nvim_get_keymap` is the only
exhaustive enumeration source.** Definition-time hooks are the only way to wrap
*invocations* — there is no Neovim event for "a mapping fired." This is why the
architecture splits the two concerns into separate primitives.

### Per-mapping fields worth logging

From `mapblock_fill_dict`:

- **Identity**: `lhs` (display, with `<...>` notation), `lhsraw` (resolver form),
  `mode_bits`, `buffer`.
- **Behavior**: `rhs` xor `callback`, `expr`, `noremap`, `silent`, `nowait`.
- **Attribution**: `desc`, `sid` + `lnum` (which script defined it — useful to separate
  user maps from plugin maps).

Note: `m_orig_str` (the user-typed `<C-x>` style string, pre-termcoding) is **not**
exposed via `nvim_get_keymap`; only via `maparg()` with the compatible flag. The
API's `lhs` field is already in str2special form, which is human-readable.

---

## Architecture: two primitives

The work splits cleanly. Each primitive is a small Lua module with a stable
file-output contract; future features compose them.

```
keymap_snapshot.lua  ── writes ──→  keymap_snapshot.ndjson  (the universe)
                                              │
                                              ▼ joined on (mode, lhs)
keymap_tracker.lua   ── writes ──→  keymap_usage.log        (the events)
                                              │
                                              ▼ consumed by
                                  pickers, shell scripts, future features
```

Both files live under `vim.fn.stdpath('data')`, typically `~/.local/share/nvim/`.

### Storage strategy: append-log vs aggregate-on-write

Usage trackers split into two strategies: **aggregate-on-write with decay**
(zoxide's `db.zo`: one compact `(key, score, last_accessed)` DB, frecency scoring,
periodic decay keeps the file bounded — but raw history is permanently discarded)
vs **log everything, aggregate-on-read** (atuin shell history: every event a full
timestamped record; unbounded but prunable; full fidelity for any future
analysis).

**This doc's NDJSON append-log is the atuin-style strategy, and that's the right
call**: reconciliation, weekly summaries, and a suggestion engine all need the raw
log, not a decayed scalar. If a live usage-aware picker ever makes full log
replays a hot path, add a *derived* in-memory `(mode,lhs) → decayed score` table
checkpointed to disk — a materialized view over the log, never a replacement. A
future optimization, not currently planned.

### Primitive 1 — keymap snapshot (`lua/keymap_snapshot.lua`)

**Purpose**: produce a complete, mode-aware list of currently-registered keymaps. The
foundational primitive — the existing `<leader>sk` picker is one consumer; reconciliation,
usage-count display, and suggestion engines are others.

**API**:

```lua
local M = require('keymap_snapshot')

M.collect()  -- returns { { m, lhs, desc, buffer, expr, sid, nop, ... }, ... }
M.write()    -- collect + serialize to keymap_snapshot.ndjson (overwrites)
M.path       -- "~/.local/share/nvim/keymap_snapshot.ndjson"
```

`M.collect()` is the in-memory primitive — Lua callers (pickers, future features) use
it directly. `M.write()` is for shell-script consumers.

**Algorithm**:

1. For each mode in `{n,i,c,o,t,l,x,s}`: call `nvim_get_keymap(mode)`.
2. For each loaded buffer × each mode: call `nvim_buf_get_keymap(buf, mode)`.
3. (Optional, behind a flag) abbrev modes `{ia,ca,!a}` via `nvim_get_keymap(mode)`.
4. Dedupe by `(lhsraw, mode_bits, buffer)`.
5. Filter `<Plug>...`, `<SNR>...` lhs. Mark `<Nop>` and default-map entries; don't drop.
6. Return rows; `M.write()` serializes one NDJSON object per row.

**File format** (NDJSON, one row per `(mode, lhs, buffer)`):

```
{"m":"n","lhs":"<leader>sf","desc":"Search: Files","buffer":0,"expr":false,"sid":12,"nop":false}
```

**Refresh strategy**: snapshots are cheap (a few hundred entries × eight modes,
in-memory). Two natural triggers:

- On `<leader>sk` open — piggy-back on the user's "I want to see my keymaps" moment via
  a one-line addition to `pickers/keybindings.lua`.
- On demand via `:lua require('keymap_snapshot').write()` or a `:KeymapSnapshot` Ex
  command.

No autocmd-driven refresh needed; staleness is not a problem for the primary log use
case.

### Primitive 2 — usage log (`lua/keymap_tracker.lua`)

**Purpose**: append one NDJSON line per keymap invocation to a flat log file.

**API**:

```lua
local M = require('keymap_tracker')

M.record(mode, lhs, desc, src)  -- public hook for external sources
M.flush()                        -- force write of buffered queue
M.path                           -- "~/.local/share/nvim/keymap_usage.log"
```

**Mechanism**: monkey-patches `vim.keymap.set` early in `init.lua`. The wrapper:

- Returns the rhs unchanged if `opts.expr == true`. Wrapping breaks evaluation
  semantics (rhs is evaluated per keystroke and the return value is the typed keys).
- For function rhs: returns a closure that calls `M.record(...)` then forwards args.
- For string rhs: returns a closure that calls `M.record(...)` then `nvim_feedkeys`
  with the recursive `m` flag (so `<Plug>` and recursive maps still resolve). Note:
  the previous draft's `vim.cmd(rhs)` is wrong for non-`<cmd>` strings like `'<C-w>h'`.
- Records `mode` from `vim.api.nvim_get_mode().mode` at fire time, not at definition
  time, since one shim can be registered for multiple modes.

**Buffering**: queue in memory, flush every 30s via `vim.uv.new_timer()` plus
`VimLeave`, `FocusLost`, and `BufWritePost` autocmds.

**Coverage and the four miss cases**: the shim catches `vim.keymap.set` only. The
user's `lua/keymaps.lua` is 100% `vim.keymap.set` — coverage of *user* mappings is
complete. Plugin mappings registered via `nvim_set_keymap` direct, `:map` Ex, or
Vimscript will not be tracked. Mitigations, in order of complexity:

1. **Accept the gap.** Reconciliation against the snapshot surfaces never-tracked
   entries; the snapshot's `sid` field separates user from plugin origin, so a future
   `kmap-unused` consumer can ignore plugin entries by default.
2. **Layer a parallel shim** of `vim.api.nvim_set_keymap` and
   `vim.api.nvim_buf_set_keymap` (~20 lines, tagged `src:"api"`).
3. **The Ex/Vimscript path has no Lua hook** — those mappings can only be observed via
   query-time enumeration and are not invocation-trackable.

Recommend (1) first; layer (2) when reconciliation reveals real misses.

### Integration

| File | Change |
|---|---|
| `nvim/.config/nvim/init.lua` | Insert `require('keymap_tracker')` between `vim.g.mapleader = ' '` (line 1) and `require('configs')` (line 2). Loading before `require('plugins')` and `require('keymaps')` ensures every subsequent `vim.keymap.set` is wrapped, including plugin-registered maps. |
| `nvim/.config/nvim/lua/pickers/keybindings.lua` | One-line addition at end of `build_results()`: `pcall(function() require('keymap_snapshot').write() end)`. Picker open is the natural snapshot trigger. |
| `nvim/.config/nvim/lua/keymap_snapshot.lua` | New file (Primitive 1). |
| `nvim/.config/nvim/lua/keymap_tracker.lua` | New file (Primitive 2). |

### What becomes easy on top of these primitives

Sketches only — kept in mind during design, not implemented here.

- **Reconciliation `kmap-unused`**: `comm -23` of snapshot lhs vs log lhs in shell, ~5
  lines of jq + sort. (`comm -23 <(jq -r 'select(.buffer==0 and .expr==false) |
  "\(.m) \(.lhs)"' snapshot | sort -u) <(jq -r '"\(.m) \(.lhs)"' log | sort -u)`.)
- **Usage counts in `<leader>sk`**: load the log into a `(mode,lhs) → count` table
  once per session in `pickers/keybindings.lua`; append count to the display column.
  ~15 lines. If this becomes a hot path, back it with the checkpointed decayed-score
  table from [Storage strategy](#storage-strategy-append-log-vs-aggregate-on-write)
  instead of a full log replay.
- **Mode-aware picker**: today's picker is normal-mode only. With Primitive 1 it
  trivially extends to all modes with a mode-filter prompt — same picker shape, swap
  the data source from `which-key.buf.get({mode='n'})` to `keymap_snapshot.collect()`.
- **Weekly summary**: shell script over the log grouped by week + mode.
- **Suggestion engine**: rank keymaps by `desc` similarity to a query, weighted by
  inverse-usage — surfaces forgotten keymaps. Stretch goal.
- **`kmap-top` shell alias**: `jq -r '"\(.m) \(.lhs)"' keymap_usage.log | sort | uniq
  -c | sort -rn | head -30`.

---

<a id="future-multi-machine-sync"></a>
## Future: multi-machine sync

Not yet implemented; captured here so the ideation isn't lost. The user works on two
machines (work laptop, personal laptop) and wants usage on one to count toward the
aggregate seen on the other, and vice versa. Sync is allowed to be occasional or
incomplete — hobby project, not a correctness-critical system — which opens up
simpler options than a proper CRDT.

Two viable shapes, in increasing order of infra:

1. **File-sync the append-log itself.** Each machine keeps its own
   `keymap_usage.<hostname>.log`, synced via an existing trusted transport — most
   likely this dotfiles repo's git, since that's already the cross-machine sync
   mechanism in use. Never sync a single shared file two machines write concurrently;
   each machine's log stays local and distinct, and synced logs are unioned at read
   time (`cat *.log | jq ...`, or a `sort -u`-style merge). No conflict is possible
   since log lines are append-only and independently keyed by machine. Zero new
   infra, and it slots directly under the existing NDJSON design — the "merge" is
   `cat`+`jq`, not new code. Downside: sync is manual/periodic (a commit+pull, maybe
   hooked into shell startup) rather than continuous.
2. **Remote store as source of truth.** Each machine writes usage events (or
   increments) directly to a hosted DB when online, instead of (or alongside) the
   local log. **Turso/libSQL embedded replicas** fit best: local SQLite for
   fast/offline writes, transparent background sync to a remote libSQL server, no
   custom queueing code to write. A lighter alternative is a plain HTTP endpoint
   (e.g. a Cloudflare Worker + D1) that each machine POSTs events to — simpler client
   code, but an event fired while offline is just lost rather than queued, an
   acceptable trade given the project doesn't need complete data.

**Recommendation**: start with option 1 (git-synced per-machine logs, merged at read
time) if/when sync is implemented — zero new infra, reuses the existing NDJSON
append-log design as-is. Revisit option 2 (Turso) only if continuous/near-real-time
sync across machines becomes worth the added dependency.

---

## Alternatives considered

**`vim.on_key` keystream listener.** Subscribe to raw key bytes; match against the
snapshot's `lhsraw` set after each key. Catches every fire regardless of registration
path. *Rejected*: reproduces the resolver's FULL/PARTIAL/NONE trichotomy and
`timeoutlen` logic in Lua — overcounting (logging both `j` and `jj`) or
undercounting (logging `<leader>` prefix presses) are likely failure modes.
Performance-sensitive on every keystroke. This concern is not theoretical:
hardtime.nvim's soft-hint feature uses exactly this approach and does **not**
attempt the timeout/partial-match disambiguation — it tolerates false positives
because a wrong hint is cheap. Our accurate persistent-log use case does not have
that luxury. See [Findings (condensed)](#findings-condensed).

**Explicit `map()` helper, migrate all call sites.** Define a `map(mode, lhs, rhs,
opts)` helper and rewrite every `vim.keymap.set(...)` line. *Rejected*: misses every
plugin map, so the snapshot and log universes systematically disagree; high churn for
low coverage; new keymaps elsewhere need discipline. The shim achieves equivalent
coverage with one require and zero call-site edits.

---

## Verification

1. `tail -F ~/.local/share/nvim/keymap_usage.log` in a separate terminal pane.
2. Open nvim, press `<leader>sf`. Within 30s (timer flush) — or immediately on
   `FocusLost` when switching to the tail pane — one new NDJSON line should appear
   with `lhs:"<leader>sf"`.
3. Press `<leader>sk` to trigger the snapshot write. `wc -l
   ~/.local/share/nvim/keymap_snapshot.ndjson` should comfortably exceed the
   normal-mode-only result count of the picker (since the snapshot covers all eight
   modes).
4. If the config has any `expr` mapping, press it. **No log line should appear** — expr
   mappings are deliberately unwrapped.
5. Test data isolation: temporarily redirect via `:lua
   require('keymap_tracker').path = '/tmp/test.log'` before manual testing, reset
   after.

---

## Files to create/change

- `nvim/.config/nvim/lua/keymap_snapshot.lua` — new (Primitive 1).
- `nvim/.config/nvim/lua/keymap_tracker.lua` — new (Primitive 2).
- `nvim/.config/nvim/init.lua` — insert `require('keymap_tracker')` after line 1.
- `nvim/.config/nvim/lua/pickers/keybindings.lua` — append snapshot trigger to
  `build_results()`.

Reusable existing utilities to call rather than reimplement:

- `lua/pickers/keybindings.lua` — pattern for cached, fuzzy-searchable keymap UI;
  future usage-count picker extends the same shape.
- `lua/builtins.lua` — hardcoded built-ins (`u`, `p`, `dd`, …); could merge into the
  snapshot if "built-in motions I never use" becomes interesting.
- `lua/whichkey.lua:57-70` `keywords` table — alias mappings for fuzzy search; future
  picker reuses.

---

<a id="open-questions--decisions-pending"></a>
## Open questions / decisions pending

Three small choices to make before implementation. Defaults are listed; flag any to
change.

1. **Tracker load position in `init.lua`.**
   - **Default**: insert `require('keymap_tracker')` *before* `require('plugins')` (i.e.
     between line 1 `vim.g.mapleader = ' '` and line 2 `require('configs')`). Catches
     plugin-registered `vim.keymap.set` calls in addition to user maps.
   - **Alternative**: insert *between* `require('plugins')` and `require('keymaps')`.
     Scopes the log to user maps only — cleaner signal but plugin map usage is
     untracked. Easy to switch later.

2. **Snapshot trigger.**
   - **Default**: piggy-back on `<leader>sk` open by appending one line to
     `pickers/keybindings.lua:build_results()`. Snapshot refreshes naturally whenever
     the user reaches for the picker.
   - **Alternative**: separate `:KeymapSnapshot` Ex command, no automatic trigger.
     Requires explicit refresh; useful if the picker integration proves brittle.

3. **`nvim_set_keymap` shim — include now, or defer?**
   - **Default**: defer until reconciliation reveals real plugin misses. Most user maps
     go through `vim.keymap.set` already.
   - **Alternative**: include immediately (~20 lines, tagged `src:"api"`). Gives
     broadest invocation coverage with negligible cost.

A fourth open question may arise during implementation: **whether to fold abbreviation
modes (`ia`, `ca`, `!a`) into the default snapshot.** Defer; the decision is local to
`keymap_snapshot.lua` and can be made when writing it.

---

## Why this doc exists: Track C of the keymap-optimization audit

This tracker was scoped out of `keymap-optimization.md`'s "Track C —
Ergonomics: measure, then optimize hot paths" (that plan has since been
deleted; its other tracks — A: correctness fixes, B: namespace/mnemonic
consistency, D: tooling/guardrails — all landed and are reflected in
GUIDE.md and the `keymap-audit` skill).

> **Status: deferred (2026-07-09).** Nothing below is being implemented now.

Highest potential payoff, highest muscle-memory cost, and — crucially — the
config has **no usage data** to rank candidates. Guessing frequency is how
speculative maps like `<A-hjkl>` happen. So:

### C1. Implement this tracker first (2 small modules)

The research in this doc is done; Primitive 1 (snapshot) + Primitive 2 (usage
log) are ~150 lines total. Let it run for 2–4 weeks.

**Why it's better than optimizing now:** the audit's Track B reorganizations
were each justified by *semantics*; Track C changes are justified only by
*frequency* (shortest keys for hottest actions). Without the log you'd
optimize by anecdote. With it, decisions become one-liners:
`jq -r '.lhs' keymap_usage.log | sort | uniq -c | sort -rn | head -20`.

C2 (leader-alias promotions) and C3 (`<A-hjkl>` data decision) moved to
`nvim-backlog.md` → "Editing power & motions".

---

<a id="resuming-notes"></a>
## Resuming notes

If picking this up after time has passed:

- The user's `init.lua` line numbers may have shifted — re-verify with `Read` before
  inserting the `require('keymap_tracker')` line.
- The user's `pickers/keybindings.lua` `build_results()` function shape may have
  changed. The integration is one `pcall` line at the end of that function; verify the
  function name and end position before adding it.
- Cited file/line references (in the enumeration Background above) were pinned to the
  Neovim revision at `/Users/dhruv/src/neovim/` and the which-key clone at
  `~/.local/share/nvim/site/pack/core/opt/which-key.nvim` (folke/which-key.nvim,
  commit `3aab2147e7`, v3.17.0) at research time. They have drifted before — re-grep
  for the function names (`keymap_array`, `mapblock_fill_dict`, `get_map_mode`)
  against current source before relying on any line number.
- The `<leader>sk` picker currently passes `mode = 'n'` to `which-key.buf.get` — this
  is a real coverage gap. Once Primitive 1 lands, the picker can switch its data
  source from the which-key tree to `keymap_snapshot.collect()` and gain all-mode
  coverage.
- If using Neovide, then Cmd-based keymaps are also an option. Should consider this as
  well.
  - Can be as easy as manually tracking this for now.
  - Goal is to make sure we can integrate Neovide keymaps as well at a later date.
- Note for myself:
  - Consider the usage of this data: should we include timestamps? What other metadata
    is useful here?
