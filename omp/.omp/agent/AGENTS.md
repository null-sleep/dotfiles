# Global omp preferences

Stowed from the dotfiles repo (`omp/.omp/agent/AGENTS.md`); applies to every
project. Task subagents do not receive `AGENTS.md`, so anything they must obey
lives in `RULES.md` next to this file.

## Subagent model selection

The user chooses subagent models per call (`task.perCallModel`), either by
naming one ("use opus", "the sonnet sub model") or by leaving it to you.

- A bare name such as `sonnet`, `opus`, or `haiku` means the OpenRouter model.
  Exception: `fable` is subscription-only (OpenRouter Fable is hidden by the
  account's Zero Data Retention setting), so `fable` and `fable-sub` are the
  same model, `anthropic/claude-fable-5-2`. "sub" means the direct Anthropic
  subscription model (the `*-sub` roles).
  Map the user's words to the exact id from the approved-model listing in the
  task tool description, which shows each model's role name; ids are matched
  literally, and Anthropic's direct ids use dashes (`claude-sonnet-5-5`).
- Include a thinking level (`:low` ... `:max`) when it matters; without one the
  agent's own level is used.
- Per-call selection has no automatic fallback. This is a standing user
  preference that **overrides the task tool's own default ("requested model
  unavailable: stop and report; never substitute")**: when the requested model
  is unavailable (not approved, hidden by the account's Zero Data Retention
  setting, expired login, usage cap, or a typo) and the user did not require
  that exact model (benchmarks, A/B comparisons, "only on X"; then stop and
  report as usual), use your own judgement instead of stopping to ask:
  1. Pick the closest sensible substitute, preferring the same family on
     another provider (`sonnet-sub` -> OpenRouter `sonnet`; subscription Fable
     -> OpenRouter `opus`), then the nearest tier and cost among the approved
     models. Do not drop to something clearly weaker for work that needs
     quality, and keep the requested thinking level where supported.
  2. Spawn with it and finish the task.
  3. Say in one line in the final report which model you used instead and why.
- Model setup for this machine is maintained in the dotfiles repo; see its
  `omp-models-sync` skill when asked to update or audit models.

## Plan mode in Zed (ACP)

You cannot change your own model, and you cannot choose the plan-mode model
for the user. In a Zed (ACP) thread plan mode keeps the thread's model; only
the model dropdown decides, and `modelRoles.plan` is ignored there. So when
the user wants to plan on a particular model, tell them which exact dropdown
entry to pick, including the version and any `(sub)` suffix (for example
"Claude Opus 5.5 (sub)" versus "Claude Opus 5.5"), and do not offer a model
choice through `ask`: the answer would change nothing. Picking some models
resets the thinking level, so tell them to check it after switching.
