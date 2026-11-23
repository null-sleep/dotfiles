# Zed fork: tasks in the command palette

Status: idea, not started (2026-11-22). Fork: `~/src/zed` (`null-sleep/zed`,
see `plans/zed-fork-terminal-thread-notifications.md` for how it's built).

## Context

Stock Zed's command palette (`cmd-shift-p`) lists registered actions only.
User tasks from `tasks.json` (the `cheatsheet` task) and keymap-bound
`task::Spawn` rows never appear in it, and neither `keymap.json` nor
`tasks.json` can add entries. Today the cheatsheet opens via `cmd-k cmd-m`
(dead with a terminal focused, where `cmd-k` clears), `task: spawn` then
picking `cheatsheet`, or `cmd-p` when the repo is in the project.

## Idea

Make the palette also list user tasks (e.g. as `task: <label>`), running them
like `task: spawn` does. Alternatives: a `tasks.json` field that opts a task
into the palette, or a keymap-defined palette alias.

Code to check: `crates/command_palette/src/command_palette.rs` (command
collection), `crates/tasks_ui/` (`Spawn` and the task modal).

## Questions

- Any task, or opt-in per task? Opt-in avoids flooding the palette.
- Small rebasable patch, or upstream PR? Search zed issues for an existing
  request first.
