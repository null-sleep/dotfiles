# Dotfiles review remediation plan

## Context

A 4-agent comprehensive review of the dotfiles repo produced ~50 verified findings
(correctness bugs, packaging problems, doc drift, cruft). A Plan agent drafted
per-issue fixes; each was then critiqued and re-derived — verdicts below marked
**endorsed** (agree with draft), **revised** (critique changed the solution), or
**won't-fix** (deliberately skipped, with reason). Facts spot-verified against the
repo: `utils.has_ui()` exists (utils.lua:10), visual-paste house pattern is `"_dP`
(keymaps.lua:69), `<leader>sa` is unbound repo-wide, work machines use a *real*
`~/.zshrc_bitgo.zsh` (README:932) so committing the ignore file breaks nothing,
this machine has no bitgo symlink and no loaded yknotify agent.

Ordering: correctness → packaging → docs → cruft. Conventional commits, one
logical change each (map at end).

**Execution directives (user):** work autonomously through the commit
sequence, committing as each logical change completes — do NOT batch into one
commit. FIRST action: write this plan to `plans/dotfiles-review-remediation.md`
(commit 0). STOP and check with the user before starting the Verification
section.

---

## Part 1 — nvim correctness

### B1. Tab-accept calls nonexistent API — `lua/completion.lua:12-20` [endorsed]
`vim.lsp.inline_completion.accept()` doesn't exist in 0.12.4; `get()` applies the
completion and returns whether one existed. Replace the middle Tab step with:
```lua
function()
  if vim.lsp.inline_completion.is_enabled({ bufnr = 0 })
     and vim.lsp.inline_completion.get() then
    return true
  end
end,
```
Keep the Tab-priority comment (still valid).

### B2. Keymap conflicts — USER DECIDED: terminals move to `<leader>T`
Conflicts: `<leader>sb` (keymaps.lua:13 fuzzy alias silently overwrote
outline.lua:178 aerial), `<leader>tb` (git.lua:47 buffer-local blame shadows
terminal.lua:167 bottom terminal), `<leader>th` (lsp.lua:129 buffer-local
hover-hold shadows terminal.lua:154 horizontal terminal).

User choices (all confirmed):
- Terminals → `<leader>T` prefix (verified free repo-wide): `Tt` float,
  `Th` horizontal, `Tv` vertical, `Tb` bottom panel (`terminal.lua:153-167`).
- Blame toggle KEEPS `<leader>tb` (git.lua unchanged); hover-hold KEEPS
  `<leader>th` (lsp.lua unchanged) — matches what user's fingers get today.
- Aerial Telescope picker binding (`outline.lua:178`): DELETE (redundant with
  the enhanced document picker + `<leader>o` sidebar + `<leader>O` popup;
  `:Telescope aerial` stays typeable). `<leader>sb` stays the fuzzy alias.
- Document symbols picker: re-key `<leader>sS` → `<leader>sd` (kills the
  annoying capital chord; pairs with `ss` workspace) AND enhance it — see
  B2-ENH below.

Companion edits in the SAME commit (nvim CLAUDE.md rule):
- `lua/terminal.lua:153-167` — Tt/Th/Tv/Tb; grep terminal.lua prose/comments
  for old keys.
- `lua/keymaps.lua:18` — `<leader>sS` → `<leader>sd`.
- `lua/whichkey.lua:78` — `['<leader>tb']` keywords become blame keywords; add
  `['<leader>Tb']` terminal-bottom keywords; line 81 `['<leader>sb']`
  keywords become buffer-fuzzy; remove/repoint aerial-picker entry. Check
  whichkey group defs for `<leader>T` ('Terminal') and `<leader>t` ('Toggle').
- `GUIDE.md` — terminal section keymap table (~970-1011) → `T*` keys; line ~55
  Architecture bullet (drop picker mention), ~730 outline table row (remove
  picker row), symbol-picker rows `sS` → `sd`, Git blame + LSP hover-hold
  rows (keys unchanged; scrub any shadowing prose); By-prefix rows: new
  `<leader>T` family, `<leader>t` cleanup.

### B2-ENH. Symbol picker enhancements — `lua/pickers/symbols.lua`
USER REQUESTED (grew out of the sb/aerial comparison; `ss` consistency added).

**document() (`<leader>sd`)** — lift aerial's two telescope-extension
techniques (read at
`~/.local/share/nvim/site/pack/core/opt/aerial.nvim/lua/telescope/_extensions/aerial.lua`):
1. **Syntax-highlighted source-line column**: new trailing `{ remaining = true }`
   display column showing the symbol's buffer line (`nvim_buf_get_lines`,
   trimmed), highlighted via a treesitter highlights-query pass over the
   buffer (aerial ext lines 74-114: collect once per open, offset-shift the
   ranges into the display column). Column order: icon | name(30, truncates) |
   kind(12) | lnum | source line. Graceful degradation: no parser → plain text.
2. **Open at cursor symbol**: compute `default_selection_index` = entry whose
   range encloses/is closest to the cursor line (aerial ext lines 179-196
   pattern, adapted to LSP symbol ranges).

**workspace() (`<leader>ss`) — match sd's look** (currently icon | name |
[client] | relpath, no kind/lnum/source-line):
1. Add the **kind label column** (shared KIND_WIDTH constant already exists).
   Whether kind also joins the match text is an implementation call — must
   not break `first_token_sorter()` / `name_match_highlights` semantics
   (they assume ordinal = bare name; see symbols.lua:418-462).
2. Merge location into one Comment-styled cell `relpath:lnum`.
3. Add the **source-line trailing column, lazily**: telescope calls
   `entry.display` only for visible rows, so read the line on demand with a
   per-file cache — `vim.fn.readfile(file, '', lnum)` reads only the first
   lnum lines; if the file is already a loaded buffer use its lines +
   treesitter highlights (same helper as document()); unloaded files render
   the line plain. Cache lives for the picker's lifetime.
4. **No cursor preselect** — the finder is dynamic/query-driven
   (finders.new_dynamic); there is no static list to preselect in. Not a gap.

Shared: extract the line-fetch + highlight helper once, used by both pickers.
Own commit, after the B2 re-key: `feat(nvim): source-line column in symbol
pickers, cursor preselect in sd, kind column in ss`.

### B3. Theme picker cancel restores wrong variant — `lua/pickers/theme.lua:61,104-112` [endorsed]
Snapshot `require('themes').active` (virtual variant, source of truth) instead of
`vim.g.colors_name`; restore via `themes.apply(original)`; drop the manual
`vim.o.background` save/restore (apply owns background).

### B4. Neovide Cmd+V redoes in n/v — `lua/neovide.lua:32` [endorsed]
```lua
vim.keymap.set('n', '<D-v>', '"+p',            { desc = 'Paste' })
vim.keymap.set('v', '<D-v>', '"_d"+P',         { desc = 'Paste over selection' })
vim.keymap.set({ 'i', 'c' }, '<D-v>', '<C-r>+', { desc = 'Paste' })
```
Visual variant matches the `"_dP` house pattern (keymaps.lua:69) but pastes from
`+`. Terminal mapping (line 33) unchanged.

### B5. Deprecated `gs.undo_stage_hunk` — `lua/git.lua:44` [endorsed; USER CONFIRMED]
Remove the `<leader>hu` mapping (upstream: `stage_hunk` now toggles; keeping the
key would silently change semantics). Update `<leader>hs` desc to
`'Git hunk: Stage/unstage (toggle)'` + comment; update GUIDE Git hunk table.

### B6. Group-less autocmds [endorsed]
Add per-file augroups with `clear = true` (match configs.lua:41 style):
`ai.lua:63,79` → `UserSidekick`; `git.lua:57` → `UserGitEditor`;
`terminal.lua:130` → `UserTermKeymaps`; `session.lua:31` → `UserSessionSave`.

### B7. `utils.check_nvim_update` — `lua/utils.lua:31-52` [endorsed, one revision]
Rewrite with: (1) skip when headless (`M.has_ui()`) or under claude-nvim —
**use the same env guard plugins.lua:107 uses** (verify exact var name at
implementation, don't assume `CLAUDE_NVIM == '1'`); (2) 24h debounce via stamp
file in `stdpath('cache')`, written *before* the async call; (3)
`vim.tbl_get(info, 'formulae', 1, 'versions', 'stable')` guard; (4)
`vim.version.parse` + `vim.version.cmp(latest, vim.version()) > 0` so local/dev
builds newer than brew never notify.

### B8. Low-priority nvim fixes [endorsed, except keybindings cache — deferred]
- `pickers/keybindings.lua:35,99` session cache — **DEFERRED (user decision):**
  do NOT change in this pass; user wants to think about it. Listed under
  Follow-ups below.
- `keymaps.lua:29-41` — Esc float-closer: skip windows with `focusable == false`
  (spares satellite/treesitter-context floats).
- cursortab.nvim — purge: drop the exception in `plugins.lua:83`, remove the
  `nvim-pack-lock.json` entry; note `:lua vim.pack.del({'cursortab.nvim'})`
  one-time step in commit message. Own commit.
- `pickers/gitstatus.lua:35` — resolve git root from buffer dir like
  `yank.lua:43` (list-form `systemlist`, `-C dir`), fallback `getcwd()` for
  unnamed buffers. Fixes wrong-repo + shell-quoting in one line.
- `gitui.lua:91` — `vim.system({...}):wait(3000)`, timeout → existing warn path.
  No full async refactor (fallback-only path).
- `configs.lua:51-57` — `stop()` **and** `close()` the old timer before
  replacing; keep the `_G` slot (it's what survives re-source).
- `pickers/symbols.lua` — add minimal `nvim/.config/nvim/.stylua.toml`
  (2-space, AutoPreferSingle), run stylua on symbols.lua ONLY, review diff.
- Term-nav duplication — `utils.term_nav_keymaps(buf, { esc = false })` helper;
  terminal.lua passes `esc = true` (keeps its `<C-]>`/`<S-CR>` extras inline),
  ai.lua passes `esc = false` (Esc must reach the CLI).

## Part 2 — shell/zsh

- **C2 [endorsed]** `.zshrc_config.zsh:60` + `README.md:869` (same commit):
  dead `git.io/antigen` → `https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh`.
- **C3 [endorsed]** `.zshrc_bitgo.zsh:53`: `alias bga='$HOME/src/bitgo-admin/bin/bgadmin'`.
- **C4 [endorsed]** `.zshrc_bitgo.zsh:28,50`: gate `colima_check_and_start` +
  `yknotify_check` behind `/tmp/.bitgo-shell-checks-$UID` stamp (per-boot;
  periodic /tmp cleanup re-runs it occasionally — fine). Functions stay defined.
  Depends on A1/A2 for the new label name inside `yknotify_check`.
- **C5 [endorsed]** `.zshrc_config.zsh:145-153`: move `~/.local/bin` prepend to
  after homebrew/python/cargo; comment "last prepend wins".
- **C6 [endorsed]** delete the no-op `unalias git` + wrong comment (lines 57-58).
- **C7 [endorsed]** ulimit guard: skip when `unlimited`, then numeric compare.
- **C8 [revised — verify first]** `.zshrc_halp.zsh:7` mise double-activation:
  before dropping the explicit eval, CONFIRM the antigen omz mise plugin actually
  runs `mise activate` (reviewer said "likely"; plan asserted). If confirmed,
  drop the eval, leave a pointer comment; if not, keep eval and skip.
- **C9** — `gt` alias: add shadows-Graphite comment [endorsed].
  `theme` toggle: fall back `$(macos_appearance || macos_appearance_fast)` [endorsed].
  `claude-nvim:61`: validate variant slug `[[ $v =~ ^[A-Za-z0-9_-]+$ ]]` before
  lua interpolation ( `lua` subcommand at :65 is arbitrary-by-design, leave) [endorsed].
  Stale nvim-editor comment `.zshrc_config.zsh:178-185`: rewrite crediting
  flatten.nvim (pairs with README E2 fix) [endorsed].
  **eval-init caching: WON'T-FIX** (single-digit ms; staleness bugs on upgrade).

## Part 3 — claude package

- **D1 [endorsed — critique agrees with skipping lib.sh]** The dangerous
  duplication (light slug `catppuccin-latte` in `setup-theme.sh:17` +
  `theme:70`) crosses the stow boundary — a repo lib can't fix it. Add mutual
  `# KEEP IN SYNC:` comments at both sites. The 3-script jq boilerplate stays
  (extract at the 4th script — repo's own "third copy" rule, applied honestly:
  the scripts double as user docs). 
- **D2 [endorsed]** `setup-statusline.sh:22`: `// empty` + `${current:-<none>}`.
- **D3 [endorsed]** `statusline-command.sh`: move all state to
  `${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/` (prevcost, growth,
  cleanup stamp, month files, `find` cleanup); month-file rewrite via
  `mktemp "$MONTH_FILE.XXXXXX"` then `mv` (kills the concurrent-pane truncate race).

## Part 4 — packaging

### A1+A2. yknotify package rebuild [endorsed — full house-pattern alignment]
New layout:
```
yknotify/
  .local/bin/yknotify-watch          # was yknotify.sh at package root
  Library/LaunchAgents/com.dhruv.yknotify.plist   # was com.user.yknotify.plist
  setup-yknotify.sh                  # new, mirrors macos/setup-theme-follow.sh
  .stow-local-ignore                 # new: setup-yknotify\.sh
```
- Plist: copy macos plist shape — `/bin/zsh -c 'exec "$HOME/.local/bin/yknotify-watch"'`
  (portable `$HOME`), `RunAtLoad` + `KeepAlive`, `ThrottleInterval` 10, logs
  `/tmp/yknotify.{out,err}.log`, portability comment header.
- Script: resolve binaries via `command -v` with explicit `/opt/homebrew/bin` +
  `/usr/local/bin` probes (launchd PATH lacks brew; Intel support); hard-fail
  with a clear stderr message if missing (ThrottleInterval makes that a visible
  throttled error, not a silent hot loop); single `jq -r '.type'` per event.
- `setup-yknotify.sh`: clone of `macos/setup-theme-follow.sh` (symlink check →
  binary warnings → bootout+bootstrap with retry) + one legacy-migration line:
  `launchctl bootout "gui/$(id -u)/com.user.yknotify" 2>/dev/null || true`.
- README: delete the `sed __USER__` block + `launchctl load/start`; rewrite
  section (see E4). `.zshrc_bitgo.zsh` `yknotify_check` → new label + script.
Rejected alternative: minimal username re-substitution — leaves deprecated
load, no throttle, breaks again on next machine.

### C1. BitGo fail-open stow [endorsed]
Commit `zsh/.stow-local-ignore` (content `.zshrc_bitgo.zsh`); remove line 1 of
`.gitignore`. Safe: work machines drop a *real* file (README:932), never rely on
the stow symlink; verified this machine has no `~/.zshrc_bitgo.zsh` at all.
Then delete the README Gotcha block (:933-945) and the Quick-start step-6
pre-step. Rejected: `.example` rename (still needs an ignore file → solves less).

### E6. Brewfile [endorsed]
- `brew "ruff"` — add (README format-on-save section instructs it; comment notes
  Mason installs its own copy for nvim).
- `brew "elixir"` — uncomment: `lsp.lua:41` has `elixirls` in `ensure_installed`
  unconditionally, so machines without the runtime get Mason failures; README
  already lists it required.
- `gnupg` + `pinentry-mac` — add as *commented* optional entries pointing at
  README's GPG/YubiKey section (flow is opt-in).

### F2. Tracked `.spl` [endorsed]
`git rm --cached nvim/.config/nvim/spell/en.utf-8.add.spl`; add `*.spl` to
`.gitignore`; keep committing the `.add` (existing convention). Note `:mkspell`
regen in commit message.

## Part 5 — docs

### E1. GUIDE.md missing coverage [endorsed placements]
- `linting.lua` → new Part 2 `## Linting (nvim-lint)` after Format-on-save
  (needs `<a id>` anchor — parens); `<leader>cl` + `<leader>tl` table; prose from
  the file's header comment (LSP vs nvim-lint split). Architecture bullet,
  Contents entry, By-prefix row, Load-order check. Do NOT touch README's
  `### Format-on-save tools` heading (grep anchor).
- `edit.lua` → new Part 2 `## Editing utilities`: `<leader>us` (n/x),
  `<leader>uc` / `:CleanPaste` (incl. the `:` vs `<cmd>` gotcha,
  keymaps.lua:298-300), `:StripWS`. Architecture bullet ("required from
  keymaps.lua, not init.lua — no Load-order entry").
- flatten.nvim → `###` under Design Decisions (concept, no keymaps): should_nest,
  block_for gitcommit/rebase, interaction with `nvim-editor` + `<leader>w`.
  Mention in plugins.lua Architecture bullet.

### E2. Stale docs [endorsed]
- README:898-907 nvim-editor → rewrite: script is `exec nvim "$@"`; flatten.nvim
  in the host does interception/blocking (pairs with C9 comment fix).
- GUIDE:~1006,1011 → remove `<C-[>` cycle-previous row + tip; also fix
  terminal.lua:126-129's comment advertising unbound `<S-C-]>`.
- README:253-260 managed-files table → generalize: `themes/*.json` (10 themes),
  add `review-pr` skill row; fix line ~335 prose (two skills).

### E3. Root CLAUDE.md:3 [endorsed]
Package list: add `yknotify`; reclassify `iterm2/` ("color presets + settings
export, loaded via iTerm2's import — not stow"); one line for `plans/` (design
docs, not a package).

### E4. README package sections [endorsed]
- New Part 2 `## macos` section (Optional/utilities): package contents,
  `stow --no-folding macos`, setup script, link to the existing auto-follow
  subsection (don't move that content). Contents TOC entry.
- yknotify section rewrite per A1/A2 (new paths/label/setup script; keep the
  Focus/DnD note verbatim; mention legacy-label cleanup). Same commit as or
  after A1/A2.

### E5. iTerm2 sync story — USER DECIDED: state export
Standardize on the tracked `iTerm2 State.itermexport`: README documents
export (Settings → General → Settings → "Export All Settings & Data" into
`iterm2/`) and import on new machines; DELETE the "Load preferences from
custom folder" instructions (never actually enabled; would churn an untracked
plist); add `iterm2/com.googlecode.iterm2.plist` to `.gitignore` as
belt-and-braces.

### E7. Low docs [endorsed]
- Neovide keymaps: move the 6-key table README:648-660 → new GUIDE Part 2
  `## Neovide` section (reflecting B4's corrected Cmd+V); README keeps
  install/symlink + link. Contents + By-prefix entries.
- README:665 Typora keymap bullet → pointer to GUIDE Global keymaps.
- Anchors: `<a id="gpg-yubikey-notifications">` above README:605,
  `<a id="colima-default-config">` above README:1031.
- plans/TODO.md: mark shipped items (1, 2a, 9/16, 17, 18) `[done]` or delete.
- plans/changelog.md rename → only if convenient (borderline won't-fix).

## Part 6 — cruft

- **F1 — USER DECIDED: preserve, reorganize**: `animal.{go,py,rs}` are active
  fixtures for testing new editor features across languages. `git mv` them to
  `fixtures/` at repo root; update the reference in
  plans/copilot-context-enrichment.md; add a `fixtures/` line to root
  CLAUDE.md's non-package-directory note (E3) and a one-liner in README if it
  fits an existing section. KEEP the `__pycache__` gitignore rule; update its
  comment's path reference.
- **F3 [endorsed]**: add `.DS_Store` to `.gitignore`.
- **F4 [endorsed]**: delete 0-byte `nvim/.config/nvim/README.md` (stows a
  useless symlink; root README already links GUIDE).

## Follow-ups (deferred by user — revisit later, do NOT implement now)
- ~~`pickers/keybindings.lua:35,99` session-wide cache staleness~~ **SHIPPED:**
  deleted the session cache; `M.open()` now rebuilds via `build_results()` on
  every open (cheap — one which-key tree walk + two keymap syscalls). which-key
  already invalidates its own per-buffer tree on LspAttach/BufEnter, so the
  external cache was both redundant and the cause of the staleness/leak.

## Won't-fix (deliberate)
- zsh eval-init caching (C9) — ms-level win, staleness risk.
- Shared `claude/lib.sh` (D1) — can't reach the real duplication; extract at
  script #4.
- Re-binding a cycle-previous terminal key — `<C-]>` wraps; docs fix suffices.

## Commit sequence (conventional commits)
0. `docs(plans): add dotfiles review remediation plan` — USER REQUESTED: copy
   this plan into `plans/dotfiles-review-remediation.md` as the first action
   (repo convention: plans/ holds design docs), so the repo carries the
   remediation record.
1. `fix(nvim): use inline_completion.get() return to accept ghost text` (B1)
2. `fix(nvim): move terminals to <leader>T, re-key symbols picker to sd, drop aerial picker binding` (B2 + GUIDE + whichkey)
2b. `feat(nvim): source-line column in symbol pickers, cursor preselect in sd, kind column in ss` (B2-ENH)
3. `fix(nvim): restore themes.active on theme-picker cancel` (B3)
4. `fix(neovide): Cmd+V pastes instead of redoing in normal/visual mode` (B4)
5. `fix(nvim): drop deprecated gitsigns undo_stage_hunk` (B5 + GUIDE)
6. `refactor(nvim): add augroups to ai/git/terminal/session autocmds` (B6)
7. `fix(nvim): harden update check (version cmp, 24h debounce, headless skip)` (B7)
8. `fix(nvim): Esc float guard, gitstatus root, gitui timeout, timer close` (B8; keybindings cache deferred)
9. `chore(nvim): purge cursortab.nvim remnants` (B8)
10. `style(nvim): add stylua.toml; reformat pickers/symbols.lua` (B8)
11. `fix(zsh): antigen URL, PATH order, ulimit guard, dead unalias` (C2+C5+C6+C7 + README:869)
12. `fix(zsh): bitgo $HOME alias, per-boot check gate, mise dedupe` (C3+C4+C8)
13. `fix(zsh): theme toggle fallback, claude-nvim slug validation, stale comments` (C9)
14. `feat(yknotify): portable plist, ~/.local/bin script, setup script` (A1+A2 + yknotify_check + README rewrite)
15. `fix(stow): commit zsh/.stow-local-ignore` (C1 + README simplification)
16. `fix(claude): setup-statusline null guard; statusline state to ~/.cache; sync comments` (D1-D3)
17. `chore(brew): add ruff, uncomment elixir, note gnupg/pinentry-mac` (E6)
18. `docs(nvim): GUIDE coverage for linting/edit/flatten/Neovide; drop stale <C-[>` (E1+E2+E7)
19. `docs: refresh README (nvim-editor, themes/skills table, macos section, iTerm2, anchors, Typora)` (E2+E4+E5+E7)
20. `docs: update root CLAUDE.md package list` (E3)
21. `chore: move animal fixtures to fixtures/, untrack .spl, ignore .DS_Store, delete empty README` (F1-F4)
22. `docs(plans): prune completed TODO items` (E7)

## Verification
- nvim: `nvim --headless "+lua print('ok')" +q` clean; then interactive:
  Tab-accept ghost text (no error), `<leader>Tb`/`Th`/`Tt`/`Tv` open terminals
  in a git+LSP buffer, `<leader>tb` toggles blame / `<leader>th` toggles
  hover-hold in that same buffer, `<leader>sd` in fixtures/animal.rs shows the
  source-line column with treesitter colors and opens preselected on the
  cursor's enclosing symbol (also test a buffer with no parser → plain text,
  no error), `<leader>ss` shows kind + relpath:lnum + source-line for both
  loaded and unloaded files with no lag while typing, `<leader>ts` scope
  toggle still works, theme picker Esc from a light variant restores it, Cmd+V in
  Neovide normal mode pastes, `:so %` a patched file twice → no duplicate
  autocmds (`:autocmd UserSidekick`).
- zsh: `exec zsh` clean startup; `echo $path` shows `~/.local/bin` first;
  second shell in same boot skips colima check (stamp).
- yknotify: `bash yknotify/setup-yknotify.sh` on this machine →
  `launchctl print gui/$UID/com.dhruv.yknotify` shows running; `/tmp/yknotify.err.log`
  empty of respawn spam.
- stow: `stow -R zsh claude nvim yknotify macos` → no new unexpected symlinks in
  `$HOME` (specifically no `~/.zshrc_bitgo.zsh`, no `~/yknotify.sh`).
- statusline: trigger a Claude session, confirm files under
  `~/.cache/claude-statusline/`.
- docs: `grep -rn 'GUIDE.md' nvim/.config/nvim/lua/` and
  `grep -rn '## Claude Code\|### Format-on-save tools' .` anchors intact;
  TOC links resolve.
