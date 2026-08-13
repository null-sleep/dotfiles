# plans/ — index

Design and feature-planning docs for this dotfiles repo (mostly the Neovim
config). This index is orientation only — **the code is the source of truth**;
a plan may be stale or superseded by what actually shipped. Plans are pruned
as they land (see git history for removed ones).

## TODO — things to act on

A running checklist of what I actually want to do next across these plans
(distinct from the index below, which just catalogs everything). Check items
off or delete them as they land; add new ones freely.

- [ ] **Reconsider `skipDangerousModePermissionPrompt` and
  `skipAutoPermissionPrompt`** — both flipped to `false` in the tracked
  `claude/.claude/settings.json` (upstream and the work fork) on 2026-08-12;
  `claude/tests/settings-invariants.sh` asserts them false. If the re-enabled
  confirmations prove too much friction day-to-day, revisit deliberately and
  update the invariants test together with the decision.
- [ ] **Evaluate omp local memory before enabling autolearn** —
  `memory.backend: local` is now repo-pinned through
  `omp/setup-settings.sh`. Use the automatic summary pipeline for several
  real sessions, inspect `/memory view` and `memory://root/MEMORY.md`, and
  record omissions, stale guidance, startup/model cost, and whether recalled
  context changes decisions correctly. Only then decide whether explicit
  `learn` capture earns its extra prompting surface; if it does, enable
  `autolearn.enabled` with `autoContinue: false` first and audit
  `memory://root/learned.md` before considering automatic capture turns.
  Backend comparison and data-residency questions remain in
  [omp-integration.md](omp-integration.md) → TODO.
- [ ] **Revisit tracking omp settings in the repo** — `omp config set`
  rewrites `~/.omp/agent/config.yml` via atomic rename (verified 2026-08-12:
  inode changes), so stowing it would break the same way pi's `settings.json`
  would; for now `omp/setup-settings.sh`'s forced block is the repo-owned
  settings surface. If more settings need tracking, evaluate a stowed
  read-only `--config` overlay (omp never writes overlays) vs its costs —
  wrapping every launch path and shadowing `/settings` edits. Details in
  [omp-integration.md](omp-integration.md) → TODO.
- [x] **`sync-upstream`: make `finish` verify before advancing the marker** —
  done 2026-08-12 in the private downstream fork (where the skill lives).
  `finish` was advancing `UPSTREAM_HEAD` unconditionally, so a failed
  cherry-pick chained into it silently marked the pending commits synced —
  they'd never be offered again. It now lists any pending commit with no
  evidence it landed and refuses, with `--force` for deliberate skips.
  Evidence is the `-x` provenance trailer (now added to the picks, and the
  only durable link back since the two histories share no commits) or a
  patch-id match, which alone can't survive a hand resolution against the
  fork's divergent files. Both paths are covered by fixture tests.
- [ ] **Agent view — all phases + UX follow-ups + review fixes shipped
  2026-08-10; interactive verification and branch merge outstanding** —
  cmux-style dashboard: [sidekick-agent-view.md](sidekick-agent-view.md),
  with operational internals (state machine, invariants, test recipes)
  in [sidekick-agent-view-internals.md](sidekick-agent-view-internals.md).
  On the `agent-view` branch: the view + rings + Phase 3 emitters
  (opencode/pi/cursor), then the UX-critique follow-ups (ack repair with
  defer-not-drop + `<M-u>` dismiss, leading glyph column,
  `! <label> +N` identity badge, urgent-only desktop notification via
  terminal-notifier), a three-reviewer adversarial pass (11 defects, all
  fixed), and a committed regression suite
  (`nvim/.config/nvim/tests/agentview/run.sh`). Still to do: the plan's
  interactive checklist (items 1–17) in a real UI session, then **merge
  the branch to main**; after that, the plan's "TRY THIS NEXT":
  click-to-focus notifications, and follow-up 4 (OSC 9/777 via
  TermRequest — deserves its own plan).
- [ ] **Verify the sidekick session labels + the 4-agent pool** — shipped
  2026-08-07 (display labels on `<leader>ar`/`<M-r>`/`<C-r>`; `opencode` and
  `pi` added to `AGENTS`). Everything testable headlessly passed — namespace
  collisions both directions, label GC, auto-name skipping label-occupied
  numbers, the four presets resolving to the right binaries. What's left needs
  a real UI, in one `env -u NVIM nvim` session:
  1. **`<C-r>` in the `<leader>al` picker.** It closes, prompts, then reopens
     (`vim.ui.input` is async and snacks owns the picker's own input window).
     Confirm the reopen isn't jarring; if a nested input turns out fine, the
     hook can switch to an in-place `picker:find()`.
  2. **`<M-r>` from terminal mode.** No precedent in this config for prompting
     out of a terminal buffer, and sidekick's own WinEnter/TermEnter autocmds
     call `startinsert`/`stopinsert` — check the input takes keystrokes and
     returns focus in the right mode.
  3. **`u` in an opencode and a pi panel.** Both should undo the last input
     edit. 0x1F is right per vendor docs + pi-tui's decoder, but neither was
     pressed for real. If opencode misbehaves, do **not** try Ctrl+Z — that's
     its `terminal_suspend` (only its Windows build reuses `ctrl+z` for undo).
  4. ~~**Context refs on the new agents.**~~ *Closed 2026-08-07 — no change
     needed, nothing to test.* `<leader>at`/`af`/`ac` send `ai_context.lua`'s
     `@file#L<n>` globally, and the worry was that opencode/pi would choke on
     the `#L` suffix. They can't: **neither resolves a pasted `@` ref into an
     attachment at all.** pi calls `processFileArguments` only on command-line
     `@file` args (`main.js:141`) — its TUI `@` is an autocomplete trigger with
     no post-submit text scan. opencode is the same by its own issue tracker
     (#2129): a literal `@path:10:20` doesn't pre-create an attachment, "the
     agent will usually naturally make the tool call to read the file". So on
     those two the ref is text the model acts on, and the shape only has to be
     legible — which `#L` is, while also being the machine-parsed form on
     claude and cursor. Per-agent overrides would buy nothing.
- [ ] **Verify the opencode + pi themes by eye** — both were wired into the
  `theme` switcher on 2026-08-07 but neither could be confirmed from an agent
  session: opencode's appearance detection needs a real terminal to answer its
  OSC 11 background query (a captured pty has nothing to reply), and pi won't
  start in a pty *and* needs `OPENROUTER_API_KEY` set. Three checks, in a real
  Ghostty window:
  1. **opencode follows the terminal.** `theme dark`, launch `opencode`, confirm
     it comes up dark; `theme light`, launch a *new* one, confirm light. Already-
     open sessions are expected NOT to change — it reads the background once at
     startup. If it doesn't follow, the `system` theme isn't picking up
     Ghostty's background; try `catppuccin` (true-color, adaptive, but Mocha
     instead of Dracula on the dark side).
  2. **pi recolors live.** With `pi` open, run `theme toggle` in another pane —
     the running session should repaint. This is the one behavior taken purely
     from pi's docs ("pi reloads the active custom theme file automatically");
     if it doesn't fire, the fallback is restarting pi, and the palettes are
     still correct. Treat the doc claim as unproven — opencode's docs promised
     custom-theme support its binary doesn't implement.
  3. **The ported palettes look right.** `pi/.pi/agent/themes/{catppuccin-latte,
     dracula}.json` were validated against pi's schema (all 51 required tokens,
     no unknown keys, every `vars` reference resolves) but never rendered. Check
     the syntax-highlighting and diff colors in particular, since those were
     mapped by hand rather than copied from an existing pi theme.
- [ ] **Does Ghostty repaint on a scripted appearance change?** — open question
  from 2026-08-07. After `theme light`, macOS reported light through both
  `defaults read -g AppleInterfaceStyle` (absent) and System Events (`dark mode:
  false`), and all three theme state files were Latte, but the Ghostty window
  was still rendering dark. Ghostty is supposed to resolve `theme = light:…,dark:…`
  (`ghostty/.config/ghostty/config:12`) against the system appearance on its own,
  which is exactly why the `theme` script doesn't touch it. Unresolved whether
  it's a stale-notification bug in Ghostty 1.3.1, something specific to
  `osascript`-driven changes, or just a screenshot taken mid-flip. Next time it
  happens: press **Cmd+Shift+,** (reload config) and see if it repaints. If it
  does, the script may need to nudge Ghostty rather than assuming the native
  follow works — which would undo the "Ghostty needs no script involvement"
  premise the [Unified theme switching](../README.md#unified-theme-switching)
  section is built on, and applies equally to opencode, which rides the same
  terminal palette.
- [ ] **Restow pi on any machine deployed at 85823a2** — for the few commits
  before 141c441, pi was a full stow package including `settings.json`, so a
  machine set up in that window has `~/.pi/agent/settings.json` symlinked into
  the repo — pi would write its runtime state (`lastChangelogVersion`,
  `/settings` edits) straight into the working tree. After pulling: `stow -R
  --no-folding pi` then `bash pi/setup-settings.sh`. Machines set up before or
  after the window are unaffected; delete this once every machine has pulled
  past it (2026-08-07).
- [ ] **Re-enable Ghostty `copy-on-select` once multi-line copies work** —
  disabled 2026-07-20 because Ghostty writes hard line breaks to the macOS
  pasteboard as NUL instead of newline, so every multi-line selection pastes
  as a single line. When re-enabling, the value must be `clipboard`, not
  `true`. Details and the byte-level evidence in [Ghostty copy-on-select
  mangles multi-line copies](#ghostty-copy-on-select-mangles-multi-line-copies)
  below; still unverified whether it's Ghostty-wide or specific to the Claude
  Code pane.
- [ ] **Adopt zmx for persistent terminal sessions** — nvim terminals and
  sidekick Claude sessions currently die with nvim, and Ghostty restores layout
  but not contents; all three are the same root cause (the client owns the PTY).
  Background, goals, and open questions in
  [zmx-session-persistence.md](zmx-session-persistence.md) (2026-07-26).
  Reboot ending every session is accepted and out of scope. Next step is a
  spec: session naming, lifecycle/reaping, and the Ghostty launch shape — not
  installing anything yet.
- [ ] **Evaluate the dropbar breadcrumb, and tune what it shows per filetype** —
  on trial 2026-07-28 behind `<leader>tw` (2nd attempt; first reverted
  2026-07-03). Two decisions, in order:
  1. *Does it earn its row?* It duplicates the treesitter-context sticky
     header's scope chain; the two stack, but cost up to 4 rows off the top of
     **every** window (1 winbar + `max_lines = 3`, multiwindow). If the
     duplication is the problem rather than dropbar itself, try `max_lines = 1`
     before dropping either.
  2. *If it stays, tune the contents.* `bar.sources` is already a
     `fun(buf, win)` upstream, so per-filetype content is a supported hook —
     stock is `path + markdown` / `terminal` / `path + (lsp || treesitter)`.
     Knobs: drop `path` where the statusline already shows the filename;
     `sources.path.max_depth` (16); `sources.lsp.valid_symbols` and
     `sources.treesitter.valid_types` to cut noisy kinds down to the
     `module > Class > method` spine; `bar.truncate`.
  Verdict → [nvim-backlog.md](nvim-backlog.md)'s dropbar entry; setup in
  `nvim/.config/nvim/lua/breadcrumbs.lua`, prose in [GUIDE.md → Breadcrumbs
  (dropbar)](../nvim/.config/nvim/GUIDE.md#breadcrumbs-dropbar).
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
- [x] **Unify yank.lua's `yc`/`yC` ref format with sidekick's `#L`** — done
  2026-08-07. They emitted `@path:42-58` while `ai_context.lua` emitted
  `@path#L42-58`; the colon shape turned out to be documented nowhere, and
  `@file#L100-110` is Claude Code's actual mention syntax, so `yc`/`yC` were
  producing a "Claude reference" Claude doesn't parse as a range. Both now emit
  `#L`, which also matches GitHub permalinks. Not routed through
  `ai_context.M.ref` on purpose — that one is cwd-relative and self-quotes,
  while `yc`/`yC` are repo-relative/absolute for sharing outside the checkout.
- [ ] **Collapse the sidekick detach sweep's 9 `State.get` calls into 1** — all
  9 filter the same snapshot, so the sweep re-scans the world 9× for nothing.
  Harmless today (~0.05ms/call post-`88cb662`), but it's the multiplier that
  turned a 65ms backend scan into a ~590ms freeze — do it before enabling mux.
  See "Performance" in
  [sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md).
- [ ] **Evaluate [edgy.nvim](https://github.com/folke/edgy.nvim) per-edge** —
  UI/UX evaluation plan in [edgy-ui-ux.md](edgy-ui-ux.md) (2026-07-27):
  staged bottom → left → right trial, verdict per edge. Start with Stage 0
  (`splitkeep = "screen"` + a run-output marker filetype), which pays off
  even if edgy is rejected. Supersedes nvim-backlog.md's one-paragraph
  "Unified stacked edgebar" entry.
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
- [ ] **Evaluate [vim-herdr-navigation](https://github.com/paulbkim-dev/vim-herdr-navigation)**
  — a herdr plugin (`herdr plugin install paulbkim-dev/vim-herdr-navigation`),
  not an nvim one: unifies `Ctrl+h/j/k/l` across herdr panes and nvim splits
  (vim-tmux-navigator ported to herdr). This config already binds those keys
  to `<C-w>h/j/k/l` (`nvim/.config/nvim/lua/keymaps.lua:122-125`) plus
  terminal-mode versions for sidekick terminals
  (`nvim/.config/nvim/lua/utils.lua:40-43`), so it would extend an existing
  keybinding rather than add a new one. Caveat found before adopting: its
  nvim-side maps are normal-mode only, so sidekick's terminal-mode
  `<C-h/j/k/l>` wouldn't fall through to herdr panes without also extending
  `utils.lua` — decide whether that's worth doing before installing. Needs
  `jq` (already a dependency here) and herdr ≥0.7.0 (have 0.8.0). See
  README → "Herdr".
- [ ] **Evaluate [llmtrim-herdr](https://github.com/fkiene/llmtrim-herdr)** —
  a herdr plugin (`herdr plugin install fkiene/llmtrim-herdr`) that
  compresses every agent pane's requests (-31% input / -74% output, per its
  own measurements) with a per-pane savings badge — the herdr-pane equivalent
  of the `rtk` hook already wired into Claude Code
  (`claude/.claude/settings.json`). Check whether it double-compresses
  alongside rtk on the same Claude pane (rtk hooks Claude's own PreToolUse
  Bash output; this operates at the terminal-pane layer, so they may not
  actually overlap — unverified) before enabling both.

## Known fragility

Deliberate dependencies on other plugins' *private* internals. Each breaks
silently (or throws) when upstream refactors — nothing else will flag them, so
re-check this list after a `:PackUpdate`. Add an entry whenever a change
knowingly reaches into private API.

- **`picker.lua` → snacks picker internals (two monkey-patches).**
  `Snacks.picker.format.filename` is wrapped relying on the private
  `{ '', resolve = fn }` chunk shape (path-width cap), and
  `Snacks.picker.preview.file` is wrapped copying upstream's
  `preview_title`/`title` precedence (full path in the preview border). A
  snacks refactor makes both stop applying *silently* — paths expand to full
  width, preview titles revert to basename. Check: open `<leader>sg`, confirm
  paths are capped and the preview border shows the item's path.
- **`grugfar.lua` → grug-far private fields.** The `<localleader>S`
  search/replace swap reads `inst._context` / `inst._buf` and the internal
  `grug-far.inputs` module, with no pcall — an upstream rename throws on
  keypress. Check: `<leader>sR`, type something in search, `<localleader>S`.

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
  done / is idle (pipeline first, UI later). The UI now has its own plan:
  sidekick-agent-view.md below.
- [sidekick-agent-view.md](sidekick-agent-view.md) — the agent view MVP:
  `<leader>av` dedicated tabpage with a left agent-list sidebar +
  embedded agent terminal, cycling, and two-tier attention glyphs
  consuming the event pipeline (`agentview.lua` + `agent_events.lua`).
  All three phases + the UX-critique follow-ups + review fixes landed
  2026-08-10; interactive verification of the full checklist is the
  remaining open item, then merging the `agent-view` branch.
- [sidekick-agent-view-internals.md](sidekick-agent-view-internals.md) —
  agent-facing companion to the above: the shipped state machine as a
  truth table, the invariants, the sidekick internals we depend on,
  headless-testing recipes, retreat positions, and the regression suite
  (`nvim/.config/nvim/tests/agentview/run.sh`). Read before editing
  `agent_events.lua`/`agentview.lua`.
- [sidekick-windowless-prewarm.md](sidekick-windowless-prewarm.md) — real
  windowless CLI-start API to replace the hidden-float pre-warm hack; interim
  hack shipped, Phase C (upstream PR) + Phase D (simplify `ai.lua`) still open.
- [sidekick-cursor-support.md](sidekick-cursor-support.md) — add Cursor
  (`cursor-agent`) as a second agent beside Claude in the flat session pool
  (`<leader>an` agent picker is the single creation door, agent-aware
  naming/fork, pool-wide switch/cycle). UX locked 2026-07-21 (rev. 2026-07-22);
  implemented 2026-07-22, all manual verification passed. **Partly superseded
  2026-08-07** — `opencode` and `pi` joined `AGENTS` (so "the two agents" reads
  as four) and the `u` handling became an allowlist table; the UX rationale
  still holds. Only open item left from it: the hardcoded picker ranking.
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
- [edgy-ui-ux.md](edgy-ui-ux.md) — per-edge UI/UX evaluation of edgy.nvim
  (2026-07-27): what each screen edge gains, the hand-rolled layout code a
  successful adoption would delete (`buffers.lua` coordinator, QuitPre
  sidebars-quit, stickybuf, sidekick's edge promotion), staged trial with
  kill criteria. Expected verdict: bottom likely, left maybe, right no.
- [zmx-session-persistence.md](zmx-session-persistence.md) — background +
  motivation (no spec yet, 2026-07-26): adopt [zmx](https://github.com/neurosnap/zmx)
  so the shell outlives its client — nvim terminals and Claude sessions survive
  `:qa` and crashes, and Ghostty gets contents back to pair with the layout
  `window-save-state` already restores. Persistence without a multiplexer; it
  re-hydrates clients using Ghostty's own extracted VT engine. Carries the
  Ghostty #1847 status (open 2 years, no maintainer design engagement) so that
  isn't re-researched.
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
