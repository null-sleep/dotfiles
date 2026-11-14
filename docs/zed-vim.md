# Zed in vim mode — navigation and workflows

Companion to [`docs/zed.md`](zed.md), which covers Zed's native keys, the
agent/git/review workflows, and how `keymap.json` works. This doc is what
changes when `vim_mode` is on: how to move inside a file, between files,
tabs, panes, and panels, and the Zed-specific `g`/`]`/`z`/`ctrl-w` maps
that replace nvim's leader keys. **Default bindings only** — mapping the
nvim config's own keys onto Zed is a later step (see the last section).
Checked against the `v1.28.1` `vim.json`.

Notation: letter keys are written vim-style (`gd`, `]b`, `ZZ`); chords and
modifiers in Zed's keymap style (`ctrl-w h`, `cmd-p`). In `keymap.json` an
uppercase letter is `shift-`: `gA` is `"g shift-a"`, `]B` is `"] shift-b"`.

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
- [Code navigation (LSP, diagnostics, hunks)](#code-nav)
- [Panes and docks (`ctrl-w`)](#panes)
- [Panels with vim keys](#panels)
- [Editing extras](#editing)
- [Git and agent review, vim style](#git-review)
- [`:` commands](#ex)
- [Opt-in bindings](#opt-in)
- [Gotchas cheat-sheet](#gotchas)
- [Later: mapping the nvim bindings](#later)

---

<a id="quick-glance"></a>
## Daily keys — the quick glance

| keys | does | nvim habit it replaces |
|---|---|---|
| `:` | command palette (also every `:w`, `:q`, `:sp`) | `:` |
| `cmd-p`, `gS`, `g/` | file finder, project symbols, project search | `<leader>ff`, `<leader>fs`, `<leader>fg` |
| `gs` | symbols in this file | `<leader>o` |
| `gd` / `gy` / `gI` / `gA` | definition / type / implementation / references | `gd` / `gy` / `gri` / `grr` |
| `grn` / `gra` / `K` | rename / code actions / hover | `<leader>cr` / `<leader>ca` / `K` |
| `]d` `[d`, `]c` `[c` | next diagnostic, next hunk | same |
| `]b` `[b`, `ctrl-^` | next/prev tab, alternate file | `L`/`H`, `gb` |
| `ctrl-o` / `ctrl-i` | jump list (crosses files) | same |
| `ctrl-w h/j/k/l`, `ctrl-w v`/`s` | pane focus, split | `<C-hjkl>`, `<C-w>v` |
| `ZZ` / `ZQ`, `ctrl-w o` | close tab (save / discard), close others | `:x`, `<leader>bo` |
| `cmd-shift-e`, `:E` | project panel (then `h`/`j`/`k`/`l`) | `<leader>e` |
| `gcc`, `ysiw)`, `cs"'`, `ds"` | comment, surround | same |
| `gl` / `ga` | add cursor at next match / all matches | — |
| `do` / `dp` / `du` | show hunk / revert hunk / stage hunk and next | `<leader>hp` / `hr` / `hs` |
| `cmd-?`, `:A` | agent panel | `<leader>aa` |
| `q`/`@`/`Q`, `"+y` | macros, system register | same |

<a id="mental-model"></a>
## The mental model

1. **Vim mode is a keymap layer, not a different editor.** Every vim key
   ends in a Zed action (`gd` → `editor::GoToDefinition`), so the whole
   native keymap stays reachable and `cmd-…` keys keep working.
2. **`:` is the command palette.** Vim ex commands are palette entries
   (`:w`, `:sp`, `:%s/a/b/`, `:12`), and any Zed action is also typeable
   there. Arguments are the catch: `:e file` and `:w name` don't exist.
3. **Vim contexts live on `Editor`.** `vim_mode == normal` is only true
   inside an editor, so panels (project, outline, git, threads sidebar)
   get their own small vim-ish layers (`j`/`k`/`h`/`l`, `gg`/`G`, `/`)
   rather than the full mode machine.
4. **The leader is unclaimed.** `space` is `vim::WrappingRight` in editors
   and only has a handful of defaults in non-editor panes (`space f`,
   `space /`, `space w h`…), which is why the nvim-style leader block in
   `zed/.config/zed/keymap.json` can take it over later.
5. **Tabs are nvim buffers; panes are nvim windows.** `]b`/`[b` walk the
   pane's tabs, `ctrl-w` moves between panes. Zed also has `gt`/`gT`, but
   they walk the same tab strip — there is no separate tab-page layer.

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
| `]r` `[r` | next/prev LSP reference to the symbol under the cursor |
| `]e` `[e`, `]space` `[space` | move line down/up, blank line below/above |
| `gj` `gk` `g0` `g$` `gM` | display-line motions on wrapped lines |
| `g;` `g,`, `gi`, `gv` | change list, insert at last insert, reselect |
| `g*` `g#` | search partial word |
| `%` | also matches quotes (`match_quotes`) and `\|` in Rust |
| `ctrl-g` | show location |
| `zh` `zl`, `zH` `zL` | horizontal scroll (no soft wrap) |

`/` is regex by default (`use_regex_search`) in Rust dialect: `(a|b)`, not
`\(a\|b\)`; `(?i)` for case-insensitive. `escape` in normal mode is
`editor::Cancel` — it drops extra cursors and clears highlights, like
nvim's `<Esc>` map here.

<a id="files-tabs"></a>
## Moving between files and tabs

| keys | action | does |
|---|---|---|
| `]b` / `[b` | `pane::ActivateNextItem` / `…Previous…` | next / prev tab (nvim `L` / `H`) |
| `]B` / `[B` | `pane::ActivateLastItem` / `ActivateItem 0` | last / first tab |
| `gt` / `gT` | `vim::GoToTab` / `GoToPreviousTab` | same tab strip; `3gt` jumps to tab 3 |
| `ctrl-pagedown` / `ctrl-pageup` | `pane::ActivateNextItem` / `…Previous…` | also tabs |
| `ctrl-^` | `pane::AlternateFile` | last file in this pane (nvim `gb`) |
| `ctrl-o` / `ctrl-i` | `pane::GoBack` / `GoForward` | jump list — follows `gd` across files |
| `ctrl-]` / `ctrl-t` | `editor::GoToDefinition` / `pane::GoToOlderTag` | tag-stack style go/return |
| `gf` | `editor::OpenSelectedFilename` | open the path under the cursor |
| `gx` | `editor::OpenUrl` | open the URL under the cursor |
| `ZZ` / `ZQ` | `pane::CloseActiveItem` (save_all / skip) | close tab, saving / discarding |
| `ctrl-w c`, `:q`, `:bd` | `pane::CloseActiveItem` | close tab |
| `ctrl-w o` | `workspace::CloseInactiveTabsAndPanes` | keep only this tab (nvim `<leader>bo`) |
| `ctrl-w a` | `pane::CloseAllItems` | close every tab in the pane |
| `cmd-p` | `file_finder::Toggle` | fuzzy file picker; no vim-mode default in editors |
| `ctrl-tab` | `tab_switcher::Toggle` | MRU tab switcher |
| `:ls`, `:tabn`, `:tabp`, `:tabc`, `:tabnew` | — | buffer list, tab cycling, close, new empty tab |

In pickers (`Picker > Editor`): `ctrl-n`/`ctrl-p` move, `ctrl-u` clears the
query, `ctrl-w` deletes a word, `ctrl-h` backspaces; `enter` opens,
`cmd-enter` opens in a split, `escape` cancels.

The nvim `<leader><leader>` smart picker has no vim-mode default; the
closest is `cmd-p` (recent files rank first when the query is empty) or
`ctrl-tab`. `space f` opens the file finder only from non-editor panes
(project panel, empty pane).

<a id="code-nav"></a>
## Code navigation (LSP, diagnostics, hunks)

| keys | action | does |
|---|---|---|
| `gd`, `ctrl-]` | `editor::GoToDefinition` | definition |
| `gD` | `editor::GoToDeclaration` | declaration |
| `gy`, `grt` | `editor::GoToTypeDefinition` | type definition |
| `gI`, `gri` | `editor::GoToImplementation` | implementation |
| `gA`, `grr` | `editor::FindAllReferences` | references, as a multibuffer |
| `grn`, `cd` | `editor::Rename` | rename symbol |
| `gra`, `g.` | `editor::ToggleCodeActions` | code actions |
| `K`, `gh` | `editor::Hover` | hover |
| `gB` | `editor::BlameHover` | git blame for the line |
| `gs`, `gO` | `outline::Toggle` | symbols in this file |
| `gS` | `project_symbols::Toggle` | workspace symbols |
| `g/` | `pane::DeploySearch` | project search multibuffer |
| `]d` / `[d`, `g]` / `g[` | `editor::GoToDiagnostic` / `…Previous…` | diagnostics |
| `]c` / `[c` | `editor::GoToHunk` / `…Previous…` | git hunks |
| `]r` / `[r` | `vim::GoToNextReference` / `…Previous…` | occurrences of the symbol under the cursor |
| `g space` | `editor::OpenExcerpts` | from a multibuffer: open the real file here |
| `ctrl-w d`, `ctrl-w gd`, `ctrl-w ]` | `editor::GoToDefinitionSplit` | definition in a new split |
| `ctrl-w D`, `ctrl-w gD` | `editor::GoToTypeDefinitionSplit` | type definition in a split |
| `ctrl-w space` | `editor::OpenExcerptsSplit` | multibuffer excerpt in a split |
| `:cl`, `:cn` / `:cp`, `:cc` | — | diagnostics multibuffer, next/prev diagnostic |

Multiple definitions or references open a multibuffer; `cmd-up`/`cmd-down`
step through excerpts and `g space` drops into the file. `ctrl-o` brings
you back from any of these, the same jump list nvim keeps.

Inside the hover/signature popups: `ctrl-n`/`ctrl-p` cycle signature
overloads; `escape` closes. Completions: `ctrl-n`/`ctrl-p` (or
`tab`/`shift-tab`) move, `ctrl-y` accepts, `ctrl-e` dismisses — in insert
mode `ctrl-n`/`ctrl-p` with no menu open trigger word completions,
`ctrl-x ctrl-o` LSP completions, `ctrl-space` is the native key.

<a id="panes"></a>
## Panes and docks (`ctrl-w`)

The `ctrl-w` layer is active in editors and in non-editor panes alike
(`VimControl && !menu || !Editor && !Terminal`); `ctrl-w ctrl-<key>`
variants exist for every entry.

| keys | action | does |
|---|---|---|
| `ctrl-w h/j/k/l` (or arrows) | `workspace::ActivatePane<Dir>` | focus the pane in that direction |
| `ctrl-w w` / `ctrl-w p` / `ctrl-w W` | `workspace::ActivateNextPane` / `…Previous…` | cycle panes |
| `ctrl-w v` / `ctrl-w s` | `pane::SplitVertical` / `SplitHorizontal` | split (`:vsp` / `:sp`) |
| `ctrl-w n` | `workspace::NewFileSplitHorizontal` | new file in a split (`:new`) |
| `ctrl-w H/J/K/L` | `workspace::MovePane<Dir>` | move this pane to an edge |
| `ctrl-w shift-<arrow>` | `workspace::SwapPane<Dir>` | swap with the neighbour |
| `ctrl-w x` | `workspace::SwapPaneAdjacent` | swap with the next pane |
| `ctrl-w >` / `<` / `+` / `-` | `vim::ResizePane<Dir>` | resize (nvim `<A-hjkl>`) |
| `ctrl-w _` / `ctrl-w =` | `vim::MaximizePane` / `ResetPaneSizes` | maximize / equalize |
| `ctrl-w c` / `q` | `pane::CloseActiveItem` | close this tab (pane closes when empty) |
| `ctrl-w o` | `workspace::CloseInactiveTabsAndPanes` | only this one |
| `ctrl-w gt` / `ctrl-w gT` | `pane::ActivateNextItem` / `…Previous…` | tabs, from the `ctrl-w` layer |
| `shift-escape` | `workspace::ToggleZoom` | zoom the pane or panel (native key) |

**Docks are not panes.** `ctrl-w h` from the editor does not land in the
project panel or agent panel, and `ctrl-w l` from a dock does not come
back; use the panel's own toggle (`cmd-shift-e`, `cmd-?`, `ctrl-shift-g`,
`` ctrl-` ``) or `f6`/`shift-f6` to cycle docks and center. Adding
`ctrl-w h/j/k/l` under a `"context": "Dock"` block fixes the return trip —
snippet in [`docs/zed.md`](zed.md#custom-bindings).

In vim mode `ctrl-w` in insert mode still deletes the previous word, and in
normal mode it is unbound (`null`) so the chord can start.

<a id="panels"></a>
## Panels with vim keys

Each panel has a netrw/oil-flavoured layer: `j`/`k` move, `h`/`l` collapse
and expand, `gg`/`G` first/last, `ctrl-d`/`ctrl-u` scroll, `zt`/`zz`/`zb`
recenter, counts work, `:` opens the palette.

- **Project panel** (`cmd-shift-e`, `:E`, `cmd-shift-e` again or `escape`
  to go back) — `enter`/`t` open (permanent tab), `p` preview open, `v`
  vertical split, `o` horizontal split, `%` new file, `d` new directory,
  `R` rename, `D` delete, `x` reveal in Finder, `s` open with system app,
  `-` select parent, `}`/`{` next/prev directory, `]c`/`[c` next/prev git
  change, `]d`/`[d` next/prev diagnostic, `/` search in this directory,
  `zd` compare marked files.
- **Outline panel** (`cmd-shift-b`) — `enter` focuses the editor at the
  entry, `-` parent, `/` cancels. Doubles as a tree of project-search or
  references results.
- **Git panel** (`ctrl-shift-g`, `:G`) — `x` stage/unstage, `X` stage all,
  `U` unstage all, `gx` stage a range, `gf` open the diff, `i` into the
  commit box, `tab` back to the list; `escape`/`ctrl-c` cancel the commit.
- **Git graph / file history** — `j`/`k`, `gg`/`G`, `ctrl-d`/`ctrl-u`;
  `tab` cycles the graph's focusable parts.
- **Threads sidebar** (`cmd-alt-j` toggle, `cmd-alt-;` focus) — `j`/`k`,
  `h`/`l` collapse/expand a project group, `gg`/`G`, `/` filter, `o` new
  thread in this project, `dd` delete thread, `]p`/`[p` next/prev project,
  `za`/`zc`/`zo`/`zM`/`zR` fold groups. Inside the filter box `escape`
  cancels, `j`/`k` still move.
- **Markdown preview** — `ctrl-d`/`ctrl-u`/`ctrl-e`/`ctrl-y`, `gg`/`G`, `/`
  search, `ctrl-o`/`ctrl-i`.
- **Agent message box** — `enter` sends even in vim normal mode
  (`MessageEditor > Editor && VimControl`); `escape` returns to normal mode
  without leaving the thread.
- **Settings editor** (`cmd-,`) nav list — `j`/`k`/`h`/`l`, `gg`/`G`.

<a id="editing"></a>
## Editing extras

Beyond stock operators, registers, `.`, and counts:

| keys | does |
|---|---|
| `iw` `aw` `ip` `is` `it`, `i"` `i'` `` i` `` `i(`/`ib` `i[`/`ir` `i{`/`iB` `i<` `i\|` | the usual objects; `r` is `[]`, `B` is `{}` |
| `iq` / `aq` | nearest quotes of any kind (mini.ai style) |
| `ia` / `aa` | function argument |
| `ii` / `ai` / `aI` | indent block (`aI` includes the line below) |
| `if` / `af`, `ic` / `ac` | function, class (Tree-sitter) |
| `ie` / `ae` | entire file |
| `gc` + motion, `gcc`, `gb` | toggle line / block comments; `dgc` deletes a comment |
| `ys` + motion + char, `yss`, `cs` + old + new, `ds` + char | surround add / line / change / delete |
| `gR` + motion, `gRR` | replace with register |
| `cx` + motion, `cxx`, `cxc` | exchange (vim-exchange): mark two ranges, clear |
| `gl` / `gL`, `g>` / `g<` | add cursor at next / prev match; skip and add |
| `ga` | cursor on every match |
| `gn` / `gN` | select next / prev search match |
| `gI` / `gA` (visual) | cursor at first non-blank / end of every selected line |
| `ctrl-a` / `ctrl-x`, `g ctrl-a` (visual) | increment / decrement; stepped per line |
| `gu` `gU` `g~` `g?`, `gq` / `gw` | case, rot13, rewrap |
| `=` + motion | auto-indent |
| `!` + motion | pipe through a shell command |
| `J` / `gJ` | join with / without whitespace |
| `ctrl-x ctrl-a` (insert) | inline assistant on the current line |
| `ctrl-x ctrl-c` (insert) | request an edit prediction |
| `ctrl-x ctrl-l` (insert) | code actions |
| `ctrl-o` (insert) | one normal-mode command |
| `ctrl-r` + register (insert) | paste a register |
| `ctrl-w` / `ctrl-u` (insert) | delete word / to line start |
| `ctrl-t` / `ctrl-d` (insert) | indent / outdent the line |
| `ctrl-y` / `ctrl-e` (insert) | copy the character above / below |
| `ctrl-k` (insert) | digraph (`custom_digraphs` adds your own) |
| `q<reg>` … `q`, `@<reg>`, `Q` | record, replay, replay last |
| `"+y`, `"+p` | explicit system clipboard (with `on_yank`, plain `y` already does this) |

Visual block (`ctrl-v`) is implemented as multiple cursors, so `I`/`A`
edits show live on every line; `o`/`O` swap ends. Visual `*`/`#` search
the selection. `s` in visual mode is substitute, not sneak.

<a id="git-review"></a>
## Git and agent review, vim style

| keys | action | does |
|---|---|---|
| `]c` / `[c` | `editor::GoToHunk` / `…Previous…` | next / prev hunk |
| `do`, `:dif` | `editor::ToggleSelectedDiffHunks` | show the old text inline; `escape` hides |
| `dp`, `:rev` | `git::Restore` | revert the hunk (nvim `<leader>hr`) |
| `du` / `dU` | `git::StageAndNext` / `UnstageAndNext` | stage / unstage and move on (`<leader>hs`) |
| `dO` | `git::ToggleStaged` | toggle the hunk's staged state |
| `gB` | `editor::BlameHover` | blame popup (`<leader>hb`) |
| `:G` | git panel | then `x`/`X`/`U`/`i` as above |
| `:D`, `:A`, `:te`, `:cl` | debug, agent, terminal, diagnostics | panel shortcuts |

Project diff (`ctrl-g d` from the git panel) is an editor, so `]c`/`[c`,
`du`, `dp`, and all motions work in it; `g space` opens the file.

The agent review buffer (`shift-ctrl-r`, `agent::OpenAgentDiff`) has no vim
defaults — keep/reject are the native `cmd-y` / `cmd-alt-z` and
`shift-alt-y` / `shift-alt-z`; see [`docs/zed.md` → Reviewing agent
edits](zed.md#review). `cmd->` quotes a visual selection into the thread.

<a id="ex"></a>
## `:` commands

Optional letters in brackets. No command takes a file argument.

| command | does |
|---|---|
| `:w[rite]`, `:wa`, `:up[date]`, `:w!` | save (current / all / if changed / skip format) |
| `:q[uit]`, `:q!`, `:wq`, `:x`, `:qa`, `:wqa`, `:bd` | close tab(s) — `:cq` quits Zed |
| `:sp[lit]`, `:vs[plit]`, `:new`, `:vne[w]` | splits |
| `:tabedit`, `:tabnew`, `:tabn`, `:tabp`, `:tabc`, `:ls` | tab strip |
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
- **Sneak** — `"s": "vim::PushSneak"`, `"shift-s": "vim::PushSneakBackward"`
  in `vim_mode == normal || vim_mode == visual` (loses substitute).
- **Subword motions** — `"w": "vim::NextSubwordStart"`, `"b"`, `"e"`, `"g e"`
  in `VimControl && !menu && vim_mode != operator` (camelCase-aware).
- **Visual surround / exchange** — `"shift-s": "vim::PushAddSurrounds"`,
  `"shift-x": "vim::Exchange"` in `vim_mode == visual`.
- **Any-quote / any-bracket objects** — `"q": "vim::AnyQuotes"`,
  `"b": "vim::AnyBrackets"` in
  `vim_operator == a || vim_operator == i || vim_operator == cs`.
- **Jump labels** — `"g w": "vim::HelixJumpToWord"` (flash/leap-style;
  loses `gw` rewrap, `gq` remains).
- **Wrapping `h`/`l`** — `"h": "vim::WrappingLeft"`, `"l": "vim::WrappingRight"`.
- **`ctrl-w` into docks** — the `"context": "Dock"` block from
  [Panes and docks](#panes).
- **`shift-y` = `y$`** — `["workspace::SendKeystrokes", "y $"]` in
  `vim_mode == normal && !menu`.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **`:e file` does not exist** — nothing in `:` takes a file argument.
  `cmd-p`, `gf`, or the project panel.
- **`s`/`S` substitute** unless you bind sneak; `cs`/`ds`/`ys` are surround
  only after an operator.
- **`space` moves right** in editors — any leader you add shadows it, which
  is intended, but a half-typed chord waits 1 s before `space` falls
  through.
- **`ctrl-w hjkl` stops at the dock edge** — see [Panes and docks](#panes).
- **`K` is hover, not man.** `gh` is the same thing.
- **`ctrl-n`/`ctrl-p` in insert mode are word completions**, not LSP ones;
  `ctrl-x ctrl-o` or `ctrl-space` for the LSP menu.
- **`ctrl-c` is escape** in insert/visual mode — it does not copy.
- **Regex is Rust's** in `/`, `:s`, and project search: `(a|b)`, `$1`,
  `(?i)`; `\<` `\>` are `\b`.
- **Visual block = multi-cursor** — great for `I`/`A`, but `:'<,'>` ranges
  act on lines, and `$` on a ragged block behaves differently from Vim.
- **`gA`/`gI` are overloaded** — references/implementation in normal,
  multi-line insert in visual.
- **`gw` and `gq` are the same (rewrap)** until you bind `gw` to jump
  labels.
- **`use_system_clipboard: "on_yank"`** mirrors nvim's clipboard split:
  `y` writes the clipboard, `d`/`x`/`c` do not — `"+p` is never needed for
  a yank, but a deleted range is only in `""`.
- **`ctrl-g` shows location, `ctrl-a` increments** — both are vim, neither
  is the native `go_to_line::Toggle` / select-all.
- **Vim contexts are `Editor`-only** — a `Workspace && vim_mode == normal`
  binding never fires.

<a id="later"></a>
## Later: mapping the nvim bindings

Deliberately not done yet — learn the defaults first. When it is time, the
commented block in `zed/.config/zed/keymap.json` is the starting point and
these are the nvim habits (from GUIDE.md's keymap index) with the cleanest
Zed targets:

| nvim | Zed action to bind | note |
|---|---|---|
| `H` / `L` | `pane::ActivatePreviousItem` / `ActivateNextItem` | loses `H`/`L` screen-top/bottom motions |
| `<C-h/j/k/l>` | `workspace::ActivatePane<Dir>` | add the `Dock` block too so it reaches panels |
| `<A-h/j/k/l>` | `vim::ResizePane<Dir>` | |
| `gb` | `pane::AlternateFile` | `gb` is block-comment by default |
| `jj` / `jk` | `vim::NormalBefore` | insert-mode context |
| `<leader><leader>`, `<leader>ff` | `file_finder::Toggle` | |
| `<leader>fg` / `<leader>fs` | `pane::DeploySearch` / `project_symbols::Toggle` | |
| `<leader>e` / `<leader>o` | `project_panel::ToggleFocus` / `outline_panel::ToggleFocus` | |
| `<leader>ca` / `cr` / `cf` | `editor::ToggleCodeActions` / `Rename` / `Format` | |
| `<leader>h*` | `git::StageAndNext`, `git::Restore`, `editor::BlameHover` | or just learn `du`/`dp`/`gB` |
| `<leader>aa` / `<leader>ax` | `agent::ToggleFocus` / `workspace::CloseActiveDock` | |
| `<leader>bx` / `<leader>bo` | `pane::CloseActiveItem` / `workspace::CloseInactiveTabsAndPanes` | |
| `<leader>qq` | `workspace::CloseWindow` | |
| `<leader>tn` | `editor::ToggleRelativeLineNumbers` | |
| `]q` / `[q` | `editor::GoToDiagnostic` / `…Previous…` | Zed has no quickfix; diagnostics or multibuffer excerpts (`cmd-down`) are the analogue |
