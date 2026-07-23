# plans/ — index

Design and feature-planning docs for this dotfiles repo (mostly the Neovim
config). This index is orientation only — **the code is the source of truth**;
a plan may be stale or superseded by what actually shipped. Plans are pruned
as they land (see git history for removed ones).

## TODO — things to act on

A running checklist of what I actually want to do next across these plans
(distinct from the index below, which just catalogs everything). Check items
off or delete them as they land; add new ones freely.

- [ ] **Re-enable Ghostty `copy-on-select` once multi-line copies work** —
  disabled 2026-07-20 because Ghostty writes hard line breaks to the macOS
  pasteboard as NUL instead of newline, so every multi-line selection pastes
  as a single line. When re-enabling, the value must be `clipboard`, not
  `true`. Details and the byte-level evidence in [Ghostty copy-on-select
  mangles multi-line copies](#ghostty-copy-on-select-mangles-multi-line-copies)
  below; still unverified whether it's Ghostty-wide or specific to the Claude
  Code pane.
- [ ] **Saved picker searches** — save a search when you run it so you can
  re-run it later. A feature to add to the picker.
- [ ] **Fuzzy-filter the grep-selection picker (`<leader>ss`) on the whole
  match, not just its first line** — a word on a match's 2nd/3rd line can't
  currently narrow the list (2026-07-21). Trade-off: noisier matching. Knob
  is the `text` field in `pickers/grepselection.lua`'s `parse()`. Option to
  try, not a decision.
- [ ] **Review and adopt the plans/ hygiene conventions** — status-header
  template, prune-on-land rule, anchor-citation convention, `plans-audit`
  skill sketch. Proposal saved in [plans-hygiene.md](plans-hygiene.md)
  (2026-07-18); nothing in force until adopted.
- [ ] **Try smart path shortening in the symbol picker's path column** — the
  column now truncates from the left (`…s/pickers/symbols.lua:42`, 2026-07-20)
  so the filename always survives, but a component-wise squeeze
  (`n/./n/l/pickers/symbols.lua`) would fit the *whole* path in the same 38
  cells. Option to try, not a decision; `PATH_WIDTH` in
  `nvim/.config/nvim/lua/pickers/symbols.lua` is the other knob.
- [ ] **Try filename-first path display in snacks pickers** — list currently
  left-truncates (40-cell default, 60 for files/`<leader>sf`);
  `formatters.file.filename_first = true` would show `order.go packages/…/`
  instead. Option to try; see
  [GUIDE.md → Path display](../nvim/.config/nvim/GUIDE.md#picker-path-display).
- [ ] **Tune picker path display `PATH_MAX` / `PATH_MAX_BY_SOURCE`** — default
  40 cells, `files = 60` for `<leader>sf` in `picker.lua` (2026-07-23); raise
  or lower per source if a list feels too tight or too long. See
  [GUIDE.md → Path display](../nvim/.config/nvim/GUIDE.md#picker-path-display).
- [ ] **Try on-demand full-path notify in pickers** — flash/notify the full
  path for the current row without changing list/border chrome (`<C-y>`
  already yanks it). Option to try; see
  [GUIDE.md → Path display](../nvim/.config/nvim/GUIDE.md#picker-path-display).
- [ ] **Try an LSP-only custom path format** — per-source `format` on
  `lsp_references` / `lsp_definitions` only (e.g. two-line path + snippet),
  leaving files/grep alone. Option to try; see
  [GUIDE.md → Path display](../nvim/.config/nvim/GUIDE.md#picker-path-display).
- [ ] **Review snacks' default picker keymaps for inspiration** — hoisted from
  [telescope-vs-snacks-picker.md](telescope-vs-snacks-picker.md)'s
  post-migration TODO (#2) when that doc was shrunk (2026-07-18).
- [ ] **Mine linkarzu's snacks-picker post for setup ideas** — hoisted from the
  same post-migration TODO (#8).
- [ ] **Finish large-file protection's deferred per-subsystem guards**
  (gitsigns / satellite / auto-save + `:LargeFileRestore`) — see
  [large-file-protection.md](large-file-protection.md) → TODO. The sidekick-NES
  guard that was also on this list is moot: NES was removed 2026-07-20.
- [ ] **Finish verifying Go debug/test** — two interactive checks never closed.
  (1) The `-test.run` **state-leak**: `<leader>nd` on `TestDescribe`, terminate,
  then `<leader>nd` on `TestMax` — the second session must stop in `TestMax`, not
  back in `TestDescribe`. The fix (a `dap_manual_config` *function*, not a table)
  is proven in a simulated harness but never on a real session. (2) The targets
  picker's **abort/kill**: `<leader>dR` on a big module, `<Esc>` mid-load, then
  `pgrep -f "go list"` — nothing should linger. See
  [go-run-debug-test.md](go-run-debug-test.md) → Verification.
- [ ] **Unify yank.lua's `yc`/`yC` ref format with sidekick's `#L`** — `yc`/`yC`
  in `nvim/.config/nvim/lua/yank.lua` emit `@path:42-58` (colon, no `L`), while
  sidekick / `ai_context.lua` emit `@path#L42-58`. Both are readable and Cursor
  parses either (noted 2026-07-21 while designing
  [sidekick-cursor-support.md](sidekick-cursor-support.md)), so this is a
  pre-existing repo inconsistency, unrelated to the Cursor work — worth a
  separate pass sometime to prefer one shape (`#L`) everywhere, not part of that
  change.
- [ ] **Collapse the sidekick detach sweep's 9 `State.get` calls into 1** — all
  9 filter the same snapshot, so the sweep re-scans the world 9× for nothing.
  Harmless today (~0.05ms/call post-`88cb662`), but it's the multiplier that
  turned a 65ms backend scan into a ~590ms freeze — do it before enabling mux.
  See "Performance" in
  [sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md).
- [ ] **Evaluate [avante.nvim](https://github.com/yetone/avante.nvim)** — a
  Cursor-style AI plugin (inline suggest + one-click apply, "Zen Mode" agent,
  multi-provider, project `avante.md` instructions). Overlaps sidekick.nvim
  (CLI agents), so the question is whether it *replaces* it or just adds a
  second AI surface — and since Copilot's removal (2026-07-20) it would also be
  the only inline-suggestion source, which changes the calculus. Note the costs:
  needs a build step (Rust/Cargo or a prebuilt binary fetch) and its own API
  keys, plus plenary + nui.
- [ ] **Wire treesitter text objects and navigation** — `af`/`if`, `ac`/`ic`,
  `aa`/`ia`, `al`/`il` select, plus `]f`/`[f`/`]F`/`[F`/`]k`/`[k` jump. Plugin
  already installed. See [treesitter-textobjects.md](treesitter-textobjects.md).
  Related: the [mini.ai](https://github.com/nvim-mini/mini.ai) eval below —
  that plan defers the `o`/`d`/next-last text objects to it.
- [ ] **Evaluate [mini.ai](https://github.com/nvim-mini/mini.ai)** — fits the
  existing mini.* family (mini.icons/notify/bufremove are in use; mini.surround
  itself is still only queued in [nvim-backlog.md](nvim-backlog.md), not
  installed). Would unblock the
  `o`/`d`/next-last text objects that
  [treesitter-textobjects.md](treesitter-textobjects.md) defers on needing it
  (its "Shortlist of shortcuts to consider" table).
- [ ] **Evaluate [claudecode.nvim](https://github.com/coder/claudecode.nvim)** —
  implements the Claude Code IDE protocol (what `/ide` and the VS Code
  extension speak). Why: it adds what sidekick's terminal embedding can't —
  Claude's proposed edits arrive as **native nvim diffs** to accept/reject
  in-editor, and selection/open-file context is shared automatically instead
  of via explicit `<leader>at`/`<leader>ap` sends. Would complement, not
  replace, the sidekick setup in `ai.lua`; evaluate coexistence first.
- [ ] **Evaluate [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim)** —
  already the top pick for multibuffer-style search & replace in
  [nvim-backlog.md](nvim-backlog.md) (Zed gap analysis); not yet installed.
- [ ] **Evaluate [flash.nvim](https://github.com/folke/flash.nvim)** — labeled
  jump motion, already scoped in [nvim-backlog.md](nvim-backlog.md) ("Editing
  power & motions"): `s` labeled jump, `S` treesitter-node select, `r`/`R`
  remote in operator-pending. Known conflicts noted there (`s` = core
  substitute, `S` overlaps the hand-built structural select). Config example:
  <https://tduyng.com/blog/neovim-enhance-editing-experiences/> (2026-07-21);
  same post's other picks: grug-far already shipped, noice.nvim rejected,
  yanky.nvim in nvim-backlog.md's Smaller wishlist as a maybe.
- [ ] **Adapt neotest to the workflow** — see
  [neotest-workflow.md](neotest-workflow.md). Three parts: a fuzzy test
  picker (`<leader>ns`'s tree lists every test but isn't *searchable*), the
  panel placement (neotest is entirely unconfigured, so the summary opens on
  the **right edge — the same one sidekick's CLI owns** — and is registered
  in none of the three panel registries), and a run-the-whole-suite key
  (`<leader>nf` stops at file scope). Main open decision in the plan: move
  the summary to the left edge and join the `<leader>e`/`<leader>o` swap
  group, or generalize the coordinator to per-edge groups.
- [ ] **Build the Python debug/test stack** — spec'd and thrice-reviewed in
  [python-debug-test.md](python-debug-test.md). Two follow-on decisions it
  deliberately leaves open: (1) **what is a Python "run target"?** — the
  `pickers/pytargets.lua` analogue of `go list` (`__main__` scripts?
  `[project.scripts]`? `python -m pkg`?), which is what finally binds
  `<leader>dR` for Python; (2) whether `dap-python.debug_selection()` (debug a
  visual selection — no neotest equivalent) deserves a key.

---

<a id="ghostty-copy-on-select-mangles-multi-line-copies"></a>

## Ghostty copy-on-select mangles multi-line copies

Findings from the 2026-07-20 investigation, kept here rather than as its own
plan — it's a one-setting problem with a one-line workaround.

**Symptom.** Selecting multi-line text in Ghostty and pasting it into nvim
yields a single line, with the line breaks rendered as `^@`.

**Cause.** Ghostty writes hard line breaks to the macOS pasteboard as NUL
(`0x00`) rather than newline (`0x0A`). Confirmed with `od -c` straight off
the pasteboard, no editor in the path:

```
$ pbpaste | od -c | head -2
0000000    S   a   m   p   l   e       H   e   a   d   i   n   g  \0  \0
0000020    T   h   i   s       i   s       a       b   o   l   d       s
```

Everything downstream is behaving correctly: `systemlist('pbpaste')` returns
one item because there is nothing to split on, and nvim renders the NULs as
`^@`. Soft-wrapped continuation lines are joined with a space correctly — only
hard breaks are affected.

**Ruled out.** nvim's clipboard provider (stock `pbcopy`/`pbpaste`, health
check clean), `g:clipboard` (nil, and no plugin sets it), this repo's
`setreg` calls, and any multiplexer (none in use). A headless run of the same
config pastes multi-line text correctly.

**The `true` vs `clipboard` trap.** `copy-on-select = true` prefers the
*selection* clipboard, which on macOS `pbpaste` and other apps cannot read —
so it silently copies nothing to the system clipboard. It does not avoid the
NUL bug either. If the setting is ever re-enabled, it must be `clipboard`.

**Current state.** `copy-on-select = false` in
`ghostty/.config/ghostty/config`. ⌘C is unaffected and still copies
multi-line text correctly.

**Open.** Whether this affects all Ghostty selections on macOS or only the
Claude Code pane — the minimal shell reproduction (select three lines of
`printf` output, then `pbpaste | od -c`) was never run to completion. Worth
settling before filing upstream, since a terminal mangling every multi-line
copy is a big enough bug that it would likely already be known. Ghostty
1.3.1, installed 2026-03-13; the setting itself landed 2026-07-17 in
`7d5912a`, which is why this appeared to be a recent regression.

**Workaround if upstream is slow.** A custom `g:clipboard` whose paste
function splits on `\0` as well as `\n` makes nvim immune regardless of
fault, and would let `copy-on-select` be re-enabled for nvim's benefit even
while the bug is live. Goes in `nvim/.config/nvim/lua/configs.lua`, next to
the existing clipboard comment (~line 15):

```lua
-- Ghostty writes hard line breaks to the macOS pasteboard as NUL, so the
-- stock provider sees one line. Split on both NUL and newline.
local function paste()
  local f = io.popen('pbpaste', 'r')
  if not f then return {} end
  local raw = f:read('*a') or ''
  f:close()
  return vim.split(raw, '[\n%z]')
end

vim.g.clipboard = {
  name = 'pbcopy-nul-tolerant',
  copy = { ['+'] = 'pbcopy', ['*'] = 'pbcopy' },
  paste = { ['+'] = paste, ['*'] = paste },
}
```

`io.popen` is load-bearing: `vim.fn.system()` converts NUL to SOH (`\1`) on
the way back, so a `%z` split against it silently matches nothing. Verified
2026-07-20 against a NUL-separated pasteboard (splits correctly), a normal
newline pasteboard (unchanged), and copying (still writes newlines).

Cost of adopting it: this config currently sets no `g:clipboard` at all, so
it trades a stock, zero-maintenance provider for a hand-rolled one that is
macOS-only and papers over someone else's bug. Prefer the upstream fix if it
arrives.

---

Grouped by state, not priority.

## Active — outstanding work with momentum

- [sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) — a
  cmux-style event pipeline so nvim knows which Claude session needs input / is
  done / is idle (pipeline first, UI later).
- [sidekick-windowless-prewarm.md](sidekick-windowless-prewarm.md) — real
  windowless CLI-start API to replace the hidden-float pre-warm hack; interim
  hack shipped, Phase C (upstream PR) + Phase D (simplify `ai.lua`) still open.
- [sidekick-cursor-support.md](sidekick-cursor-support.md) — add Cursor
  (`cursor-agent`) as a second agent beside Claude in the flat session pool
  (`<leader>an` agent picker is the single creation door, agent-aware
  naming/fork, pool-wide switch/cycle). UX locked 2026-07-21 (rev. 2026-07-22);
  implementation not started.
- [rustrover-nvim-parity.md](rustrover-nvim-parity.md) — how much of RustRover's
  edge (SSR, batch clippy fixes, refactor previews, debugger visuals, DB/HTTP/
  coverage tooling) can be closed in the existing rustaceanvim setup.
  SSR (`<leader>cs`) and batch clippy-fix (`<leader>cF`) shipped 2026-07-17;
  the rest (refactor preview, debugger visuals, bundled tooling, and the
  genuinely protocol-level gaps — Cargo.toml-aware rename,
  move-with-import-fixup, data breakpoints, memory view) still open.

## Ready to build — self-contained specs, not started

- [python-debug-test.md](python-debug-test.md) — Python debugging (nvim-dap-python
  + debugpy) and testing (neotest-python), the Rust/Go stacks' missing sibling —
  plus the venv convention neither of them needed (`uv` creates it,
  `<project>/.venv` is the contract, one resolver feeds pyright + debugpy +
  neotest). Three times adversarially reviewed; the targets picker is deferred.
- [neotest-workflow.md](neotest-workflow.md) — use neotest more by removing the
  friction: a fuzzy test picker, panel placement (it's unconfigured today, so
  the summary contests the right edge with sidekick), and a suite-run key.
- [harpoon2.md](harpoon2.md) — persistent, ordered per-project file bookmarks
  (`<leader>1`–`<leader>5`).
- [treesitter-textobjects.md](treesitter-textobjects.md) — semantic
  select/move/swap text objects (`af`/`if`/`ac`/…), plus a LazyVim mini.ai delta.
- [quickfix-improvements.md](quickfix-improvements.md) — quicker.nvim / nvim-bqf
  for a real, prunable quickfix panel.
- [neovide-path-env.md](neovide-path-env.md) — a stow-managed `~/.zshenv` so
  GUI-launched Neovide inherits the terminal PATH (LSPs/formatters).
- [ghostty-followups.md](ghostty-followups.md) — successor to the now-deleted
  `ghostty.md` migration plan. Two leftover open items (status bar,
  `ApplePressAndHoldEnabled`), plus a
  researched list of Ghostty 1.3 features (command palette, quick terminal,
  split zoom, `window-save-state`, shaders, …) not yet used in the config.

## Backlog

- [nvim-backlog.md](nvim-backlog.md) — the single Neovim enhancement backlog
  (consolidated from the Zed/VS Code/JetBrains gap analyses + the LazyVim /
  LunarVim comparison passes + the old TODO wishlist; 2026-07-18 it also
  absorbed the edgy.nvim unified-edgebar research, the sidekick split↔float
  toggle sketch, and keymap-tracker's Track C2/C3 promotion candidates).
- [dap-breakpoint-persistence.md](dap-breakpoint-persistence.md) — research:
  persist nvim-dap breakpoints across restarts (plugin pair vs an ~80-line
  DIY, git-root-keyed); read harpoon2's storage model before deciding.
- [git-worktree-nvim-plugin.md](git-worktree-nvim-plugin.md) — research:
  worktree-switching plugins vs plain `cd` + fresh nvim; narrowed to
  do-nothing / Juksuu / afonsofrancof. Reach for it if worktree switching
  gets frequent.
- [plans-hygiene.md](plans-hygiene.md) — proposal (not adopted): conventions
  for this directory itself — status headers, prune-on-land, anchor citations,
  a `plans-audit` skill — distilled from the 2026-07-18 consolidation. See the
  TODO entry above.

## As-needed toolkit — known-good options, not scheduled work

Not active, not backlogged, not parked-with-a-trigger — these are researched,
ready-to-install answers to a need that hasn't shown up yet. No revival
condition to watch for; just reach for one when the matching need is
actually real. Detail for each lives in
[rustrover-nvim-parity.md](rustrover-nvim-parity.md) → "Bundled tooling".

- **HTTP client** — `kulala.nvim`. Write requests in a plain `.http` file,
  run one with a keybinding, see status/headers/body in a response pane —
  no separate Postman/Insomnia app. Targets 100% compatibility with
  JetBrains' own `.http` format, so the same request files work in RustRover
  too. Reach for this when there's an actual API to poke at during
  development.
- **DB client** — `vim-dadbod` + `vim-dadbod-ui`. Connection tree, saved
  queries, execute-SQL-in-a-buffer. Reach for this when a project's DB work
  gets frequent enough that a terminal `psql`/`sqlite3` session stops being
  enough.

## Parked / reference — deliberate holds and design records

- [nvim-startup-performance.md](nvim-startup-performance.md) — Phase 1 landed and
  verified; Phase 2 parked for good with a documented revival trigger.
- [keymap-tracker.md](keymap-tracker.md) — keymap-usage-tracker spec, parked
  (shrunk 2026-07-18 to the buildable two-primitive core + condensed findings;
  the internals deep-dives live in git history, and Track C2/C3's promotion
  candidates moved to nvim-backlog.md → Editing power & motions).
- [telescope-vs-snacks-picker.md](telescope-vs-snacks-picker.md) — **shipped**
  (telescope removed, snacks.picker everywhere, 2026-07; shrunk to its
  decision-record core 2026-07-18). Keeps §6 (explorer verdict + reopen
  conditions), §7 (scroll-perf kernels + the open intermittent-hang residual),
  §8 (live-mode audit), and two open design TODOs (#9 corpus-stack `<c-g>`,
  #10 re-grep surviving files).
- [large-file-protection.md](large-file-protection.md) — **shipped**
  (snacks.bigfile, 2026-07-13); kept for the filetype-rename mechanism,
  threshold rationale, and the still-open per-subsystem guards (see the TODO
  list above).
- [sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md) —
  **shipped**; kept as the design reference the event-pipeline plan cites. Also
  carries the **sidekick performance runbook** — start there if nvim hangs on
  switching or tearing down a CLI session.
- [go-run-debug-test.md](go-run-debug-test.md) — **shipped** (2026-07): Go
  debugging (nvim-dap-go + delve) and testing (neotest-golang + gotestsum). Kept
  as the decision record — it's where the `dap_mode = 'manual'` trap and the
  `outputMode = 'remote'` requirement are explained, and it carries the one
  outstanding verification (the `-test.run` state-leak check).
- [go-targets-picker.md](go-targets-picker.md) — **shipped** (2026-07):
  `<leader>dR`/`<leader>cR` debug/run any `main` package in the module via an
  async `go list`. Kept for the `go list -e` exit-code trap and delve's
  `program`-must-be-a-folder contract.
