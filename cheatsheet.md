# Cheatsheet

Opened by `cmd-k cmd-m` in Zed (task `cheatsheet`). Scroll with arrows / space, quit with `q`.

Toggle vim mode: `cmd-k cmd-v`.

## Tabs
- `ctrl-tab` / `ctrl-shift-tab` — tab switcher; `ctrl-backspace` closes the selected tab
- `cmd-}` / `cmd-{` — next / previous tab (also `alt-cmd-right` / `alt-cmd-left`)
- `ctrl-1` … `ctrl-9` — jump to tab N; `ctrl-0` — last tab
- `ctrl-shift-pagedown` / `ctrl-shift-pageup` — move tab right / left
- `cmd-k shift-enter` — pin / unpin tab
- `ctrl--` / `ctrl-_` — go back / forward through navigation history

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

## Files and panels
- `cmd-p` — file finder
- `cmd-shift-p` — command palette
- `cmd-shift-f` — project search
- `cmd-b` — toggle left dock
- `cmd-n` — new file; `cmd-s` — save; `cmd-k s` — save without formatting

## Vim mode
Toggle with `cmd-k cmd-v`. Defaults only; nothing from the nvim config is mapped yet.

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
