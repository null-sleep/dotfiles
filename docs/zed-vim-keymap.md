# Zed vim mode — recommended keymap

**Status:** proposal, nothing adopted yet (2026-11-14). The draft block in
`zed/.config/zed/keymap.json` predates this doc and mirrors nvim keys that
don't exist (`<leader>ff`/`fg`/`fs`, `<leader>cr`); replace it with the
block below when adopting.

Which of the nvim config's bindings to carry into Zed vim mode, which to
drop in favour of Zed's defaults, and why. Guidance for experimenting, not
a finished keymap: adopt a row, live with it, then tick the status.
Defaults are documented in [`docs/zed-vim.md`](zed-vim.md); the mechanics
of `keymap.json` in [`docs/zed.md`](zed.md#custom-bindings); the nvim side
in `nvim/.config/nvim/GUIDE.md` → Keymap index.

Three rules behind every call:

1. **Keep a Zed default when it is already two keys and mnemonic** (`gd`,
   `]d`, `]c`, `du`/`dp`, `gS`, `ZZ`). Rebinding those buys nothing.
2. **Borrow an nvim key when it is daily muscle memory with no cheap
   Zed equivalent** (`H`/`L`, `ctrl-h/j/k/l`, `jk`, `<leader><leader>`,
   `<leader>e`, `<leader>aa`).
3. **Never shadow a Zed chord prefix.** `space g` is fine; `g r` is not
   (it delays `grn`/`gra`/`grr` by the 1 s chord timeout).

Notation: nvim keys as in GUIDE.md (`<leader>sf`); Zed keys as in
`keymap.json` (`space s f`). `<leader>` is `space` in both.

## References

- [`docs/zed-vim.md`](zed-vim.md) — the defaults each row competes with
- [`docs/zed.md` → Adding your own bindings](zed.md#custom-bindings) —
  contexts, chords, `null`, `SendKeystrokes`
- [All actions](https://zed.dev/docs/all-actions) — every name below was
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
- [Deliberately left on Zed defaults](#defaults)
- [Caveats](#caveats)
- [Adopting a row](#adopting)

---

<a id="decisions"></a>
## Decisions by area

Columns: the nvim key, what Zed gives you out of the box, the call, and
the reason. **Calls:** *borrow* = bind the nvim key; *default* = learn
Zed's key instead; *try* = plausible, verify in use; *skip* = no Zed
equivalent worth faking.

<a id="nav"></a>
### Files, tabs, panes

| nvim | Zed default | call | why |
|---|---|---|---|
| `H` / `L` prev/next buffer | `[b` / `]b` | borrow | most-pressed nav keys in nvim; loses `H`/`L` screen-top/bottom, which the nvim config already gave up |
| `<C-h/j/k/l>` split nav | `ctrl-w h/j/k/l` | borrow | one key vs two; needs the `Dock` block too or it dead-ends at panels |
| `<A-h/j/k/l>` resize | `ctrl-w <`/`>`/`-`/`+` | try | rarely used; `ctrl-w _`/`=` cover the common cases |
| `gb` alternate buffer | `ctrl-^` | borrow | `ctrl-^` is awkward on a Mac keyboard; loses `gb` block-comment (`cmd-k cmd-/` remains) |
| `jj` / `jk` escape | `escape`, `ctrl-c`, `ctrl-[` | borrow `jk` | `jj` too makes every `j` in insert mode wait 1 s; one is enough |
| `<leader><leader>` smart picker | `cmd-p` (recent-first on empty query) | borrow | daily; `cmd-p` is the same picker |
| `<leader>bb` buffer picker | `ctrl-tab` | borrow | MRU tab switcher with preview |
| `<leader>bx` close buffer | `ZZ`, `ctrl-w c`, `cmd-w` | borrow | pairs with `bo`; `ZZ` also saves, which is not always wanted |
| `<leader>bo` close others | `cmd-alt-t` | borrow | `pane::CloseOtherItems`, not `CloseInactiveTabsAndPanes` (that also collapses splits) |
| `<leader>qq` quit all | `cmd-q` | skip | `cmd-q` is already one chord |
| `<C-w>v` / `<C-w>s` splits | `ctrl-w v` / `ctrl-w s` | default | identical |
| `]q` / `[q` quickfix | `cmd-down` / `cmd-up` excerpts | default | Zed has no quickfix; multibuffer excerpts are the analogue |

<a id="pickers"></a>
### Pickers and search

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>sf` files | `cmd-p` | borrow | keeps the `s*` family intact |
| `<leader>sg` live grep | `g/`, `cmd-shift-f` | borrow | project search multibuffer; `g/` is good but `sg` is reflex |
| `<leader>sw` grep word/selection | — | try | `pane::DeploySearch` seeds the box from the selection: `viw` then `space s w` |
| `<leader>ss` workspace symbols | `gS` | borrow | both; `gS` stays |
| `<leader>sd` document symbols | `gs` | borrow | both; `gs` stays |
| `<leader>s/`, `<leader>sb` in-buffer fuzzy | `/`, `cmd-f` | default | `/` is the same thing in vim mode |
| `<leader>sr` resume picker | `cmd-k cmd-p` | borrow | `workspace::ReopenLastPicker` is exactly it |
| `<leader>sk` keymap picker | `cmd-k cmd-s` | borrow | the keymap editor is a searchable picker |
| `<leader>so` recent files | `cmd-p` empty query | skip | same list |
| `<leader>sm` modified files | git panel | default | `space g g` below |
| `<leader>sq` / `sl` quickfix picker | `cmd-shift-m` | default | diagnostics multibuffer |
| `<leader>sa` AST search, `<leader>sh` help | — | skip | no equivalent |
| picker `<C-v>` / `<C-s>` open in split | `cmd-enter` | default | one secondary-confirm, no split direction |
| picker `<C-q>` to quickfix | — | skip | results are already a multibuffer |

<a id="lsp"></a>
### LSP and code navigation

| nvim | Zed default | call | why |
|---|---|---|---|
| `gd`, `gD`, `gy`, `gri`, `grr`, `grn`, `gra`, `grt`, `gO`, `K`, `[d`/`]d` | same keys | default | Zed ships the Neovim 0.11 set; nothing to do |
| `<leader>pd/pt/pi/pr` peek floats | `ctrl-w d`, `ctrl-w D` | default | no peek in Zed; a split is the closest |
| `<leader>ca` code action | `gra`, `g.` | borrow | daily reflex, one extra row |
| `<leader>cf` format | `cmd-shift-i` | borrow | `editor::Format` |
| `<leader>ce` diagnostic float | `K` | default | hover includes the diagnostic |
| `<leader>cd` diagnostic list | `cmd-shift-m`, `:cl` | borrow | `diagnostics::Deploy` |
| `<C-s>` signature help | `ctrl-s` (insert), `cmd-i` | default | insert-mode default matches |
| `<leader>ti` inlay hints | `ctrl-:` | borrow | `ctrl-:` is a stretch |
| `<leader>th` auto-hover, `grx` codelens | — | skip | no equivalent |
| `<M-o>` / `<M-i>` structural select | `[x` / `]x` | default | already two keys |

<a id="panels"></a>
### Panels

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>e` file tree | `cmd-shift-e`, `:E` | borrow | daily |
| `<leader>o` outline sidebar | `cmd-shift-b` | borrow | daily |
| `<leader>O` outline popup | `gs` | default | same modal |
| `<C-\>` floating terminal, `<C-/>` panel | `` ctrl-` `` | try `ctrl-\` | one toggle in Zed; `` ctrl-` `` is fine too |
| tree `a`/`d`/`r`/`x`/`c`/`p` | `%`/`D`/`R`/… (netrw-style) | default | different vocabulary; learn Zed's |

<a id="git"></a>
### Git

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>hs` stage/unstage hunk | `dO` (toggle), `du` (stage + next) | default | the `d` operator layer is better than the leader here |
| `<leader>hr` reset hunk | `dp` | default | |
| `<leader>hp` preview hunk | `do` | default | |
| `<leader>hb` blame line | `gB` | default | |
| `<leader>tb` inline blame toggle | — | borrow | `editor::ToggleGitBlameInline` has no key |
| `<leader>Gg` Neogit status | `ctrl-shift-g`, `:G` | borrow as `space g g` | daily; the draft already had it |
| `<leader>Gc`/`Gp`/`Gu`/… popups | panel `cmd-enter`, `ctrl-g up/down` | default | the panel is the popup |
| `<leader>vv` uncommitted diff | `ctrl-g d` from the panel | borrow as `space g d` | `git::Diff` from anywhere |
| `<leader>vp` PR vs base | `cmd-alt-g r` | borrow as `space g r` | `git::ReviewDiff` |
| `<leader>vf` file history | — | borrow as `space g f` | `git::FileHistory` has no key |
| `<leader>vn` / `vh` last-N commits | — | skip | git graph / file history instead |
| `<leader>vq` close diff | `cmd-w`, `ZZ` | default | it's a tab |

<a id="ai"></a>
### AI / agent

| nvim | Zed default | call | why |
|---|---|---|---|
| `<leader>aa` toggle CLI | `cmd-?`, `:A` | borrow | daily |
| `<leader>ax` kill session | — | borrow as close dock | `workspace::CloseActiveDock`; killing is the thread's stop button |
| `<leader>an` new session (agent picker) | `cmd-alt-shift-n` | borrow | `agent::ToggleNewThreadMenu` is the agent picker |
| `<leader>al` session picker | `ctrl-tab` in the panel | borrow | `agents_sidebar::ToggleThreadSwitcher` |
| `<leader>av` agent view | `cmd-alt-j` | borrow | the threads sidebar is the dashboard |
| `<leader>at` / `as` send ref / selection | `cmd->` | borrow (visual) | `agent::AddSelectionToThread` |
| `<leader>ad` (new) review diff | `ctrl-shift-r` | borrow | `agent::OpenAgentDiff`; the nvim config has no equivalent key |
| `<leader>ae`/`aE`/`ab`/`aq`/`af`/`ac` send context | `@` picker | default | `@diagnostics`, `@file`, `@symbol` in the message box |
| `<leader>aj` unread, `<leader>ar` label | sidebar `R` | skip / default | |
| `<C-.>` focus CLI | `cmd-?` | default | |

<a id="debugger"></a>
### Debugger

| nvim | Zed default | call | why |
|---|---|---|---|
| `<F5>` continue, `<F9>` breakpoint, `<F10>` over, `<F11>` into | `f5`, `f9`, `f10`, `f11` | default | identical |
| `<F12>` step out | `shift-f11` | borrow `<leader>dO` | `f12` is go-to-definition in Zed |
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
| `<leader>tq` quickfix window | `cmd-shift-m` | default | same as `<leader>cd` above |
| `<leader>tf` / `tL` format/lint-on-save | — | skip | settings, not actions |
| `yp` / `yP` yank path | `cmd-k p` | borrow | `editor::CopyRelativePath` / `CopyPath`; the `y`-operator prefix is free |
| `yu` permalink | — | borrow | `editor::CopyPermalinkToLine` |
| `<Esc>` clear highlights | `escape` | default | `editor::Cancel` already does it |
| `gcc`, `ys`/`cs`/`ds` | same | default | |
| `<leader>us`/`uc`/`uo` | — | skip | nvim-specific utilities |

<a id="block"></a>
## The keymap block

Everything marked *borrow* or *try*, grouped by context, ready to paste
into `zed/.config/zed/keymap.json`. Comment out rows you have not adopted.

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
      "space s g": "pane::DeploySearch",
      "space s w": "pane::DeploySearch",       // try: select the word first
      "space s s": "project_symbols::Toggle",
      "space s d": "outline::Toggle",
      "space s r": "workspace::ReopenLastPicker",
      "space s k": "zed::OpenKeymap",

      // LSP
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
      "space g r": "git::ReviewDiff",
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
      "space s w": "pane::DeploySearch"        // grep the selection
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

Not in the block, on purpose: a one-key "new Claude thread".
`agent::NewExternalAgentThread` takes the agent as an argument, but its
shape was not verifiable from the docs — add it through the keymap editor
(`space s k` → `Add Keybinding`), which fills in the accepted form.

<a id="defaults"></a>
## Deliberately left on Zed defaults

So you don't reach for a mapping that isn't coming:

- **LSP:** `gd` `gD` `gy` `gri` `grr` `grn` `gra` `grt` `gO` `K` `[d` `]d`
  — identical to nvim.
- **Hunks:** `]c` `[c`, `do` `dp` `du` `dU` `dO`, `gB` — the `d`-operator
  layer replaces `<leader>h*`.
- **Tabs/panes beyond `H`/`L`:** `]b` `[b` `]B` `[B`, `ctrl-w` everything,
  `ZZ`/`ZQ`, `ctrl-o`/`ctrl-i`.
- **Multibuffer:** `cmd-down`/`cmd-up`, `g space` — the quickfix analogue.
- **Editing:** `gcc`, surround, `cx`, `gl`/`ga` multi-cursor, `[x`/`]x`.
- **Agent context:** `@file`, `@diagnostics`, `@symbol` in the message box
  instead of `<leader>ae`/`ab`/`af`.
- **Native chords that are already good:** `cmd-p`, `cmd-shift-f`, `cmd-?`,
  `cmd-shift-e`, `shift-escape` (zoom), `cmd-k cmd-s` (keymap editor).

<a id="caveats"></a>
## Caveats

- **`H`/`L` lose their motions.** `shift-h`/`shift-l` are
  `vim::WindowTop`/`WindowBottom` by default; `M` keeps the middle. The
  nvim config made the same trade.
- **`ctrl-j`/`ctrl-k` in normal mode** are `vim::Down` and (unbound) — safe
  to take. Don't bind them in `vim_mode == insert`: `ctrl-k` is digraph.
- **`ctrl-l`** is screen redraw in Vim; nothing in Zed needs it.
- **`alt-h/j/k/l`** on macOS: Zed treats `alt` as a modifier, so no
  dead-key issue, but they're also free for anything else — low priority.
- **`gb` block comment** goes away; `g shift-b` (blame) is untouched.
- **`space` chords wait 1 s** before falling through to
  `vim::WrappingRight`. Enable `"which_key": { "enabled": true }` while
  learning the layer; `alt-/` lists pending completions.
- **`space s w` seeding from the selection** is from the 1.24 release notes
  for the *file finder*; project search behaving the same is the "try".
- **`y p`/`y shift-p`/`y u`** sit on the yank operator: `yp` is harmless
  (`p` is no motion), but if any `y`-prefixed text object you use starts
  with `p`/`u`, move these to `space y *`.
- **Vim contexts are `Editor`-only**, which is why the leader keys are
  duplicated into a `!Editor && !Terminal` block for panels.
- **`g r` must not be bound** (the old draft had it) — it delays Zed's
  `grn`/`gra`/`grr`.

<a id="adopting"></a>
## Adopting a row

1. Paste the block (or a subset) into `zed/.config/zed/keymap.json`,
   replacing the old commented draft. Zed reloads keymaps on save.
2. If a key does nothing, `dev: open key context view` shows the context
   under the cursor; `cmd-shift-p` shows what the action is currently
   bound to.
3. After a week, update the **Status** line and the call column: *borrow*
   → **adopted**, or back to *default* with a one-line reason. Rows that
   flip to *default* get deleted from the block, not commented.
4. Keep GUIDE.md as the owner of nvim's keys; this doc only records the
   Zed side of the mapping.
