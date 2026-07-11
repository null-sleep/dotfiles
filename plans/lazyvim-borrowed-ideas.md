# Ideas to borrow from LazyVim

**Status:** research / not started
**Date:** 2026-07-11

## Context

Investigated `/Users/dhruv/src/LazyVim` (LazyVim core v16, 2026-07) for ideas
worth porting into this config — same exercise as
`plans/astronvim-borrowed-polish.md` (AstroNvim), with a LunarVim pass
happening in parallel (separate plan when done). Every candidate below was
cross-checked against the live config so this lists only real gaps; items the
AstroNvim plan already covers (and the ones that landed from it: mkdir-on-save,
cursor restore, yank highlight, `diffopt` linematch/histogram, polite
`q`-close) are not repeated.

File references are into the LazyVim repo unless prefixed otherwise.

LazyVim's big architectural pieces — lazy.nvim itself, the `LazyFile` batched
load event, the LazyExtras opt-in system, the picker/cmp abstraction layer —
all exist to serve lazy.nvim's event-based loading and swappable defaults.
This config loads eagerly via `vim.pack` with fixed, deliberate picks
(Telescope, blink.cmp, nvim-tree, Neogit, mini.notify), so those are excluded
up front (see "Rejected").

## Suggested landing order

- **Batch A — editing power, biggest genuine gaps:** 1 (surround),
  2 (text objects — via the existing `plans/treesitter-textobjects.md`),
  3 (flash).
- **Batch B — one small PR of keymaps/options/autocmds:** 6, 7, 8.
- **Batch C — cheap plugin/module enables:** 4 (todo-comments),
  5 (snacks bigfile + words).
- **Already planned elsewhere:** grug-far — top pick in
  `plans/features-from-other-editors.md` and on `plans/TODO.md`; not
  re-planned here, but this audit independently reconfirms it (LazyVim binds
  it at `<leader>sr`; here `<leader>sr` is Telescope resume, so use
  `<leader>sR` or similar).

## Adopt (high value)

### 1. Surround plugin — the single biggest gap

Nothing in this config can add/change/delete surroundings. LazyVim ships
`nvim-mini/mini.surround` as an extra with a `gs`-prefixed keyset chosen
specifically to avoid clobbering `s`/`S` (which flash takes — see item 3):
`gsa` add (n/v), `gsd` delete, `gsr` replace, `gsf`/`gsF` find right/left,
`gsh` highlight.
Source: `lua/lazyvim/plugins/extras/coding/mini-surround.lua`.

Alternative: `kylechui/nvim-surround` (classic `ys`/`cs`/`ds` grammar). Pick
one; mini.surround's `gs` prefix composes better if flash lands on `s`.
Note: this config has nvim-autopairs but that only covers *inserting* pairs,
not changing/deleting them around existing text.

### 2. `a`/`i` text objects (function, class, argument)

`nvim-treesitter-textobjects` is already on the runtimepath here but
completely unwired (only used for sidekick's `{function}`/`{class}` context
vars). LazyVim gets `af/if/ac/ic` + `]f`/`[f` `]c`/`[c` `]a`/`[a` motions
from it, and layers `nvim-mini/mini.ai` on top for arguments, digits, next/
last variants (`vinq` = "inside next quotes") and which-key integration.

**This is already `plans/treesitter-textobjects.md` (status: not started).**
Land that plan; the LazyVim delta worth folding into it:

- LazyVim's mini.ai spec adds custom specs for buffer (`ag`/`ig`), digits
  (`d`), and treesitter-driven `o` (blocks/conditionals/loops) — see
  `lua/lazyvim/plugins/coding.lua` (mini.ai section) and
  `lua/lazyvim/util/mini.lua` (`ai_whichkey` — registers every text object
  in which-key so `va` pops a menu).
- Main-branch textobjects needs explicit keymap wiring (no module system);
  LazyVim's pattern is in `lua/lazyvim/plugins/treesitter.lua` (buffer-local
  `select()`/`move()` calls per FileType).
- Pairs with, not replaces, the existing `<M-o>`/`<M-i>` structural select.

### 3. `folke/flash.nvim` — labeled jump motion

No long-range motion story in this config today (jumplist + mouse buttons
aside). Flash gives: `s` labeled jump, `S` treesitter-node select, `r`/`R`
remote/treesitter-search in operator-pending mode, `<c-s>` toggle during `/`
search (labels appear on plain search matches), `<c-space>` incremental
treesitter selection.
Source: `lua/lazyvim/plugins/editor.lua` (flash spec).

Conflict check: `s` in normal mode is currently core "substitute character" —
losing it is the standard flash trade-off. `S` conflicts with nothing here.
Flash's treesitter select (`S`) overlaps the custom `<M-o>`/`<M-i>`
structural select; keep both initially, judge later. Also integrates with
Telescope (LazyVim wires `<a-s>`/`s` inside the snacks picker; a Telescope
equivalent exists via `flash.jump` in picker mappings).

### 4. `folke/todo-comments.nvim`

Highlights TODO/FIXME/HACK/PERF/NOTE, gives `]t`/`[t` navigation and a
Telescope picker (`:TodoTelescope`). Zero conflicts (`]t`/`[t` unused here;
`<leader>st` is the themes picker, so bind the picker at e.g. `<leader>sT`
or under diagnostics). Cheap win.
Source: `lua/lazyvim/plugins/editor.lua` (todo-comments spec).

### 5. Enable snacks `bigfile` + `words` (already installed)

snacks.nvim is already present with only `scratch` + `indent` on
(`plugins.lua` deliberately disables the rest). Two more modules are nearly
free and don't overlap existing custom code:

- **`bigfile`** — subsumes/extends the manual >50k-line/1.5MB treesitter
  skip; also disables other expensive per-buffer features on huge files.
  If enabled, decide whether the manual guard in the treesitter FileType
  autocmd stays as belt-and-braces or goes.
- **`words`** — `]]`/`[[` (and `<a-n>`/`<a-p>`) jump between LSP references
  of the symbol under cursor. Document highlight is already wired on
  LspAttach here, so the visual half exists; this adds navigation.
  Conflict check: `]]`/`[[` are core section motions — rarely used in code
  with this config's languages, but confirm before binding.

Source: `lua/lazyvim/plugins/util.lua` (bigfile/quickfile),
`lua/lazyvim/plugins/ui.lua` (words), keymaps in
`lua/lazyvim/plugins/lsp/keymaps.lua`.

## Keymaps worth stealing (Batch B)

Source for all: `lua/lazyvim/config/keymaps.lua`.

### 6a. `j`/`k` → `gj`/`gk` when no count

`{ expr = true }`: `v:count == 0 ? 'gj' : 'j'` (n + x modes, also for
`<Down>`/`<Up>`). This config runs with `wrap` **on**, so display-line
movement matters more here than in LazyVim (which sets `wrap=false`).

### 6b. Undo break-points in insert mode

`,` `.` `;` each mapped to `<char><c-g>u` — one `u` no longer nukes an
entire insert session. Three one-liners.

### 6c. `n`/`N` always search forward/backward

Regardless of whether the search was `/` or `?`; append `zv` to open folds
at the match. Four expr maps (n/x/o modes).

### 6d. Severity-filtered diagnostic jumps

`]e`/`[e` errors-only, `]w`/`[w` warnings-only, alongside the existing
`]d`/`[d`. Small `vim.diagnostic.jump({ severity = ... })` wrappers.
Especially useful here since virtual text is off by default — pairs with the
AstroNvim plan's `on_jump` auto-float (item 3 there).

### 6e. `<A-j>`/`<A-k>` move line/selection — CONFLICT, decide first

LazyVim moves lines/selections with `<A-j>`/`<A-k>` (with proper `v:count`
and reindent). **Here `<A-h/j/k/l>` is split-resize.** If wanted, move
resize to `<C-Up/Down/Left/Right>` (LazyVim's resize keys, free here) and
take Alt for line-moving. Skip if resize muscle memory wins.

## Options (Batch B)

Source: `lua/lazyvim/config/options.lua`. Only genuine deltas listed:

- `splitkeep = "screen"` — no text jump when splits open/close; noticeable
  with the bottom terminal panel and sidebars.
- `virtualedit = "block"` — cursor past line ends in visual-block mode.
- `jumpoptions = "view"` — jumplist motions restore scroll position, not
  just cursor position. Complements the mouse-button jumplist maps.
- `shiftround` — `>`/`<` snap to multiples of shiftwidth.
- `grepprg = "rg --vimgrep"` + `grepformat = "%f:%l:%c:%m"` — makes `:grep`
  usable as a Telescope fallback.
- `smoothscroll` — `<C-e>`/`<C-y>` scroll by screen line with wrap on.

Checked and already equivalent here (do not re-land): undofile/undolevels,
ignorecase+smartcase, splitright/below, scrolloff/sidescrolloff, custom
fillchars, timeoutlen (via which-key delay), inccommand (nvim ≥0.11 default).

## Autocmds (Batch B)

Source: `lua/lazyvim/config/autocmds.lua`. Home: `lua/autocmds.lua` (the
module the AstroNvim plan designates).

- **Auto-equalize splits on `VimResized`** — `wincmd =` in each tab,
  preserving the current tab. Pairs well with heavy terminal/panel use.
- **`wrap` + `spell` for prose filetypes** — gitcommit/markdown/text. Spell
  is globally off here (toggle `<leader>tz`); this scopes it on where it's
  useful without flipping the global.
- **Extend `q`-to-close filetype coverage** — the landed AstroNvim item
  covers help/quickfix buftypes; LazyVim also catches `checkhealth`,
  `lspinfo`, `neotest-output`/`-summary`/`-output-panel`, `dap-float`, etc.
  Neotest panels currently need `:q` here. Fold the extra filetypes into the
  existing handler (keep its don't-clobber-existing-`q` guard).

## Rejected (documented so we don't re-litigate)

- **lazy.nvim / `LazyFile` event / LazyExtras / `opts_extend` merging** —
  all serve lazy.nvim's deferred loading and distro-style opt-in; this
  config is eager `vim.pack` with fixed picks. Nothing to defer.
- **snacks picker/explorer/dashboard/notifier/lazygit, noice, bufferline,
  neo-tree** — explicit counter-choices already made (Telescope + custom
  pickers, nvim-tree, mini.notify, lualine-only, Neogit). Churn, not
  improvement.
- **Root-dir detection (`lua/lazyvim/util/root.lua`)** — LazyVim's most
  interesting infrastructure (LSP-root-aware pickers, root/cwd toggle,
  per-buffer cache), but deeply woven into their picker abstraction. Big
  lift, moderate payoff unless monorepo work (cwd ≠ project root) becomes
  common. Revisit on demand, don't port speculatively.
- **Copilot as completion source (`ai_cmp`)** — the Tab-priority
  ghost-text arrangement here (blink menu → Copilot ghost text → literal
  Tab) is arguably better; keep it.
- **`<leader>u*` Snacks.toggle suite** — a `<leader>t*` toggle set already
  exists here with equivalent coverage (diagnostics, inlay hints, format,
  lint, spell, relative numbers, indent guides, AI, blame, hover).
- **persistence.nvim, conform, nvim-lint, which-key, lazydev, gitsigns,
  blink.cmp, mini.icons, treesitter-context** — already present.
- **mini.pairs** — nvim-autopairs already covers pair *insertion*
  (`check_ts=true`); switching engines buys nothing. The gap is surround
  (item 1), a different capability.
- **trouble.nvim** — loclist + Telescope + satellite marks cover the
  diagnostics-list workflow here; `plans/quickfix-improvements.md` is the
  existing plan for list ergonomics. Reconsider only if that plan stalls.
- **dial.nvim / yanky / inc-rename / harpoon** — nice-to-haves; harpoon
  already has its own plan (`plans/harpoon2.md`), inc-rename is redundant
  with core `grn` + `inccommand`, the others don't earn a slot yet.

## Implementation notes

- **Per repo convention:** GUIDE.md updates land in the same change as each
  feature (see `nvim/.config/nvim/CLAUDE.md`); every new keymap needs a
  `desc` for the keybindings picker (`<leader>sk`).
- New plugins go through `vim.pack` in `plugins.lua` + the pin lockfile
  flow, one module per feature where config is nontrivial (flash and
  surround are small enough to live in `plugins.lua`; textobjects wiring
  per its own plan).
- Keymap collisions to re-verify at implementation time (the
  `plans/keymap-tracker.md` inventory is the source of truth): `s`/`S`
  (flash), `gs` prefix (surround), `]]`/`[[` (snacks words), `]t`/`[t`
  (todo-comments), `<A-j>/<A-k>` (line-move vs resize).
- Batch B autocmds → `lua/autocmds.lua` per the AstroNvim plan's decided
  home; options → `configs.lua`.
- Verification per item (`/verify` convention): surround → `gsa"` around a
  word round-trips with `gsd"`; flash → `s` + label lands across the
  window; 6a → `j` on a wrapped line moves one display line; 6d → `]e`
  skips warnings; VimResized → resize the terminal window and splits
  re-equalize; bigfile → open a >1.5MB file, treesitter stays off.
