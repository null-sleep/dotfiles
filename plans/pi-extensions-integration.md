# pi extensions integration — agent brief

> **Outcome (2026-08-08):** shipped as seven extensions, not six — pi-btw
> moved from the evaluate-only trio to adopted; pi-worktree and
> pi-caffeinate were evaluated and dropped. See README.md's `## pi` →
> `### Extensions` and `docs/pi.md` for what actually landed.

Not a design doc — this is a **prompt** meant to be handed to an agent (run it
via the `Agent` tool with `model: "fable"`, `subagent_type: "general-purpose"`)
to plan and implement adding a set of third-party `pi` extensions to this
repo's `pi/` stow package. Paste the fenced block below as the prompt
verbatim; it's self-contained.

Target extensions and why: [comparison discussion, 2026-08-08] surfaced
[narumiruna/pi-extensions](https://github.com/narumiruna/pi-extensions) as the
most substantive third-party extension collection for `pi`
(`@earendil-works/pi-coding-agent`, already installed and stowed in this repo
— see `## pi` in README.md). Six extensions to implement, three to evaluate.

---

```
You are planning and implementing an addition to a GNU Stow-managed dotfiles
repo at ~/src/dotfiles. Read ~/src/dotfiles/CLAUDE.md first — it has hard
requirements about updating README.md in the same change, heading/anchor
hygiene, and table-vs-bullet-list conventions. Follow it exactly.

## Background

This repo already has a `pi/` stow package for `pi` (`@earendil-works/pi-coding-agent`,
https://pi.dev — a minimal, TypeScript-extensible terminal coding agent). Before
anything else, read pi's own docs so you're working from the current spec, not
guesswork:
- https://pi.dev/docs/latest/quickstart
- https://pi.dev/docs/latest/settings — settings.json shape, global vs.
  project scope, precedence rules. Needed to get the `packages` array
  handling right in Phase 3.
- https://pi.dev/docs/latest/skills — Agent Skills as an alternative
  extension point. Some of the target extensions below might be better fits
  as a skill than a `pi.registerTool`-style extension; use this to judge that
  per group in Phase 1.

Then read the existing setup in this repo before touching anything:
- `pi/setup-settings.sh` — the pattern to mirror. It's a one-time, idempotent,
  **fill-in-only** script: it seeds `~/.pi/agent/settings.json` (which pi itself
  writes to, so it's deliberately NOT stowed) with repo-chosen defaults via
  `jq '$defaults * .'`, meaning it sets what's missing and never overwrites a
  value the user or pi has since changed. Re-running it is a no-op if already
  configured.
- `pi/.pi/agent/themes/*.json` — the one thing that IS stowed (`stow --no-folding pi`).
- The `## pi` section of README.md (search for it) — documents install, the
  settings.json split rationale, and the theme integration. `### What's managed`
  in that section is the canonical "what's tracked vs. machine-local" table —
  follow its style for any new table you add.
- pi's own extension mechanism: `~/.pi/agent/settings.json` has a `"packages"`
  array (e.g. `["npm:@scope/pkg@1.2.3", "git:github.com/user/repo"]`). Running
  `pi install npm:@scope/pkg` registers the entry AND installs it under
  `~/.pi/agent/npm/` — plain `npm install` does NOT register it with pi.
  `pi list` shows what's currently installed; `pi update --extensions` updates
  installed packages.

## Task

Add these six extensions from https://github.com/narumiruna/pi-extensions
(all published under the `@narumitw` npm scope) to this repo's managed pi
setup:

1. **pi-lsp** (`@narumitw/pi-lsp`) — language-server diagnostics and code
   actions across many languages.
2. **pi-subagents** (`@narumitw/pi-subagents`) — delegate isolated work to
   subagents (single/parallel/chained) — a feature pi's core deliberately omits.
3. **pi-plan-mode** (`@narumitw/pi-plan-mode`) — Codex-like read-only `/plan`
   collaboration before implementation.
4. **pi-github-pr** (`@narumitw/pi-github-pr`) — shows current-branch PR
   checks/reviews/comments via the authenticated `gh` CLI.
5. **pi-usage** (`@narumitw/pi-usage`) — view current-account subscription
   limits or OpenRouter spend via `/usage`.
6. **pi-statusline** (`@narumitw/pi-statusline`) — TUI footer showing model,
   git state, context/tokens/cost/time.

Additionally, **evaluate** (research and recommend, don't install without an
explicit go-ahead from the user) these three — they're plausible fits but
less clearly justified:

7. **pi-worktree** (`@narumitw/pi-worktree`) — create/switch/remove/prune git
   worktrees, carrying the pi session along. NOTE: check
   `plans/git-worktree-nvim-plugin.md` in this repo first — there may already
   be worktree tooling here that this would duplicate or should integrate with.
8. **pi-caffeinate** (`@narumitw/pi-caffeinate`) — prevent system sleep during
   long-running prompts.
9. **pi-btw** (`@narumitw/pi-btw`) — quick `/btw` side question without
   polluting the main conversation.

## Process — do this in order

### Phase 1: parallel research, one subagent per group

Split the six required extensions into these groups and spawn one subagent
per group (plus one for the evaluate-only trio) to research in parallel.
Each subagent should fetch the actual package README/source (via `gh` or web
fetch — do not guess at config shape) and report back: what settings.json
entries or config files it needs, any one-time setup beyond `pi install`
(e.g. external CLI dependencies), whether it's stowable or must stay
machine-local (mirror the reasoning in `pi/setup-settings.sh` re: what pi
itself writes to), and any conflicts or overlaps with what's already in this
repo.

- **Group A — code intelligence**: pi-lsp alone. Specifically check whether
  it expects LSP binaries already on PATH (this repo's nvim config already
  installs/manages several language servers — the subagent should check
  whether pi-lsp can point at those same binaries or needs its own).
- **Group B — delegation & planning**: pi-subagents + pi-plan-mode together
  (both backport features pi's minimal core omits by design; likely share
  config shape or interact with each other).
- **Group C — status & git observability**: pi-github-pr + pi-usage +
  pi-statusline together (all read-only informational additions; check
  whether any expect `gh auth login` state — this machine already uses `gh`
  elsewhere, so probably fine, but verify. Also check pi-statusline doesn't
  assume `starship` in a way that conflicts with anything in this repo's
  ghostty/zsh prompt setup).
- **Group D — evaluate only**: pi-worktree, pi-caffeinate, pi-btw. Produce an
  adopt/skip recommendation with reasoning for each; do not plan
  implementation details unless the user says to proceed with one.

### Phase 2: synthesize, then ask the user questions

Merge the four groups' findings into one coherent plan. Before writing any
code or running any install commands, ask the user clarifying questions —
ask as many as you need, not just one round. For every question, give
background (what the extension actually does and why the question matters)
and a concrete example (a sample settings.json snippet, sample footer text,
sample command output) so the user can decide without reading source
themselves. At minimum cover:

- **Version pinning** — pin exact versions in the `packages` array
  (`npm:@narumitw/pi-lsp@1.4.0`, reproducible but needs manual bumps) vs.
  track latest (`npm:@narumitw/pi-lsp`, no version pin, drifts silently).
  Check how this repo pins versions elsewhere (e.g. opencode, cursor-agent in
  README.md) and present that as prior art.
- **pi-lsp language scope** — which languages' servers should it assume are
  already installed (point at nvim's) vs. install fresh itself? Show both
  options concretely.
- **pi-github-pr auth** — confirm `gh auth status` is already good on this
  machine (it's used elsewhere in this session already) rather than assuming.
- **pi-usage tracking target** — this repo's pi defaults to OpenRouter as
  provider (see `pi/setup-settings.sh`); confirm pi-usage should track
  OpenRouter spend rather than a subscription plan's limits.
- **pi-statusline fields** — which of model / git branch / context% /
  tokens / cost / time should show in the footer; show an example rendered
  footer line for a couple of configurations.
- **pi-subagents / pi-plan-mode defaults** — enabled globally by default, or
  opt-in per project? Any default keybindings to reserve or avoid clashing
  with pi's existing keybindings (see pi's `docs/keybindings.md` if present
  in the installed package).
- **The evaluate-only trio** — a direct yes/no per extension, with your
  Phase 1 recommendation and reasoning laid out first.

### Phase 3: implement

Once the user has answered:

- Write a new idempotent setup script (e.g. `pi/setup-extensions.sh`)
  mirroring `pi/setup-settings.sh`'s conventions: fill-in-only, safe to
  re-run, and — this is the hard requirement — it must **only install/setup
  extensions that aren't already present**. Check `~/.pi/agent/settings.json`'s
  `packages` array (via `jq`) for existing `npm:@narumitw/<name>` entries
  before calling `pi install` for that one; skip ones already there. It
  should run after `pi/setup-settings.sh` (pi and settings.json must already
  exist) — document that ordering both in the script's header comment and in
  README.md.
- Update the `## pi` section of README.md in the same change: what's
  installed, the install command(s), a bullet list (not a table — these are
  prose descriptions, not short uniform cells) of what each extension does,
  and update `## Contents` if you add a new anchor. Follow the anchor-link
  hygiene rule in CLAUDE.md for any heading with slashes/parens.
- Do not install anything or write to any machine's real `settings.json`
  until the plan from Phase 2 is confirmed by the user — treat `pi install`
  and settings.json writes as non-reversible-enough to warrant that pause.
- Commit directly to main when done (no branch/PR needed for a change this
  size in this repo), one commit per logical group is fine.

Stop and show the plan before implementing. Do not skip Phase 2's questions
even if you think you know the right defaults — the whole point of this
brief is to surface the decisions, not make them silently.
```
