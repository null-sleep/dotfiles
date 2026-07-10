# Speed up nvim startup + session restore (`<leader>qs`)

## Context — what the profiling found

Headless startup is ~124ms with **everything loading eagerly**. Top costs from `--startuptime`:
`plugins.lua` 37ms, `lsp.lua` 19ms, `gitui.lua` (neogit+diffview) 11ms, `completion.lua` 8.6ms,
`testing.lua` (neotest) 7.6ms, `debugging.lua` (dap+dap-ui) 5.8ms, `filetree.lua` 3.6ms.

The past-7-days commits are **not** the regression: snacks.nvim adds 0.5ms, the sidekick/statusline
component is a cheap per-redraw pcall, the keybindings-picker work only affects picker open. The
sluggish *feel* — especially `<leader>qs` — is a **startup collision**, mostly from older code:

1. **`ai.lua` pre-warms the `claude` CLI 100ms after startup** (heavy node process, ~1–2s of CPU),
   and `terminal.lua` pre-warms a toggleterm shell at 100ms — exactly when you press `<leader>qs`.
2. **Session restore itself is cheap** (~130ms sync, sessions are a few KB) — the slowness is the
   async storm it triggers: rust-analyzer indexing, Copilot LSP (node), lua_ls, gitsigns/treesitter
   per buffer, all competing with the claude spawn.
3. **`mason-tool-installer` `auto_update`**: when the 24h debounce expires, ~19 package update
   checks spawn right at startup (explains "sometimes it's much worse").
4. **`configs.lua` runs a 500ms forever-timer** calling `:checktime` on all buffers, plus
   `check_nvim_update()` spawns `brew info` in the startup window (once/24h).

An Opus adversarial review of the first draft verified every plugin-level gotcha empirically
(neogit `did_setup` lock-in, plugin-phase clobbering of init-time command overrides, nvim-tree
pre-setup error notify, toggleterm `spawn()` non-idempotency, mason `start_delay`, persistence
Load events) and re-prioritized: **the de-collision work is the actual fix for the felt problem;
the module deferrals are a ~22ms once-per-session polish.** The plan below reflects that order.
Debugging (dap) deferral was dropped: for a Rust-first user its 5.8ms would be reloaded ~2s after
the first `.rs` buffer anyway, and its dap-ui listener wiring has five entry points (incl.
unguarded `:Dap*` commands) — highest risk, no real gain.

Key mechanic (verified): `vim.pack.add` puts every plugin on the rtp and sources its `plugin/`
files during startup regardless of our `packadd` calls — so deferral targets the `require()`/
`setup()` work, plugin commands still exist, and `require()` resolves at any time.

---

## Phase 1 — de-collide the startup/restore window (the felt fix)

### 1. `ai.lua` — move claude pre-warm off the restore window
- Replace `vim.defer_fn(..., 100)` with a re-schedulable 3000ms one-shot uv timer, following
  `configs.lua`'s `_G` stop/close re-source guard; **also close the handle inside its own callback
  after firing** (the first draft leaked it until re-source).
- `User PersistenceLoadPre` → stop timer; `PersistenceLoadPost` → reschedule (events verified in
  persistence.nvim source) — so `<leader>qs` pushes the claude spawn to 3s *after* restore.
- **Race guards (both required — the 3s window makes them reachable):**
  - At pre-warm start: skip entirely if a `sidekick_terminal` buffer already exists.
  - Mid-pre-warm: `<leader>aa` during the show→hide window could open into the hidden-float
    override or get hidden by the trailing `cli.hide`. Re-check before the trailing
    `cli.hide`/cleanup: if a visible sidekick CLI appeared during the window, skip the hide and
    clear the `_G.__sidekick_prewarm` flag immediately.

### 2. `terminal.lua` — stagger shell pre-warm (100ms → 2000ms)
- Staggered before claude's 3000ms so the spawns don't land together.
- Add "user got there first" guards: `Terminal:spawn()` is **not** idempotent (verified) — check
  `require('toggleterm.terminal').get(1, true)` for the float and bufnr validity for the bottom
  panel before spawning. (Trade-off, acceptable: `<C-\>` within the first 2s pays a cold spawn.)

### 3. `lsp.lua` — `start_delay = 3000` on mason-tool-installer
Option verified in plugin source (`vim.defer_fn(check_install, start_delay)`); moves the daily
~19-package update check out of the startup window. Extend the existing comment.

### 4. `configs.lua` — cheaper background checks
- checktime poll timer 500ms → 2000ms (interactive cases are covered by the
  FocusGained/BufEnter/CursorHold autocmds; the timer only covers "changed while idle/unfocused").
- Wrap `require('utils').check_nvim_update()` in `vim.defer_fn(..., 5000)` — it's already async,
  but this moves the `brew info` process spawn off the startup window. Its own 24h/headless
  guards still apply at fire time.

**Land Phase 1, measure the `<leader>qs` feel in a rust repo, then decide whether Phase 2 is
still wanted** (it's a once-per-session ~22ms trim, at the edge of perception).

---

## Phase 2 (optional polish) — defer on-demand modules (~22ms)

### 5. `utils.lua` — add `M.lazy_setup(fn)`
Returns a memoized `ensure()`: runs `fn` on first call, no-ops after (module-local flag, resets on
re-source like today's eager behavior).

### 6. `gitui.lua` — defer neogit setup (11.3ms) — **`<leader>g*` only**
- Wrap the neogit packadd + `setup{}` in `ensure()`; prepend it in the `<leader>g*` callbacks only.
- **Leave `<leader>v*` untouched**: diffview has no `setup()` call today, runs on defaults, and is
  already on the rtp via `vim.pack.add` — routing it through neogit's ensure would add an
  unnecessary 11ms to plain diffview opens. Keep `local dv = require('diffview')` as is.
- **`:Neogit` override (required):** `neogit.open()` auto-setups with `{}` and `setup()` has a
  `did_setup` guard — a manual `:Neogit` before first keypress silently locks in default config.
  Re-register the command to call `ensure()` first, from a **`UIEnter`-once autocmd** (an
  init-time override gets clobbered when the end-of-startup plugin phase re-sources `plugin/`
  files — verified empirically).

### 7. `testing.lua` — defer neotest (7.6ms)
- `ensure()` wraps packadds + `neotest.setup{adapters={require('rustaceanvim.neotest')}}`; all
  `<leader>n*` prepend it. (`<leader>nd` needs no extra wiring now that dap stays eager.)
- `rust.lua` stays an eager require in `init.lua` (keeps the deferred adapter require safe) —
  reword the ordering comments in `init.lua`/`testing.lua`/nvim `CLAUDE.md`.
- Optional: `UIEnter`-once `:Neotest` override calling `ensure()` (failure without it is loud,
  not silent — lower priority than `:Neogit`).

### 8. `filetree.lua` + `keymaps.lua` + `outline.lua` — defer nvim-tree (3.6ms)
- Keep eager: netrw-disable globals, QuitPre auto-close autocmd (needs no setup). Defer: setup +
  FileCreated subscription. Export `{ ensure, is_ready }`.
- `keymaps.lua` `<leader>e` calls `ensure()` first. `outline.lua` `<leader>o` must check
  `require('filetree').is_ready()` before `nvim-tree.api.tree.is_visible()` — pre-setup that call
  emits a `[NvimTree] setup not called` error notify (verified). A never-setup tree can't be
  visible, so the guard is exactly equivalent.
- Sessions never contain the tree, so restore can't surface a broken panel.

**Not deferred, deliberately:** debugging.lua (see Context), completion.lua/blink,
plugins.lua's telescope/treesitter setup, git.lua/gitsigns, aerial (symmetric candidate to
nvim-tree — revisit only if Phase 2 proves worthwhile).

### 9. Doc sync (same change, per repo rules)
- GUIDE.md: Architecture "Plugin loading pattern" + file-responsibility bullets + Load-order
  rewording; new Design Decisions subsection ("On-demand modules set up on first use"); first-use
  notes in the Neogit/Rust-testing/nvim-tree/toggleterm/AI/LSP Part 2 sections.
- nvim `CLAUDE.md`: reword the "rust before testing" bullet.
- Copy this plan into `plans/` in the repo (house workflow).

## Workflow
Per-change commits with `Part-of:` body trailers (no subject numbering): roughly one commit per
numbered step, docs included in the commit that changes the behavior. Pause before verification.
Phase 1 steps are mutually independent; in Phase 2, step 5 precedes 6–8.

## Verification

Phase 1:
1. Collision test: in a rust repo, start nvim → immediately `<leader>qs`; claude appears ~3s after
   restore completes (watch `ps aux | grep claude`), `<leader>aa` at ~5s is instant, `<C-\>` warm.
2. Race guards: `<leader>aa` within 2s → CLI not hidden at 3s and not opened into a hidden float;
   `<C-\>` early → exactly one shell #1 (`:lua =#require('toggleterm.terminal').get_all(true)`).
3. `debounce_hours = 0` temporarily → mason update check fires ~3s in, not at startup; revert.
4. checktime: external edit while nvim idle/unfocused reloads within ~2s.
5. Re-source ai/terminal/configs twice — single autocmd registrations, no timer-leak errors.

Phase 2:
6. `nvim --startuptime` before/after — gitui/testing/filetree drop (~22ms total), nothing new >1ms.
7. First-press smoke tests: `<leader>gg/gc/gq` (config applied: tab kind, no gutter signs),
   `<leader>vv/vp/vq` (unchanged path), `<leader>nn/ns/nd` in a Cargo project, `<leader>e` both
   ways, `<leader>o` before ever opening the tree (no error notify), panel swaps.
8. Command paths: `:Neogit` (our config applied → override works), `:DiffviewOpen`, `:Neotest run`.
9. `:checkhealth` / `:messages` clean; GUIDE.md/CLAUDE.md greps resolve; re-source the three
   deferred modules twice each.
