# omp: the model ladder (2026-11)

Status: decision record, applied 2026-11-18 (omp cycle, roles, fallback
chains, Auto Code pool, Zed favorites). Intent: record which models this setup
uses, in what order, and why, so the next round of model releases can be judged
the same way instead of from scratch. The how-to for applying a change is the
[omp-models-sync skill](../agents/.agents/skills/omp-models-sync/SKILL.md); its
[DECISIONS.md](../agents/.agents/skills/omp-models-sync/DECISIONS.md) holds the
short standing rules. Earlier history: [omp-model-setup-2026-11.md](omp-model-setup-2026-11.md).

## If you only read one thing

- Climb only when the rung below failed: Terra by default, then Sol, then
  Astra. Carbon and Opus are second opinions from another model family, not
  upgrades. Fable is a last resort for hard non-coding reasoning.
- Rank on **cost and time per task**, not list price. Verbose models cost
  several times their list price suggests (Sonnet: same list price as Sol,
  about 10x the cost per task).
- The Artificial Analysis Intelligence Index is general-purpose; only two of
  its nine evals are coding. Check the coding evals before promoting a model
  for coding.
- Every role, fallback chain and the Auto Code pool uses only cycle models (or
  their `*-sub` / Codex twins). Astra and Fable never go in Auto Code: they run
  only when picked.

## The ladder

`cycleOrder` (cheap on the left, `default` in the middle):
`haiku`, `default` (Terra), `sol`, `sonnet`, `astra`, `carbon`, `opus`,
`fable`, `auto-code`. A new session starts on the `default` role, not the first
slot or the last model used. `Ctrl+P` climbs, `Shift+Ctrl+P` steps down.

| Rung | Role | Model | Use when |
|---|---|---|---|
| step down | `haiku` | Claude Haiku 5.5 | Trivial edits, quick questions; also `commit`, `advisor`, `smol`, `tiny` |
| 1 (default) | `default` | GPT-6.1 Terra | Everyday, well-scoped work; also `task`, `vision` |
| 2 | `sol` | GPT-6.2 Sol | Terra's answer wasn't good enough; multi-step work, review |
| side | `sonnet` | Claude Sonnet 5.5 | Different-family take at Sol's level; long prompts (no 272K surcharge) |
| 3 | `astra` | GPT-6.2 Astra | Hard debugging, architecture, subtle bugs |
| side | `carbon` | Gemini 4 Carbon | Astra stuck; terminal/ops work, long context, audio/video input |
| side | `opus` | Claude Opus 5.5 | Astra stuck and a Claude take is wanted; also the `plan` role |
| last | `fable` | Claude Fable 5.2 (subscription) | Hard reasoning or knowledge work nothing else solved |
| router | `auto-code` | OpenRouter Auto Code | Let OpenRouter pick among Terra, Sol, Sonnet, Opus, Carbon |

## The numbers behind it (2026-11-18)

Artificial Analysis leaderboard, Intelligence Index v5.0.1. Cost and time are
per index task at **Max** effort (Carbon at High). Our roles run at `high` or
`xhigh`, so real cost and time are lower; the ordering is what was used.
List prices and context windows are OpenRouter's.

| Model | Index | $ per task | Min per task | First token (s) | List in/out per M | Context |
|---|---|---|---|---|---|---|
| Haiku 5.5 | 36 | 0.41 | 14.8 | 184 | 0.10 / 0.50 | 100K |
| GPT-6.1 Terra | 51 | 0.96 | 14.7 | 146 | 1 / 5 | 1.05M |
| GPT-6.2 Sol | 57 | 1.01 | 8.4 | 73 | 2 / 10 | 1.05M |
| Sonnet 5.5 | 55 | 10.02 | 32.2 | 291 | 2 / 10 | 1M |
| GPT-6.2 Astra | 62 | 4.00 | 13.4 | 196 | 8 / 40 | 1.05M |
| Gemini 4 Carbon | 60 | 7.76 | 36.0 | 75 | 2 / 10 | 1M |
| Opus 5.5 | 59 | 10.04 | 24.6 | 362 | 4 / 20 | 1M |
| Fable 5.2 | 65 | 26.54 | 41.3 | 228 | 8 / 40 | 1M |

Coding evals (Artificial Analysis; only the top three of each were readable):

- Terminal-Bench 4.0: Kimi K3.1 Pro 67.2%, Carbon 65.2%, Astra 64.1%.
- FrontierCode-AA 2.0 (would a maintainer merge it): Fable 5.2 High 49.1%,
  Astra Xhigh 49.0%, Fable Max 48.8%.
- No independent coding score was found for Terra, Sol, Sonnet or Opus.

Output speed (tokens per second, where measured): Sonnet 147, Opus 118,
Carbon 60, Sol 6.1 49. Sonnet streams fastest but writes about 5x the tokens of
Sol, so Sol finishes a task about 4x sooner.

## Why each choice

- **Terra stays `default`.** Sol scores 6 points higher at about the same cost
  per task at Max effort, but Sol's list price is 2x Terra's and how they
  compare at the lower efforts we run is unmeasured. On OpenAI's own API Sol
  also bills a whole request at 2x input / 1.5x output past 272K input tokens
  (not checked on OpenRouter). Considered making Sol the default; kept Terra
  as the cheap starting point and put Sol one keypress up.
- **Sol is rung 2.** Best value in the set: 57 for $1.01 in 8.4 minutes.
- **Astra is rung 3, ahead of Carbon and Opus.** It outscores both, costs less
  than half of either per task, finishes faster, and ties Fable on
  FrontierCode.
- **Carbon before Opus.** Carbon scores a point higher and costs about 23% less
  per task; it is the slowest model on the ladder. Opus has no measured coding
  edge here; it stays as the Claude second opinion and the `plan` role.
- **Sonnet is kept as a side step.** Same list price as Sol and close on the
  index, but about 10x the cost per task. Kept for a different-family view,
  fast streaming, and long prompts. Online opinion (Sol 6.1 vs Sonnet 5.5) is
  a near tie split by workload: Sonnet reaches a result in fewer turns and has
  no long-context surcharge; Sol is cheaper on cache-heavy loops, more careful
  with invalid input, and followed system prompts and tools better in one
  orchestrator user's report. Its system card reports higher "unwanted
  persistence" and coding-deception rates than Astra.
- **Fable is last.** Highest index, but about 6.6x Astra's cost per task with no
  coding edge over Astra. It runs on the Anthropic subscription (OpenRouter
  Fable is hidden by the account's ZDR setting), so it spends the weekly cap.
- **Haiku is the only step down; Luna is dropped.** Same list price, Haiku
  scores 36 vs Luna's 28; Luna's lower verbosity saves fractions of a cent on
  commit messages. Consistency won. Haiku's 100K context is the catch: it is
  kept out of Auto Code (1M override) and makes the advisor compact more.
- **Auto Code pool:** Terra, Sol, Sonnet, Opus, Carbon. Astra and Fable are out
  so the user decides when to spend on them; Haiku is out for its context.

## Considered and not adopted

- **Gemini 4 Hydrogen** (index 54, $3.16 per task, 15.2 min, $1.50/$7.50):
  Sol beats it on quality, cost and time. Better value than Sonnet; would be
  worth it only as a Sonnet replacement. Supports `xhigh` (Carbon stops at
  `high`).
- **Gemini 4 Argon** (50): superseded by Carbon at the same price.
- **Kimi K3.1 Pro** (46, $3.68, 38.7 min): tops Terminal-Bench 4.0 but trails
  Terra on the index and is slow. Retired with DeepSeek (V4.1 Flash, 33) and
  GLM-5.3 (32) because they were never used.
- **Others below Terra on the index:** Qwen4 Max 43, Muse Wonder 44, Grok 4.7
  35, Muse Ember 36 (cheap and fast, Haiku territory).
- **Not checked:** `google/gemini-4-neon` ($3/$15), the newest Gemini on
  OpenRouter at the time.

## Redo it when new models ship

1. **Collect** for each candidate: Artificial Analysis index, cost per task,
   time per task, first-token time, and the effort level of that row; the
   Terminal-Bench and FrontierCode scores; OpenRouter list price, context
   window, and whether the per-key catalog lists it (ZDR can hide models; see
   the skill's Gotchas).
2. **Compare on the same effort** where possible, and on cost per task rather
   than list price.
3. **Place each candidate:**
   - Replace a rung if it beats that rung's model on index without costing
     clearly more per task (a newer Sol, Terra or Astra usually does).
   - Add a side step only if it brings a different family or a capability the
     rungs lack (context, modality, a coding-eval lead).
   - Skip it if an existing rung beats it on index, cost and time together.
4. **Check context windows** against roles that need long context (Auto Code's
   1M override, the advisor, long sessions on `default`).
5. **Keep consistency:** only cycle models in roles, chains and the Auto Code
   pool; Astra- and Fable-class models stay out of Auto Code.
6. **Apply** with the omp-models-sync skill, then update this file's tables
   and choices (or add a dated section if the reasoning changed).

## Sources

- Artificial Analysis: [leaderboard](https://artificialanalysis.ai/leaderboards/models),
  [Terminal-Bench 4.0](https://artificialanalysis.ai/evaluations/terminalbench-4-0),
  [FrontierCode-AA 2.0](https://artificialanalysis.ai/evaluations/frontiercode-2-0),
  model pages for Sol, Carbon, Opus and Sonnet.
- OpenRouter `/api/v1/models` (list prices, context windows).
- Sol vs Sonnet write-ups: [DataCamp](https://www.datacamp.com/blog/gpt-6-1-sol-vs-claude-sonnet-5-5)
  (one hands-on run), [Rohit Raj](https://rohitraj.tech/notes/gpt-6-1-sol-vs-claude-sonnet-5-5-coding-agents-2026)
  (cost math, system-card numbers), [HN comment](https://news.ycombinator.com/item?id=50312092)
  (instruction following in an orchestrator),
  [Hierarchy](https://hierarchy.ch/en/news/gpt-6-1-sol-vs-claude-opus-5-5-vs-gemini-4-argon)
  (mid-tier overview).
