# Plan: Keymap usage tracker

Primary goal: track every explicit keymap invocation to a persistent log file.
Build on top of a reusable "all keymaps" enumeration primitive so future features
(never-used analysis, usage-aware pickers, weekly summaries) layer on cheaply.

---

## Status

- Research: **complete** — Neovim resolver internals, which-key approach, and the
  enumeration story (`nvim_get_keymap` semantics, mode coverage, miss cases) are all
  documented below.
- Architecture: **proposed** — two primitives (`keymap_snapshot.lua`,
  `keymap_tracker.lua`) with file-based outputs, integrated via two small edits to
  existing files. Recommended approach is recorded; alternatives rejected with
  reasoning.
- Decisions pending: see [Open questions / decisions pending](#open-questions--decisions-pending) at the end of this doc — three small choices remain before implementation.
- Code: **not yet written.** No files created or modified in `nvim/.config/nvim/`.

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

---

## Background: how which-key.nvim approaches the same problem

Worth comparing because which-key faces a similar problem (knowing about every keymap and
reacting to prefix sequences) and solves it differently. The relevant files live at
`/Users/dhruv/src/which-key.nvim/lua/which-key/`.

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

which-key applies the `<Plug>`/`<SNR>` filter at
`/Users/dhruv/src/which-key.nvim/lua/which-key/buf.lua:129`.

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
  ~15 lines.
- **Mode-aware picker**: today's picker is normal-mode only. With Primitive 1 it
  trivially extends to all modes with a mode-filter prompt — same picker shape, swap
  the data source from `which-key.buf.get({mode='n'})` to `keymap_snapshot.collect()`.
- **Weekly summary**: shell script over the log grouped by week + mode.
- **Suggestion engine**: rank keymaps by `desc` similarity to a query, weighted by
  inverse-usage — surfaces forgotten keymaps. Stretch goal.
- **`kmap-top` shell alias**: `jq -r '"\(.m) \(.lhs)"' keymap_usage.log | sort | uniq
  -c | sort -rn | head -30`.

---

## Alternatives considered

**`vim.on_key` keystream listener.** Subscribe to raw key bytes; match against the
snapshot's `lhsraw` set after each key. Catches every fire regardless of registration
path. *Rejected*: reproduces the resolver's FULL/PARTIAL/NONE trichotomy and
`timeoutlen` logic in Lua (see the Neovim background) — overcounting (logging both
`j` and `jj`) or undercounting (logging `<leader>` prefix presses) are likely failure
modes. Performance-sensitive on every keystroke.

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

## Resuming notes

If picking this up after time has passed:

- The user's `init.lua` line numbers may have shifted — re-verify with `Read` before
  inserting the `require('keymap_tracker')` line. The current load order is documented
  at `## Status` (top of file).
- The user's `pickers/keybindings.lua` `build_results()` function shape may have
  changed. The integration is one `pcall` line at the end of that function; verify the
  function name and end position before adding it.
- All cited line numbers in the Background sections are pinned to specific Neovim and
  which-key.nvim revisions present in `/Users/dhruv/src/neovim/` and
  `/Users/dhruv/src/which-key.nvim/` at the time of research. If those repos have been
  updated, re-grep for the function names (`keymap_array`, `mapblock_fill_dict`,
  `get_map_mode`) before relying on specific line numbers.
- The `<leader>sk` picker currently passes `mode = 'n'` to `which-key.buf.get` — this
  is a real coverage gap. Once Primitive 1 lands, the picker can switch its data
  source from the which-key tree to `keymap_snapshot.collect()` and gain all-mode
  coverage.
- If using Neovide, then Cmd based keymaps are also an option. Should consider this as well.
  - Can be as easy as manually tracking this for now.
  - Goal is to make sure we can integrate Neovide keymaps as well at a later date.
- Note for myself: 
  - Consider the usageof this data, shold we include timestamps? What other metadata is useful here?
