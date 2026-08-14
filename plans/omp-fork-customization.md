# omp fork — build from source to customize past the extension API

> **Status (2026-08-13, updated same day):** mostly defused. The motivating
> feature (candidate 1 below) shipped as a plain extension after discovering
> the segment registry is live-mutable in-process — no fork needed. What
> remains is the upstream-PR angle (a PR-ready patch already sits
> uncommitted in the clone) and the smaller candidates. Kept for the next
> time the extension API says "no", and for the registry-mutation caveats.

## Background — the wall this keeps hitting

Porting the Claude Code statusline's context-growth bars to omp (2026-08-13)
first landed as `omp/.omp/agent/extensions/turn-count.ts` rendering through
`ctx.ui.setStatus` on the hook-status row — one line *above* the native
status line, not in it — because the extension surface looked closed:

- **The segment registry has no registration API.** `SEGMENTS` in
  `packages/coding-agent/src/modes/components/status-line/segments.ts` is a
  fixed record with no turn segment and no `custom`/`extension` id.
- **`setFooter` is a stub.** Wired to `() => {}` in every mode (verified
  through v17.3.2), so whole-footer replacement (pi's escape hatch, used by
  `claude-footer.ts`) silently does nothing in omp.

## The breakthrough — the registry is mutable, no fork required

Re-auditing the same day found the wall has a door:

- The package root barrel (`index.ts` → `modes/components` → `status-line`)
  **exports the live `SEGMENTS` record**, and extensions in the compiled
  binary get the *host's module instance*, not a copy (proved by patching
  `model`'s render from a `-e` probe extension and seeing the marker in the
  editor's top border).
- `renderSegment` looks ids up in the record **at render time**, and unknown
  ids return `{visible: false}` instead of erroring.
- The settings schema validates `statusLine.leftSegments` only as `array` —
  no id enum — so `omp config set` accepts a made-up id.

So `turn-count.ts` now registers a `turn_count` segment in the live record
and `setup-settings.sh` appends the id to `leftSegments`; `#N ▂▅█` renders
inside the native line. Caveats that keep this doc alive:

- It leans on an *unblessed* invariant (root barrel keeps re-exporting the
  registry; record stays unfrozen). The extension degrades to the
  hook-status row if the export disappears.
- `theme.fg` uses private fields — call it as a method; an extracted unbound
  reference throws at render time (cost one debugging round). And `theme`
  itself is a reassigned module `var` (the OSC-11 auto-switcher swaps the
  whole object), so it must be re-read per render, never captured.
- A segment renderer that throws escapes the TUI render loop unhandled —
  there's no per-segment catch anywhere on the paint path — so the
  extension's render body guards itself and returns invisible on error.

Bonus discovery: `~/src/oh-my-pi` already carries an **uncommitted, PR-ready
native patch** (a `turn_count` segment + memoized branch-walk in
`component.ts`, `SegmentContext.turnCount`, schema id, and tests) from an
earlier prototype — exactly what option 1 below would submit.

The two cosmetic gaps `docs/omp.md` accepts remain fork/PR-only: baked
context-color thresholds (90/70/50 + absolute-token floors vs Claude's
70/90) and fixed `cache_hit`/`cost` formats — those live inside built-in
segment closures, not the registry. See
[omp-integration.md](omp-integration.md) → "Native status line over porting
`claude-footer.ts`" for the 2026-08-12 registry audit this supersedes.

## The avenue

omp is source-available and already cloned at `~/src/oh-my-pi` (upstream
`can1357/oh-my-pi`; bazel output symlinks show it has been built on this
machine). The idea: build from source and carry small local patches — a
personal fork — for features the extension API can't reach. Motivating
candidates, roughly in order of want:

1. ~~A `turns` segment so `#N ▂▅█` sits *in* the native status line.~~
   **Done without a fork** — see the breakthrough above. The remaining play
   here is upstreaming the clone's native patch (or an
   extension-registration API) so it stops depending on an unblessed export.
2. **Configurable status-line thresholds/formats** — close the two accepted
   gaps (context color tiers, `CH59%`-style compact cache/cost) instead of
   accepting them.
3. **A working `setFooter`** — restores pi-parity as the general escape
   hatch, making 2 unnecessary for anyone willing to own a footer port.

## Options ladder (cheapest first)

1. **Upstream PRs.** An extension-registered-segment API or a `status`
   segment is a feature upstream plausibly wants; `setFooter` is an existing
   stub they may intend to fill. Zero maintenance if accepted. Slow, and the
   feature shape is negotiated, not owned. Check `CONTRIBUTING.md` and open
   issues in the clone before building anything.
2. **Patch-carrying fork.** Keep `~/src/oh-my-pi` on a branch of small,
   rebase-friendly commits; rebuild on upstream releases. Full control,
   but this repo then owns a build pipeline (bun + bazel workspace, Rust
   crates, a ~117 MB compiled binary) and gives up the
   `brew upgrade omp` designated-owner convention (README's install story
   and the Brewfile both assume the tap). Upstream moves fast — 17.x has
   been cutting releases continuously — so unrebased patches rot quickly.
3. **Hybrid.** Fork only long enough to prototype the segment, then submit
   it upstream with the prototype as the PR. Most likely path if 1 stalls.

## To answer before committing to 2

- Does `bun`/bazel produce a working binary from the clone today, and how
  long does a clean build take? (`bazel-*` symlinks say it once worked.)
- How does a self-built binary install beside the brew one — replace
  `/opt/homebrew/bin/omp`, or a separate name/profile while stock omp stays
  the daily driver?
- Where do local patches live so they survive machine loss — a GitHub fork,
  or a patch series tracked in this repo?
- Is the win worth it at all, now that the inline segment works via the
  registry mutation — i.e. is de-risking that unblessed invariant (plus
  candidates 2–3) enough to justify owning a build?

## Cross-references

- [omp-integration.md](omp-integration.md) — the shipped integration and the
  "native status line, not a port" decision this would partially revisit.
- `docs/omp.md` → "Status line and theme" — documents the registry-mutation
  mechanism, the `turn-count.ts` segment, and the two accepted gaps.
- `claude/.claude/statusline-command.sh` — the bars' reference
  implementation.
