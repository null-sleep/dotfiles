# plans/ — index

Design and feature-planning docs for this dotfiles repo (mostly the Neovim
config). This index is orientation only — **the code is the source of truth**;
a plan may be stale or superseded by what actually shipped. Plans are pruned
as they land (see git history for removed ones).

## TODO — things to act on

A running checklist of what I actually want to do next across these plans
(distinct from the index below, which just catalogs everything). Check items
off or delete them as they land; add new ones freely.

- [ ] **Render images + mermaid diagrams in nvim under Ghostty** —
  [ghostty-followups.md](ghostty-followups.md) Part 1 §3. **PARKED
  (2026-07-15):** the render pipeline works (native-Rust `mmdr` via an `mmdc`
  shim — no Chromium — gate + `SNACKS_GHOSTTY` + imagemagick all built and
  installed), but inline images are **disabled** (`image.enabled = false`)
  because terminal-graphics images only draw in the *focused* window, which
  blanks the diagram whenever the Claude-in-a-split pane is focused. Resume =
  flip `enabled` back on and decide if that split limitation is acceptable.
  See Part 1 §3 for the full record + the flatten.nvim testing gotcha.
- [ ] **Remove the stale-`NvimTree_N` session cleanup shim** — once every
  machine's saved sessions have quit at least once under the fix (self-healing
  the old `badd NvimTree_N` phantom), drop the by-name buffer-wipe loop in
  `session.lua`'s `PersistenceSavePre` hook (keep the window-close). Shim added
  in `669b19e`.
  - [ ] **Saved picker searches** - when you search something save that somewhere
     so you can easily re-run it later. This is a feature that I want to add to the
     picker plugin.
- [ ] **Review snacks' default picker keymaps for inspiration** — hoisted from
  [telescope-vs-snacks-picker.md](telescope-vs-snacks-picker.md)'s
  post-migration TODO (#2) when that doc was shrunk (2026-07-18).
- [ ] **Mine linkarzu's snacks-picker post for setup ideas** — hoisted from the
  same post-migration TODO (#8).
- [ ] **Make `<leader>ab` an interactive buffer-picker send** — see the
  re-sketched second half of
  [sidekick-af-ac-context-fix.md](sidekick-af-ac-context-fix.md) (the original
  telescope mechanism was pruned; re-spec against snacks at build time).
- [ ] **Finish large-file protection's deferred per-subsystem guards**
  (gitsigns / satellite / auto-save / sidekick NES + `:LargeFileRestore`) —
  see [large-file-protection.md](large-file-protection.md) → TODO.
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
- [ ] **Wire treesitter text objects and navigation** — `af`/`if`, `ac`/`ic`,
  `aa`/`ia`, `al`/`il` select, plus `]f`/`[f`/`]F`/`[F`/`]k`/`[k` jump. Plugin
  already installed. See [treesitter-textobjects.md](treesitter-textobjects.md).
  Related: the [mini.ai](https://github.com/nvim-mini/mini.ai) eval below —
  that plan defers the `o`/`d`/next-last text objects to it.
- [ ] **Evaluate [atone.nvim](https://github.com/XXiaoA/atone.nvim)** — a modern
  undo-tree UI (treesitter-powered live diff previews, auto buffer attach, node
  bookmarks). We have **no undo-tree plugin at all** today, so this is additive,
  not a swap — worth a look purely on "can I see and navigate my edit history".
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
  substitute, `S` overlaps the hand-built structural select).
- [ ] **Build the Python debug/test stack** — spec'd and thrice-reviewed in
  [python-debug-test.md](python-debug-test.md). Two follow-on decisions it
  deliberately leaves open: (1) **what is a Python "run target"?** — the
  `pickers/pytargets.lua` analogue of `go list` (`__main__` scripts?
  `[project.scripts]`? `python -m pkg`?), which is what finally binds
  `<leader>dR` for Python; (2) whether `dap-python.debug_selection()` (debug a
  visual selection — no neotest equivalent) deserves a key.

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
  `<leader>af`/`<leader>ac` context column bug (land-ready spec); the
  `<leader>ab` buffer-picker half was re-sketched against snacks 2026-07-18
  (see the TODO above).
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
- [ghostty-followups.md](ghostty-followups.md) — successor to the now-deleted
  `ghostty.md` migration plan. Two leftover open items (status bar,
  `ApplePressAndHoldEnabled`) + the parked inline-mermaid resume plan, plus a
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
