# dotfiles

Stow-managed dotfiles repo. Stow packages: nvim, zsh, ghostty, macos, rcmd,
zellij, claude, cursor, yknotify, ripgrep. NOT stow packages: `plans/` (design/feature
planning docs), `fixtures/` (per-language demo files for testing editor
features), `docs/` (standalone learn-it reference guides, e.g.
`docs/ripgrep.md` — distinct from `plans/`, which is design docs).
`README.md` is the maintained setup/reference doc for the whole repo.

Editing something under `nvim/.config/nvim/`? See the nested
`nvim/.config/nvim/CLAUDE.md` for how this repo maintains `GUIDE.md` (the
nvim config's reference doc) — read it before adding to `GUIDE.md` or
renaming any of its sections. That file follows the same shape as this one.

## Update README.md in the same change

**Whenever you add a new stow package, tool, or app to this repo — or change
an existing one's setup steps — update `README.md` as part of that same
change, not as a follow-up.** This applies to your own edits and to any repo
change you make on the user's behalf. Concretely:

- New package/tool/app → a new `## ` Part 2 section, a `## Contents` entry
  under the right category, and a `## Quick start` step/link if it's part of
  the fresh-machine bootstrap path.
- Existing setup step changes (a new flag, a renamed command, a moved file)
  → update it in place; no new heading needed.
- Renamed/removed section → update the same spots, and grep the repo for
  stale references before renaming a heading (see "Heading titles are grep
  anchors" below).

Treat an undocumented addition as an incomplete change, the same way you'd
treat a missing test — this is the rule that would have caught `README.md`
drifting stale against the nvim config before this reorg (see below).

## Maintaining README.md

`README.md` is organized in two tiers, each an H1:

- **Part 1: Essentials** — the read-once, machine-bootstrap spine: Quick
  start, Fonts, Setup, Stow, Verify your setup, Languages.
- **Part 2: Reference** — one `## ` section per tool/app, grouped by category
  in the `## Contents` TOC (AI & Claude tooling, Editors, Terminals &
  multiplexing, Shell, Version control, Optional/utilities).

### Where new content lands

- A new **tool/package/app** → its own Part 2 `## ` section + a Contents
  entry under the matching category (+ a Quick-start link if it's on the
  fresh-machine path).
- A **setup-step change** to an existing tool → edit that section in place;
  don't create a new heading for it.
- A **repo-wide mechanic** (how stow works, how to add a config) → Part 1,
  next to `Setup`/`Stow`, not buried in a per-tool section.

### Ownership rule: README vs GUIDE.md

**README owns setup/install/machine-config; `nvim/.config/nvim/GUIDE.md` owns
nvim keymaps and features.** This boundary just fixed a real problem: README's
old `## Neo Vim` section was a ~575-line stale, notation-mismatched parallel
copy of what GUIDE.md already documented properly, and it contained actual
bugs (wrong keys), not just cosmetic drift. Don't let it re-accumulate:

- A new nvim **keymap** is documented in GUIDE.md, never back in README.
- A new nvim **setup step** (installing a binary, symlinking a config file,
  a one-time system config like the GPG/YubiKey pinentry setup) belongs in
  README's `## Neovim` section — GUIDE.md doesn't cover machine-level setup.
- If you're tempted to add a keymap table to README, it belongs in GUIDE.md
  instead; link to it rather than duplicating.

### Heading titles are grep anchors

Some headings are referenced by exact title text from other files in this
repo:
- `## Claude Code` ← `claude/.claude/skills/nvim-theme-to-claude/SKILL.md`
- `### Format-on-save tools` ← `nvim/.config/nvim/GUIDE.md`

Grep the repo before renaming any heading (`grep -rn '<heading text>' .`) and
update every match. This is a plain-text convention (comments/prose, not
markdown links), so a rename breaks it silently otherwise.

### Anchor-link hygiene

Same rule as the nested nvim `CLAUDE.md`: headings with parentheses, dots,
slashes, or `+` slugify inconsistently across renderers (GitHub, Typora, nvim
render-markdown). For any such heading, add an explicit anchor immediately
above it and link the `## Contents` TOC to that instead of trusting the
auto-slug:

```markdown
<a id="rtk-token-optimizer"></a>
### rtk — token optimizer
```

Plain-word headings don't need this — their auto-slugs are unambiguous.

### No collapsible `<details>`

`render-markdown.nvim` doesn't collapse `<details>`/`<summary>` blocks —
README is read in the same tools as GUIDE.md (nvim, Typora). Use headings +
native folding instead.

### Tables vs. bullet lists

Tables work well for short, uniform cells (file → symlink method, plugin →
binary → install command). Don't force a column into a table when it holds
long, variable-length prose (a paragraph-per-row description) — both
`render-markdown.nvim` and GitHub wrap/misalign long cells badly. Use a
bullet list instead (`- **item** — description`). See
`nvim/.config/nvim/GUIDE.md`'s `Architecture` → `File responsibilities` list
for the pattern this replaced a table with.

**No emoji in table cells.** `render-markdown.nvim` renders emoji (✅/❌ and
other status glyphs) at a variable width, which knocks the whole column off
the monospace grid so cells stop lining up with their rows — this bit the
`plans/telescope-vs-snacks-picker.md` comparison table. For status/boolean
columns use plain text (`yes`/`no`), and put any footnote markers in the
label column as `[1]`, `[2]`… — never in the status cells — so those cells
stay uniform-width. Applies to every doc read through render-markdown
(README, `plans/`, GUIDE.md), not just README.

### Notation

If README ever needs to mention an nvim keymap, use `<leader>`, not
`<Space>` (same physical key, matches GUIDE.md's house style) — this should
be rare now that README no longer carries its own keymap tables.

### Keep in sync when editing

- The `## Contents` TOC, when adding/removing/renaming a top-level section.
- `## Quick start`'s numbered steps and inline links, if a Part 1 section's
  flow changes.
