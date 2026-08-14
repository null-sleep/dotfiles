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
  **Re-confirmed 2026-08-12** after auditing omp 17.2.15's segment registry
  for the two things the footer looked to be missing:
  - *Thinking effort was never missing.* The `model` segment renders it when
    `segmentOptions.model.showThinkingLevel !== false` — opt-out, so it was
    already showing ` · ◑ med`. Now pinned `true` so the forced block owns it
    rather than a default. `compactThinkingLevel` picks glyph-on-model vs
    suffix.
  - *Turn count is unreachable natively.* The registry (`pi`, `model`,
    `mode`, `path`, `git`, `pr`, `subagents`, `token_*`, `cost`,
    `context_*`, `time*`, `session`, `hostname`, `cache_*`, `session_name`,
    `usage`, `collab`) has no turn segment — `session` is the session-ID
    prefix — and extensions can't register one; `setFooter` replaces the
    whole footer or nothing. So parity here *is* the port, which is what
    this decision rejects. **Corrected 2026-08-13:** "extensions can't
    register one" turned out false in practice — the package root exports
    the live `SEGMENTS` record, ids are looked up at render time, and the
    config schema doesn't validate them, so the stowed `turn-count.ts` now
    registers a `turn_count` segment inline. Details and caveats in
    [omp-fork-customization.md](omp-fork-customization.md).
  - *Thresholds and formats aren't configurable.* Context color is baked
    (error ≥90%, purple ≥70%, warning ≥50%, plus 500k/270k/150k token
    floors) against Claude's two-tier 70/90; `cache_hit` is `59.43%` at
    fixed color, `cost` always 2dp. Cosmetic, and the port would trade them
    for omp's own extras (advisor status, fast-mode and auto-compact icons,
    premium/sub indicators).
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
  Post-review correction: omp *sessions* never hit this — launched in
  `$HOME` without `--allow-home`, omp auto-switches its cwd to a temp dir,
  so the shadow is real only for `omp config` reads from `$HOME` (and
  `--allow-home` sessions). Options considered: (a) drop the Claude theme
  key — breaks Claude Code's themed CLI; (b) ship a custom
  `~/.omp/agent/themes/custom:active.json` shim — would duplicate a built-in
  palette by hand and drift, and built-in names beat custom files anyway,
  making the shim's behavior name-dependent; (c) accept it. Chose (c);
  revisit if upstream scopes the claude settings import.
  (`setup-settings.sh` originally warned on the shadow; the warning was a
  guaranteed false positive once the script itself ran from `$HOME`, so it
  now runs from an empty temp dir and the warning is gone.)
- **Web search is repo-owned policy**: order `perplexity` → `public`
  (keyless tiers), `anthropic` excluded even as a fallback — consistent
  with keeping the Anthropic OAuth surface out of third-party harness use.
- **Coexistence rules with pi.** Never export `PI_CODING_AGENT_DIR` or
  `PI_CONFIG_DIR` globally — both agents obey them (use `omp --profile` for
  isolation). Benign sharing is kept: `PI_HARDWARE_CURSOR` (JediTerm export
  covers omp too) and `OPENROUTER_API_KEY` — accepting that OpenRouter
  per-key spend reporting mixes pi + omp.

## TODO

- [ ] **Evaluate omp's long-term memory backends (Hindsight et al.).** omp's
  memory system (`retain`/`recall`/`reflect`/`learn`, off by default) is
  pluggable via `memory.backend`: `local`, Hindsight, or Mnemopi — plus a
  per-session mental-model compression that loads on the next session's
  first turn. Questions to answer before enabling one: what each backend
  actually stores and where (work-machine data residency for the fork!),
  local vs hosted, how project scoping works, whether `learn`-promoted
  skills collide with the stowed `~/.claude` skills omp also discovers, and
  what effective daily use looks like (when to `retain` vs rely on the
  auto mental model). Source: the omp clone's `docs/memory.md` +
  `docs/mnemosyne-memory-backend.md`, and `omp config list --json | jq`
  over the `memory.*` keys. If one earns its keep, seed the choice in
  `setup-settings.sh` and document it in `docs/omp.md`.
- [ ] **Revisit tracking omp settings in the repo.** `config.yml` can't be
  stowed — verified 2026-08-12 that `omp config set` saves via atomic rename
  (inode changes), so a stowed symlink would be silently replaced by a plain
  file on the first write, same failure mode that keeps pi's `settings.json`
  machine-local. Today the script *is* the tracked settings: promote a key
  into `setup-settings.sh`'s forced block to make it repo-owned. If more
  settings ever need tracking, the candidate design is a stowed **read-only
  `--config` overlay** (omp loads but never writes overlay files) — costs a
  wrapper/alias on every launch path (zsh, nvim's `sk/cli/omp.lua`, herdr)
  and makes overlaid keys silently win over `/settings` edits, which is why
  it wasn't done now.

## Out of scope

- **herdr integration** — no omp pane/preset wiring; revisit if omp becomes
  a daily driver.
- **pi-btw** — assessed as an accepted loss at integration time; later
  verification found omp 17.2.15 ships a built-in `/btw` (ephemeral side
  question, branchable), so nothing was actually lost. Documented in
  `docs/omp.md`, no setup needed.
