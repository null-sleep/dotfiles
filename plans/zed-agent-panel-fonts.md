# Zed: agent panel font family and size

Status: decided (2026-11-15). Zed 1.28.1 installed. The code paths below were
read from Zed `main` and tag `v1.28.1` (same code in both), not stepped
through.

## Current settings

In `zed/.config/zed/settings.json`, next to `buffer_font_size`:

```jsonc
"agent_ui_font_family": "Hack Nerd Font Mono",
"agent_ui_font_size": 17,
"agent_buffer_font_size": 15,
```

The rest of Zed is unchanged: `ui_font_size` 15, `buffer_font_size` 15,
`buffer_font_family` Hack Nerd Font Mono.

## Which setting controls what

The agent panel has two kinds of thread, and they use different settings:

- **Chat threads** (Zed's own agent, or omp over ACP) use the agent settings:
  - `agent_ui_font_size` / `agent_ui_font_family`: reply body text. If unset,
    they use `ui_font_size` / `ui_font_family`.
  - `agent_buffer_font_size` / `agent_buffer_font_family`: the message box,
    your sent messages, code blocks, and inline code in replies. The family
    uses `buffer_font_family` if unset.
  - Reply line height is `agent_buffer_font_size × 1.75`
    (`crates/markdown/src/markdown.rs`, `MarkdownStyle::themed_with_overrides`).
    It doesn't follow `agent_ui_font_size`.
  - The message box and code blocks use `buffer_line_height` (default
    `comfortable`, 1.618; `message_editor.rs`).
- **π terminal threads** (omp's own interface in Zed's terminal) use the
  `terminal` block: `terminal.font_size` (15 here), `terminal.font_family`
  (unset, so it uses `buffer_font_family`) and `terminal.line_height` (unset;
  Zed's documented default is `standard`, 1.3). The agent settings don't
  touch them. Changing `terminal.font_size` also resizes the bottom terminal
  pane.

Zed's in-panel zoom (`Cmd` + `=` / `Cmd` + `-`) changes both agent sizes
together (`agent_panel.rs`). The zoomed size is kept in memory and overrides
the settings file until it's reset.

## What happened

1. **Replies looked small and cramped.** With nothing set, replies used the
   sans UI font at `ui_font_size` 15. Setting `agent_ui_font_size` 17 made
   them bigger but still cramped next to the monospace code blocks.
2. **Fix: monospace replies.** Zed has no separate line-spacing setting for
   reply text, so `agent_ui_font_family` became Hack Nerd Font Mono, the
   code-block font. Then 16, then 17.
3. **The message box looked bigger than the replies.** The box was at
   `agent_buffer_font_size` 16 against replies at 17. Measured from a
   screenshot, reply letters are about 7–8% narrower than in the box and code
   blocks, so roughly 15 px on screen. Zed's source says replies render at
   the full `agent_ui_font_size`. The gap is unexplained (screenshot
   estimate, not measured in Zed).
4. **Lowered `agent_buffer_font_size` to 15.** Zed has no setting for the
   message box alone, so code blocks, inline code and reply line spacing
   (28 → 26¼ px) shrank with it. Other users report the same coupling
   ([#38849](https://github.com/zed-industries/zed/discussions/38849)).

## What others use

No survey exists. These are the data points found:

- **Zed defaults** (`assets/settings/default.json`, v1.28.1): `ui_font_size`
  16 in `.ZedSans` (IBM Plex Sans), `buffer_font_size` 15 in `.ZedMono`
  (Lilex), `buffer_line_height` `comfortable`. `agent_ui_font_size` is
  unset (follows the UI size), `agent_buffer_font_size` is 12.
- **Zed docs example**
  ([visual customization](https://zed.dev/docs/visual-customization)):
  `agent_ui_font_family` Inter at 15, `agent_buffer_font_family` Berkeley
  Mono at 12.
- **Zed's "Presenting" profile example** (`default.json`): 20 for
  `agent_ui_font_size`, `buffer_font_size` and `ui_font_size`.
- **Users:**
  - [#30464](https://github.com/zed-industries/zed/discussions/30464): runs
    UI 24 and buffer 20, and had to find the agent-specific settings.
  - [#53206](https://github.com/zed-industries/zed/discussions/53206): wants
    18 for replies because body text looks smaller than code blocks, the same
    mismatch seen here.
  - [#55433](https://github.com/zed-industries/zed/discussions/55433): the
    request that led to `agent_ui_font_family` (shipped in v1.14.2). Some
    users want monospace replies, others serif or sans.

This setup (mono replies at 17, box and code at 15) is on the larger side,
and monospace replies are a choice others make too.

## If revisiting

- Code blocks too small: set `agent_buffer_font_size` back to 16. The message
  box grows with it.
- Want a sans font for replies again: set `agent_ui_font_family` to a roomy
  sans (Inter needs installing). Line spacing still comes from
  `agent_buffer_font_size × 1.75`.
- Find out why replies render at about 15 px: check the size in Zed itself
  (not a screenshot) and look for an in-memory zoom override
  (`AgentUiFontSize` global).
- Watch Zed for a message-box-only size setting.
