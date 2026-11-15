# Zed: stale buffers, autosave, and format-on-save

Status: decided and shipped in `91513fc` (2026-11-14), with checks pending. Zed
1.28.1, omp 18.20.2. Reference text lives in `docs/zed.md` → Gotchas; this file
holds the reasoning and what is still open.

## What happened

The `settings.json` tab in Zed showed a `●` and was missing the `terminal` and
`toolbar` blocks that were on disk. Saving it would have written the old text
through the stow symlink and deleted both. Reopening the tab fixed it. What
made the buffer dirty first was never established.

## How Zed behaves (read from source, not reproduced)

- `Buffer::file_updated` in `crates/language/src/buffer.rs` reloads a buffer
  when its file changes on disk only if `!was_dirty`. A dirty buffer is left
  alone, so Zed never overwrites unsaved edits and never refreshes them either.
- `session.restore_unsaved_buffers` is `true` (Zed's default, also set in
  `settings.json` by `c76418a`), so a dirty buffer can survive a restart and
  meet a later `git pull`. This is the suspect; it is unproven.
- omp's file writes go through Zed (`docs/omp.md`). ACP `write_text_file`
  edits the open buffer, records it for the review view, formats it when the
  language's `format_on_save` is not `off`, and then calls `save_buffer`. Agent
  edits are therefore on disk before review, with or without autosave. Reject
  restores the old text and saves again.
- Upstream: [#38109](https://github.com/zed-industries/zed/issues/38109)
  (out-of-sync buffers, closed after several fixes),
  [#48697](https://github.com/zed-industries/zed/issues/48697) (dirty buffer
  stays stale after undo, closed),
  [#49162](https://github.com/zed-industries/zed/issues/49162) (ACP
  `readTextFile` can return a stale buffer, open, not reproduced since May).

## nvim comparison

nvim does not hit this. `autosave.lua` saves on `BufLeave`, `FocusLost`,
`QuitPre`, `VimSuspend` and 1s after changes; `configs.lua` sets
`autoread` and runs `checktime` on focus, buffer enter, cursor hold, terminal
events, and a 2s poll. nvim only reloads clean buffers too, so the difference
is that autosave keeps them clean. nvim also never restores dirty buffers
across sessions, and `format.lua` keeps `disable_autoformat = true` because
debounced autosave plus format-on-save reformats mid-edit.

## Decisions

- `autosave: { after_delay: { milliseconds: 1000 } }`. Closest Zed mode to
  nvim's debounce. `on_focus_change` was considered and rejected: nvim also
  saves after edits, and the longer a buffer is dirty the longer it can go
  stale.
- Autosaves stay unformatted (`after_delay` skips `format_on_save`); `cmd-s`
  still formats where the language has it on, `cmd-k s` saves without
  formatting, and `editor: format` / `cmd-shift-i` formats on demand.
  Corrected 2026-11-14: the first version said all your saves stay
  unformatted.
- Agent writes keep Zed's defaults and are formatted: ACP `write_text_file`
  formats whenever `format_on_save` is not `off`, with no autosave check.
  omp's docs say formatting may change the text it writes, and the project
  formatter (gofmt, rustfmt, pre-commit, CI) is the source of truth.
- No per-language `format_on_save: "off"`. `settings.json` is global, so it
  would switch off formatting in every Rust or Go project. The only affected
  repo file is `fixtures/animal.rs` (not rustfmt-clean, so an agent write could
  reformat it); the Go fixtures are gofmt-clean.
- `restore_unsaved_buffers` stays `true` for now.

## Pending

- Confirm autosave works: edit a file, wait 1s, check the `●` clears; change
  the file from a terminal and check the tab updates.
- Watch whether autosave interferes with agent edits in the review view. The
  source says omp's writes are already saved, so nothing should change, but it
  was not tried.
- If the stale tab returns, set `session.restore_unsaved_buffers: false`
  (matches nvim, costs unsaved work on quit) and note it here and in
  `docs/zed.md`.
- If agent edits cause formatting-only diffs in a project whose formatter is
  not enforced, add `languages.<Lang>.format_on_save: "off"` for that
  language. For this repo's fixtures only, consider a project-local
  `.zed/settings.json` (not checked that Zed supports it).
- Consider a key for `editor::ReloadFile` if the palette becomes tedious; no
  key conflict check done.
- Re-check against upstream after a Zed upgrade; #49162 is the one that
  affects omp reads.
