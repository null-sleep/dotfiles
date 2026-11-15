# Cheatsheet

Opened by `cmd-k cmd-m` (Zed task `cheatsheet`) as a markdown preview.
To edit it, press `cmd-shift-v` (show source).

Toggle vim mode: `cmd-k cmd-v`

Sections: Review changes, Agent threads, Pickers and navigation, Editing and LSP,
Docks and panels, Tabs / closing / panes, Zed itself, Gotchas, Vim mode (last).

## Review changes
- `ctrl-g d` in the git panel — uncommitted changes
- palette: `git: diff` — the same, from anywhere
- palette: `git: diff branch` — whole branch vs its base, the PR view (no key)
- palette: `git: compare with branch` — diff against another base
- `cmd-y` / `cmd-shift-y` — stage / unstage hunk, jump to the next
- `alt-cmd-z` — revert hunk
- `ctrl-cmd-y` — stage everything
- `cmd-enter` — commit (diff view or commit box)
- `cmd-down` / `cmd-up` — next / previous excerpt
- `alt-enter` — open the real file
- `cmd-shift-b` — outline panel, lists the diff's files
- `ctrl-shift-g` — git panel
- `ctrl-g ctrl-g` — fetch (auto-fetch is off)
- `cmd-'` — show old text inline for a hunk
- `cmd-f8` / `cmd-shift-f8` — next / previous hunk

## Agent threads
- `cmd-?` — focus agent panel; again, back to the editor
- `alt-cmd-j` — toggle threads sidebar
- `alt-cmd-;` — jump to the sidebar and back
- `ctrl-tab` / `ctrl-shift-tab` — thread switcher, most recent first (agent panel)
- `alt-]` / `alt-[` — next / previous thread directly
- `cmd-n` — new thread (panel focused)
- `enter` / `cmd-enter` — send / send and follow
- `ctrl-shift-r` — open the agent diff
- `cmd-y` / `alt-cmd-z` — keep / reject one hunk
- `alt-shift-y` / `alt-shift-z` — keep all / reject all
- `alt-shift-u` — undo last reject

## Pickers and navigation
- `cmd-p` — file finder
- `cmd-shift-p` — command palette
- `alt-cmd-f` — live grep picker
- `cmd-shift-f` — project search
- `cmd-t` — project symbols
- `cmd-shift-o` — symbols in this file
- `ctrl-g` — go to line
- `cmd-shift-m` — all diagnostics
- `ctrl--` / `ctrl-_` — back / forward through navigation history
- `cmd-k cmd-p` — reopen the last picker
- `alt-cmd-o` — recent projects
- `ctrl-cmd-b` — branch picker
- `ctrl-cmd-w` — worktree picker
- In a picker: `enter` confirm, `cmd-enter` open in a split, `escape` cancel

## Editing and LSP
- `f12` / `alt-shift-f12` — go to definition / find references
- `f2` — rename
- `cmd-.` — code actions
- `cmd-shift-i` — format
- `cmd-/` — toggle comment
- `cmd-s` — save (formats in some languages)
- `cmd-k s` — save without formatting

## Docks and panels

### Open or focus a panel
- `cmd-shift-e` — project panel
- `cmd-shift-b` — outline panel
- `ctrl-shift-g` — git panel
- `cmd-shift-d` — debug panel
- `cmd-?` — agent panel
- `alt-cmd-j` — threads sidebar: show / hide (showing it also focuses it)
- `alt-cmd-;` — threads sidebar: jump to it, press again to return to where you were
- `cmd-shift-c` — collab panel
- `` ctrl-` `` — terminal panel
- Press a focus key again while focused to return to the editor (the panel stays open)
- `` ctrl-` `` is the exception: it closes the focused terminal panel

### Docks
- `cmd-b` / `cmd-r` / `cmd-j` — toggle left / right / bottom dock
- The agent dock is `cmd-b` in the agentic layout, `cmd-r` in classic
- `alt-cmd-y` — hide / show every dock
- `shift-escape` — zoom the focused pane or panel; again to restore
- `ctrl-alt-w` — close the focused dock (`cmd-w` closes the tab, not the dock)
- `f6` / `shift-f6` — cycle focus between docks and center
- `ctrl-alt-=` / `ctrl-alt--` — grow / shrink the focused dock
- `ctrl-alt-0` — reset the dock size

### Project panel
- `space` — preview the selected file
- `enter` / `f2` — rename
- `cmd-n` — new file
- `alt-cmd-n` — new folder
- `cmd-d` — duplicate
- `cmd-x` / `cmd-c` / `cmd-v` — cut / copy / paste
- `backspace` — move to trash
- `left` / `right` — collapse / expand
- `cmd-left` / `cmd-right` — collapse / expand all
- `cmd-z` / `cmd-shift-z` — undo / redo file operations
- `alt-cmd-r` — reveal in Finder
- `alt-cmd-c` — copy path

### Git panel
- `cmd-1` / `cmd-2` — Changes / History tab
- `space` — stage / unstage the selected file
- `shift-space` — stage a range
- `ctrl-cmd-y` / `ctrl-cmd-shift-y` — stage all / unstage all
- `backspace` — restore the selected file (asks first)
- `tab` in the Changes list — jump to the commit box
- `tab` in the commit box — back to the list
- `cmd-enter` — commit
- `cmd-shift-enter` — amend
- `alt-tab` in the commit box — generate a commit message
- `ctrl-g up` / `ctrl-g down` — push / pull
- Fetch and the project diff are under Review changes

### Threads sidebar
- `alt-cmd-j` — show / hide the sidebar
- `alt-cmd-;` — focus it from anywhere (e.g. the message box); again, back to the same spot
- `up` / `down` — move through threads (`ctrl-p` / `ctrl-n` also work)
- `left` / `right` — collapse / expand a project group
- `enter` — switch to the selected thread
- `cmd-f` — filter threads by title
- `cmd-n` — new thread in the selected project
- `shift-r` — rename
- `shift-backspace` — archive; `cmd-shift-backspace` — delete
- `cmd-g` — all threads, all projects, in time order
- `ctrl-tab` / `ctrl-shift-tab` — thread switcher
- `alt-]` / `alt-[` — next / previous thread

### Terminal panel
- `` ctrl-` `` — open / close the terminal panel
- `ctrl-~` — new terminal tab
- `cmd-n` — new terminal tab (panel focused)
- `cmd-d` — split
- `cmd-f` — search
- `cmd-k` — clear (so `cmd-k` chords don't fire in a terminal)
- `ctrl-shift-space` — vi-style scrollback selection
- `cmd-shift-r` — task picker
- `alt-cmd-r` — rerun the last task

### Debugger
- `f4` — start a session (from anywhere)
- `f5` — continue (while stopped)
- `f10` / `f11` / `shift-f11` — step over / into / out (while stopped)
- `f9` in an editor — toggle breakpoint
- `f6` — pause a running session (otherwise it cycles dock focus)
- `shift-f5` — stop the session

## Tabs, closing, panes

### Tabs
- `ctrl-tab` / `ctrl-shift-tab` — tab switcher (editors)
- `ctrl-backspace` — close the selected tab in the switcher
- `cmd-}` / `cmd-{` — next / previous tab
- `alt-cmd-right` / `alt-cmd-left` — the same
- `ctrl-1` … `ctrl-9` — jump to tab N
- `ctrl-0` — last tab
- `ctrl-shift-pagedown` / `ctrl-shift-pageup` — move tab right / left
- `cmd-k shift-enter` — pin / unpin tab
- `cmd-n` — new file

### Closing
- `cmd-w` — close tab
- `cmd-shift-t` — reopen closed tab
- `alt-cmd-t` — close other tabs
- `cmd-k e` / `cmd-k t` — close tabs to the left / right
- `cmd-k u` — close clean (unmodified) tabs
- `cmd-k w` — close all tabs
- `cmd-k cmd-w` — close all tabs and panes
- `ctrl-alt-cmd-w` — close inactive tabs and panes
- `cmd-shift-w` — close window

### Panes and splits
- `cmd-\` — split right
- `cmd-k up/down/left/right` — split in that direction
- `cmd-k cmd-up/down/left/right` — focus the pane in that direction
- `cmd-1` … `cmd-9` — focus pane N

## Zed itself
- `cmd-k cmd-s` — keymap editor (search any action and its binding)
- `cmd-k cmd-m` — open this cheatsheet
- `cmd-shift-v` in a markdown preview — show source (edit the file)
- `cmd-shift-v` in markdown source — open the preview
- Every `.md` opens as a preview (`markdown_preview.open_markdown_files_in_preview`)
- `cmd-k v` — open the preview to the side

## Gotchas
Keys that mean different things by context:
- `cmd-y`: editor = stage and next; agent review = keep; permission prompt = allow once
- `alt-cmd-y`: toggle all docks; editor hunk = toggle staged; in a thread = allow always
- `alt-cmd-z`: editor = revert hunk; agent diff = reject hunk
- `shift-escape`: zoom; in the git commit box = expand the commit editor
- `alt-tab`: editor = accept prediction; thread = cycle models; git panel = commit message

Other:
- A `●` on a tab you didn't edit means the file changed on disk (stale tab).
  Don't `cmd-s` it; run palette `editor: reload file`, or close it with Don't Save.
- `alt-cmd-g r` only works inside a branch diff; open one first with `git: diff branch`.
- Branch diffs use the last-fetched `origin/<base>`; fetch first (`ctrl-g ctrl-g`).
- Not yet tried in a running Zed: the Review changes keys (from Zed's default keymap).

## Vim mode
Defaults only; nothing from the nvim config is mapped yet.
Toggle: `cmd-k cmd-v`. Zoom, docks, and the other non-vim keys above still apply.

### Tabs and files
- `]b` / `[b` — next / previous tab
- `gt` / `gT` — the same; `3gt` jumps to tab 3
- `]B` / `[B` — last / first tab
- `ctrl-^` — alternate file
- `ctrl-o` / `ctrl-i` — jump list back / forward (follows `gd` across files)
- `ZZ` / `ZQ` — close tab, saving / discarding
- `ctrl-w c` — close tab
- `ctrl-w o` — close other tabs
- `ctrl-w a` — close all tabs in the pane
- `:w` `:q` `:wq` `:bd` — save / close tab
- `:tabn` `:tabp` `:tabnew` `:tabc` `:ls` — tab strip
- `:` — command palette; any Zed action works as `:<action name>`

### Panes (`ctrl-w`)
- `ctrl-w h/j/k/l` — focus pane
- `ctrl-w w` / `ctrl-w p` — cycle panes
- `ctrl-w v` / `ctrl-w s` — split vertical / horizontal (`:vsp` / `:sp`)
- `ctrl-w H/J/K/L` — move pane to an edge
- `ctrl-w x` — swap with next pane
- `ctrl-w >` `<` `+` `-` — resize
- `ctrl-w _` — maximize
- `ctrl-w =` — equalize
- Docks are not panes; use the dock keys above (`f6` / `shift-f6`)

### Code navigation
- `gd` / `gD` — definition / declaration
- `gy` / `gI` — type / implementation
- `gA` — references
- `K` / `gh` — hover
- `grn` — rename
- `gra` / `g.` — code actions
- `gs` / `gS` — symbols in file / project
- `g/` — project search
- `g space` — open the real file from a multibuffer
- `]d` / `[d` — next / previous diagnostic
- `]c` / `[c` — next / previous git hunk
- `]m` / `[m` — next / previous method
- `]]` / `[[` — next / previous section
- `ctrl-w d` — definition in a split

### Editing
- `gcc` — toggle line comment
- `gc` + motion — comment a range
- `ysiw)` / `cs"'` / `ds"` — surround add / change / delete
- `gl` — add cursor at next match
- `ga` — cursor at every match
- `iq` / `aq` — inside / around any quotes
- `if` / `af` — inside / around function
- `ic` / `ac` — inside / around class
- `do` — show hunk diff
- `dp` — revert hunk
- `du` — stage hunk and go to next

### Panels
Project, outline, and git lists: `j` / `k` move. Project, outline, and the git
Changes list also take `h` / `l` (collapse / expand) and `gg` / `G` (first / last).
`:` opens the palette in panels (not in editors or the terminal).

#### Project panel
- `enter` / `t` — open (permanent tab)
- `p` — preview open
- `v` / `o` — open in a vertical / horizontal split
- `%` — new file
- `d` — new directory
- `R` — rename
- `D` — delete
- `x` — reveal in Finder
- `-` — select parent
- `}` / `{` — next / previous directory
- `]c` / `[c` — next / previous git change
- `/` — search in this directory

#### Git panel
- `x` — stage / unstage
- `X` / `U` — stage all / unstage all
- `gf` — open the diff
- `gx` — stage a range
- `i` — into the commit box
- `tab` — back to the list

#### Outline panel
- `enter` — focus the editor at the entry
- `-` — parent entry

#### Threads sidebar
- `h` / `l` — collapse / expand a project group
- `/` — filter (`escape` cancels)
- `o` — new thread in this project
- `dd` — delete thread
- `]p` / `[p` — next / previous project
