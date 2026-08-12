# omp integration — design brief

> **Outcome (2026-08):** shipped as the `omp` stow package — `setup-settings.sh`
> plus one stowed extension (`nvim-notify.ts`). See README.md's `## omp` and
> `docs/omp.md` for what landed. This records the decisions and why.

## Background

[oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`) is can1357's
batteries-included fork of pi, run **alongside** pi, not replacing it. It
shares pi's extension API and most `PI_*` env vars but inverts the design:
everything this repo installs as pi extensions (plan mode, subagents, LSP,
statusline, PR status, usage) is built in, config is one YAML store driven
by `omp config`, and discovery providers read `.claude`/`.codex`/`.gemini`
config — so `CLAUDE.md` and `~/.claude` skills apply to omp for free.

## Decisions

- **brew (`can1357/tap/omp`) over npm/bun install.** omp ships as a single
  native binary with platform natives; the tap is upstream's primary channel
  and matches this repo's Brewfile-first convention. No node toolchain in
  the loop.
- **Native status line over porting `claude-footer.ts`.** omp's
  `statusLine.preset: custom` reproduces the Claude-shaped footer (model,
  ctx%, cache-hit left; cost right; no separators; transparent) with five
  `omp config set` calls. A TypeScript port would re-own rendering omp
  already does, for zero extra fidelity. Consequence: the look is *forced*
  by `setup-settings.sh` on re-run (repo-owned), unlike fill-in keys.
- **Built-in themes + auto slots over the `active.json` pattern.** pi gets
  repo-generated theme JSONs and a `theme`-script step because it has one
  active theme. omp holds a dark and a light slot (`dark-dracula` /
  `light-catppuccin`, both built-ins) and switches live on the terminal's
  OSC 11 background — so the repo's `theme` script deliberately has **no omp
  step**; Ghostty flips, omp follows.
- **No `@narumitw` extensions.** Plan mode, task subagents + Agent Hub,
  lsp/debug, PR status, and usage are native. Installing the pi extensions
  would duplicate (and race) built-ins.
- **`nvim-notify.ts` is the only stowed file** — the sidekick attention
  bridge port. Two event remaps vs the pi original: omp has no
  `agent_settled`, so done-detection is `agent_end` gated on
  `!willContinue && ctx.isIdle() && !ctx.hasPendingMessages()`; and omp task
  children run in-process (no subagent env marker), so `ctx.hasUI` is the
  per-event guard instead.
- **`config.yml` is not stowed; `setup-settings.sh` seeds it.** Same split
  as pi's `settings.json`: omp writes settings edits, migrations, and
  runtime state into it, so a stowed symlink would funnel machine state into
  the repo. Fill-in keys (`modelRoles.default` →
  `openrouter/anthropic/claude-sonnet-5`, `defaultThinkingLevel: medium`,
  `startup.quiet: true`) survive user changes; theme/status-line keys are
  forced.
- **The `$HOME` theme-shadowing quirk is left unworked-around.** With cwd
  exactly `$HOME`, omp's claude provider treats `~/.claude` as the project
  dir and `settings.json`'s `"theme": "custom:active"` shadows `theme.dark`.
  Options considered: (a) drop the Claude theme key — breaks Claude Code's
  themed CLI; (b) ship a custom `~/.omp/agent/themes/custom:active.json`
  shim — would duplicate a built-in palette by hand and drift, and built-in
  names beat custom files anyway, making the shim's behavior name-dependent;
  (c) accept it — omp is launched from project dirs in practice, and
  `setup-settings.sh` warns when it sees the shadowing. Chose (c); revisit
  if upstream scopes the claude settings import.
- **Coexistence rules with pi.** Never export `PI_CODING_AGENT_DIR` or
  `PI_CONFIG_DIR` globally — both agents obey them (use `omp --profile` for
  isolation). Benign sharing is kept: `PI_HARDWARE_CURSOR` (JediTerm export
  covers omp too) and `OPENROUTER_API_KEY` — accepting that OpenRouter
  per-key spend reporting mixes pi + omp.

## Out of scope

- **herdr integration** — no omp pane/preset wiring; revisit if omp becomes
  a daily driver.
- **pi-btw** — assessed as an accepted loss at integration time; later
  verification found omp 17.2.15 ships a built-in `/btw` (ephemeral side
  question, branchable), so nothing was actually lost. Documented in
  `docs/omp.md`, no setup needed.
