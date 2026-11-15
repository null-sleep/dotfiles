# Zed fork: richer Terminal Thread notifications

Status: idea, not started (2026-11-15). Scope only; another session will dig
in. Fork: `~/src/zed` (`null-sleep/zed`, built and launched with `zed-dev` /
`Zed Dev.app`, see README).

## Context

`plans/zed-claude-stop-bell.md` gets Claude Terminal Threads to instant pop-ups
from the dotfiles side: a hook sets the terminal title to `<why> · <session
title>` and rings BEL. That's as far as stock Zed allows. The remaining gaps
against omp's ACP notifications are all in Zed:

- No caption line. The reason is stuffed into the title, which also renames
  the thread in the sidebar until Claude rewrites it.
- One pop-up per thread until it's focused (`has_notification`). Closing the
  pop-up doesn't reset it, so a later permission prompt after a finish is
  silent.
- Terminal icon instead of an agent icon; no distinction between finished,
  waiting and error.

Code: `crates/agent_ui/src/agent_panel.rs` (`mark_terminal_notification`,
`show_terminal_notification`, `pop_up_terminal_notification`,
`dismiss_terminal_notifications`), `crates/terminal/src/alacritty.rs`
(event mapping), and the ACP counterpart in
`crates/agent_ui/src/conversation_view.rs` (`notify_with_sound`,
`show_notification`).

## Options, roughly by effort

0. **Option to skip the Dock bounce.** Every agent pop-up (Terminal Thread
   and ACP) calls `window.request_attention()` (`agent_panel.rs`
   `show_terminal_notification`, `conversation_view.rs` `show_notification`),
   which on macOS is one informational Dock bounce while Zed is unfocused
   (`gpui_macos/src/window.rs` `request_attention`, from #58779). Stock Zed
   can only drop it with `notify_when_agent_waiting: "never"`, which also kills
   the pop-up. Add a setting (e.g. `agent.request_attention_when_agent_waiting:
   false`) that keeps pop-up + sound but skips the bounce. Wanted: confirmed
   2026-11-15 that Zed's own icon bounces on Claude Terminal Thread pop-ups.
   (Ghostty's bounce is separate and intended: `terminal-bell.sh` rings BEL
   there on purpose.)
1. **Reset on dismiss.** Clear `has_notification` when the pop-up is
   dismissed, so the next bell notifies again. Small, self-contained, and
   plausibly upstreamable.
2. **Caption from a desktop-notification escape code.** Parse OSC 9 / OSC 777
   `notify` / OSC 99 in the terminal and pass the body as the
   `AgentNotification` caption (it's hard-coded `None` today). The hook would
   then send OSC 9 instead of rewriting the title, so the sidebar title stays
   intact. Claude's `terminalSequence` allowlist already permits these. Needs
   alacritty's parser to surface them (check whether the vendored alacritty
   exposes unknown OSCs; an upstream OSC 9 PR, #58012, was closed unmerged;
   see discussion #58285 for why).
3. **OSC 7501 Program Status Protocol.** Claude Code emits it since 2.1.295
   (working / needs approval / done). Supporting it in Terminal Threads would
   give state-aware captions and icons with no hook at all, and could drive the
   sidebar status like ACP threads. Biggest win, biggest change. Upstream
   discussion #65412 has had no response.

Related upstream: #63482 and #66287 (system notifications for terminal
threads), #65484 (`ZED_TERMINAL_THREAD_ID` env var, which would let the hook
target only Terminal Threads), #61424 (bells from remote-project threads don't
notify).

## Questions for the follow-up session

- Which option to start with. 1 is quick; 2 or 3 removes the title hack.
- Keep the changes as a small rebasable patch set on the fork, or aim for
  upstream PRs?
- If 2 or 3 lands, update `terminal-bell.sh` to send OSC 9 / rely on OSC 7501
  inside `zed-dev` only. That needs a way to tell the fork from stable,
  e.g. `TERM_PROGRAM_VERSION` or an env var the fork sets.
