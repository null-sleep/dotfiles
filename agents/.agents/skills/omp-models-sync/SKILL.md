---
name: omp-models-sync
description: Update or audit this dotfiles repo's omp (Oh My Pi) model setup — modelRoles, the Ctrl+P/Alt+O cycle, the *-sub Anthropic subscription roles, the per-call subagent allowlist, Auto Code pool, fallback chains, Zed model list (omp's ACP picker and the native Zed Agent's favorite_models), and the docs that repeat model ids. Use when new models ship, when the user says "update/refresh/sync the models" or asks whether the omp config is stale or drifted, and whenever you edit omp/setup-settings.sh model data.
---

# omp models sync

The omp model setup spans several files that must stay coherent. The user
does a round of updates whenever new models ship. Run this procedure, apply
the fixes, and **report what you found** (see "Flag to the user").

Scope: `/Users/dhruv/src/dotfiles` (stow repo). Shell must run outside a
project with its own `.omp/` config: prefix omp commands with
`cd "$(mktemp -d)" &&`, as `omp/setup-settings.sh` does.

## Policy: use the latest models, keep live == script

- **Use the newest generation of each family the catalog offers.** Never
  "reconcile" by reverting to an older id.
- **`omp/setup-settings.sh` is the source of truth; the live
  `~/.omp/agent/config.yml` must match it.** `DEFAULT_ROLES` is
  *fill-in-only* — it never overwrites a role already live, so any edit to it
  must also be applied live, or the two drift (this already happened: live
  `gpt-5.6-*` roles vs seeded `gpt-6.*`). `omp config set modelRoles` replaces
  the **whole** object, so always pass the full merged value, e.g.
  `omp config set modelRoles "$(omp config get modelRoles --json | jq -c '.value + {luna: "openrouter/..."}')"`.
  After a round, the only expected differences are the repo-forced `web`
  entries in `modelRoles` and `retry.fallbackChains`.
- Explain any intentional divergence in a comment next to the role instead of
  leaving it silent.

## Where model identity lives

- `omp/setup-settings.sh`
  - `DEFAULT_ROLES` — role → `provider/id:level`.
  - `DEFAULT_MODEL_TAGS`, `DEFAULT_FALLBACK_CHAINS` (GLM chains name DeepSeek,
    Qwen and Codex models; they go stale too).
  - `CYCLE_ORDER` (forced) and `SUB_ROLES` (`*-sub`: the direct Anthropic
    subscription twins, kept out of the cycle).
  - `task.perCallModelAllow` is **derived** from `CYCLE_ORDER` + `SUB_ROLES`
    on every run: canonical `provider/id`, no `:level`, so any thinking level
    is selectable per call. Never hand-set it; it is overwritten. Add the role
    to the cycle or `SUB_ROLES` and re-run instead.
- `omp/setup-auto-code.sh` — the Auto Code router pool is a fixed list of
  OpenRouter ids; it does **not** follow role edits.
- `omp/setup-model-labels.sh` — appends ` (sub)` to `anthropic/*` and
  `openai-codex/*` names; re-run when either provider ships models.
- `omp/setup-zed-models.sh` — writes `~/.omp/agent/zed-models.yml`, the
  `enabledModels` scope that decides what the **Zed omp model picker** (ACP
  `model` select) lists. Regenerated from `modelRoles` on every run of
  `setup-settings.sh`. Patterns are `*/*<model-id>`, matching the id on every
  provider, so a role's model also pulls in same-id models elsewhere (the
  `carbon` role also lists direct `google/gemini-4-carbon`). **The `oa-*`
  (Codex) roles are deliberately excluded** from the scope; see the 2026-11
  decision "Codex roles are left out of the Zed picker" below. Extras are
  expected; a missing model is not.
- `zed/.config/zed/settings.json` `agent.favorite_models` — **not omp**: the
  native Zed Agent's model selector (zed.dev-hosted models, billed through
  Zed Pro). Hand-maintained list of the newest zed.dev model per line, pinned
  at the top of the selector and cycled with `alt-tab`. It pins, it doesn't
  filter (Zed has no hide/allowlist setting). Repeated in prose in
  `docs/zed.md` → "Zed Agent's model list" (with Zed prices and the
  Zed-vs-OpenRouter generation gaps). See the 2026-11 decision "Native Zed
  Agent favorites track zed.dev's newest models".
- `omp/.omp/agent/extensions/cycle-model-picker.ts` — `Alt+O` picker over
  `cycleOrder`.
- Docs repeating ids: `docs/omp.md` (the `modelRoles` block under "Providers
  and model roles", Advisor paragraph, Per-call model paragraph, Auto Code
  pool sentence, the Plan mode section's `plan` role and thinking finding,
  "ACP-specific catches" under "Zed — ACP thread or terminal"), `README.md`
  (omp setup section) and `omp/.omp/agent/AGENTS.md` (names
  `anthropic/claude-fable-5-2` and `claude-sonnet-5-5`). `plans/` files are
  historical decision records; do not rewrite their model ids.
- Tests `omp/tests/*.sh` use fixture ids; touch them only when behavior
  changes, not on every model bump.

## Gotchas

- OpenRouter ids are dotted (`openrouter/anthropic/claude-sonnet-5.5`); the
  direct Anthropic catalog uses dashes (`anthropic/claude-sonnet-5-5`).
  Per-call `model` is matched **literally** against the catalog: verify every
  new id with `omp models find <name> --json` and use the returned
  `selector`. Role aliases (`@sonnet`), globs and partial ids are rejected.
- Per-call `model` conflicts with a `task.agentModelOverrides` entry and with
  a `^model:level` prompt tag. A bad selector errors; there is no fallback.
- Project `.omp/` settings can narrow `task.perCallModel`/`perCallModelAllow`
  but never widen them. Keep them in global config.
- Auto Code's pool needs OpenRouter ids; `*-sub` and `oa-*` roles are not
  usable there.
- Codex subscription (`openai-codex/*`, the `oa-*` roles) is **low priority**
  for this user, who uses OpenRouter for those models and only sometimes has
  a Codex subscription. A missing or "not found" `openai-codex/*` id is
  expected and not worth chasing: do not spend a round on it, do not block on
  it, and do not treat it as drift. Codex ids may also only appear at session
  start, so absence in `omp models find` is not proof they do not exist.
- **A missing OpenRouter id may be blocked by Zero Data Retention (ZDR), not
  absent.** The account's ZDR setting
  (https://openrouter.ai/settings/privacy) hides models whose endpoints
  retain data; omp's catalog is built from that filtered list, and a request
  gets a 404 "ZDR violation". Before declaring a model gone, diff the public
  `curl https://openrouter.ai/api/v1/models` against the per-key
  `curl -H "Authorization: Bearer $OPENROUTER_API_KEY" .../api/v1/models/user`.
  Present publicly but missing per-key = ZDR. Anthropic Fable and
  Qwen `qwen3.8-flash`/`qwen3.8-max-*` hit this in 2026-11.
- Models that support only some thinking levels (e.g. `qwen3.8-27b`:
  `low,medium,xhigh`) must use an exact supported `:level` in fallback
  chains; the docs describe clamping only for per-call and advisor levels.
- Per-call `model` with no `:level` inherits the agent's thinking level, not
  the role's suffix; include the level when it matters.
- **Plan mode is not a per-call model.** In the terminal its model comes
  from the `plan` role (or `--plan <id>` / `PI_PLAN_MODEL` for one launch), so
  an agent cannot pass one when asked to "plan with X". Headless
  `--plan-yolo` and `-p "/plan"` did not apply the plan model in testing.
  **In Zed (ACP) plan mode ignores the `plan` role:** it keeps the thread's
  model and thinking, so the user picks the planning model and thinking in
  Zed's selectors, per thread; leaving Plan keeps the picked model, and a
  model change can reset thinking (`high` -> `medium` on OpenRouter GPT-6.1
  Sol/Terra and GPT-6 Luna; Claude on OpenRouter and sub, and Codex GPT-5.6
  Terra, held `high`; probed 2026-11-16), so check it after switching. So the
  `plan` role matters only
  in the terminal; a Zed user asking to "plan with X" just picks X in the
  dropdown (it must be in the Zed scope). Details and evidence:
  `plans/omp-plan-mode-models.md`.
- **ACP (Zed) must keep working; the user cares about it.** Zed runs
  `omp acp --approval-mode yolo --config ~/.omp/agent/zed-models.yml` and keeps
  one process across threads. After changing roles, `RULES.md` or the global
  `AGENTS.md`, the user must reload the agent in Zed (a new thread may not be
  enough); say so in the report. **Out of scope:** the model picked in the
  Zed dropdown (`default_config_options.model` in
  `zed/.config/zed/settings.json`) is the user's choice and churns; do not
  flag it or add fallback chains for it. Unverified and not worth chasing
  (the user rarely uses GLM): whether fallback chains honour the
  `zed-models.yml` `enabledModels` scope.
- **Zed has two model pickers; don't mix them up.** omp's dropdown in an omp
  thread is scoped by `zed-models.yml` (OpenRouter + subscriptions, newest
  generations). The native Zed Agent's selector lists Zed's hosted models,
  and `agent.favorite_models` only pins entries there. Neither affects the
  other (`alt-tab` and favorites never reach omp's dropdown). Zed's
  `agent.default_model` is rewritten on every pick, so it's out of scope like
  omp's `default_config_options.model`.
- **zed.dev lags OpenRouter.** As of 2026-11 Zed hosts Fable 5.1 (OpenRouter
  5.2), Haiku 4.5 (5.5), GPT-5.6 Terra (6.1 Terra), and no Gemini 4 Carbon
  or Hydrogen. Only pin what https://zed.dev/docs/ai/models lists; never
  copy omp's newest ids into `favorite_models`. Zed ids follow neither omp
  form exactly: Claude is dashed (`claude-opus-5-5`), GPT and Gemini are
  dotted (`gpt-6.1-sol`, `gemini-3.5-flash`), provider `zed.dev`. Verify an
  id with `strings /Applications/Zed.app/Contents/MacOS/zed | grep -o
  '<id>'`. Models served only from Zed's cloud list (`gemini-4-argon` in
  2026-11) aren't in the binary; have the user star the model in the picker
  so Zed writes the real id, or flag it as unverified.

## Procedure

1. **Discover.** For each provider (`openrouter`, `anthropic`; `openai-codex`
   only as a quick check, see Gotchas) run `omp models find <family> --json`
   for every family in the cycle, `*-sub`, `dseek`, `kimi`, `astra`, `fable`,
   `carbon`, the fallback chains, and the Auto Code pool. Find the newest
   version and note anything deprecated, renamed, repriced or missing. Check
   thinking levels the model supports before keeping a `:level` suffix. If an
   OpenRouter id is missing, run the ZDR check in Gotchas before calling it
   gone.
2. **Detect drift.** Diff the live `omp config get modelRoles --json` against
   `DEFAULT_ROLES` (expect only `web`), live `retry.fallbackChains` against
   `DEFAULT_FALLBACK_CHAINS` (expect only `web`), and live `cycleOrder`
   against `CYCLE_ORDER`.
3. **Apply.** Update `DEFAULT_ROLES`/`SUB_ROLES`/`CYCLE_ORDER`/chains, apply
   the same role **and chain** changes live (merge into the existing object;
   see Policy; chains: `omp config set retry.fallbackChains "$(omp config get
   retry.fallbackChains --json | jq -c '.value + {...}')"`, since
   `$defaults + .` never updates an existing key), and update
   `setup-auto-code.sh` if the router pool should change.
4. **Re-run** `bash omp/setup-settings.sh` (regenerates the allowlist and the
   Zed picker scope), then `bash omp/setup-model-labels.sh`. `setup-settings.sh`
   does not call the labels script, and the `(sub)` suffix it keeps on
   `anthropic/*` and `openai-codex/*` names is the only thing that tells
   duplicates apart in Zed's picker. Confirm
   `omp config get task.perCallModelAllow --json` lists the intended models
   and the live-vs-script diffs are clean.
5. **Smoke test** a per-call subagent on a subscription id, e.g.
   `model: anthropic/claude-haiku-5-5:low` with a trivial prompt, and read
   `perCallModelIdentity` from the agent's session file. **Then check ACP**:
   start `omp acp` with the Zed entry's args (from
   `zed/.config/zed/settings.json`) in this repo, send JSON-RPC
   `initialize`, `session/new` (`cwd`, `mcpServers: []`) and a
   `session/prompt` asking the model, without tools, whether it sees the
   global `AGENTS.md`, the `RULES.md` rule, the task tool's `model` field,
   and the approved-model listing; collect `agent_message_chunk` updates.
   All four should be present, with the `*-sub` roles in the listing.
   **Also update and check the ACP model picker** with "ACP picker probe"
   below: every cycle and `*-sub` model from this round is present, each
   `anthropic/*` and `openai-codex/*` entry ends in `(sub)`, and nothing you
   retired lingers. A new model missing from the picker means its role is
   missing or the pattern did not match: re-run `setup-settings.sh`. Tell the
   user to reload the Zed omp agent; the picker is read when the agent
   process starts.
6. **Native Zed Agent favorites.** Fetch https://zed.dev/docs/ai/models and
   check whether any line has a newer hosted model than
   `agent.favorite_models` (and whether Gemini 4 Carbon is hosted yet; it's a
   standing TODO in that file). Update the list and the `docs/zed.md`
   paragraph (models, prices, generation gaps) together. Not driven by
   `setup-settings.sh`; nothing to re-run, and Zed reloads settings live.
7. **Docs and tests.** Update every doc listed above in the same change; run
   `for t in omp/tests/*.sh; do bash "$t"; done`.
8. **Do not commit unless asked**; other uncommitted changes in the tree
   (e.g. `claude/.claude/settings.json`) are the user's.
9. **Record the decision.** If you changed a role or a rule for a non-obvious
   reason, add it to "Decisions and rationale" below with the date, so the
   next round can tell a deliberate choice from drift.

## ACP picker probe

`session/new` returns the model list Zed shows in its dropdown. Print it from
the repo root (reads `zed-models.yml`, so run it after the re-run in step 4):

```bash
python3 - <<'EOF'
import json, os, select, subprocess, time
p = subprocess.Popen(
    ["omp", "acp", "--approval-mode", "yolo", "--config",
     os.path.expanduser("~/.omp/agent/zed-models.yml")],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
def rpc(i, method, params):
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params}) + "\n")
    p.stdin.flush()
    end = time.time() + 40
    while time.time() < end:
        if select.select([p.stdout], [], [], 1)[0]:
            m = json.loads(p.stdout.readline() or "{}")
            if m.get("id") == i:
                return m.get("result", {})
    return {}
rpc(1, "initialize", {"protocolVersion": 1, "clientCapabilities": {}})
res = rpc(2, "session/new", {"cwd": os.getcwd(), "mcpServers": []})
for o in res.get("configOptions", []):
    if o.get("id") == "model" or o.get("category") == "model":
        print("current:", o.get("currentValue"))
        for x in o.get("options", []):
            for y in x.get("options", [x]):
                print(y.get("value"), "|", y.get("name"))
p.kill()
EOF
```

Expect the `(sub)` rows (`anthropic/*` and `openai-codex/*`) and the OpenRouter
rows, sorted by provider, so an unlabelled `google/gemini-4-carbon` lands
between the Anthropic and Codex rows. Currently 19 rows. The only Codex row is
`openai-codex/gpt-6-luna` (matched by the `luna` role's id, not by `oa-s`,
which is excluded). Codex `gpt-5.6-terra` and OpenRouter `gpt-5.6-sol`/
`gpt-5.6-terra` should NOT appear; if they do, the `oa-` exclusion in
`setup-zed-models.sh` was lost. Known extras from the id-wide patterns: a
second, unlabelled "Gemini 4 Carbon" (direct `google/gemini-4-carbon`). Report
new or surprising extras; do not hand-edit `zed-models.yml` (it is generated).

The probe needs `OPENROUTER_API_KEY` in its environment, as Zed's omp process
has it. Without it (seen from an eval kernel, 2026-11-16) `session/new`
lists only a handful of rows (`anthropic/*`, Codex and
`google/gemini-4-carbon`) and starts on a subscription model; that is a probe
artifact, not drift.

## Flag to the user

Always surface these in your final report, even if you resolved them:

- A newer version of a model already in a role, or a new family worth a
  preset (and which role you would put it in).
- A model in a role, the cycle, the Auto Code pool or a fallback chain that is
  deprecated, renamed, repriced or gone from the catalog.
- Live config that had drifted from `DEFAULT_ROLES`, and what you changed.
- A `anthropic` subscription login that is expired or missing: the cycle
  `fable` role fails over to OpenRouter Opus (main session and role-routed
  subagents only); per-call Fable and the other `*-sub` models just error.
  `openai-codex` login state is low priority; mention it only if asked.
- A reminder to reload the Zed omp agent after the change, any model missing
  from or newly surprising in the Zed picker (see "ACP picker probe"), and
  anything else that would behave differently in a Zed ACP thread (other than
  the Zed dropdown model the user picked, which is out of scope).
- A newer zed.dev-hosted model than one in `agent.favorite_models`, a
  favorite Zed no longer hosts, Gemini 4 Carbon becoming available on Zed,
  a favorite id you couldn't verify, and an introductory price ending (Gemini
  4 Argon: $2.20/$11 until 2026-11-30, then $4/$20).
- omp release notes affecting roles, `task.perCallModel*`, `cycleOrder`,
  selector syntax, or how plan mode picks its model (terminal or ACP).
- Anything you could not verify (no catalog entry, no credentials).

## When a requested subagent model is unavailable

Standing preference, **overriding the task tool's own default ("requested
model unavailable: stop and report; never substitute")**: use judgement; do
not stop and ask. Per-call `model` has no automatic fallback (a bad,
unapproved, ZDR-hidden, expired-login or capped selector fails preflight or
the worker), so when a spawn fails for that reason, or the model the user
named does not exist, **and the user did not require that exact model**
(benchmarks, A/B comparisons, "only on X"; then stop and report as usual):

1. Pick the closest sensible substitute yourself: same family on another
   provider first (e.g. `sonnet-sub` -> OpenRouter `sonnet`, subscription
   Fable -> OpenRouter `opus`), otherwise the nearest tier and cost among the
   approved models. Do not drop to something clearly weaker for work that
   needs quality, and keep the requested thinking level where supported.
2. Spawn with the substitute and finish the task.
3. Tell the user in the final report which model you used instead and why,
   in one line, so they can correct it. Do not make this a blocking question.

Applies to any subagent spawn, in any project. The canonical, stowed copies
are `omp/.omp/agent/AGENTS.md` (full version, main sessions and advisors) and
`omp/.omp/agent/RULES.md` (short sticky version, which task subagents also
receive); keep all three wordings consistent when changing the rule.

## Decisions and rationale

Append new entries; keep old ones and mark them superseded rather than
deleting. Each says what would make us revisit it. Entries marked PROPOSED
were recommended but not yet approved/applied; once applied, drop the marker
and say what was actually done.

### 2026-11: `*-sub` roles and per-call allowlist

- **Decision:** `task.perCallModelAllow` is derived from `CYCLE_ORDER` +
  `SUB_ROLES`, canonical `provider/id` without `:level`. The user normally
  uses only the cycle's models but wants to choose the thinking level per
  call, so the list is per model, not per selector.
- **Naming convention:** a bare role name (`sonnet`, `opus`, `haiku`) is the
  OpenRouter model; `X-sub` is the direct Anthropic subscription model. The
  user says "the sonnet sub model". The mechanism is the role name shown next
  to each approved model in the task tool's listing, so it works in any
  project. `AGENTS.md`/`CLAUDE.md` in the repo load only inside this repo
  (this skill is stowed globally but loads only when an agent decides to use
  it), so do not rely on them alone.
- **Rejected:** a `before_subagent_spawn` extension to rewrite models (the
  `@role` expansion was never verified, and it is extra machinery).
- **Revisit if:** omp adds provider-aware model aliases, or the listing stops
  showing role names.

### 2026-11: Fable is subscription-only; `fable` and `fable-sub` share a model

- **Finding:** `openrouter/anthropic/claude-fable-5.2` exists on OpenRouter
  publicly but is excluded by the account's Zero Data Retention (ZDR) setting
  (see Gotchas), so omp reports it as not found and the old `fable` cycle
  role pointed at a dead id. Fable is available only as
  `anthropic/claude-fable-5-2` (subscription).
- **ZDR is a deliberate choice: do not suggest turning it off.** The user
  considered lifting ZDR to get OpenRouter Fable (and Qwen `flash`/`max`) back
  and chose to keep ZDR on. Treat ZDR-hidden models as unavailable, and put
  the subscription id in the role instead.
- **Decision (applied):** `fable` (cycle role) =
  `anthropic/claude-fable-5-2:high`, and `fable-sub` is **kept** with the same
  value. Two roles on one model costs nothing: the allowlist and Zed scope
  de-duplicate, labels are per model. Keeping `fable-sub` preserves the
  predictable "X sub" name that the per-call listing relies on. To remove a
  role later, delete it from `DEFAULT_ROLES` and `SUB_ROLES` first and then
  from the live object (`jq 'del(."fable-sub")'`); seeding is fill-in-only
  and `$defaults + .` would re-add it on any run in between.
- **Rejected:** guidance-only ("for Fable always use the anthropic id") with
  no role change: Ctrl+P and Alt+O would still select a model omp cannot
  find, the task listing would keep advertising a dead id, and the allowlist
  would keep a dead entry.
- **Consequences accepted:** Fable runs outside the ZDR setting and draws on
  the subscription's Fable weekly cap rather than per-token OpenRouter
  billing; `openrouter-session-cost.ts` hides the OpenRouter total while a
  non-OpenRouter model is active.
- **Fallback (applied):** `retry.fallbackChains["anthropic/claude-fable-5-2"]`
  = `["openrouter/anthropic/claude-opus-5.5:high"]`, so a hit cap or an
  expired login moves to OpenRouter Opus instead of erroring in the main
  session. Model-selector keys match the exact model whichever role selected
  it, so the one key covers both `fable` and `fable-sub` **when they are the
  active model of the main session or a role-routed subagent**. Per-call
  spawns (`fable` or `fable-sub` passed as `model`) get no automatic fallback
  (`omp://tools/task.md`: per-call workers "do not drop `model` or use an
  automatic model fallback"); they rely on the unavailable-model rule above.
  It is seeded fill-in-only like the GLM chains.
- **Revisit if:** the user lifts ZDR (then OpenRouter Fable could return as
  `fable`, with `fable-sub` as the subscription twin), or Anthropic changes
  subscription limits.

### 2026-11: Fallback chains and Codex roles

- **Applied:** GLM 5.3 chain Qwen step -> `qwen3.8-2.4t-a95b:xhigh`; GLM 5.3
  Flash chain DeepSeek step -> `deepseek-v4.1-flash-1017:max` (newer and
  cheaper than `v4-flash-0731`, ZDR-visible), Qwen step ->
  `qwen3.8-27b:medium`, Codex tail -> `openai-codex/gpt-6-luna:high`. Both
  Qwen models support only `low,medium,xhigh`, so use exactly those levels.
  All new ids were run once with `omp -p --model <id>` and answered.
- **Unverified:** which Qwen model is the analog of the old `-max` (an
  inference from price and size). `27b` has a 262k context on its ZDR
  endpoint versus 1M for GLM Flash, so a long session falling back to it may
  fail and move on to the next entry.
- `oa-s` = `openai-codex/gpt-6-luna:high` (verified to run). **`oa-l` is
  unchanged** at `gpt-5.6-sol:xhigh`, which omp reports as not found. Codex is
  low priority (see Gotchas), so leave it unless the user asks; if they do,
  check an interactive session (`/model`) for `openai-codex/gpt-6.1-sol`.
- The DeepSeek/Qwen fallback steps are low-stakes (the user rarely uses the
  GLM roles); do not spend effort optimizing them each round beyond keeping
  ids valid.
- **Not adopted, flag each round:** `kimi-k3.1-pro`, `gemini-4-hydrogen`
  (supports `xhigh`; `carbon` stops at `high`).

### 2026-11: Unavailable subagent model -> use judgement

- **Decision:** the user wants agents to pick a sensible substitute and tell
  them, not stop to ask, when a requested subagent model is unavailable. See
  "When a requested subagent model is unavailable".
- **Not done:** an extension or `before_subagent_spawn` hook to automate it;
  per-call selection has no built-in fallback by design, and judgement covers
  the cases (ZDR-hidden ids, expired logins, caps, typos).
- **Revisit if:** omp adds a per-call fallback chain, or substitutions turn
  out wrong often enough to justify an explicit mapping.

### 2026-11: ACP (Zed) is a supported surface for all of this

- **Finding (probed on omp 18.20.2):** a fresh `omp acp` with the Zed
  entry's flags gets the global `AGENTS.md`, the `RULES.md` sticky rule, the
  per-call `model` field and the approved-model listing with role names,
  the same as the terminal. A thread started after reloading the Zed agent
  had them all.
- **Requirement:** the user wants this to keep working in Zed; every round
  ends with the ACP check in Procedure step 5 and the ACP items under "Flag
  to the user".
- **Out of scope:** see the next entry.
- **Revisit if:** omp's ACP mode starts reloading context files per thread,
  or Zed gains a per-thread agent process.

### 2026-11: Zed dropdown model and fallback gaps are out of scope

- **Decision (user):** do not track or fix the model picked in the Zed
  dropdown (`default_config_options.model`, written by Zed on each pick).
  It churns with the user's choice, so a check against it is stale by the
  next thread. Do not flag that it lacks a fallback chain and do not add
  `anthropic/*` subscription chains for it.
- **Also accepted:** per-call spawns never fall back (omp design; the
  `RULES.md` substitute rule covers them), and whether fallback chains honour
  the `zed-models.yml` `enabledModels` scope stays unverified (it only
  affects GLM chains, which the user rarely uses).
- **Not done:** `*-sub` -> OpenRouter twin fallback chains for Opus, Sonnet
  and Haiku. They would cover a capped subscription in the main thread, but
  the user chose to keep the Zed subscription model out of this setup.
- **Revisit if:** the user starts relying on a subscription model as a fixed
  Zed default, or a cap or expired login keeps interrupting Zed threads.

### 2026-11: The Zed picker is regenerated and checked every round

- **Finding (probed 2026-11-16, matches a Zed screenshot):** the picker
  listed 22 entries. Because `enabledModels` patterns are `*/*<id>`, a role's
  id matches on every provider, so it also showed a second "Gemini 4 Carbon"
  (direct `google/gemini-4-carbon`, unlabelled). `(sub)` names come from
  `models.yml` via `setup-model-labels.sh`, which `setup-settings.sh` does not
  run.
- **Decision:** Procedure step 4 runs the labels script after setup, and step
  5 runs the ACP picker probe. Extras are tolerated and reported.
- **Not done (unverified idea):** emitting provider-scoped patterns for
  roles that name a provider, which would drop the cross-provider extras and
  the duplicate Carbon. Not tried; revisit if the duplicates keep confusing
  picks.

### 2026-11: Codex roles are left out of the Zed picker

- **Finding:** `oa-m` is `openai-codex/gpt-5.6-terra`. Its id pattern
  `*/*gpt-5[.-]6-terra` matched on every provider, so the Zed picker showed
  three near-identical Terra rows: Codex `GPT-5.6 Terra (sub)`, OpenRouter
  `GPT-5.6 Terra`, and the intended OpenRouter `GPT-6.1 Terra` (plus
  OpenRouter `GPT-5.6 Sol` from `oa-l`). A live Zed plan ran on the Codex
  Terra instead of the intended one.
- **Decision (user, 2026-11-16):** `setup-zed-models.sh` skips every `oa-*`
  role, so the Zed picker drops from 22 to 19 rows and loses those three
  GPT-5.6 rows. The `oa-*` roles still exist and route in the terminal and
  for subagents; only the Zed dropdown changed. Codex is low priority and the
  GPT-5.6 rows are an older generation than GPT-6.1. `omp/tests/zed-models-config.sh`
  covers it.
- **Why Claude does not have this problem:** the Anthropic subscription
  models and their OpenRouter twins are both intended picker rows, told apart
  by the `(sub)` suffix, with a role for each (`opus`/`opus-sub` and so on).
  They are the same model on two billing routes, so picking the wrong twin
  only changes the route. Codex differed in two ways: the OpenRouter GPT-5.6
  rows were pulled in only by `oa-*`'s ids (no role of yours wanted them), and
  the near-identical names were different generations (GPT-5.6 Terra beside
  the intended GPT-6.1 Terra), so a wrong pick changed the model itself.
  (Inference from the picker contents and the live session; not a separate
  test.)
- **Revisit if:** a Codex subscription becomes a regular Zed choice. Then
  delete the `oa-` test in `setup-zed-models.sh`, re-run
  `omp/setup-settings.sh`, re-probe the picker, and expect the Codex Terra
  and the OpenRouter GPT-5.6 rows to return. If you want only the
  subscription row, try provider-scoped patterns first (untested; see the
  entry above).

### 2026-11: In Zed, plan mode uses the thread's model

- **Finding (probed on omp 18.20.2 with Zed's `omp acp` flags):** entering
  Plan keeps the current model and thinking (a plan-mode turn ran on
  `gpt-6.1-terra`, not the `plan` role's Opus); picking a model in Plan
  applies at once; leaving Plan keeps it; a model change can reset thinking
  (`high` -> `medium` on OpenRouter GPT-6.1 Sol/Terra and GPT-6 Luna;
  unchanged on Claude (OpenRouter and sub) and Codex GPT-5.6 Terra; cause
  unknown). Recorded in
  `plans/omp-plan-mode-models.md`.
- **Consequence:** in Zed the selectors choose the planning model and
  thinking per thread, which the user values as more flexible than the
  terminal's fixed `plan` role. Do not "fix" it by trying to force the
  `plan` role in ACP, and do not build the wanted `/planopus`-style
  commands for Zed (they are terminal-only; `sessionModes` is undefined in
  ACP). The `plan` role stays maintained for the terminal.
- **Unknown:** whether this is deliberate ACP behaviour or a side effect;
  how plan approval and its execution target appear in Zed.
- **Revisit if:** an omp release makes ACP plan mode apply the `plan` role
  (the user would lose per-thread choice; flag it), or Zed's model picker
  stops being available while in Plan.

### 2026-11: Native Zed Agent favorites track zed.dev's newest models

- **Request (user):** limit the native Zed Agent's model list to the newest
  model in each line Zed hosts, and add Gemini 4 Carbon once Zed hosts it.
  This covers Zed only, not omp.
- **Finding (Zed 1.28.1):** Zed has no way to hide models.
  `hidden_models` (zed-industries/zed#52347) was closed unmerged, and
  `language_models.*.available_models` only adds or overrides (Discussion
  #50303).
- **Decision:** `agent.favorite_models` pins Claude Fable 5.1, Opus 5.5,
  Sonnet 5.5, Haiku 4.5; GPT-6 Astra, GPT-6.1 Sol, GPT-5.6 Terra, GPT-6 Luna;
  Gemini 4 Argon, Gemini 3.5 Flash. GPT-5.3-Codex, GPT-5 mini and GPT-5 nano
  are left out as superseded (my call; the user can add them back). All ids
  except `gemini-4-argon` were found in the Zed binary.
- **Why a list in the settings file rather than starring in the UI:** it's
  stowed and reviewable. Starring still works, but it rewrites the list, so
  commit those diffs rather than discarding them.
- **Seen alongside (not omp):** Zed 1.28.1's native Agent can fail on
  Claude with `unknown variant 'between_tools', expected one of 'enabled',
  'adaptive', 'disabled'`, mostly during compaction. Retrying fails the same
  way; reloading the agent clears it. It's a Zed client/server mismatch, so
  don't touch any model setting to fix it.
- **Revisit if:** Zed ships a real hide/allowlist setting (switch to it),
  Zed hosts Carbon or a newer generation of any pinned line, or the user
  wants the GPT-5.x Codex/mini/nano lines back.
