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
- [ ] **Add the `ghostty` stow package** — a plain-text, macOS-native terminal
  alongside kitty/iTerm2 that follows macOS light/dark on its own. Verify theme
  names with `ghostty +list-themes` first (see the risk callout). See
  [ghostty.md](ghostty.md).
- [ ] **Remove the stale-`NvimTree_N` session cleanup shim** — once every
  machine's saved sessions have quit at least once under the fix (self-healing
  the old `badd NvimTree_N` phantom), drop the by-name buffer-wipe loop in
  `session.lua`'s `PersistenceSavePre` hook (keep the window-close). Shim added
  in `669b19e`.
  - [ ] **Saved picker searches** - when you search something save that somewhere so you can easily re-run it later. This is a feature that I want to add to the picker plugin.
- [ ] **Finish verifying Go debug/test** — two interactive checks never closed.
  (1) The `-test.run` **state-leak**: `<leader>nd` on `TestDescribe`, terminate,
  then `<leader>nd` on `TestMax` — the second session must stop in `TestMax`, not
  back in `TestDescribe`. The fix (a `dap_manual_config` *function*, not a table)
  is proven in a simulated harness but never on a real session. (2) The targets
  picker's **abort/kill**: `<leader>dR` on a big module, `<Esc>` mid-load, then
  `pgrep -f "go list"` — nothing should linger. See
  [go-run-debug-test.md](go-run-debug-test.md) → Verification.
- [ ] **Collapse the sidekick detach sweep's 9 `State.get` calls into 1** — all
  9 filter the same snapshot, so the sweep re-scans the world 9× for nothing.
  Harmless today (~0.05ms/call post-`88cb662`), but it's the multiplier that
  turned a 65ms backend scan into a ~590ms freeze — do it before enabling mux.
  See "Performance" in
  [sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md).
- [ ] **Evaluate [avante.nvim](https://github.com/yetone/avante.nvim)** — a
  Cursor-style AI plugin (inline suggest + one-click apply, "Zen Mode" agent,
  multi-provider, project `avante.md` instructions). Overlaps what we already
  run — sidekick.nvim (CLI agents) + Copilot ghost text — so the question is
  whether it *replaces* either or just adds a third AI surface. Note the costs:
  needs a build step (Rust/Cargo or a prebuilt binary fetch) and its own API
  keys, plus plenary + nui.
- [ ] **Evaluate [atone.nvim](https://github.com/XXiaoA/atone.nvim)** — a modern
  undo-tree UI (treesitter-powered live diff previews, auto buffer attach, node
  bookmarks). We have **no undo-tree plugin at all** today, so this is additive,
  not a swap — worth a look purely on "can I see and navigate my edit history".

---

Grouped by state, not priority.

## Active — outstanding work with momentum

- [telescope-vs-snacks-picker.md](telescope-vs-snacks-picker.md) — the single
  tracking doc for the picker effort, now **migrated** (telescope removed,
  snacks.picker everywhere, 2026-07): research + swap assessment, the removed
  `filter.lua` spec, the symbols-picker eval, the nvim-tree vs snacks-explorer
  eval (§6 — verdict: keep nvim-tree, but reconsider), and the post-migration
  TODOs.
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

- [harpoon2.md](harpoon2.md) — persistent, ordered per-project file bookmarks
  (`<leader>1`–`<leader>5`).
- [treesitter-textobjects.md](treesitter-textobjects.md) — semantic
  select/move/swap text objects (`af`/`if`/`ac`/…), plus a LazyVim mini.ai delta.
- [quickfix-improvements.md](quickfix-improvements.md) — quicker.nvim / nvim-bqf
  for a real, prunable quickfix panel.
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
- [ghostty.md](ghostty.md) — add a `ghostty` stow package (native-macOS GPU
  terminal) alongside kitty/iTerm2, with a native macOS-following Catppuccin
  Latte / Dracula dual theme and iTerm2-parity keybindings.
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
- [keymap-tracker.md](keymap-tracker.md) — deferred keymap-usage-tracker research
  (Neovim/which-key internals) + the parked Track C ergonomics backlog.
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

## Process / one-time

- [review-remediation-migration.md](review-remediation-migration.md) — one-time
  cross-machine post-pull migration checklist; deletes itself once every machine
  has migrated.
