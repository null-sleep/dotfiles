# OMP OpenRouter session cost

> **Status:** implemented and live-smoked 2026-09-18 against OMP 18.2.5 as a
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

## Advisor and subagent attribution plan

### Replaced boundary

Before this implementation, the live extension counted only OpenRouter
assistant responses in the primary session manager's entries. Advisor,
subagent, and subagent-advisor requests were billed but absent from that entry
stream.

The implementation remains extension-only. OMP 18.2.5 exposes the root session
id, session file, and artifact directory through `ReadonlySessionManager`, and
persists every relevant normalized assistant message. It does not forward
advisor or child-agent lifecycle events to the primary extension instance, so
live attribution needs a background transcript reconciler rather than another
`message_end` handler.

OMP's persisted layout is a companion tree rooted beside the primary JSONL.
Here `<root>` is the primary session filename without `.jsonl`:

```text
<root>.jsonl
<root>/__advisor.jsonl
<root>/__advisor.<slug>.jsonl
<root>/<agentId>.jsonl
<root>/<agentId>/__advisor.jsonl
<root>/<agentId>/__advisor.<slug>.jsonl
<root>/<agentId>/<nestedAgentId>.jsonl
```

At each level, OMP recurses from `<dir>/<agentId>.jsonl` only into the
same-stem `<dir>/<agentId>/` directory. Nested ids are already fully qualified
(for example `Parent.Child`). This is the same ownership walk used by OMP's
persisted Agent Hub roster; the reconciler must mirror it rather than recursively
accepting every JSONL below the artifact root.

Each valid child transcript begins with an optional fixed title slot followed
by a session header. The header's `id` is the child's credential-routing
session id.
`parentSession` is a useful consistency check, but physical containment in the
companion tree is authoritative: older transcripts can omit it, and a moved
root can leave its historical path stale. Symlinked files/directories and paths
whose resolved location escapes `<root>/` are ignored.
The reconciler must re-read `getSessionFile()` and `getArtifactsDir()` before
each pass: `/move` keeps the same session manager and id while relocating both
paths.

OMP's `getAdvisorCost()` is not usable here. It sums
`message.usage.cost.total`, the same zero field that required this extension in
the first place.

### Decision

Extend `openrouter-session-cost.ts` with one general auxiliary-transcript
reconciler. Keep the direct primary `message_end` path, the existing
four-request OpenRouter lookup queue, the wrapped native `cost` segment, and
the fallback hook-status row. The reconciler only discovers attributable
response ids and supplies their owning credential session; it never prices a
request itself.

No filesystem work runs in the renderer. One serialized, self-scheduling scan
per active primary session owns discovery, byte cursors, and rescheduling.
Session switch or shutdown aborts both that scanner and the existing network
work.
Retain the current `ctx.hasUI` activation guard. Extension instances loaded in
headless child sessions stay inert; only the primary UI instance scans and
persists the root aggregate.

### Attribution and persisted schema

Write new resolutions under `openrouter-session-cost/v2`:

```ts
type CostAttribution = {
  ownerSessionId: string;
  source: "primary" | "advisor" | "subagent";
  agentId: string | null;
  advisorSlug: string | null;
};

type StoredCostRecordV2 = CostRecord & CostAttribution;
```

The field invariants are:

- Primary response: `source: "primary"`, `agentId: null`,
  `advisorSlug: null`.
- Primary advisor response: `source: "advisor"`, `agentId: null`; the default
  advisor uses an empty slug and named advisors use their filename slug.
- Subagent response: `source: "subagent"`, the transcript's full `agentId`,
  `advisorSlug: null`.
- Subagent-advisor response: `source: "advisor"`, the owning full `agentId`,
  and the advisor slug.

`ownerSessionId` is always the primary session id, never the child transcript's
session id. The latter is retained only in the in-memory discovery record for
credential routing.

The response id remains the accounting identity. A response seen in more than
one place contributes once. A restored valid v2 record is canonical for its
response id; otherwise primary entries win over auxiliary entries, then sorted
relative transcript path and line order make conflicts deterministic. Log one
sanitized warning for conflicting attribution, but never add both costs.

The v1 reader remains only as persisted-data compatibility for existing
primary responses. It accepts a record only when the response id is still in
the primary session entries. All new primary and auxiliary resolutions write
v2; no v1 entry is rewritten or duplicated merely to migrate it.

A valid v2 record whose `ownerSessionId` matches the active session restores
immediately from the primary JSONL, including advisor and subagent spend. This
is safe because v2 is appended only after the response has been observed in an
owned transcript. The asynchronous scan recovers work lost before persistence;
it does not subtract a billed, durably attributed response merely because an
artifact was later removed.

### Bootstrap and reconciliation

On `session_start`, `session_switch`, and `session_branch`:

1. Abort the previous state and capture the new root session id/file.
2. Scan primary session entries synchronously. Collect primary OpenRouter
   response ids, restore valid v1/v2 records, and render the cached total
   immediately.
3. Mark the initial auxiliary reconciliation in flight and schedule it without
   awaiting from the lifecycle handler.
4. Walk the companion tree in stable path order. Validate title/session
   headers, derive attribution and the owning credential session, and enqueue
   only OpenRouter assistant response ids not already resolved or pending.
5. Clear the initial-scan marker only after the captured tree snapshot has
   parsed. Metadata lookups can remain pending independently.

`session_tree` re-runs the primary-entry reconciliation and requests an
immediate auxiliary scan. Primary `message_end` still enqueues directly and
`agent_end` requests a scan so advisor output already flushed at the turn edge
is picked up quickly.

Each auxiliary file has a cursor containing file identity, last complete-line
byte offset, validated header, and owner metadata. A scan snapshots the file
size, streams only `[offset, snapshotSize)`, and advances the cursor only
through newline-terminated JSON records. A trailing partial record is retained
for the next pass. Inode replacement or size regression resets that file to
offset zero; response-id deduplication makes the rescan harmless.

The initial process scan necessarily reads historical auxiliary transcripts.
Subsequent scans read only appended bytes. Directory enumeration remains
bounded to the OMP companion-tree rule. One scan may be in flight; another
trigger only requests one follow-up pass.

Use a one-second cadence while the primary agent is responding, metadata is
pending, a task/eval async job with an `agentId` is running, or the session is
inside a short post-activity window. Back off to five seconds while quiescent.
`ctx.getAsyncJobSnapshot()` is only a scheduling hint; native job aggregates
never enter the cost total.

### Credential routing

Every queued discovery carries a `credentialSessionId`:

- primary and top-level advisor responses use the primary session id;
- subagent responses use that child transcript header's session id;
- subagent-advisor responses use their owning child session id.

Replace the single `apiKeyPromise` with a map keyed by credential session id,
then call `getApiKeyForProvider("openrouter", credentialSessionId, ...)`.
This preserves OMP's child credential affinity and still shares one resolution
among requests from the same owner. Never enumerate, compare, log, or persist
credentials.

OMP gives an advisor a random provider-facing session id that is not persisted
in its transcript. The repo's configured single OpenRouter key makes the
stable owning-session lookup resolve the same account. A multiple-OpenRouter-
account setup cannot prove the advisor's original account extension-only; a
404/authorization failure must remain unresolved (`+ ?`) rather than trying
arbitrary stored keys.

### Queue, persistence, and failure semantics

Queue items become `{ responseId, attribution, credentialSessionId }`. The
process-wide immutable cache remains keyed only by response id and stores
generation metadata, not session attribution. Reusing a cached generation in
another owned transcript still writes a v2 record for that owner.

Before `pi.appendEntry(...)`, require all of the following:

- this is still the active primary state;
- the discovery still belongs to that state's `ownerSessionId`;
- the response id remains in the state's observed-response index; and
- no valid v2/v1 record for that response id has already been persisted.

Network retry, timeout, numeric validation, and four-request concurrency stay
unchanged. Track transcript-scan failures separately from generation lookup
failures:

- `ENOENT` during discovery is a tolerated create/remove race and schedules
  another pass.
- A trailing unterminated line is pending input, not corruption.
- A parseable non-session JSONL is unrelated and ignored.
- A session-shaped malformed header is an owned-transcript failure even on its
  first scan. A malformed complete record later in a valid transcript taints
  that path but is skipped so later complete records remain discoverable. Clear
  the taint only after replacement or truncation causes a clean scan from byte
  zero.
- An unreadable owned transcript, invalid reserved advisor transcript, or
  exhausted metadata lookup means completeness is unknown. Log a concise path
  basename/reason once and show `+ ?`.
- A later successful lookup clears only the corresponding lookup failure.

### Display semantics

The primary OpenRouter view becomes the exact session-owned aggregate of
primary, advisor, subagent, and subagent-advisor generation metadata. The
status segment remains one number; v2 records retain the per-source attribution
for reconciliation rather than adding another TUI surface.

- `+ …` means the primary agent is responding, initial auxiliary reconciliation
  is running, or at least one discovered response is awaiting metadata.
- `+ ?` means a known lookup or owned-transcript reconciliation failed and
  takes precedence when both markers apply.
- A background auxiliary model call cannot be marked in flight before its
  assistant record is persisted; discovery is therefore bounded by the scan
  cadence. Do not show `+ …` merely because an unrelated async job exists.
- Focused-agent views still delegate to OMP's native renderer. Returning to the
  primary view shows the same aggregate; focus never adds another observation.
- Non-OpenRouter primary models still delegate to the native subscription,
  premium-request, advisor, and time-pricing renderer unchanged. Accumulated
  OpenRouter auxiliary spend reappears when the primary view uses OpenRouter.

### Implementation sequence

1. Split generation metadata from attribution in the extension state; add the
   v2 schema, v1 reader, uniform primary v2 writer, and per-credential key cache.
2. Add the byte-cursor JSONL reader and companion-tree walker in the same
   extension file. Keep it private; no second generic filesystem abstraction.
3. Wire initial/incremental scheduling, scan failure state, cancellation, queue
   discoveries, and pre-persist ownership checks.
4. Update `README.md`'s status-line description and `docs/omp.md`'s detailed
   semantics, delay/failure notes, resume behavior, and remaining exclusions.

`omp/setup-settings.sh` and `AGENTS.md` do not change: the segment id, extension
path, stow package inventory, and setup steps are unchanged.

### Verification

1. Build a throwaway Bun probe that loads the real extension factory after a
   `mock.module` shim supplies the host-only package, with a fake
   `ExtensionAPI`, temporary session tree, deterministic mocked generation
   responses, and captured `appendEntry`/status calls. Exercise primary,
   default/named advisors, top-level/nested subagents, and subagent advisors.
2. In that probe, append after the initial scan and confirm only the new
   response is looked up and persisted; then exercise `/move`, a named advisor
   whose slug is `bak`, a partial final line, inode replacement, truncation, a
   malformed first-seen child header, malformed complete JSON, an unrelated
   JSONL, a symlink escape, duplicate response ids across sources, and session
   cancellation.
3. Verify v1 primary restoration, immediate v2 auxiliary restoration, invalid
   owner/source-field combinations, deterministic conflict handling, and one
   v2 append per response id.
4. Verify credential resolution receives the primary id for primary/advisor
   records and each child header id for child/subagent-advisor records.
5. Re-run the existing missing-key, temporary 404, 429/5xx retry, timeout,
   terminal HTTP, malformed payload, and invalid numeric-field probes with
   auxiliary queue items included.
6. Deploy through `stow --no-folding omp` and
   `bash omp/setup-settings.sh`; confirm the right segment list still ends in
   `cost`.
7. In one small real OpenRouter session, enable the configured advisor, run a
   foreground subagent, let a detached subagent finish after the primary turn,
   wake the parked agent for another turn, spawn one nested agent, and exercise
   a subagent advisor. Observe each persisted transcript category increase the
   primary total once.
8. Focus each child and return to the primary view. Confirm focused views stay
   native and the primary aggregate neither disappears nor doubles.
9. Exit and resume. The full v2 total must render from primary entries before
   network reconciliation; new auxiliary responses must increase it after
   their transcript append and metadata indexing delay.
10. Independently enumerate every OpenRouter response id in the owned transcript
    tree, query generation metadata directly, group by persisted attribution,
    and compare the unique effective-cost sum with the display at two decimals.
11. Remove the throwaway probe and review both user-facing docs against the
    observed TUI behavior.

No permanent live-network test: it would spend API usage and remain
nondeterministic. The byte-cursor and ownership cases justify a deterministic
probe during implementation, but this dotfiles repo should not gain a test
framework solely for one extension.

### Remaining non-primary work

Title generation and other internal `completeSimple()` calls still expose no
response id to extensions. Per-turn subagent attribution is also unavailable
after restart: OMP persists the child transcript and agent id, but not the
spawning `parentToolCallId` in that transcript.

The durable upstream replacement for transcript scraping remains one replayable
completed-generation event, or the same ownership fields persisted on the
normalized assistant message:

```ts
type BillableGeneration = {
  responseId: string;
  provider: string;
  ownerSessionId: string;
  credentialSessionId: string;
  source: "primary" | "subagent" | "advisor" | "title" | "internal";
  agentId?: string;
  advisorSlug?: string;
  parentToolCallId?: string;
};
```

The host should own these identities. The extension should continue to own
OpenRouter lookup, bounded retry, deduplication, persistence, and display.
The live status value now includes primary, advisor, subagent, and
subagent-advisor OpenRouter spend. Title/internal generations and per-turn
subagent ownership remain excluded as described above.

## Non-goals

- Changing OMP's persisted `message.usage.cost` or global `omp stats` database.
- Replacing the `S…` subscription-equivalent display.
- Carrying a forked OMP binary or changing OpenRouter routing/account settings.
