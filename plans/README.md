# plans/ — index

Design and feature-planning docs for this dotfiles repo (mostly the Neovim
config). This index is orientation only — **the code is the source of truth**;
a plan may be stale or superseded by what actually shipped. Plans are pruned
as they land (see git history for removed ones).

## TODO — things to act on

A running checklist of what I actually want to do next across these plans
(distinct from the index below, which just catalogs everything). Check items
off or delete them as they land; add new ones freely.

- [ ] **Decide the iTerm2 sync approach** — keep the opaque state-export blob
  or migrate to git-diffable Dynamic Profiles. See the "what to do next" box
  at the top of [iterm2-sessions-profiles.md](iterm2-sessions-profiles.md).
- [ ] **Confirm all machines have migrated**, then delete
  [review-remediation-migration.md](review-remediation-migration.md) (it's a
  one-time checklist that says to delete itself once every machine has pulled +
  migrated).
- [ ] **Decide `changelog.md`'s fate** — flesh out the changelog format or drop
  the idea. See [changelog.md](changelog.md).

_Add plan work you want to prioritize here._

---

Grouped by state, not priority.

## Active — outstanding work with momentum

- [sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) — a
  cmux-style event pipeline so nvim knows which Claude session needs input / is
  done / is idle (pipeline first, UI later).
- [sidekick-windowless-prewarm.md](sidekick-windowless-prewarm.md) — real
  windowless CLI-start API to replace the hidden-float pre-warm hack; interim
  hack shipped, Phase C (upstream PR) + Phase D (simplify `ai.lua`) still open.
- [sidekick-af-ac-context-fix.md](sidekick-af-ac-context-fix.md) — fix the
  `<leader>af`/`<leader>ac` context column bug and make `<leader>ab` an
  interactive buffer picker.

## Ready to build — self-contained specs, not started

- [go-run-debug-test.md](go-run-debug-test.md) — Go run/debug/test support
  (go.nvim + nvim-dap-go + neotest-golang), mirroring the Rust setup.
- [harpoon2.md](harpoon2.md) — persistent, ordered per-project file bookmarks
  (`<leader>1`–`<leader>5`).
- [treesitter-textobjects.md](treesitter-textobjects.md) — semantic
  select/move/swap text objects (`af`/`if`/`ac`/…), plus a LazyVim mini.ai delta.
- [quickfix-improvements.md](quickfix-improvements.md) — quicker.nvim / nvim-bqf
  for a real, prunable quickfix panel.
- [filter-picker-rethink.md](filter-picker-rethink.md) — externalize filter
  presets to data + in-flight filter editing in `live_grep`.
- [symbol-picker-alternatives.md](symbol-picker-alternatives.md) — time-boxed
  eval of whether snacks.picker / fzf-lua could replace the bespoke symbol picker.
- [copilot-context-enrichment.md](copilot-context-enrichment.md) — experimental:
  inject LSP/treesitter type context into Copilot's `didChange` for better ghost text.
- [neovide-path-env.md](neovide-path-env.md) — a stow-managed `~/.zshenv` so
  GUI-launched Neovide inherits the terminal PATH (LSPs/formatters).
- [iterm2-sessions-profiles.md](iterm2-sessions-profiles.md) — migrate the
  opaque iTerm2 state export to a git-diffable Dynamic Profile JSON.
- [sidekick-window-layout.md](sidekick-window-layout.md) — try the sidekick CLI
  as a right-anchored float overlay vs. the current split; runtime toggle.
- [terminal-fresh-splits.md](terminal-fresh-splits.md) — decouple fresh-spawn
  split terminals from the pre-warmed float (they currently share id=1 and stomp
  its `direction`).
- [unified-sidebar-panel.md](unified-sidebar-panel.md) — edgy.nvim-style unified
  stacked edgebar (tree + git + outline + terminal); the narrower
  file-tree↔outline mutual-exclusion already shipped (see GUIDE.md).

## Backlog

- [nvim-backlog.md](nvim-backlog.md) — the single Neovim enhancement backlog
  (consolidated from the Zed/VS Code/JetBrains gap analyses + the LazyVim /
  LunarVim comparison passes + the old TODO wishlist).

## Parked / reference — deliberate holds and design records

- [nvim-startup-performance.md](nvim-startup-performance.md) — Phase 1 landed and
  verified; Phase 2 parked for good with a documented revival trigger.
- [floating-terminal-backdrop.md](floating-terminal-backdrop.md) — dim/outline
  behind the terminal float; explored, working, then reverted — re-apply notes.
- [keymap-tracker.md](keymap-tracker.md) — deferred keymap-usage-tracker research
  (Neovim/which-key internals) + the parked Track C ergonomics backlog.
- [sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md) —
  **shipped**; kept as the design reference the event-pipeline plan cites.

## Process / one-time

- [review-remediation-migration.md](review-remediation-migration.md) — one-time
  cross-machine post-pull migration checklist; deletes itself once every machine
  has migrated.
- [changelog.md](changelog.md) — stalled idea to define a changelog format for
  tracking this bespoke editor setup's evolution.
