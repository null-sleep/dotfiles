# Zed vim mode — recommended keymap

**Status:** proposal, with `<M-]>` / `<M-[>` (cycle threads) and
`cmd-k cmd-v` (`workspace::ToggleVimMode`, not an nvim carry-over) adopted
and tested (2026-11-14). `zed/.config/zed/keymap.json` holds those two
rows (plus an unrelated `cmd-k cmd-m` block that opens `cheatsheet.md`). The
earlier draft, which mirrored nvim keys that don't exist, was
removed; adopt further rows from the block below.

**Basis: Zed 1.28.1** (`zed --version`) — every action and default named
here was checked against the `v1.28.1` tag
(`assets/keymaps/default-macos.json`, `vim.json`) and
[All actions](https://zed.dev/docs/all-actions). After a Zed upgrade,
re-check a row against the new tag before adopting it, and bump the
version here.

Which of the nvim config's bindings to carry into Zed vim mode, which to
drop for Zed's defaults, and why. Guidance for experimenting, not a
finished keymap: adopt a row, live with it, then update the Status.

Three rules behind every call:

1. **Don't rebind a Zed default that is already two keys and mnemonic**
   (`gd`, `]d`, `]c`, `du`/`dp`, `gS`, `ZZ`). A leader alias *beside* it
   is fine when the leader key is the reflex.
2. **Borrow an nvim key when it is daily muscle memory with no cheap Zed
   equivalent** (`H`/`L`, `ctrl-h/j/k/l`, `jk`, `<leader><leader>`,
   `<leader>e`, `<leader>aa`).
3. **Never shadow a Zed chord prefix.** `space g` is fine; `g r` is not —
   it delays `grn`/`gra`/`grr` by the 1 s chord timeout (the removed draft
   bound it).

Notation: nvim keys as in GUIDE.md (`<leader>sf`); Zed keys as in
`keymap.json` (`space s f`). `<leader>` is `space` in both.

## References

- [`docs/zed-vim.md`](zed-vim.md) — the defaults each row competes with;
  anything not listed here stays on them
- [`docs/zed.md` → Adding your own bindings](zed.md#custom-bindings) —
  contexts, chord timeout, which-key popup, `null`
- [All actions](https://zed.dev/docs/all-actions) — every action below was
  checked here or in the v1.28.1 keymaps
- `nvim/.config/nvim/GUIDE.md` → Keymap index, LSP, Picker, Git, AI,
  Debugging — the source of the nvim column

## Contents

- [Decisions by area](#decisions)
  - [Files, tabs, panes](#nav)
  - [Pickers and search](#pickers)
  - [LSP and code navigation](#lsp)
  - [Panels](#panels)
  - [Git](#git)
  - [AI / agent](#ai)
  - [Debugger](#debugger)
  - [Toggles, yanks, misc](#misc)
- [The keymap block](#block)
- [Caveats](#caveats)
- [To check](#to-check)
- [Adopting a row](#adopting)

---

<a id="decisions"></a>
## Decisions by area

**Calls:** *borrow* = bind the nvim key (or the Zed key named in *why*);
*default* = learn Zed's key instead; *try* = plausible, verify in use;
*skip* = no Zed equivalent worth faking.

<a id="nav"></a>
### Files, tabs, panes

| nvim | Zed default | call | why |
|---|---|---|---|
| `H` / `L` prev/next buffer | `[b` / `]b` | borrow | most-pressed nav keys; loses `vim::WindowTop`/`WindowBottom` (`M` stays), as nvim did |
| `<C-h/j/k/l>` split nav | `ctrl-w h/j/k/l` | borrow | one key vs two; needs the `Dock` block or it dead-ends at panels |
| `<A-h/j/k/l>` resize | `ctrl-w <`/`>`/`-`/`+` | try | rarely used; `ctrl-w _`/`=` cover the common cases |
| `gb` alternate buffer | `ctrl-^` | borrow | `ctrl-^` is awkward on a Mac; loses `gb` block-comment (`cmd-k cmd-/` remains) |
| `jj` / `jk` escape | `escape`, `ctrl-c`, `ctrl-[` | borrow | `jk` only; one escape chord is enough |
| `<leader><leader>` smart picker | `cmd-p` (recent-first when empty) | borrow | daily; same picker |
| `<leader>bb` buffer picker | `ctrl-tab` | borrow | MRU tab switcher with preview |
| `<leader>bx` close buffer | `ZZ`, `ctrl-w c`, `cmd-w` | borrow | pairs with `bo`; `ZZ` also saves |
| `<leader>bo` close others | `cmd-alt-t` | borrow | `pane::CloseOtherItems`; `CloseInactiveTabsAndPanes` would also collapse splits |
| `<leader>qq` quit all | `cmd-q` | skip | already one chord |
| `<C-w>v` / `<C-w>s` splits | `ctrl-w v` / `ctrl-w s` | default | identical |
| `]q` / `[q` quickfix | `cmd-down` / `cmd-up` excerpts | default | no quickfix; multibuffer excerpts are the analogue |

<a id="pickers"></a>
### Pickers and search

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>sf` files | `cmd-p` | borrow | keeps the `s*` family intact |
| `<leader>sg` live grep | `alt-cmd-f` picker, `g/` multibuffer | borrow | `text_finder::Toggle` is Telescope `live_grep` (preview, 1.9+); `g/` stays for editing results |
| `<leader>sw` grep word/selection | `alt-cmd-f` | borrow | the text finder pre-fills from the selection (1.9 notes): `viw` then `space s w` |
| `<leader>ss` workspace symbols | `gS` | borrow | alias; `gS` stays. Same as nvim: only already-started servers answer ([Zed's rule](zed.md#language-servers)). Different prompt: no `name path` split, the whole text is the name query ([details](zed.md#language-servers)) |
| `<leader>sd` document symbols | `gs` | borrow | alias; `gs` stays |
| `<leader>s/`, `<leader>sb` in-buffer fuzzy | `/`, `cmd-f` | default | `/` is the same thing |
| `<leader>sr` resume picker | `cmd-k cmd-p` | borrow | `workspace::ReopenLastPicker` |
| `<leader>sk` keymap picker | `cmd-k cmd-s` | borrow | the keymap editor is searchable |
| `<leader>so` recent files | `cmd-p` empty query | skip | same list |
| `<leader>sm` modified files | git panel | default | `space g g` below |
| `<leader>sq` / `sl` quickfix picker | `cmd-shift-m` | default | diagnostics multibuffer |
| `<leader>sa` AST search, `<leader>sh` help | — | skip | no equivalent |
| picker `<C-v>` / `<C-s>` split | `cmd-enter` | default | one secondary-confirm, no direction |
| picker `<C-q>` to quickfix | — | skip | results are already a multibuffer |

<a id="lsp"></a>
### LSP and code navigation

| nvim | Zed default | call | why |
|---|---|---|---|
| `gd`, `gD`, `gy`, `gri`, `grr`, `grn`, `gra`, `gO`, `K`, `[d`/`]d` | same keys | default | Zed ships these; nvim's `grt` has no Zed twin, `gy` is it |
| `<leader>pd/pt/pi/pr` peek floats | `ctrl-w d`, `ctrl-w D` | borrow | the picker-with-preview result mode (`open_results_in: "picker"`, 1.9+) is the peek; `gd`/`gA` keep the multibuffer |
| `<leader>ca` code action | `gra`, `g.` | borrow | daily reflex |
| `<leader>cf` format | `cmd-shift-i` | borrow | `editor::Format` |
| `<leader>ce` diagnostic float | `K` | default | hover includes the diagnostic |
| `<leader>cd` diagnostic list | `cmd-shift-m`, `:cl` | borrow | `diagnostics::Deploy` |
| `<C-s>` signature help | `ctrl-s` (insert), `cmd-i` | default | insert-mode default matches |
| `<leader>ti` inlay hints | `ctrl-:` | borrow | `ctrl-:` is a stretch |
| `<leader>th` auto-hover, `grx` codelens | — | skip | no equivalent |
| `<M-o>` / `<M-i>` structural select | `[x` / `]x` | default | already two keys |

Key-by-key nvim vs Zed vim comparison for go-to and back/forward:
[`zed-vim.md` → Go to and back](zed-vim.md#nvim-nav-compare).

**Multi-language repos:** a Zed language server starts when you open a file
of its language, so `gS` / `cmd-t` and the LSP keys above only cover
languages you have opened a file in this session; see
[`zed.md` → Language servers](zed.md#language-servers).

<a id="panels"></a>
### Panels

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>e` file tree | `cmd-shift-e`, `:E` | borrow | daily |
| `<leader>o` outline sidebar | `cmd-shift-b` | borrow | daily |
| `<leader>O` outline popup | `gs` | default | same modal |
| `<C-\>` float term, `<C-/>` panel | `` ctrl-` `` | try | as `ctrl-\`; editor-only, so it can't close the terminal (there the shell gets it) |
| tree `a`/`d`/`r`/`x`/`c`/`p` | `%`/`D`/`R`/… (netrw-style) | default | different vocabulary; learn Zed's |

<a id="git"></a>
### Git

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>hs` stage/unstage hunk | `dO` (toggle), `du` (stage + next) | default | the `d` operator layer beats the leader |
| `<leader>hr` reset hunk | `dp` | default | |
| `<leader>hp` preview hunk | `do` | default | |
| `<leader>hb` blame line | `gB` | default | |
| `<leader>tb` inline blame toggle | — | borrow | `editor::ToggleGitBlameInline` has no key |
| `<leader>Gg` Neogit status | `ctrl-shift-g`, `:G` | borrow | as `space g g`; daily |
| `<leader>Gc`/`Gp`/`Gu`/… popups | panel `cmd-enter`, `ctrl-g up/down` | default | the panel is the popup |
| `<leader>vv` uncommitted diff | `ctrl-g d` (git panel) | borrow | as `space g d`: `git::Diff` from anywhere |
| `<leader>vp` PR vs base | `git: diff branch` (no key) | borrow | as `space g p`: `git::DiffBranch` (merge-base, like `vp`); `space g c` picks another base. Not `cmd-alt-g r`, which sends the diff to an agent ([guide](zed.md#branch-diff)) |
| `<leader>vf` file history | — | borrow | as `space g f`: `git::FileHistory` has no key |
| `<leader>vn` / `vh` last-N commits | — | skip | git graph / file history instead |
| `<leader>vq` close diff | `cmd-w`, `ZZ` | default | it's a tab |

<a id="ai"></a>
### AI / agent

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>aa` toggle CLI | `cmd-?`, `:A` | borrow | daily |
| `<leader>ax` kill session | — | borrow | as close dock (`workspace::CloseActiveDock`); stopping is the thread's button |
| `<leader>an` new session | `cmd-alt-shift-n` (panel) | borrow | `agent::ToggleNewThreadMenu` is the agent picker |
| `<leader>al` session picker | `ctrl-tab` (panel) | borrow | `agents_sidebar::ToggleThreadSwitcher` |
| `<M-]>` / `<M-[>` cycle sessions | `alt-]` / `alt-[` (agent panel, sidebar) | adopted | `multi_workspace::NextThread` / `PreviousThread` have no default key; bound in `keymap.json` |
| `<M-n>` fork session | — | skip | no equivalent |
| `<leader>av` agent view | `cmd-alt-j` | borrow | the threads sidebar is the dashboard |
| `<leader>at` / `as` send ref / text | `cmd->` | borrow | visual only: `agent::AddSelectionToThread` |
| `<leader>ad` (new) review diff | `ctrl-shift-r` (agent diff, thread) | borrow | `agent::OpenAgentDiff`; no nvim equivalent |
| `<leader>ae`/`aE`/`ab`/`aq`/`af`/`ac` send context | `@` picker | default | `@diagnostics`, `@file`, `@symbol` in the message box |
| `<leader>ar` label session | sidebar `R` | default | rename the thread |
| `<leader>aj` jump to unread | — | skip | no equivalent action |
| `<C-.>` focus CLI | `cmd-?` | default | |

<a id="debugger"></a>
### Debugger

| nvim | Zed default | call | why |
|---|---|---|---|
| `<F5>` continue, `<F9>` breakpoint, `<F10>` over, `<F11>` into | `f5`, `f9`, `f10`, `f11` | default | identical |
| `<F12>` step out | `shift-f11` | default | `f12` is go-to-definition; `space d O` below covers it |
| `<leader>db` / `dc` / `di` / `do` / `dO` | F-keys only | borrow | the leader layer is what gets used away from the F row |
| `<leader>dq` terminate | `shift-f5` | borrow | `debugger::Stop` |
| `<leader>dl` run last | `f5` (idle) | borrow | `debugger::Rerun` |
| `<leader>du` dap-ui | `cmd-shift-d` | borrow | `debug_panel::ToggleFocus` |
| `<leader>dB` conditional, `dr` REPL, `de` eval | right-click, console tab, hover | skip | no actions to bind |

<a id="misc"></a>
### Toggles, yanks, misc

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>tn` relative numbers | — | borrow | `editor::ToggleRelativeLineNumbers` |
| `<leader>td` diagnostics on/off | — | borrow | `editor::ToggleDiagnostics` |
| `<leader>tq` quickfix window | `cmd-shift-m` | default | same as `<leader>cd` |
| `<leader>tf` / `tL` format/lint-on-save | — | skip | settings, not actions |
| `yp` / `yP` yank path | `cmd-k p` (absolute only) | borrow | `editor::CopyRelativePath` / `CopyPath` |
| `yu` permalink | — | borrow | `editor::CopyPermalinkToLine` |
| `<Esc>` clear highlights | `escape` | default | `editor::Cancel` already does it |
| `gcc`, `ys`/`cs`/`ds` | same | default | |
| `<leader>us`/`uc`/`uo` | — | skip | nvim-specific utilities |

<a id="block"></a>
## The keymap block

Every *borrow* and *try*, grouped by context, ready to paste into
`zed/.config/zed/keymap.json`. Comment out rows you have not adopted.

```jsonc
[
  // ── Normal mode in editors ──────────────────────────────────────────
  {
    "context": "Editor && vim_mode == normal && !menu",
    "bindings": {
      // tabs and panes
      "shift-h": "pane::ActivatePreviousItem",
      "shift-l": "pane::ActivateNextItem",
      "g b": "pane::AlternateFile",
      "ctrl-h": "workspace::ActivatePaneLeft",
      "ctrl-j": "workspace::ActivatePaneDown",
      "ctrl-k": "workspace::ActivatePaneUp",
      "ctrl-l": "workspace::ActivatePaneRight",
      "alt-h": "vim::ResizePaneLeft",          // try
      "alt-j": "vim::ResizePaneDown",          // try
      "alt-k": "vim::ResizePaneUp",            // try
      "alt-l": "vim::ResizePaneRight",         // try
      "space space": "file_finder::Toggle",
      "space b b": "tab_switcher::Toggle",
      "space b x": "pane::CloseActiveItem",
      "space b o": "pane::CloseOtherItems",

      // pickers and search
      "space s f": "file_finder::Toggle",
      "space s g": "text_finder::Toggle",      // live-grep picker; g/ = multibuffer
      "space s w": "text_finder::Toggle",      // select the word first
      "space s s": "project_symbols::Toggle",
      "space s d": "outline::Toggle",
      "space s r": "workspace::ReopenLastPicker",
      "space s k": "zed::OpenKeymap",

      // LSP — p* = "peek": results in a picker with preview
      "space p d": ["editor::GoToDefinition", { "open_results_in": "picker" }],
      "space p t": ["editor::GoToTypeDefinition", { "open_results_in": "picker" }],
      "space p i": ["editor::GoToImplementation", { "open_results_in": "picker" }],
      "space p r": ["editor::FindAllReferences", { "open_results_in": "picker" }],
      "space c a": "editor::ToggleCodeActions",
      "space c f": "editor::Format",
      "space c d": "diagnostics::Deploy",
      "space t i": "editor::ToggleInlayHints",

      // panels
      "space e": "project_panel::ToggleFocus",
      "space o": "outline_panel::ToggleFocus",
      "ctrl-\\": "terminal_panel::Toggle",    // try

      // git
      "space g g": "git_panel::ToggleFocus",
      "space g d": "git::Diff",
      "space g p": "git::DiffBranch",          // PR view: merge-base vs default branch
      "space g c": "git::CompareWithBranch",   // same, pick the base
      "space g f": "git::FileHistory",
      "space t b": "editor::ToggleGitBlameInline",

      // agent
      "space a a": "agent::ToggleFocus",
      "space a x": "workspace::CloseActiveDock",
      "space a n": "agent::ToggleNewThreadMenu",
      "space a l": "agents_sidebar::ToggleThreadSwitcher",
      "space a v": "multi_workspace::ToggleWorkspaceSidebar",
      "space a d": "agent::OpenAgentDiff",

      // debugger
      "space d b": "editor::ToggleBreakpoint",
      "space d c": "debugger::Continue",
      "space d i": "debugger::StepInto",
      "space d o": "debugger::StepOver",
      "space d shift-o": "debugger::StepOut",
      "space d q": "debugger::Stop",
      "space d l": "debugger::Rerun",
      "space d u": "debug_panel::ToggleFocus",

      // toggles and yanks
      "space t n": "editor::ToggleRelativeLineNumbers",
      "space t d": "editor::ToggleDiagnostics",
      "y p": "editor::CopyRelativePath",
      "y shift-p": "editor::CopyPath",
      "y u": "editor::CopyPermalinkToLine"
    }
  },

  // ── Visual mode ─────────────────────────────────────────────────────
  {
    "context": "Editor && vim_mode == visual && !menu",
    "bindings": {
      "space a t": "agent::AddSelectionToThread",
      "space a s": "agent::AddSelectionToThread",
      "space s w": "text_finder::Toggle"       // grep the selection
    }
  },

  // ── Inside the agent panel / threads sidebar: cycle threads ─────────
  {
    "context": "AgentPanel || ThreadsSidebar",
    "bindings": {
      "alt-]": "multi_workspace::NextThread",
      "alt-[": "multi_workspace::PreviousThread"
    }
  },

  // ── Insert mode ─────────────────────────────────────────────────────
  {
    "context": "Editor && vim_mode == insert",
    "bindings": { "j k": "vim::NormalBefore" }
  },

  // ── Docks: make ctrl-h/j/k/l come back from panels ──────────────────
  {
    "context": "Dock",
    "bindings": {
      "ctrl-h": "workspace::ActivatePaneLeft",
      "ctrl-j": "workspace::ActivatePaneDown",
      "ctrl-k": "workspace::ActivatePaneUp",
      "ctrl-l": "workspace::ActivatePaneRight"
    }
  },

  // ── Non-editor panes (project panel, empty pane): same leader keys ──
  {
    "context": "!Editor && !Terminal",
    "bindings": {
      "space space": "file_finder::Toggle",
      "space e": "project_panel::ToggleFocus",
      "space g g": "git_panel::ToggleFocus",
      "space a a": "agent::ToggleFocus"
    }
  }
]
```

Not in the block: a one-key "new Claude thread".
`agent::NewExternalAgentThread` takes the agent as an argument whose shape
the docs don't show — add it via the keymap editor (`space s k` →
`Add Keybinding`), which fills in the accepted form.

<a id="caveats"></a>
## Caveats

- **What `ctrl-h/j/k/l` displace in normal mode:** `editor::Backspace`,
  `vim::Down`, `editor::KillRingCut`, `editor::ScrollCursorCenter` (`zz`
  does the same) — none worth keeping. Never bind them in insert mode:
  `ctrl-k` is digraph there.
- **`y` becomes a chord prefix** for `y p`/`y shift-p`/`y u`. Nothing is
  lost (`p`/`u` are not motions, text objects start with `i`/`a`); `y`
  just resolves on the next key, as an operator does anyway.
- **Vim contexts are `Editor`-only**, hence the `!Editor && !Terminal`
  block for panels. It doesn't collide with vim.json's own `space f`,
  `space /`, `space shift-s`, `space w …` there.
- **Leader chords wait 1 s** before `space` falls through to
  `vim::WrappingRight`; the which-key popup (`which_key.enabled`, on in
  this repo's `settings.json`) lists what can complete a pending chord
  ([details](zed.md#custom-bindings)).

<a id="to-check"></a>
## To check

Open calls from review; each is a one-line change once decided.

- [ ] **Git prefix: `space g *` or `space v *`?** nvim's diffview keys are
  `<leader>vv`/`vp`/`vf`; the block puts them under `g` next to
  `space g g`. Rule 2 (muscle memory) argues for `v`; one git prefix argues
  for `g`. Pick one after a week of reaching for it.
- [ ] **`ctrl-\` terminal toggle: keep as *try* or drop to *default*?** As
  bound (editor only) it opens the terminal but can't close it from inside
  — the shell gets `ctrl-\` (SIGQUIT). Either add
  `{ "context": "Terminal", "bindings": { "ctrl-\\": "terminal_panel::Toggle" } }`
  so it works both ways, or settle on `` ctrl-` ``.
- [ ] **Do `space a n` / `space a l` / `space a d` fire from a plain
  editor?** Their defaults are bound only in `AgentPanel` / `ThreadsSidebar`
  / agent-diff contexts. If they need the panel focused, prefix them with
  `agent::ToggleFocus` via `workspace::SendKeystrokes`, or drop them.
- [ ] **`alt-h/j/k/l` resize** — keep only if actually used.
- [ ] **`space s w` from visual mode** — confirm the text finder keeps the
  selection as its query (documented for the active editor; verify the
  visual case).

<a id="adopting"></a>
## Adopting a row

1. Paste the block (or a subset) into `zed/.config/zed/keymap.json`,
   replacing the file's array. The block already contains the `alt-]` /
   `alt-[` thread-cycling entry that `keymap.json` holds today, so replace
   rather than append. Zed reloads keymaps on save.
2. If a key does nothing, `dev: open key context view` shows the context
   under the cursor; `cmd-shift-p` shows what the action is bound to.
3. After a week, update the **Status** line and the call column: *borrow*
   → **adopted**, or back to *default* with a one-line reason. Rows that
   flip to *default* get deleted from the block, not commented.
4. GUIDE.md stays the owner of nvim's keys; this doc records only the Zed
   side of the mapping.
