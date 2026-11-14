# Zed: per-preset omp agent entries

Status: parked (2026-11-14). Option 1, the scoped model dropdown, shipped
instead; see README → Zed and `docs/zed.md` → Agent panel. Revisit if most
new omp threads in Zed start on the same one or two non-default presets.

## Problem

omp's ACP mode sends Zed one `model` select listing the whole catalog (~870
models) plus separate `thinking` and `mode` selects. Zed has no cycle picker
for external agents: `agent.favorite_models` and `alt-tab`
(`agent::CycleFavoriteModels`) cover only Zed's own agent. omp's `Ctrl+P`
cycle and the `Alt+O` preset picker (`cycle-model-picker.ts`) are TUI-only.

## Option 1 (shipped): scoped model dropdown

`omp/setup-zed-models.sh` writes `~/.omp/agent/zed-models.yml` (one
`enabledModels` pattern per role model, every logged-in source; Bedrock
disabled), passed via `--config`. The dropdown drops to about 20 entries,
alphabetical rather than cycle order; Thinking stays a separate select, so a
role's thinking suffix isn't applied.

## Option 2: one agent entry per preset

Zed's new-thread menu (`+`, `cmd-alt-shift-n`) lists every `agent_servers`
entry, each a separate process launch. Extra omp entries that differ only by
`--model @<role>` turn that menu into a preset picker:

```jsonc
"omp · opus": {
    "type": "custom",
    "command": "/opt/homebrew/bin/omp",
    "args": ["acp", "--approval-mode", "yolo",
             "--config", "~/.omp/agent/zed-models.yml",
             "--model", "@opus"]
}
```

Verified 2026-11-14 against `omp acp` directly (not yet in the Zed UI):
`--model @opus` starts the session on `openrouter/anthropic/claude-opus-5.5`
with thinking `high` taken from the role, which the dropdown cannot do. It
composes with `--config` scoping.

Gains:

- A thread starts on the right model and thinking level in one choice.
- `agent: new external agent thread` takes an agent id, so each entry can
  get its own key binding in `zed/.config/zed/keymap.json`.

Costs:

- Start-time only; switching mid-thread is still the dropdown.
- Every entry is another row beside Claude, Codex, Cursor, and the rest.
  More than two to four becomes noise.
- Each entry is a distinct agent id, so Zed's thread import and history may
  split by preset. Untested.
- Hand-maintained: a renamed or removed role breaks its entry silently.

## If adopted

- Candidates: `omp · opus`, maybe `omp · sonnet`; `default` (Terra) is the
  existing `omp` entry.
- Add a check to `omp/setup-settings.sh` that every `--model @<role>` in
  `zed/.config/zed/settings.json` names a configured role.
- Test in Zed: start thread, confirm model and thinking, check history and
  import grouping.
- Document in README → Zed and `docs/zed.md` → Agent panel.
