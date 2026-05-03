# nvim-tree Solo/Reveal Mode

## Idea

When switching buffers, the file tree should show only the path to the active file —
all sibling folders and unrelated top-level directories are collapsed. Like Zed's
file tree behavior.

Example: with `securitymaster/institution/utils/ingestor.go` open, the tree shows:

```
▾ securitymaster/
  ▾ institution/
    ▾ utils/
        ingestor.go   ← active
```

Everything else at the top level is collapsed. Siblings within `utils/` are still
visible (unavoidable — expanding a directory node always shows all its children).

## Why nvim-tree can't do this natively

`api.tree.find_file` reveals a file by expanding its parent chain, but has no way
to simultaneously collapse all other nodes. There's no "collapse siblings" API.
`collapse_all` + `find_file` collapses everything then re-expands the path, which
is the right shape but causes flicker and doesn't suppress siblings.

## Options to explore

### Option A: Autocmd approximation (nvim-tree)

On `BufEnter` for non-tree buffers:
1. `api.tree.collapse_all()`
2. `api.tree.find_file({ open = true, focus = false })`

Pros: no new plugin, works today
Cons: siblings in the same directory are still visible; minor flicker on fast buffer
switching; `update_focused_file` may conflict

### Option B: Custom renderer / node filter

nvim-tree exposes a `filters` API but it operates on filenames/patterns, not on
"is this file in the active buffer's ancestry." Would need a custom filter function
that walks the active buffer path and hides nodes not on that path. Not currently
exposed as a public API — would require internal module access (fragile).

### Option C: Switch to mini.files

`mini.files` opens as a floating panel showing one directory at a time (ranger-style).
Naturally shows only the current directory contents. Not a persistent sidebar, but
the "only see relevant files" goal is met differently.

Cons: no persistent sidebar; different mental model; floating UI doesn't suit all
workflows.

### Option D: Build a custom tree plugin / thin wrapper

A minimal sidebar that:
- Renders only the ancestry path of the active buffer as a tree
- On cursor movement, lazily loads children of the hovered node
- Collapses everything else on buffer switch

This would be a new plugin. Significant effort but would be the only way to get
true solo mode in a persistent sidebar.

## Decision pending

None of the existing plugins nail this. Option A is low-effort and worth trying
first to see if the sibling-visibility limitation is tolerable in practice. If it
is, ship it. If siblings are still too noisy, revisit Option D or accept the
limitation and close this out.
