---
name: omp-models-sync
description: Update or audit this dotfiles repo's omp (Oh My Pi) model setup — modelRoles, the Ctrl+P/Alt+O cycle, the *-sub Anthropic subscription roles, the per-call subagent allowlist, fallback chains, Zed model list (omp's ACP picker and the native Zed Agent's favorite_models), and the docs that repeat model ids. Use when new models ship, when the user says "update/refresh/sync the models" or asks whether the omp config is stale or drifted, and whenever you edit omp/setup-settings.sh model data.
---

# omp models sync

The omp model setup spans several files that must stay coherent. The user
does a round of updates whenever new models ship. Run this procedure, apply
the fixes, and **report what you found** (see "Flag to the user").

Standing decisions (why roles, chains and the Zed setup are the way they are,
and what would reopen each) live in [DECISIONS.md](DECISIONS.md) next to this
file (`skill://omp-models-sync/DECISIONS.md`). Read it before changing a role
or rule, so a deliberate choice is not "fixed" as drift.

Which models are in the cycle and why (the numbers, the ladder order, what was
rejected, and a checklist for judging new releases) is the model ladder record,
`plans/omp-model-ladder.md`. When new models ship, redo its "Redo it when new
models ship" checklist before changing roles, and update its tables after.

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
  `omp config set modelRoles "$(omp config get modelRoles --json | jq -c '.value + {haiku: "openrouter/..."}')"`.
  After a round, the only expected differences are the repo-forced `web`
  entries in `modelRoles` and `retry.fallbackChains`.
- Explain any intentional divergence in a comment next to the role instead of
  leaving it silent.

## Where model identity lives

- `omp/setup-settings.sh`
  - `DEFAULT_ROLES` — role → `provider/id:level`.
  - `DEFAULT_MODEL_TAGS`, `DEFAULT_FALLBACK_CHAINS` (the OpenAI chains name
    Codex models, and the Fable chain names OpenRouter Opus; both go stale
    each round, see Procedure step 3).
  - `CYCLE_ORDER` (forced) and `SUB_ROLES` (`*-sub`: the direct Anthropic
    subscription twins, kept out of the cycle).
  - `task.perCallModelAllow` is **derived** from `CYCLE_ORDER` + `SUB_ROLES`
    on every run: canonical `provider/id`, no `:level`, so any thinking level
    is selectable per call. Never hand-set it; it is overwritten. Add the role
    to the cycle or `SUB_ROLES` and re-run instead.
- `omp/.omp/agent/extensions/plan-critique.ts` — no model ids, but it builds
  a `task` `model:` selector from each cycle role, so every `CYCLE_ORDER` role
  must stay in `task.perCallModelAllow`; rerun `omp/tests/plan-critique-smoke.ts`
  after cycle changes.
- No OpenRouter Auto Code router (removed 2026-11-19, see
  [DECISIONS.md](DECISIONS.md)): don't re-add one without the router check in
  Gotchas.
- `omp/setup-model-labels.sh` — appends ` (sub)` to `anthropic/*` and
  `openai-codex/*` names; re-run when either provider ships models.
- `omp/setup-zed-models.sh` — writes `~/.omp/agent/zed-models.yml`, the
  `enabledModels` scope that decides what the **Zed omp model picker** (ACP
  `model` select) lists. Regenerated from `modelRoles` on every run of
  `setup-settings.sh`. Patterns are `*/*<model-id>`, matching the id on every
  provider, so a role's model also pulls in same-id models elsewhere (the
  `neon` role also lists direct `google/gemini-4-neon`). **The `oa-*`
  (Codex) roles are deliberately excluded** from the scope; see
  [Zed picker scope](DECISIONS.md#zed-picker-scope). Extras are expected; a
  missing model is not.
- `zed/.config/zed/settings.json`
  `agent_servers.omp.favorite_config_option_values.model` — hand-maintained
  stars in **omp's** Zed dropdown: one value per cycle model (the OpenRouter
  row; Fable's subscription row), giving a Favorites section and the
  `alt-tab` cycle in omp threads. Values are the ACP option ids (the
  `provider/id` the ACP picker probe prints). Update it whenever
  `CYCLE_ORDER` or a cycle role's model changes; a stale id just drops out of
  the Favorites section. Order is ignored (Zed shows omp's order).
- `zed/.config/zed/settings.json` `agent.favorite_models` — **not omp**: the
  native Zed Agent's model selector (zed.dev-hosted models, billed through
  Zed Pro). Hand-maintained: one zed.dev counterpart per omp cycle model, pinned
  at the top of the selector and cycled with `alt-tab`. It pins, it doesn't
  filter (Zed has no hide/allowlist setting). Repeated in prose in
  `docs/zed.md` → "Zed Agent's model list" (with Zed prices and the
  Zed-vs-OpenRouter generation gaps). See
  [Native Zed Agent favorites](DECISIONS.md#native-zed-agent-favorites).
- `omp/.omp/agent/extensions/cycle-model-picker.ts` — `Alt+O` picker over
  `cycleOrder`.
- Docs repeating ids: `docs/omp.md` (the `modelRoles` block under "Providers
  and model roles", Advisor paragraph, Per-call model paragraph, the Auto
  Code removal note, the Plan mode section's `plan` role and thinking finding,
  "ACP-specific catches" under "Zed — ACP thread or terminal"), `README.md`
  (omp setup section) and `omp/.omp/agent/AGENTS.md` (names
  `anthropic/claude-fable-5-2` and `claude-sonnet-5-5`). `plans/` files are
  historical decision records; do not rewrite their model ids.
- Tests `omp/tests/*.sh` use fixture ids; touch them only when behavior
  changes, not on every model bump.
- Other repo docs/files that name omp models: `docs/zed.md` (Zed favorites
  paragraph with prices, and the Zed picker-scope paragraph quoting a
  pattern), root `AGENTS.md`/`CLAUDE.md` (the "Keeping omp models in sync"
  pointer to this skill; update both if its wording changes), and
  `omp/.omp/agent/RULES.md` (the unavailable-model rule, no ids).
  `docs/omp.md` also keeps illustrative, non-setup-owned model examples (the
  GPT-5.6 Sol/Pro/batch naming table and its OpenRouter links, and an
  `anthropic/claude-sonnet-4-5` credential example): refresh them only when
  they mislead, not every round.

### Live state outside the repo (machine-local)

- `~/.omp/agent/config.yml` — `modelRoles`, `modelTags` and
  `retry.fallbackChains` are seeded fill-in-only, so they must be updated by
  hand (Policy above), except the migrations in `setup-settings.sh` (retired
  provider cleanup, the `fable` id, the `web` entries). `cycleOrder` and
  `task.perCallModelAllow` are forced/derived on every run. `advisor.*` is
  not seeded (the `advisor` role is in `modelRoles`).
- `~/.omp/agent/models.yml` — written by `setup-model-labels.sh` (`(sub)`
  `modelOverrides`). An old `openrouter/auto-code` override from the removed
  router script is harmless and can be deleted.
- `~/.omp/agent/zed-models.yml` — generated Zed picker scope; never hand-edit.
- `~/.omp/agent/models.db` — omp's own catalog cache (read-only evidence;
  `omp models find` is the supported way to query it).

### Other tools with their own model pins (not driven by this skill)

Not omp, not covered by `setup-settings.sh`; they do not follow role edits.
Check them during a round and **flag** newer generations to the user rather
than editing silently, since each tool has its own catalog and price list.

- `pi/setup-settings.sh` `defaultModel` (pi's default; also `docs/pi.md`
  mentions `pi-btw` taking an `openrouter/<model-id>` and the footer example
  in `pi/.pi/agent/extensions/claude-footer.ts`).
- `opencode/.config/opencode/opencode.json` `model` and `small_model`
  (OpenRouter ids).
- `claude/.claude/settings.json` `model` (a Claude Code alias such as
  `sonnet`, not an id; the alias tracks Anthropic's newest of that tier).
- `zed/.config/zed/settings.json`: `agent.default_model` and
  `agent_servers.omp.default_config_options.model` are the user's dropdown
  picks and churn (out of scope); `agent.favorite_models` is covered above.
- Nothing in `nvim/`, `cursor/`, `herdr/`, `zellij/`, `ghostty/` or `macos/`
  pins a model id (2026-11 audit); `nvim/` and `claude/statusline-command.sh`
  only display or match agent/model names from other tools.

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
- **OpenRouter routers (Auto Code) only route among models OpenRouter has
  measured, and omp hides what ran.** Before adding a router role, send one
  request per pool model with the pool narrowed to that model (`plugins:
  [{"id": "auto-router", "allowed_models": [<id>]}]`): "No measured models
  satisfy the Auto Code policy" or "No router pool model is routable" means it
  is never picked. omp records and shows the requested router id, not the
  routed model (that is only in the response `model` field and
  `/api/v1/generation?id=<gen-id>`).
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
  flag it or add fallback chains for it. Unverified and not worth chasing:
  whether fallback chains honour the `zed-models.yml` `enabledModels` scope.
- **Zed has two model pickers; don't mix them up.** omp's dropdown in an omp
  thread is scoped by `zed-models.yml` (OpenRouter + subscriptions, newest
  generations). The native Zed Agent's selector lists Zed's hosted models,
  and `agent.favorite_models` only pins entries there. Neither affects the
  other (`alt-tab` and favorites never reach omp's dropdown). Zed's
  `agent.default_model` is rewritten on every pick, so it's out of scope like
  omp's `default_config_options.model`.
- **zed.dev lags OpenRouter.** As of 2026-11 (Zed 1.29.2) Zed hosts Fable
  5.2 (same as OpenRouter), Haiku 4.5 (5.5), GPT-5.6 Terra (6.1 Terra), and
  no Gemini 4 Neon, Carbon or Hydrogen. Only pin what https://zed.dev/docs/ai/models lists; never
  copy omp's newest ids into `favorite_models`. Zed ids follow neither omp
  form exactly: Claude is dashed (`claude-opus-5-5`), GPT and Gemini are
  dotted (`gpt-6.1-sol`, `gemini-3.5-flash`), provider `zed.dev`. Verify an
  id with `strings /Applications/Zed.app/Contents/MacOS/zed | grep -o
  '<id>'`. Models served only from Zed's cloud list (`gemini-4-argon` in
  2026-11) aren't in the binary; have the user star the model in the picker
  so Zed writes the real id, or flag it as unverified.

## Procedure

**Sweep first (once per round).** Compare this hit list from the repo root
against "Where model identity lives" and add any new file to this skill:

```bash
grep -rnEil 'gpt-[0-9]|claude-(opus|sonnet|haiku|fable)|gemini-[0-9]|openrouter/|anthropic/|modelRoles|enabledModels|favorite_models|perCallModel|cycleOrder' \
  --exclude-dir=.git --exclude-dir=plans . | sort
```

Also run `omp config get` on keys that can hold model ids but are unset here
(`task.agentModelOverrides`, a global `enabledModels`; `modelProviderOrder`
holds provider names) before assuming they are empty.

1. **Discover.** For each provider (`openrouter`, `anthropic`; `openai-codex`
   only as a quick check, see Gotchas) run `omp models find <family> --json`
   for every family in the cycle, `*-sub`, `neon`, `fable`, and the
   fallback chains. Find the newest
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
   see Policy; chains: `$defaults + .` never updates an existing key, so
   delete the old key and add the new one together, e.g. `omp config set
   retry.fallbackChains "$(omp config get retry.fallbackChains --json | jq -c
   '.value | del(.["<old primary id>"]) + {"<new primary id>": [...]}')"`).
   **Fallback chains are part of every round**, not an afterthought: re-key
   each OpenAI chain to its primary role's current OpenRouter id (the key is
   the exact model id, so a role bump to a new generation leaves its chain
   dead; the Fable chain's key stays `anthropic/claude-fable-5-2`), and point every step at the newest
   generation of that tier (`openai-codex/*`, and
   `openrouter/anthropic/claude-opus-*` for Fable), the same rule as the
   roles. The Codex `oa-*` roles follow the same generations. Compare the
   live chains against `DEFAULT_FALLBACK_CHAINS` with `diff <(omp config get
   retry.fallbackChains --json | jq -S '.value|del(.web)') <(...)`.
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
   check, for each omp cycle model, whether Zed hosts a newer counterpart than
   the one in `agent.favorite_models` (and whether Gemini 4 Neon is hosted
   yet, to replace Argon; a standing TODO in that file). The list holds exactly
   one zed.dev model per cycle model; add or drop a favorite when the cycle
   changes. Update the list and the `docs/zed.md` paragraph (models, prices,
   generation gaps) together. Not driven by `setup-settings.sh`; nothing to
   re-run, and Zed reloads settings live.
7. **Docs and tests.** Update every doc listed above in the same change; run
   `for t in omp/tests/*.sh; do bash "$t"; done`.
8. **Do not commit unless asked**; other uncommitted changes in the tree
   (e.g. `claude/.claude/settings.json`) are the user's.
9. **Record the decision.** If you changed a role or a rule for a non-obvious
   reason, add or rewrite its entry in [DECISIONS.md](DECISIONS.md), so the
   next round can tell a deliberate choice from drift. The round's id changes
   go in the commit message, not there.

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

Expect the `(sub)` rows (`anthropic/*`) and the OpenRouter rows, sorted by
provider, so an unlabelled `google/gemini-4-neon` lands right after the
Anthropic rows. Check by content, not row count (it shifts as roles change):
every cycle and `*-sub` model is present and no retired model (DeepSeek, Kimi,
GLM, GPT-6 Luna) is listed. Expect no Codex rows: no non-`oa-` role names a
Codex-catalog id since the `luna` role (which pulled in
`openai-codex/gpt-6-luna`) was dropped. Codex `gpt-5.6-terra` and OpenRouter
`gpt-5.6-sol`/`gpt-5.6-terra` should NOT appear; if they do, the `oa-` exclusion in
`setup-zed-models.sh` was lost. Known extras from the id-wide patterns: a
second, unlabelled "Gemini 4 Neon" (direct `google/gemini-4-neon`). Report
new or surprising extras; do not hand-edit `zed-models.yml` (it is generated).

The probe needs `OPENROUTER_API_KEY` in its environment, as Zed's omp process
has it. Without it (seen from an eval kernel, 2026-11-16) `session/new`
lists only a handful of rows (`anthropic/*`, Codex and
`google/gemini-4-neon`) and starts on a subscription model; that is a probe
artifact, not drift.

## Flag to the user

Always surface these in your final report, even if you resolved them:

- A newer version of a model already in a role, or a new family worth a
  preset (and which role you would put it in).
- A model in a role, the cycle or a fallback chain that is
  deprecated, renamed, repriced or gone from the catalog.
- Pins in other tools that are behind the newest generation (`pi`,
  `opencode`; see "Other tools with their own model pins"), and any new file
  the Procedure's sweep turned up that this skill did not list.
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
  favorite Zed no longer hosts, Gemini 4 Neon becoming available on Zed,
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
receive); keep all three wordings consistent when changing the rule. Not
automated (no `before_subagent_spawn` hook): per-call selection has no
fallback by design. Revisit if omp adds per-call fallback chains, or
substitutions are often wrong.
