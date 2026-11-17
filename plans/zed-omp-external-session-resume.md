# Zed fork: resume terminal-created omp sessions in ACP

Status: candidate for the private Zed fork, not started (2026-11-17). Zed can
restore ACP sessions it created, but it does not offer saved sessions created
independently by `omp` in a terminal. omp already exposes the required ACP
session capabilities; the missing piece is Zed's external-agent session picker
and load flow.

## Problem and verified evidence

An omp session started from the terminal is persisted under
`~/.omp/agent/sessions/` and can be resumed in a terminal with `omp -r` or
`omp -c`. Its transcript cannot currently be adopted into a Zed omp ACP chat
thread.

The important ownership boundary is not whether a model/provider is cloud
hosted. Zed restores ACP threads that **Zed created and recorded**, including
an omp ACP thread first started in Zed. A terminal-created omp session is owned
only by omp's local session store; Zed neither discovers it in Thread History
nor currently asks the agent to present a picker for it. The desired feature is
therefore session adoption, not provider-history synchronization or a scan of
`~/.omp/agent/sessions/`.

Verified on omp 18.22.0 on 2026-11-17, using
`omp acp --config ~/.omp/agent/zed-models.yml` directly over stdio:

- The ACP initialize response advertises `loadSession: true` and the session
  capabilities `list`, `resume`, `fork`, and `close`.
- `session/list` returned the terminal-created session:

  ```text
  sessionId:  01a1e853-89a5-7699-807d-aeda2582ac71
  cwd:        /Users/dhruv/src/dotfiles
  title:      ZED: Test resuming session in Zed
  updatedAt:  2026-11-17T07:11:10.631Z
  messages:   2
  ```

- Its cwd is the open `dotfiles` workspace, so its absence from Zed's threads
  is not a project-path mismatch.
- Zed does not show this session in Thread History or offer an external-agent
  session picker/load action.

This is a Zed UI/lifecycle gap, not an omp persistence or ACP-protocol gap.
The concrete evidence is the omp server's own capability and list responses.

### Related ACP configuration finding (not a workaround)

A separate source check against Zed `main` at `482e765` found that Zed accepts
and renders generic external-agent ACP configuration options: selects including
`model_config`, plus booleans (Zed advertises
`session.configOptions.boolean` during ACP initialization). That would let omp
expose an ordinary per-thread option such as a fast-mode control, but it cannot
adopt a different saved session: config options modify an already-existing ACP
session. Zed's built-in `agent::ToggleFastMode` is native-thread-only, so it is
also unrelated to session loading.

The ACP [Session Config Options](https://agentclientprotocol.com/protocol/session-config-options)
spec is useful background for that distinction, but it is separate from the
session list/load capability at issue here.

## Desired UX

For an ACP agent that declares session listing and loading support, Zed should
provide a **Resume agent session…** action from the agent panel or new-thread
flow:

1. Choose the agent server (for this use case, `omp`).
2. Ask it for saved sessions and show a searchable picker.
3. Default to sessions whose `cwd` equals the current worktree; allow an
   explicit "all locations" view rather than silently loading another project.
4. Show title, cwd, last-updated time, message count, and enough of the session
   id to disambiguate untitled entries.
5. On selection, call ACP's session load/resume operation and create a normal
   Zed agent thread linked to the returned/existing ACP session id.
6. The resulting thread participates in normal Zed history, restoration,
   notifications, model/thinking selectors, and Review Changes.

A terminal session should not be open concurrently in the omp TUI and in the
resumed Zed thread. The first implementation can warn in documentation rather
than trying to detect concurrent clients.

## Why Zed, rather than an omp workaround

Today omp ACP exposes no `/resume` slash command in Zed; session resume is an
ACP client operation. omp could add a `/resume <id>` command or a static
`omp acp --resume <id>` launch argument, but neither supplies a usable picker
in Zed, and the latter cannot receive a per-session id from Zed's static
`agent_servers.omp.args` setting. Creating a fresh ACP session and importing an
old transcript also creates two identities and is not true session resumption.

Zed already knows the active workspace, owns the agent-thread UI, and receives
session metadata through ACP. A generic implementation would benefit all ACP
agents that support session list/load, rather than coupling Zed to omp's local
storage layout.

## Fork implementation sketch

Read Zed `main` at `482e765` (2026-11-16) before patching; re-locate symbols
on the fork's base commit.

1. **Find the existing ACP thread-history/reconnect path.** Trace the agent
   panel's restore flow and the ACP connection methods that invoke session load
   for a Zed-created thread. Reuse that path; do not reconstruct an ACP session
   locally from transcript data.
2. **Add an agent-session listing entry point.** It must be enabled only when
   the connected external agent advertises `list` plus `loadSession`/`resume`.
   Decide whether a temporary ACP connection is sufficient to list sessions or
   whether the picker needs a short-lived placeholder thread.
3. **Build the picker.** Filter current-cwd results by default, preserve all
   metadata, and make the empty/error states explain whether the agent lacks
   support or simply has no matching sessions.
4. **Load and register the selected session.** Create Zed's persistent thread
   record only after the ACP load succeeds. Avoid duplicate records when the
   same external session is selected twice; focus the existing Zed thread.
5. **Restore behavior.** Verify Zed restart restores the newly adopted session
   just as it restores an ACP thread created in Zed.
6. **Tests.** Extend Zed's mock ACP agent with list/load responses for multiple
   cwd values, untitled entries, errors, and a duplicate load. Add an
   integration test that confirms the load request's selected id and that the
   adopted thread is restorable.

Likely source areas to inspect first:

- `crates/agent_servers/src/acp/v1.rs` — ACP client capabilities and session
  operations.
- `crates/acp_thread/` — ACP session/thread state.
- `crates/agent_ui/` — agent-panel history, thread creation, and picker UI.

`agent_ui/src/config_options.rs` is useful precedent for generic external-agent
controls, but it is not the session-resume implementation.

## Acceptance test

1. In `~/src/dotfiles`, start `omp` in a terminal and send a distinctive marker
   such as `zed-acp-resume-test-YYYY-MM-DD`; exit it.
2. In the same Zed workspace, choose **Resume agent session…** → `omp`.
3. See the terminal-created session (including the marker's title/timestamp) in
   the picker and load it.
4. Ask for the marker in the Zed ACP chat; the resumed agent returns it from
   its transcript.
5. Restart Zed, reopen the adopted thread from history, and confirm the same
   context remains available.
6. Confirm an omp session from another cwd is hidden by default and is clearly
   labelled before an explicit cross-project load.

## Upstream vs fork

This is a generic ACP feature and should be upstreamable in principle. Build it
in the fork first only if it is wanted soon: it touches persistent thread
lifecycle and needs enough test coverage to stay rebaseable. If the UX proves
sound, extract it as a small upstream PR with the mock-agent tests.

Until then, the supported path for an existing terminal-owned session is
`omp -r <id-prefix>` in a Zed Terminal Thread; it remains terminal UI, not a
Zed agent chat. Do not open that same omp session concurrently in a terminal
and an adopted ACP thread once this feature exists.
