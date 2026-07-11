# nvim-tree Reveal Mode

## Current goal (revised 2026-07-11)

Match what VS Code (`explorer.autoReveal`) and Zed (`project_panel.auto_reveal_entries`)
actually do: on switching buffers, expand the ancestor directories of the
active file (if not already expanded) and scroll it into view — **without**
collapsing anything else currently expanded elsewhere in the tree.

This replaces the original goal (auto-collapsing siblings on every switch),
which turned out to be based on a mistaken premise about what those editors
do — see "Superseded goal" below for the full history.

## Status: already implemented, no change needed

`nvim/.config/nvim/lua/filetree.lua`'s existing `update_focused_file = { enable = true }`
already delivers exactly this behavior. Confirmed by reading the installed
plugin source (`~/.local/share/nvim/site/pack/core/opt/nvim-tree.lua`,
2026-07-11):

- **Trigger**: a single debounced `BufEnter` autocmd (`lua/nvim-tree/autocmd.lua:60-72`),
  debounce delay defaults to 15ms (`view.debounce_delay`, `config.lua:57`).
- **Only expands, never collapses**: the reveal logic in
  `lua/nvim-tree/actions/finders/find-file.lua:62-74` sets `dir.open = true`
  for every ancestor directory of the target file and lazily loads its
  children if unread. There is no `open = false` / close / collapse call
  anywhere in that function — directories expanded elsewhere in the tree are
  left untouched. The plugin's own doc string confirms this: "Update the
  focused file on `BufEnter`, uncollapsing folders recursively"
  (`doc/nvim-tree-lua.txt:1467`).
- **Scrolls into view, doesn't force-center**: after redraw, `view.set_cursor({line, 0})`
  (`find-file.lua:87-90`) moves the tree window's cursor, so Neovim scrolls
  the minimum needed to bring the line into view (respecting `scrolloff`).
  Centering only happens if `view.centralize_selection = true`, which
  defaults `false` and isn't set here — matching VS Code's scroll-into-view
  (not always-centered) behavior.
- **Self-guarding, no `is_special()` needed**: `find-file.lua:22-25` bails via
  `vim.uv.fs_realpath(path)` returning `nil` for any buffer without a real
  on-disk path — covers the tree's own buffer, terminals, Neogit, prompts,
  etc. automatically. Unlike code-only keymaps elsewhere in this config, this
  feature does not need `require('buffers').is_special()` — don't add it.
- **`update_root` is off, correctly**: left at its default `false`
  (`doc/nvim-tree-lua.txt:1477-1484`). Enabling it would re-root the tree
  when opening files outside the current cwd — more aggressive than reveal,
  and not part of the VS Code/Zed behavior being matched.

**Conclusion:** no code change required. If this ever needs documenting
properly (per this repo's nvim `CLAUDE.md` conventions), the one-line summary
for `GUIDE.md`'s Design Decisions is: *"nvim-tree reveals the active buffer on
every switch — expands ancestor directories and scrolls it into view, without
collapsing anything else that's open (VS Code `explorer.autoReveal` / Zed
`auto_reveal_entries` parity). Auto-collapsing siblings is intentionally not
done, matching both editors."*

## Follow-ups

- [x] Write up the reveal behavior in `GUIDE.md`'s Design Decisions section —
      done: "Reveal mode expands, never collapses", plus a Features bullet
      for `highlight_opened_files`.
- [ ] Revisit the open-buffer highlight color. `ColorColumn` (current) works
      and is visible, but doesn't match the active theme's own accent color.
      A per-theme accent-blend approach was prototyped (blend `Title`'s fg
      into `NvimTreeNormal`'s bg at ~25%) and confirmed working, then reverted
      at the user's request to keep iterating later — see
      `nvim/.config/nvim/lua/themes.lua`'s `NvimTreeOpenedHL` override for the
      current state.

---

## Superseded goal: auto-collapse siblings on every switch

The rest of this document is kept for history — it explored a different,
more aggressive behavior before research revealed neither VS Code nor Zed
actually do it (see "External research" below). Not being pursued.

### Idea

When switching buffers, the file tree should show only the path to the active file —
all sibling folders and unrelated top-level directories are collapsed. Believed at
the time to be Zed's file tree behavior — **this belief was wrong, see External
research.**

Example: with `securitymaster/institution/utils/ingestor.go` open, the tree shows:

```
▾ securitymaster/
  ▾ institution/
    ▾ utils/
        ingestor.go   ← active
```

Everything else at the top level is collapsed. Siblings within `utils/` are still
visible (unavoidable — expanding a directory node always shows all its children).

### Why nvim-tree can't do this natively

`api.tree.find_file` reveals a file by expanding its parent chain, but has no way
to simultaneously collapse all other nodes. There's no "collapse siblings" API.
`collapse_all` + `find_file` collapses everything then re-expands the path, which
is the right shape but causes flicker and doesn't suppress siblings.

### Options explored

#### Option A: Autocmd approximation (nvim-tree) — verified feasible, not pursued

On `BufEnter` for real file buffers (skip the tree buffer itself, special/panel
buffers, and buffers with no backing file):
1. `api.tree.collapse_all()`
2. `api.tree.find_file({ buf = ev.buf })`

Verified against the installed nvim-tree source (commit `cf18a66`, 2026-07-10):
- `collapse_all` sets every dir node closed and redraws once; it does **not**
  call `nvim_set_current_win`, so it never steals focus from a code window.
- `find_file` only opens directories that are path-prefixes of the target file
  (`vim.startswith(path_real, node.absolute_path .. sep)`), and also never
  moves window focus (`opts.focus` defaults `false`).
- `api.events` has no buffer-focus event — the built-in `update_focused_file`
  is itself just a debounced `BufEnter` autocmd wrapping `find_file`. There is
  no "collapse siblings only" primitive anywhere in the public API; composing
  these two calls is the only shape that doesn't reach into plugin internals.

Implementation notes (for reference, if ever revisited):
- Disable the built-in `update_focused_file` (`enable = false`) and replace it
  with a single owned `BufEnter` autocmd doing both calls — running both
  simultaneously double-fires the reveal and causes a visible
  collapse→re-expand flicker (the built-in follow debounces ~15ms after yours
  runs).
- Guard the autocmd: skip `api.tree.is_tree_buf(buf)`,
  `require('buffers').is_special(buf)`, `vim.bo[buf].buftype ~= ''`, and
  buffers with no file on disk (`vim.uv.fs_stat(name) == nil`) — otherwise
  entering a terminal/Neogit/prompt buffer collapses the whole tree with
  nothing to reveal.
- Debounce per-buffer (mirror the plugin's own ~15ms) to avoid a
  collapse+redraw storm on rapid `:bnext` or the `L` vsplit-preview keymap.
- Tree-focused manual browsing (expanding folders with `l` while inside the
  sidebar) is untouched — the autocmd only fires on entering a *different*
  buffer.

Pros: no new plugin, built entirely on public `api.tree.*` calls (no reliance
on internal modules), preserves focus in both directions.
Cons: two redraws per switch (collapse then reveal) — minor, usually
coalesced into one repaint per Neovim tick; siblings within the active file's
own directory remain visible; the debounce/guard glue code was never actually
written or tested; zero prior art means unknown edge cases (quickfix
navigation, Telescope preview buffers, etc.).

#### Option B: Custom renderer / node filter

nvim-tree exposes a `filters` API but it operates on filenames/patterns, not on
"is this file in the active buffer's ancestry." Would need a custom filter function
that walks the active buffer path and hides nodes not on that path. Not currently
exposed as a public API — would require internal module access (fragile).

#### Option C: Switch to mini.files

`mini.files` opens as a floating panel showing one directory at a time (ranger-style).
Naturally shows only the current directory contents. Not a persistent sidebar, but
the "only see relevant files" goal is met differently.

Cons: no persistent sidebar; different mental model; floating UI doesn't suit all
workflows.

#### Option D: Build a custom tree plugin / thin wrapper

A minimal sidebar that:
- Renders only the ancestry path of the active buffer as a tree
- On cursor movement, lazily loads children of the hovered node
- Collapses everything else on buffer switch

This would be a new plugin. Significant effort but would be the only way to get
true solo mode in a persistent sidebar.

### External research

Searched for existing prior art before committing to a build (2026-07-11):

- **nvim-tree.lua**: no issue/discussion proposes this exact behavior.
  [Discussion #2911](https://github.com/nvim-tree/nvim-tree.lua/discussions/2911)
  covers reveal-only (`update_focused_file`), not sibling-collapse. This is an
  open gap, not a documented option you're missing.
- **neo-tree.nvim**: `filesystem.follow_current_file.enabled` reveals/highlights
  only, no `collapse_others`-style key. **mini.files**: has `Reset` (`<BS>`) to
  manually collapse back to the anchor dir, but nothing automatic on file
  switch, and it's a Miller-columns browser, not a persistent tree anyway.
  **oil.nvim**: single-directory view, not applicable.
- No community gist/dotfiles snippet found implementing "collapse_all +
  find_file on BufEnter" — this would have been the first to publish this
  specific combo, for better or worse (no prior art to diff a design against,
  but also no known gotchas someone else already hit and wrote up).
- **VS Code** (`explorer.autoReveal`): only expands/scrolls to the active file;
  never auto-collapses siblings. Auto-collapse-on-switch is an open,
  unimplemented request — [microsoft/vscode#150869](https://github.com/microsoft/vscode/issues/150869).
- **Zed** (`project_panel.auto_reveal_entries`, `auto_fold_dirs`): same —
  reveal/scroll only; `auto_fold_dirs` visually merges single-child directory
  chains, a different feature. Sibling-collapse is an open discussion, not
  shipped — [zed-industries/zed#6668](https://github.com/zed-industries/zed/discussions/6668),
  [zed-industries/zed#17136](https://github.com/zed-industries/zed/issues/17136).

**Implication:** the collapse-siblings behavior isn't "catching up" to a
feature every other editor has — it's a genuinely novel workflow with no
reference implementation anywhere. That's why the current goal (above) was
revised to match what VS Code/Zed actually do instead, which turned out to
already be implemented in this config.

### Decision: closed, superseded

Not pursuing sibling auto-collapse. `update_focused_file = { enable = true }`
already matches actual VS Code/Zed behavior — see "Current goal" at the top of
this document. Options A–D above are kept for reference only, in case the
always-collapse behavior is wanted again in the future despite no editor
shipping it.
