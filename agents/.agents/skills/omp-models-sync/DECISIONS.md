# omp models sync: decisions and rationale

Companion to `SKILL.md` in this directory. Read it before changing a role,
chain, allowlist rule or Zed setting, so a deliberate choice is not "fixed" as
drift.

Standing decisions only: what was chosen, why, and what would reopen it.
Per-round changelogs (which ids moved where) belong in commit messages. When
a decision changes, rewrite or delete its entry (git keeps the history)
instead of stacking a superseding one. Mark entries recommended but not yet
applied as PROPOSED.

## Per-call allowlist and `*-sub` roles

- `task.perCallModelAllow` is derived from `CYCLE_ORDER` + `SUB_ROLES` as
  canonical `provider/id` without `:level`, so the user picks the thinking
  level per call.
- A bare role name (`sonnet`, `opus`, `haiku`) is the OpenRouter model;
  `X-sub` is the direct Anthropic subscription twin ("the sonnet sub model").
  Agents resolve it from the role name shown in the task tool's model
  listing, which works in any project; don't rely on a repo `AGENTS.md`.
- Rejected: a `before_subagent_spawn` extension that rewrites models.
- Revisit if omp adds provider-aware model aliases, or the listing stops
  showing role names.

## ZDR stays on; Fable is subscription-only

- ZDR is the user's deliberate choice: never suggest lifting it. Treat
  ZDR-hidden models (OpenRouter Fable, Qwen `flash`/`max`) as unavailable and
  use a subscription id instead.
- `fable` and `fable-sub` are both `anthropic/claude-fable-5-2:high`; keeping
  both preserves the "X sub" naming, and the allowlist and Zed scope
  de-duplicate. To remove a role, delete it from `DEFAULT_ROLES`/`SUB_ROLES`
  first and then live (`jq 'del(."fable-sub")'`), or the fill-in seed re-adds
  it.
- The `anthropic/claude-fable-5-2` -> OpenRouter Opus fallback chain covers a
  hit cap or expired login for the main session and role-routed subagents.
  Per-call spawns never fall back (omp design); the unavailable-model rule in
  `SKILL.md` covers them: substitute and report, deliberately not automated by
  a hook or mapping. Revisit if omp adds a per-call fallback chain or
  substitutions often go wrong.
- Accepted: Fable bypasses ZDR and uses the subscription's weekly cap;
  `openrouter-session-cost.ts` hides the OpenRouter total while it's active.
- Revisit if ZDR is lifted or Anthropic changes subscription limits.

## OpenRouter OpenAI roles are not pinned to an upstream

- No `@azure` (or other `@upstream`) on OpenRouter OpenAI roles. With ZDR on,
  the only ZDR endpoints for GPT-6 Luna, 6.1 Terra, 6.2 Sol and 6.2 Astra are
  Azure (`azure`, `azure/us` +10%, `azure/eu` +20%;
  `curl -s https://openrouter.ai/api/v1/endpoints/zdr`), so traffic stays on
  Azure and OpenRouter can fail over between its regions. Each answered from
  `provider: Azure` unpinned (2026-11-17).
- Revisit if ZDR is lifted: routing could then reach OpenAI direct (`flex`,
  cheap but slow; `fast`/`ultrafast`, 2-3x price). Re-pin or set provider
  preferences then.

## Zed ACP is supported; the dropdown model is not tracked

- ACP must keep working. A fresh `omp acp` with Zed's flags gets the global
  `AGENTS.md`, `RULES.md`, the per-call `model` field and the role-named
  model listing (probed on omp 18.20.2); every round ends with `SKILL.md`
  Procedure step 5.
- Out of scope (user): the model picked in Zed's dropdown
  (`default_config_options.model`) and fallback chains for it, including
  `*-sub` -> OpenRouter twin chains; whether chains honour `enabledModels`.
- Revisit if omp ACP starts reloading context per thread, or the user relies
  on a fixed subscription model as the Zed default.

## Zed picker scope

- Regenerated from roles every run. `*/*<id>` patterns match every provider,
  so extras (a second, unlabelled direct Gemini 4 Neon) are tolerated and
  reported; a missing model is not. `(sub)` labels come from
  `setup-model-labels.sh`, which `setup-settings.sh` does not run (`SKILL.md`
  Procedure step 4).
- `oa-*` (Codex) roles are skipped (user, 2026-11-16): their ids pulled in
  near-identical older-generation rows (Codex and OpenRouter GPT-5.6 Terra
  beside the intended GPT-6.1 Terra), and a Zed plan ran on the wrong one.
  Claude twins don't have this problem: both rows are intended, the same
  model on two billing routes, told apart by `(sub)`. Covered by
  `omp/tests/zed-models-config.sh`.
- Untried: provider-scoped patterns for roles that name a provider, which
  would drop the cross-provider extras.
- Revisit if a Codex subscription becomes a regular Zed choice: delete the
  `oa-` skip in `setup-zed-models.sh`, re-run `omp/setup-settings.sh`, and
  re-probe.

## In Zed, plan mode uses the thread's model

- In ACP, Plan keeps the thread's model and thinking and ignores the `plan`
  role; a model picked in Plan applies at once and stays after leaving
  (probed on omp 18.20.2; details in `plans/omp-plan-mode-models.md`).
- The user prefers this per-thread choice: don't force the `plan` role in
  ACP or build `/planopus`-style commands for Zed (`sessionModes` is
  undefined in ACP). The `plan` role stays maintained for the terminal.
- Revisit if an omp release makes ACP apply the `plan` role (flag it: the
  per-thread choice would be lost).

<a id="native-zed-agent-favorites"></a>
## Native Zed Agent favorites mirror the omp cycle

- User (2026-11): one zed.dev favorite per omp cycle model, so the native
  picker matches the ladder: Haiku 4.5, GPT-5.6 Terra, GPT-6.1 Sol, Sonnet
  5.5, Gemini 4 Argon (stand-in for Neon), Opus 5.5, Fable 5.2. Use the newest
  generation Zed hosts for each; replace Argon with Gemini 4 Neon once Zed
  hosts it. Models outside the cycle stay out (GPT-6 Astra, Gemini 3.5 Flash,
  GPT-6 Luna, GPT-5.3-Codex, GPT-5 mini and nano). Zed only, not omp.
- Zed can't hide models (`hidden_models`, zed-industries/zed#52347, closed
  unmerged; `available_models` only adds), so `agent.favorite_models` pins
  instead, and shows the pins in Zed's catalog order, not the settings order.
  Starring in the UI rewrites the list; commit those diffs.
- Not omp: Zed 1.28.1's native Agent (1.29.1 unchanged in source) can fail on Claude with
  `unknown variant 'between_tools'`, mostly during compaction; reloading the
  agent clears it. Don't change model settings for it.
- Revisit if Zed ships a hide/allowlist setting, or hosts Neon or a newer
  generation of a pinned line.

## Standing notes for each round

- DeepSeek, Kimi and GLM are retired by the user (never used): no `dseek`,
  `kimi`, `glm-*` or `cheap-l` roles, cycle slots, tags or chain entries;
  `setup-settings.sh` strips them from a live config. Don't re-add them as "newest
  generation" drift.
- Cycle order is a rough cheap-to-expensive line with `default` (Terra) in the
  middle: `haiku`, `default`, `hydrogen` (trial), `sol`, `sonnet`, `neon`,
  `opus`, `fable`. New sessions start on the `default` role (not the first
  slot or last used model), so slot order only sets what `Ctrl+P` /
  `Shift+Ctrl+P` reach next; keep `terra` out of the cycle (`default` is it) and
  Sol in. `luna` is out too (user, 2026-11): Haiku 5.5 scores 36 vs Luna's 28 at
  the same list price, and one step-down slot is enough. Rationale: Artificial
  Analysis 2026-11 (Sol 6.2 beats Terra on index at similar cost per task) and
  the coding note below.
- Every role and chain uses only cycle models (or their
  `*-sub` / Codex twins) (user, 2026-11, consistency over Luna's small savings).
  `commit` -> Haiku `:medium`, `advisor` -> Haiku `:high` (cheap, different
  family from the Terra default; its 100K window means more advisor
  compaction). The `luna` and `oa-s` roles and the Luna chain are gone; `RETIRED_RE` in `setup-settings.sh` strips them from a
  live config.
- **No OpenRouter Auto Code router** (user, removed 2026-11-19). Tested with
  the pool narrowed to one model per request: Sol, Sonnet and Opus routed;
  Gemini 4 Neon and Hydrogen failed with "No measured models satisfy the Auto
  Code policy" (OpenRouter only routes models it has measured, so new releases
  are left out), and GPT-6.1 Terra with "No router pool model is routable". The
  six-model pool was really three. omp also records and shows
  `openrouter/auto-code`, not the routed model (only in the response `model`
  field or the generation record), so you can't tell what ran. The role, tag,
  empty fallback chain, cycle slot, Zed favorite, `setup-auto-code.sh` and its
  test are gone; `RETIRED_RE` and the role/tag `del` lists strip them from a
  live config. Revisit only if the router covers new models promptly and omp
  shows the routed model; run the router check in `SKILL.md` Gotchas first.
- Coding benchmarks decide the top of the ladder (user, 2026-11-19). On the
  Artificial Analysis Coding Agent Index v2.1 (each model in its own vendor's
  harness): Neon xhigh 58.6 ($6.86/task), Fable 5.2 high 58.2, Opus 5.5 max
  58.2, Sonnet 5.5 max 56.3, Carbon high 55.5 ($9.75), GPT-6.2 Astra max 53.5
  ($5.12). So Neon replaced Carbon (better and cheaper; Carbon's price doubles
  on 2026-12-01) and Astra was dropped with its `oa-xl` role and chain steps
  (it trailed Neon, Opus and Sonnet on coding despite the higher general
  index). `neon` runs at `xhigh`, the measured setting. Revisit if Astra's
  successor or a Neon `high` row changes the coding order.
- Fallback chains and the Codex `oa-*` roles track the newest generation of each
  tier (terra 6.1, sol 6.2), same as the OpenRouter roles. The Codex catalog on
  this machine lists only `gpt-6-luna` (and 5.6 Luna/Terra), so the 6.1/6.2
  Codex ids are unverified; omp skips unavailable steps. Revisit if a Codex id
  turns out not to exist.
- `hydrogen` is a **trial** (user, 2026-11-19): Gemini 4 Hydrogen at `high`,
  right after `default`. Same general index as Terra (51) at about 2x the cost
  per task, but about 1.7x faster per task and 10x faster to the first token
  (17 s vs 173 s); 52.3 on the Coding Agent Index at `xhigh`. Zed hosts no Hydrogen, so no
  native favorite. To end the trial: drop it from `DEFAULT_ROLES`, `DEFAULT_MODEL_TAGS`
  and `CYCLE_ORDER`, add `.hydrogen` to the role and tag `del` lists, remove it
  from the omp Zed favorites, and update
  the docs and the ladder record.
