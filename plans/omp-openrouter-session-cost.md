# OMP OpenRouter session cost

> **Status:** implemented and live-smoked 2026-09-17 against OMP 18.2.4 as a
> stowed extension; the Homebrew binary remains unmodified.

## Problem

OMP's native `cost` segment sums `message.usage.cost.total`. For the active
OpenRouter route that field is zero, so the segment disappears even though
OpenRouter records a nonzero cost for every generation. The model selector is
not the problem: `openrouter/openai/gpt-5.6-terra:high` produces a normal
OpenRouter response id that can be resolved through OpenRouter's generation
metadata endpoint.

`openai-codex/...` subscription sessions are a separate path. Their existing
`S0.66`-style list-price-equivalent display must remain unchanged.

## Evidence

- All 40 OpenRouter response ids sampled from the current saved session
  resolved successfully through `GET /api/v1/generation`; no missing or invalid
  records. Their cumulative upstream inference cost was `$2.8732586` while the
  OpenRouter account charge reported by those records was zero.
- A real extension handler can resolve the active OpenRouter credential through
  `ctx.modelRegistry.getApiKey(...)` and authenticate the generation lookup. No
  environment-variable-only shortcut is required.
- Generation metadata is eventually consistent. A lookup issued directly in
  `message_end` returned 404 at 0.257, 0.468, 0.821, 1.420, and 2.505 seconds,
  then returned the complete record at 4.649 seconds. Retrieval must therefore
  run in the background with bounded 404 retries; it must not block the turn.
- A catalog-price fallback is not trustworthy enough to present as session
  spend. Repricing the same 40 saved messages from OMP's current Sol catalog
  produced `$1.4366293`, exactly 50% below OpenRouter's `$2.8732586` upstream
  total. Use generation metadata as the source of truth rather than silently
  substituting a local estimate.
- OMP exposes every required extension surface: `message_end`, session lifecycle
  events, `ReadonlySessionManager.getEntries()`, model/key resolution,
  `pi.appendEntry(...)` for hidden persisted state, and the live mutable
  `SEGMENTS` record already used by this repo's `turn-count.ts` and
  `cwd-name.ts`.

## Decision

Add `omp/.omp/agent/extensions/openrouter-session-cost.ts`. On the first
UI-backed `session_start`, it wraps the existing live `SEGMENTS.cost` entry.
The configured status-line id remains `cost`, so `omp/setup-settings.sh` does
not need a new segment or migration.

The wrapper has two paths:

- Active model provider is not `openrouter`, or a focused subagent is being
  viewed: delegate to OMP's original cost renderer without changing its
  subscription, premium-request, advisor, or time-based-pricing behavior.
- Active model provider is `openrouter`: render the exact cumulative OpenRouter
  generation cost maintained by the extension.

This keeps the change narrow and avoids either a duplicate cost segment or a
fork of the fast-moving OMP binary.

## Cost semantics

For each unique OpenRouter assistant `responseId` in
`sessionManager.getEntries()`:

1. Fetch its generation metadata.
2. If `is_byok` is true and `upstream_inference_cost` is a finite nonnegative
   number, count that upstream inference cost.
3. Otherwise count `total_cost`, the amount OpenRouter charged for the
   generation, when it is finite and nonnegative.
4. Treat a record lacking the applicable field as unresolved, never as zero.

Sum every unique response in the session, including responses on abandoned
branches. Those requests were billed, and this matches OMP's native
`getUsageStatistics()` session-wide accounting rather than its active context
branch.

Display states:

- Idle with complete metadata: show the current total, including `$0.00` before
  the first request and `$2.87` after accumulated requests.
- From `agent_start` while OMP is responding: show the settled current total
  plus an explicit in-flight term, for example `$2.87 + …`.
- If the agent becomes idle before the just-finished generation metadata is
  indexed, retain `$2.87 + …` until every pending lookup settles, then atomically
  replace it with the new total. Never show the old total as if it were final.
- If a lookup exhausts retries, show `$2.87 + ?` until a later reconciliation
  resolves it.

Use OMP's live theme and `statusLineCost` color. Keep two-decimal formatting to
match the native segment.

## Durable state and reconciliation

Persist one hidden custom entry per resolved generation under a versioned type,
for example `openrouter-session-cost/v1`:

```text
responseId
isByok
totalCost
upstreamInferenceCost
effectiveCost
fetchedAt
```

Never persist the API key or response body. On `session_start`,
`session_switch`, and `session_branch`:

1. Scan all session entries for unique OpenRouter assistant response ids.
2. Scan valid versioned cost entries and index them by response id.
3. Ignore cost entries whose response id has no corresponding assistant
   message, malformed numeric fields, duplicate later entries, and unknown
   schema versions.
4. Sum cached records immediately, then enqueue only missing ids.

Track the response lifecycle with `agent_start` and `agent_end`; active work
forces the `+ …` suffix even before the next response id exists. On an
OpenRouter assistant `message_end`, enqueue its response id without awaiting the
network request. When a lookup completes, append the validated custom entry only
if the owning session is still active and still contains the response id. Keep
the suffix after `agent_end` while that lookup remains pending. A resume or later
reconciliation recovers work lost to an early process exit or session switch.

Keep an in-process immutable cache keyed by response id so switching among
sessions does not refetch already-seen generations. Persisted entries make a
new OMP process render resumed-session cost immediately without replaying one
HTTP request per historical generation.

## Fetch policy

- Resolve credentials through `ModelRegistry` for the owning OMP session.
- Limit reconciliation to four concurrent generation requests.
- Use a per-request timeout.
- Retry 404, 429, and 5xx responses with bounded delays spanning at least eight
  seconds; the measured indexing delay requires attempts beyond 2.5 seconds.
- Honor cancellation/session generation changes and stop retries on shutdown.
- Treat 401, 403, malformed JSON, and invalid numeric fields as terminal for
  that reconciliation pass. Log a concise warning without credentials or
  response payloads; replace the pending ellipsis with `+ ?` and retry on the
  next session reconciliation.
- Trigger a repaint by toggling an empty hook status; clearing an absent status
  does not invalidate OMP 18.2's segment cache. Network completion never runs
  inside the segment renderer.

If the `SEGMENTS` export disappears or becomes immutable, leave the native
segment untouched and render the same value through the hook-status row. Every
renderer body must catch its own errors because native segment rendering does
not contain extension exceptions.

## Files

- Add `omp/.omp/agent/extensions/openrouter-session-cost.ts`.
- Update `AGENTS.md`'s OMP package inventory to include the new stowed
  extension.
- Update `README.md`'s OMP setup, managed-files list, extension count,
  diagnostics, and status-line description.
- Update `docs/omp.md`'s status-line section with the source field, cumulative
  semantics, active/pending display states, eventual-consistency delay, and
  native fallback behavior.
- Update `omp/setup-settings.sh` to write the extension-owned segment arrays
  under OMP's config lock; OMP 18.2 rejects custom ids through `config set`.

## Verification

1. Run the repository's normal OMP deployment path: `stow --no-folding omp`,
   then `bash omp/setup-settings.sh`; confirm the existing status-line segment
   configuration still ends in `cost`.
2. Start a real interactive session with
   `openrouter/openai/gpt-5.6-terra:high`. Verify `$0.00` while idle, then send a
   small prompt and observe `$0.00 + …` while OMP responds. After generation
   metadata is indexed, the display must settle atomically on the new numeric
   total without delaying response or tool execution.
3. Query every response id in that test session directly through OpenRouter and
   compare the independently summed effective total with the displayed value at
   the same two-decimal precision.
4. Produce multiple tool round trips and verify each response id contributes
   exactly once.
5. Exit and resume the session. The persisted total must render immediately;
   a new response must increase it after metadata indexing completes.
6. Branch and navigate the session tree. The total must remain session-wide and
   must not double-count duplicate custom entries.
7. Switch to `oa-l` and confirm the original subscription renderer still shows
   `S…`; switch back to OpenRouter and confirm the OpenRouter total returns.
8. Exercise missing-key, temporary 404, and terminal HTTP failure paths with a
   throwaway fetch probe. OMP must remain usable; active or pending work must
   show `+ …`, and exhausted lookups must show `+ ?` rather than a fabricated
   zero or estimate.
9. Remove the throwaway probe and review the final docs against the observed
   TUI behavior.

No permanent live-network test: it would spend model/API usage and be
nondeterministic. The durable contract is proven by the actual TUI smoke test
plus direct independent reconciliation against OpenRouter's generation API.

## Current limitations

The displayed total is exact for one deliberately narrow scope: OpenRouter
assistant responses whose response ids are present in the primary session's
persisted entries. It is a primary-session total, not a process-wide,
turn-wide, or OpenRouter-account-wide total. Model calls made outside that
entry stream are absent even when the primary turn triggered them.

How easy each gap is to close depends on whether the solution must remain a
dotfiles extension against the unmodified Homebrew OMP binary or may add a
small upstream OMP event.

### Advisors

Advisors are the easiest extension-only addition. OMP already persists each
advisor's complete assistant messages, including OpenRouter response ids,
beside the primary transcript:

```text
<session>/__advisor.jsonl
<session>/__advisor.<slug>.jsonl
```

The primary session owns those top-level files unambiguously. A background
auxiliary-transcript reconciler can discover them, extract unique OpenRouter
response ids, pass those ids through the existing generation-metadata queue,
and persist records in the primary session with `source: "advisor"` and the
advisor slug. Resume can rebuild immediately from the primary session's cost
records, while live reconciliation reads only transcript bytes added since the
last snapshot and never performs file I/O in the status renderer.

OMP's existing `getAdvisorCost()` is not an exact shortcut. It sums
`message.usage.cost.total`, the same field that is zero for the active BYOK
route. Folding that native aggregate into the displayed value would silently
mix an estimate or platform charge with authoritative generation metadata and
must not be done.

### Title generation

Title generation is the smallest host-side change, but it is not cleanly
solvable by the current extension API. `generateTitleOnline()` already receives
the complete normalized assistant response and the caller already knows the
owning primary session id. OMP could emit or persist:

```text
source: title
ownerSessionId
responseId
provider
```

The extension could then resolve that response id exactly like a primary
response. Today the title call runs through `completeSimple()` outside the
primary extension event stream, and only the generated title becomes session
metadata, so the response id is otherwise unreachable. A small upstream OMP
change is preferable to monkey-patching the provider call or carrying a fork.

### Subagents

Subagents are feasible without a core change but have more lifecycle cases than
advisors. OMP persists each child transcript under the primary session's
artifact directory:

```text
<session>/<agentId>.jsonl
```

The child session header records its parent, and the transcript retains each
assistant response id. The advisor transcript reader should therefore be
designed as a general auxiliary-transcript reconciler rather than followed by a
second subagent-specific mechanism.

Exact subagent attribution must additionally handle:

- background agents completing after the primary turn has settled;
- parked agents resuming and appending new generations;
- nested agent ids and their owning parent/turn;
- child-session credential routing for OpenRouter metadata lookup;
- the same response being visible from parent and focused-agent views without
  double-counting; and
- subagent advisors stored under
  `<session>/<agentId>/__advisor*.jsonl`.

Focusing a subagent continues to delegate the segment to OMP's native renderer.
The primary view should aggregate child records only after they have an
explicit `ownerSessionId`, `agentId`, and source category.

### Other non-primary work

This is the hardest category because it is open-ended rather than one known
call site. Any current or future internal `completeSimple()` or side-agent call
can bypass the primary transcript. Adding a scraper for each feature would
continually drift.

The durable OMP-side contract should be one completed-generation event emitted
by every billable model-call surface after it has a normalized assistant
response:

```ts
type BillableGeneration = {
  responseId: string;
  provider: string;
  ownerSessionId: string;
  source: "primary" | "subagent" | "advisor" | "title" | "internal";
  agentId?: string;
};
```

The host owns attribution; the extension owns OpenRouter lookup, bounded retry,
deduplication, persistence, and display. This same event would make title
generation and future internal calls straightforward without exposing their
implementation details.

### Recommended order

1. Add advisor accounting through a general auxiliary-transcript reconciler.
2. Extend the same reconciler to subagent and subagent-advisor transcripts.
3. Propose the generic completed-generation event upstream for title generation
   and future internal calls.
4. Keep native aggregates and catalog-price estimates out of the exact total;
   do not use them as an interim fallback.

Every future path must preserve the guarantees of the primary-session
implementation: authoritative OpenRouter generation metadata, an explicit
owner and category, one durable record per response id, immediate resume
restoration, bounded reconciliation, and no double-counting. Until those paths
exist, the status value should be read as **primary-session OpenRouter spend
only**.

## Non-goals

- Changing OMP's persisted `message.usage.cost` or global `omp stats` database.
- Replacing the `S…` subscription-equivalent display.
- Carrying a forked OMP binary or changing OpenRouter routing/account settings.
