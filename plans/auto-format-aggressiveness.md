# Auto-format aggressiveness

Format-on-save is now ON (`lua/format.lua`, `vim.g.disable_autoformat = false`,
2026-07-20). This plan captures the tuning options for *when* it fires, to be
picked from lived experience rather than guessed at up front.

Scope: format-on-save timing only. Nothing here is about Copilot — that removal
landed in the same change and needs no plan.

## The problem: format-on-save is coupled to auto-save, not to `:w`

`auto-save.nvim` performs its writes with a plain `silent! write`
(`auto-save/init.lua:78-86`), and `noautocmd` defaults to `false`
(`auto-save/config.lua:20`) and is not overridden in `lua/autosave.lua`. So
`BufWritePre` fires normally and conform's `format_on_save` runs on auto-save's
writes, not just on ones you typed.

`lua/autosave.lua` sets:

```lua
trigger_events = {
  immediate_save = { 'BufLeave', 'FocusLost' },
  defer_save     = { 'InsertLeave', 'TextChanged' },
},
debounce_delay = 1000,
```

Net effect: **the buffer reformats roughly one second after you stop typing**,
while you're still sitting in it. That is the behavior to evaluate.

Useful hook for the options below: `auto-save.nvim` fires
`User AutoSaveWritePre` and `User AutoSaveWritePost` around its write
(`auto-save/init.lua:76,88`, dispatched via `nvim_exec_autocmds("User", …)`).
That's what makes it possible to distinguish an auto-save write from a real one.

## Prior art: nobody ships this combination

Researched 2026-07-20. The short version: **no editor or distro ships debounced
auto-save together with format-on-save**, and the two editors that offer both
features explicitly suppress formatting on automatic saves.

**VS Code** — `editor.formatOnSave` defaults to `false`, and even when enabled it
refuses to run on a delayed auto-save. Enforced in source, not just documented
([`saveParticipants.ts`](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/workbench/contrib/codeEditor/browser/saveParticipants.ts)):

```typescript
if (context.reason === SaveReason.AUTO) { return undefined; }
```

The setting description was reworded in Oct 2024 to state it outright: *"When
`files.autoSave` is set to `afterDelay`, the file will only be formatted when
saved explicitly."* Requests for the combination were closed `as-designed`
([#225661](https://github.com/microsoft/vscode/issues/225661)) and
`out-of-scope` ([#45997](https://github.com/microsoft/vscode/issues/45997)).
When `onFocusChange` auto-save *was* leaking into formatOnSave, that was treated
as a **bug and fixed** ([#206475](https://github.com/microsoft/vscode/issues/206475)) —
so VS Code's model is explicit-save-only, full stop. `files.autoSaveDelay`
defaults to 1000ms, the same debounce this config runs.

**Zed** — same rule, arrived at independently. From its `default.json`: *"Keep in
mind, if the autosave with delay is enabled, format_on_save will be ignored."*
Zed also flipped `format_on_save` to `"off"` globally on 2026-06-29
([PR #59710](https://github.com/zed-industries/zed/pull/59710)), keeping it on
only for 12 languages with canonical formatters (Rust, Go, Zig, Elixir, …).

**Helix** — `auto-format` defaults to `false`; ~21 of 250+ languages opt in
explicitly. No autosave, so no interaction.

**JetBrains** — the outlier: "Reformat code" under Actions on Save defaults to
**off**, but when enabled it *does* run on autosave. Its autosave triggers on
frame deactivation and idle rather than a keystroke debounce, so it rarely fires
mid-expression.

**Sublime / Emacs / vanilla Neovim** — no built-in format-on-save at all.
(Emacs' `apheleia` is worth a look for a different mitigation: it formats
asynchronously and checks whether the buffer changed during formatting before
applying the result.)

**Neovim distros** — opinionated ones default on with a toggle keymap; starters
default off with the code sitting there commented out. Crucially **none of them
ships an auto-save plugin**, so "format-on-save" there means `:w`:

| Distro | Default | Mechanism |
|---|---|---|
| LazyVim | on | `vim.g.autoformat = true`; `<leader>uf` buffer, `<leader>uF` global |
| AstroNvim | on | `format_on_save.enabled = true`, buffer-local override |
| kickstart.nvim | off | opt-in allowlist, ships empty |
| NvChad starter | off | commented out, and its `BufWritePre` event too |
| LunarVim | off | `enabled = false`; dormant since 2025-06 |

**Takeaway for this config:** option 3 below is the industry-standard answer,
not a fallback. The `:w`-rarity objection to it is real, but it's precisely the
tradeoff VS Code users on `afterDelay` already accept.

## Option 1 — format on leaving the buffer/window

Format only on auto-save's `immediate_save` path (`BufLeave`, `FocusLost`); gate
the debounced saves out of formatting via a flag set in `User AutoSaveWritePre`.

Formatting then happens at "done with this file" boundaries and can never move
code under a live cursor. Auto-save behavior is untouched — this changes only
which writes get formatted.

Cost: a file you never leave never gets formatted, so long single-file sessions
drift until you switch away or hit `<leader>cf`.

## Option 2 — format on finishing an insert

Drop `TextChanged` from `defer_save`, keeping `InsertLeave`, then leave
`format_on_save` on. Formatting fires ~1s after you leave insert mode.

**This changes auto-save, not just formatting** — `TextChanged` is what catches
*normal-mode* edits. Without it, those are only written on `BufLeave`/`FocusLost`.
Concretely, what stops being debounce-saved:

- `dd` to delete a line, then sit reading the file. Today it's on disk after 1s.
  After this change it isn't — a crash, or a `git diff` / test run from another
  terminal, sees the pre-delete content until you switch buffers.
- `p` to paste, `u` to undo, `<C-r>` to redo, `:s/foo/bar/g`, a macro via `@q`,
  a gitsigns `<leader>hr` reset-hunk. All normal-mode, all affected.
- The asymmetry is the confusing part in practice: type a line and it saves;
  delete that same line with `dd` and it doesn't. Same file, same second, two
  different durability guarantees, no visible signal which one you got.

And on the formatting side it still doesn't fully solve the mid-edit problem:

- `o` to open a line, type a few words, `<Esc>` to think → 1s later the buffer
  reformats around you while you're still deciding what to write. This is the
  exact case option 1 avoids and option 2 does not.
- `<Esc>` immediately followed by `dd` because the thought was wrong → the
  format already fired on the `InsertLeave`, so you paid to format a state you
  discarded a keystroke later.

Worth weighing against option 1, which gets the same "not mid-typing" property
without touching auto-save's durability at all.

## Option 3 — format on explicit `:w` only (matches VS Code / Zed)

Keep `format_on_save` on, but skip it for auto-save writes. Two implementations:

- **Targeted (preferred).** Set a flag in `User AutoSaveWritePre`, clear it in
  `AutoSaveWritePost`, and have `format_on_save` return early while it's set.
  Affects formatting only.
- **Blunt.** `noautocmd = true` in `autosave.lua` — okuuva's fork supports it
  (`auto-save/config.lua:21`) and it makes auto-save write with `noautocmd`, so
  `BufWritePre` never fires. One line, but it also silences *every* other
  write-time autocmd on those saves (gitsigns refresh, lint-on-save), which is
  broader than the problem.

This reproduces VS Code's `SaveReason.AUTO` gate, which Neovim has no built-in
equivalent for — `BufWritePre` fires identically for `:w` and for a
plugin-issued write, so the distinction has to be reconstructed by hand.

The catch: auto-save already handles most writes in this config, so `:w` gets
typed rarely, and this may end up firing about as often as `<leader>cf` would.

## Option 4 — keep formatting on auto-save, but cancel saves mid-thought

Rather than gating formatting, make auto-save fire less surprisingly. okuuva's
fork has `trigger_events.cancel_deferred_save`, which defaults to
`{ 'InsertEnter' }` and is currently inherited (this config's `trigger_events`
override omits the key, and `Config:set_options` deep-merges with `"keep"`, so
the default survives). linkarzu's write-up on this exact stack adds visual-mode
and flash-jump cancels plus a 2s delay:

```lua
cancel_deferred_save = {
  'InsertEnter',
  { 'User', pattern = 'VisualEnter' },
  { 'User', pattern = 'FlashJumpStart' },
},
```

Complementary to options 1-3 rather than exclusive with them.

## Already fixed (2026-07-20)

Two things found while researching the above, both landed rather than deferred:

- **conform `undojoin = true`** (`lua/format.lua`) — merges the format into the
  preceding edit's undo entry so `u` undoes your change, not just the reformat.
  Auto-save + autoformat breaking undo/redo is a documented interaction
  ([pocco81/auto-save.nvim#87](https://github.com/pocco81/auto-save.nvim/pull/87)),
  and it gets worse the more often formatting fires — so it matters more here
  than in a `:w`-only setup.
- **`QuitPre`/`VimSuspend` restored** (`lua/autosave.lua`) — the
  `trigger_events.immediate_save` override had dropped them, because
  `Config:set_options` deep-merges with `"keep"` and a specified key replaces
  the plugin default wholesale. A pending deferred save was never flushed on
  quit or suspend.

## Orthogonal: how broad should the LSP fallback be?

`lsp_format = 'fallback'` is set twice — `default_format_opts`
(`lua/format.lua:62`) and the `format_on_save` return (`:71`). So auto-formatting
reaches **every filetype with a formatting-capable LSP** (ts_ls, gopls, pyright,
lua_ls, eslint), not just the 15 with an explicit `formatters_by_ft` entry.

Expect large whole-file diffs the first time you touch a repo that isn't already
formatted to those servers' defaults — independent of which trigger option is
chosen, since it's about breadth rather than frequency.

Alternative: `lsp_format = 'never'` on the auto path only, keeping `'fallback'`
for `<leader>cf`. Auto-format then touches only the explicitly configured
filetypes. Note this also drops rust's rustfmt→rust_analyzer fallback on the
auto path (`lua/format.lua:24`).

## Decision log

- **2026-07-20** — enabled format-on-save as-is (no trigger tuning, LSP fallback
  left broad) to gather real usage first. Revisit against the options above once
  there's a concrete complaint to aim at.
- **2026-07-20** — researched prior art (above) *after* enabling. It points
  fairly hard at option 3: VS Code and Zed both ship the gate, and VS Code
  treats formatting leaking onto an automatic save as a defect. Deliberately
  not acted on yet — the point of enabling as-is was to find out whether the
  mid-edit reformat is actually annoying in practice, and that data is worth
  more than matching someone else's default. If it does annoy, skip straight to
  option 3 rather than re-litigating all four.
