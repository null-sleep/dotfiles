---
name: keymap-audit
description: Audit this dotfiles repo's nvim keymap conventions on demand (desc presence/format, select-mode-safe visual maps, which-key group hygiene, duplicate lhs, doc sync with GUIDE.md). Use when the user asks to check/audit/lint nvim keymaps, review a batch of keymap changes for consistency, or asks "is GUIDE.md in sync with the code" for keybindings. Read-only — reports findings, fixes nothing.
---

# Keymap audit

A lint for the nvim config's own keymap conventions — the ones documented in
`nvim/.config/nvim/CLAUDE.md` and enforced only by human discipline today.
A 2026-07 keymap audit (plan since landed and removed from `plans/`) found
real drift (a stale `jj`/`jk` doc mismatch, a hand-maintained tags table
that tagged a nonexistent key and missed seven real ones, six maps using
the wrong visual mode) that nothing caught until an explicit audit. This
skill is that audit, runnable anytime, not just after a big refactor.

**This skill only reports. It never edits code or GUIDE.md** — if findings
warrant a fix, that's a separate, explicit follow-up task.

## Scope

Read these before reporting anything:

- `nvim/.config/nvim/lua/*.lua` and `nvim/.config/nvim/lua/pickers/*.lua` —
  every `vim.keymap.set(...)` / `map(...)` call (including buffer-local ones
  set inside `LspAttach`, `FileType`, etc. autocmds).
- `nvim/.config/nvim/lua/whichkey.lua` — group labels, `triggers`, the
  `keywords` and `tags` tables.
- `nvim/.config/nvim/GUIDE.md` — the `Keymap index` (By prefix + Global
  keymaps tables) and every Part 2 feature section's own keymap table.

## Checks

Run all seven, independent of each other — a failure in one doesn't block
checking the rest.

### 1. Missing `desc`

Every `vim.keymap.set` / wrapped `map()` call must pass a `desc` (string or
via an opts table). Flag any that don't — which-key and the `<leader>sk`
picker both key off it.

### 2. Desc format (`Group: Action`)

Desc should match `^%u[%w%s%-/]*: ` (capitalized group, colon, space, then
the action) — e.g. `Git hunk: Stage`, `Debug: Continue`. This check is
scoped to what its intent covers: **leader-namespace maps and other global
maps that belong to a which-key group** — the descs the `<leader>sk`
picker's desc-derived tags and which-key popup headings key off.

**Exempt as a class: buffer-local plugin-panel action labels.** Maps set
buffer-locally inside a plugin panel's own buffer describe in-panel
actions, not grouped global commands — a `Group:` prefix there would be
noise. Examples of the exempt class: nvim-tree's `on_attach` action labels
in `lua/filetree.lua`, and the sidekick CLI terminal's buffer-local maps in
`lua/ai.lua`. Recognize the class (buffer-local + set inside a plugin
panel's attach/autocmd), don't allowlist the literal strings — the
exemption must survive a label rewording.

For global maps, maintain a small allowlist of intentional singletons that
don't need a prefix (global, ungrouped actions, not part of any leader
namespace): `Exit insert mode`, `Clear search highlights and close floats`,
`Toggle alternate buffer`, `Yank to system clipboard (unless register
specified)`, `Yank line to system clipboard (unless register specified)`,
`Dedent and reselect`, `Indent and reselect`, `Paste without yanking
replaced text`, `Copy`, `Paste`, `Paste over selection`, `Paste (terminal)`,
`Save`, `Zoom in`, `Zoom out`, `Reset zoom`, `Move to left/right split`/
`Move to split above/below`, `Split: narrower/shorter/taller/wider`,
`Previous/Next buffer`, `Jumplist: back/forward (mouse back/forward
button)`, `LSP: Go to definition (Ctrl+click)`. Extend this allowlist
rather than flagging a deliberately bare global keymap as a violation — but
do flag anything new that looks like it belongs to a leader namespace and
just forgot the prefix.

### 3. Select-mode hazard (F1 regression guard)

No `vim.keymap.set` call may use mode `'v'` or include `'v'` in a mode list
(e.g. `{'n','v'}`, `{'n','i','v'}`). Visual-only maps must use `'x'`. This
guards against exactly the regression the 2026-07 keymap audit found:
`'v'` also matches **select** mode, and blink.cmp drops LSP
snippet placeholders into select mode — a `'v'` map there hijacks the
keystroke meant to type over the placeholder (e.g. a `p` map fires a paste
instead of literal `p`). Report every offending `file:line`; this a hard
fail, not a style nit.

### 4. Which-key group hygiene

- Every leader prefix with **2 or more** leaf keymaps (e.g. `<leader>g*` has
  many) must have a corresponding group label in `whichkey.lua`'s `wk.add()`
  call (`{ '<leader>X', group = '...' }`).
- Any **new single-char group** other than the four in `triggers`
  (`<leader>`, `g`, `[`, `]`) needs its own entry added to `triggers` — see
  the note at the top of `keymaps.lua` ("If you add a new single-char group
  in wk.add(), add it to triggers too").

### 5. Duplicate lhs within a mode

Flag any lhs mapped more than once in the same mode (global scope; buffer-
local overrides in `FileType`/`LspAttach` autocmds intentionally shadowing a
global map are expected and NOT a finding — e.g. Rust's buffer-local `K` and
`<leader>ca` overriding the LSP ones). Maintain an allowlist of documented,
intentional aliases so they don't get flagged as accidental duplicates:
`<leader>s/` / `<leader>sb` (both current-buffer fuzzy find), `<leader>bx` /
mini.bufremove close-buffer conventions, the `<C-_>`/`<C-/>`
terminal-toggle family, `<leader>ai` / `<C-.>` (CLI focus fallback), and
`<leader>bb` / `<leader>m` (buffer picker alias). A duplicate lhs not on this
list is a real finding.

### 6. Group-letter squatters

Flag any which-key group (`wk.add()` entry with `group = ...`) that resolves
to **exactly one** leaf binding — a single key doesn't need a whole
top-level group slot (this is what the 2026-07 keymap audit called out for
the old `<leader>r` "Refactor" group, since dissolved).

### 7. Doc sync (both directions)

- **Code → GUIDE.md**: every keymap defined in code should appear somewhere
  in GUIDE.md — either a feature section's own table or the `Keymap index`
  → `Global keymaps` table (per the ownership rule in the nested
  `nvim/.config/nvim/CLAUDE.md`: never document the same key in two tables,
  but it must be in exactly one). Flag any keymap missing from both.
- **GUIDE.md → code**: every key documented in a GUIDE.md keymap table
  should still exist in code. Flag any that don't (stale doc, renamed/
  removed keymap).
- **whichkey.lua sanity**: every lhs used as a key in `keywords` or `tags`
  should correspond to a real keymap somewhere in the lua sources. Flag any
  that don't (this is exactly how the old tags table's phantom `<leader>gs`
  entry went unnoticed).

## Output format

A findings report grouped by check number (1–7), each finding as
`file:line — description`. End with a one-line pass/fail summary per check
(e.g. `Check 3 (select-mode hazard): PASS` or `Check 5 (duplicate lhs): FAIL
— 2 findings`). If a check has zero findings, still report it as `PASS` so
the report is a complete scorecard, not just a list of problems.

Do not fix anything found — this skill's contract is report-only.
