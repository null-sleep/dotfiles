# Large-file protection

**Status:** shipped 2026-07-13 — `snacks.bigfile` with stock defaults, one line
in `picker.lua`. The targeted patches in "What this leaves open" are
**deliberately deferred**: ship the cheap 90%, revisit only if a real big file
still misbehaves.

## The problem

Opening a very large or minified file was unprotected. The only size guard
anywhere in the config was `is_large_buffer` in `lua/plugins.lua` (>50k lines
OR >1.5MB), and it gated exactly one thing: whether native treesitter
highlighting and folding attach.

Everything else fired unguarded on a 2MB file: LSP attached and full-document
synced; `document_highlight` re-ran on every 300ms CursorHold; codelens
refreshed; nvim-lint ran on **BufReadPost as well as BufWritePost**; auto-save
rewrote the file — and a multi-megabyte undofile — 1000ms after any change,
which re-triggered lint; gitsigns diffed it; satellite recomputed its
scrollbar; aerial fell back to its **LSP** backend precisely *because*
treesitter had been skipped; sidekick's NES kept requesting edits.

`snacks.bigfile` was already installed (snacks is set up in `lua/picker.lua`)
and simply not enabled. This enables it.

## The mechanism — read this first, everything follows from it

`snacks.bigfile` does **not** disable features. It registers a
`vim.filetype.add({ pattern = { ['.*'] = fn } })` matcher that renames the
buffer's **filetype to `bigfile`** when `getfsize(path) > 1.5MB`, or when the
*average* line length exceeds 1000 — the minified case, which a 1-line 2MB JS
file trips even though it is a single line.

That rename is the whole thing. Every filetype-keyed subsystem then simply
never matches, for free and forever:

- **LSP** (`vim.lsp.enable` is filetype-matched) — and with it
  `document_highlight` and codelens, which only register inside `LspAttach`.
- **nvim-lint** (`linters_by_ft`) — kills the BufReadPost *and* the
  BufWritePost run.
- **conform** (`formatters_by_ft`).
- **aerial** (treesitter + lsp backends; neither attaches).
- **render-markdown**, **treesitter-context** (needs a live TS highlighter).
- **native treesitter** — `plugins.lua`'s FileType autocmd has
  `pattern = ts_filetypes`, and `bigfile` is not among them.

A `FileType bigfile` autocmd then runs snacks' `setup` hook, whose default does
`:NoMatchParen`, `foldmethod=manual`, `statuscolumn=''`, `conceallevel=0`,
`vim.b.completion = false` (blink honors this), the two mini.* disable flags,
and re-enables regex `syntax` with the *real* filetype on `vim.schedule` — so a
big file still gets vim-regex highlighting, just not treesitter.

Two consequences worth knowing before you hit them:

- **`gc` stops working** in a big file. No ftplugin ran, so `commentstring` is
  unset. `:setf <realft>` brings it back (and re-attaches LSP with it).
- **`:set ft?` says `bigfile`** — that's the signal protection is on, and it's
  visible in the statusline.

## TODO — what the rename doesn't reach

Deferred, not overlooked. The rename only reaches filetype-keyed things; these
four are not ft-keyed and still run on a big file. Do them **if one actually
bites** — each is small and independent, so there's no need to take them as a
batch.

- [ ] **gitsigns** — attaches per *buffer*, filetype-agnostic. Its own
  `max_file_length` is 40000 **lines**, so a 1-line 2MB minified file sails
  straight through it. Fix: `on_attach` returns `false` when
  `vim.bo[buf].filetype == 'bigfile'` — a refusal, not a post-hoc `detach()`,
  so there's no autocmd-ordering race. In `lua/git.lua`. Worth also writing
  `max_file_length = 40000` explicitly, since today the upstream default is
  silently in effect.
- [ ] **satellite** — decorates per *window*. Fix: add `'bigfile'` to
  `excluded_filetypes` in `lua/git.lua`.
- [ ] **auto-save** — has a filetype *exclusion* list rather than ft dispatch.
  Fix: add `'bigfile'` to the `excluded` list in `lua/autosave.lua`. This is
  the one most likely to bite: a huge buffer plus the 1000ms debounce plus
  `undofile` means a multi-megabyte write after every burst of typing.
- [ ] **sidekick NES / undofile / `wrap`** — all need a custom `setup` hook in
  the snacks opts: `vim.b[buf].sidekick_nes = false`,
  `vim.bo[buf].undofile = false`, and `wrap = false` (a 2MB single line,
  wrapped, is the worst redraw case there is).
  **Trap:** overriding `setup` **replaces** snacks' default wholesale — deep-extend
  swaps functions, and the default isn't exported — so a custom hook must first
  re-implement the default verbatim (`:NoMatchParen`, `foldmethod=manual`,
  `statuscolumn=''`, `conceallevel=0`, `vim.b.completion = false`, the two
  mini.* flags, and the scheduled `syntax = ctx.ft` restore). That's the point
  at which this stops being a one-liner and wants its own `lua/largefile.lua`.
- [ ] **Escape hatch (`:LargeFileRestore`)** — only worth building alongside
  the hook above, since it needs the real filetype stashed in a buffer var
  (snacks doesn't stash it). Today the manual equivalent is `:setf <realft>`,
  which restores `gc` and LSP but *not* treesitter — `plugins.lua`'s guard
  blocks that independently, and a force flag would be needed to override it.

Not a hole: blink's `buffer` source already skips buffers over
`max_async_buffer_size` (200k chars).

Accepted limitations of the mechanism itself, not worth fixing: snacks bails
when `getfsize <= 0`, so pasted/stdin/`:enew` blobs are unprotected; and
classification happens only at filetype-detection time, so a buffer that is
already open needs `:e` to be reclassified.

## Thresholds — two tiers, deliberately not unified

- **Tier 1 — snacks.bigfile: bytes / average line length.** 1.5MB (the number
  the existing guard already used — no new constant invented) and 1000 average
  line length. Effect: everything ft-keyed off, via the rename.
- **Tier 2 — `is_large_buffer` in `plugins.lua`: line count.** Kept, unchanged,
  file-local. Snacks has **no line-count criterion at all**, and the gap is
  real: a 60k-line file of short lines (~700KB) is *not* a snacks bigfile — its
  filetype stays `python`, LSP and completion still work, and correctly so,
  because they handle it fine — but a treesitter parse plus `foldexpr` over 60k
  lines is the pathological part, and this guard already blocks exactly that.

Tier 2's `>1.5MB` arm is now mostly redundant (such a file is ft `bigfile`, so
the TS autocmd never fires), but it stays as the backstop for the buffers
snacks cannot classify — the `getfsize <= 0` cases above.

No shared exported predicate: there would be exactly one consumer, and the two
criteria are not interchangeable.

**`bigfile` is deliberately not in `buffers.lua`'s `special_filetypes`.** That
registry means "not a real editable code buffer", and its consumers *decline to
act* (the `<leader>o`/`<leader>O` outline guards, the quit-when-only-sidebars
autocmd). A big file **is** a real code buffer — editable, saveable, `gc`-able
once its filetype is restored — just an expensive one. Registering it would
make `<leader>o` refuse to open the outline on it and would leak into the
sidebar/quit logic. Same separation the repo `CLAUDE.md` already draws for
autosave's and satellite's exclusion lists.

## Rejected: a hand-rolled predicate

An `is_large(buf)` predicate exported from a module and threaded through every
attach site would keep the real filetype (so `gc` and ftplugin survive), but it
costs ~8 edit sites, each with its own attach lifecycle (LSP per-client,
gitsigns per-buffer, aerial per-backend, satellite per-window), and every future
filetype-keyed plugin would need a new guard. The rename gets six subsystems for
free. LazyVim reaches the same conclusion: it ships `bigfile = { enabled = true }`
with zero customization and has no file-size logic of its own anywhere.

## Verify

```sh
# >1.5MB real source (~2.4MB, 60k lines) -> bigfile
python3 -c "print('\n'.join('local x%d = %d  -- padding padding padding' % (i,i) for i in range(60000)))" > /tmp/big.lua
# minified single line (~2.4MB, 1 line)  -> bigfile via BOTH criteria
python3 -c "import sys; sys.stdout.write('var a=1;'*300000)" > /tmp/min.js
# 60k short lines (~700KB)               -> NOT bigfile; the TS line guard trips instead
python3 -c "print('\n'.join('x%d = %d' % (i,i) for i in range(60000)))" > /tmp/many.py
```

In nvim: `:set ft?` → `bigfile` (plus a notification) on the first two,
`python` on the third; `:lua =vim.lsp.get_clients({bufnr=0})` → `{}` on a
bigfile; `:lua =vim.b.completion` → `false`; `:set foldmethod?` → `manual`.
