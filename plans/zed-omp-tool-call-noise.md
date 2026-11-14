# Zed: quieting omp tool-call cards

Status: open idea, nothing built (2026-11-14). Zed 1.28.1, omp 18.20.2. The
options below are researched but untested in a live Zed thread. Option 3 (an
ACP filter wrapper) is the only one that removes the cards.

## Problem

In an omp thread inside Zed, every `bash` call renders as its own "Run Command"
card showing the full `$ <command>`. A research-heavy turn stacks a dozen of
them, interleaved with collapsed "Thinking" headers, and they carry little
information once the turn is done.

## What Zed can and cannot do (v1.28.1)

Read from `agent_settings.rs` and `thread_view.rs` at the `v1.28.1` tag, plus
[all-settings](https://zed.dev/docs/reference/all-settings.md).

- `agent.expand_terminal_card: false` hides command **output** until clicked.
  Shipped in `caadbf6`; it works for omp threads, the cards in the screenshot
  show only the command line.
- `agent.expand_edit_card: false` does the same for edit diffs. Shipped.
- `agent.thinking_display: "always_collapsed"` collapses thinking blocks.
  Shipped in `caf7796`.
- The card **header** is not configurable. Any tool call of kind `execute`
  gets the card layout (`use_card_layout = needs_confirmation || is_edit ||
  is_terminal_tool`), and the header is the tool call's title.
- No setting, action, or key hides or collapses all tool calls. The only
  per-card control is the hover chevron.

## What omp sends (ACP mapper)

Read from the mapper embedded in the omp 18.20.2 binary
(`modes/acp/acp-event-mapper.ts`), not from published docs. omp's docs have no
ACP page beyond approval mode, `--config`, and slash commands.

- Per tool call: one `tool_call` at start, `tool_call_update`s while running,
  one at the end. No setting gates these. `todo` additionally sends `plan`
  updates.
- `bash` / `shell` / `exec` get `kind: "execute"` and the title
  `$ <full command>`. That is the card header Zed shows. `eval` is also
  `execute`. A tool with a model-provided intent uses that as the title;
  otherwise the title is the path, pattern, query, or tool name.
- `read` is `read`, `grep` / `glob` / `ast_grep` are `search`, `write` / `edit`
  are `edit`, `web_search` is `fetch`, `todo` is `think`.
- Text and reasoning go out as separate `agent_message_chunk` and
  `agent_thought_chunk` updates, independent of tool calls.
- `display.hideToolActivity` (and `Ctrl+Shift+O`) affects omp's own TUI
  transcript. The ACP mapper does not read it; expected to have no effect in
  Zed, untested.
- In the screenshot, `read` and `grep` calls render as one compact line, while
  `bash` renders as a card. The difference is the `execute` kind.

## Options

### 1. Change nothing (current state)

Output is collapsed; headers remain. Zero cost.

### 2. Use fewer `bash` calls

Prefer `read`, `grep`, and `find` for lookups; keep `bash` for git, stow, and
scripts. Chain fewer commands per call so each card stays short. This is a
model-behavior change, not config, and it was explicitly declined for now (a
repo-wide rule in `AGENTS.md` was also declined).

### 3. Filter wrapper between Zed and omp

omp speaks newline-delimited JSON-RPC over stdio (verified 2026-11-14: an
`initialize` request to `omp acp --approval-mode yolo` returned
`protocolVersion`, `agentInfo`, and capabilities). Zed's `omp` entry is a
`custom` agent, so `command` can point at a wrapper that spawns the real
`omp acp ...`, forwards everything, and drops selected agent-to-client
`session/update` messages.

Variants, from least to most lossy:

- **Execute-only.** Remember the `toolCallId` of each `tool_call` with
  `kind: "execute"`; drop it and its `tool_call_update`s. Edit cards, diffs,
  reads, and searches stay. Removes the "Run Command" cards and nothing else.
- **All tool calls.** Drop every `tool_call` and `tool_call_update`; only
  prose, thoughts, and plans remain.

Must pass through untouched:

- `session/request_permission` (a separate request type; dropping it hangs
  approval). Mostly idle under `--approval-mode yolo`, but not guaranteed.
- `agent_message_chunk`, `agent_thought_chunk`, `plan`, and every response.

Costs:

- **All-tool-calls variant** likely empties Zed's Review Changes list (built
  from tool-call diffs; `docs/zed.md` depends on it), hides edit locations and
  progress, and leaves you learning about file changes from prose or git.
  Whether Zed misbehaves on tool-less turns (Stop button, running indicator)
  is unknown.
- **Execute-only** loses visibility into what commands ran. A failing command
  would show only through the agent's prose.
- The wrapper depends on omp's wire format staying stable across upgrades.
- Zed's `--config` path and `--approval-mode yolo` args must be forwarded.
- Roughly 40 lines of Node or Bun under `omp/`, plus a Zed `settings.json`
  edit and a README note. A pass-through test is cheap: feed a recorded
  session through the filter and diff the kept messages.

### 4. Terminal Thread instead of an ACP thread

Zed runs omp's own TUI in a terminal pane: no cards, omp's native display
(including `Ctrl+Shift+O`). Loses the Zed-side model dropdown, thinking blocks,
and agent-review integration. Restart behavior is in `docs/zed.md` → Terminal
Threads after a restart.

### 5. Upstream requests

- Zed: a card-density setting such as `agent.tool_call_display: "compact"`.
- omp: an option to shorten or hide titles for `execute` tool calls over ACP.

Neither exists today; either would be a feature request.

### 6. Patch omp

Changing the `bash` kind or title in the mapper would fix it at the source, but
needs a fork of omp. Not recommended; see
[omp-fork-customization.md](omp-fork-customization.md) for the cost ladder.

## Recommendation if picked up

Try option 3's **execute-only** variant first, because it removes exactly the
noise and keeps review intact. Build it so the filter mode is an environment
variable or flag (`execute`, `all`, `off`), so the all-tool-calls variant can
be tried without rewriting.

## If adopted

- Put the wrapper in `omp/`, add it to `omp/.stow-local-ignore` patterns if it
  is not meant to be stowed (the file now ignores `^/setup-.*\.sh` and
  `^/tests`).
- Point the `omp` entry in `zed/.config/zed/settings.json` at it, keeping
  `--approval-mode yolo` and `--config ~/.omp/agent/zed-models.yml`.
- Test in Zed: a thread with a bash call, an edit, and a failing command;
  confirm edit cards, Review Changes, Stop, and approval prompts still work.
- Test the wrapper alone with a recorded ACP session.
- Document in README → Zed and `docs/zed.md` → Agent panel; note the omp
  upgrade risk.
