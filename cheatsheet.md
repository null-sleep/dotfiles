# Zed cheatsheet

`cmd-k cmd-m` opens this (task `cheatsheet`); `cmd-shift-v` flips preview and
source. `cmd-k cmd-v` toggles vim mode.

Columns: **Zed** native key, **Vim** Zed's vim-mode key, **nvim** this repo's
nvim config (GUIDE.md notation). A blank cell means the key to its left still
applies (Zed keys work in vim mode); a blank nvim cell can also mean nvim has
no equivalent. `—` means no key; use the palette.
Full reference: `docs/zed.md`, `docs/zed-vim.md`.

## Find and navigate

| Action | Zed | Vim | nvim |
|---|---|---|---|
| command palette | `cmd-shift-p` | `:` | |
| file finder | `cmd-p` | | `<leader>sf`, `<leader><leader>` |
| live-grep picker | `alt-cmd-f` | | `<leader>sg` |
| grep word / selection | `alt-cmd-f` (prefills) | | `<leader>sw` |
| project search, editable results | `cmd-shift-f` | `g/` | |
| project search and replace | `cmd-shift-h` | | `<leader>sR` |
| search in file / next, prev match | `cmd-f` / `cmd-g`, `cmd-shift-g` | `/` / `n`, `N` | |
| symbols in file / project | `cmd-shift-o` / `cmd-t` | `gO` / `gS` | `gO` / `<leader>ss` |
| go to line | `ctrl-g` | `:<n>` | |
| back / forward (crosses files) | `ctrl--` / `ctrl-_` | `ctrl-o` / `ctrl-i` | |
| alternate file | — | `ctrl-^` | `gb` |
| open path / URL under cursor | — | `gf` / `gx` | |
| all diagnostics / next, prev | `cmd-shift-m` / `f8`, `shift-f8` | `:cl` / `]d`, `[d` | `<leader>cd` (list) |
| reopen last picker | `cmd-k cmd-p` | | `<leader>sr` |
| recent projects | `alt-cmd-o` | | |
| branch / worktree picker | `ctrl-cmd-b` / `ctrl-cmd-w` | | `<leader>Gb` / `<leader>Gw` |

In a picker: `enter` open, `cmd-enter` open in a split, `escape` cancel.
File finder: `cmd-shift-i` includes ignored files.

## Code

| Action | Zed | Vim | nvim |
|---|---|---|---|
| definition / in a split | `f12` / `alt-f12` | `gd` / `ctrl-w d` | `gd` / `<leader>pd` (peek) |
| type definition / implementation | `cmd-f12` / `shift-f12` | `gy` / `gri` | |
| references | `alt-shift-f12` | `grr` | |
| rename | `f2` | `grn` | |
| code actions | `cmd-.` | `gra`, `g.` | `gra`, `<leader>ca` |
| hover | `cmd-k cmd-i` | `K` | |
| format | `cmd-shift-i` | | `<leader>cf` |
| toggle comment | `cmd-/` | `gcc`, `gc` + motion | |
| add cursor at next match / all | `cmd-d` / `cmd-shift-l` | `gl` / `ga` | |
| grow / shrink selection | `ctrl-cmd-right` / `ctrl-cmd-left` | `[x` / `]x` | `<M-o>` / `<M-i>` |
| move line up / down | `alt-up` / `alt-down` | `[e` / `]e` | |
| toggle fold | `cmd-k cmd-l` | `za` | |
| LSP completions | `ctrl-space` | `ctrl-x ctrl-o` (insert) | `<C-space>` |
| inline assist | `ctrl-enter` | `ctrl-x ctrl-a` (insert) | |
| save / without formatting | `cmd-s` / `cmd-k s` | `:w` / `:w!` | |

Autosave runs 1s after the last edit and never formats; `cmd-s` formats Go,
Rust, Elixir, and other languages Zed formats by default.

## Review changes

| Action | Zed | Vim | nvim |
|---|---|---|---|
| uncommitted diff | `git: diff` (`ctrl-g d` in git panel) | | `<leader>vv` |
| branch vs base, the PR view | `git: diff branch` | | `<leader>vp` |
| against another base | `git: compare with branch` | | |
| next / prev hunk | `cmd-f8` / `cmd-shift-f8` | `]c` / `[c` | |
| next / prev file (excerpt) | `cmd-down` / `cmd-up` | | `<Tab>` / `<S-Tab>` (diffview) |
| show old text inline | `cmd-'` | `do` | `<leader>hp` |
| stage / unstage hunk, then next | `cmd-y` / `cmd-shift-y` | `du` / `dU` | `<leader>hs` (toggle) |
| revert hunk | `alt-cmd-z` | `dp` | `<leader>hr` |
| stage everything | `ctrl-cmd-y` | | `<C-s>` (Neogit) |
| commit | `cmd-enter` | | `<leader>Gc` |
| open the real file | `alt-enter` | `g space` | `gf` (diffview) |
| more context around excerpt | `shift-enter` | | |
| blame this line | `cmd-k cmd-b` | `gB` | `<leader>hb` |
| list the diff's files | `cmd-shift-b` (outline) | | |
| split / unified view | `editor: toggle split diff` | | `<leader>vc` |
| fetch (auto-fetch is off) | `ctrl-g ctrl-g` | | `f` (Neogit) |

Branch diffs compare with the last-fetched `origin/<base>`; fetch first.
They have no hunk stage or revert. `alt-cmd-g r` sends an open branch diff to
an agent for review.

## Agent

| Action | Zed | Vim | nvim |
|---|---|---|---|
| focus agent panel; again, back | `cmd-?` | `:A` | `<C-.>`, `<leader>aa` |
| hide agent dock | `ctrl-alt-w`, `cmd-b` (agentic) / `cmd-r` (classic) | | `<leader>aa` |
| full-screen thread; again, restore | `shift-escape` | | |
| new thread / pick agent | `cmd-n` / `alt-cmd-shift-n` (panel) | | `<leader>an` |
| send / send and follow | `enter` / `cmd-enter` | | |
| interrupt and send now | `cmd-shift-enter` | | |
| attach file, symbol, diagnostics | `@` | | `<leader>ap`, `<leader>ae` |
| quote selection into thread | `cmd->` | | `<leader>at`, `<leader>as` |
| model picker / profile / mode | `alt-cmd-/` / `cmd-i` / `shift-tab` | | |
| search thread | `cmd-f` | | |
| prev / next message | `shift-pageup` / `shift-pagedown` | | |
| thread switcher | `ctrl-tab` / `ctrl-shift-tab` | | `<leader>al` |
| next / prev thread (custom) | `alt-]` / `alt-[` | | `<M-]>` / `<M-[>` (same keys) |
| rename thread | `shift-r` (sidebar) | | `<leader>ar` |
| agent diff / project diff | `ctrl-shift-r` / `ctrl-shift-d` | | |
| keep / reject hunk | `cmd-y` / `alt-cmd-z` | | |
| keep all / reject all / undo reject | `alt-shift-y` / `alt-shift-z` / `alt-shift-u` | | |

Vim: `enter` sends from the message box in normal mode too. The agent diff
shows only Zed Agent and omp edits; review Claude Agent and Terminal Thread
edits with `git: diff`.

## Tabs and panes

| Action | Zed | Vim | nvim |
|---|---|---|---|
| next / prev tab | `cmd-}` / `cmd-{` | `]b` / `[b`, `gt` / `gT` | `L` / `H` |
| tab N / last tab | `ctrl-1`…`ctrl-9` / `ctrl-0` | `Ngt` / `]B` | |
| tab switcher | `ctrl-tab` | | `<leader>bb`, `<leader>m` |
| move tab right / left | `ctrl-shift-pagedown` / `ctrl-shift-pageup` | | |
| pin / unpin | `cmd-k shift-enter` | | |
| close tab | `cmd-w` | `:q`, `ctrl-w c` | `<leader>bx` |
| close and save / discard | — | `ZZ` / `ZQ` | |
| reopen closed tab | `cmd-shift-t` | | |
| close other tabs | `alt-cmd-t` | | `<leader>bo` |
| close tabs left / right / clean | `cmd-k e` / `cmd-k t` / `cmd-k u` | | |
| close all tabs in pane | `cmd-k w` | `ctrl-w a` | |
| close inactive tabs and panes | `ctrl-alt-cmd-w` | `ctrl-w o` | |
| close all tabs and panes / window | `cmd-k cmd-w` / `cmd-shift-w` | | |
| split right / down | `cmd-\` / `cmd-k down` | `ctrl-w v` / `ctrl-w s` | |
| focus pane in a direction | `cmd-k cmd-<arrow>` | `ctrl-w h/j/k/l` | `<C-h/j/k/l>` |
| focus pane N | `cmd-1`…`cmd-9` | | |
| next pane | — | `ctrl-w w` | |
| move pane to an edge / swap | — | `ctrl-w H/J/K/L` / `ctrl-w x` | |
| resize / maximize / equalize | — | `ctrl-w <>+-` / `ctrl-w _` / `ctrl-w =` | `<A-h/j/k/l>` (resize) |
| zoom pane or panel; again, restore | `shift-escape` | | |

## Panels and docks

| Action | Zed | Vim | nvim |
|---|---|---|---|
| left / right / bottom dock | `cmd-b` / `cmd-r` / `cmd-j` | | |
| all docks (not from an editor) | `alt-cmd-y` | | |
| close focused dock | `ctrl-alt-w` | | |
| zoom focused panel; again, restore | `shift-escape` (agent, terminal, debug) | | |
| cycle focus: docks, center | `f6` / `shift-f6` | | |
| grow / shrink / reset dock | `ctrl-alt-=` / `ctrl-alt--` / `ctrl-alt-0` | | |

A panel's focus key, pressed inside it, returns to the editor and leaves the
panel open; close it with `ctrl-alt-w`. The agent dock is `cmd-b` in the
agentic layout, `cmd-r` in classic. Zoom does nothing in the project, git, and
outline panels.
Docks are not panes: `ctrl-w h/j/k/l` never reaches them.

### Project panel

nvim column: nvim-tree.

| Action | Zed | Vim | nvim |
|---|---|---|---|
| open, focus; again, back | `cmd-shift-e` | `:E`; back: `escape` | `<leader>e` |
| close | `ctrl-alt-w` | | `<leader>e`, `q` |
| preview | `space` | `p` | |
| open in a permanent tab | — | `enter`, `t` | `l`, `<CR>` |
| open in a vertical / horizontal split | — | `v` / `o` | `<C-v>` / `<C-s>` |
| new file / folder | `cmd-n` / `alt-cmd-n` | `%` / `d` | `a` / `a` + `name/` |
| rename | `enter`, `f2` | `R` | `r` |
| move to trash | `backspace` | `D` | |
| duplicate / cut / copy / paste | `cmd-d` / `cmd-x` / `cmd-c` / `cmd-v` | | — / `x` / `c` / `p` |
| undo / redo file operation | `cmd-z` / `cmd-shift-z` | | |
| collapse / expand | `left` / `right` | `h` / `l` | |
| collapse / expand all | `cmd-left` / `cmd-right` | | `W` (collapse) |
| parent / next, prev directory | — | `-` / `}`, `{` | |
| next / prev git change | — | `]c` / `[c` | |
| filter / search in this directory | — | `/` | `f` |
| reveal in Finder / copy path | `alt-cmd-r` / `alt-cmd-c` | `x` (reveal) | |

### Outline panel

Symbols of the current file; in a multibuffer (search, references, diffs), its
files. nvim column: aerial.

| Action | Zed | Vim | nvim |
|---|---|---|---|
| open, focus; again, back | `cmd-shift-b` | | `<leader>o` |
| close | `ctrl-alt-w` | | `<leader>o`, `q` |
| jump to entry | `space` | `enter` (focuses the editor) | `<CR>` |
| collapse / expand | `left` / `right` | `h` / `l` | |
| parent entry | — | `-` | |
| open the real file / in a split | `alt-enter` / `alt-cmd-enter` | | |
| reveal in Finder / copy path | `alt-cmd-r` / `alt-cmd-c` | | |
| symbol popup instead | `cmd-shift-o` | `gO` | `<leader>O` |

### Git panel

nvim column: the Neogit status buffer.

| Action | Zed | Vim | nvim |
|---|---|---|---|
| open, focus; again, back | `ctrl-shift-g` | `:G` | `<leader>Gg` |
| close | `ctrl-alt-w` | | `q`, `<leader>Gq` |
| Changes / History tab | `cmd-1` / `cmd-2` | | — / `l` (log popup) |
| stage / unstage file | `space` | `x` | `s` / `u` |
| stage a range | `shift-space` | `gx` | |
| stage all / unstage all | `ctrl-cmd-y` / `ctrl-cmd-shift-y` | `X` / `U` | `S` / `U` |
| open the file's diff | — | `gf` | `<CR>` opens the file |
| restore file (asks first) | `backspace` | | `x` |
| list to commit box / back | `tab` / `tab` | `i` / `tab` | |
| commit / amend | `cmd-enter` / `cmd-shift-enter` | | `c` (popup) |
| generate commit message | `alt-tab` (commit box) | | |
| push / pull | `ctrl-g up` / `ctrl-g down` | | `P` / `p` (popups) |

### Threads sidebar

nvim column: the `<leader>av` agent-view sidebar.

| Action | Zed | Vim | nvim |
|---|---|---|---|
| show / hide | `alt-cmd-j` | | `<leader>av` / `q` |
| focus; again, back to the same spot | `alt-cmd-;` | | |
| move | `up` / `down` | `k` / `j` | |
| collapse / expand project | `left` / `right` | `h` / `l` | |
| next / prev project | — | `]p` / `[p` | |
| switch to thread | `enter` | | `<CR>`, `1`…`9` |
| filter by title | `cmd-f` | `/` | |
| new thread in this project | `cmd-n` | `o` | `n` |
| rename | `shift-r` | | `r` |
| archive / delete | `shift-backspace` / `cmd-shift-backspace` | `dd` (delete) | `x` (kill) |
| all threads, by time | `cmd-g` | | |

### Terminal, tasks, debugger

| Action | Zed | Vim | nvim |
|---|---|---|---|
| terminal panel: open / close | `` ctrl-` `` | `:te` | `<C-/>` (float: `<C-\>`) |
| debug panel: open, focus / close | `cmd-shift-d` / `ctrl-alt-w` | `:D` | `<leader>du` |
| new terminal tab | `ctrl-~`, `cmd-n` (panel) | | `<M-n>` (float), `2<C-\>` |
| split / search / clear | `cmd-d` / `cmd-f` / `cmd-k` | | |
| select in scrollback (vi keys) | `ctrl-shift-space` | | `jj`, `<Esc>` (normal mode) |
| task picker / rerun last | `cmd-shift-r` / `alt-cmd-r` | | |
| debug: start / continue / stop | `f4` / `f5` / `shift-f5` | | `<F5>` / `<F5>` / `<leader>dq` |
| step over / into / out | `f10` / `f11` / `shift-f11` | | `<F12>` (out) |
| toggle breakpoint / pause | `f9` / `f6` (running) | | `<leader>db` (breakpoint) |

## Vim-only extras

None of these exist in the nvim config.

- Text objects: `iq`/`aq` any quotes, `if`/`af` function, `ic`/`ac` class,
  `ia`/`aa` argument, `ii`/`ai` indent, `ie` whole file
- Surround: `ys` + motion + char, `cs"'`, `ds"`
- Jump: `]m`/`[m` method, `]]`/`[[` section, `]r`/`[r` same symbol
- `gR` + motion replace with register; `cx` + motion twice to exchange
- `:` commands take no file argument (no `:e file`); use `cmd-p` or `gf`

## Zed itself

| Action | Zed | nvim |
|---|---|---|
| keymap editor, searches every action | `cmd-k cmd-s` | `<leader>sk` |
| settings | `cmd-,` | |
| markdown: preview to the side | `cmd-k v` | |

Every `.md` opens as a preview (`markdown_preview.open_markdown_files_in_preview`).

## Gotchas

| Key | Editor | Elsewhere |
|---|---|---|
| `cmd-y` | stage hunk, next | agent diff: keep; permission prompt: allow once |
| `alt-cmd-y` | toggle hunk staged | dock: all docks; permission prompt: allow always |
| `alt-cmd-z` | revert hunk | agent diff: reject; permission prompt: reject once |
| `alt-tab` | accept edit prediction | thread: cycle models; commit box: message |
| `shift-escape` | zoom | commit box: expand the editor |
| `enter` | — | project panel: rename; vim project panel: open |
| `ctrl-g` | go to line | vim normal mode: show location (use `:<n>`) |
| `cmd-k` | chord prefix | terminal: clear, so `cmd-k` chords never fire |

Same key, different meaning in nvim:

| Key | Zed vim | nvim |
|---|---|---|
| `H` / `L` | top / bottom of screen | prev / next buffer |
| `gb` | block comment | alternate buffer |
| `<C-h/j/k/l>` | backspace, down, kill line, center | focus split |
| `space` | move right (no leader yet) | leader |
| `x`, git panel | stage | discard (Neogit) |
| `x`, project panel | reveal in Finder | cut (nvim-tree) |
| `d`, project panel | new folder | delete permanently (nvim-tree) |
| `f12` | go to definition (any mode) | debugger step out |
| `ys`, `cs`, `ds` | surround | not mapped |

- A `●` on a tab you didn't edit means the file changed on disk. Don't `cmd-s`;
  run `editor: reload file` or close with Don't Save.
- `cmd-w` closes the tab, never the dock; `ctrl-alt-w` closes the dock.
- `cmd-t` / `gS` see only running language servers; a server starts when you
  open a file in its language.
- Vim: `ctrl-c` is escape, not copy. Regex is Rust's: `(a|b)`, `$1`.
- Adopting nvim keys in Zed: `docs/zed-vim-keymap.md` has a ready block.
