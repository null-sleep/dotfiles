# Git worktree helper for Neovim

**Status:** research / not started
**Date:** 2026-07-18

Goal: an easy way to create/switch/manage git worktrees without leaving
Neovim, instead of manually running `git worktree` in a shell and restarting
the editor per worktree.

---

## Option 0: just `cd` into the worktree and start a fresh `nvim`

The zero-dependency alternative: run `git worktree add ../feature-x
feature-x`, `cd ../feature-x`, `nvim`. Worth stating plainly since it's the
baseline every plugin below has to beat.

**What it gets right for free:**
- No plugin, no config, no failure surface — it's just `git worktree` +
  `cd`, both already muscle memory.
- Correct-by-construction cwd, LSP roots, and per-worktree state — a brand
  new nvim process means `lsp.lua`'s root detection, `session.lua`'s
  persistence keying, and any cwd-sensitive plugin all just work without
  needing to be told a worktree switch happened.
- No "stale state from the old worktree" class of bug — nothing carries
  over, because nothing is reused.

**What it costs, which is what every plugin above is buying back:**
- Loses your whole editor session: open buffers, window layout, undo
  history for unsaved changes, quickfix list, terminal buffers (this config
  runs toggleterm/sidekick panels — see `ai.lua`), any in-memory DAP
  breakpoints (see `plans/dap-breakpoint-persistence.md` — this is the same
  underlying "state doesn't survive a restart" problem, just triggered by a
  worktree change instead of a quit).
- No "same file, new worktree" continuity — you re-navigate to whatever
  file you were looking at by hand instead of the plugin re-opening it for
  you.
- Doesn't compose with the rest of the running instance — if you're mid-way
  through something in Neovim (a git operation in `gitui.lua`, an open
  sidekick agent session per `plans/sidekick-multi-claude-sessions.md`, an
  aerial outline pinned open), a plugin-driven switch can carry that
  forward or hook into it (`on_switch` callbacks); a fresh process can't.
- Worktree creation itself is still manual: figuring out the right sibling
  path, typing the full `git worktree add <path> <branch>` invocation,
  remembering existing-branch vs new-branch flags.

**Where this is the better call regardless of any plugin choice:** if a
worktree switch is rare (a few times a day) and usually coincides with
wanting a clean slate anyway (switching to review an unrelated PR, starting
a genuinely separate task), the fresh-process cost is arguably a feature,
not a downside — it forces exactly the state reset Option A/B's hooks
otherwise have to work hard to fake. The plugins below earn their keep when
worktree switches are frequent *and* you want to keep context (open
buffers, running LSP, a live sidekick session) across the switch.

---

## Option A: existing plugins

Compared against this config's actual picker: **snacks.nvim**, no
Telescope installed (`plugins.lua`/`picker.lua`).

### Juksuu/worktrees.nvim
- **Deps:** plenary.nvim required; telescope.nvim *and* snacks.nvim both
  optional.
- **Commands:** `:GitWorktreeCreate`, `:GitWorktreeCreateExisting` (from an
  existing branch), `:GitWorktreeSwitch`, `:GitWorktreeRemove`.
- **Buffer handling on switch:** tries to map the open file to the same
  path in the new worktree; configurable via `swap_current_buffer`.
- **Worktree location:** `worktree_path` option — default `..` (sibling of
  repo root), or `<worktree_path>/<projectname>/<folder>`.
- **Hooks:** `on_add`, `on_before_switch`, `on_switch`, `on_before_remove`,
  `on_remove`. README ships real recipes: swapping *all* open
  buffers/windows to the new worktree, and per-worktree sessions via
  `mini.sessions` (including stopping LSP clients before switching — a real
  pain point when hopping worktrees, and directly relevant to this config's
  rust-analyzer workspace-reload setup in `lsp.lua`).
- **Picker integration:** genuinely snacks-native — if snacks.nvim is
  installed, the picker UI itself ships in **snacks**
  (`Snacks.picker.worktrees()`, `worktrees_new()`, `worktrees_remove()`);
  this plugin supplies the create/switch/remove logic underneath it.
- **Logging:** file-based debug log with configurable level; README calls
  out a real bare-repo gotcha (`remote.origin.fetch` misconfigured) with a
  fix command.

### afonsofrancof/worktrees.nvim
- **Deps:** none beyond Neovim 0.11+ and git — no plenary, no telescope, no
  snacks requirement. Lightest footprint of the group.
- **Explicitly scope-frozen:** README states it's "feature complete" for
  create/delete/switch and won't grow much beyond that — deliberate, not
  neglect.
- **Commands:** `:WorktreeCreate`, `:WorktreeDelete`, `:WorktreeSwitch`,
  all interactive via `vim.ui.select`/`vim.fn.input`-style prompts — so it
  inherits whatever `vim.ui.select` provider is configured (snacks by
  default here).
- **Config:** `base_path` (where worktrees live relative to git common dir)
  + `path_template` (string or `function(branch)`), more flexible naming
  than Juksuu's.
- **Hooks:** simpler — `on_create(path)`, `on_delete(path)`,
  `on_switch(from, to)`. No before/after split.
- **Keymaps:** set directly via `opts.mappings` in setup.

### ThePrimeagen/git-worktree.nvim
- **Deps:** plenary.nvim required, telescope.nvim optional (Telescope-only
  UI — no snacks path).
- **Design assumption:** works best with a **bare repo** clone; non-bare
  works but branch selection is clunkier without Telescope.
- **API (Lua only, no `:Ex` commands):** `create_worktree(path, branch,
  upstream)`, `switch_worktree(path)`, `delete_worktree(path)`.
- **Config:** most granular of the simple plugins —
  `change_directory_command` (`cd` vs `tcd`, tab-local cwd),
  `update_on_change`/`update_on_change_command`, `clearjumps_on_change`,
  `autopush` (push+rebase on create).
- **Hooks:** single `on_tree_change(op, metadata)` with an `Operations`
  enum (Switch/Create/Delete) — coarser than Juksuu's, simplest to reason
  about; README pitches chaining into harpoon-style workflows.
- **Telescope UI:** `<Enter>` switch, `<c-d>` delete, `<c-f>` toggle
  force-delete — delete is built into the picker itself.
- Oldest/most established (ThePrimeagen), but the least actively
  maintained-looking docs of the group (placeholder Known Issues section,
  no stated Neovim version floor).

### Mohanbarman/g-worktree.nvim
- **Deps:** none beyond Telescope optionally.
- **Config:** `base_dir_pattern` templated string
  (`../{git_dir_name}-wt/{branch_name}`), repo-name-aware by default.
- **Distinct feature:** `post_create_cmd` — runs an arbitrary Vim command
  after creating a worktree (default `Explore .`) — none of the others
  auto-run a post-create UI action.
- **API:** branch-name-keyed (`create_worktree('<BRANCH_NAME>')`) rather
  than path-keyed like ThePrimeagen's.
- Thinnest README of the group — no hooks, no logging, no stated Neovim
  version requirement. Reads as the least mature/maintained option.

### mitubaEX/git_worktree.nvim
- **Deps:** hard Telescope requirement, no picker alternative.
- By far the most feature-heavy: `:GitWorktreeReview <pr_number>` creates a
  worktree straight from a GitHub PR via `gh` CLI (handles forks),
  `:GitWorktreeCleanup`/`:GitWorktreeForceCleanup` for bulk-removing
  worktrees, `.worktreeinclude` file to auto-copy gitignored/env files
  (`.envrc`, `.vscode`, etc.) into every new worktree, smart branch
  detection (existing local/remote/new/`--from-default`), and an actual
  CI-run test suite (plenary busted-style).
- **Buffer handling:** `cleanup_buffers`, `warn_unsaved`, `update_buffers`
  — most explicit/configurable of the group.
- **Worktree layout:** centralizes all worktrees under one `.worktrees/`
  dir (or a shared absolute path across repos), vs. the sibling-directory
  convention the others default to.
- Trade-off: heaviest plugin, hard Telescope dependency, and its own README
  install snippet still says `yourusername/git_worktree.nvim` — a sign it
  may be less polished than its feature list suggests.

---

## Comparison at a glance

| Approach | Deps | Picker fit (snacks, no Telescope) | Keeps session state across switch | Effort to adopt |
|---|---|---|---|---|
| `cd` + fresh `nvim` | none | n/a | no | none (already works) |
| Juksuu/worktrees.nvim | plenary (+ snacks optional) | native | yes, via hooks | low |
| afonsofrancof/worktrees.nvim | none | via `vim.ui.select` | yes, via hooks | low |
| ThePrimeagen/git-worktree.nvim | plenary (+ telescope optional) | none (Telescope-only) | yes, via single hook | medium (Telescope dep) |
| Mohanbarman/g-worktree.nvim | none (+ telescope optional) | none (Telescope-only) | no hooks | low, but thin docs |
| mitubaEX/git_worktree.nvim | telescope (hard) | none (Telescope-only) | yes, most configurable | medium (Telescope dep, heaviest feature set) |

---

## Recommendation

Ruled out on picker-fit grounds: ThePrimeagen's and mitubaEX's (hard
Telescope dependency), and g-worktree.nvim (Telescope-oriented, thin docs,
no hooks).

Down to three real choices:

1. **Do nothing — keep `cd` + fresh `nvim`.** Right call if worktree
   switches stay infrequent; see Option 0 above for why the "cost" is
   partly a feature.
2. **Juksuu/worktrees.nvim** — if switches become frequent enough to want
   in-place continuity: genuinely snacks-native picker, richest hooks
   (before/after switch + session-restore recipe using `mini.sessions` +
   LSP client stop, which maps directly onto `lsp.lua`'s rust-analyzer
   workspace-reload logic).
3. **afonsofrancof/worktrees.nvim** — if the same continuity is wanted with
   the smallest possible dependency addition (zero deps, `vim.ui.select`-
   driven so it rides on snacks automatically without a dedicated
   integration).

---

## Open questions / decisions for later

1. Is worktree-switch frequency actually high enough to justify a plugin,
   or does Option 0 cover the real workflow?
2. If a plugin: Juksuu (richer hooks, snacks-native picker) vs.
   afonsofrancof (zero deps, scope-frozen)?
3. If adopted, does it warrant a session-restore hook similar to the
   `mini.sessions` recipe in Juksuu's README, given this config already
   uses `persistence.nvim` for sessions (`session.lua`)?
4. Worktree path convention to standardize on: sibling directory (`..`,
   the default for most of these) vs. a centralized `.worktrees/` dir
   (mitubaEX's model) — affects `.gitignore` needs if adopted manually
   without a plugin's help too.

---

## Sources

- worktrees.nvim (Juksuu) — https://github.com/Juksuu/worktrees.nvim
- worktrees.nvim (afonsofrancof) — https://github.com/afonsofrancof/worktrees.nvim
- git-worktree.nvim (ThePrimeagen) — https://github.com/ThePrimeagen/git-worktree.nvim
- g-worktree.nvim (Mohanbarman) — https://github.com/Mohanbarman/g-worktree.nvim
- git_worktree.nvim (mitubaEX) — https://github.com/mitubaEX/git_worktree.nvim
