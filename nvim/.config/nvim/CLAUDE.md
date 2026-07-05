# Neovim config notes for Claude

This is the nvim config subtree of a stow-managed dotfiles repo. `GUIDE.md`
in this directory is the maintained reference doc for the whole config —
read it before making non-trivial changes here.

## Update GUIDE.md in the same change

**Whenever you add a new lua module (a `require()` in `init.lua`) or a new
keymap, update `GUIDE.md` as part of that same change — not as a follow-up.**
This applies to your own edits and to any config change you make on the
user's behalf. Concretely:

- New module → add its `Architecture` file-responsibilities row and, if it's
  `require()`d from `init.lua`, extend the `Load order` line. Give it a Part 2
  section too if it has keymaps or behavior worth explaining (see below) —
  a bare Architecture row is not enough on its own for anything with a keymap.
- New keymap → add it to the right table per "Where new content lands" below,
  and never leave a keymap undocumented.
- Renamed/removed module or keymap → update the same spots, and grep for
  stale references (`grep -rn 'GUIDE.md' lua/` catches section-title refs;
  grep the key/module name itself for prose mentions elsewhere in the guide).

This guide went stale before (three modules and a handful of keymaps had no
documented home) precisely because updates landed in the code without a
matching GUIDE.md edit. Treat an undocumented file or keymap as an incomplete
change, the same way you'd treat a missing test.

## Maintaining `GUIDE.md`

`GUIDE.md` is organized in two tiers, each an H1:

- **Part 1: Essentials** — read-once concepts: `Architecture` (file
  responsibilities, load order), `Design Decisions` (the "why" behind
  non-obvious choices), `Keymap index` (orientation only — see below).
- **Part 2: Reference** — per-tool sections (LSP, Git, Rust, AI, ...), each
  owning its own keymap table, recipes, and troubleshooting notes.

### Where new content lands

- A new **concept / design rationale** → a new `###` subsection under
  `Design Decisions`.
- A new **global keymap** (no natural feature-section home) → the
  `Keymap index` → *Global keymaps* table, plus a row in the *By prefix*
  orientation table if it starts a new prefix family.
- A new **feature-specific keymap** → the keymap table inside that
  feature's own Part 2 section, next to the prose explaining it — **not**
  the Keymap index. Add a *By prefix* orientation row pointing there.
- A new **tool/module** → its own Part 2 `##` section, a row in the
  `Architecture` file-responsibilities table, and a `Load order` update if
  it's a new `require()` in `init.lua`.
- A new **"how do I add an X"** recipe (LSP server, formatter, theme,
  neotest adapter) → lives beside its tool's Part 2 section, not in a
  separate recipes bucket — locality over categorization.

### Keymap ownership rule

**Never document the same key in two tables.** Feature-specific keys are
canonical in their Part 2 section (the prose there usually explains a
gotcha the key alone doesn't convey — e.g. why `<leader>dR` differs from
`<F5>` for a cold start). The `Keymap index` is an index: a *By prefix*
table (prefix → purpose → defining file → link) plus a *Global keymaps*
table for keys that have no feature section to live in. If you're about to
add a key to both places, stop — it belongs in exactly one.

### Section titles are grep anchors

Code comments reference `GUIDE.md` sections by exact title text, e.g.
`lua/session.lua` → `See GUIDE.md "Synthetic sidebar buffers can't be
session-serialized"` and `lua/plugins.lua` → `See GUIDE.md "Design
Decisions"`. Before renaming any heading, run:

```
grep -rn 'GUIDE.md' lua/
```

and update every match. This is a plain-text convention (comments, not
markdown links), so a title rename breaks it silently otherwise.

### Anchor-link hygiene

The `## Contents` TOC and cross-references use markdown anchor links
(`[Git (Neogit)](#git-neogit)`). Headings with parentheses, dots, slashes,
or `+` slugify inconsistently across renderers (GitHub, Typora, nvim) —
e.g. `Window/tab title` slugs to `windowtab-title` on GitHub (slash
dropped, no hyphen inserted), not the more intuitive `window-tab-title`.
For any heading with punctuation beyond plain hyphens, add an explicit
anchor immediately above it and link the TOC to that instead of trusting
the auto-slug:

```markdown
<a id="git-neogit"></a>
## Git (Neogit)
```

Plain-word headings (`Architecture`, `Themes`, `Format-on-save`) don't need
this — their auto-slugs are unambiguous.

### No collapsible `<details>`

`render-markdown.nvim` does not collapse `<details>`/`<summary>` blocks —
they render as inert/broken markup in-editor, even though they work fine on
GitHub. Use headings + native folding (`zc`/`zo` in nvim, the outline panel
in Typora) as the portable equivalent instead.

### Notation

Use `<leader>`, never `<Space>` — `vim.g.mapleader` is set to `' '` in
`init.lua`, so they're the same physical key. Mixing both in the same
document is confusing when tables sit side by side.

### Keep in sync when editing

- The `## Contents` TOC, when adding/removing a top-level section.
- The `Architecture` file-responsibilities table and `Load order` line,
  when adding/removing a module `require()`d from `init.lua`.
- `README.md` at the repo root, which has its own overlapping keymap/prefix
  tables (currently using `<Space>` notation) — check it for parity when a
  keymap documented there changes. Not automated; check by hand.
- The top disclaimer ("this guide may be outdated, the code is truth") —
  keep it; don't let this doc imply more authority than the source.

### Other recurring conventions this config follows

- **Topic files avoid shadowing a plugin's own Lua module name** — e.g.
  `gitui.lua` (not `neogit.lua`, since Neogit's own module is `neogit`),
  `outline.lua` (not `aerial.lua`), `debugging.lua` (not `dap.lua`),
  `filetree.lua` (not `nvim-tree.lua`). Follow this pattern for new
  wrapper files.
- Commit `nvim-pack-lock.json` after updating plugins (pins versions
  across machines).
- Commit `spell/en.utf-8.add` after adding personal-dictionary words.
- Every keymap should have a `desc` string (surfaces in which-key and the
  `<leader>sk` fuzzy picker).
- `rust` must `require()` before `testing` in `init.lua` — `testing.lua`
  needs `rustaceanvim.neotest` on the runtimepath.
