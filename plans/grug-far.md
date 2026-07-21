# grug-far.nvim — project-wide find & replace

**Status:** planned / not started
**Date:** 2026-07-20

Goal: add [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) for
interactive, buffer-based find & replace across the project — the thing
snacks.picker's live-grep deliberately *doesn't* do. snacks grep finds and
jumps; grug-far turns a search into an editable results buffer you can tweak
and then apply as a real replacement (with preview, per-line sync, undo).

Refs: [docs](https://github.com/MagicDuck/grug-far.nvim),
[linkarzu walkthrough](https://linkarzu.com/posts/neovim/grug-far/),
[LazyVim's spec](https://www.lazyvim.org/plugins/editor#grug-farnvim).

## Why it earns a slot (vs. what's already here)

`<leader>sg` (`Snacks.picker.grep`) and `<leader>sw` (grep word) cover
read-only *search* (find + jump). Neither does *replace*. Today a
project-wide rename means `:cdo`/`:cfdo` off a quickfix list or dropping to a
shell `sed`. grug-far replaces that with: pattern → live results buffer →
edit it (delete rows you don't want) → apply. It complements the pickers.

## Approach: follow grug-far's recommended usage + LazyVim's shape

Decision: implement the **single-key, recommended-API** form first (what
grug-far's docs recommend and what LazyVim ships), and keep the richer
multi-key scoped layer as an **optional future addition**,
not built now.

Two facts from grug-far's own docs drove this (both verified in
`doc/grug-far.txt`):

- **`open()` is the recommended call for a lua-function keymap.** Called from
  visual mode it auto-prefills the selection as search text *and* sets
  `--fixed-strings` (so regex metacharacters in the selection stay literal).
- **`with_visual_selection()` is explicitly "not recommended"** — it exists
  only for keymaps whose right-hand side is a *string* instead of a lua
  function. Ours are lua functions, so we use `open()` for both `n` and `x`.

### Decisions (locked)

- **One entry key: `<leader>sr`** (mode `{ 'n', 'x' }`) → `open()`. Lives
  under the existing `<leader>s` "Search" which-key group — **no new group**.
- **`<leader>sr` currently = Snacks resume; move resume to `<leader>sc`**
  ("continue"). `sc` is free.
- **`transient = true`** on the open — buffer is unlisted and auto-deletes on
  close. Safe because search *history* persists independently (`\t` in-buffer),
  so nothing recoverable is lost.
- **Minimal `setup()`** — only `keymaps = { close = { n = 'q' } }` (see close
  decision). Explicitly **not** `headerMaxWidth`: that option doesn't exist in
  current grug-far (it's stale in LazyVim's spec, silently ignored — verified
  absent from `lua/grug-far/opts.lua` and the docs).
- **Lazy-load the plugin; eager-register the glue.** The cheap,
  plugin-independent bits run at startup so they're always live — the
  `<leader>sr` keymap, the `buffers.lua` `special_filetypes` entry, and the
  stickybuf arm. The heavy `packadd` + `setup()` is deferred to the first
  `<leader>sr` press (memoized) — LazyVim's lazy-load, hand-rolled for
  `vim.pack`. (Honest caveat: grug-far's setup is light, so the raw startup
  win is likely small; the point is the clean split you asked for, and it
  reverts to eager trivially if it ever complicates debugging.)
  - **vim.pack nuance (important):** grug-far is already on the rtp and its
    `plugin/` file — which registers `:GrugFar`/`:GrugFarWithin` — runs at
    startup regardless of `packadd`. So the *only* thing actually deferred is
    `setup()` (plus its transitive requires). **Command-path caveat:** a
    `:GrugFar` invoked *before* the first `<leader>sr` opens with grug-far's
    **default** keymaps (`\c` close), because our `setup()` hasn't run yet;
    once it has (after any `<leader>sr`), the config is global and sticks.
    `<leader>sr` is the primary entry, so this edge is **accepted** — we keep
    the lazy load rather than adding a command override (a Phase-2-style
    `UIEnter` re-registration of `:GrugFar` would fix it but isn't worth the
    clobber-guard complexity for a rarely-used path).
- **ast-grep installed** — adds the syntax-aware engine; swap in-buffer with
  `\e`.
- **Register the buffer**: add `grug-far` to `buffers.lua` `special_filetypes`,
  pin it via stickybuf's `get_auto_pin`, and exclude it in `autosave.lua`
  (three separate lists — see step 7).
- **Close with `q`** — remap grug-far's own close action to `q` via its
  `keymaps.close` option. This makes `q` run grug-far's *real* teardown
  (abort in-flight search + instance cleanup), unlike LazyVim's generic
  `close_with_q` autocmd, which maps `q` to a bare window `:close`. LazyVim
  uses an autocmd because it enforces `q`-to-close as one shared convention
  across dozens of panel filetypes; we have exactly one plugin wanting it and
  it ships a native option, so the option is cleaner and avoids extending our
  help/quickfix-scoped `q` autocmd (`autocmds.lua:107`) to an editable buffer.
  `:q`/`:close` still work like any window (the always-familiar fallback). We
  drop grug-far's default `\c` because `\`-localleader is unfamiliar here and
  this config has no other localleader habit to lean on.
- **No `filesFilter` default.** A silent `*.<ext>` filter hides
  cross-language matches — a bad default for a rename tool. (See the
  optional layer for an opt-in version.)
- **README**: Brewfile comment only, no README prose (ast-grep is a plain
  plugin dep, like `fd`).

## Preconditions (already satisfied)

- nvim 0.12.4 ✓ (needs ≥ 0.11).
- ripgrep 15.1.0 ✓ (needs ≥ 14, ≥ 15 recommended).
- File icons ✓ — `mini.icons` (in `plugins.lua`) mocks `nvim-web-devicons`,
  satisfying grug-far's optional icon dependency.
- `<localleader>` = `\` (default; `maplocalleader` unset). grug-far's
  **in-buffer** keys hang off it: `\r` apply replace, `\e` swap engine, `\s`
  sync all, `\t` history, `\x` swap replacement interpreter (Lua). No change
  needed — grug-far would be this config's first `<localleader>` consumer.
  (Close is remapped off `\c` to `q`; see the close decision above.)

## Steps

### 1. `Brewfile` — add ast-grep

In the "Core CLI — shell, search, dotfiles management" block, next to
`ripgrep`/`fd`:

```ruby
brew "ast-grep"        # grug-far's optional AST search/replace engine (grug-far invokes the `ast-grep` binary, not the `sg` alias)
```

Then `brew bundle` (idempotent). Verify: `ast-grep --version` ≥ 0.36.

### 2. `lua/plugins.lua` — register with vim.pack

Add to the `vim.pack.add({ ... })` list, near other editing-UX plugins:

```lua
{ src = gh('MagicDuck/grug-far.nvim') },
```

`setup()` + keymap live in the dedicated module (step 3), not here — this
config keeps a plugin's keymaps+setup together in its own topic file (like
`scratch.lua`, which owns `<leader>b*` keys despite the shared `<leader>b`
prefix).

### 3. New `lua/grugfar.lua` — setup + the entry key

Named `grugfar.lua` (no hyphen) to avoid shadowing the plugin's own
`grug-far` Lua module — same convention as `gitui.lua`/`outline.lua`.

```lua
-- grug-far.nvim — interactive project-wide find & replace. Complements the
-- read-only snacks grep pickers (<leader>s*) with an editable results buffer
-- you apply as a real replacement. In-buffer keys use <localleader> (\):
-- \r apply, \e swap engine, \s sync all, \t history, \x Lua interpreter.
--
-- Lazy-load: the <leader>sr keymap is registered eagerly, but the plugin's
-- packadd + setup() run only on first press (memoized in ensure()). vim.pack
-- still sources grug-far's plugin/ files at startup, so :GrugFar exists
-- regardless; only the require()/setup() work is deferred off startup.
local loaded = false
local function ensure()
  if loaded then return end
  loaded = true
  vim.cmd.packadd('grug-far.nvim')
  require('grug-far').setup({
    keymaps = { close = { n = 'q' } },  -- close with q instead of \c (:q also works)
  })
end

-- In visual mode open() auto-prefills the selection as a --fixed-strings
-- search (grug-far's recommended lua-fn usage; no with_visual_selection()).
-- transient = unlisted buffer that auto-deletes on close; history persists
-- separately (\t in-buffer).
vim.keymap.set({ 'n', 'x' }, '<leader>sr', function()
  ensure()
  require('grug-far').open({ transient = true })
end, { desc = 'Search: Search & replace (grug-far)' })
```

### 4. `lua/keymaps.lua` — move resume off `<leader>sr`

Line 16 today: `<leader>sr` → `Snacks.picker.resume()`. Rebind to
`<leader>sc`:

```lua
vim.keymap.set('n', '<leader>sc', function() Snacks.picker.resume() end,
  { desc = 'Search: Continue (resume last picker)' })
```

Then fix the stale references to the old key (list verified complete via grep
of the config + GUIDE.md; re-grep `leader>sr`/`resume` at edit time — line
numbers drift):
- `lua/pickers/symbols.lua:376` — comment mentions `<leader>sr` restores the
  frozen result; update to `<leader>sc`.
- GUIDE.md `<leader>sr` rows (step 8).

### 5. `init.lua` — require the module

Add `require('grugfar')` in the plugin/feature block (near `scratch`/`git`).
Update GUIDE.md's `Load order` line in the same edit (step 8).

This module `require` is **cheap** — it only registers the `<leader>sr` keymap
and defines the memoized `ensure()`. grug-far's `packadd` + `setup()` don't
run until first use (step 3), so the plugin stays off the startup path while
its keymap and the `special_filetypes`/stickybuf glue are live from boot. This
realizes the lazy-load noted in `plans/nvim-startup-performance.md` (item 10).

### 6. `lua/whichkey.lua` — nothing to add

`<leader>sr` lives under the existing `{ '<leader>s', group = 'Search' }`
entry. No new group, no `triggers` change.

### 7. `lua/buffers.lua` + stickybuf — register the buffer

Per the nvim `CLAUDE.md` "Registering a new panel plugin" rule:

- **`buffers.lua`** — add to `special_filetypes` (bracket notation, the key
  has a hyphen):
  ```lua
  ['grug-far'] = true,  -- find & replace panel
  ```
  This drives `is_special()`, so code-only global keymaps decline in it — the
  outline/format guards, plus the alternate-buffer skip and `<leader>b`
  guards in `keymaps.lua`. Note: `special_filetypes` does **not** feed
  `autosave.lua` (it keeps its own `excluded` list — see next bullet); the
  nested `CLAUDE.md` calls out that autosave is deliberately off `is_special()`.
- **`autosave.lua`** — add `'grug-far'` to its `excluded` list. Grug-far's
  results buffer is `buftype=nofile` (so a `:write` no-ops anyway), but
  excluding it explicitly keeps autosave from ever attempting one.
- **stickybuf** — extend `get_auto_pin` in `plugins.lua` (mirrors the
  `sidekick_terminal` arm) so `gf`/jumps can't load a file *into* the
  grug-far window:
  ```lua
  if vim.bo[bufnr].filetype == 'grug-far' then return 'filetype' end
  ```

("Editable" ≠ "a code file" — the registry's question is "is this a code
buffer?", answer no, so this is the right bucket despite the buffer being
edited by design.)

### 8. `nvim/.config/nvim/GUIDE.md` — document it (same change)

Per the nvim `CLAUDE.md` "Update GUIDE.md in the same change" rule:

- **`## Contents` TOC** (GUIDE.md:17) — add the new section to it; required
  when adding a top-level section (nested `CLAUDE.md` "Keep in sync").
- New Part 2 `## grug-far` section — use this **plain** title (its auto-slug
  is unambiguous, so no explicit `<a id>` anchor needed; avoid a title with
  `&`/parens, which would). It covers:
  the `<leader>sr` entry (n + visual), the in-buffer `<localleader>` keys
  (point to `g?` in-buffer for the authoritative list rather than
  duplicating it), the `q`/`:q` close, the ripgrep-vs-astgrep engine note
  (`\e` swaps), and the "Power move" recipe below (`--multiline` + `\x` Lua
  interpreter, with the sync caveats).
- **Worked examples.** Include the "Worked examples" recipes below (rename,
  visual replace, filetype/subdir scoping, exclude, selective apply, hidden
  files, ast-grep structural) so the section teaches workflows, not just keys.
- **Scoping (Files Filter vs Paths).** Document how to narrow a search, since
  we deliberately don't pre-fill it — this is where that capability lives:
  - **Files Filter** field — *which* files, ripgrep-glob / gitignore syntax:
    `*.lua`, `*.{ts,tsx,js}`, a subtree `lua/**`, exclude with `!` (`!*_test.go`,
    `!README.md`); multiple patterns, one per line. "Same filetype as this
    buffer" = type `*.<ext>` here (the opt-in `<leader>re` in the future layer
    just pre-fills this).
  - **Paths** field — *where* to search (dirs/files; supports `~`, `<buflist>`,
    `<qflist>`).
- `Architecture` file-responsibilities bullet for `grugfar.lua`.
- `Load order` line updated for the new `require('grugfar')`.
- `Keymap index` → *By prefix*: no new prefix row (`<leader>s` already
  listed); the `<leader>sr` row is canonical in the new section.
- **Resume remap**: update the `<leader>sr` → Resume rows in GUIDE.md — the
  keymap table (~:1283) and the prose (~:1544) — to `<leader>sc`. Re-grep at
  edit time; those line numbers drift.

### 9. `README.md` — no change

Adding a plugin is a GUIDE.md change, not a README change. The only
repo-level surface is the Brewfile line from step 1; its inline comment
carries the "why". No README edit.

### 10. Commit hygiene

- `nvim-pack-lock.json` updates after nvim installs the plugin — commit it.
- `:checkhealth grug-far` should be clean (ripgrep + ast-grep both found).

## Keymap summary

Entry point (global):

| Key          | Mode | Action                                        |
| ------------ | ---- | --------------------------------------------- |
| `<leader>sr` | n, x | Open search/replace (visual: selection prefill) |

Changed by this work:

| Key          | Mode | Was                | Now                          |
| ------------ | ---- | ------------------ | ---------------------------- |
| `<leader>sc` | n    | (free)             | Resume last picker (moved)   |
| `<leader>sr` | n    | Resume last picker | Search & replace (grug-far)  |

In-buffer (buffer-local, `<localleader>` = `\`; authoritative list is `g?`):

| Key   | Action                          |
| ----- | ------------------------------- |
| `\r`  | Apply the replacement           |
| `\s`  | Sync all edited lines to source |
| `\e`  | Swap engine (ripgrep ↔ astgrep) |
| `\t`  | Open search history             |
| `\x`  | Swap replacement interpreter (Lua/Vimscript) |
| `q`   | Close the grug-far buffer (remapped from `\c`; `:q` also works) |
| `g?`  | Full in-buffer help             |

## Worked examples for the GUIDE section

Concrete, copy-pasteable recipes to include in the GUIDE.md section so it
teaches the common workflows, not just the keymaps. Fields (Search, Replace,
Files Filter, Flags, Paths) are lines in the buffer — navigate to a line and
type; `\r` applies. All are reversible with `u`.

1. **Project-wide rename.** `<leader>sr` → Search `getUserId`, Replace
   `getUserID` → `\r`. (`u` undoes every file at once.)
2. **Replace highlighted text.** Visually select `user.profile.name`,
   `<leader>sr` — it prefills the selection as the Search and sets
   `--fixed-strings`, so the `.`s are literal → set Replace → `\r`.
3. **Restrict to one filetype.** `<leader>sr` → Files Filter `*.lua` (or
   `*.{ts,tsx}`) → Search/Replace as usual.
4. **Exclude tests / a file.** Files Filter `!*_test.go` (or `!*.test.ts`,
   `!README.md`) — `!` negates; stack multiple patterns, one per line.
5. **Scope to a subdirectory.** Paths `lua/pickers` (searches only there), or
   Files Filter `lua/pickers/**`.
6. **Case-insensitive / whole word.** Flags `-i` (ignore case), `-w` (word
   boundary) — anything after Flags is passed straight to the engine.
7. **Selective apply.** Run the search, then `dd` the result rows you *don't*
   want changed; `\r` only touches the rows that remain. (Easier than crafting
   a perfect exclusion pattern.)
8. **Include hidden / ignored files.** Flags `--hidden` and/or `--no-ignore`.
9. **Structural (ast-grep).** `\e` to swap engine → Search `console.log($A)`,
   Replace `logger.debug($A)` → `\r`. `$A` is an ast-grep metavariable
   matching any argument. (astgrep is apply-only: `\r`, no `\s`.)

For the heavy multiline/Lua-interpreter case, see the Power move below.

## Power move: multiline + Lua interpreter (from linkarzu)

Worth documenting in the GUIDE section — grug-far's most powerful mode, per
the [linkarzu walkthrough](https://linkarzu.com/posts/neovim/grug-far/):

- Add `--multiline` in the **Flags** field to let a single search/replace span
  line breaks (patterns and replacements can contain `\n`).
- Press `\x` in-buffer to swap the replacement input to the **Lua
  interpreter**: the replacement is then Lua code with the current match
  available as `match`, so you can compute replacements a static string can't
  express (case conversion, arithmetic, conditional rewrites).
- Caveats to note in the doc: `\s` (Sync all) is **disabled** under
  `--multiline`, and the **astgrep** engine supports `\r` (Replace) but not
  `\s` either — so multiline/astgrep work is apply-only, no line-sync.

## Optional future layer: dedicated scoped keys

Not built now — kept here to revisit if the single `<leader>sr` proves too
blunt. This config's house style already favors one-key-per-intent (a dozen
`<leader>s*` keys), so a `<leader>r` "Replace" group would be *consistent*
with how the rest of the config works. The trade: four more bindings to hold
in your head, buying convenience (scope pre-set) not capability (grug-far's
buffer is editable — you can always change `Paths`/`Files Filter` in-buffer).

If adopted, add a `{ '<leader>r', group = 'Replace' }` which-key entry and:

| Key          | Mode | Opens with                                     |
| ------------ | ---- | ---------------------------------------------- |
| `<leader>rr` | n, x | project-wide (same as `<leader>sr`)            |
| `<leader>rf` | n    | `prefills.paths = expand('%')` — current file  |
| `<leader>rd` | n    | `prefills.paths = expand('%:h')` — current dir |
| `<leader>rw` | n    | `prefills.search = expand('<cword>')` — word   |
| `<leader>re` | n    | `prefills.filesFilter = '*.'..ext` — same type |

(`<leader>re` is the opt-in home for the same-extension filter we rejected as
a default — visible and deliberate rather than a hidden filter on `rr`.)

Whether `<leader>sr` and `<leader>rr` should coexist or the group should
subsume the single key is itself a decision to make at adoption time.

## Verification

1. `brew bundle` → `ast-grep --version`, `rg --version`.
2. Restart nvim; plugin installs via vim.pack; `:checkhealth grug-far` clean.
3. `<leader>sr`, type a throwaway pattern, confirm live results populate.
4. Enter a replacement, `\r`, confirm files change + `u` undoes cleanly.
5. Visual-select text, `<leader>sr`, confirm the selection prefills Search
   and `--fixed-strings` is set (metacharacters treated literally).
6. `\e` swaps to astgrep; run a simple AST pattern to confirm the engine.
7. `q` closes the buffer (remapped close); `:q` also closes it.
8. `<leader>sc` resumes the last picker (moved resume works); confirm the
   `<leader>sr` desc in the `<leader>sk` keybinding picker now reads
   "Search & replace".
9. **Lazy-load:** before first `<leader>sr`, `:lua =package.loaded['grug-far']`
   is `nil`; after one press it's populated. `:GrugFar`/`:GrugFarWithin` exist
   from boot (registered in grug-far's `plugin/` file) — but note they open
   with grug-far's **default** keymaps (close `\c`, not `q`) until `setup()`
   has run. See the command-path caveat under the lazy-load decision.
10. **transient + pin:** jump to a match with `<Enter>` — the file opens in a
    *separate* window, never into the pinned grug-far window; after close,
    `:ls!` shows the transient buffer wiped (`bufhidden=wipe`).

## Resolved (was: open questions)

1. **Visual-mode call** — use `open()` (grug-far's recommended lua-fn path),
   not `with_visual_selection()`.
2. **Keymap shape** — single `<leader>sr` primary; dedicated `<leader>r*`
   keys deferred to the optional layer above.
3. **`<leader>sr` collision** — move Snacks resume to `<leader>sc`.
4. **buffers.lua / stickybuf** — register both.
5. **Close key** — remap grug-far's `keymaps.close` to `q` (drop `\c`); `:q`
   also works. No autocmd needed.
6. **`filesFilter` default** — no; opt-in `<leader>re` if ever wanted.
7. **`setup()` overrides** — only `keymaps.close = { n = 'q' }`.
   (`headerMaxWidth` dropped — not a real grug-far option; stale in LazyVim.)
8. **README** — Brewfile comment only.
9. **Loading** — lazy: eager `<leader>sr` keymap + `special_filetypes`/stickybuf
   glue; `packadd` + `setup()` memoized on first press. Accepted caveat:
   `:GrugFar` before the first `<leader>sr` uses default `\c` close (no command
   override — not worth it for a rarely-used path).
10. **autosave** — exclude `grug-far` in `autosave.lua` (`special_filetypes`
    doesn't gate autosave).
