# Zed in vim mode — navigation and workflows

Companion to [`docs/zed.md`](zed.md), which covers Zed's native keys, the
agent/git/review workflows, and how `keymap.json` works. This doc is what
changes when `vim_mode` is on: moving inside a file, between files, tabs,
panes, and panels, and the Zed-specific `g`/`]`/`z`/`ctrl-w` maps that
replace nvim's leader keys. **Default bindings only** — mapping the nvim
config's own keys is a later step (see the last section). Checked against
the `v1.28.1` `vim.json`.

Notation: letter keys are written vim-style (`gd`, `]b`, `ZZ`); chords and
modifiers in Zed's keymap style (`ctrl-w h`, `cmd-p`, `g space`). In
`keymap.json` an uppercase letter is `shift-`: `gA` is `"g shift-a"`, `]B`
is `"] shift-b"`.

## References

- [Vim mode](https://zed.dev/docs/vim) — enabling, the `vim` settings
  block, supported `:` commands, differences from Vim
- [vim.json (v1.28.1)](https://github.com/zed-industries/zed/blob/v1.28.1/assets/keymaps/vim.json)
  — every binding below, with its context
- [Key bindings](https://zed.dev/docs/key-bindings) and
  [`docs/zed.md` → Adding your own bindings](zed.md#custom-bindings)
- `nvim/.config/nvim/GUIDE.md` → Keymap index — the nvim habits this doc
  maps onto Zed (`H`/`L`, `<C-hjkl>`, `gb`, `jj`)

## Contents

- [Daily keys — the quick glance](#quick-glance)
- [The mental model](#mental-model)
- [Turning it on](#enable)
- [Moving inside a file](#in-file)
- [Moving between files and tabs](#files-tabs)
- [Code navigation (LSP, diagnostics)](#code-nav)
- [Panes and docks (`ctrl-w`)](#panes)
- [Panels with vim keys](#panels)
- [Git hunks and agent review](#git-review)
- [Editing extras](#editing)
- [`:` commands](#ex)
- [Opt-in bindings](#opt-in)
- [Gotchas cheat-sheet](#gotchas)
- [Later: mapping the nvim bindings](#later)

---

<a id="quick-glance"></a>
## Daily keys — the quick glance

Used many times a day; each is covered in full below.

| keys | does | nvim habit it replaces |
|---|---|---|
| `:` | command palette (also every `:w`, `:q`, `:sp`) | `:` |
| `cmd-p`, `alt-cmd-f`, `gS` | file finder, live-grep picker, project symbols (all with preview) | `<leader>sf`, `<leader>sg`, `<leader>ss` |
| `gs`, `cmd-shift-b` | symbols in this file (modal), outline panel | `<leader>sd`, `<leader>o` |
| `gd` / `gy` / `gI` / `gA` | definition / type / implementation / references | `gd` / `gy` / `gri` / `grr` |
| `grn` / `gra` / `K` | rename / code actions / hover | `grn` / `<leader>ca` / `K` |
| `cmd-down` / `cmd-up`, `g space` | next / prev excerpt, open the real file (multibuffer) | `]q` / `[q`, `<CR>` |
| `]d` `[d`, `]c` `[c` | next diagnostic, next hunk | same |
| `]b` `[b`, `ctrl-^` | next/prev tab, alternate file | `L`/`H`, `gb` |
| `ctrl-o` / `ctrl-i` | jump list (crosses files) | same |
| `ctrl-w h/j/k/l`, `ctrl-w v`/`s` | pane focus, split | `<C-hjkl>`, `<C-w>v` |
| `ZZ` / `ZQ`, `ctrl-w o` | close tab (save / discard), close others | `:x`, `<leader>bo` |
| `cmd-shift-e`, `:E` | project panel (then `h`/`j`/`k`/`l`) | `<leader>e` |
| `do` / `dp` / `du` | show hunk / revert hunk / stage hunk and next | `<leader>hp` / `hr` / `hs` |
| `gcc`, `ysiw)`, `cs"'`, `ds"` | comment, surround | same |
| `gl` / `ga` | add cursor at next match / all matches | — |
| `cmd-?`, `:A` | agent panel | `<leader>aa` |

<a id="mental-model"></a>
## The mental model

1. **Vim mode is a keymap layer, not a different editor.** Every vim key
   ends in a Zed action (`gd` → `editor::GoToDefinition`), so the native
   keymap and its `cmd-…` keys keep working.
2. **`:` is the command palette.** Ex commands are palette entries (`:w`,
   `:sp`, `:%s/a/b/`, `:12`), and any Zed action is typeable there.
   Arguments are the catch: `:e file` and `:w name` don't exist.
3. **Vim contexts live on `Editor`.** Panels get their own small vim-ish
   layers ([Panels](#panels)) rather than the full mode machine.
4. **The leader is unclaimed.** `space` is `vim::WrappingRight` in editors
   and has only a handful of defaults in non-editor panes (`space f`,
   `space /`, `space w h`…), so the leader block proposed in
   [`docs/zed-vim-keymap.md`](zed-vim-keymap.md) can take it over later.
5. **Tabs are nvim buffers; panes are nvim windows.** `]b`/`[b` and
   `gt`/`gT` walk the same tab strip (no separate tab-page layer);
   `ctrl-w` moves between panes.

<a id="enable"></a>
## Turning it on

```jsonc
{
  "vim_mode": true,
  "vim": {
    "use_system_clipboard": "on_yank",   // y → clipboard; d/c/x stay local (nvim parity)
    "use_smartcase_find": true,          // f/t case-insensitive on lowercase targets
    "toggle_relative_line_numbers": true // relative in normal, absolute in insert
  },
  "relative_line_numbers": "enabled",
  "vertical_scroll_margin": 10,          // scrolloff
  "cursor_blink": false
}
```

The repo's `settings.json` ships `vim_mode: false` with the `vim` block in
place; flip the flag (or `workspace: toggle vim mode`) and uncomment the
editing block. Other `vim` keys: `default_mode`, `use_regex_search`,
`gdefault`, `highlight_on_yank_duration` (ms, `0` off), `custom_digraphs`.
`command_aliases` (top level) adds palette aliases: `{ "W": "w", "Q": "q" }`.

<a id="in-file"></a>
## Moving inside a file

Standard motions, counts, `f`/`t`/`;`/`,`, `%`, `*`/`#`, `/`/`?` with
`n`/`N`, marks (`m`, `'`, `` ` ``), `H`/`M`/`L`, `ctrl-d`/`u`/`f`/`b`/`e`/`y`,
`zt`/`zz`/`zb`, and folds (`za`, `zc`, `zo`, `zM`, `zR`, `zf`) all work. On
top of those:

| keys | does |
|---|---|
| `]m` `[m`, `]M` `[M` | next/prev method start, end (Tree-sitter) |
| `]]` `[[`, `][` `[]` | next/prev section (top-level item) start, end |
| `]/` `[/` | next/prev comment |
| `]-` `]+` `]=` (and `[`) | next line with lesser / greater / same indent |
| `])` `]}`, `[(` `[{` | unmatched bracket forward / back |
| `[x` `]x` | grow / shrink selection to the enclosing syntax node |
| `]e` `[e`, `] space` `[ space` | move line down/up, blank line below/above |
| `gj` `gk` `g0` `g$` `gM` | display-line motions on wrapped lines |
| `g;` `g,`, `gi`, `gv` | change list, insert at last insert, reselect |
| `g*` `g#` | search partial word |
| `%` | also matches quotes (`match_quotes`) and `\|` in Rust |
| `ctrl-g` | show location |
| `zh` `zl`, `zH` `zL` | horizontal scroll (no soft wrap) |

`]r`/`[r` (next/prev reference) is under [Code navigation](#code-nav).
`escape` in normal mode is `editor::Cancel` — it drops extra cursors and
clears highlights, like nvim's `<Esc>` map here. `/` uses Rust regex (see
[Gotchas](#gotchas)).

<a id="files-tabs"></a>
## Moving between files and tabs

| keys | action | does |
|---|---|---|
| `]b` / `[b`, `ctrl-pagedown` / `ctrl-pageup` | `pane::ActivateNextItem` / `…Previous…` | next / prev tab (nvim `L` / `H`) |
| `]B` / `[B` | `pane::ActivateLastItem` / `ActivateItem 0` | last / first tab |
| `gt` / `gT` | `vim::GoToTab` / `GoToPreviousTab` | same tab strip; `3gt` jumps to tab 3 |
| `ctrl-w gt` / `ctrl-w gT` | `pane::ActivateNextItem` / `…Previous…` | tabs, from the `ctrl-w` layer |
| `ctrl-^` | `pane::AlternateFile` | last file in this pane (nvim `gb`) |
| `ctrl-o` / `ctrl-i` | `pane::GoBack` / `GoForward` | jump list — follows `gd` across files |
| `ctrl-]` / `ctrl-t` | `editor::GoToDefinition` / `pane::GoToOlderTag` | tag-stack style go/return |
| `gf` / `gx` | `editor::OpenSelectedFilename` / `OpenUrl` | open the path / URL under the cursor |
| `cmd-p` / `ctrl-tab` | `file_finder::Toggle` / `tab_switcher::Toggle` | file picker (no vim-mode default) / MRU tabs |
| `ZZ` / `ZQ` | `pane::CloseActiveItem` (save_all / skip) | close tab, saving / discarding |
| `ctrl-w c`, `ctrl-w q`, `:q`, `:bd` | `pane::CloseActiveItem` | close tab (the pane closes when empty) |
| `ctrl-w o` / `ctrl-w a` | `workspace::CloseInactiveTabsAndPanes` / `pane::CloseAllItems` | keep only this tab (nvim `<leader>bo`) / close all in the pane |

Tab-strip `:` commands (`:ls`, `:tabn`, `:tabnew`…) are in [`:` commands](#ex).
In pickers, on top of the [native picker keys](zed.md#pickers): `ctrl-u`
clears the query, `ctrl-w` deletes a word, `ctrl-h` backspaces. The
pickers are Telescope-style since 1.9 — resizable, with a preview pane —
and `alt-cmd-f` (`text_finder::Toggle`) is the live-grep picker, seeded
from the selection; `g/` stays the editable multibuffer. No default
replaces nvim's `<leader><leader>` smart picker — `cmd-p` (recent files
rank first on an empty query) or `ctrl-tab` come closest; `space f` opens
the finder only from non-editor panes (project panel, empty pane).

<a id="code-nav"></a>
## Code navigation (LSP, diagnostics)

| keys | action | does |
|---|---|---|
| `gd`, `ctrl-]` / `gD` | `editor::GoToDefinition` / `GoToDeclaration` | definition / declaration |
| `gy` | `editor::GoToTypeDefinition` | type definition (no `grt` in Zed) |
| `gI`, `gri` | `editor::GoToImplementation` | implementation |
| `gA`, `grr` | `editor::FindAllReferences` | references, as a multibuffer |
| `grn`, `cd` | `editor::Rename` | rename symbol |
| `gra`, `g.` | `editor::ToggleCodeActions` | code actions |
| `K`, `gh` | `editor::Hover` | hover |
| `gs`, `gO` / `gS` | `outline::Toggle` / `project_symbols::Toggle` | symbols in this file / workspace |
| `g/` | `pane::DeploySearch` | project search multibuffer |
| `]d` / `[d`, `g]` / `g[` | `editor::GoToDiagnostic` / `…Previous…` | diagnostics |
| `]r` / `[r` | `vim::GoToNextReference` / `…Previous…` | occurrences of the symbol under the cursor |
| `g space` | `editor::OpenExcerpts` | from a multibuffer: open the real file here |
| `ctrl-w d`, `ctrl-w gd`, `ctrl-w ]` | `editor::GoToDefinitionSplit` | definition in a new split |
| `ctrl-w D`, `ctrl-w gD` | `editor::GoToTypeDefinitionSplit` | type definition in a split |
| `ctrl-w space` | `editor::OpenExcerptsSplit` | multibuffer excerpt in a split |

Multiple definitions or references open a multibuffer: `cmd-down`/`cmd-up`
step through excerpts ([multibuffer keys](zed.md#search-multibuffers)),
`g space` drops into the file, `ctrl-o` comes back. Prefer a Telescope-style
picker with preview instead? `"lsp_results_location": "picker"` globally,
or per binding with `{ "open_results_in": "picker" }` — the nvim
`<leader>pr` peek habit ([keymap doc](zed-vim-keymap.md#lsp)). Diagnostics
as a quickfix list: `:cl`, `:cn`/`:cp` ([`:` commands](#ex)).

Popups: `ctrl-n`/`ctrl-p` cycle signature overloads; `escape` closes. In
the completion menu `ctrl-n`/`ctrl-p` (or `tab`/`shift-tab`) move,
`ctrl-y` accepts, `ctrl-e` dismisses; opening it is a
[gotcha](#gotchas).

<a id="panes"></a>
## Panes and docks (`ctrl-w`)

The `ctrl-w` layer is active in editors and non-editor panes alike
(`VimControl && !menu || !Editor && !Terminal`), and every entry also has a
`ctrl-w ctrl-<key>` form. Normal mode nulls the native `ctrl-w` so the
chord can start; insert mode still deletes a word.

| keys | action | does |
|---|---|---|
| `ctrl-w h/j/k/l` (or arrows) | `workspace::ActivatePane<Dir>` | focus the pane in that direction |
| `ctrl-w w` / `ctrl-w p` / `ctrl-w W` | `workspace::ActivateNextPane` / `…Previous…` | cycle panes |
| `ctrl-w v` / `ctrl-w s` | `pane::SplitVertical` / `SplitHorizontal` | split (`:vsp` / `:sp`) |
| `ctrl-w n` | `workspace::NewFileSplitHorizontal` | new file in a split (`:new`) |
| `ctrl-w H/J/K/L` | `workspace::MovePane<Dir>` | move this pane to an edge |
| `ctrl-w shift-<arrow>` / `ctrl-w x` | `workspace::SwapPane<Dir>` / `SwapPaneAdjacent` | swap with the neighbour / next pane |
| `ctrl-w >` / `<` / `+` / `-` | `vim::ResizePane<Dir>` | resize (nvim `<A-hjkl>`) |
| `ctrl-w _` / `ctrl-w =` | `vim::MaximizePane` / `ResetPaneSizes` | maximize / equalize |
| `shift-escape` | `workspace::ToggleZoom` | zoom the pane or panel (native key) |

Closing (`ctrl-w c`/`q`/`o`/`a`) and `ctrl-w gt`/`gT`: [Files and
tabs](#files-tabs); `ctrl-w d` and other split jumps: [Code nav](#code-nav).

**Docks are not panes.** `ctrl-w h` from the editor does not land in the
project or agent panel, and `ctrl-w l` from a dock does not come back. Use
the panel's own toggle (`cmd-shift-e`, `cmd-?`, `ctrl-shift-g`,
`` ctrl-` ``), `f6`/`shift-f6` to cycle docks and center, or the `Dock`
[opt-in](#opt-in) for the return trip.

<a id="panels"></a>
## Panels with vim keys

Each panel has a netrw/oil-flavoured layer: `j`/`k` move, `h`/`l` collapse
and expand, `gg`/`G` first/last, `ctrl-d`/`ctrl-u` scroll, `zt`/`zz`/`zb`
recenter, counts work, `:` opens the palette.

- **Project panel** (`cmd-shift-e`, `:E`; `cmd-shift-e` again or `escape`
  to go back) — `enter`/`t` open (permanent tab), `p` preview open, `v`/`o`
  vertical/horizontal split, `%` new file, `d` new directory, `R` rename,
  `D` delete, `x` reveal in Finder, `s` open with system app, `-` select
  parent, `}`/`{` next/prev directory, `]c`/`[c` next/prev git change,
  `]d`/`[d` next/prev diagnostic, `/` search in this directory, `zd`
  compare marked files.
- **Outline panel** (`cmd-shift-b`) — `enter` focuses the editor at the
  entry, `-` parent, `/` cancels. Doubles as a tree of project-search or
  references results.
- **Git panel** (`ctrl-shift-g`, `:G`) — `x` stage/unstage, `X` stage all,
  `U` unstage all, `gx` stage a range, `gf` open the diff, `i` into the
  commit box, `tab` back to the list; `escape`/`ctrl-c` cancel the commit.
- **Git graph / file history, settings editor (`cmd-,`) nav list** — the
  base layer; `tab` cycles the graph's focusable parts.
- **Threads sidebar** (`cmd-alt-j` toggle, `cmd-alt-;` focus) — `h`/`l`
  collapse/expand a project group, `/` filter (`escape` cancels, `j`/`k`
  still move), `o` new thread in this project, `dd` delete thread,
  `]p`/`[p` next/prev project, `za`/`zc`/`zo`/`zM`/`zR` fold groups.
- **Markdown preview** — `ctrl-d`/`ctrl-u`/`ctrl-e`/`ctrl-y`, `gg`/`G`, `/`
  search, `ctrl-o`/`ctrl-i`.
- **Agent message box** — `enter` sends even in normal mode
  (`MessageEditor > Editor && VimControl`); `escape` returns to normal mode
  without leaving the thread.

<a id="git-review"></a>
## Git hunks and agent review

| keys | action | does |
|---|---|---|
| `]c` / `[c` | `editor::GoToHunk` / `…Previous…` | next / prev hunk |
| `do` | `editor::ToggleSelectedDiffHunks` | show the old text inline (`:dif`); `escape` hides |
| `dp` | `git::Restore` | revert the hunk (`:rev`; nvim `<leader>hr`) |
| `du` / `dU` | `git::StageAndNext` / `UnstageAndNext` | stage / unstage and move on (`<leader>hs`) |
| `dO` | `git::ToggleStaged` | toggle the hunk's staged state |
| `gB` | `editor::BlameHover` | blame popup (`<leader>hb`) |

The project diff (`ctrl-g d` from the [git panel](#panels)) is an editor,
so `]c`/`[c`, `du`, `dp`, and all motions work in it; `g space` opens the
file. The agent review buffer (`ctrl-shift-r`) has no vim defaults — use
the native keep/reject keys in
[`docs/zed.md` → Reviewing agent edits](zed.md#review). `cmd->` quotes a
visual selection into the thread.

<a id="editing"></a>
## Editing extras

Beyond stock operators, registers, macros (`q`, `@`, `Q` replays the last),
`.`, counts, and text objects (`r` is `[]`, `B` is `{}`):

| keys | does |
|---|---|
| `iq` / `aq` | nearest quotes of any kind (`vim::MiniQuotes`, mini.ai style) |
| `ia` / `aa`, `ie` / `ae` | function argument, entire file |
| `ii` / `ai` / `aI` | indent block (`aI` includes the line below) |
| `if` / `af`, `ic` / `ac` | function, class (Tree-sitter) |
| `gc` + motion, `gcc`, `gb` | toggle line / block comments; `dgc` deletes a comment |
| `ys` + motion + char, `yss`, `cs` + old + new, `ds` + char | surround add / line / change / delete |
| `gR` + motion, `gRR` | replace with register |
| `cx` + motion, `cxx`, `cxc` | exchange (vim-exchange): mark two ranges, clear |
| `gl` / `gL`, `g>` / `g<`, `ga` | add cursor at next / prev match; skip and add; every match |
| `gn` / `gN` | select next / prev search match |
| `gI` / `gA` (visual) | cursor at first non-blank / end of every selected line |
| `ctrl-a` / `ctrl-x`, `g ctrl-a` (visual) | increment / decrement; stepped per line |
| `gu` `gU` `g~` `g?`, `gq` / `gw` | case, rot13, rewrap |
| `=` / `!` + motion | auto-indent / pipe through a shell command |
| `J` / `gJ` | join with / without whitespace |
| `"+y`, `"+p` | explicit system clipboard (`on_yank` makes plain `y` do this) |

Insert mode:

| keys | does |
|---|---|
| `ctrl-x ctrl-a` / `ctrl-x ctrl-c` / `ctrl-x ctrl-l` | inline assistant / request edit prediction / code actions |
| `ctrl-o` | one normal-mode command |
| `ctrl-r` + register | paste a register |
| `ctrl-w` / `ctrl-u` | delete word / to line start |
| `ctrl-t` / `ctrl-d` | indent / outdent the line |
| `ctrl-y` / `ctrl-e` | copy the character above / below |
| `ctrl-k` | digraph (`custom_digraphs` adds your own) |

Visual block (`ctrl-v`) is multiple cursors, so `I`/`A` edits show live on
every line; `o`/`O` swap ends. Visual `*`/`#` search the selection; visual
`s` is substitute, not sneak.

<a id="ex"></a>
## `:` commands

Optional letters in brackets. No command takes a file argument.

| command | does |
|---|---|
| `:w[rite]`, `:wa`, `:up[date]`, `:w!` | save (current / all / if changed / skip format) |
| `:q[uit]`, `:q!`, `:wq`, `:x`, `:qa`, `:wqa`, `:bd` | close tab(s) — `:cq` quits Zed |
| `:sp[lit]`, `:vs[plit]`, `:new`, `:vne[w]` | splits |
| `:tabedit`, `:tabnew`, `:tabn`, `:tabp`, `:tabc`, `:ls` | tab strip (new empty tab, cycle, close, list) |
| `:E[xplore]`, `:G[it]`, `:A[I]`, `:D[ebug]`, `:te[rm]`, `:C[ollab]`, `:Ch[at]`, `:No[tif]`, `:Ext[ensions]` | panels |
| `:cl[ist]`, `:cn`/`:ln`, `:cp`/`:lp`, `:cc`/`:ll` | diagnostics as a quickfix list |
| `:dif[fupdate]`, `:rev[ert]` | `do` / `dp` |
| `:<n>`, `:$`, `:/foo`, `:?foo` | jump to line / end / match |
| `:[range]s/foo/bar/[g]`, `:j[oin]`, `:d[elete]`, `:s[ort] [i]`, `:y[ank]`, `:[range]!cmd` | range edits |
| `:se[t] [no]wrap`, `[no]nu`, `[no]rnu`, `[no]ic` | per-buffer toggles |
| `:<any zed action>` | e.g. `:editor: toggle split diff`; `command_aliases` shortens these |

Vim-style `:%s/\(a\)/\1/` is auto-converted; native form is `(a)` and `$1`.

<a id="opt-in"></a>
## Opt-in bindings

Not default, documented by Zed, and worth considering — each is a block
in `keymap.json` (how-to in [`docs/zed.md`](zed.md#custom-bindings)):

- **`jk` / `jj` to escape** — `{ "context": "vim_mode == insert",
  "bindings": { "j k": "vim::NormalBefore" } }` (nvim `jj`/`jk`).
- **`ctrl-w` into and out of docks** — `ctrl-w h/j/k/l` →
  `workspace::ActivatePane<Dir>` under `"context": "Dock"` (snippet in
  [`docs/zed.md`](zed.md#custom-bindings)).
- **Sneak** — `"s": "vim::PushSneak"`, `"shift-s": "vim::PushSneakBackward"`
  in `vim_mode == normal || vim_mode == visual` (loses substitute).
- **Subword motions** — `"w": "vim::NextSubwordStart"`, `"b"`, `"e"`, `"g e"`
  in `VimControl && !menu && vim_mode != operator` (camelCase-aware).
- **Visual surround / exchange** — `"shift-s": "vim::PushAddSurrounds"`,
  `"shift-x": "vim::Exchange"` in `vim_mode == visual`.
- **Any-quote / any-bracket objects** — `"q": "vim::AnyQuotes"`,
  `"b": "vim::AnyBrackets"` in
  `vim_operator == a || vim_operator == i || vim_operator == cs`. These
  *replace* the defaults (`q` = `vim::MiniQuotes`, `b` = parentheses) with
  targets.vim-style "any pair containing the cursor" objects.
- **Jump labels** — `"g w": "vim::HelixJumpToWord"` (flash/leap-style;
  loses `gw` rewrap, `gq` remains).
- **Wrapping `h`/`l`** — `"h": "vim::WrappingLeft"`, `"l": "vim::WrappingRight"`.
- **`Y` = `y$`** — `"shift-y": ["workspace::SendKeystrokes", "y $"]` in
  `vim_mode == normal && !menu`.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **`:e file` does not exist** — nothing in `:` takes a file argument.
  `cmd-p`, `gf`, or the project panel.
- **`s`/`S` alone are substitute** unless you bind sneak; surround is only
  the two-key `ys`/`cs`/`ds`.
- **`space` moves right** in editors — a leader you add shadows it, as
  intended, but a half-typed chord waits 1 s before `space` falls through.
- **`K` is hover, not man.** `gh` is the same thing.
- **`ctrl-n`/`ctrl-p` in insert mode are word completions**, not LSP;
  `ctrl-x ctrl-o` or `ctrl-space` for the LSP menu.
- **`ctrl-c` is escape** in insert/visual mode — it does not copy.
- **Regex is Rust's** in `/`, `:s`, and project search: `(a|b)`, not
  `\(a\|b\)`; `$1`, `(?i)`; `\<` `\>` are `\b`.
- **Visual block = multi-cursor** — great for `I`/`A`, but `:'<,'>` ranges
  act on lines, and `$` on a ragged block behaves differently from Vim.
- **`gA`/`gI` are overloaded** — references/implementation in normal,
  multi-line insert in visual.
- **`on_yank` clipboard** — `y` writes the clipboard, `d`/`x`/`c` do not,
  so a deleted range is only in `""`.
- **`ctrl-g` shows location, `ctrl-a` increments** — both vim; neither is
  the native `go_to_line::Toggle` / select-all.
- **Vim contexts are `Editor`-only** — a `Workspace && vim_mode == normal`
  binding never fires.

<a id="later"></a>
## Later: mapping the nvim bindings

Deliberately not done yet — learn the defaults first. The per-key
recommendations (borrow / default / try / skip, with a pasteable
`keymap.json` block) live in [`docs/zed-vim-keymap.md`](zed-vim-keymap.md);
its status line tracks what has been adopted.
