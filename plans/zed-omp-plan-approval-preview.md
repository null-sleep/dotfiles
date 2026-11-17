# Zed: seeing the whole omp plan before approving it

Status: implemented (2026-11-16) as the Zed-only extension
`omp/.omp/agent/extensions/zed-plan-in-chat.ts`, with no fork; see
[Plan: Zed-only extension](#zed-only-patch). The scripted ACP smoke passes.
Zed check (2026-11-16): with a 50-line plan, the plan rendered in the chat
and **Approve and execute** exited plan mode. Refine and dismiss weren't
tried in Zed; the scripted smoke covers them.
The upstream issue/PR paths below stay open.
omp 18.20.2 (brew; upstream main 18.22.0), Zed 1.28.1. Source reads are pinned to the commits linked in
[Sources](#sources).
Intent: explains why omp's plan approval in Zed shows only the start of the
plan, how the Claude and Codex adapters do it, and the fix, either as an
issue to file or as a patch to write.

## Problem

In an omp ACP thread in Zed, the approval card ("Input Requested by omp",
"Approve plan "<slug>" and start implementation?") shows the first 12 lines of
the plan as plain text, then `…`. The plan is never posted to the chat, so you
can't read the whole plan from Zed before choosing **Approve and execute** or
**Refine plan**. Raw markdown (`#`, backticks) shows unrendered in the card.

## Workaround today

Open the plan file. omp keeps it under the session's local root:

```sh
# Newest plan for this repo; the cwd slug for ~/src/dotfiles is -src-dotfiles
zed "$(ls -t ~/.omp/agent/sessions/-src-dotfiles/*/local/*-plan.md | head -1)"
```

General shape: `~/.omp/agent/sessions/<cwd-slug>/<session>/local/<slug>-plan.md`.
`ls -t` picks the newest plan for the repo; when several sessions are planning
at once, use the path of the session you want. The approval card stays open while
you read the file. Editing the file before approving is meant to take effect,
since omp re-reads the plan from disk when you approve. That is stated in omp's
extension docs and not tested in Zed. Use **Refine plan** if it matters.

Through the public extension API alone, an extension can't fix this:

- `plan_review_requested` and `ctx.resolvePlanReview` exist, but they are
  interactive-mode only (`extensibility/extensions/types.ts`).
- Under ACP, `ctx.ui.notify` only writes to the log.
- The only UI an extension can show under ACP is an elicitation form, which
  Zed renders as plain text. omp#14211 ran into the same limit.

Patching host prototypes from an extension does work, though. See
[Plan: Zed-only extension](#zed-only-patch).

## Cause: omp sends only a preview

`#requestAcpPlanApprovalChoice` in
`packages/coding-agent/src/modes/acp/acp-agent.ts` builds the approval as a
form elicitation (`elicitation/create`) and truncates the plan on purpose:

```ts
// Keep the body bounded — Zed renders elicitation messages
// inline and a multi-thousand-line plan blows out the dialog.
const previewLines = planContent.split("\n").slice(0, 12).join("\n");
const ellipsis = planContent.split("\n").length > 12 ? "\n…" : "";
```

The preview came with the fix for omp#1869 (plan approval did not work in Zed
at all). That PR described it as "a short plan preview".

Other ACP clients:

- A client that advertises `elicitation.form` gets the same 12-line form.
- A client without it gets no prompt: the method returns `true` and the plan is
  approved silently. That is omp#11686, labelled `wontfix`.
- omp never sends plan-mode plans as `plan_update`. Its ACP code checks only
  `elicitation.form` and `auth.terminal` in the client capabilities, and the
  event mapper sends only the old checklist-style `plan` update (from `todo`).

## How other ACP adapters do it

### Codex (agentclientprotocol/codex-acp)

Seen in a Zed thread on 2026-11-16 (Codex in Plan mode, a 55-step dummy plan):
the whole plan appears as rendered markdown in the chat, then an "Implement
this plan?" card with **Yes, implement this plan** and **No, and tell Codex
what to do differently**. Nothing is cut off.

From the source:

- `CodexPlanStream`: a client without plan-update support gets the whole plan
  as one `agent_message_chunk` when the plan completes. A client with
  plan-update support gets markdown `plan_update` snapshots instead.
- `PlanReviewReporter.permissionRequest`: approval is a
  `session/request_permission` with a `switch_mode` tool call titled
  "Implement this plan?", the plan text in `rawInput.plan` (Zed's "View Raw
  Input"), and options `implement_plan` (`allow_once`) and `revise_plan`
  (`reject_once`).

### Claude (agentclientprotocol/claude-agent-acp)

From the source; not checked in a live Zed thread:

- `ExitPlanModeReporter`: the plan-approval tool call carries the full plan
  text as its content ("Approve Plan", kind `switch_mode`). Zed renders tool
  call content as markdown.
- Approval is a `session/request_permission` on that tool call, titled "Ready
  to code?", with options like "Yes, clear context and use auto mode".
- `planModeUpdate`: an approved plan is also sent as a markdown `plan_update`
  to clients that support plan updates.

### The protocol pieces

- `session/request_permission` is core ACP, so every client supports it. Using
  it also gives clients without elicitation a prompt, which is what omp#11686
  needs.
- [Plan Operations RFD](https://agentclientprotocol.com/rfds/plan-operations)
  (unstable): `plan_update` with `{ type: "markdown", planId, content, path? }`.
  `path` is an absolute path to the plan file, and clients may use it to open
  the file. Zed implements it in
  [zed#66345](https://github.com/zed-industries/zed/pull/66345) (merged
  2026-11-06): markdown plans render in a scrollable area and file plans open
  on click. It is advertised on ACP v1 only behind Zed's `acp-beta` flag, so a
  fix can't rely on it alone.

## Fix to ask omp for

All on omp's side; Zed needs no change.

1. **Show the full plan before asking.** When the client has no `plan`
   capability, send the whole plan as an `agent_message_chunk` (Codex's
   fallback) with a final line giving the plan file's absolute path. When the
   client advertises `plan`, send `plan_update` markdown with `content` and
   `path` instead. This step alone makes the plan readable in Zed.
2. **Ask with `session/request_permission`.** Use a `switch_mode` tool call
   titled "Approve plan: <title>", with the plan in `rawInput`, and options
   **Approve and execute** (`allow_once`) and **Refine plan** (`reject_once`).
   Keep the current rule: only an explicit approve grants write access;
   dismissal, cancel, or an unknown answer counts as refine. This replaces the
   form elicitation and closes the silent auto-approve in omp#11686.
3. Delete the 12-line preview and its comment.

Rejected:

- **Just raise the 12-line limit.** The card renders plain text, so a long plan
  becomes an unformatted wall, the problem the original comment warned about.
- **Fix it in Zed.** Zed can't show text omp never sends. The nearest Zed issue
  is [zed#51204](https://github.com/zed-industries/zed/issues/51204)
  ("ACP: Cursor External Agent creates unviewable plans in plan mode"), the
  same complaint for Cursor's agent; a comment there is optional.

<a id="patch-omp"></a>
## Option: patch omp ourselves

The goal is to make omp do what Codex does in Zed: post the full plan to the
chat, then ask for approval. Read from omp `main` at `6e8ab5f` (2026-11-16);
re-read before editing, since omp releases often.

### Filing an issue or opening a PR

omp's `CONTRIBUTING.md` says not to open an issue for work you are about to
submit, because its bot (robomp) treats actionable issues as work to pick up
and may start the same fix in parallel. So if you patch, skip the issue: put
the draft's text in the PR description instead. Other rules from that file:

- The PR body needs at least one sentence in your own words saying what
  changed and why.
- Show that it works end to end. `bun check` alone doesn't count: run it in
  Zed and report the scenario and the result.
- Small, narrowly scoped changes can go straight to a PR. Discuss major
  behavioural changes on omp's Discord first.
  - Step 1 below (post the plan to the chat) is small.
  - Step 2 (switch from a form to a permission request) changes how every ACP
    client approves plans, and touches the `wontfix` call in omp#11686. It is
    worth asking on Discord first, or sending as a second PR.

### Where the change goes

All of it is in `packages/coding-agent/src/modes/acp/acp-agent.ts`:

- `#applyModeChange`: entering ACP plan mode installs
  `#handleAcpPlanProposal` as the plan-proposal handler. A write to
  `xd://propose` calls it.
- `#handleAcpPlanProposal(record, title)`:
  - calls `resolveApprovedPlan(...)` to get `planFilePath` (a `local://` URL),
    `planContent` and the title, then `#requestAcpPlanApprovalChoice(...)`;
  - on refine, keeps plan mode on and returns "Plan refinement requested…";
  - on approve, clears plan mode, autosaves the plan, and sends
    `current_mode_update` and the config update to the client.
- `#requestAcpPlanApprovalChoice(sessionId, title, planContent)` builds the
  12-line form. It returns `true` on its own when the client lacks
  `elicitation.form`.
- `#resolveAcpPlanFilePath(session, url)` turns the `local://` URL into an
  absolute path. Use it for the path line in the chat message and for
  `plan_update.path`.
- `this.#connection.sessionUpdate({ sessionId, update })` sends any session
  update; the approval branch already uses it.
- For the permission prompt, `this.#connection.requestPermissionWithCancel(request)`
  is what the bash approvals use. See `requestPermission` and
  `permissionOutcomeFromResponse` in `acp-client-bridge.ts`, which also
  cancel the prompt when the user steers.
- `acp-event-mapper.ts` sends assistant text as `agent_message_chunk` with
  `content` and `messageId`. omp sends no `plan_update` anywhere today.

### Step 1: post the full plan before asking

Smallest change that fixes the problem in Zed.

- In `#handleAcpPlanProposal`, after `resolveApprovedPlan` and before asking,
  send one `agent_message_chunk` holding the full plan markdown, then a line
  with the plan file's absolute path. That is Codex's fallback when the client
  has no plan support.
- Keep the form, but shorten its message to the question and the title. The
  plan is now in the chat right above it.
- When `#clientCapabilities?.plan` is set, also send a markdown `plan_update`
  with a fixed `planId` such as `plan-mode` (the Claude adapter's choice), the
  plan as `content`, and the absolute `path`. Zed sets that capability only
  with `acp-beta` on, so the chat message must not depend on it.

Not yet known; check while building:

- Whether Zed joins the chunk onto the agent's running reply or starts a new
  block. Try both with and without a fresh `messageId`.
- Whether the plan shows up again after reloading the thread. Session replay
  is rebuilt from omp's session history, and a chunk sent only live may not
  be in it.
- Whether the installed ACP SDK's types already have `plan` in the client
  capabilities and `plan_update`. If they don't, ship the chat message alone
  and leave `plan_update` out.

### Step 2: ask with a permission request

- Replace the form with `session/request_permission`:
  - a tool call of kind `switch_mode`, `toolCallId` such as
    `plan-review:<title>`, titled "Approve plan: <title>", with
    `rawInput: { plan, planFilePath }`;
  - options `approve` → "Approve and execute" (`allow_once`) and `refine` →
    "Refine plan" (`reject_once`).
- Approve only on the `approve` option. Cancelled, dismissed, steered, an
  unknown option, or an RPC error all mean refine. That is the rule the test
  "treats dismissed elicitation as refine, never approves" protects.
- Drop the auto-approve for clients without forms, since every ACP client
  supports permission requests. That is what closes omp#11686.
- Afterwards, update the tool call to `completed`, like Codex's
  `PlanReviewReporter.decided`, so the card doesn't stay pending.

### Tests

In `packages/coding-agent/test/acp-agent.test.ts`, next to the existing
"plan-proposal handler …" tests:

- `createHarness({ elicitationHandler, clientCapabilities, permissionHandler })`
  builds a fake connection. `harness.updates` records every session update, so
  it can check that the plan chunk (or `plan_update`) goes out before the
  approval request.
- The fake `requestPermissionWithCancel` always answers `cancelled`, and
  `permissionHandler` only observes the request. Step 2 needs a way to pick
  the answer, so that both approve and refine can be tested.
- Existing tests to keep passing: approve exits plan mode and sends
  `current_mode_update`, autosave success and failure, and dismissal means
  refine. A test that checks the elicitation message text will need updating
  once step 1 shortens it.

### Build and run it in Zed

- No local omp checkout exists now. `~/src/oh-my-pi`, mentioned in
  [omp-fork-customization.md](omp-fork-customization.md), is gone. Clone
  `can1357/oh-my-pi` (or a GitHub fork for the PR).
- From `packages/coding-agent/DEVELOPMENT.md`:
  - `bun run check` typechecks and lints (the gate);
  - `bun run test` runs the tests;
  - `bun run build` builds the `dist/omp` binary.
- Zed starts omp from `agent_servers.omp` in `zed/.config/zed/settings.json`
  as `/opt/homebrew/bin/omp acp --approval-mode yolo --config
  ~/.omp/agent/zed-models.yml`. To try the patch, add a second entry (for
  example `omp-dev`) with the same args and `command` set to the built
  binary, so the brew one stays the daily driver. Remove it once the PR
  lands or is abandoned.
- `~/.local/bin/omp` is an older self-built binary (reports 18.18.6, dated
  2026-11-10). `/opt/homebrew/bin` comes first on `PATH`, so it isn't used.
  Don't overwrite it without knowing what it is for.
- End-to-end check in Zed: in a new `omp-dev` thread, switch to Plan and ask
  for a dummy plan of 50+ lines (the same test that was run on Codex). Check
  that:
  - the whole plan renders as markdown above the approval card;
  - **Approve and execute** exits plan mode and starts implementing;
  - **Refine plan** keeps plan mode on;
  - dismissing the card never approves.

### If it isn't merged

Carrying the patch means building and rebasing omp on each release. Costs and
options are in [omp-fork-customization.md](omp-fork-customization.md) → Options
ladder. If the PR stalls, file the draft issue below instead, linking the PR.

<a id="zed-only-patch"></a>
## Plan: Zed-only extension

Goal: in a Zed thread, omp posts the whole plan to the chat as rendered
markdown, then asks Approve/Refine. Every other omp surface behaves exactly
as stock omp. Source read from omp `main` (18.22.0, 2026-11-16) and probed
against the installed brew binary (18.20.2).

### No fork needed: an extension can reach the ACP connection

This uses the same trick as `turn-count.ts`. In the compiled binary,
extension imports of `@oh-my-pi/*` resolve to the host's live module
instances (`legacy-pi-compat.ts`, `scripts/legacy-pi-virtual-module.ts`).
The bundled registry includes:

- `@oh-my-pi/pi-utils/acp`, because pi-utils' flat `./*` export covers the
  top-level `acp.ts`. That module exports `AgentSideConnection`, whose
  `sessionUpdate` and `unstable_createElicitation` are prototype methods.
- `@oh-my-pi/pi-coding-agent/session/agent-session` (`AgentSession`, with
  its public `setPlanProposalHandler`).
- `@oh-my-pi/pi-coding-agent/plan-mode/approved-plan`
  (`resolveApprovedPlan`) and `plan-mode/plan-files` (`resolvePlanFilePath`,
  plus `readPlanFile` and `listPlanFiles` from the same module).

Probe on 2026-11-16: `omp acp -e probe.ts`, driven over stdio with
`initialize` and `session/new`. All four symbols resolved as functions. A
wrapper the probe installed on `AgentSideConnection.prototype.sessionUpdate`
fired for the live connection's `available_commands_update` and
`session_info_update`. So an extension can send any session update to Zed
and intercept the plan-approval elicitation.

One limit: ACP binds extensions per `session/new`, after `initialize` (see
`main.ts`, "ACP binds extensions per `session/new`"). The extension
therefore can't see `clientInfo`, and it gates on an env var instead (next
section).

### Why it stays Zed-only

- **Env gate.** The extension returns immediately unless
  `OMP_ZED_PLAN_IN_CHAT=1`. Only Zed sets it, through
  `agent_servers.omp.env` in `zed/.config/zed/settings.json` (Zed's
  external-agents docs list `env` for custom agents; not yet seen passed
  through). The TUI and other launches never set it. After reading the
  variable, the extension runs `delete process.env.OMP_ZED_PLAN_IN_CHAT`, so
  an `omp` started as a child of the Zed process (for example from the bash
  tool) runs stock.
- **What each wrapper touches.** The connection wrapper only runs under
  `omp acp`; nothing else creates an `AgentSideConnection`.
  - The `AgentSession` setter wrapper is process-wide, so it also sees setter
    calls that don't come from ACP: prewalk (`prewalk.ts`), `sdk.ts`, and
    in-process subagents. (Interactive mode never loads in an `omp acp`
    process.)
  - In those cases it only does read-only plan reads and leaves a stash
    entry that nothing reads.
- **Falls back to stock.** The extension never answers the elicitation and
  never changes its schema or options. Any miss or throw falls back to
  calling the original method with the original params. The worst case is
  today's 12-line card, never a broken or auto-approved plan. omp approves
  only on `value === "Approve and execute"`, and a failed request counts as
  refine.

### Shape chosen: chat message, then the existing form

This is what Codex does in Zed, and it was seen working there on 2026-11-16.
The plan goes out as an `agent_message_chunk`, which Zed renders as markdown
in the transcript. The form that follows shrinks to the question alone.
omp's own approve/refine logic stays untouched: approve only on an explicit
**Approve and execute**, and dismissal means refine.

Not chosen: replacing the form with `session/request_permission`, using a
`switch_mode` tool call that carries the plan as `content`. That is the ACP
spec's session-modes example and what claude-agent-acp does (see
[Prior art](#zed-only-prior-art)). From an extension it would mean
answering the elicitation ourselves, which is exactly the decision logic we
want to leave to omp. It belongs in an upstream PR.

### The extension: `omp/.omp/agent/extensions/zed-plan-in-chat.ts`

1. **Gate and guard.** Return unless `OMP_ZED_PLAN_IN_CHAT === "1"`, then
   delete the variable. Keep a `Symbol.for("zed-plan-in-chat")` flag on each
   patched prototype so that per-session reloads patch only once. If any
   import or method is missing, return, which leaves stock behaviour.
2. **Capture the full plan.** Wrap
   `AgentSession.prototype.setPlanProposalHandler`:

   ```ts
   proto.setPlanProposalHandler = function (handler) {
     return orig.call(this, handler
       ? async title => { await stash(this, title).catch(() => {}); return handler(title); }
       : handler);
   };
   ```

   - It must be a `function`, not an arrow, so that `this` is the
     `AgentSession`.
   - `null` must pass through unchanged, because approval clears the handler
     with it.
   - `stash` is `async`, so a synchronous throw becomes a rejection that the
     `.catch` swallows.
   - ACP's `#applyModeChange` calls the setter on the instance (including
     re-entry through `setSessionMode` and the config-option path), and the
     original setter wraps the result in `waitForUser`. `xd://propose`
     awaits the handler, so the stash is always filled before omp's own
     `resolveApprovedPlan` and the elicitation run.
   - `stash` calls `resolveApprovedPlan` with the same inputs as
     `#handleAcpPlanProposal`:
     - `suppliedTitle`;
     - `statePlanFilePath` from `getPlanModeState()`;
     - `readPlan`/`listPlanFiles`, implemented with `readPlanFile` and
       `listPlanFiles` from `plan-mode/plan-files`.

     The options are `localProtocolOptions: { getArtifactsDir: () => this.sessionManager.getArtifactsDir(), getSessionId: () => this.sessionManager.getSessionId() }`
     and `cwd: this.sessionManager.getCwd()`, the same ones
     `#resolveAcpPlanFilePath` uses.
   - Calling it a second time is safe. It only reads, and it renames
     nothing. A missing plan throws the same `ToolError` from both calls: the
     stash swallows its copy, and omp's handler reports the real one. The
     duplicate call is also unavoidable, because `acp-agent.ts` imports it
     as an ESM binding, which can't be patched.
   - The stash then rebuilds the exact message omp will send:
     `` `Approve plan "${title}" and start implementation?\n\n${first12}${ellipsis}` ``,
     built with the same 12-line `split("\n")`/`join("\n")`, and `\n…` only
     past 12 lines. It stores `{ planContent, absPath, title }` keyed by that
     string, with `absPath` from `resolvePlanFilePath`.
   - Re-stashing the same key overwrites the entry. Entries are small and
     leftovers are rare (prewalk, or a proposal that never reaches the
     elicitation), so the map needs no cap.
   - Not keyed by session id: the elicitation carries
     `record.protocolSessionId`, which can differ from the session's own id
     once a session is loaded or switched.
3. **Post it, then ask.** Wrap
   `AgentSideConnection.prototype.unstable_createElicitation`:
   - Look up `params.message` in the stash.
     - An exact hit is the plan prompt for exactly that plan.
     - Anything else passes straight through.
     - Titles are `[A-Za-z0-9_-]` after `normalizePlanTitle`, and both sides
       split lines the same way, so CRLF and trailing newlines can't cause a
       mismatch.
     - Two sessions collide only if they share a title and the first 12
       lines.
   - `await this.sessionUpdate(...)` with an `agent_message_chunk`: a fresh
     `crypto.randomUUID()` `messageId`, and text `planContent.trimEnd()`,
     then `---`, then ``Plan file: `<absPath>` ``. omp's own turn tracking
     (`liveMessageId`, `textEmitted`) only covers assistant message events,
     so an extra chunk neither suppresses nor duplicates omp's text.
   - If that succeeds, call the original with the message replaced by
     `Approve plan "<title>" and start implementation? The full plan is in
     the chat above.` If anything fails, call the original with the
     untouched params. Delete the stash entry either way.
   - **Added while building:** a per-session `lastPosted` map stops repeat
     posts within one turn. After **Refine**, omp's plan mode keeps nudging
     the model to call a tool, so it often re-proposes the plan unchanged in
     the same turn (seen in the smoke run). An identical plan isn't posted
     again; the card says "The plan is unchanged from the copy above."
     instead.
4. **Reset the dedupe each turn.** Wrap `AcpAgent.prototype.prompt` (from
   `@oh-my-pi/pi-coding-agent/modes/acp/acp-agent`) to clear `lastPosted`
   for the session. This came out of the Sonnet review. A thread reload goes
   through `session/load`, which reuses the live session record
   (`#loadManagedSession`) and replays history without the live-only chunk.
   So keying by session object wouldn't help, and clearing on any outcome
   other than Refine would repost after every dismissal, since dismissal
   also counts as refine. A reload is always followed by a new prompt, and
   the refine loop stays inside one turn.

About 200 lines including types and comments. Apart from being loaded, it
uses no extension API; everything goes through the host symbols above. The
host imports are dynamic and come after the env gate, so a launch without
the flag never touches them. If one of them disappears in a later omp, the
extension logs one line to stderr (Zed's agent log) and does nothing,
instead of raising a load error.

Optional follow-up, only if refine turns out to be awkward in practice: a
free-text "What to change" field. omp's refine result carries no user
feedback, so the model has to ask. That would mean changing the
elicitation's schema and the tool result, which is past what an extension
should rewrite, so it goes upstream.

### Verify

1. **Scripted ACP smoke:** `omp/tests/zed-plan-in-chat-smoke.ts`. Run
   `bun omp/tests/zed-plan-in-chat-smoke.ts with`, then `… without`.
   - It spawns `/opt/homebrew/bin/omp acp --approval-mode yolo --config ~/.omp/agent/zed-models.yml`
     with no `-e`, so it also proves the stowed extension loads with Zed's
     flags.
   - It sends `initialize` with `elicitation: { form: {} }`, then
     `session/new`, picks the Haiku model, and calls `session/set_mode`
     with `plan`.
   - It prompts for a 40-line dummy plan and answers the first
     `elicitation/create` with **Refine plan**. The prompt asks the model to
     re-propose the same plan after a refine, so the dedupe branch runs.
     Later cards are dismissed, and after the third the script sends
     `session/cancel`.
   - `with` then sends a second prompt asking for the same plan again. That
     card must come with a fresh copy (the per-turn reset).
   - The dedupe check reports SKIP rather than PASS if the model never
     re-proposed. There's an overall 5-minute timeout, stderr is ignored,
     and non-JSON stdout lines are logged and skipped.

   **Result on 18.20.2 (2026-11-16): both variants pass.**
   - `with`: the full plan arrived (line 40 and the absolute path included)
     as its own `agent_message_chunk`, with a fresh `messageId`, right after
     the `xd://propose` tool call and before `elicitation/create`.
     - The card read `Approve plan "dummy" and start implementation? The
       full plan is in the chat above.`
     - The re-proposals in the same turn got no second copy, and their cards
       said the plan was unchanged. The second prompt's card came with a
       fresh copy.
     - The model's own `ask` elicitation passed through untouched.
     - No `current_mode_update` to `default` was sent.
   - `without`: no plan chunk, and the stock card with 12 lines and `…`.
2. **Zed end to end (run 2026-11-16, partial).** After reloading the omp
   agent, a 50-line plan proposed in a Zed thread rendered in the chat above
   the card. That also shows Zed passes `env` through. **Approve and
   execute** exited plan mode. Not tried in Zed: Refine, the "unchanged"
   re-proposal card, and dismissal (the scripted smoke covers Refine and
   the re-proposal). The checklist, for a rerun:
   - the whole plan renders as markdown above the card (which also proves
     Zed passes `env` through);
   - the card shows only the question;
   - **Approve and execute** exits plan mode;
   - **Refine plan** stays in plan mode;
   - dismissing the card never approves.
3. **TUI unchanged.** A plan in a terminal `omp` session still opens the
   native review overlay. By construction, the factory returns before
   importing anything when the env var is unset.

Seen during the smoke run, and not caused by the extension: in the stock
`without` run, before the script capped proposals, Haiku re-proposed after
every refine/cancel, reaching 214 elicitations in four minutes. omp's
refine result gives the model nothing to act on, and plan mode keeps
insisting on a tool call. In Zed that means repeated cards after **Refine
plan** until you type what to change. It's one more argument for the
refine-feedback idea above, which belongs upstream.

Known limits and open questions:

- After reloading the thread, the plan chunk is gone. Replay rebuilds only
  from `sessionManager.buildSessionContext().messages`, and a live-only
  notification is never stored. Accept that; the plan file and its path
  remain. `pi.sendMessage` is no fix: custom messages replay as a *user*
  chunk and also enter the model's context.
- The chat holds a snapshot taken when the plan was proposed. Edits to the
  file before **Approve** still take effect, because omp re-reads it, but
  the chat copy doesn't change.
- Placement, seen in Zed on 2026-11-16 (screenshots): the plan is its own
  block, directly below the "Run Command: Proposing …" tool card. Headings,
  lists, bold/italic/inline code, the table (file paths as links) and the
  syntax-highlighted code block all render. Long code lines scroll
  sideways. The `Plan file:` line follows a horizontal rule.

### Repo changes (done)

- `omp/.omp/agent/extensions/zed-plan-in-chat.ts`, stowed with
  `stow --no-folding omp`.
- `"env": { "OMP_ZED_PLAN_IN_CHAT": "1" }` on `agent_servers.omp` in
  `zed/.config/zed/settings.json`, with a comment pointing here.
- `omp/tests/zed-plan-in-chat-smoke.ts`; the `omp` package's
  `.stow-local-ignore` already excludes `tests/`.
- Stowed-extension lists updated in `AGENTS.md`, README (omp's "What's
  managed" table and the stow comment), README's Zed section, and
  `docs/omp.md` → Zed ACP.

### Upkeep

- The extension rests on unblessed internals:
  - the bundled `pi-utils/acp`, `session/agent-session`,
    `modes/acp/acp-agent`, `plan-mode/approved-plan`, and
    `plan-mode/plan-files` exports;
  - prototype (not instance) methods on `AgentSideConnection` and
    `AcpAgent`;
  - the elicitation message format and the 12-line preview rule;
  - `resolveApprovedPlan`'s signature and title normalization.
- This is the same risk class as `turn-count.ts`'s `SEGMENTS` mutation.
  Each break degrades to the stock 12-line card.
- After `brew upgrade omp`, run
  `bun omp/tests/zed-plan-in-chat-smoke.ts with` and `… without`. If `with`
  fails, fix the message builder or imports. Between 18.20.2 and 18.22.0 the
  plan path didn't change.
- If omp restructures the area, re-read and rework the extension. One
  candidate is PR omp#12982 (open), which adds a `plan_review` extension
  event that also fires in ACP.
- A patched fork ("Option: patch omp ourselves" above) is the fallback only
  if the host modules stop being reachable from extensions.

<a id="zed-only-upstream"></a>
### Upstream

The extension proves the UX. A PR would build it into
`#handleAcpPlanProposal` for every form-capable client, ideally with the
`session/request_permission` shape (the earlier "Option: patch omp
ourselves" → Step 2), because that is spec-canonical and fixes omp#11686.
Follow omp's `CONTRIBUTING.md` (no issue for work being submitted; an
end-to-end Zed demo in the PR body). Once it ships in a brew release, delete
the extension and the env entry.

<a id="zed-only-prior-art"></a>
### Prior art (searched 2026-11-16)

- No omp or pi-mono fork renders the plan before approval. Related omp work
  is limited to #1869/#1870 (which added the preview), #11686, #12593, and
  #12982.
- claude-agent-acp
  [PR #451](https://github.com/agentclientprotocol/claude-agent-acp/pull/451)
  fixed the same bug on their side. `ExitPlanMode` had dropped the plan from
  the tool-call `content`, so users saw "Ready to code?" with no plan; the
  fix restored `content: [{ type: "content", content: { type: "text", text: plan } }]`.
- The ACP spec's
  [session-modes](https://agentclientprotocol.com/protocol/v1/session-modes.md)
  "Exiting plan modes" example is a `request_permission` with a
  `switch_mode` tool call that carries the plan as `content`.
- Other agents (Gemini CLI, Kimi CLI, Mistral Vibe, opencode) either lack
  ACP plan approval or have the same blind-approval bug. Nobody has a better
  pattern than Codex's or Claude's.
- Zed: elicitation messages render as a plain `Label` (`elicitation.rs`),
  which explains the raw markdown in today's card.
  [zed#62788](https://github.com/zed-industries/zed/issues/62788) (permission
  cards not rendering) was reported against 1.15.0. Re-check it on 1.28.1
  before choosing the permission-request shape.

## Related issues

- omp#1869 (closed): plan approval missing in Zed; the fix added the preview.
- omp#11686 (open, `wontfix`): clients without elicitation can't approve
  anything; plan approval is silently granted.
- omp#14211 (open): edit approvals in Zed show no diff; same blind-approval
  problem for edits, and it notes that extensions can show only forms under
  ACP.
- omp#15239 (open): refine a plan while still seeing it.
- omp#12593 (open PR): `/plan` command over ACP; doesn't touch approval.
- zed#51204 (open): unviewable Cursor plans in plan mode.
- zed#65482 (open): text in ACP input-request cards can't be selected or
  copied.

Searched 2026-11-16 (GitHub issue search on both repos); no issue asks for the
full plan in omp's ACP approval.

## Draft issue (not filed)

Use this only if not patching. If you send a PR, don't file it; omp's
contributing rules say not to open an issue for work you are submitting. Use
the text in the PR description instead. To file: `gh issue create -R
can1357/oh-my-pi --title "<title>" --body-file <file>`, after reading it over
and attaching a screenshot of the cut-off card.

**Title:** ACP: plan approval shows only a 12-line preview; send the full plan
and approve via session/request_permission

**Body:**

````markdown
## Summary

In an ACP client (Zed), omp's plan approval shows only the first 12 lines of
the plan, as plain text, followed by `…`. The plan is never sent to the chat,
so the user can't read the plan they are approving without opening the
session's `local://<slug>-plan.md` file outside the client.

## Current behaviour (main)

`#requestAcpPlanApprovalChoice` in
`packages/coding-agent/src/modes/acp/acp-agent.ts` asks through a form
elicitation and truncates the plan:

```ts
const previewLines = planContent.split("\n").slice(0, 12).join("\n");
const ellipsis = planContent.split("\n").length > 12 ? "\n…" : "";
const message = `Approve plan "${title}" and start implementation?\n\n${previewLines}${ellipsis}`;
```

- Zed renders the elicitation message as plain text, so even the preview
  shows raw markdown.
- Clients without `elicitation.form` get no prompt; the method returns `true`
  and the plan is approved silently (#11686).
- omp never sends plan-mode plans as `plan_update`.

## How other ACP adapters do it

- **codex-acp**: when the plan completes, a client without the `plan`
  capability gets the whole plan as one `agent_message_chunk` (`CodexPlanStream`);
  a client with it gets markdown `plan_update` snapshots. Approval is
  `session/request_permission` with a `switch_mode` tool call "Implement this
  plan?", `rawInput.plan`, and options `implement_plan` (`allow_once`) /
  `revise_plan` (`reject_once`) (`PlanReviewReporter`). In Zed the full plan
  renders as markdown in the chat with the approval buttons below it.
- **claude-agent-acp**: the plan-approval tool call carries the full plan as
  content (`ExitPlanModeReporter`), approval is `session/request_permission`
  ("Ready to code?"), and the approved plan is sent as a markdown
  `plan_update` (`planModeUpdate`).

## Proposal

1. Before asking, send the full plan: an `agent_message_chunk` with the plan
   markdown and the plan file's absolute path; or, when the client advertises
   the `plan` capability, a `plan_update` with
   `{ type: "markdown", planId, content, path }` (Plan Operations RFD; Zed
   supports it in zed-industries/zed#66345 behind `acp-beta`).
2. Ask with `session/request_permission` instead of the form: a `switch_mode`
   tool call "Approve plan: <title>", plan in `rawInput`, options
   "Approve and execute" (`allow_once`) and "Refine plan" (`reject_once`).
   Keep today's rule that only an explicit approve grants write access. This
   also gives clients without elicitation a real prompt (#11686).
3. Remove the 12-line preview.

Step 1 alone fixes readability; step 2 matches codex-acp and claude-agent-acp.

## Related

#1869 (introduced the preview), #11686, #14211, #15239.

## Environment

omp 18.20.2 (brew; upstream main 18.22.0), Zed 1.28.1 (ACP), macOS.
````

<a id="sources"></a>
## Sources

- omp `acp-agent.ts` at `6e8ab5f`:
  [`#requestAcpPlanApprovalChoice`](https://github.com/can1357/oh-my-pi/blob/6e8ab5fb19178082c39326948975cb2587ace7cf/packages/coding-agent/src/modes/acp/acp-agent.ts#L2726-L2747)
- codex-acp at `6567651`:
  [`PlanReviewReporter`](https://github.com/agentclientprotocol/codex-acp/blob/656765115f82253c79f87918abb77189c114a799/src/tool-calls/reporters/PlanReviewReporter.ts),
  [`CodexPlanStream`](https://github.com/agentclientprotocol/codex-acp/blob/656765115f82253c79f87918abb77189c114a799/src/CodexPlanStream.ts#L25-L35)
- claude-agent-acp at `0073280`:
  [`ExitPlanModeReporter`](https://github.com/agentclientprotocol/claude-agent-acp/blob/0073280b977a69934fb56670943d1ef42e7b687e/src/tool-calls/reporters/interaction.ts#L37-L73),
  [`planModeUpdate`](https://github.com/agentclientprotocol/claude-agent-acp/blob/0073280b977a69934fb56670943d1ef42e7b687e/src/exit-plan.ts#L154-L166)
- [Plan Operations RFD](https://agentclientprotocol.com/rfds/plan-operations),
  [zed#66345](https://github.com/zed-industries/zed/pull/66345)
- Issues: [omp#1869](https://github.com/can1357/oh-my-pi/issues/1869),
  [omp#11686](https://github.com/can1357/oh-my-pi/issues/11686),
  [omp#14211](https://github.com/can1357/oh-my-pi/issues/14211),
  [omp#15239](https://github.com/can1357/oh-my-pi/issues/15239),
  [omp#12593](https://github.com/can1357/oh-my-pi/issues/12593),
  [zed#51204](https://github.com/zed-industries/zed/issues/51204),
  [zed#65482](https://github.com/zed-industries/zed/issues/65482)
