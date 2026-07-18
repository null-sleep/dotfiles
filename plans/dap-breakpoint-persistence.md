# Persist nvim-dap breakpoints across sessions

**Status:** research / not started
**Date:** 2026-07-17

Goal: breakpoints set with `<leader>db`/`<leader>dB` (`debugging.lua`) currently
live only in `nvim-dap`'s in-memory `dap.breakpoints` table and vanish on
restart. Want them to survive quitting and reopening Neovim.

---

## Why the existing session plugin doesn't already cover this

`persistence.nvim` (`session.lua`) drives `:mksession`, which serializes
buffers/windows/layout but **not** signs or extmarks — the `DapBreakpoint`
signs defined in `debugging.lua:40` and nvim-dap's internal breakpoint table
are both invisible to `mksession`. This needs a dedicated mechanism, not a
session-plugin option.

Confirmed nvim-dap has no native answer either: upstream issue
[mfussenegger/nvim-dap#198](https://github.com/mfussenegger/nvim-dap/issues/198)
("Feature Request: Breakpoint persistence") is still open. The maintainer
declined to add it — `dap.breakpoints` is an internal table he's reluctant to
stabilize as public API — and instead posted a DIY Lua snippet that
commenters iterated on. No core support is planned.

---

## Option A: existing plugins

- **[Weissle/persistent-breakpoints.nvim](https://github.com/Weissle/persistent-breakpoints.nvim)**
  (258★, last push 2025-03-22) — does the actual save/load. Hooks
  `toggle_breakpoint`/`set_breakpoint`, writes to
  `stdpath('data')/nvim_checkpoints`, auto-loads on `BufReadPost`.
  **Caveat: keyed by cwd, not by project/git-root** — opening the same file
  from a different working directory won't find its breakpoints. Management
  commands are minimal: `:PBToggleBreakpoint`, `:PBSetConditionalBreakpoint`,
  `:PBSetLogPoint`, `:PBClearAllBreakpoints`. No list/picker UI.

- **[Carcuis/dap-breakpoints.nvim](https://github.com/Carcuis/dap-breakpoints.nvim)**
  (21★, pushed within the last week) — a management/UI layer with a **hard
  dependency** on persistent-breakpoints.nvim (delegates all persistence to
  it, same cwd-keying caveat). This is what supplies the "manage breakpoints"
  half of the ask: `:DapBpNext`/`:DapBpPrev` to navigate, `:DapBpReveal` for a
  properties popup, `:DapBpEdit`/`:DapBpEditAll` to edit condition/logpoint/
  hit-condition, `:DapBpSet` via `vim.ui.select`, `:DapBpClearAll`, inline
  virtual text for conditional/logpoint breakpoints, and
  `:DapBpEditException` (telescope/snacks.nvim multi-selector) for exception
  filters.

  Watch for overlap: its breakpoint-properties virtual text may visually
  compete with `theHamsta/nvim-dap-virtual-text`'s variable-value virtual
  text, already in `debugging.lua`.

Trade-off: two plugins (one a hard dependency of the other) for full
persistence + management, both fairly small/low-churn projects (not
abandoned, but not heavily trafficked either).

---

## Option B: roll our own (candidate for a fun exercise)

nvim-dap exposes what's needed to DIY this without extra dependencies:

- `require('dap').breakpoints.get()` — snapshot of all breakpoints,
  keyed by buffer, with line/condition/logMessage/hitCondition.
- `require('dap').listeners.after.setBreakpoints['x'] = fn` (or hooking the
  `<leader>db`/`<leader>dB` keymaps directly in `debugging.lua`) to persist
  on every change.
- Load path: an autocmd on `BufReadPost` that calls
  `dap.set_breakpoint(...)` for any saved entries matching the buffer's file.
- Storage: JSON file, similar shape to what persistent-breakpoints.nvim
  writes, but **could key by git root instead of cwd** — sidesteps that
  plugin's biggest caveat, likely via a small `vim.fs.root()` /
  `vim.fn.systemlist('git rev-parse --show-toplevel')` lookup, one file per
  project under `stdpath('data')/dap-breakpoints/`.

Upside: no dependency chain, full control over keying (fixes the cwd
problem those two plugins share), and it's a self-contained, well-scoped
Lua exercise (~50-100 lines) that plugs directly into the sign/keymap
scaffolding `debugging.lua` already has. The upstream issue's DIY snippet
is a reasonable starting reference, not a copy-paste target.

Downside: reinvents `:DapBpEdit`/navigate/clear-all UI from Option A if we
ever want that; scope creep risk if "just persist breakpoints" grows into
"reimplement dap-breakpoints.nvim."

---

## Reminder: look at bookmark-plugin storage techniques before building

Before committing to Option A or B, worth a side investigation into how
line-bookmark plugins solve the *same underlying problem* (persist a list of
{file, line} locations per project, survive restarts, offer navigate/list/
clear UI) — breakpoints are structurally just bookmarks with extra DAP
metadata (condition, logMessage, hitCondition) bolted on.

- **`plans/harpoon2.md`** — already-researched, not-yet-implemented plan for
  ThePrimeagen's harpoon2. Its storage model (persistent, ordered,
  per-project list surviving restarts) is close kin to what breakpoint
  persistence needs. Worth checking whether harpoon2, once installed, could
  either (a) have its storage module reused/mimicked for breakpoints, or
  (b) literally host breakpoints as a distinguished harpoon list.
- **`chentoast/marks.nvim`** and **`cbochs/grapple.nvim`** — other
  line/file bookmark plugins worth a skim for their persistence format
  (shada-based vim marks vs. their own JSON) as reference points for Option
  B's storage layer.

This is exploratory, not blocking — flagging it so Option B doesn't get
built from scratch without first seeing whether an established bookmark
plugin's approach (or the plugin itself) shortcuts the work.

---

## Open questions / decisions for later

1. Option A (persistent-breakpoints.nvim + dap-breakpoints.nvim) vs Option B
   (DIY, git-root-keyed)?
2. If DIY: reuse/build on harpoon2 (once `plans/harpoon2.md` lands) or fully
   standalone?
3. Storage keying: cwd (matches Option A's plugins) vs git root (fixes their
   caveat, needs a bit more code)?
4. If dap-breakpoints.nvim is adopted, resolve the virtual-text overlap with
   `nvim-dap-virtual-text` — disable one's display or scope them to not
   collide.

---

## Sources

- persistent-breakpoints.nvim — https://github.com/Weissle/persistent-breakpoints.nvim
- dap-breakpoints.nvim — https://github.com/Carcuis/dap-breakpoints.nvim
- nvim-dap#198 (breakpoint persistence feature request, open) — https://github.com/mfussenegger/nvim-dap/issues/198
- marks.nvim — https://github.com/chentoast/marks.nvim
- grapple.nvim — https://github.com/cbochs/grapple.nvim
