# Zed: pick claude or omp per Terminal Thread

Status: proposed (2026-11-15). Nothing built. Option 1 is the preferred
shape; settle the open questions before implementing.

## Problem

`+ > Terminal` in Zed's agent panel is a single entry, and
`agent.terminal_init_command` is a single string. It is currently
`"claude"`, so every new Terminal Thread starts Claude. Getting omp's TUI
(its extensions, the `Alt+O` picker) means Ctrl-C and typing `omp` each time.
The omp ACP entry under External Agents is a different thing (Zed's UI over
omp's ACP mode) and stays regardless.

## What Zed offers (checked 2026-11-15)

- One Terminal entry in the `+` menu. No setting adds named terminal entries
  such as "Terminal (claude)" and "Terminal (omp)". Only ACP `agent_servers`
  entries get their own rows.
- `agent.terminal_init_command` is typed into the shell as if you had typed
  it, so the configured shell interprets it. It runs when a Terminal Thread
  is created and again when a saved one is recreated after reopening a
  project. The terminal stays an interactive shell after the command exits.
  Docs: <https://zed.dev/docs/ai/terminal-threads>.
- Zed's own docs call it a plain string with no template variables. A
  per-terminal id substitution is only a proposal
  (zed-industries/zed#60306).
- An `agent.terminal_command` setting that launched a program and routed the
  `+` button to it was proposed in zed#57953 and closed when
  `terminal_init_command` (#59374) shipped.

## Option 1 (preferred): a picker as the init command

Point the init command at a small zsh function and keep one `+ > Terminal`
entry:

```jsonc
"agent": { "terminal_init_command": "zagent" }
```

`zagent` lives in `zsh/.zshrc_config.zsh` next to the `claude` function. It
asks which agent to run, runs the choice, and falls through to a plain
shell for the third answer (and after the agent exits, as today):

```
agent? [c]laude  [o]mp  [s]hell  (default c):
```

Gains:

- Fully inside supported Zed settings; no keymap tricks.
- One keypress per new thread; Enter alone keeps today's behaviour (Claude).
- Also runs when a saved thread is recreated after a restart, so a restored
  thread asks again. That is better than silently starting Claude in a thread
  that was running omp.

Costs:

- A prompt on every new thread, including the ones where you want a plain
  shell or `pi`/`codex` (answer `s`, then type it).
- The shell function must exist in every interactive shell Zed spawns. It is
  stowed with zsh, so a machine without it prints `command not found`.
- Reuse the existing `claude` function (it picks the theme when inside Zed)
  rather than calling the binary directly.

## Option 2: keep `claude` as the default, switch by hand

Today's behaviour. No change. Costs one Ctrl-C plus `omp` for every omp
thread.

## Option 3: one-key launchers in `keymap.json`

Bind `agent::NewTerminalThread` followed by `workspace::SendKeystrokes`
typing `omp` and Enter, plus a second binding for `claude`. That gives
separate "new claude" and "new omp" keys.

Not verified:

- Whether `SendKeystrokes` reaches a freshly spawned Terminal Thread shell
  reliably, or races its startup.
- `terminal_init_command` would have to be cleared, or it would fire first
  and start Claude underneath the typed `omp`.
- The accepted action argument shape on the installed Zed (see
  `docs/zed-vim-keymap.md`, which notes it was not verified).

Only worth trying on top of Option 1, and only if a picker prompt feels too
slow.

## Open questions

- Prompt shape: single keypress (`read -k 1`) or a `select` menu. A
  keypress is faster; a menu is easier to extend to `pi`/`codex`.
- Whether `zagent` should be a shell function (stowed with zsh) or a script
  on `PATH`. A function can reuse the `claude` function's Zed theme logic
  directly.
- Whether restored threads should re-ask or remember the previous choice.
  Remembering needs a per-terminal id, which Zed does not expose (#60306).

## If adopted

- Add `zagent` to `zsh/.zshrc_config.zsh`; set
  `agent.terminal_init_command` to `"zagent"` in
  `zed/.config/zed/settings.json`.
- Update README → Zed (the settings.json bullet that says
  `terminal_init_command` starts `claude`) and `docs/zed.md` → Agent panel,
  Terminal Thread notifications, and Terminal Threads after a restart, which
  all assume a Claude-only init command.
- Test in Zed: new thread, answer each of the three choices; restart Zed and
  confirm a restored thread prompts again.
