# Plan: Keymap analysis & optimization tracks

A comprehensive audit of every keybinding in the nvim config, followed by four
independent improvement tracks. Each track is a different *kind* of
optimization — correctness, consistency, ergonomics, tooling — adoptable
separately and in any order (except A, which should land first).

Relation to existing plans:
- `plans/keymaps-refactor.md` — largely implemented already (groups, descs,
  `<leader>?`, prefix conventions). This doc supersedes its open items.
- `plans/keymap-tracker.md` — the usage-tracking research. Track C below
  depends on it; nothing else does.

---

## Current state: inventory

~95 `vim.keymap.set` calls across 20 modules, plus plugin-managed maps
(blink.cmp, telescope in-picker, nvim-tree/aerial buffer-local, toggleterm's
`open_mapping`). 17 which-key leader groups.

| Namespace | Owner file | Contents |
|---|---|---|
| `<leader>s*` | keymaps.lua | 13 Telescope/search pickers |
| `<leader>t*` | scattered (keymaps, lsp, git, format, linting, pickers) | 11 toggles |
| `<leader>T*` | terminal.lua | 4 terminal openers |
| `<leader>a*` | keymaps.lua | 12 AI/sidekick |
| `<leader>g*` | gitui.lua | 10 Neogit popups |
| `<leader>v*` | gitui.lua | 7 diffview |
| `<leader>h*` | git.lua (buffer-local) | 4 hunk ops |
| `<leader>d*` | debugging.lua, rust.lua | 12 debug |
| `<leader>n*` | testing.lua | 8 neotest |
| `<leader>p*` | lsp.lua (buffer-local) | 5 peek floats |
| `<leader>c*` | lsp.lua, format, linting, rust | 8 code actions |
| `<leader>q*` | session.lua, keymaps.lua | 4 session + 1 close-buffer |
| `<leader>b*` | keymaps.lua, scratch.lua | close + 2 scratch |
| `<leader>u*` | keymaps.lua, titling.lua | 4 utilities |
| `<leader>r*` | lsp.lua (buffer-local) | 1 (rename) |
| singletons | various | `<leader>e` `o` `O` `m` `?` `<leader><leader>` |
| non-leader | various | `jj`, clipboard `y/Y`, `</>/p` visual, `<C-hjkl>`, `<A-hjkl>`, `<S-h/l>`, `<Tab>` NES, `<C-.>`, `<C-\>`, `<C-`>`-family, mouse, `gd/gD/gy/gri/grr`, `K`, `<C-s>`, `]c [c ]s [s ]a [a`, `yp/yP/yc/yC/yu`, `<M-o>/<M-i>`, `<F5>/<F9>-<F12>`, `<D-*>` (Neovide) |

### What's already good (don't churn)

- Every map has a `desc`; most follow `Group: Action`.
- The `<leader>T` vs `<leader>t` split (buffer-local shadowing fix) is
  documented and correct.
- Deliberate, commented aliases: `<C-`>/<C-_>/<C-/>` (terminal compat),
  `<leader>ai` for `<C-.>`, `<leader>s/`+`sb`.
- `gr*` follows nvim 0.11+ core conventions instead of inventing new keys;
  telescope overrides only where multi-result UX matters.
- Guards (`is_special`) give feedback instead of silent no-ops.
- Mnemonic mirroring of zsh git aliases (`<leader>gc/gp/gu/gl` ≈ shell
  `gc/gp/gu/gl`) — cross-tool muscle memory.

---

## Findings (evidence for the tracks)

Each numbered finding is referenced by the tracks below.

**F1 — Select-mode pollution (real bug).** These maps use mode `'v'` (visual
**and select**) or `{'n','v'}`:
`<`/`>`/`p` (keymaps.lua:72-76), `y` (keymaps.lua:61), `<leader>cf`
(format.lua:79), `<leader>ca`/`<leader>de` (lsp.lua:246, debugging.lua:48),
`<D-c>` (neovide.lua:35), and the which-key `<leader>` trigger itself
(whichkey.lua:13). blink.cmp expands LSP snippets via `vim.snippet`, which
puts placeholders in **select mode** — where typing should replace the
selection with literal text. With these maps, typing `p` inside a placeholder
runs `"_dP` (pastes!), `y` yanks to clipboard, and `<Space>` opens which-key
instead of inserting a space. The config already uses `'x'` correctly in six
other places (`<leader>at`, `<leader>us`, `<leader>uc`, `<leader>tc`, yank
maps, `<M-o>/<M-i>`) — the `'v'` ones are stragglers.

**F2 — Doc drift.** GUIDE.md line 375 documents `jk` → exit insert; the code
maps `jj` (keymaps.lua:56). One of them is wrong.

**F3 — Signature help is normal-mode only.** `<C-s>` (lsp.lua:244) fires
signature help in normal mode, but the moment you need a signature is while
*typing arguments* in insert mode (blink's auto-signature covers typing-time,
but there's no on-demand re-trigger after dismissing it). Nvim 0.11+ core
maps `<C-s>` in insert+select mode for exactly this.

**F4 — `<leader>ad` is destructive and sits one slot from daily-driver keys.**
`close()` kills the CLI process and session (ai.lua's own comment: "this is
not hide — it's tear down"), adjacent to `aa` (toggle) and `as` (select). A
typo costs the whole Claude session.

**F5 — Inconsistent quit/stop letters.** Close/terminate is `q` in five
namespaces (`gq`, `vq`, `pq`, `dq`, `qq`) but `S` in tests (`nS` stop,
because `ns` = summary). Capital pairs also mean different things per group:
`ns/nS` = summary/stop, `no/nO` = output/output-panel, `do/dO` =
step-over/step-out.

**F6 — `<leader>q` group mixes two concepts.** Group label is "Session/Quit":
`qs/qS/ql/qd` are sessions; `qq` closes a *buffer* (alias of `<leader>bd`).

**F7 — `<leader>r` "Refactor" group holds one key**, `rn` = rename, which
duplicates core `grn`. Similarly `<leader>ca` duplicates core `gra`. (The
telescope-backed `grr/gri` overrides are justified; these two are plain
duplicates with a leader-key cost of one extra group.)

**F8 — Buffer operations are scattered across four homes.** Picker =
`<leader>m`, alternate = `<leader><leader>`, cycle = `<S-h>/<S-l>`, close =
`<leader>bd`, while the `<leader>b` "Buffer" group holds close + two
*scratch* maps. Which-key's `<leader>b` popup doesn't tell the buffer story.

**F9 — `<leader>tc` (toggle comment) is an action in a settings namespace.**
Every other `<leader>t*` flips persistent state (spell, numbers, diagnostics,
blame, format-on-save…); `tc` edits text and duplicates built-in `gcc`/`gc`.

**F10 — Desc-format stragglers.** `Toggle scratch buffer` / `Select scratch
buffer` (scratch.lua), `Lint buffer` (linting.lua), `Format buffer`
(format.lua), `Buffer picker` (keymaps.lua:136) lack the `Group: Action`
prefix the `<leader>sk` picker and tags system key off.

**F11 — Manual metadata tables drift.** whichkey.lua's `keywords` (49
entries) and `tags` (28 entries) are hand-maintained per-lhs. Several current
keys are missing (`<leader>gg`, `<leader>gp`, `<leader>gu`, `<leader>gl`,
`<leader>gr`, `<leader>gw`, `<leader>gq` have no tags; the `tags` table says
`<leader>gd/gs/gc/gb` — `gs` doesn't exist). Tags like `git`/`debug`/`test`
are mechanically derivable from the desc prefix.

**F12 — `<Tab>` NES map vs `<C-i>` (terminal-dependent).** In terminals
without the kitty keyboard protocol / CSI u, `<Tab>` and `<C-i>` are the same
byte, so the normal-mode NES map (keymaps.lua:249) shadows jumplist-forward.
Fine in kitty/iTerm2-with-CSI-u/Neovide (this setup), breaks over plain ssh.
Mouse X2 and `<D-M-Right>` are partial fallbacks. No change proposed — worth
a GUIDE.md caveat only.

**F13 — `<A-hjkl>` resize is self-declared speculative** (keymaps.lua:89:
"may remap to something else later if they go unused"). No usage data exists
to decide (see Track C).

**F14 — `<S-h>/<S-l>` buffer cycling shadows native `H`/`L`**
(top/bottom-of-screen motions). Deliberate, common tradeoff — listed here
only so the decision is recorded as *accepted*, not accidental.

---

## Track A — Correctness fixes (recommended unconditionally)

Small diffs, zero muscle-memory cost, each fixes an actual defect.

### A1. Fix select-mode pollution (F1)

Change mode `'v'` → `'x'` (and `{'n','v'}` → `{'n','x'}`) for: `<`, `>`, `p`,
`y`, `<leader>cf`, `<leader>ca`, `<leader>de`, `<D-c>`, `<D-v>` (visual
variant), and the which-key trigger (`mode = { 'n', 'x' }`).

**Why it's better — concrete failure today:**
```
1. In a Lua buffer, type `vim.key` → accept `keymap.set(...)` completion
2. vim.snippet drops you in a placeholder, selected in SELECT mode
3. Type "print_fn" to name the arg
   → the leading `p` fires `"_dP`: your clipboard content is pasted
     over the placeholder instead of the text you typed
```
After the fix, select mode behaves like every other editor's snippet
placeholders: typing replaces. Visual-mode behavior is unchanged (`'x'` is
exactly visual-without-select).

### A2. Reconcile `jj` vs `jk` (F2)

Code says `jj`, GUIDE.md says `jk`. Pick one (see Track C4 for the
ergonomics argument for `jk`) and fix the other. Minimum viable fix: GUIDE.md
line 375 → `jj`.

### A3. Add insert-mode signature help (F3)

```lua
map({ 'n', 'i' }, '<C-s>', vim.lsp.buf.signature_help, 'LSP: Signature help')
```

**Why it's better:** mid-call, cursor between parens, blink's auto-signature
dismissed — today you must leave insert mode, press `<C-s>`, re-enter insert.
After: one chord, stay in flow. Matches nvim core's own 0.11 default.

### A4. Guard the destructive `<leader>ad` (F4)

Options (pick one):
1. **Confirm prompt** (recommended): wrap `close()` in
   `vim.fn.confirm('Kill CLI session?')` — one extra keystroke on a rare,
   destructive action; typo-proof.
2. Move to `<leader>aD` — capital = "louder" variant, `ad` freed.
3. Leave as-is (it *is* documented in the desc).

**Why it's better:** `aa`→`ad` is a one-key slip that today silently discards
a running Claude conversation. Every other destructive surface in this config
(nvim-tree delete, session stop) has either a prompt or an undo path.

### A5. `nS` → `nq` (F5, test half)

`Test: Stop` moves to `<leader>nq`, matching `gq/vq/pq/dq/qq`.

**Why it's better — before/after the convention table:**
| Intent | Git | Diffview | Peek | Debug | Test |
|---|---|---|---|---|---|
| before: close/stop | `gq` | `vq` | `pq` | `dq` | `nS` ← odd one out |
| after | `gq` | `vq` | `pq` | `dq` | `nq` |

One rule ("q closes the thing this namespace owns") instead of a rule plus an
exception. `nS` frees up; `ns` (summary) untouched.

Deliverables: edits in keymaps.lua, lsp.lua, debugging.lua, format.lua,
neovide.lua, whichkey.lua, ai.lua, testing.lua + matching GUIDE.md rows.
Per-change commits (see Sequencing).

---

## Track B — Namespace & mnemonic consistency

Medium churn: a handful of keys move. Each change is independent; adopt à la
carte. All muscle-memory-affecting, so each lists a transition aid.

### B1. Make `<leader>q` purely Session (F6)

- Rename group label `Session/Quit` → `Session`.
- `<leader>qq` currently = close buffer. Either drop it (canonical
  `<leader>bd` stays) or — better — repurpose `qq` as `:qa`-adjacent
  "quit nvim" which its letters actually suggest, if you'd use it.
- Transition aid: keep `qq` mapped to a `vim.notify('moved to <leader>bd')`
  stub for a few weeks, then delete.

**Why it's better:** today `<leader>q` which-key popup reads: *Close buffer,
Restore, Select, Restore last, Stop saving* — one of these is not like the
others. Post-change the group is scannable and the label needs no slash.

### B2. Dissolve or grow the one-key `<leader>r` group (F7)

Options:
1. **Dissolve (recommended):** delete `<leader>rn`, rely on core `grn`
   (already active, already in which-key's `g` group). Also consider deleting
   `<leader>ca` for `gra` — or keep it since visual-mode code actions on
   `gra` are awkward. Frees an entire top-level leader key.
2. Grow it: `rn` rename, `ri` inline, `re` extract (LSP code-action-filtered)
   — only worth it if refactor actions get real use.

**Why it's better (option 1):** a top-level leader letter is scarce real
estate — 17 of 26 are taken. Spending one on a single alias of a built-in
means the which-key root popup carries a whole group row for one key. Freed
`r` becomes available for something with fan-out (e.g. a future Run/REPL
namespace).

### B3. Unify the buffer story under `<leader>b` (F8)

- `<leader>bb` → buffer picker (today `<leader>m`; keep `m` as alias
  initially — it's cheap and one-keystroke shorter, may survive on merit).
- `<leader>bd` stays (close), `bs/bS` stay (scratch).
- Optional: `<leader>bo` → close all other buffers (new, cheap via
  mini.bufremove loop) — a frequently-missed operation.

**Why it's better:** pressing `<leader>b` + wait becomes a complete buffer
menu: *picker, delete, scratch, scratch-select, [only]*. Today that popup
shows close + scratch only, and discovering the picker requires knowing the
unrelated `<leader>m`. New-machine muscle memory has one home. LazyVim users
(largest convention pool) expect exactly `<leader>bb`/`<leader>bd`.

### B4. Evict the comment toggle from `<leader>t` (F9)

Delete `<leader>tc` (normal + visual). `gcc`/`gc` are the native, universal
keys and already which-key-discoverable under `g`.

**Why it's better:** `<leader>t` becomes 100% "flip a setting" — every entry
in the popup is a stateful toggle, so scanning it answers "what modes am I
in?" (several toggles echo their state). No functionality lost: `gcc` is
*fewer* keystrokes than `<leader>tc`.

### B5. Standardize the desc stragglers (F10)

`Buffer: Toggle scratch`, `Buffer: Select scratch`, `Buffer: Picker`,
`Code: Lint buffer`, `Code: Format buffer`.

**Why it's better:** `<leader>sk` fuzzy-search groups by desc prefix; typing
"Buffer:" today misses the scratch pads and the picker. Also a prerequisite
for Track D1 (mechanical tag derivation).

---

## Track C — Ergonomics: measure, then optimize hot paths

> **Status: deferred (2026-07-09).** Nothing below is being implemented now.
> Kept as the backlog of things to try — revisit after A/B/D have settled.

Highest potential payoff, highest muscle-memory cost, and — crucially — the
config has **no usage data** to rank candidates. Guessing frequency is how
speculative maps like `<A-hjkl>` (F13) happen. So:

### C1. Implement `plans/keymap-tracker.md` first (2 small modules)

The research is done; Primitive 1 (snapshot) + Primitive 2 (usage log) are
~150 lines total. Let it run for 2–4 weeks.

**Why it's better than optimizing now:** every reorganization in Track B is
justified by *semantics*; Track C changes are justified only by *frequency*
(shortest keys for hottest actions). Without the log you'd optimize by
anecdote. With it, decisions become one-liners:
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

### C3. Resolve `<A-hjkl>` (F13) with data

If the log shows zero invocations after a month: unmap, and consider
`<A-h>/<A-l>` for buffer prev/next (releasing `<S-h>/<S-l>`, restoring native
`H`/`L` — resolves F14) or window-swap. If they do get used, delete the
"speculative" comment and keep them.

### C4. Insert-escape: `jj` vs `jk` (ties into A2)

`jk` is a two-finger inward roll (faster than a double-tap, no key-repeat
ambiguity) and — since GUIDE.md *already documents jk* — half the config
believes it's `jk` anyway. Mapping **both** costs nothing:
`jj` stays for muscle memory, `jk` gets documented as canonical.

**Why it's better:** typing latency on the `j` prefix is identical (timeout
starts either way); a roll is measurably quicker to complete than a
double-tap; and the doc-vs-code conflict disappears without retraining.

---

## Track D — Tooling & guardrails (make consistency self-maintaining)

The audit above found drift (F2, F10, F11) that no human process caught
despite this repo's unusually strict doc discipline. Encode the conventions.

### D1. Derive picker tags from desc prefixes (F11)

In `pickers/keybindings.lua` (or a shared helper): tag = lowercased text
before the first `:` in desc (`"Git hunk: Stage"` → `git hunk`), with a small
override table for the current hand-tuned extras (`rust`, `diff`, `lsp`).
Delete the 28-entry manual `tags` table; keep `keywords` (genuinely
non-derivable synonyms).

**Why it's better — the drift is already visible:** the manual table tags
`<leader>gs`, which *doesn't exist*, and misses 7 real `<leader>g*` keys
added later. A derived tag can't go stale: the day B5 lands, every scratch
map is automatically searchable under "buffer" with zero whichkey.lua edits.

### D2. Keymap-audit skill — a lint for the conventions this config already has

A Claude Code skill (`claude/.claude/skills/keymap-audit/SKILL.md`, stowed
like `nvim-theme-to-claude`) that audits the config's keymap sources
(`lua/*.lua`, `whichkey.lua`, GUIDE.md) and reports violations of:
1. maps with no `desc` (existing house rule)
2. `desc` not matching `^%u[%w%s%-]*: ` (Group: Action) — allowlist for
   intentional singletons
3. mode `'v'` or `{'n','v'}` maps (select-mode hazard, F1's regression guard)
4. leader prefixes with ≥2 maps but no which-key group label
5. duplicate lhs within a mode (excluding documented aliases via a small
   allowlist)
6. group-letter squatters: groups with exactly 1 binding (would have flagged
   F7)
7. doc sync: every keymap in code appears in GUIDE.md (per the nested
   CLAUDE.md rule) and every documented key still exists in code; whichkey
   `keywords`/tag overrides reference only existing lhs

Invoked on demand (`/keymap-audit`) — e.g. after a batch of keymap changes.

**Why it's better:** F1 existed because six maps predated the config's own
`'x'` convention and nothing re-checked old code against new rules. Every
finding class in this doc that was *mechanical* (F1, F5, F7, F10, F11)
becomes a red line in a health report instead of an archaeology project. The
repo already treats "undocumented keymap = incomplete change" (CLAUDE.md);
this makes that rule executable.

### D3. (Optional, cosmetic) which-key group icons

From the old keymaps-refactor.md plan; still unimplemented; purely visual
scannability of the root popup. Cheap, zero risk, do whenever.

---

## Sequencing & verification

Suggested order (respecting the per-change-commit convention with `Part-of:`
trailers):

1. **A1–A5** — six small commits, no decisions needed beyond A4's option.
2. **D1, D2** — guardrails in place *before* the renames, so B-track changes
   get linted as they land.
3. **B1–B5** — one commit per key-move, GUIDE.md updated in the same commit
   (house rule). Transition stubs where noted.
4. **C1** — tracker modules; then a calendar reminder ~4 weeks out to run the
   analysis and decide C2/C3/C4.

Verification (pause before running, per workflow preference):
- `:KeymapAudit` clean (after D2).
- Snippet placeholder test: expand a snippet, type `p`/`y`/`<Space>`/`<`
  inside the placeholder — literal text must appear (A1).
- `<leader>` + wait: Session group shows only sessions (B1); Toggle group
  shows only toggles (B4); Buffer group shows picker+close+scratch (B3).
- `<leader>sk`: search "buffer" surfaces scratch + picker (B5/D1).
- `grep -n 'jk' GUIDE.md` agrees with the code (A2).
- GUIDE.md keymap index + per-section tables updated for every moved key;
  `grep -rn 'GUIDE.md' lua/` anchors still resolve.

## Decisions (resolved 2026-07-09)

1. **A4**: confirm prompt on `<leader>ad` (kill CLI session).
2. **A2/C4**: map **both** `jj` and `jk` for insert-escape; document both.
3. **B1**: `<leader>qq` repurposed as **quit-all (`:qa`) with a confirm
   prompt**; group label stays `Session/Quit` (now accurate).
4. **B2**: drop `<leader>rn` (rely on core `grn`), dissolve the `<leader>r`
   group; **keep** `<leader>ca`.
5. **B3**: add `<leader>bb` (picker), keep `<leader>m` as permanent alias;
   **also add `<leader>bo`** (close all other buffers).
6. **B4**: remove `<leader>tc` (both modes) — `gc` operator + `gcc`
   line-shortcut are the native, sufficient keys.
7. **Track C: deferred entirely** — no tracker build, no alias promotions
   yet. The C2 alias candidates (`<leader>f` find files, `<leader>/` grep,
   `<leader>.` resume) stay recorded in this doc as things to try later.
8. **D1**: yes — derive picker tags from desc prefixes, slim override table
   for non-derivable extras.
9. **D2**: build the audit as a **Claude Code skill**
   (`claude/.claude/skills/keymap-audit/`), not an in-nvim `:KeymapAudit`
   command — the checks are read-and-reason work, better done by a skill
   that can also cross-check GUIDE.md prose, with no lua lint code to
   maintain.
10. **D3**: no which-key icons.
