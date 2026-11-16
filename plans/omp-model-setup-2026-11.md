# omp: model setup overhaul (2026-11)

Status: shipped to live config and committed (2026-11-16, omp 18.20.2; see
`git log` for the two commits that name this file). Intent: let the user pick any cycle model, or its Anthropic
subscription twin, per subagent call at any thinking level, and keep the whole
model setup (roles, chains, Zed picker, docs) coherent across rounds. This file
is a compressed record of one long session: the why and the history. The how-to
is the [omp-models-sync skill](../agents/.agents/skills/omp-models-sync/SKILL.md);
plan-mode details are in [omp-plan-mode-models.md](omp-plan-mode-models.md).

## If you only read one thing

- `omp/setup-settings.sh` is the source of truth and live config must equal it
  (only `web` differs). Seeding is fill-in-only: change live with
  `omp config set`, passing the whole merged object, never just the new key.
- Never hand-set `task.perCallModelAllow`; it is derived from `CYCLE_ORDER` +
  `SUB_ROLES` on every run. Add a role there and re-run instead.
- Bare name = OpenRouter, `X-sub` = direct Anthropic subscription. Anthropic
  ids are dashed (`claude-opus-5-5`), OpenRouter ids dotted (`claude-opus-5.5`).
- Do not suggest turning off OpenRouter Zero Data Retention (ZDR). A missing
  OpenRouter id may be ZDR-hidden, not gone; `fable` stays on the subscription.
- Unavailable subagent model: substitute and report, never stop to ask, unless
  the user required that exact model. Keep the three wordings in sync.
- In Zed (ACP) the dropdown picks the planning model; `modelRoles.plan` only
  matters in the terminal. Do not try to force it in ACP.
- Run omp config commands from a temp dir (`cd "$(mktemp -d)" && omp ...`).

## Outcome

| What | Owner |
|---|---|
| Roles incl. `fable` on subscription | `omp/setup-settings.sh` `DEFAULT_ROLES` |
| `*-sub` roles (sonnet, opus, haiku, fable) | `SUB_ROLES`, out of the cycle |
| Per-call model on, 15-entry allowlist | `setup-settings.sh` (derived) |
| Fable -> OpenRouter Opus chain, GLM chains | `DEFAULT_FALLBACK_CHAINS` |
| Unavailable-model rule, naming, Zed plan note | `omp/.omp/agent/AGENTS.md` |
| Sticky one-line rule (reaches subagents) | `omp/.omp/agent/RULES.md` |
| Procedure, gotchas, decision log, ACP probe | the skill |
| Zed picker scope, `oa-*` excluded, 19 rows | `omp/setup-zed-models.sh` |
| Plan-mode findings, wanted `/planopus` | `plans/omp-plan-mode-models.md` |
| User-facing description | `docs/omp.md`, `README.md` (omp) |
| Short pointer to the skill | `AGENTS.md`/`CLAUDE.md` "Keeping omp models in sync" |
| Native Zed Agent favorites (not omp) | `zed/.config/zed/settings.json` `agent.favorite_models`, `docs/zed.md` |

## Decisions

- **Per-call model on, allowlist derived.** `task.perCallModel=on` (user set it
  by hand first; the script now forces it). The allowlist was `[]` (every
  routed model), then 12 cycle ids, then 16 with `*-sub`, now 15 after the dead
  OpenRouter Fable id dropped. Entries are canonical `provider/id`, no
  `:level`, because the user wants the thinking level free per call.
  Rejected: per-selector entries, a hand-maintained list.
- **Naming convention.** Bare role = OpenRouter, `X-sub` = Anthropic
  subscription; agents map words via the role names in the task tool's
  approved-model listing, which works in any project. Rejected: a
  `before_subagent_spawn` rewrite hook (alias expansion unverified, machinery).
- **`fable` is the subscription id.** OpenRouter Fable exists publicly but the
  account's ZDR setting hides it; the user keeps ZDR on. `fable-sub` is kept
  with the same value so "fable sub" still maps by name. Rejected: deleting
  `fable-sub` (re-seeding would re-add it mid-sequence) and guidance-only with
  no role change (the cycle would keep a dead id).
- **Fable fallback.** `retry.fallbackChains["anthropic/claude-fable-5-2"]` =
  OpenRouter Opus 5.5 `:high`. Covers the main session and role-routed
  subagents only; per-call spawns never fall back (omp design) and rely on the
  rule below. No `*-sub` -> OpenRouter chains for Opus/Sonnet/Haiku (user kept
  the Zed dropdown model out of scope).
- **GLM chain steps are low-stakes.** Qwen and DeepSeek swaps kept ids valid
  (`qwen3.8-2.4t-a95b:xhigh`, `qwen3.8-27b:medium`,
  `deepseek-v4.1-flash-1017:max`); Qwen supports only `low,medium,xhigh`. Do not
  optimise them each round.
- **Codex is low priority.** `oa-s` moved to `openai-codex/gpt-6-luna:high`;
  `oa-l` stays on `gpt-5.6-sol:xhigh`, reported not found, left unresolved.
- **Unavailable subagent model -> judgement.** Pick the closest substitute
  (same family on another provider first, never clearly weaker, keep the
  thinking level), finish, and say so in one line. Explicitly overrides the
  task tool's "stop and report; never substitute" default, except when the user
  required that exact model. Canonical copies: global `AGENTS.md` (main
  sessions, advisors) and `RULES.md` (subagents drop `AGENTS.md` but keep
  `RULES.md`); the skill restates it. Rejected: an automation hook.
- **Global files stowed with `--no-folding`** (`stow --no-folding omp`), so a
  second machine gets them with `git pull`. Rejected: machine-local
  `~/.omp/agent/AGENTS.md`; repo-only text (loads only inside this repo).
- **Skill, not a context-file section.** The procedure matters only during a
  model round; the context files keep a short standing rule pointing at it.
- **Drift resolved toward newest ids.** Eight live roles were on `gpt-5.6-*`
  while the script seeded `gpt-6.*`; live `plan` was `gpt-5.6-sol:high`. Live
  moved to the script (plan = OpenRouter Opus, per commit `48fcdf0`).
- **Plan mode.** Terminal: `modelRoles.plan` or `--plan <id>`; the role stays
  OpenRouter Opus 5.5 `:high` (option 1). Zed ACP ignores the role; the
  dropdown decides per thread, which the user prefers. Headless `--plan-yolo`
  did not apply the plan model (cause unknown). Wanted, not built:
  `/planopus`-style commands, TUI only.
- **Zed picker drops `oa-*`.** `*/*<id>` patterns matched `oa-m`'s
  `gpt-5.6-terra` on every provider, giving three near-identical Terra rows; a
  live Zed plan ran on Codex Terra. Excluding `oa-*` took the picker from 22 to
  19 rows. Claude twins are fine: same model on two billing routes, each with
  its own role and a `(sub)` label. The Codex GPT-5.6 rows were unwanted older
  generations. Revisit with a Codex subscription.
- **Native Zed Agent favorites (follow-up, Zed only).** The user wanted the
  native Zed Agent's model list limited to zed.dev's newest model per line.
  Zed 1.28.1 can't hide models (`hidden_models`, zed#52347, closed
  unmerged), so `agent.favorite_models` pins 10 models instead. zed.dev lags
  OpenRouter: Fable 5.1, Haiku 4.5, GPT-5.6 Terra, no Carbon. TODO: add
  Carbon when Zed hosts it. The skill now checks this list every round
  (Procedure step 6). Kept separate from omp's dropdown on purpose.
- **User preferences recorded in the skill:** latest models always, ZDR stays
  on, Codex and GLM fallbacks low priority, Zed dropdown model out of scope,
  ACP must keep working, do not commit unless asked.

## Evidence

- **Per-call identity:** `perCallModelIdentity` in subagent session files for
  all four `*-sub` ids (`anthropic/claude-{haiku,sonnet,opus}-5-5`,
  `anthropic/claude-fable-5-2`) and for OpenRouter Haiku and Opus.
- **New ids:** each run once with `omp -p --model <id>` (Fable sub, Codex
  `gpt-6-luna`, the three fallback models); all answered.
- **ZDR:** public `api/v1/models` lists Fable; the per-key `models/user` list
  (291 models) does not; a direct request returns 404 "ZDR violation".
- **jq dry-runs** of the script's role, chain and allowlist logic against live
  config matched (live minus `web` equals defaults; allowlist 15 entries).
- **Context delivery:** a subagent spawned from a fresh session outside the repo
  carried the `RULES.md` text in `<generic-rules>` and no `AGENTS.md` text. An
  earlier probe from the long-running parent saw neither ([INFERENCE] parent
  started before `RULES.md` existed).
- **ACP:** `omp acp` with Zed's flags driven over stdio JSON-RPC: sees global
  `AGENTS.md`, `RULES.md`, the per-call `model` field and the listing; plan mode
  kept the thread's model; picker probe lists 19 rows (re-run 2026-11-16).
- **Plan mode, terminal:** `expect`-driven `omp --plan anthropic/claude-opus-5-5:low`
  then `/plan` logged a temporary `model_change` to Opus.
- **Thinking reset on model switch (ACP, from `high`):** dropped to `medium` on
  OpenRouter GPT-6.1 Sol, GPT-6.1 Terra and GPT-6 Luna; held on Claude
  (OpenRouter and sub) and Codex GPT-5.6 Terra. Cause unknown.

## Gotchas hit

- Fill-in-only seeding (`$defaults + .`) never updates an existing role or
  chain key; every changed value had to be applied live by merging into the
  whole `modelRoles` or `retry.fallbackChains` object.
- An apostrophe in a comment inside the single-quoted jq program in
  `setup-settings.sh` closed the quote and broke `bash -n`; comment moved out.
- Concurrent agents edited the skill, plan doc and `docs/omp.md` during the
  work; stale edit tags rejected whole batches. Re-read before each edit.
- omp config commands pick up project `.omp/` config unless run from a temp dir.
- First guesses used dotted Anthropic ids and claimed "OpenRouter has no
  Fable"; both wrong. Verify with `omp models find` and the ZDR diff.
- Fable subscription 429 (retry-after about 32 minutes) sank the Fable review.
- The ACP probe needs `OPENROUTER_API_KEY`; without it only a few rows appear.

## Reviews

- HybridReview (Opus sub): corrected the Fable diagnosis to ZDR, kept
  `fable-sub`, fixed Qwen levels, noted docs alone do not reach other projects.
- OmpModelsReview (Opus sub): one P1 (skill step would wipe `modelRoles`), jq
  hardening, wording fixes, and pre-existing stale ids (Fable, Qwen, `oa-l`).
- SecondOpusReview (Opus sub): rule vs task-tool default conflict, Fable chain
  overclaimed for per-call spawns, chain drift missing from the procedure, rule
  wording gaps, dead Fable id migration for other machines.
- FableReview failed on the 429; OpusReviewBackup (OpenRouter Opus): Terra
  picker hazard, thinking-reset wording, plan-doc timeline and scoping errors.
- All text fixes were applied; dropping `oa-*` from Zed was the user's call.

## Open items

- `/planopus`, `/planopussub`, `/plansol` extension: TODO at the top of
  `plans/README.md`, design in the plan doc.
- Headless `--plan-yolo` and `-p "/plan"` ignore the plan model: not investigated.
- `oa-l` (`openai-codex/gpt-5.6-sol`) unresolved; check `/model` for `gpt-6.1-sol`.
- Real subscription cap or login failure triggering the Fable chain: untested.
- Who switched the live Zed thread to Sonnet after plan approval, and the
  thinking level of those plan turns: unknown.
- Provider-scoped Zed patterns (would drop duplicate Carbon): idea, untested.
- `kimi-k3.1-pro`, `gemini-4-hydrogen`: flagged, not adopted.
- Zed itself was never driven; ACP checked only over JSON-RPC.
- Native Zed Agent: `gemini-4-argon` favorite id unverified (only in
  Zed's cloud list); Gemini 4 Carbon not hosted by Zed yet; Argon's intro
  price ends 2026-11-30.
- Not part of this work: `claude/.claude/settings.json`,
  `zed/.config/zed/settings.json` and `docs/zed.md` had unrelated uncommitted
  changes (Zed and Claude model picks) and were left out of the commits.
  The later favorites follow-up does edit `zed/.config/zed/settings.json`
  (`agent.favorite_models`) and `docs/zed.md`; commit those hunks with it.

## Links

- [docs/omp.md](../docs/omp.md): Plan mode; Subagents; Providers and model
  roles; Zed — ACP thread or terminal.
- [setup-settings.sh](../omp/setup-settings.sh),
  [setup-zed-models.sh](../omp/setup-zed-models.sh),
  [global AGENTS.md](../omp/.omp/agent/AGENTS.md),
  [RULES.md](../omp/.omp/agent/RULES.md), repo [AGENTS.md](../AGENTS.md) /
  [CLAUDE.md](../CLAUDE.md), [README.md](../README.md) (omp).
