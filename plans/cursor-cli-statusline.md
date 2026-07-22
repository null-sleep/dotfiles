# Cursor CLI statusline (Claude parity, available fields)

> **Status:** design locked 2026-07-22 — not started.
> Mirrors the Claude Code statusline package shape (`claude/` +
> `setup-statusline.sh`), adapted to Cursor's thinner stdin payload.

## Goal

Give `cursor-agent` a custom status line above the prompt that looks and
feels like the Claude Code one for the fields Cursor actually provides:
model (+ param summary), git branch, context %, message-count sparkline.
No cost or rate-limit segments (absent from Cursor's payload).

## Background

Cursor CLI supports the same `statusLine.type = "command"` hook as Claude
Code (`~/.cursor/cli-config.json`). Spec: Cursor's built-in
`skills-cursor/statusline` skill; payload aligned with Claude's but thinner
— no `cost`, no `rate_limits`, no `worktree.branch`.

This repo already ships Claude's script at
`claude/.claude/statusline-command.sh` and injects it via
`claude/setup-statusline.sh`. Cursor gets the same packaging pattern.

## Decisions

1. **New `cursor/` stow package** (not under `zsh/` or a shared script).
   `stow --no-folding cursor` so a pre-existing `~/.cursor/` is never folded.
2. **Fork Claude's script**, don't share one binary. Cost/usage modes stay
   Claude-only; Cursor packaging stays independent.
3. **Feature set A** — model (+ `param_summary`), branch via
   `git -C "$cwd"`, ctx %, `#N` + growth sparkline from
   `context_window.current_usage`. No cost/rate-limit, no env-var mode.
4. **`cli-config.json` stays machine-local** (auth, model prefs). Only the
   `statusLine` block is injected by setup, same as Claude's `settings.json`.

## Layout

```
cursor/
  .stow-local-ignore              # setup-statusline.sh
  .cursor/
    statusline-command.sh         → ~/.cursor/statusline-command.sh
  setup-statusline.sh             # jq-inject into ~/.cursor/cli-config.json
```

Setup injects (idempotent; rewrite hardcoded `/Users/…` paths to `$HOME`):

```json
"statusLine": {
  "type": "command",
  "command": "bash $HOME/.cursor/statusline-command.sh"
}
```

## Script behavior

Single stdout line, ANSI colors matching Claude's non-cost mode:

`ModelName (params)  branch:foo  ctx:NN%  #N ▁▂▃…`

| Segment | Source |
|---|---|
| Model (cyan) | `model.display_name`; append `model.param_summary` when present |
| Branch | `git -C "$cwd" branch --show-current` (quiet fail if not a repo) |
| Context % | `context_window.used_percentage` — ≥90 red, ≥70 yellow, else dim |
| `#N` + bars | Per-`session_id` history in `~/.cache/cursor-statusline/`; same awk sparkline as Claude; skip while `current_usage` is null |

State dir: `${XDG_CACHE_HOME:-$HOME/.cache}/cursor-statusline` (not `/tmp`).
Same 7-day cleanup stamp pattern as Claude.

## Docs / bootstrap

- **README.md** `## Cursor CLI (cursor-agent)` — stow + setup steps, what's
  managed table, Verify-your-setup row.
- **Quick start** — per-tool, not the core stow cluster: extend step 7's
  "Claude Code setup scripts" pointer to also mention Cursor statusline
  setup (same pattern as Claude — install/stow first, then one-shot inject).
- **plans/README.md** — Active entry; check off when landed.
- **CLAUDE.md** (repo root) — add `cursor` to the stow-packages list.

## Out of scope

- Scraping Cursor usage/limits from cookies or web APIs.
- Themes for Cursor CLI (no Claude-style theme package yet).
- Sharing one script between Claude and Cursor.
- Stow-managing `cli-config.json` itself.

## Implementation plan

1. Add `cursor/.stow-local-ignore`, `cursor/.cursor/statusline-command.sh`
   (fork + adapt), `cursor/setup-statusline.sh` (mirror Claude's jq inject
   against `~/.cursor/cli-config.json`).
2. Update README (`## Cursor CLI`, Verify table, Contents if needed) and
   root `CLAUDE.md` stow-package list.
3. Smoke: mock JSON pipe into the script; run setup on this machine; open a
   `cursor-agent` session and confirm the line renders.
4. Mark this plan implemented; prune/check off in `plans/README.md`.

## Verification

```bash
# Unit-ish: script renders from mock payload
echo '{"session_id":"t","model":{"display_name":"Grok","param_summary":"High"},"cwd":"'"$PWD"'","context_window":{"used_percentage":42,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' \
  | bash cursor/.cursor/statusline-command.sh
# Expect: cyan model + (High), branch if in a git repo, ctx:42%, #1 (no bars yet)

stow --no-folding cursor
bash ~/src/dotfiles/cursor/setup-statusline.sh
# Re-run → "statusLine already configured"
jq -r '.statusLine.command' ~/.cursor/cli-config.json
# → bash $HOME/.cursor/statusline-command.sh
```

Manual: start `cursor-agent` (or `<leader>an` → cursor in nvim), send a
message — statusline shows model + ctx %; after a second message the
sparkline appears.
