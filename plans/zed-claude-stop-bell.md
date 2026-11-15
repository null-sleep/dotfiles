# Instant Claude terminal bell (Zed + Ghostty)

Status: implemented 2026-11-15. `Stop` and `PermissionRequest` (via an
AskUserQuestion prompt) verified live in Zed stable 1.28.1 (pop-up: terminal
icon, Claude's session title, project name, no caption). Ghostty's bell, Dock
bounce and desktop banner also confirmed.
Replaces the global `preferredNotifChannel: "terminal_bell"` setting.

## Target

The omp ACP integration's notifications are the ideal: instant, and Zed knows
when the agent finished or is waiting. A Claude Terminal Thread should match
their timing, sound and pop-up as closely as a bell allows.

## How Zed notifies (from `~/src/zed` source)

- **ACP threads** (`crates/agent_ui/src/conversation_view.rs`): a pop-up plus
  sound right as each thread event happens, captioned "Finished running tools"
  / "New message", "Waiting for tool confirmation", "Waiting for input", or an
  error, refusal or token-limit warning.
- **Terminal Threads** (`crates/agent_ui/src/agent_panel.rs`,
  `mark_terminal_notification`): a bell (BEL) from an unfocused thread
  produces the same sound and pop-up. The pop-up shows the thread title with
  a terminal icon and has no caption line. Bells are ignored while the thread is
  visible. After one pop-up, further bells are silent until the thread is
  focused. Closing the pop-up does not reset that.
- Zed's terminal has no OSC 9/99/777 desktop-notification support, so BEL is
  the only lever.

## Why not `preferredNotifChannel`

- `terminal_bell` waits `messageIdleNotifThresholdMs` (60 s) after a turn and
  then rings only if you haven't typed. Permission and question bells wait 6 s
  and are cancelled if you answer first. The `Notification` hook has the same
  delays.
- `auto` sends nothing in Zed (its detection covers only Apple Terminal, iTerm,
  kitty and Ghostty), but it gives Ghostty real desktop notifications.

## Design

`claude/.claude/hooks/terminal-bell.sh` returns a `terminalSequence` (title change +
BEL, see below) when `TERM_PROGRAM=zed`. In Ghostty it returns a bare BEL:
the Dock bounce + 🔔 the global `terminal_bell` channel gave, now instant, with
Claude's `auto` banner still following later. (Renamed from `zed-bell.sh` for
this.) Claude writes the sequence to its own terminal (hooks
have no controlling tty, so `/dev/tty` fails). Registered synchronously on:

- `Stop`: turn finished.
- `StopFailure`: turn ended on an API error (fires instead of `Stop`).
- `PermissionRequest`: a permission prompt is shown. It fires only on the "ask"
  path, so not for allowed calls, in bypass mode, or in auto mode unless
  escalated. AskUserQuestion prompts also come through it. Without `permissionRequestResult`, the hook doesn't touch the
  decision.
- `Elicitation`: an MCP server asks for input. The script always exits 0,
  because exit 2 would decline it.

`preferredNotifChannel` is removed, so other terminals use `auto` again.

Facts checked against the 2.1.325 binary and the hooks docs:

- `terminalSequence` is honoured on every event, but not for async hooks or
  under `-p`/SDK. That excludes nested `claude -p` and Claude Code over ACP, so
  no guard is needed for them. The "personal hooks" filter applies only under
  `CLAUDE_CODE_RESTRICT_PERSONAL_CONFIG`.
- `TERM_PROGRAM=zed` is set in every Zed terminal. In the ordinary terminal
  panel Zed's `terminal.bell` defaults to off, so the bell is harmless there.
  Shells nested inside Zed (herdr, nvim's terminal) inherit the variable; that's
  fine.

## Compared with omp over ACP

| | omp over ACP | Claude Terminal Thread |
|---|---|---|
| Timing | instant | instant |
| Sound + pop-up, click to focus | yes | yes |
| Suppressed while visible | yes | yes |
| Caption (why it fired) | yes, own line | in the title |
| Icon | agent | terminal |
| Second event before you look | new pop-up | silent until focused |
| After closing the pop-up | still notifies | silent until focused |

Closing the gaps needs Zed changes; fork work is scoped in
[zed-fork-terminal-thread-notifications.md](zed-fork-terminal-thread-notifications.md). Watch Zed adopting OSC 7501 (Program
Status Protocol, [discussion #65412](https://github.com/zed-industries/zed/discussions/65412)),
which Claude Code emits since 2.1.295 and which would make this hook
unnecessary. Also watch [#63482](https://github.com/zed-industries/zed/issues/63482) and
[#66287](https://github.com/zed-industries/zed/issues/66287) (system
notifications).

## Caption via the title

Zed's pop-up has no caption line but shows the terminal title read at bell
time. So the hook sends OSC 2 `<why> · <session title>` followed by the BEL in
one `terminalSequence`. Claude's parser accepts several sequences in one string.

- Why: `✓ Finished`, `✗ Error: <error>`, `⚠ Needs permission: <tool>`,
  `? Question for you` (AskUserQuestion), `☰ Plan ready for review`
  (ExitPlanMode), `? Input requested: <mcp server>`. Built from the hook's
  stdin.
- The glyph matters for threads renamed in Zed: the custom name replaces the
  terminal title, but Zed keeps a leading symbol + space from it
  (`terminal_title_prefix`), so the pop-up reads e.g. `✓ Claude Notifications`.
- Session title: the last `customTitle` (from /rename), otherwise the last
  `aiTitle`, read from `transcript_path`.
- Without `jq` or with unparseable input, it falls back to a bare BEL.
- Cost: the thread's sidebar title shows the caption until Claude rewrites
  its own title.

Verified live: `Question for you · MCP server setup` and `Finished · MCP server
setup` (before glyphs). A renamed thread showed only its name, which is why
the glyphs were added; with them it shows `✓ Claude Notifications` (verified).
