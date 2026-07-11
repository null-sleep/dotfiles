# Plan: Keymap usage tracker

Primary goal: track every explicit keymap invocation to a persistent log file.
Build on top of a reusable "all keymaps" enumeration primitive so future features
(never-used analysis, usage-aware pickers, weekly summaries) layer on cheaply.

---

## Status

- **Start here if you want the crux in plain English**: the Q&A at the top of
  [Background: why "one mapping fired" is ambiguous](#background-why-one-mapping-fired-is-ambiguous-the-atomization-problem)
  explains, without jargon, what "solving atomization" actually means and why it's hard.
- Research: **complete** — Neovim resolver internals, which-key approach, the
  enumeration story (`nvim_get_keymap` semantics, mode coverage, miss cases), a prior-art
  survey (no existing plugin solves the persistent-log goal; enumeration is well-covered),
  storage/aggregation patterns from analogous tools (zoxide vs atuin), and Neovim core's
  own API roadmap (no "keymap fired" event exists or is close to landing) are all
  documented below.
- Architecture: **proposed** — two primitives (`keymap_snapshot.lua`,
  `keymap_tracker.lua`) with file-based outputs, integrated via two small edits to
  existing files. Recommended approach is recorded; alternatives rejected with
  reasoning.
- Decisions pending: see
  [Open questions / decisions pending](#open-questions--decisions-pending) at the end of
  this doc — three small choices remain before implementation.
- Code: **not yet written.** No files created or modified in `nvim/.config/nvim/`.
- Stretch idea, unrelated to shipping this plan: see
  [Recommendation: a real upstream fix](#recommendation-a-real-upstream-fix) — a scoped,
  plausible Neovim core contribution that would close this doc's own userland coverage
  gaps for everyone, not just this tracker. Nothing here depends on it.

To resume: read the Status, the Architecture section, and the Open questions; pick
answers for the three pending decisions; then implement Primitive 1 first (it's
independent and immediately useful even without the tracker), Primitive 2 second,
then the two integration edits.

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
   summaries, suggestion engines.

Scope: all explicitly mapped keys — `<leader>`, `<C->`, `<M->`, `<S->`, `yp`, `zg`,
etc. Native unmapped motions (`j`, `w`) are out of scope.

Log line format (NDJSON, one line per invocation):

```
{"t":"2026-05-04T14:22:01","m":"n","lhs":"<leader>sf","desc":"Search: Files"}
```

NDJSON over flat text because `lhs` and `desc` can contain spaces, brackets, and
quotes — quoting via JSON is cheaper than re-parsing later.

---

## Background: how Neovim resolves keymaps

Relevant because it explains why hooking at `vim.keymap.set` is the right level and why
`vim.on_key` is the wrong one. The core lives in two files: `mapping.c` (storage) and
`getchar.c` (resolution).

### The key insight

Each keystroke goes into a typeahead buffer. To resolve, Vim hashes the first byte to
get a short linked list of mappings sharing that first byte (typically 1–5 entries),
walks it, and classifies each entry against the buffered bytes as **full**, **partial**,
or **no match**. If any partial match is found, Vim waits up to `timeoutlen` ms for more
input. Otherwise the longest full match (if any) fires; if there's none, the buffered
bytes flush as raw keys. There's no trie — just "bucket + walk + trichotomy + timeout."

### Worked example: typing `gd`

Suppose the `'g'` chain (Normal mode) has three entries: `gd`, `gg`, `gcc`. User types
`g`, then `d`. Typeahead state:

```
typebuf.tb_buf:  [ g ][ d ][   ][   ]...
                  ↑    ↑
                 tb_off tb_off + tb_len  (tb_len = 2)
```

Resolver walks the `'g'` chain, comparing each `m_keys` against `tb_buf[tb_off..]`:

```
       m_keys  vs  tb_buf       byte 0   byte 1   verdict
       ─────────────────────    ──────   ──────   ────────────────
node1: "gd"        "gd"         g==g ✓   d==d ✓   FULL  → remember as candidate
node2: "gg"        "gd"         g==g ✓   g!=d ✗   NONE
node3: "gcc"       "gd"         g==g ✓   c!=d ✗   NONE
```

End of chain. No partial match was found, so the longest full match wins → `gd` fires
immediately.

### The trichotomy

That example showed all three verdicts. Formalized:

```
  case A: FULL                  case B: PARTIAL                case C: NONE
  ──────────────                ───────────────                ─────────────
  m_keys: "gd"                  m_keys: "gcc"                  m_keys: "gg"
  tb_buf: "gd|"                 tb_buf: "gc|"                  tb_buf: "gd|"
          ─── matched fully             ── matched, but                ─ diverged
                                            tb_len < keylen

  mlen == m_keylen              mlen == tb_len                 m_keys[mlen] != tb[mlen]
                                  && tb_len < m_keylen

  → remember as candidate       → set keylen=KEYLEN_PART_MAP   → ignore, bump max_mlen
    (longest one wins)             break the chain walk
                                   (caller must wait)
```

A FULL match is **provisional**, not immediate: `aa` and `aaa` may both be mapped, so
the resolver remembers the longest FULL seen and only fires it once it knows nothing
extends it.

### Worked example: `jj` → `<Esc>` with timeoutlen=200

Now the partial case. The `'j'` chain (Insert side) has one entry, `"jj"`:

```
t=0ms     tb_buf: [j]      scan: "jj" vs "j" → mlen=1, tb_len=1, keylen=2
                            → PARTIAL. keylen=KEYLEN_PART_MAP. Wait.
                            inchar(wait=200ms)
                                    │
          ┌─────────────────────────┴──────────────────────┐
          ▼                                                ▼
t=80ms    you press 'j'                          t=200ms   timeout fires
          tb_buf: [j][j]                                   timedout=true
          rescan: "jj" vs "jj" → FULL                      rescan: PARTIAL guard
          ins_typebuf("<Esc>")                              now bypassed; no FULL
          → <Esc> fires                                     → 'j' fires as raw key
```

Two outcomes from the same partial state, distinguished only by whether more input
arrived in time.

### Firing rule (summary)

A mapping fires the moment **one** of these is true:

- A full match exists and no entry in the same hash chain extends it (no partial match
  possible).
- A full match exists with `<nowait>`.
- `timeoutlen` ms elapsed with no further input while a partial match was buffered — the
  longest full match seen so far wins; if there is none, the buffered bytes are flushed
  as raw keys.

That's the whole behavior. The rest of this section explains the data structures and
algorithm that implement it — useful for understanding *why* the right hook for our
tracker is at the rhs (after resolution) rather than at the keystream (before).

---

### Storage: hashed linked lists of `mapblock_T`

Each mapping is a node in a singly-linked list (`src/nvim/mapping_defs.h:11`):

```c
struct mapblock {
  mapblock_T *m_next;
  char *m_keys;     // lhs
  char *m_str;      // rhs
  int m_keylen;
  int m_mode;       // bitmask of modes this applies in
  char m_nowait;
  ...
};
```

These nodes hang off a 256-slot hash table (`src/nvim/mapping.c:68`):

```c
static mapblock_T *(maphash[MAX_MAPHASH]) = { 0 };
```

The hash is just the **first byte of the lhs**, with one bit of mode separation:

```c
#define MAP_HASH(mode, c1) \
  (((mode) & (MODE_NORMAL|MODE_VISUAL|MODE_SELECT|MODE_OP_PENDING|MODE_TERMINAL)) \
   ? (c1) : ((c1) ^ 0x80))
```

That `^ 0x80` trick keeps Normal/Visual mappings in different buckets from
Insert/Cmdline mappings even when they share a first byte, so the resolver only walks
one chain. Each `buf_T` also has `b_maphash[]` for buffer-local mappings — these are
tried first.

The `'g'` chain from the first example, plus the `'j'` chain from the second:

```
maphash[256]  (global; curbuf->b_maphash[256] mirrored per-buffer)

  index = MAP_HASH(mode, first_byte_of_lhs)

  ┌─────┐
  │  0  │ → NULL
  │  1  │ → NULL
  │ ... │
  │ 'g' │ → ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
  │ 103 │   │ m_keys: "gd" │ →  │ m_keys: "gg" │ →  │ m_keys: "gcc"│ → NULL
  │     │   │ m_keylen: 2  │    │ m_keylen: 2  │    │ m_keylen: 3  │
  │     │   │ m_mode: N    │    │ m_mode: N    │    │ m_mode: N    │
  │     │   │ m_str: ...   │    │ m_str: ...   │    │ m_str: ...   │
  │     │   └──────────────┘    └──────────────┘    └──────────────┘
  │ ... │
  │ 'j' │ → ┌──────────────┐
  │ 106 │   │ m_keys: "jj" │ → NULL          (lives in INSERT-side bucket,
  │     │   │ m_mode: I    │                  i.e. index 'j' ^ 0x80 = 234)
  │     │   └──────────────┘
  │ ... │
  │ 234 │ → (jj lives here, not 106 — mode XOR keeps insert separate)
  │ ... │
  │ 255 │ → NULL
  └─────┘
```

A chain is **all mappings whose lhs starts with the same byte AND share the
Normal-vs-Insert side of the XOR**.

### The typeahead buffer

The other key structure (`src/nvim/getchar_defs.h:31`):

```c
typedef struct {
  uint8_t *tb_buf;       // pending input bytes
  uint8_t *tb_noremap;   // per-byte noremap flags (parallel array)
  int tb_off;            // start of valid range
  int tb_len;            // bytes valid
  int tb_maplen;         // bytes that came from a map's rhs
  ...
} typebuf_T;
```

Every keystroke goes here first. Mapping resolution happens *against* this buffer, not
against incoming raw keys.

### Byte-level shape of `m_keys`, `tb_buf`, and `tb_off`

Both `m_keys` (the mapping's lhs) and `tb_buf` (the typeahead) are **flat byte arrays in
the same encoding**, which is why the resolver compares them with a plain byte-for-byte
loop.

- **`m_keys`** — a NUL-terminated `char *` holding the lhs as bytes. Multi-byte keys
  like `<Esc>`, `<C-w>`, `<leader>` are pre-encoded into Vim's internal byte form
  (typically a `K_SPECIAL` 0x80 escape sequence + 2 bytes for special keys), so by the
  time it lives on `mapblock_T` it's just a flat byte string.
  `m_keylen = strlen(m_keys)`.
- **`tb_buf`** — a flat `uint8_t *` byte array, the typeahead ring buffer. Same encoding
  as `m_keys`. Sized `tb_buflen` total.
- **`tb_off`** — the offset into `tb_buf` where *valid pending bytes start*. The buffer
  is used like a ring: bytes are consumed from the front by **advancing `tb_off`**, not
  by `memmove`'ing the array. So:

```
tb_buf:  [ . ][ . ][ . ][ g ][ d ][ . ][ . ]...
                       ↑         ↑
                      tb_off    tb_off + tb_len
                      (=3)       (=5)
```

The valid window is `tb_buf[tb_off .. tb_off + tb_len)`. `del_typebuf(n, 0)` consumes by
bumping `tb_off += n`; `ins_typebuf()` writes new bytes either at `tb_off` (replacing
what was matched, for rhs substitution) or at the tail. That's why every comparison in
the resolver indexes as `tb_buf[tb_off + mlen]` — `tb_off` is the cursor.

### The resolver: `handle_mapping` (`src/nvim/getchar.c:2184`)

Returns a `map_result_T` enum (`map_result_fail | _get | _retry | _nomatch`):

1. Hash the first byte of typeahead → get the chain head (buffer-local first, then
   global).
2. Walk the chain. For each node whose first byte matches and whose `m_mode` intersects
   current state, compare `mp->m_keys[]` against `typebuf.tb_buf[]` byte-by-byte and
   classify into the FULL/PARTIAL/NONE trichotomy above.
3. Decision (lines 2319–2345):
   - If a partial match was found AND not `timedout` AND no `<nowait>` full match →
     return without firing. Caller will read more input.
   - Otherwise the longest full match wins: `ins_typebuf()` substitutes the rhs into the
     typebuf at `tb_off`, and the function returns `map_result_retry` so resolution
     restarts on the new bytes (this is how recursive mappings work — and where
     `m_noremap` flags in `tb_noremap[]` block re-expansion).

### `mlen` vs `m_keylen`: the two lengths driving classification

These two integers do all the work in the comparison loop.

- **`m_keylen`** — the static length of *this mapping's* lhs in bytes. Stored on
  `mapblock_T` when the mapping is created and never changes. For `"gd"` it's 2; for
  `"gcc"` it's 3; for `<leader>sf` (where `<leader>` expands to e.g. `\`) it's 3
  (`\sf`).
- **`mlen`** — a *per-comparison* counter. Starts at 1 (the first byte already matched —
  that's why we're walking this chain at all) and counts up as long as
  `m_keys[mlen] == tb_buf[tb_off + mlen]`. The loop bails on a mismatch, or naturally
  when it runs out of typed bytes (`mlen < typebuf.tb_len` is the loop guard).

After the loop, comparing `mlen` against `m_keylen` and `tb_len` gives the verdict
(`getchar.c:2296`):

```c
if (mlen == keylen || (mlen == typebuf.tb_len && typebuf.tb_len < keylen)) {
  // full or partial — keep this candidate
} else {
  // diverged — bump max_mlen and skip
}
```

Five worked cases against the same `'g'` chain (`gd`, `gg`, `gcc`):

```
                            tb_len  scan trace                  mlen  m_keylen  verdict
─────────────────────────── ──────  ─────────────────────────── ────  ────────  ────────
1) typed "gd" vs "gd"          2    [1]:'d'=='d' ✓, loop ends     2      2      FULL
                                                                                (mlen == m_keylen)

2) typed "gx" vs "gd"          2    [1]:'d'!='x' ✗, break         1      2      NONE
                                                                                (mlen < both;
                                                                                max_mlen → 1)

3) typed "gc" vs "gcc"         2    [1]:'c'=='c' ✓, loop ends     2      3      PARTIAL
                                                                                (mlen == tb_len
                                                                                 < m_keylen)

4) typed "gcx" vs "gcc"        3    [1]:'c'=='c' ✓, [2]:'c'!='x' 2      3      NONE
                                    ✗, break                              (mlen != m_keylen,
                                                                           mlen != tb_len)

5) typed "g" alone vs "gd"     1    loop doesn't enter            1      2      PARTIAL
                                    (mlen=1 not < tb_len=1)              (mlen == tb_len
                                                                          < m_keylen)
```

Two non-obvious points:

- **The loop is bounded by `tb_len`, not `m_keylen`**. So scanning a 3-byte typebuf
  against a chain of 50-byte mappings is still O(tb_len) per node — a partial match is
  detected the moment the loop *naturally exits*, not by walking to the end of `m_keys`.
- **`m_keylen` is also the tiebreaker for full matches.** When multiple full matches
  exist (e.g. both `aa` and `aaa` are mapped and you typed `aaa`), the resolver picks
  the one with the largest `m_keylen` — that's the `mp_match_len` bookkeeping in the
  loop.

### The timeout (in `vgetorpeek`)

The wait that turns a PARTIAL into either an extended FULL or a flush is in the caller
`vgetorpeek` (`src/nvim/getchar.c:2583`). After `handle_mapping` reports a partial
match, it calls `inchar()` with a wait time (line 2929):

```c
wait_time = (int)p_tm;   // 'timeoutlen' for partial map
// or p_ttm ('ttimeoutlen') for partial keycode
// or -1 for indefinite
```

If `inchar()` returns NUL, that's the timeout (line 2960):

```c
if (wait_tb_len > 0) {  // timed out
  timedout = true;
  continue;
}
```

Then `handle_mapping` runs again, and this time the `!*timedout` guard at line 2320
fails, so the partial-match wait is skipped and the longest remembered full match wins.

### The full decision tree

Trichotomy + timeout combined — the four paths the resolver picks from after scanning a
chain:

```
                ┌─────────────────────────────────────┐
                │ Walked the chain. What did we find? │
                └─────────────────────────────────────┘
                                 │
       ┌─────────────────────────┼─────────────────────────────┐
       ▼                         ▼                             ▼
  partial match            full match,                    no match
  found?                   no partial?                    at all?
       │                         │                             │
       │ yes                     │ yes                         │ yes
       ▼                         ▼                             ▼
  is <nowait> on             FIRE: ins_typebuf(rhs),       FIRE raw key:
  a full match?              return map_result_retry       return map_result_get
       │                                                    (consume tb_buf[tb_off])
       ├── yes → fire that one
       │
       └── no → wait for more input via inchar(wait=p_tm)
                          │
                          ▼
                  inchar returned a byte?
                          │
              ┌───────────┼────────────┐
              ▼                        ▼
         yes: append to            no (NUL = timed out):
         tb_buf, restart           timedout=true, restart
         scan                      scan — partial-wait guard
                                   now skipped, longest full
                                   match wins (or raw key fires
                                   if no full match existed)
```

So the data structure is a **mode-segregated, first-byte-hashed linked list of
`mapblock_T`**, and the algorithm is **a bounded prefix scan over the typeahead buffer
with a `(partial, full, none)` trichotomy and a `timeoutlen` tie-breaker**. There's no
trie — Vim relies on the chains being short (typical first-byte buckets hold few
mappings) and on `MAXMAPLEN = 50` capping per-comparison work.

### Implications for this tracker

- The right hook level is the **rhs**, not the keystream. By the time Neovim is about to
  execute a mapping it has already resolved partial/full/timeout/noremap — wrapping the rhs
  means we log exactly when a mapping *fires*, with no reimplementation of that logic.
  This is what Option A does.
- `vim.on_key` (Option B) operates one layer too low: it sees raw bytes before the resolver
  classifies them, so it can't distinguish "user typed `j` as a prefix of `jj`" from "user
  typed `j` as a motion". Reproducing the trichotomy + timeout in Lua is the complexity
  Option B's "Cons" alludes to.
- There is no "keymap fired" autocmd event because Neovim's event model fires on
  *consequences* (TextChanged, CursorMoved, ModeChanged, TextYankPost) rather than on
  command dispatch. That's why a wrapper is needed at all.
- Confirmed via a search of neovim/neovim's own issue tracker (see
  [Prior art: Neovim core API status](#prior-art-neovim-core-api-status)) that no such
  event exists and none is close to landing — the wrapper is the long-term design, not a
  stopgap awaiting a future core feature.

---

## Background: how which-key.nvim approaches the same problem

Worth comparing because which-key faces a similar problem (knowing about every keymap and
reacting to prefix sequences) and solves it differently. The relevant files live at
`lua/which-key/` inside a folke/which-key.nvim checkout (see
[Appendix: code references](#appendix-code-references) for this machine's actual path).

### The key insight

which-key is a **popup-and-disambiguation layer**, not a replacement resolver. It installs
real Vim keymaps on a small set of "trigger" keys (e.g. `<leader>`, `g`, `z`); when one
fires, which-key takes over input via `getcharstr`, walks a trie of subsequent keys, then
**re-feeds the resolved prefix back to Vim** so Vim's own resolver runs the actual mapping.
There is no parallel implementation of `handle_mapping`.

### Worked example: `<leader>ff`

Start here — the rest of the section formalizes the pieces this example uses.

Spec:

```lua
require("which-key").add({
  { "<leader>f",  group = "find" },
  { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "files" },
  { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "grep" },
  { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "buffers" },
})
```

After the spec is parsed, which-key registers a *trigger* — a real Vim keymap on
`<Space>` whose rhs is a Lua callback (the `desc` is tagged `which-key-trigger` so the
rescan can ignore it):

```lua
vim.keymap.set("n", "<Space>", function()
  require("which-key.state").start({ keys = "<Space>" })
end, { nowait = true, desc = "which-key-trigger ..." })
```

Step by step:

```
1. User presses <Space>.
   → Vim's resolver fires the trigger keymap → state.start({keys="<Space>"}).

2. state finds node <Space> in the trie. Has children, no nowait, no own leaf
   → schedule popup after `delay` ms.

3. step() blocks on getcharstr. User presses 'f'.
   → state.check descends to <Space>f. Still a group
   → redraw popup with find/grep/buffers entries.

4. User presses 'f' again.
   → descends to <Space>ff. Leaf (count() == 0) → fall through to state.execute.

5. execute() suspends the trigger, prepends count/register if any, then
   nvim_feedkeys(replace_termcodes("<Space>ff"), "mit", false).
   → Vim's normal resolver matches the real <leader>ff keymap and runs Telescope.
   → A tick later, Triggers.schedule re-attaches the trigger.
```

The "suspend before re-feed" step is what prevents recursion: feeding `<Space>ff` back
while the trigger is still installed would route straight back into which-key.

### The three mechanisms behind that example

#### a) Triggers — real Vim keymaps that wake which-key

After building the trie, `Mode:attach` (`buf.lua:56-93`) walks it and picks "trigger"
nodes (plugin/proxy nodes with no own keymap; safe single-key prefixes like `g`, `z`,
`Z`; anything in `Config.triggers.mappings`). For each, `Triggers.add`
(`triggers.lua:39-53`) registers a real Vim keymap whose rhs starts the state loop. So
**`<leader>` becomes a real Vim keymap** — Vim's resolver still runs first; which-key
only sees control once Vim has resolved the trigger and dispatched its rhs. (This is why
the rescan filters out `which-key-trigger` descriptions — to avoid re-ingesting its own
work.)

#### b) The `state.start` loop

Once awakened (`state.lua:278-369`):

1. Look up the prefix node in the trie.
2. Show the popup; enter `while M.state` loop calling `getcharstr` (blocking) for each
   subsequent key (`state.lua:248-275`).
3. For each char, `state.check` (`state.lua:183-215`) tries `state.node:find(key)`:
   - If the resulting node has children **and** isn't `nowait` **and** hasn't `timedout`
     (delta > `timeoutlen`), descend and loop.
   - Otherwise call `state.execute`, which `nvim_feedkeys` the full prefix back to Vim
     with the `mit` flags — letting **Vim's own resolver** actually run the mapping.
     `Triggers.suspend` is called at the top of `execute` (`state.lua:222`) so the feed
     doesn't recurse; `Triggers.schedule` re-attaches a tick later
     (`triggers.lua:139-156`).
4. `<Esc>` cancels, `<BS>` pops up one level.

#### c) Timeout interaction

which-key does **not** override `timeoutlen`. It measures wall-clock since `state.started`
(`state.lua:188`) and combines that with `nowait` to decide whether a leaf+group node
should fire or wait (`state.lua:194-199`). The `delay` config (default 200ms,
`config.lua:13-15`) controls when the popup *appears* — independent of `timeoutlen`.

### The trie behind the loop

Where Neovim's core uses a flat hash table of linked lists keyed by first byte, which-key
uses a **trie** keyed by single key tokens (`<leader>`, `f`, `<C-w>`, …). Each
`wk.Buffer` (`buf.lua:147-160`) holds `modes: table<string, wk.Mode>`; each `wk.Mode`
(`buf.lua:7-12`) owns a `tree: wk.Tree` wrapping a `root: wk.Node`.

A `wk.Node` (`node.lua:3-25`) carries:

```
key            -- one token (e.g. "f")
keys           -- full prefix string ("<Space>f")
path: string[] -- token list
parent
_children: table<string, wk.Node>
keymap?        -- the REAL Neovim keymap from nvim_get_keymap
mapping?       -- the VIRTUAL which-key spec from wk.add() / presets / plugins
plugin?        -- e.g. "marks", "registers" for dynamic children
```

A node can be **both a leaf keymap and a group** simultaneously (e.g. `gc` is "comment
line" *and* the prefix of `gcc`). `node.lua:53-70` defines `__index` to fall through to
either `mapping` or `keymap`, so callers don't care which side defined
`desc`/`rhs`/`nowait`.

Continuing the worked example, the trie under `root` looks like:

```
root
└── " " (<leader>)            keys="<Space>"
    └── "f"                   keys="<Space>f"   mapping={group=true,desc="find"}
        ├── "f"               keys="<Space>ff"  keymap={rhs=":Telescope...", desc="files"}
        ├── "g"               keys="<Space>fg"  keymap={rhs=...,             desc="grep"}
        └── "b"               keys="<Space>fb"  keymap={rhs=...,             desc="buffers"}
```

A wider view across modes and buffers:

```
        wk.Buffer
           │
           ├── modes["n"]                    wk.Mode
           │     ├── tree                    wk.Tree
           │     │    └── root               wk.Node
           │     │          ├── "<Space>"   ──┐ "<leader>" group
           │     │          │     ├── "f"    │   group="find"
           │     │          │     │    ├── "f"  keymap → :Telescope find_files
           │     │          │     │    ├── "g"  keymap → :Telescope live_grep
           │     │          │     │    └── "b"  keymap → :Telescope buffers
           │     │          │     └── "s"    ...
           │     │          ├── "g"           ─┐ both leaf+group
           │     │          │     ├── "c"     │   "comment line"
           │     │          │     │    └── "c"   "toggle linewise"
           │     │          │     └── "d"        keymap → vim.lsp.buf.definition
           │     │          └── "z" ...
           │     └── triggers: wk.Node[]      -- nodes which-key has installed real keymaps on
           │
           └── modes["v"] ...
```

Build is **eager within a (buf, mode), lazy across them** (`buf.lua:182-199`): the tree
for a (buf, mode) is built the first time it's asked for, then cleared and rebuilt on
`BufReadPost`, `BufNew`, `LspAttach`, `LspDetach`, `RecordingEnter`, and after every
`wk.add()` call (`config.lua:331-333`). Not rebuilt per keystroke.

### Where the trie's contents come from

`Mode:update` (`buf.lua:117-145`) merges three sources onto the same nodes:

1. **Real Vim keymaps** — `vim.api.nvim_get_keymap(mode)` plus
   `vim.api.nvim_buf_get_keymap(buf, mode)` (`buf.lua:120-121`). Stored on `node.keymap`.
   Filters: skips entries whose `desc` contains `"which-key-trigger"` (those are
   which-key's *own* triggers), drops `<Plug>…` and `<SNR>…` mappings, stores `<Nop>` as
   virtual descriptions only (`buf.lua:125-131`).
2. **User spec** — everything pushed via `wk.add(spec)` / legacy `wk.register()`.
   Recursively parsed by `mappings.lua:_parse`, normalized into a flat `wk.Mapping[]`
   (`config.lua:323-334`), then re-inserted as `virtual = true`. Lands on `node.mapping`.
3. **Plugin/preset specs** — `plugins/init.lua:9-23` loads `marks`, `registers`,
   `spelling`, `presets`. Each contributes a spec routed through the same `Config.add`
   path. `marks` adds a `plugin = "marks"` group on `'` and `` ` ``; the *actual* mark
   list is computed lazily by `plugins/marks.lua:33-62` and materialized as ephemeral
   child nodes via `Node:expand` (`node.lua:119-180`).

After insertion, `Tree:fix` (`tree.lua:72-79`) prunes nodes that are neither real
keymaps, useful groups, nor have a `desc`.

### Limitations and gotchas

- **Single-key trigger safelist** (`buf.lua:28-36`): triggers auto-install only for
  single keys `g`, `z`, `Z` (plus anything explicitly listed in
  `Config.triggers.mappings`). Other prefixes need explicit configuration.
- **Filtered keymap classes**: `<Plug>…`/`<SNR>…` dropped; `<Nop>` only as virtual desc;
  `which_key_ignore` desc → pruned.
- **Mode coverage**: trigger auto-install only for modes in `Config.triggers.modes`
  (defaults to `nxso`, `config.lua:32`). Insert/command/terminal not auto-watched.
  Macros suspend triggers entirely (`state.lua:54-63`).
- **Operator-pending + counts + registers**: handled by re-feeding
  (`state.execute`, `state.lua:228-239`) which prepends `vim.v.count` and `"<reg>` —
  but only outside xo mode (where Vim already has them pending).
- **Marks/registers**: dynamic plugin nodes via `Node:expand`; never persisted between
  invocations.
- **Not modeled**: dot-repeat semantics, `expr` mappings (stored but never evaluated),
  abbreviations.
- **Tree rebuild cost**: amortized — not per keystroke. Invalidated on
  buffer/LSP/recording events and after `wk.add()`. `Util.cache.{keys,norm,termcodes}`
  memoizes string parsing (`util.lua:3-7`).

### Implications for this tracker

- which-key shows that **`vim.api.nvim_get_keymap(mode)` + `nvim_buf_get_keymap(buf, mode)`
  is the canonical way to enumerate registered keymaps**. Useful for the `kmap-unused`
  cross-reference analysis (Option B's data source done right).
- which-key's trigger pattern (real keymap whose rhs is a Lua callback) is essentially
  what Option A does, applied to *every* mapping rather than just prefixes — hooking in
  at `vim.keymap.set` time means we get the same "callback runs when Vim decides to
  execute" guarantee for free, without needing a tree or trigger machinery.
- The choice to never reimplement `handle_mapping` and instead `nvim_feedkeys` back to
  Vim validates the wider principle: stay above the resolver, don't try to replicate it.
  Option A inherits this — wrapping the rhs runs *after* Vim has resolved
  partial/full/timeout/noremap, so we log exactly when a mapping fires.
- which-key's `desc`-based filtering (`which-key-trigger`, `which_key_ignore`) is a
  precedent for tagging the wrapper with a marker so future re-introspection can
  identify and skip wrapped entries.
- The trie + lazy-rebuild pattern is overkill for a usage logger but is the right
  starting point if we ever want **in-Neovim analysis** (e.g. a Telescope picker that
  shows "all mappings, sorted by usage count"). At that point, build the tree from
  `nvim_get_keymap` once and join against the log file — same shape as which-key's data
  source pipeline.

---

## Background: enumerating keymaps in Neovim

Reliable enumeration is the foundation of the second primitive. Findings drawn from
`/Users/dhruv/src/neovim/`.

### The canonical API

`nvim_get_keymap(mode)` (`src/nvim/api/vim.c:1601`) and `nvim_buf_get_keymap(buf, mode)`
(`src/nvim/api/buffer.c:859`) both delegate to `keymap_array(mode, buf, arena)`
(`src/nvim/mapping.c:2878`). This walks **all 256 maphash buckets exhaustively**
(`mapping.c:2896-2914`), filtering by `int_mode & m_mode` so a single `mapblock_T` can
match multiple mode queries.

Each entry, populated by `mapblock_fill_dict` (`mapping.c:2085-2141`), contains: `lhs`,
`lhsraw`, `lhsrawalt`, `rhs` *xor* `callback`, `desc`, `mode`, `mode_bits`, `noremap`,
`script`, `expr`, `silent`, `nowait`, `replace_keycodes`, `sid`, `lnum`, `buffer`,
`abbr`.

Buffer-local maps live on `b_maphash[]` per `buf_T` and are **not** returned by the
global call — query each loaded buffer separately. Abbreviations live in a separate
linked list (`first_abbr` / `b_first_abbr`); access via mode `"ia"`, `"ca"`, or `"!a"`
(`mapping.c:2891`).

### Mode coverage

Atomic vs alias mode letters (per `get_map_mode` at `mapping.c:982-1017`):

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

| Class | Source | Filter rule |
|---|---|---|
| `<Plug>...` | `keycodes.h:197,450` | `lhs:sub(1,6) == "<Plug>"`. Stored in maphash; not directly user-invokable. |
| `<SNR>...` | Vimscript script-local | `lhs:sub(1,5) == "<SNR>"`. Same. |
| `<Nop>` | `mapping.c:355,261` | `m_str == ""` and no callback. Real binding (user explicitly disabled the lhs); keep but mark. |
| `expr` mappings | `m_expr` set at `mapping.c:528,819` | rhs evaluated per keystroke (`eval_map_expr` at `mapping.c:1635-1684`); **don't wrap**. |
| Default Neovim maps (e.g. `Y` → `y$`) | `runtime/lua/vim/_core/defaults.lua:108` | Real entries in maphash, `desc:match(':help')`. Keep. |

which-key applies the `<Plug>`/`<SNR>` filter at `lua/which-key/buf.lua:129` (see
[Appendix: code references](#appendix-code-references) for this machine's actual checkout
path).

### Definition-time vs query-time

A `vim.keymap.set` shim (`runtime/lua/vim/keymap.lua:57-105`, a thin Lua wrapper over
`nvim_set_keymap`) catches Lua-level sets only. **Misses**:

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
exposed via `nvim_get_keymap`; only via `maparg()` with the compatible flag
(`mapping.c:2109-2111`). The API's `lhs` field is already in str2special form, which is
human-readable.

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

(Design-pattern comparison drawn from general knowledge of analogous frequency-tracking
CLI tools rather than a source read — lower citation confidence than the Neovim/which-key
sections above, which are pinned to specific files/lines.)

Usage trackers split into two fundamentally different strategies:

- **Aggregate-on-write, with decay** (zoxide's `db.zo`; lineage autojump/fasd/`z.sh`): no
  event log at all. One compact DB of `(key, score, last_accessed)` tuples is loaded fully
  into memory, updated in place per event, and rewritten atomically. Scoring is *frecency*
  (frequency + recency — the concept Firefox's URL bar popularized); a decay/aging step
  multiplies every score down by a constant (~0.9) once their sum crosses a threshold,
  keeping the file bounded forever and letting stale entries fade. Cheap O(1)-ish storage
  and instant top-N, but the raw history is permanently discarded — no re-asking a
  question the score formula wasn't designed for (usage-by-week, alternate decay curves).
- **Log everything, aggregate-on-read** (atuin shell history; McFly): every event is a
  full timestamped record appended to a real store (atuin: local SQLite, optionally
  synced). No decay, no in-place aggregation — all aggregation happens by query at read
  time. Unbounded but prunable; full fidelity preserved for any future analysis.

**This doc's NDJSON append-log (ground truth) is the atuin-style strategy, and that's the
right call** given the stated future goals — reconciliation, weekly summaries, and a
suggestion engine all need the raw log, not a decayed scalar. This validates the existing
design; it changes nothing.

The one place the zoxide-style structure legitimately helps: a live usage-aware picker
(see [What becomes easy](#what-becomes-easy-on-top-of-these-primitives)) would otherwise
replay the entire NDJSON log on every open — wasteful. An in-memory `(mode,lhs) → decayed
score` table, maintained incrementally and checkpointed to disk periodically, would beat a
full log scan for that one consumer. This is a *derived, secondary* structure (a
materialized view over the log), **not** a replacement — the log stays ground truth,
exactly as atuin keeps a full log while nothing stops a materialized view on top. A
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
  ~15 lines. If this becomes a hot path (picker opened often on a large log), back it
  with the checkpointed decayed-score table from [Storage strategy](#storage-strategy-append-log-vs-aggregate-on-write)
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

## Background: why "one mapping fired" is ambiguous (the atomization problem)

> **In plain terms, before the technical walkthrough below — this is the crux of the
> whole problem.**
>
> **Q: What do we mean by "solve atomization"? What's the problem, and why do we want to
> solve it?**
>
> Think of ordering coffee: you say "one," then "medium," then "latte" — three separate
> words, but you and the barista both know it's *one order*. Vim's engine doesn't work
> that way. When you type `c`, then `i`, then `{` (change-inside-braces), Vim hears three
> completely separate keystrokes, one at a time, and only some scratch notes in the back
> of its head ("there's an edit pending... what kind... on what") tie them together.
> There's no single moment where Vim goes "order received, that was one thing." You'd
> have to watch closely and guess when the "order" started and ended.
>
> **"Solving atomization" means: teach Vim to actually know, in one clean place, "these
> keystrokes were one complete action"** — instead of the current setup, where that
> knowledge only exists as scattered scratch notes read and updated in between separate
> keystrokes, never bundled into a single "yep, this was one thing" moment.
>
> Why we'd want this solved, beyond our own tracker: a **usage tracker** (us) sees `c`,
> then `i`, and has to guess these were one edit — or worse, misses `{` entirely because
> it never even reaches the part of Vim that watches keystrokes. **Multicursor plugins**
> need to replay "the one thing you just did" at several other cursor positions — but
> without a definition of where "the one thing" starts and stops, they can't reliably
> know what to replay. **Undo** has the same problem in miniature already: bundling
> several small edits into "one undo step" is hand-assembled per plugin today because
> Vim itself doesn't hand you a clean boundary. It's the same missing piece showing up
> wherever a tool needs to answer "what did the user just do, as one thing?"
>
> **Q: When I type `ci{`, something in Vim must go "Oh! I know what to do for this" —
> and this must be true of all kinds of keyboard commands. Can't we just use *that*
> moment to solve "this is one complete action"?**
>
> Yes — and this is the key insight. There absolutely is a moment where Vim goes "oh, I
> know what to do, doing it now." For `ci{`, that moment is real: a specific check deep
> in Vim's code asks "is there a pending edit, and do I now have enough info to finish
> it?" — the instant that's true, it does the edit. That's a genuine "GO" moment (see
> [the `do_pending_operator` guard](#what-holds-ci-together-oparg_t--finish_op) below).
>
> The catch: **that "GO" moment isn't one single place in the code — it's dozens of
> different places, one for each different shape of command, in totally different parts
> of the editor.** Operator+motion commands (`ci{`, `dw`, `y$`) have their "GO" moment in
> one specific spot. Simple one-key commands (`x`, `u`, `p`) have theirs somewhere else
> entirely — firing immediately, no waiting. Entering insert mode (`i`, `a`, `o`) has its
> own separate "GO," in yet another spot. Running a `:command<Enter>` fires through a
> completely different subsystem. A macro replaying keys funnels back through *all* of
> the above, one recorded keystroke at a time. A plugin-defined keymap fires wherever its
> code happens to land — which could itself be one of the things above.
>
> So it's not that Vim has *no* recognition moment — it's that it has *many*, scattered
> across many different files, each shaped differently, and **none of them currently
> tell anyone else "hey, I just fired."** They're all privately satisfied with themselves
> and move on. "Solving atomization" is exactly the job of finding every one of those
> scattered "GO" moments and wiring them all up to report the same thing, the same way —
> real, unglamorous plumbing work across many corners of the editor, made harder by the
> fact that even the people who wrote the code don't always agree where one of these
> boundaries begins (see the
> [`#28634` maintainer dispute](#citations-the-what-counts-as-one-action-consensus-problem)
> over exactly when an operator "counts" as started). That "bigger, unstarted project" is
> also, not coincidentally, exactly what multicursor plugins are blocked on for the same
> reason — they need this same unified "one action just happened" signal to know what to
> replay at every other cursor. That's why this sits blocked rather than being a quick
> fix — see [Recommendation: a real upstream fix](#recommendation-a-real-upstream-fix).

This section explains a claim the [Prior art: Neovim core API status](#prior-art-neovim-core-api-status)
subsection below leans on: that Neovim core has no "a mapping fired" event partly
because *nobody has defined what "one" fired action even is*. It matters here because
it's the deepest reason Option A (wrap `vim.keymap.set`) is not merely convenient but the
only unambiguous hook — and understanding it stops a future reader from "improving" the
tracker by pushing the hook lower, into the keystream or the resolver, where an action's
boundaries dissolve.

Verified against `/Users/dhruv/src/neovim/` — `state.c`, `normal.c`, `normal_defs.h`,
`ops.c`, `getchar.c`. Where the terse mental model ("`ci{` is three trips through the
resolver") turned out slightly wrong, this section corrects it from the source rather than
repeating it.

### The key insight

"Atomic" is a claim about *boundaries*: an action is atomic if there is one identifiable
moment where the whole thing — operator, count, register, motion, text object — is known
as a single unit. A usage tracker that wants to log "the user changed inside braces" needs
that boundary: it has to know that `c`, `i`, and `{` are **one** edit and not three. A
multicursor feature needs the very same thing for the opposite reason — to *replay* one
action at N cursors it must know where the action starts and stops.

Neovim's normal-mode engine has no such boundary. It is built as a **flat loop that
consumes one resolved key per iteration**, and the "operator + motion" grouping lives in a
couple of side-band globals (`oparg_T`, `finish_op`) that are read and mutated *across*
loop iterations, never bundled into any single call that could stand for "the action." So
the boundary a tracker would want to hook is not merely hidden — it genuinely isn't
represented anywhere in the code.

### One resolved key per call: the state loop

Every modal state (normal, insert, cmdline, terminal) runs the same generic driver,
`state_enter` (`src/nvim/state.c:34`):

```
state_enter(s):                    // s = a VimState with check()/execute() callbacks
  while true:
    check_result = s->check(s)     // normal_check() → normal_prepare(): per-iter setup
    ...
    key = safe_vgetc()             // ← ONE fully-resolved key (mapping engine already ran)
    s->execute(s, key)             // normal_execute(): dispatch that ONE key
```

`safe_vgetc()` returns the *output* of the resolver: by the time it hands back a key,
`handle_mapping` has already done the FULL/PARTIAL/NONE trichotomy + `timeoutlen` dance
from [Background: how Neovim resolves keymaps](#background-how-neovim-resolves-keymaps).
For normal mode, `execute` is `normal_execute` (`src/nvim/normal.c:1072`): it looks the key
up in `nv_cmds[]`, calls that command's function, then runs `normal_finish_command` →
`do_pending_operator` (`src/nvim/ops.c:3278`).

"Get one key, dispatch, loop" is structural, not incidental — it's the *same* driver for
every mode. So **"one `execute` call handles exactly one resolved key" is a fact of the
architecture**, which is precisely why a multi-key action like `ci{` cannot be one call.

### What holds `ci{` together: `oparg_T` + `finish_op`

The only thing tying the keys of `ci{` into one edit is state that lives *outside* the
resolver and outside any single `normal_execute` call:

- **`oparg_T`** (`src/nvim/normal_defs.h:20`) — the pending-operator record: `op_type`
  (e.g. `OP_CHANGE`), `regname`, `motion_type`, `motion_force`, `start`/`end` positions,
  `line_count`, … It hangs off the `NormalState` (`s->oa`) and is reachable via the
  file-static `current_oap`. It is **not** a parameter of the resolver at all.
- **`finish_op`** — a global flag meaning "an operator is already pending; the command
  taken *this* iteration will complete it." `normal_prepare` recomputes it once per loop
  iteration: `finish_op = (s->oa.op_type != OP_NOP)` (`normal.c:539`).

`do_pending_operator` only actually performs an edit when
`(finish_op || VIsual_active) && oap->op_type != OP_NOP` (`ops.c:3289`). That guard is the
real "fire" moment — and it is reached at the *tail* of the loop iteration that lands the
**motion**, one full iteration after the operator key was seen.

### Worked example: `ci{` on `foo({ bar })` with the cursor on `bar`

Three keystrokes — but watch how many times we go around the state loop, and what
`oparg_T`/`finish_op` look like each time:

```
buffer:  foo({ bar })
cursor:        ^  (inside the braces)

 ─────┬────────┬───────────┬──────────────┬──────────────────────────────────────────
 iter │ key    │ finish_op │ oap->op_type │ what normal_execute does
      │ (from  │ (set by   │ (after the   │
      │ resolv-│ normal_   │ command runs)│
      │ er)    │ prepare)  │              │
 ─────┼────────┼───────────┼──────────────┼──────────────────────────────────────────
  1   │  c     │  false    │  OP_CHANGE   │ nv_operator: oap->op_type = OP_CHANGE,
      │        │ (op was   │              │ oap->start = cursor. do_pending_operator
      │        │  OP_NOP)  │              │ guard = (false || false) → NO-OP.
      │        │           │              │ returns; operator is now "pending".
 ─────┼────────┼───────────┼──────────────┼──────────────────────────────────────────
  2   │  i     │  TRUE     │  OP_CHANGE   │ nv_edit sees op pending → nv_object.
      │        │ (op !=    │              │ needs a text-object char: reads '{'
      │        │  OP_NOP)  │              │ NOT through the resolver — via
      │        │           │              │ plain_vgetc() under no_mapping++
      │        │           │              │ (normal_get_additional_char, normal.c:720).
      │        │           │              │ nv_object computes the { } range.
      │        │           │              │ do_pending_operator guard is now
      │        │           │              │ (TRUE && OP_CHANGE) → ★ FIRES ★:
      │        │           │              │ deletes " bar " region, enters insert.
 ─────┴────────┴───────────┴──────────────┴──────────────────────────────────────────
```

Timeline view — resolver trips marked `[R]`, raw reads marked `[raw]`:

```
 key:      c                  i                 {
           │                  │                 │
         [R] resolver       [R] resolver      [raw] plain_vgetc under
         classified          classified        no_mapping — the object
         (omap-able)         (omap-able)        char is NOT resolved
           │                  │                 │
           ▼                  ▼                 ▼
   normal_execute #1   ┌─ normal_execute #2 ──────────────┐
   set op pending      │  read '{' raw, compute { } range, │
   (no edit yet)       │  do_pending_operator() ★ EDIT ★   │
                       └───────────────────────────────────┘
                          oparg_T carried op_type across the
                          gap between call #1 and call #2;
                          finish_op flipped true at the top of #2
```

Two corrections the source forces on the "three trips through the resolver" model:

- It is **two** resolver trips, not three. `c` and `i` each arrive via
  `safe_vgetc()`/`handle_mapping` and are independently mappable (including in
  operator-pending / `omap`). But `{` is slurped by `normal_get_additional_char` with
  `no_mapping++` active (`normal.c:720`) — it never touches the mapping engine, so as the
  text-object argument it is *not* remappable here and would not fire a resolver-level hook
  at all.
- The edit does not happen "when `{` lands" as a discrete step. It happens inside
  `do_pending_operator` at the *tail of the `i` iteration*, gated by a global `finish_op`
  that was flipped true at the *top* of that same iteration, based on state left behind by
  the `c` iteration.

So even the boundaries are irregular: part of one human edit flows through the resolver
(`c`, `i`), part bypasses it (`{`), and the moment-of-effect is a guard check in a
different file (`ops.c`) reading a global that was set two iterations of bookkeeping
earlier.

### The generalization: there is no "whole action" call frame

Put the two facts together:

1. `normal_execute` handles exactly one resolved key (the state-loop invariant).
2. The operator/motion grouping is carried by `oparg_T` + `finish_op`, which are read and
   written *between* those calls, never assembled into one.

Therefore **no single call frame ever holds "the whole `ci{` action."** There is nothing
to attach a boundary to. This is the concrete reason a "mapping fired" event doesn't and
can't trivially exist:

- **Hook per resolved key** and a tracker sees `c` then `i` — two events for one human
  edit — and misses `{` entirely, since it never reaches the resolver. Overcount on some
  keys, undercount on others; the log becomes noise.
- **Hook "one event per logical command"** and you must first *define* where a logical
  command begins and ends — i.e. build an "atomize the input stream into discrete actions"
  layer. That layer does not exist. Neovim issue
  [#30803](https://github.com/neovim/neovim/issues/30803) asks for exactly it (report `ci[`
  as one atom), and a maintainer tied it to unscheduled multicursor work
  ([#30741](https://github.com/neovim/neovim/issues/30741)), which needs the *same*
  atomization to replay one action across cursors. (See the dedicated citations subsection
  in [Prior art: Neovim core API status](#prior-art-neovim-core-api-status) for the full
  list of related discussions.)

Nobody has built that layer, so there is genuinely nothing to hook for anything richer than
a single flat mapping.

### Compounding factor: recursive maps and `<Plug>` re-enter the resolver

The atomization problem above is one logical command spanning multiple keys. A second,
independent effect pushes the count the *other* way: one *keypress* can spawn multiple
passes through the resolver.

Recall from [Background: how Neovim resolves keymaps](#background-how-neovim-resolves-keymaps)
that when `handle_mapping` (`src/nvim/getchar.c:2251`) finds a full match it does not "run"
the rhs — it *rewrites the typeahead*: `del_typebuf(keylen)` removes the matched lhs,
`ins_typebuf(rhs, …)` splices the rhs in at `tb_off`, and it returns `map_result_retry`
(`getchar.c:2622`). The caller loop in `vgetorpeek` sees `map_result_retry` and simply
`continue`s (`getchar.c:2781`) — re-running `handle_mapping` on the freshly-spliced bytes.
A `mapdepth` counter guards against runaway recursion (`getchar.c:2505`, capped at `p_mmd`).

Nearly every plugin keymap is recursive-through-`<Plug>`: the user maps a key with
`remap = true` to a `<Plug>` token, and the plugin maps that `<Plug>` token to the real
implementation. So one keypress fans out into several retry passes:

```
user config:   vim.keymap.set("n", "<C-s>", "<Plug>(sandwich-add)", { remap = true })
plugin:        vim.keymap.set("n", "<Plug>(sandwich-add)", "<cmd>lua ...<cr>")

 typebuf across successive retry passes (tb_off = ↑):
 ──────────────────────────────────────────────────────────────────────────────────
 pass 1:  [ <C-s> ]                 handle_mapping: FULL match on "<C-s>"
          ↑                           del "<C-s>", ins "<Plug>(sandwich-add)"
                                       → map_result_retry ─┐
                                                           │ continue
 pass 2:  [ <Plug>(sandwich-add) ] ◄────────────────────── ┘
          ↑                           handle_mapping: FULL match on the <Plug> token
                                       del it, ins "<cmd>lua ...<cr>"
                                       → map_result_retry ─┐
                                                           │ continue
 pass 3:  [ <cmd>lua ...<cr> ]     ◄────────────────────── ┘
          ↑                           no further mapping → the command executes
 ──────────────────────────────────────────────────────────────────────────────────
 ONE physical keypress  →  TWO rhs substitutions  →  N passes through handle_mapping
```

A hook naively placed at "`handle_mapping` matched something" would fire once per pass —
2+ firings for a keypress the user experiences as one. `<Plug>` indirection is invisible to
the user but very visible to the resolver, so keystream- or resolver-level hooking
double-counts precisely the mappings that matter most (plugin actions).

### Why this is context, not a blocker for the plan

The tracker sidesteps the entire problem by construction. It does **not** hook the resolver
or the keystream. It wraps the rhs of explicitly-registered `vim.keymap.set` mappings
(Option A), which are, by definition:

- **Flat** — one registered lhs → one rhs closure. There is no operator/motion composition
  to atomize; `<leader>ff` *is* the whole action.
- **Unambiguous at fire time** — the wrapper runs when *Vim decided to execute that
  specific mapping's rhs*, after the resolver has already settled
  partial/full/timeout/noremap and after any `<Plug>` retry chain has collapsed to the real
  target. We log exactly once, at the real firing.

So `ci{`-style operator/motion composition and `<Plug>` fan-out are compelling evidence for
*why the core has no "mapping fired" event* — which is what the
[Prior art: Neovim core API status](#prior-art-neovim-core-api-status) subsection documents
— but they are not obstacles for this tracker, which only ever concerns itself with the
flat, individually-registered mappings whose boundaries are never in question.

---

## Prior art: existing plugins

Surveyed before committing to a custom build. The two primitives have very different
prior-art coverage, so the search split along that line.

**Enumeration (Primitive 1) is well-covered** — nothing new needed. `nvim_get_keymap`,
which-key, and `nvim-mapper` already do it; this only confirms the doc's approach is
standard practice.

**Persistent, structured (timestamp/mode/lhs/desc) usage-over-time logging (Primitive 2,
the primary goal) is solved by nobody.** Every tool that came close is dead, unimplemented,
or a different category:

| Plugin | Last activity | What it does | Why it doesn't fit |
|---|---|---|---|
| letieu/key-report.nvim | archived Jun 2025 | count invocations + report — conceptually identical to this doc | dead; logging feature never implemented (listed as unfinished TODO in its own README) |
| abdul-hamid-achik/keymaps.nvim | Jan 2026 | `track_usage=true` option, `:KeymapsStats` | enumeration/cheatsheet with tracking bolted on; README gives zero detail on disk persistence, timestamps, or whether/how it hooks `vim.keymap.set`; small/unproven (6 commits, 4 stars) |
| OscarCreator/keystats.nvim | Oct 2023 | `vim.on_key()` keystroke counts → Rust-backed DB | raw keystrokes only; no mapping/lhs/desc semantics, no timestamps |
| glottologist/keylog.nvim | Apr 2024 | raw keystrokes → `~/.local/share/nvim/keystroke.log` for heatmaps | raw-key logging, no keymap semantics |
| gaborvecsei/usage-tracker.nvim (fork by Dronakurl) | Mar 2024 | *time spent* per file/project/filetype/git-branch | different category (editor-time analytics, not keybinding frequency) |
| lazytanuki/nvim-mapper | Feb 2023 | Telescope enumeration + jump-to-definition | no usage counting |

which-key's own maintainer explicitly declined to build this: GitHub issue #969 requested
exactly a persistent aggregate stats file with multi-instance locking, and it was closed
**not planned**, no PR ever materialized. → justifies building custom rather than
adopting/wrapping an existing tool.

### hardtime.nvim externally validates both of the doc's hook decisions

hardtime.nvim (actively maintained; source read directly at `lua/hardtime/init.lua`) uses
two distinct mechanisms — one per feature — and they land on opposite sides of exactly the
choice this doc makes:

- **hjkl/arrow restriction** (normal mode only): does **not** use `vim.on_key`. It directly
  `vim.keymap.set`s the restricted keys themselves and re-resolves what each key *would*
  have done by scanning `nvim_get_keymap("n")` captured at enable-time. Owning the single,
  non-prefix-ambiguous key directly sidesteps the partial-match/timeout problem entirely —
  the same "wrap the rhs, don't observe the stream" principle as Option A, now externally
  validated by a real maintained plugin making the identical architectural choice for a
  related problem.
- **soft hints** (e.g. suggest `cw` over `ce`): **does** use `vim.on_key`, appending every
  raw `keytrans`'d key to a rolling string buffer and suffix-matching against known bad
  sequences. Confirmed: it does **not** implement timeoutlen/partial-match disambiguation
  — it just tolerates false positives because a wrong hint is cheap. It special-cases
  which-key being active (to suppress interference) and ignores insert/command/replace
  modes.

The second point is direct field evidence for the doc's existing `vim.on_key` rejection
(see [Alternatives considered](#alternatives-considered)): a maintained plugin hit the
exact trichotomy/timeout wall and chose to accept inaccuracy rather than solve it — fine
for soft nagging, not for an accurate persistent log.

Also checked and confirmed **not** relevant to keypress detection: precognition.nvim
(source read — computes available motions from cursor/buffer on `CursorMoved`, a static
hint renderer, detects no keypresses); vim-hardtime / takac/vim-hardtime (same
own-the-key-via-remap trick as hardtime.nvim's hjkl mechanism); phux/vim-keypress-analyzer
(doesn't capture live — parses Vim's own `-w scriptin` raw log, a pre-mapping-resolution
keystream, so it hits the same over-counting problem `vim.on_key` does).

**Stretch goal only.** If raw native-motion tracking (`i`, `a`, `dd`, `hjkl` — currently an
explicit non-goal, see Goals and Open questions) is ever revisited, hardtime's
`vim.on_key` + `keytrans`-buffering is a reasonable *starting point* for the mechanism —
but treat it as a rough prior-art reference, not a battle-tested one to copy uncritically:
its own maintainer skipped the timeout/partial-match disambiguation our accurate-log use
case would require.

### Prior art: Neovim core API status

Also checked whether Neovim core itself has any open plan to expose a "keymap fired"
event or hook, which would obsolete the `vim.keymap.set`-wrapping approach entirely.
**Nothing exists, and nothing is close.**

- [neovim/neovim#30803](https://github.com/neovim/neovim/issues/30803) (**open**) asks for
  exactly this — `vim.on_key` reporting one atomized action (e.g. `ci[`) instead of raw
  keys, explicitly for usage/keystroke statistics. Maintainer justinmk confirmed it's "not
  implemented yet" and tied it to a larger, unscheduled prerequisite: atomizing input so
  its structure is exposed (referenced against multicursor work,
  [#30741](https://github.com/neovim/neovim/issues/30741)). No timeline, no active PR.
- [neovim/neovim#24475](https://github.com/neovim/neovim/issues/24475) (**closed**, requested
  `MacroExecutionPre`/`Post` autocmds — the closest existing precedent, since
  `RecordingEnter`/`RecordingLeave` already model "notify around an execution span") was
  self-closed once a maintainer pointed out `reg_executing()` already covers the use case.
  Signal: core's default response to "add an execution event" is "use an existing query
  primitive," not "add the event."
- [neovim/neovim#30061](https://github.com/neovim/neovim/pull/30061) (**closed, not merged**)
  ported Vim's `KeyInputPre` patch. A maintainer pushed back ("What is this providing that
  `on_key` doesn't? Should we deprecate `on_key`?"); it stalled. Note `KeyInputPre` is
  itself pre-mapping, raw-keystroke level in upstream Vim too — so even Vim hasn't solved
  post-resolution observability.
- [neovim/neovim#19156](https://github.com/neovim/neovim/issues/19156) (**open**, general
  design discussion) debates folding ad-hoc "quasi-event" systems like `vim.on_key`'s
  namespace callbacks into the autocmd system generally — relevant background, no concrete
  mapping-fired proposal.

**Verdict**: wrapping `vim.keymap.set` (Option A) is not a workaround pending a better
core primitive — it's the correct long-term design given core's demonstrated preference
for existing primitives over new events, and the one issue asking for this exact
capability is blocked on unscheduled architecture work with no timeline.

#### Citations: the "what counts as one action" consensus problem

Digging into full comment threads (not just opening posts) across neovim/neovim, vim/vim,
and the multicursor plugin ecosystem shows *why* no such event exists: nobody has actually
agreed on what the atomic unit ("one action," "one edit," "one keystroke span") should be.
This isn't one offhand remark — it recurs, independently, across unrelated threads and
projects.

- [neovim/neovim#30741#issuecomment-2404867582](https://github.com/neovim/neovim/issues/30741#issuecomment-2404867582)
  — **maintainer** justinmk, the original source of the "atomize input" quote reused in
  #30803: "otherwise you end up re-implementing a mapping parser in `on_key` (which
  doesn't know if a key will resolve to a mapping / builtin normal command)." States
  plainly that no structural boundary for "one action" is exposed anywhere in core.
- [neovim/neovim#30803#issuecomment-2409721137](https://github.com/neovim/neovim/issues/30803#issuecomment-2409721137)
  — **community member** jake-stewart (author of multicursor.nvim, the plugin justinmk
  cites as the reason atomization is blocked) describes trying to work around the gap
  with `SafeState` and hitting the same wall from the other side: "Repeating an
  overlapped mapping will stop vim from entering a safe state" — i.e. even a
  best-effort heuristic for "action just completed" breaks under recursive/overlapping
  mappings. Direct field evidence from the person building the exact plugin #30803 is
  blocked on.
- [neovim/neovim#28634](https://github.com/neovim/neovim/issues/28634) (closed, defaults
  reverted in #28649) — a maintainer-level dispute over whether pressing `c` alone
  "counts" as entering operator-pending mode while a `cr*` mapping's timeout is still
  pending. **Maintainer** gpanders initially argued the ambiguity was cosmetic
  ([#issuecomment-2094146172](https://github.com/neovim/neovim/issues/28634#issuecomment-2094146172));
  **maintainer** justinmk countered "The mode-change thing can be fixed" but proposed no
  concrete fix ([#issuecomment-2094834662](https://github.com/neovim/neovim/issues/28634#issuecomment-2094834662));
  the defaults were reverted rather than resolving where one operator invocation
  "begins" for event-firing purposes.
- [neovim/neovim#32300](https://github.com/neovim/neovim/issues/32300) (open) — `ModeChanged`
  doesn't fire between a custom operator-pending textobject finishing and
  `operatorfunc` starting, despite an intervening mode change. **Core team member**
  echasnovski confirmed the identical gap exists in upstream Vim 9.1.1065
  ([#issuecomment-2629667552](https://github.com/neovim/neovim/issues/32300#issuecomment-2629667552)) —
  the "span of one operator action" isn't well-defined in either editor's event model.
- [neovim/neovim#40227](https://github.com/neovim/neovim/discussions/40227) (Discussion,
  community members) — independent, unprompted rediscovery of the #28634 problem a year
  later: a user's custom `d`-prefixed mapping silently kills the operator-pending cursor
  feedback, because Neovim still can't tell "is this one complete action" without
  waiting out `timeoutlen`
  ([#discussioncomment-17302779](https://github.com/neovim/neovim/discussions/40227#discussioncomment-17302779)).
  Recurrence across independent threads is itself evidence this is a structural gap, not
  a one-off complaint.
- [vim/vim#15182#discussion_r1671642447](https://github.com/vim/vim/pull/15182#discussion_r1671642447)
  — **maintainer** zeertzjq, reviewing upstream Vim's `KeyInputPre` patch (the same patch
  #30061 later ported to Neovim): "I don't think 'typed' is an accurate description of
  when this event is triggered... the key may come from a mapping (which is not a typed
  key)." Confirms the pre-/post-resolution ambiguity is unresolved in Vim proper, not
  just a Neovim gap.
- [jake-stewart/multicursor.nvim#58](https://github.com/jake-stewart/multicursor.nvim/issues/58)
  — **maintainer** jake-stewart, debugging why a single user-perceived edit (typing text
  ending in `.`, remapped by lazy.nvim to `.<C-g>u`) produced multiple undo entries only
  some cursors replicated: "virtual cursors are not aware of this and will not undo in
  parts like the main cursor does"
  ([#issuecomment-2408748200](https://github.com/jake-stewart/multicursor.nvim/issues/58#issuecomment-2408748200)).
  Concrete case of "one logical edit" having no canonical boundary once multiple
  replay/undo consumers must agree on it.
- [jake-stewart/multicursor.nvim#122#issuecomment-2844417738](https://github.com/jake-stewart/multicursor.nvim/issues/122#issuecomment-2844417738)
  — **community member** bew, requesting a scoped one-shot `onSafeState` callback because
  a global one "breaks the isolation of keybind actions" — independently arrives at the
  same need this doc's tracker has: a well-scoped "this one action just fired" boundary,
  one layer above raw keymaps.
- [mg979/vim-visual-multi#40#issuecomment-452273858](https://github.com/mg979/vim-visual-multi/issues/40#issuecomment-452273858)
  — **maintainer** mg979 explains the plugin manually `undojoin`s "multiple changes that
  happen at different cursors, so that you can undo the whole operation at once" — i.e.
  "one logical edit" for undo purposes has no automatic definition in Vim/Neovim and must
  be hand-assembled per plugin, the same atomicity problem this doc's tracker sidesteps
  by hooking at the rhs rather than trying to define an edit boundary.
- [neovim/neovim/discussions/40320#discussioncomment-17362907](https://github.com/neovim/neovim/discussions/40320#discussioncomment-17362907)
  — **maintainer** justinmk, on a 2025 RFC-style Discussion proposing a generalized
  `vim.on()` event wrapper: "thinking about the story for groups and other 'keys' is the
  main thing blocking a public interface... 'visibility' is an unsolved problem." Shows
  the generalized-event-identity question (what "keys" identify one event/action
  instance) is still open years after #19156 first raised it.
- **Supporting context, not a strict citation for the atomization claim**:
  `runtime/doc/dev_arch.txt` (`*dev-new-event*`) documents Neovim's actual process for
  adding new autocmd events but does not itself state a preference for reusing existing
  primitives over adding new ones — the "use `reg_executing()` instead" pattern seen in
  #24475 is established by maintainer practice (see main list above), not codified in
  this doc.

#### Why this keeps stalling: reentrancy, atomization, and performance

The citations above are external evidence the problem is real; this is the mechanical
reason, from reading the source directly. The resolver already knows the exact moment a
mapping fires — it has to, to substitute rhs into the typeahead buffer — so why can't
that moment be exposed as a stable event? Five hypotheses, checked against
`/Users/dhruv/src/neovim`:

- **(a) Reentrancy hazard — real, but already routinely handled, not a hard wall.**
  `handle_mapping` (`getchar.c:2251`) already calls into script code synchronously for
  `<expr>` mappings (`eval_map_expr` at line 2550); the surrounding code (lines
  2525-2533) copies `m_expr`/`m_noremap`/`m_silent`/`m_keys`/`m_alt->m_keys` into locals
  first, with a comment warning that the call may redefine the mapping and invalidate
  `*mp` — the exact "callback mutates the structure being walked" hazard. Neovim's
  existing answer is "copy out before calling out," not "forbid calling out." Separately,
  `vim.on_key` (`nlua_execute_on_key`, `lua/executor.c:2253`) is called synchronously
  from `vgetc()` (`getchar.c:1819`), guarded only by a static `recursive` bool (lines
  2255-2260) — but only *after* `vgetorpeek`'s retry loop (`map_result_retry`, line 2781)
  has already fully resolved the character, not while maphash/typebuf pointers are still
  live. Net: a solvable engineering tax, not an architectural blocker.
- **(b) API design / atomization ambiguity — the dominant factor.** `normal_cmd()`
  (`normal.c:6695-6704`) resolves one key per call via the generic `state_enter()` loop
  (`state.c:34`); a compound command like `ci{` glues its keys together only via
  externally-persisted `oparg_T`/`finish_op` state (`normal.c:495-547`, `972-1018`) —
  there's no single frame where "the whole logical action" is known as one unit. (In
  fact `ci{` is only *two* resolver trips, not three — `{` bypasses the mapping engine
  entirely via `no_mapping++`, an even more irregular boundary than "three trips" would
  suggest; see the dedicated background section below for the full walkthrough.) No
  in-tree design doc addresses this; the reasoning lives only in issue #30803 discussion
  and the citations list above.
- **(c) Performance — real baseline cost, but already paid.** `handle_mapping` runs
  unconditionally for every character once `typebuf.tb_len > 0` (`getchar.c:2777-2779`),
  maphash lookup included, even for unmapped keys. A "mapping fired" callback would only
  need to trigger in the match-found branch (~lines 2437-2489) — a small fraction of
  keystrokes, and strictly cheaper than `vim.on_key`'s existing unconditional per-key
  Lua call. Minor factor, not the blocker.
- **(d) Maintainer bandwidth/priority.** Not verifiable from source — no stale
  feature-flagged or partial implementation found in-tree. Consistent with #30061 being
  closed on a design question ("what does this provide that `on_key` doesn't") rather
  than a blanket rejection.
- **(e) Verdict**: (b) dominates. (a) has established in-codebase mitigation patterns
  (copy-out-before-eval for `<expr>`; resolve-before-callback for `on_key`) — solvable
  with care, not impossible. (c) is minor since match-gating is possible and the
  baseline lookup cost is already sunk. (d) is plausible but unverifiable.

**Practical implication for this tracker's own design**: this validates the plan rather
than complicating it. The tracker never has to solve the atomization problem, because it
only wraps mappings explicitly registered via `vim.keymap.set` — a flat mapping like
`<leader>ff` has no operator-pending ambiguity. The `ci{`-style multi-key composition
problem only bites if raw built-in motions are ever tracked, which is already an
explicit non-goal (see Goals and Open questions elsewhere in this doc). So the thing
that has stalled core Neovim for years is a non-problem for this tracker's actual scope.

---

## Recommendation: a real upstream fix

Everything above explains why this tracker has to be a userland workaround. It's worth
asking what an actual upstream contribution would look like — not to solve this doc's
problem (already solved by Option A), but because the underlying gap is real and every
plugin author who wants usage/analytics data hits the same wall. This is a
recommendation, not a commitment; nothing in this doc depends on it landing.

**Don't solve atomization. Solve the flat-mapping-fired case.** The instinct is to fix
the general problem — "fire an event for the whole logical action" — but that's exactly
the piece blocked on unscheduled multicursor architecture
([#30741](https://github.com/neovim/neovim/issues/30741)) with no timeline, and the
piece a maintainer-level dispute couldn't even agree on for a *single* operator
([#28634](https://github.com/neovim/neovim/issues/28634), see
[Citations](#citations-the-what-counts-as-one-action-consensus-problem)). Chasing it
guarantees the same fate as [#30061](https://github.com/neovim/neovim/pull/30061), which
stalled the moment it looked like scope creep on `on_key`.

The narrower, genuinely shippable piece: `handle_mapping`'s matched branch (see
[Appendix](#appendix-code-references), `getchar.c:2437-2489`) already sees *every*
mapping regardless of registration path — Lua `vim.keymap.set`, direct
`nvim_set_keymap`, `:map` Ex, or Vimscript `map`. That is precisely the coverage this
doc's own tracker cannot reach (the four miss cases under
[Primitive 2](#primitive-2--usage-log-luakeymap_trackerlua)). A small, opt-in callback
fired at that point — using the same defensive copy-out-before-calling-out pattern
Neovim already ships for `<expr>` mappings
([Why this keeps stalling, (a)](#why-this-keeps-stalling-reentrancy-atomization-and-performance))
— would report "mapping X just resolved and is about to fire" for the flat case, for
every plugin, for free. Most real-world usage-tracking value is in flat mappings; this
captures it without touching operator-pending state at all.

**The `<Plug>`/recursive-chain double-count is cheap to punt, not solve.** [Recursive
maps and `<Plug>` re-enter the resolver](#compounding-factor-recursive-maps-and-plug-re-enter-the-resolver)
showed one keypress can cause N passes through the matched branch. Rather than deciding
in core which link is "the real one," tag each firing with the existing `mapdepth`
counter (`getchar.c:2505`) so consumers filter to the terminal link themselves — the
same "stay above the resolver, don't replicate its logic" principle this whole doc is
built on, just moved one layer down into core instead of userland.

**Where to land it.** Two independent opportunities, best pursued separately:

- [#32300](https://github.com/neovim/neovim/issues/32300) (`ModeChanged` doesn't fire
  around operator-pending textobject completion) already has a core team member
  (echasnovski) confirming it's a real bug in both editors. It's a bugfix, not a new
  API — apolitical, and worth submitting on its own regardless of the rest of this.
- The flat-mapping-fired hook is better pitched as a concrete instance of justinmk's own
  2025 `vim.on()` RFC
  ([discussions/40320](https://github.com/neovim/neovim/discussions/40320)) than as a
  competing one-off event. He's already trying to solve "event identity" there; arriving
  with a narrowly-scoped worked example is more likely to land than a fresh issue
  proposing yet another primitive alongside `on_key`.

---

## Alternatives considered

**`vim.on_key` keystream listener.** Subscribe to raw key bytes; match against the
snapshot's `lhsraw` set after each key. Catches every fire regardless of registration
path. *Rejected*: reproduces the resolver's FULL/PARTIAL/NONE trichotomy and
`timeoutlen` logic in Lua (see the Neovim background) — overcounting (logging both
`j` and `jj`) or undercounting (logging `<leader>` prefix presses) are likely failure
modes. Performance-sensitive on every keystroke. This concern is not theoretical:
hardtime.nvim's soft-hint feature uses exactly this approach and, confirmed by source
read (`lua/hardtime/init.lua`), does **not** attempt the timeout/partial-match
disambiguation — it tolerates false positives because a wrong hint is cheap. Our accurate
persistent-log use case does not have that luxury. See
[Prior art](#prior-art-existing-plugins).

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
GUIDE.md and the `keymap-audit` skill). The content below is preserved here
so the motivating context and candidate follow-ups aren't lost if Track C is
revived.

> **Status: deferred (2026-07-09).** Nothing below is being implemented now —
> kept as the backlog of things to try once/if this tracker gets built.

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

### C2. Candidate promotions to evaluate against the data

Free top-level leader keys today: `f i j k l w x y z / , .` (approximately).
Candidates, in expected-frequency order:

| Candidate | Today | Proposal | Rationale |
|---|---|---|---|
| Find files | `<leader>sf` | also `<leader>f` | likely the single most-used picker; 1 key saved × dozens/day |
| Grep | `<leader>sg` | also `<leader>/` | mirrors "search" intuition; LazyVim/Helix precedent |
| Buffer picker | `<leader>m` | keep — already 1 key | verify with data it deserves top-level status vs `<leader>bb` |
| Resume picker | `<leader>sr` | maybe `<leader>.` | cheap redo of last search |

Add as *aliases* (keep `s*` canonical) — zero unlearning, then let the
tracker show whether the short forms win.

**Why it's better:** example arithmetic — if `sf` fires 40×/day, `<leader>f`
saves 40 keystrokes/day and, more importantly, drops the 300ms which-key
partial-match wait risk on the `s` prefix. If the data says it fires 4×/day,
skip it and keep the namespace clean. Either way you decide with evidence.

### C3. Resolve `<A-hjkl>` with data

If the log shows zero invocations after a month: unmap, and consider
`<A-h>/<A-l>` for buffer prev/next (releasing `<S-h>/<S-l>`, restoring native
`H`/`L`) or window-swap. If they do get used, delete the "speculative"
label and keep them.

### C4. Insert-escape: `jj` vs `jk` — already resolved

Both `jj` and `jk` are mapped for insert-escape (`keymaps.lua`), so this item
is done; kept here only as the original reasoning record. `jk` is a
two-finger inward roll (faster than a double-tap, no key-repeat ambiguity)
and GUIDE.md documents it as canonical; `jj` stays for muscle memory.

---

## Resuming notes

If picking this up after time has passed:

- The user's `init.lua` line numbers may have shifted — re-verify with `Read` before
  inserting the `require('keymap_tracker')` line. The current load order is documented
  at `## Status` (top of file).
- The user's `pickers/keybindings.lua` `build_results()` function shape may have
  changed. The integration is one `pcall` line at the end of that function; verify the
  function name and end position before adding it.
- All cited line numbers in the Background sections are pinned to specific Neovim and
  which-key.nvim revisions present in `/Users/dhruv/src/neovim/` at the time of research.
  **Correction**: `/Users/dhruv/src/which-key.nvim/` does not exist on this machine — the
  actual clone verified during the code-reference-appendix pass is
  `/Users/dhruv/.local/share/nvim/site/pack/core/opt/which-key.nvim` (folke/which-key.nvim,
  commit `3aab2147e7`, v3.17.0); most citations matched exactly or within 1-2 lines, so
  it's likely the same or a very close revision. If those repos have been updated,
  re-grep for the function names (`keymap_array`, `mapblock_fill_dict`, `get_map_mode`)
  before relying on specific line numbers — or jump straight to
  [Appendix: code references](#appendix-code-references) for verified current locations.
- The `<leader>sk` picker currently passes `mode = 'n'` to `which-key.buf.get` — this
  is a real coverage gap. Once Primitive 1 lands, the picker can switch its data
  source from the which-key tree to `keymap_snapshot.collect()` and gain all-mode
  coverage.
- If using Neovide, then Cmd based keymaps are also an option. Should consider this as well.
  - Can be as easy as manually tracking this for now.
  - Goal is to make sure we can integrate Neovide keymaps as well at a later date.
- Note for myself: 
  - Consider the usageof this data, shold we include timestamps? What other metadata is useful here?

---

## Appendix: code references

Catalog of every distinct file/function/type/struct this doc's Neovim-internals and
which-key-internals discussions cite, so a future reader can jump straight to source
instead of hunting through prose. Verified by reading the actual checkouts rather than
trusting the doc's inline line numbers, which were pinned to an earlier revision.

**Neovim core** verified against `/Users/dhruv/src/neovim`, a local clone of
[null-sleep/neovim](https://github.com/null-sleep/neovim) (`origin` remote:
`git@github.com:null-sleep/neovim.git`), at commit
`3b8c19ea460b4abb5b74f91e05a14c0fcf9cc6a6` (2026-07-04 23:17:27 +0200). Nothing cited was
renamed or removed; drift is line-number-only, mostly in `getchar.c`/`mapping.c` (some
entries drifted 60-95 lines from the doc's inline citations — those pinned to an older
revision — due to code added upstream since). Where an entry differs meaningfully from
the doc's own inline citation, a footnote-style note gives both.

**which-key.nvim**: `/Users/dhruv/src/which-key.nvim` **does not exist on this
machine**. The nearest match is a `folke/which-key.nvim` clone at
`/Users/dhruv/.local/share/nvim/site/pack/core/opt/which-key.nvim`, commit
`3aab2147e74890957785941f0c1ad87d0a44c15a` (2025-10-28, reports `v3.17.0`). Most of the
doc's inline citations match this checkout exactly or within 1-2 lines, suggesting it's
the same or a very close revision to whatever the doc was originally pinned to. Line
numbers below are verified against that path.

### Neovim core (`/Users/dhruv/src/neovim`)

**`src/nvim/mapping_defs.h`**
- line 11 — `struct mapblock` (`mapblock_T`) — the mapping node: `m_next`, `m_keys`,
  `m_str`, `m_keylen`, `m_mode`, `m_nowait`. No drift.

**`src/nvim/getchar_defs.h`**
- line 31 — `typebuf_T` typedef — typeahead buffer struct: `tb_buf`, `tb_noremap`,
  `tb_off`, `tb_len`, `tb_maplen`. No drift.

**`src/nvim/mapping.c`**
- line 68 — `maphash[MAX_MAPHASH]` — the 256-slot global hash table of `mapblock_T`
  chains. No drift.
- line 355 — `<Nop>` detection (`STRICMP(orig_rhs, "<nop>") == 0`). No drift.
- line 262 — `<Nop>` display in `:map` listing (doc cites 261; drift +1).
- line 528 — `mp->m_expr = args->expr;` (first occurrence). No drift.
- line 825 — `mp->m_expr = args->expr;` (second occurrence; doc cites 819, drift +6).
- lines 988-1023 — `get_map_mode()` — mode-letter table (`n i c o t l x s v !`) (doc cites
  982-1017; drift +6).
- lines 1633-1690 — `eval_map_expr()` — evaluates an `<expr>` mapping's rhs per
  keystroke (doc cites 1635-1684; function fully intact, drift negligible).
- line 2883 — `keymap_array()` — the shared enumerator behind both
  `nvim_get_keymap`/`nvim_buf_get_keymap` (doc cites 2878; drift +5).
- lines 2901-2919 — loop walking all 256 maphash buckets, filtered by mode bits (doc
  cites 2896-2914; drift +5).
- lines 2090-2146 — `mapblock_fill_dict()` — populates the per-mapping dict: `lhs`,
  `lhsraw`, `lhsrawalt`, `rhs`/`callback`, `desc`, `mode`, `mode_bits`, `noremap`,
  `script`, `expr`, `silent`, `nowait`, `replace_keycodes`, `sid`, `lnum`, `buffer`,
  `abbr` (doc cites 2085-2141; drift +5).
- line 2891 — `int_mode = get_map_mode(&p, forceit);` inside `keymap_array` (doc's
  citation for abbr-mode access; this is the mode-resolution call itself, not the abbr
  ternary — see next two entries).
- line 2896 — `is_abbrev` bool determination (part of the same abbr-mode-access region
  doc cites at 2891).
- line 2903 — `buf ? buf->b_first_abbr : first_abbr` — abbreviation linked-list head
  selection for modes `"ia"`/`"ca"`/`"!a"` (doc's 2891 citation effectively points here;
  drift ~12).
- lines 2101-2108, 2114-2116 — compatible-flag branch and `m_orig_str` usage (the
  user-typed pre-termcoded lhs, exposed only via `maparg()`'s compatible flag, not
  `nvim_get_keymap`) (doc cites 2109-2111; drift ~5-9).

**`src/nvim/getchar.c`**
- line 1622 — `vgetc()` — the low-level character-getter that `handle_mapping`'s caller
  chain runs inside.
- line 1819 — `nlua_execute_on_key(c, on_key_buf.items)` call inside `vgetc()` — fires
  `vim.on_key` callbacks per raw keystroke, before mapping resolution. Exact match.
- line 2251 — `handle_mapping()` — the resolver; classifies FULL/PARTIAL/NONE, fires
  mappings (doc's own inline citation says 2184; drift +67).
- line 2390 — `if (mlen == keylen || (mlen == typebuf.tb_len && typebuf.tb_len <
  keylen))` — the trichotomy classification comparison (doc cites 2296; drift +94).
- lines 2413-2440 — partial-match / `<nowait>` / longest-full-match decision block (doc
  cites 2319-2345; drift +94, logic unchanged).
- line 2414 — the `!*timedout` guard specifically (doc cites 2320; drift +94; same
  region as the entry above).
- lines 2437-2489 — the matched-mapping branch: substitutes a FULL match's rhs via
  `ins_typebuf()`. Exact match (newer-round citation).
- lines 2525-2533 — defensive copy-out of `mp`'s fields (`save_m_expr`,
  `save_m_noremap`, `save_m_silent`, `save_m_keys`, `save_alt_m_keys`,
  `save_alt_m_keylen`) before evaluating an `<expr>` rhs, in case evaluation redefines
  the mapping. Exact match.
- line 2550 — `map_str = eval_map_expr(mp, NUL);` — where `handle_mapping` invokes
  `eval_map_expr` for `<expr>` mappings. Exact match.
- lines 2777-2779 — the unconditional maphash-lookup gate: `else if (typebuf.tb_len > 0)
  { ... handle_mapping(...) }`. Exact match.
- line 2781 — `if (result == map_result_retry)` handling (recursive-mapping restart).
  Exact match.
- line 2678 — `vgetorpeek()` — the main input/resolution loop that calls
  `handle_mapping()` and owns the timeout wait (doc cites 2583; drift +95).
- line 3022 — `wait_time = (int)p_ttm;` — partial-keycode timeout branch (sibling to
  next entry).
- line 3024 — `wait_time = (int)p_tm;` — `'timeoutlen'` wait for a partial map (doc
  cites 2929; drift +95).
- lines 3055-3057 — `if (wait_tb_len > 0) { timedout = true; continue; }` — timeout
  detection after `inchar()` returns nothing (doc cites 2960; drift +95).
- line 2622 — `ins_typebuf()` call inside the matched-mapping branch, splicing a FULL
  match's rhs into the typeahead buffer at `tb_off`; the caller's `continue` on
  `map_result_retry` (line 2781, above) is what re-enters `handle_mapping` on the
  freshly-spliced bytes — the mechanism behind recursive-mapping/`<Plug>` re-entry
  documented in [Background: why "one mapping fired" is ambiguous](#background-why-one-mapping-fired-is-ambiguous-the-atomization-problem).
- line 2505 — `mapdepth` recursion-depth counter (capped at `p_mmd`, `'maxmapdepth'`),
  guarding the retry loop above against runaway recursive mappings.

**`src/nvim/lua/executor.c`**
- line 2253 — `nlua_execute_on_key()` — invokes the Lua `vim.on_key` callback registry.
  Exact match (newer-round citation).
- lines 2255-2260 — `static bool recursive` guard preventing re-entrant `on_key` firing.
  Exact match.

**`src/nvim/normal.c`**
- lines 6695-6704 — `normal_cmd()` — top-level Normal-mode command dispatch loop. Exact
  match.
- lines 491-550 — operator-pending state tracking that *uses* `oparg_T`
  (`current_oap`, `op_pending()` at 495, `normal_enter()` at 513, `normal_prepare()` at
  525) — the struct itself is defined in `normal_defs.h`, not here (see next file).
  Matches the newer-round citation (~495-547) for content, with that file-location
  nuance.
- lines 962-1018 — `normal_finish_command()` — the `finish_op`-related operator-pending
  completion logic (checks at 972-975, 1006-1018). Matches newer-round citation
  (~972-1018).
- line 539 — `finish_op = (s->oa.op_type != OP_NOP);` inside `normal_prepare()` — the
  per-iteration recompute of the pending-operator flag.
- line 1072 — `normal_execute()` — the `state_enter` `execute` callback for Normal mode;
  looks the resolved key up in `nv_cmds[]`, dispatches, then runs
  `normal_finish_command()`.
- line 720 — `normal_get_additional_char()` — reads a text-object/register/mark
  argument character via `plain_vgetc()` with `no_mapping++` active, bypassing the
  mapping engine entirely (the reason `ci{`'s `{` is not independently remappable; see
  the atomization background section).

**`src/nvim/normal_defs.h`**
- lines 20-44 — `oparg_T` struct definition proper (fields for pending-operator state:
  op_type, start/end positions, counts, etc.) — this is the struct's actual home; the
  `normal.c` lines above only *use* it.

**`src/nvim/ops.c`**
- line 3289 — `do_pending_operator()` guard: `(finish_op || VIsual_active) &&
  oap->op_type != OP_NOP` — the actual moment a pending operator's edit fires, gating on
  state set by a prior, separate `normal_execute()` iteration.

**`src/nvim/state.c`**
- line 34 — `state_enter()` — the generic modal-state event loop shared by Normal,
  cmdline, etc. Exact match (newer-round citation).

**`src/nvim/api/vim.c`**
- line 1601 — `nvim_get_keymap()` — global-scope keymap enumeration API. No drift.

**`src/nvim/api/buffer.c`**
- line 870 — `nvim_buf_get_keymap()` — buffer-local keymap enumeration API (doc cites
  859; drift +11).

**`src/nvim/keycodes.h`**
- line 197 — `KE_PLUG = 83` — the `<Plug>` keycode enum value. No drift.
- line 452 — `K_PLUG` macro (`TERMCAP2KEY(KS_EXTRA, KE_PLUG)`) (doc cites 450; drift +2).

**`runtime/lua/vim/_core/defaults.lua`**
- lines 109-110 — default `Y` → `y$` mapping via `vim.keymap.set`, tagged
  `:help Y-default` (doc cites 108; drift +1-2).

**`runtime/lua/vim/keymap.lua`**
- lines 65-115 — `keymap.set()` — the public `vim.keymap.set` Lua wrapper; calls
  `nvim_set_keymap`/`nvim_buf_set_keymap` internally at lines 109-111 (doc cites 57-105;
  drift +8/+10).

### which-key.nvim (`/Users/dhruv/.local/share/nvim/site/pack/core/opt/which-key.nvim`)

**`lua/which-key/buf.lua`**
- lines 6-12 — `wk.Mode` class definition, incl. `triggers: wk.Node[]` field (line 10)
  (doc cites 7-12; drift -1). Note: `modes: table<string, wk.Mode>` lives on `wk.Buffer`
  (below), not on `wk.Mode` itself.
- lines 22-38 — local `is_safe()` — the single-key trigger safelist (`g`/`z`/`Z`) (doc
  cites 28-36; close match).
- lines 56-93 — `Mode:attach()` — walks the tree, installs real trigger keymaps; ends
  with `Triggers.schedule(self)` (line 92). Exact match.
- line 83 — where `Config.triggers.mappings` (explicit extra triggers) is consumed,
  inside `attach()`.
- lines 117-145 — `Mode:update()` — merges real keymaps + user spec + plugin specs onto
  tree nodes, then `tree:fix()` + `attach()` (140-141). Exact match.
- lines 120-121 — the `nvim_get_keymap(mode)` / `nvim_buf_get_keymap(buf, mode)` calls.
  Exact match.
- lines 124-131 — filters: skip `which-key-trigger`-tagged desc, `<Nop>` kept as
  virtual-desc-only, drop `<Plug>...`/`<SNR>...` lhs (doc cites 125-131; close match).
- line 129 — the specific `<Plug>`/`<SNR>` lhs-prefix filter condition. Exact match.
- line 136 — `self.tree:add(m, true)` — reinsertion of user-spec mappings as
  `virtual = true`.
- lines 147-160 — `wk.Buffer` class + `Buf.new`. Exact match.
- lines 181-199 — `Buf:get()` — lazy per-mode tree construction (`Mode.new` triggers an
  eager `update()` for that one mode) (doc cites 182-199; close match).

**`lua/which-key/state.lua`**
- line 14 — `---@field started number` type annotation.
- lines 54-63 — `RecordingEnter`/`RecordingLeave` autocmds suspending triggers during
  macro recording. Exact match.
- lines 183-215 — `M.check()` — descends the trie one key at a time via
  `state.node:find(key)`. Exact match.
- line 187 — `local delta = uv.hrtime()/1e6 - state.started` (doc cites 188; drift -1).
- lines 193-199 — the `has_children`/`is_nowait`/`is_action` decision that picks
  descend-vs-execute (doc cites 194-199; drift -1).
- lines 221-239 — `M.execute()` — suspends triggers (222), prepends
  `vim.v.count`/register (228-239), then feeds keys back to Vim.
- line 222 — `Triggers.suspend(state.mode)`. Exact match.
- lines 228-239 — count/register prepending logic. Exact match.
- lines 242-244 — `M.getchar()` helper wrapping `vim.fn.getcharstr()`.
- lines 248-275 — `M.step()` — per-keypress helper: reads one char (262) then calls
  `M.check` (270). Doc described this range as "the `getcharstr` loop" — the actual
  `while M.state do ... end` loop was factored out to a different location (see next
  entry); `M.step` is the per-iteration body, not the loop itself.
- lines 278-369 — `M.start()` — entry point: finds the prefix node, builds `M.state`
  (322-328, `started =` at 326), runs the loop. Exact match for the function's own span.
- lines 338-354 — the actual `while M.state do ... M.step(M.state) ... end` loop (doc's
  inline citation of "248-275" for this loop reflects an older, unfactored layout; in
  the checked-out revision the loop body lives here and calls out to `M.step`).

**`lua/which-key/triggers.lua`**
- lines 39-53 — `M.add()` — registers a real `vim.keymap.set` trigger whose callback
  calls `state.start(...)`. Exact match.
- lines 139-156 — `M.schedule()` — re-attaches a trigger one tick later via a
  `vim.uv` timer. Exact match.

**`lua/which-key/config.lua`**
- lines 13-15 — `delay` option, default 200ms popup delay. Exact match.
- line 32 — raw trigger spec entry `{ "<auto>", mode = "nxso" }`. Exact match.
- lines 267-278 — where that raw spec is compiled into the lookup table
  `M.triggers.modes[m.mode] = true` actually consulted at runtime.
- lines 323-334 — `M.add()` (config-level) — parses the user spec via
  `mappings.parse()` and stores it in the module-level `M.mappings` table. Note: the
  `virtual = true` reinsertion the doc describes happens later, per-buffer, in
  `buf.lua:136` / `tree.lua:M:add` (below) — not in this function.

**`lua/which-key/node.lua`**
- lines 3-4 — `wk.Node` class annotation + `_children` field.
- lines 10-25 — `M.new()` constructor — sets `parent`, `key`, `path`, `global`,
  `_children`, `keys`. Note: `keymap`/`mapping`/`plugin` are *not* set here — they're
  assigned later by `tree.lua:M:add` (below) and surfaced via `__index` (next entry).
- lines 53-70 — `__index` metamethod — falls through to `.mapping` or `.keymap` so
  callers don't care which side defined a field. Exact match.
- lines 119-180 — `M:expand()` — materializes ephemeral child nodes (marks, registers,
  etc.) for plugin/proxy nodes. Exact match.

**`lua/which-key/tree.lua`**
- lines 25-46 — `M:add(keymap, virtual)` — inserts a keymap/mapping onto the trie;
  sets `node.plugin` (31), `node.mapping` (41), `node.keymap` (44).
- lines 72-79 — `M:fix()` — prunes nodes with no real keymap, no useful group, and no
  desc. Exact match.

**`lua/which-key/mappings.lua`**
- line 107 — `M._parse(spec, ret, opts)` — the recursive spec-parser the doc references
  by name without a line number. Recurses on itself at line 228; closes at line 232.
- line 308 — `M.parse()` — the public wrapper, calls `_parse` at line 311.

**`lua/which-key/plugins/init.lua`**
- lines 9-23 — `M.setup()` — iterates `Config.plugins` and `require`s each
  `which-key.plugins.<name>` module (marks, registers, spelling, presets are entries in
  that config table, not hardcoded here). Exact match.

**`lua/which-key/plugins/marks.lua`**
- lines 33-62 — `M.expand()` — lazily computes the mark list via
  `vim.fn.getmarklist()` / `getmarklist(buf)`. Exact match.

**`lua/which-key/util.lua`**
- lines 3-7 — `M.cache` — memoization tables for `keys`, `norm`, `termcodes`. Exact
  match.
