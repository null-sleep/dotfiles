# Cheatsheet

Opened by `cmd-k cmd-m` in Zed (task `cheatsheet`). Scroll with arrows / space, quit with `q`.

Toggle vim mode: `cmd-k cmd-v`.

## Review changes
Keys here come from Zed's default keymap; the diff views haven't been tried in a running Zed yet.

- `ctrl-g d` (in the git panel) or `git: diff` — uncommitted changes
- `git: diff branch` — whole branch against its base, the PR view (no key; use the palette)
- `git: compare with branch` — diff against another base
- `cmd-y` / `cmd-shift-y` — stage / unstage hunk and jump to the next
- `cmd-alt-z` — revert hunk; `cmd-ctrl-y` — stage everything
- `cmd-enter` — commit (from the diff or the commit box)
- `cmd-down` / `cmd-up` — next / previous excerpt; `alt-enter` — open the real file
- `cmd-shift-b` — outline panel, lists the diff's files
- `ctrl-shift-g` — git panel; `ctrl-g ctrl-g` — fetch (auto-fetch is off)
- `cmd-'` — show old text inline for a hunk; `cmd-f8` / `cmd-shift-f8` — next / previous hunk

## Agent threads
- `cmd-?` — focus agent panel; again, back to the editor
- `cmd-alt-j` — toggle threads sidebar; `cmd-alt-;` — jump to it and back
- `ctrl-tab` / `ctrl-shift-tab` — thread switcher, most recent first (in the agent panel)
- `alt-]` / `alt-[` — next / previous thread directly
- `cmd-n` — new thread; `enter` — send; `cmd-enter` — send and follow
- `ctrl-shift-r` — open the agent diff (review changes)
- `alt-shift-y` / `alt-shift-z` — keep all / reject all; `alt-shift-u` — undo last reject
- `cmd-b` / `cmd-r` — hide / show the agent dock (`cmd-b` agentic layout, `cmd-r` classic)

## Pickers and navigation
- `cmd-p` — file finder; `cmd-shift-p` — command palette
- `alt-cmd-f` — live grep picker; `cmd-shift-f` — project search
- `cmd-t` — project symbols; `cmd-shift-o` — symbols in this file
- `ctrl-g` — go to line; `cmd-shift-m` — all diagnostics
- `ctrl--` / `ctrl-_` — go back / forward through navigation history
- `cmd-k cmd-p` — reopen the last picker
- `cmd-alt-o` — recent projects; `cmd-ctrl-b` — branch picker; `cmd-ctrl-w` — worktree picker
- In any picker: `enter` confirm, `cmd-enter` open in a split, `escape` cancel

## Editing and LSP
- `f12` / `alt-shift-f12` — go to definition / find references
- `f2` — rename; `cmd-.` — code actions
- `cmd-shift-i` — format; `cmd-/` — toggle comment
- `cmd-s` — save (formats in some languages); `cmd-k s` — save without formatting
- `cmd-n` — new file

## Docks, zoom and terminal
- `cmd-shift-e` — project panel; `ctrl-shift-g` — git panel
- `cmd-b` / `cmd-r` / `cmd-j` — toggle left / right / bottom dock
- `shift-escape` — zoom the focused pane or panel (again to restore)
- `ctrl-alt-w` — close the focused dock (`cmd-w` closes the tab, not the dock)
- `f6` / `shift-f6` — cycle focus between docks and center
- `` ctrl-` `` — terminal; `cmd-shift-r` — task picker; `cmd-alt-r` — rerun last task

## Tabs
- `ctrl-tab` / `ctrl-shift-tab` — tab switcher (in editors); `ctrl-backspace` closes the selected tab
- `cmd-}` / `cmd-{` — next / previous tab (also `alt-cmd-right` / `alt-cmd-left`)
- `ctrl-1` … `ctrl-9` — jump to tab N; `ctrl-0` — last tab
- `ctrl-shift-pagedown` / `ctrl-shift-pageup` — move tab right / left
- `cmd-k shift-enter` — pin / unpin tab

## Closing
- `cmd-w` — close tab
- `cmd-shift-t` — reopen closed tab
- `alt-cmd-t` — close other tabs
- `cmd-k e` / `cmd-k t` — close tabs to the left / right
- `cmd-k u` — close clean (unmodified) tabs
- `cmd-k w` — close all tabs
- `cmd-k cmd-w` — close all tabs and panes
- `ctrl-alt-cmd-w` — close inactive tabs and panes
- `cmd-shift-w` — close window

## Panes and splits
- `cmd-\` — split right
- `cmd-k up/down/left/right` — split in that direction
- `cmd-k cmd-up/down/left/right` — focus the pane in that direction
- `cmd-1` … `cmd-9` — focus pane N

## Vim mode
Defaults only; nothing from the nvim config is mapped yet.

### Tabs and files
- `]b` / `[b` — next / previous tab (also `gt` / `gT`; `3gt` jumps to tab 3)
- `]B` / `[B` — last / first tab
- `ctrl-^` — alternate file
- `ctrl-o` / `ctrl-i` — jump list back / forward (follows `gd` across files)
- `ZZ` / `ZQ` — close tab, saving / discarding
- `ctrl-w c` — close tab; `ctrl-w o` — close other tabs; `ctrl-w a` — close all tabs in the pane
- `:w` `:q` `:wq` `:bd` — save / close tab; `:tabn` `:tabp` `:tabnew` `:tabc` `:ls` — tab strip
- `:` — command palette, so every Zed action works as `:<action name>`

### Panes (`ctrl-w`)
- `ctrl-w h/j/k/l` — focus pane; `ctrl-w w` / `ctrl-w p` — cycle panes
- `ctrl-w v` / `ctrl-w s` — split vertical / horizontal (`:vsp` / `:sp`)
- `ctrl-w H/J/K/L` — move pane to an edge; `ctrl-w x` — swap with next pane
- `ctrl-w >` `<` `+` `-` — resize; `ctrl-w _` — maximize; `ctrl-w =` — equalize
- `shift-escape` — zoom the focused pane or panel (again to restore)
- Docks (project / agent panels) are not panes: use `cmd-shift-e`, `cmd-?`, or `f6` / `shift-f6` to move between them

### Code navigation
- `gd` / `gD` / `gy` / `gI` — definition / declaration / type / implementation
- `gA` — references; `K` or `gh` — hover; `grn` — rename; `gra` or `g.` — code actions
- `gs` / `gS` — symbols in file / project; `g/` — project search; `g space` — open the file from a multibuffer
- `]d` / `[d` — next / previous diagnostic; `]c` / `[c` — next / previous git hunk
- `]m` / `[m` — next / previous method; `]]` / `[[` — next / previous section
- `ctrl-w d` — definition in a split

### Editing
- `gcc` — toggle line comment; `gc` + motion — comment a range
- `ysiw)` / `cs"'` / `ds"` — surround add / change / delete
- `gl` — add cursor at next match; `ga` — cursor at every match
- `iq` / `aq` — inside / around any quotes; `if` / `af` — function; `ic` / `ac` — class
- `do` — show hunk diff; `dp` — revert hunk; `du` — stage hunk and go to next

## Markdown
- `cmd-shift-v` in a preview — show source (edit the file); in source — open the preview
- `cmd-k v` — open the preview to the side

## Keybindings
- `cmd-k cmd-s` — keymap editor (search any action and its binding)
- `cmd-k cmd-m` — open this cheatsheet

## Gotchas
- A `●` on a tab you didn't edit means it's stale (the file changed on disk). Don't `cmd-s` it; run `editor: reload file` or close it with Don't Save.
- `cmd-y` is stage-and-next in an editor, keep-hunk in agent review, and allow-once in a permission prompt.
- `cmd-alt-y` is toggle-all-docks, but toggle-staged on an editor hunk and allow-always in a thread.
- `cmd-alt-z` reverts a hunk in an editor, but rejects the hunk in the agent diff.
- `shift-escape` zooms, but expands the commit editor in the git commit box.
- `alt-tab` accepts an edit prediction in the editor, cycles favorite models in a thread, and generates a commit message in the git panel.
- `cmd-alt-g r` only works inside a branch diff; open the diff first with `git: diff branch`.
- Branch diffs use the last-fetched `origin/<base>`; fetch first (`ctrl-g ctrl-g`).
