# Zed: seeing the whole omp plan before approving it

Status: research done, two paths open (2026-11-16): file the drafted issue,
or patch omp ourselves and send a PR ([Option: patch omp
ourselves](#patch-omp)). Next step: start the patch in a new session.
omp 18.20.0, Zed 1.28.1. Source reads are pinned to the commits linked in
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

An extension can't fix this: under ACP, extensions can show only elicitation
forms, which Zed renders as plain text. omp#14211 ran into the same limit.

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

omp 18.20.0, Zed 1.28.1 (ACP), macOS.
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
