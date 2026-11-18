# omp: choosing the model for plan mode

Status: decision record (2026-11-16) with one wanted follow-up. For now:
option 1 below, keep the `plan` role on the model planned with most (today
`openrouter/anthropic/claude-opus-5.5:high`) and override per launch with
`--plan <id>`. **In Zed (ACP) none of that applies:** plan mode keeps the
thread's model, and the Zed model and thinking selectors pick the planning
model freely, per thread; see "ACP (Zed): plan on any model". **Wanted, not
built:** option 4, per-model plan commands (`/planopus`, `/planopussub`,
`/plansol`, ...) as a small extension for the terminal; see "Wanted: plan
commands". omp 18.20.2. Everything here was read from omp's docs and checked
with the throwaway runs listed under "Evidence"; nothing was built and no
config changed.

## Problem

Subagents take a model per call (`task.perCallModel`), so "spawn a scout on
opus sub" works. The question was whether plan mode can be steered the same
way ("plan with an opus model"), and what configuration exists for it.

## How plan mode picks its model

- Plan mode is a mode of the user's own session, entered with `/plan` or
  `Alt+Shift+P`. It is not a spawn, so the assistant cannot pass it a `model`.
- In the terminal (TUI), entering plan mode switches to the `modelRoles.plan`
  model and exiting switches back (`docs/omp.md` → Plan mode;
  `omp://models.md`). Zed (ACP) behaves differently; see "ACP (Zed): plan on
  any model".
- Assigning the `plan` role does not itself enter plan mode. Changing the role
  while plan mode is active reapplies the model at once.
- A role value may be a comma list, but omp takes the first available entry;
  it is not a per-session choice.

## Configuration surface (all of it)

| Method | Scope |
|---|---|
| `modelRoles.plan` (`omp config set modelRoles ...`) | persistent |
| `omp --plan <id>` or `PI_PLAN_MODEL` | one launch, any model/provider (`--plan` wins over the env var) |
| editing the role while plan mode is on | applies immediately, rewrites the stored role |
| `/models` session-only picker | changes the active model without rewriting roles; not tested with plan mode in the terminal |
| Zed (ACP) model + thinking selectors | per thread; in ACP plan mode ignores `modelRoles.plan`, so these choose the planning model (see below) |

No `plan.model` setting or per-invocation parameter exists in the docs.
`plan.enabled`, `plan.defaultOnStartup`, `plan.autosave`, `plan.autosaveDir`
are the only `plan.*` keys and none select a model.

Merge into the existing `modelRoles` object when editing it; `omp config set`
replaces the whole value.

## Execution target after approval

- The plan review overlay has a model slider of tiers; approval executes on the
  selected tier. It starts on `default` and follows the role cycle order.
- Extensions can answer the review with `ctx.resolvePlanReview(id, choice,
  { role })`.
- Headless `--plan-yolo` executes on `--plan-yolo-into <id-or-role>`, default
  the `smol` role (Haiku here), which is a weak implementer.
- `/prewalk` is a separate plan-then-handoff feature (`prewalk.from` defaults
  to `@default`, `prewalk.into` to `@smol`); not investigated further.

## ACP (Zed): plan on any model

In a Zed omp thread, Plan is a session mode next to the model and thinking
selectors, and plan mode does **not** switch to `modelRoles.plan`. So the
planning model is whatever the thread runs, chosen in the dropdown, at any
thinking level, per thread, with no role edit or launch flag. That is more
flexible than the terminal's fixed `plan` role and covers what option 4 wants,
without an extension.

Observed behaviour (probe under "Evidence"):

- Entering Plan keeps the current model and thinking level; a planning turn
  runs on it.
- Picking a model while in Plan takes effect at once.
- Leaving Plan keeps the picked model; nothing is restored. Switch back by
  hand before implementing if you want a different implementer.
- Changing the model can reset thinking, depending on the model (probed
  2026-11-16, thinking set to `high` before each switch): it dropped to
  `medium` on OpenRouter GPT-6.1 Sol, GPT-6.1 Terra and GPT-6 Luna, and held at
  `high` on Claude Opus and Sonnet (OpenRouter and subscription) and on Codex
  GPT-5.6 Terra. Cause unknown, so check thinking after picking the model and
  set it again if needed.
- Only models in the Zed scope (`~/.omp/agent/zed-models.yml`, generated from
  `modelRoles`) are selectable; anything else errors `Unknown ACP model`.
- This is omp's dropdown, not the native Zed Agent's selector. Zed's
  `agent.favorite_models` (pinned zed.dev models) and `alt-tab` don't reach
  it, so the native Agent's favorites play no part in choosing omp's planning
  model.

Workflow: switch to Plan, pick the model, set thinking, prompt; after
approving the plan, pick the implementation model.

Not tested in ACP: how the plan-approval review and its execution target are
presented in Zed (only the session file was read: approval logged
`mode_change` to `none` and kept the model); who made the model change to
`anthropic/claude-sonnet-5-5` in the live thread (the approval step did not:
the next turn still ran on Codex Terra with no `model_change`, and the switch
landed mid-way through a turn the user started, so a dropdown pick is likely
but unproven); which thinking level the planning turns ran at; and whether
plan mode leaves the model alone because of the ACP host or deliberately (the
docs do not say).

Duplicate-name hazard (fixed 2026-11-16): the Zed picker listed Codex
`GPT-5.6 Terra (sub)`, OpenRouter `GPT-5.6 Terra` and OpenRouter `GPT-6.1 Terra`
together (the first two were pulled in by the `oa-*` roles' ids through the
`*/*<id>` patterns in `zed-models.yml`), and the live thread ended up on the
Codex one. `setup-zed-models.sh` now skips the `oa-*` roles, so those rows are
gone from the picker (22 to 19 rows). The `(sub)` suffix from
`omp/setup-model-labels.sh` still tells the intended duplicates apart
(Anthropic subscription vs OpenRouter Claude). Revisit with a Codex
subscription; see "Zed picker scope" in the skill's `DECISIONS.md`.

## Evidence

All runs in a throwaway directory under `$TMPDIR` (nothing in the repo
touched), session files read from `~/.omp/agent/sessions/`.

- **Interactive works.** `omp --plan anthropic/claude-opus-5-5:low`, then
  `/plan <prompt>`, driven with `expect`. The session recorded a
  `model_change` to `anthropic/claude-opus-5-5` (marked `temporary`) at the
  `mode_change` to `plan`, and the planning turns ran on it; the session had
  started on `gpt-6.1-terra`.
- **Headless does not apply the plan model.** `omp -p --plan-yolo --plan
  anthropic/claude-opus-5-5:low`, the same with `PI_PLAN_MODEL`, and the same
  with no flag (role only) all planned on `gpt-6.1-terra` (the default) and
  then switched to the `--plan-yolo-into` model. `omp -p "/plan ..."` with or
  without `--plan` ran on the default and never entered plan mode (no
  `plan-mode-context`). Cause not investigated, so it is unknown whether this
  is a bug or intended. The execution target (`--plan-yolo-into`) did apply.
- **ACP ignores the plan role; the thread's model plans.** `omp acp
  --approval-mode yolo --config ~/.omp/agent/zed-models.yml` (Zed's entry)
  driven over stdio JSON-RPC, 2026-11-16: `session/new` started on
  `openrouter/openai/gpt-6.1-terra` at `high`; `session/set_mode` `plan`
  kept Terra/`high`, and a prompt in plan mode was answered by
  `openai/gpt-6.1-terra` (session file), not the `plan` role's Opus;
  `session/set_config_option` `model` = `openrouter/openai/gpt-6.1-sol`
  switched at once (thinking dropped to `medium`); `set_mode` `default` kept
  Sol. Probe pitfall: the eval kernel's environment lacked
  `OPENROUTER_API_KEY`, so the first runs listed only `anthropic/*` and
  `openai-codex/*` models; Zed's process has the key. Pass it when repeating
  the probe.
- **Live Zed thread confirms it (2026-11-16, times UTC; local EST is five
  hours earlier).** A real plan was written in a Zed omp thread (Plan mode,
  session file `~/.omp/agent/sessions/-src-dotfiles/`). The thread's model was
  switched in Zed's dropdown to `openai-codex/gpt-5.6-terra` (`model_change`
  at 02:24:12) and the three planning turns (02:24:34, 02:25:09, 02:25:12)
  ran on it (assistant messages: provider `openai-codex`, model
  `gpt-5.6-terra`), not on the `plan` role's OpenRouter Opus. The agent had
  offered the OpenRouter `gpt-6.1-terra` in a form (answer returned 02:24:48),
  but that answer controls nothing in ACP: only the Zed selector decides, so
  say which entry to select instead of asking the agent. Approval logged
  `mode_change` to `none` at 02:25:50 and the next turn (02:25:53) still ran on
  Codex Terra, so leaving Plan kept the model. At 02:26:21 the model changed
  to `anthropic/claude-sonnet-5-5` in the middle of a turn the user started at
  02:26:02, which points to a dropdown pick, though that is unproven. Thinking
  level during the plan was not checked (the session file logs thinking only
  at start).
- **Not tested:** the session-only picker during plan mode in the terminal;
  the review overlay's tier slider; whether a per-call subagent `model` works
  for subagents spawned during planning. The docs say plan-mode subagents run
  with the same `effectiveAgent` used for model and thinking overrides, with
  a read-only toolset (`read`, `grep`, `glob`, `web_search`) and no child
  spawns (`omp://task-agent-discovery.md` → Plan mode behavior).

## Options considered

1. **Chosen:** keep `plan` on the model planned with most and use
   `--plan <id>` for the odd launch. Zero machinery. The role is already
   `openrouter/anthropic/claude-opus-5.5:high` and is not in the cycle or the
   per-call allowlist (it is a role for plan mode itself).
2. Set `plan` to the subscription Opus (`anthropic/claude-opus-5-5:high`).
   Same effect with a different billing path; not chosen because OpenRouter
   Opus is already the default planning model and the user did not ask for
   the switch. Revisit if subscription limits make that preferable.
3. Pick the model in the selector after entering plan mode. **Verified in Zed
   (ACP)** (it is ACP `session/set_config_option`, the same call Zed's dropdown
   makes), where it is the way to choose because plan mode does not switch
   models there. The terminal's `/models` session-only picker during plan mode
   is not verified; in the terminal plan mode switches to the `plan` role on
   entry.
4. **Wanted (see "Wanted: plan commands"):** an extension with one command per
   model (`/planopus`, `/planopussub`, `/plansol`, ...) that sets the plan
   model for this session and enters plan mode, using
   `ctx.sessionModes.set({ mode: "plan", action: "enter" })` (TUI sessions
   only; `undefined` in print, RPC, ACP, and subagents). Wanted by the user
   2026-11-16 ("I like being able to say /planopus or /planopussub or
   /plansol"). Real machinery to maintain and never tried, so not built yet.

## Wanted: plan commands

Goal: type `/planopus`, `/planopussub`, `/plansol` and so on to start plan
mode on a named model, with the same naming convention used for subagents
(bare name = OpenRouter, `sub` = direct Anthropic subscription), without
editing the `plan` role.

What the docs give an extension to build on (`omp://extensions.md`):

- `pi.registerCommand(name, { handler })` registers a slash command. The
  existing `omp/.omp/agent/extensions/cycle-model-picker.ts` shows the repo's
  pattern for extensions: read `cycleOrder` and `modelRoles` through
  `omp config get ... --json`, resolve a role with `ctx.models.resolve("@role")`,
  then `pi.setModel(...)` and `pi.setThinkingLevel(...)`.
- `ctx.sessionModes.set({ mode: "plan", action: "enter" })` enters plan mode;
  `action: "exit"` leaves it and restores tools and model. Refusals return
  `{ ok: false, code }` with `busy`, `conflict`, `disabled` or
  `invalid_request`. It submits no prompt, so the command passes any text on
  as a separate message.
- `resolvePlanReview(id, choice, { role })` and the `plan_review_requested`
  event's `tiers` cover the execution model after approval (separate from
  which model plans).

Design sketch, to confirm by building it:

1. Generate one command per role from config, not by hand: the `*-sub` roles
   and the cycle roles (`opus`, `opussub`/`opus-sub`, `sol`, `sonnet`, ...),
   so adding a role in `setup-settings.sh` adds a command. A command name
   cannot contain `-` safely, so decide the spelling (`/planopussub` vs
   `/plan-opus-sub`) when building.
2. The handler needs the plan model to be the target model. Two ways to try,
   neither verified: (a) set the active model with `pi.setModel` after
   entering plan mode, accepting that omp's own switch to `modelRoles.plan`
   happens first on entry; (b) change `modelRoles.plan` for the session only
   (a session-only write, not `omp config set`) before entering, relying on
   the doc line that changing the role while plan mode is active reapplies
   its model. Pick by testing which one sticks after exit.
3. Pass the rest of the command line as the planning prompt
   (`/planopus <prompt>` behaves like `/plan <prompt>` on that model).
4. Keep it TUI-only: `sessionModes` is `undefined` in print, RPC, ACP (Zed)
   and subagents, so the commands will not exist headless or in Zed. Zed does
   not need them (its mode and model selectors already do this; see "ACP
   (Zed): plan on any model"). The headless `--plan-yolo` gap stays open.
5. Stow it like the other extensions (`omp/.omp/agent/extensions/`), list it in
   `README.md` "What's managed" and in the `AGENTS.md`/`CLAUDE.md` stow-package
   sentence, and add the nvim-free smoke test used for the other omp scripts
   if a testable seam exists.

Open questions to answer first: whether (a) or (b) keeps the chosen model for
the whole planning session and restores the previous model on exit; whether
the `plan_review_requested` tier slider still starts on `default`; whether
a command registered from a stowed extension can take dynamic names at all
(otherwise a fixed list is generated by `setup-settings.sh`).

## Revisit if

- Planning with several different models becomes routine, or the user wants
  the commands above (they do): build the extension, or try the session-only
  picker first. In Zed this is already covered by the selectors.
- Headless planning matters (`--plan-yolo` in scripts): investigate why the
  plan role is not applied, or file it upstream.
- omp adds a per-call or per-session plan model setting.
- `--plan-yolo` becomes a regular workflow: set `--plan-yolo-into` explicitly
  instead of accepting the `smol` (Haiku) default.
