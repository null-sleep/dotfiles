# omp: the model ladder (2026-11)

Status: decision record, applied 2026-11-18 and revised 2026-11-19 (Gemini 4
Neon replaced Gemini 4 Carbon, GPT-6.2 Astra dropped, both on coding
benchmarks). Covers the omp cycle, roles, fallback chains, Auto Code pool and
Zed favorites. Intent: record which models this setup uses, in what order, and
why, so the next round of model releases can be judged the same way instead of
from scratch. The how-to for applying a change is the
[omp-models-sync skill](../agents/.agents/skills/omp-models-sync/SKILL.md); its
[DECISIONS.md](../agents/.agents/skills/omp-models-sync/DECISIONS.md) holds the
short standing rules. Earlier history: [omp-model-setup-2026-11.md](omp-model-setup-2026-11.md).

## If you only read one thing

- Climb only when the rung below failed: Terra by default, then Sol, then Neon
  or Opus. Sonnet is a Claude side step at Sol's level. Fable is the last
  resort.
- **Coding benchmarks decide the top of the ladder**, not the general
  Intelligence Index: only two of its nine evals are coding. Use the
  Artificial Analysis Coding Agent Index and its components.
- Rank on **cost and time per task**, not list price. Verbose models cost
  several times their list price suggests, and terse ones (Astra) far less.
- Every role, fallback chain and the Auto Code pool uses only cycle models (or
  their `*-sub` / Codex twins). Fable never goes in Auto Code: it runs only
  when picked.

## The ladder

`cycleOrder` (cheap on the left, `default` in the middle):
`haiku`, `default` (Terra), `hydrogen` (trial), `sol`, `sonnet`, `neon`,
`opus`, `fable`, `auto-code`. A new session starts on the `default` role, not the first slot or
the last model used. `Ctrl+P` climbs, `Shift+Ctrl+P` steps down.

| Rung | Role | Model | Use when |
|---|---|---|---|
| step down | `haiku` | Claude Haiku 5.5 | Trivial edits, quick questions; also `commit`, `advisor`, `smol`, `tiny` |
| 1 (default) | `default` | GPT-6.1 Terra | Everyday, well-scoped work; also `task`, `vision` |
| trial | `hydrogen` | Gemini 4 Hydrogen (`high`) | Terra-level work when speed matters: same general score (51), about 1.7x faster per task and 17 s vs 173 s to the first token, at about 2x Terra's cost per task |
| 2 | `sol` | GPT-6.2 Sol | Terra's answer wasn't good enough; multi-step work, review |
| side | `sonnet` | Claude Sonnet 5.5 | Claude take near Sol's cost tier; strong coding agent; long prompts (no 272K surcharge) |
| 3 | `neon` | Gemini 4 Neon (`xhigh`) | Hard coding and agent work; codebase questions; long context, audio/video input |
| 3 | `opus` | Claude Opus 5.5 | Hard coding where a Claude take is wanted (leads FrontierCode); also the `plan` role |
| last | `fable` | Claude Fable 5.2 (subscription) | Hard problems nothing else solved |
| router | `auto-code` | OpenRouter Auto Code | Let OpenRouter pick among Terra, Hydrogen, Sol, Sonnet, Neon, Opus |

### The ladder exists only in the terminal

`Ctrl+P` and `Alt+O` follow `cycleOrder`; Zed's omp model dropdown does not.
omp's ACP server fills that dropdown from the model registry's own order
(grouped by provider, then catalog order), and `~/.omp/agent/zed-models.yml`
only filters it. Tested 2026-11-18 on omp 18.22.2 by probing `omp acp` with the
`enabledModels` list rewritten in ladder order plus `modelProviderOrder:
[openrouter, anthropic]`: the surviving rows came back in the same order as
before. Zed shows the options as sent. After a reload of the Zed omp agent the
dropdown lists the four `(sub)` Anthropic models, a direct
`google/gemini-4-neon` duplicate pulled in by the `*/*gemini-4-neon` pattern,
then the OpenRouter cycle models. Type to filter instead of scrolling.

Adopted: **favorites.** `agent_servers.omp.favorite_config_option_values.model`
in `zed/.config/zed/settings.json` stars the nine cycle models (OpenRouter
rows, Fable as the subscription row). Zed then shows a "Favorites" section above
the full list and `alt-tab` cycles only those in an omp thread, skipping the
`(sub)` twins and the direct-Gemini duplicate. Both follow omp's option order,
not the order in settings (Zed `config_options.rs`). Keep the list equal to the
cycle when the cycle changes. The native Zed Agent picker behaves the same way:
`agent.favorite_models` is read as a set and shown in Zed's catalog order (seen
2026-11-18: Sol, Opus, Fable, Sonnet, Haiku, Astra, Terra, Argon, Flash), and
its Recommended section and full catalog can't be hidden. Its favorites mirror
the cycle with the newest model Zed hosts for each line (Argon stands in for
Neon, which Zed does not host yet).

Options considered, not adopted:

- Rung numbers in display names ("2 Terra") via `modelOverrides` `name`: order
  unchanged, only helps type-to-filter, and the numbers would also show in the
  terminal picker and status line.
- Tighter Gemini pattern to drop the direct-Gemini duplicate (one row shorter).
- Upstream request or fork patch to sort ACP options by `cycleOrder`; this is
  in omp core, not reachable from an extension.

## The numbers behind it

### Coding (2026-11-19, the deciding data)

Artificial Analysis Coding Agent Index v2.1: the equal-weight mean of
FrontierCode-AA 2.0 (132 repo changes graded on whether a maintainer would
merge them), Terminal-Bench 4.1 (66 terminal tasks) and SWE-Atlas-QnA-AA (124
questions about a codebase). Each row is a model inside its own vendor's
harness (Claude Code, Codex, Antigravity CLI), so it measures model plus
harness; omp is a different harness for all of them.

| Model (effort) | Coding Agent Index | $ per task | Min per task | Notes |
|---|---|---|---|---|
| Gemini 4 Neon (xhigh) | **58.6** | 6.86 | 30.5 | FrontierCode 43.0, TB 4.1 65.2, QnA 67.7; 0 refusals |
| Claude Fable 5.2 (xhigh) | 58.5 | 15.47 | 53.3 | |
| Claude Fable 5.2 (high) | 58.2 | 7.51 | 31.3 | |
| Claude Opus 5.5 (max) | 58.2 | n/a | n/a | |
| Claude Sonnet 5.5 (max) | 56.3 | n/a | n/a | |
| Gemini 4 Carbon (high) | 55.5 | 9.75 | 33.6 | price doubles on 2026-12-01 |
| GPT-6.2 Astra (max) | 53.5 | 5.12 | 25.1 | FrontierCode 41.7, TB 4.1 63.6, QnA 55.1; 8 refusals |
| Gemini 4 Hydrogen (xhigh) | 52.3 | n/a | n/a | |
| GPT-6.1 Sol (max) | 52.2 | n/a | n/a | |
| GPT-6.2 Sol (xhigh) | 49.8 | n/a | n/a | down from 6.1 Sol: a 14-point drop on QnA |
| GPT-6.1 Terra (max) | 48.6 | n/a | n/a | |
| Claude Haiku 5.5 (max) | 29.6 | n/a | n/a | |

Read with care:

- The top five configurations sit within half a point, with no confidence
  intervals published.
- Most of Neon's 5-point lead over Astra is the Q&A component (12.6 points);
  on FrontierCode and Terminal-Bench, the two that change code, they are within
  2 points. Neon and Astra trade cost (Astra cheaper per task) for score.
- On FrontierCode-AA 2.0 alone, Opus 5.5 (46.4) edges Astra (45.4); Fable and
  Opus configurations reach about 49.
- Neon is measured only at `xhigh`; Google's claim that `high` costs 32% less
  per task than Carbon is unverified.

### General (2026-11-18)

Artificial Analysis Intelligence Index v5.0.1. Cost and time are per index task
at **Max** effort (Carbon High, Neon Xhigh). Our roles run at `high` or `xhigh`,
so real cost and time are lower. List prices and context windows are
OpenRouter's.

| Model | Index | $ per task | Min per task | First token (s) | List in/out per M | Context |
|---|---|---|---|---|---|---|
| Haiku 5.5 | 36 | 0.41 | 14.8 | 184 | 0.10 / 0.50 | 100K |
| GPT-6.1 Terra | 51 | 0.96 | 14.7 | 146 | 1 / 5 | 1.05M |
| GPT-6.2 Sol | 57 | 1.01 | 8.4 | 73 | 2 / 10 | 1.05M |
| Sonnet 5.5 | 55 | 10.02 | 32.2 | 291 | 2 / 10 | 1M |
| Gemini 4 Neon | 61 | 6.44 | 21.5 | 57 | 3 / 15 | 1M |
| Opus 5.5 | 59 | 10.04 | 24.6 | 362 | 4 / 20 | 1M |
| Fable 5.2 | 65 | 26.54 | 41.3 | 228 | 8 / 40 | 1M |
| GPT-6.2 Astra (dropped) | 62 | 4.00 | 13.4 | 196 | 8 / 40 | 1.05M |
| Gemini 4 Carbon (dropped) | 60 | 7.76 | 36.0 | 75 | 2 / 10 | 1M |

Output speed (tokens per second, where measured): Sonnet 147, Opus 118, Neon
110, Carbon 60, Sol 6.1 49, Astra 49.

## Why each choice

- **Terra stays `default`.** Sol scores higher at about the same cost per task
  at Max effort, but Sol's list price is 2x Terra's and how they compare at the
  lower efforts we run is unmeasured. On OpenAI's own API Sol also bills a
  whole request at 2x input / 1.5x output past 272K input tokens (not checked
  on OpenRouter). Kept Terra as the cheap starting point, Sol one keypress up.
- **Sol is rung 2.** Best general value: 57 for $1.01 in 8.4 minutes. On
  coding, 6.2 Sol (49.8) slipped below 6.1 Sol (52.2); still above Terra.
- **Sonnet is a side step.** Same list price as Sol but about 10x the cost per
  task on the general index; on coding it scores 56.3, well above Sol and
  Astra. Online opinion (Sol 6.1 vs Sonnet 5.5) is a near tie split by
  workload: Sonnet reaches a result in fewer turns and has no long-context
  surcharge; Sol is cheaper on cache-heavy loops, more careful with invalid
  input, and followed system prompts and tools better in one orchestrator
  user's report.
- **Neon is rung 3 and replaced Carbon.** Google built Neon from Carbon as a
  faster, cheaper tier, but it measures at least as well: top of the Coding
  Agent Index (58.6 vs Carbon 55.5), cheaper per coding task ($6.86 vs $9.75),
  faster (110 vs 60 tok/s), and Carbon's price doubles on 2026-12-01. Google
  still recommends Carbon for the deepest verification work; nothing measured
  here shows that edge. Runs at `xhigh`, the setting it was measured at.
- **Opus is rung 3 beside Neon.** Ties Fable and Neon on the Coding Agent Index
  and leads FrontierCode; slower (362 s to first token at max) and dearer per
  task. Kept as the Claude choice for hard coding and as the `plan` role.
- **Astra was dropped (2026-11-19, user, on coding data).** Highest general
  index after Fable and the cheapest per task at the top, but 53.5 on the
  Coding Agent Index, behind Neon, Opus, Sonnet and Carbon, with 8 hard
  refusals. Its `oa-xl` Codex role and its fallback-chain steps went with it.
  The tradeoff accepted: Neon costs more per coding task ($6.86 vs $5.12) for
  about 5 more points, mostly on codebase Q&A.
- **Fable is last.** Ties the top of the coding index at about 2x Neon's cost
  per task at `xhigh` (similar at `high`). Runs on the Anthropic subscription
  (OpenRouter Fable is hidden by the account's ZDR setting), so it spends the
  weekly cap.
- **Haiku is the only step down; Luna is dropped.** Same list price, Haiku
  scores 36 vs Luna's 28; Luna's lower verbosity saves fractions of a cent on
  commit messages. Consistency won. Haiku's 100K context is the catch: it is
  kept out of Auto Code (1M override) and makes the advisor compact more.
- **Auto Code pool:** Terra, Hydrogen, Sol, Sonnet, Neon, Opus. Fable is out so
  the user decides when to spend on it; Haiku is out for its context.

## Considered and not adopted

- **Gemini 4 Hydrogen** (index 54 at `xhigh`, 51 at `high`; coding 52.3;
  $1.50/$7.50): on trial in the cycle since 2026-11-19 (see the ladder table).
  On value alone Sol beats it on general work and Sonnet and Neon on coding;
  the trial tests whether its speed is worth the cost.
- **Gemini 4 Argon** (50, coding 45.5): superseded by Carbon and Neon.
- **Kimi K3.1 Pro** (46, coding 48.6): tops Terminal-Bench 4.0 but trails Terra
  on the index and is slow. Retired with DeepSeek (V4.1 Flash, 33) and GLM-5.3
  (32) because they were never used.
- **Others below Terra on the index:** Qwen4 Max 43, Muse Wonder 44, Grok 4.7
  35, Muse Ember 36 (cheap and fast, Haiku territory).

## Redo it when new models ship

1. **Collect** for each candidate: the Artificial Analysis Coding Agent Index
   row and its three components (FrontierCode, Terminal-Bench, SWE-Atlas-QnA),
   cost and time per coding task, and the effort level of that row; the
   general Intelligence Index, cost and time per task, first-token time;
   OpenRouter list price (and any introductory price end date), context window,
   supported thinking levels, and whether the per-key catalog lists it (ZDR can
   hide models; see the skill's Gotchas).
2. **Compare on the same effort** where possible, and on cost per task rather
   than list price. Note which harness each coding row used.
3. **Place each candidate:**
   - Replace a rung if it beats that rung's model on coding without costing
     clearly more per task (a newer Sol, Terra or Neon usually does).
   - Add a side step only if it brings a different family or a capability the
     rungs lack (context, modality, a coding-component lead).
   - Skip it if an existing rung beats it on coding, cost and time together.
4. **Check context windows** against roles that need long context (Auto Code's
   1M override, the advisor, long sessions on `default`).
5. **Keep consistency:** only cycle models in roles, chains, the Auto Code
   pool and both Zed favorites lists; Fable-class models stay out of Auto Code.
6. **Apply** with the omp-models-sync skill, then update this file's tables
   and choices (or add a dated section if the reasoning changed).

## Sources

- Artificial Analysis: [leaderboard](https://artificialanalysis.ai/leaderboards/models),
  [Coding Agent Index](https://artificialanalysis.ai/agents/coding-agents)
  (mirrored with scores at [BenchLM](https://benchlm.ai/benchmarks/aacodingagents)),
  [Terminal-Bench 4.0](https://artificialanalysis.ai/evaluations/terminalbench-4-0),
  [FrontierCode-AA 2.0](https://artificialanalysis.ai/evaluations/frontiercode-2-0),
  model pages for Sol, Carbon, Neon, Astra, Opus and Sonnet.
- Coding component and cost breakdowns: [OrcaRouter, Neon on the Coding Agent
  Index](https://www.orcarouter.ai/blog/gemini-4-neon-coding-agent-index),
  [OrcaRouter, Astra vs Opus](https://www.orcarouter.ai/blog/gpt-6-2-astra-vs-claude-opus-5-5),
  [OfficeChai, Astra 6.2 results](https://officechai.com/ai/gpt-6-2-astra-artificial-analysis-intelligence-index/).
- Neon vs Carbon: [Neon model card](https://deepmind.google/models/model-cards/gemini-4-neon/)
  (vendor numbers), [ToolColumn comparison](https://www.toolcolumn.com/learn/gemini-4-neon-vs-gemini-4-carbon)
  (tiers, prices, Carbon's 2026-12-01 price change),
  [DataCamp, Astra vs Carbon](https://www.datacamp.com/blog/gpt-6-2-astra-vs-gemini-4-carbon)
  (hands-on reliability).
- OpenRouter `/api/v1/models` (list prices, context windows).
- Sol vs Sonnet write-ups: [DataCamp](https://www.datacamp.com/blog/gpt-6-1-sol-vs-claude-sonnet-5-5)
  (one hands-on run), [Rohit Raj](https://rohitraj.tech/notes/gpt-6-1-sol-vs-claude-sonnet-5-5-coding-agents-2026)
  (cost math, system-card numbers), [HN comment](https://news.ycombinator.com/item?id=50312092)
  (instruction following in an orchestrator),
  [Hierarchy](https://hierarchy.ch/en/news/gpt-6-1-sol-vs-claude-opus-5-5-vs-gemini-4-argon)
  (mid-tier overview).
