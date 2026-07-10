# Polish features to borrow from AstroNvim

## Context

Investigated `/Users/dhruv/src/AstroNvim` (AstroNvim core, 2026-07) for ideas
worth porting into this config. Cross-checked every candidate against the
existing setup so this plan only lists real gaps. AstroNvim's big
architectural pieces (lazy-loading `User AstroFile` events, pausable
`vim.notify` queue, per-tab buffer lists) exist to serve lazy.nvim's
event-based loading and a bufferline — neither applies to this eager
`vim.pack` config, so they're deliberately excluded (see "Rejected" at the
bottom).

File references are into the AstroNvim repo unless prefixed otherwise. Some
cited mechanisms ultimately live in the separate **astrocore** dependency
repo; the paths below are where the wiring/spec is visible in the core repo,
and every "Adopt" item is fully readable there.

## Review revisions (2026-07-10)

Plan critiqued against the live config. Changes folded in below:

- **Item 8 mechanism corrected.** `is_special()` includes terminals/CLI
  buffers, not just sidebars — driving auto-quit off it would quit nvim when
  a toggleterm is the last window. Needs a sidebar-only subset instead. No
  longer a trivial one-liner; see the item.
- **Item 5 demoted to "Reassess".** `vim.on_key` fires on every keystroke and
  AstroNvim's auto-hlsearch has known edge cases; the payoff over the existing
  `<Esc>` clear is marginal. Do not land in the first batch.
- **Item 6 uses `:append`, not assignment**, so the `diffopt` defaults aren't
  clobbered.
- **Item 9 partially overlaps existing coverage** — `BufEnter` already fires
  `checktime` on return from a terminal. Kept, but the incremental value is
  smaller than stated.
- **Autocmd home decided** (see Implementation notes) + a suggested landing
  order added.

## Suggested landing order

- **Batch A — land first (safe, verified gaps):** 1, 2, 6, 10.
- **Batch B — guarded, more moving parts:** 3, 4.
- **Batch C — reassess before committing:** 5, 8, 9, 7.

## Adopt (high value, small code)

### 1. Auto-create parent directories on save

Not present in this config. On `BufWritePre`,
`vim.fn.mkdir(vim.fs.dirname(vim.fs.abspath(path)), "p")`, guarded to skip
URL-style buffer names (`file:match "^%w+:[\\/][\\/]"`) so it never mkdirs
for `fugitive://`/`oil://`-type buffers.
Source: `lua/astronvim/plugins/_astrocore_autocmds.lua:110`.

### 2. Restore last cursor position on file open

Genuine gap — no dedicated autocmd here, and verified Neovim 0.12.4's
`_defaults.lua` still does NOT do this. AstroNvim's version has the right
details: restore the `"` mark on `BufReadPost`, per-buffer
`last_loc_restored` guard flag, skip `gitcommit`/`gitrebase` (always want
line 1), wrap in `pcall`.
Source: `_astrocore_autocmds.lua:233`.

Sidebar/terminal safety (reviewed): `BufReadPost` is a disk-read event, so it
never fires for nvim-tree, aerial, sidekick, or `:terminal` buffers — those
are `nofile`/`terminal` buftypes created programmatically, not read from
disk. No special-buffer guard is needed for them; the only real files that
must be skipped are `gitcommit`/`gitrebase` (handled by the filetype skip).
The mark-in-bounds check + `pcall` covers a stale `"` mark past EOF.

### 3. Auto-open diagnostic float after `]d`/`[d` jumps

`vim.diagnostic.config({ jump = { on_jump = ... } })` opens a cursor-scoped,
non-focusable float after each diagnostic jump. Especially valuable here
because virtual text is off by default (`<leader>td`) — today a jump lands
on a diagnostic you can't see without another keypress.
Source: `_astrocore.lua:68`.

### 4. `q` to close transient windows, politely

On `BufWinEnter` for `help/nofile/quickfix` buftypes, map buffer-local
`q` → `<Cmd>close<CR>` — but first scan existing buffer keymaps so a
plugin's own `q` is never clobbered; cache decisions (AstroNvim uses
`vim.g.q_close_windows`) and clean up on `BufDelete`. In this config, drive
it from `lua/buffers.lua`'s `is_special()` registry instead of raw buftype.
Source: `_astrocore_autocmds.lua:199`.

Reviewed: the keymap-scan-before-binding step is the *hard* part, not
incidental — several buffers in the `is_special()` set (nvim-tree, aerial,
neogit, toggleterm) already bind or consume `q`. Getting the "don't clobber
an existing `q`" guard right is the bulk of the work here; budget for it.

Final approach (implemented): target `help`/`quickfix`/`nofile` buftypes,
then use `is_special()` as an *exclusion* (skip the interactive panels and
terminals that own their own `q` — its intended use), then skip any buffer
that already binds `q`. So `is_special()` selects what to *leave alone*, not
what to map — the reverse of the original phrasing, and consistent with the
item 8 correction.

### 5. `on_key`-driven auto-hlsearch — REASSESS (do not land first)

Reviewed down from "high value": `vim.on_key` runs on *every* keystroke, and
AstroNvim's implementation has known edge cases (macros, `n`/`N` via
mappings, heuristic `:s` cmdline detection). The existing `<Esc>` handler
(`keymaps.lua:47`) already clears highlight and works; the only gain here is
"clears without a keypress." Lowest reward-to-risk item in the plan — trial
in isolation or drop.

Use `vim.on_key` to enable `hlsearch` only while actively searching
(`/ ? n N * #` in normal mode, `:s` in cmdline) and disable it on any other
key — no manual clear needed. A `mid_mapping` flag + `vim.schedule` reset
prevents recursion. Interacts with the existing `<Esc>` clears-highlight
map: once this lands, that part of the `<Esc>` handler becomes redundant
(keep the close-floats part).
Source: `_astrocore_autocmds.lua:257` (~20 lines, self-contained).

### 6. `diffopt`: `linematch:60` + histogram algorithm

Markedly better intra-hunk diff alignment. Immediately visible in
diffview.nvim and Neogit. Use `opt.diffopt:append('linematch:60')` and
`:append('algorithm:histogram')` — append, don't assign, so the existing
`diffopt` defaults (`internal,filler,closeoff`, …) survive.
Source: `_astrocore_options.lua:16`.

## Consider (more code or smaller payoff)

### 7. LSP file-operation events for new files and renames

On `BufWritePre` for a not-yet-existing file, fire LSP
`willCreateFiles`; `didCreateFiles` on `BufWritePost` — servers fix imports
when a new file is first saved. Plus a rename command routing through
`willRenameFiles` (AstroNvim: `:AstroRename`, `<Leader>R`, `bang` to
overwrite, `complete = "file"`). nvim-tree doesn't wire these natively, so
tree renames currently break imports silently.
Source: `_astrolsp.lua:47-101`, `_astrocore.lua:16`.

### 8. Generalize the QuitPre auto-close to all sidebars

Current handler (`filetree.lua:94`) auto-closes nvim when nvim-tree is the
last window; Astro's `auto_quit` quits when *only sidebar windows* remain,
counting each sidebar filetype once so two splits of the same sidebar don't
fool it. Covers aerial too.

Correction (reviewed): **do NOT drive this off `is_special()`** — that
registry includes terminals and CLI buffers, so you'd quit nvim when a
toggleterm is the last window (wrong). Astro counts *sidebar* filetypes
specifically. Introduce a narrower sidebar-only subset (nvim-tree + aerial +
peers) — a distinct list from `is_special()`, mirroring the CLAUDE.md warning
against routing unrelated exclusion concerns through the shared predicate.
This makes the item a small-but-real change, not a ~5-line generalization.
Source: `_astrocore_autocmds.lua:25`.

### 9. `checktime` on `TermClose`/`TermLeave`

Config already reloads on focus/hold + a 500ms polling timer, but returning
from a toggleterm shell is exactly when files change — these two events
close that window instantly instead of waiting for the poll. Skip `nofile`
buftypes as Astro does.
Source: `_astrocore_autocmds.lua:101`.

Reviewed — overlap note: `BufEnter` is already in the `checktime` group
(`configs.lua:42`), so returning from a terminal to a file buffer *is*
already caught. The genuine remaining gap is `TermClose` and staying
in-place without a buffer switch; incremental value is smaller than the item
first implied. Low cost, so still worth it, but not urgent.

### 10. Highlight-on-yank

Not an AstroNvim-specific finding, but surfaced as a gap during the same
audit: one `TextYankPost` autocmd calling `vim.hl.on_yank()`. Given the
custom clipboard-split expr maps (`y` → system clipboard, `dd`/`x`/`c`
don't), visual confirmation of what got yanked is extra useful.

## Rejected (documented so we don't re-litigate)

- **`AstroFile`/`AstroGitFile` self-deleting lazy-load events**
  (`_astrocore_autocmds.lua:133`) — serves lazy.nvim event loading; this
  config loads eagerly via `vim.pack`, nothing to defer.
- **Pausable/deferred `vim.notify` queue** (`notify.lua`) — mini.notify is
  loaded before anything notifies here; no startup gap to bridge.
- **Per-tab buffer lists (`vim.t.bufs`)** — powers their tabline; this
  config deliberately has no bufferline (buffer picker instead).
- **Centralized `User AstroLargeBuf` large-file system** — the expensive
  part (treesitter) is already guarded here (>50k lines / >1.5MB in
  `plugins.lua`); only revisit if big files still lag from blink or indent
  guides.
- **blink icon provider chain with color swatches** (`blink.lua:9-71`) —
  depends on nvim-highlight-colors, not installed here.
- **guess-indent** — fixed 4-space expandtab is a deliberate choice here.

## Implementation notes

- **Autocmd home (decided).** This config has no single autocmds module —
  they're scattered across `configs.lua`, `linting.lua`, `filetree.lua`,
  `keymaps.lua`. Items 1, 2, 9, 10 (and 5 if it ever lands) are four+ new
  autocmds; put them in a new `lua/autocmds.lua` module with one augroup
  rather than scattering further. That means a matching GUIDE.md
  `Architecture` file-responsibilities entry + a `Load order` update for the
  new `require()` in `init.lua` (per nvim CLAUDE.md).
- Item 3 is a `vim.diagnostic.config` addition in `lsp.lua` (extend the
  existing `vim.diagnostic.config` block at `lsp.lua:266`, don't add a
  second call).
- Item 6 is two `opt.diffopt:append(...)` lines in `configs.lua` options.
- Per repo convention: GUIDE.md updates land in the same change as each
  feature; keymap-bearing items (4, 7) need `desc` on every map for the
  keybindings picker.
- Per-item verification (repo `/verify` convention): 1 → save a buffer under
  a non-existent nested dir, confirm it writes; 2 → reopen a file, cursor
  lands where you left it, but a fresh `git commit` opens on line 1; 3 →
  `]d` onto an error shows the message float with virtual text off; 6 → open
  a diff in diffview and confirm intra-line alignment; 10 → `yap` flashes the
  yanked region.
