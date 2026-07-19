# Go debug + test in Neovim (nvim-dap-go + neotest-golang)

> **Read together with [`go-targets-picker.md`](go-targets-picker.md).** That
> plan is a sub-issue of this one — it closed the run/targets gap this plan
> deliberately cut, replaced the `<leader>dR` mapping described here, and moved
> the dap-go setup into `golang.lua`. Neither doc tells the whole story alone,
> and the live continuation list for **both** plans (code fixes, checks left to
> run, deferred decisions) is its [Open items](go-targets-picker.md#open-items)
> section.

> **Status: SHIPPED (2026-07).** Go debugging (nvim-dap-go + delve) and testing
> (neotest-golang + gotestsum) are in and verified interactively. The *run*
> story this plan cut was later closed by the targets picker — not by go.nvim;
> see the note above. **One verification is still outstanding** — the `-test.run`
> state-leak check; see [Verification](#verification). Kept as the decision
> record: `dap_mode = 'manual'` and `outputMode = 'remote'` are both load-bearing
> and explained nowhere else.
> A 2026-07-13 post-ship review of the whole Go stack
> ([`go-targets-picker.md` → Post-ship review](go-targets-picker.md#post-ship-review))
> re-flagged that outstanding check (its finding 5) and recorded two drawbacks
> in this plan's scope: the pcall guards cover load-time failures only (a
> behavioral break in unpinned nvim-dap-go surfaces uncaught at debug time),
> and dap-ui closes only on `event_terminated`/`event_exited`, so a
> disconnect-ended Attach session can leave it open.

> **Scope narrowed (2026-07).** This plan originally proposed a *hybrid* that
> also added **ray-x/go.nvim** for a run/build/imports/code-action layer
> (`:GoRun`, `:GoBuild`, `:GoImports`, `:GoCodeAction`). That layer is **cut** —
> the goal is debugging and testing, and go.nvim is a large, opinionated plugin
> that has to be actively told not to touch LSP, DAP, and formatting to coexist
> with the existing gopls/conform setup. It stays recorded under
> [Alternatives](#alternatives-considered) as a clean follow-up if a real "run
> this program" story is ever wanted. Dropping it also removes the
> module-shadowing constraint that forced the `golang.lua` name.
>
> **Adversarially reviewed (2026-07).** A critic pass against upstream source
> caught a config-duplication bug, several wrong API facts, and a set of stale
> grep anchors this plan had missed. The findings are folded in below; the
> load-bearing one is [dap_mode = "manual"](#upstream-facts).
>
> **Shrunk to the decision-record core (2026-07-18).** The implementation
> narrative — the per-file change plan, the GUIDE restructure spec, the
> files-touched table, the commit list, and the already-passed verification
> steps — lives in git history (`git log --grep='Part-of: go debug'`). What
> remains is what a future edit needs: the upstream traps, what shipped and
> why, the outstanding checks, risks, and the alternatives record.

<a id="upstream-facts"></a>
## Upstream facts (source-verified, July 2026)

Every claim below was read out of upstream source, not docs prose — several
plausible-sounding assumptions turned out to be wrong.

- **nvim-dap-go** (`leoluz/nvim-dap-go`, module `dap-go`): `require('dap-go').setup()`
  registers `dap.adapters.go` (**a function**, not a table) plus seven
  configurations, named exactly: `Debug`, `Debug (Arguments)`,
  `Debug (Arguments & Build Flags)`, `Debug Package`, `Attach`, `Debug test`,
  `Debug test (go.mod)`. Needs nvim-dap loaded first. delve `path` defaults to
  `"dlv"` (resolved off `PATH`).
- **`dap-go.setup()` APPENDS, it does not replace.** `setup_go_configuration()`
  guards only `if dap.configurations.go == nil then dap.configurations.go = {} end`
  and then `table.insert`s all seven. Calling `setup()` twice yields fourteen
  configurations. Source:
  https://raw.githubusercontent.com/leoluz/nvim-dap-go/main/lua/dap-go.lua
- **neotest-golang re-calls `dap-go.setup()` on every debug run** — once in
  `setup_debugging()`, and once more from a
  `dap.listeners.after.event_terminated["neotest-golang-debug"]` listener that
  restores the original opts. Combined with the append behavior above, the
  default `dap_mode = "dap-go"` means **every debugged test permanently adds 14
  entries to the `<F5>` config picker.** This is the bug that shaped the design.
  Source: `.../features/dap/dap_go.lua`
- **`dap_mode = "manual"`** makes neotest-golang build its own DAP config from
  `dap_manual_config` and **never call `dap-go.setup()`**. It injects `program`
  (the test path), `args` (`-test.run <regex>`), and `cwd`; the user supplies
  `name`, `type`, `request` (and `mode`, which delve needs). Source:
  `.../features/dap/dap_manual.lua`
- **neotest-golang defaults** (`lua/neotest-golang/options.lua`): `runner = "go"`,
  `go_test_args = { "-v", "-race", "-count=1" }`, `dap_mode = "dap-go"`,
  `dap_manual_config = {}`. `-race` needs cgo + a C compiler (Xcode CLT covers
  it). It publishes real `v2.x` tags (latest `v2.9.0`), so
  `vim.version.range('^2')` resolves. **nvim-dap-go has zero tags** — unpinned is
  the only option there.
- **A bare `require('neotest-golang')` is a valid adapter.** Its `init.lua`
  returns the adapter table with a `__call` metamethod that only forwards opts.
  The call form is needed *because we pass options*, not because a bare table
  "misbehaves" (an earlier draft of this plan claimed that; it was wrong, and
  GUIDE.md's existing recipe showing the bare form is correct).
- **v2+ requires the Go parser from nvim-treesitter's `main` branch** — already
  satisfied: `plugins.lua:8` pins `version = 'main'` and lists `go` in
  `ensure_installed`.
- **Mason packages**: `delve` (exe `dlv`) and `gotestsum` — both correct, and
  both **source-built via `go install`**, so they hit exactly the failure mode
  README's Mason callout (README:194-201) already warns about. The Go toolchain
  is already a documented prerequisite. Mason prepends its `bin/` to `PATH`, so
  a bare `dlv` resolves.
- **gotestsum** is optional but strongly recommended: plain `go test -json`
  interleaves test JSON with program stdout, which corrupts neotest's parsing.

---

<a id="what-actually-shipped"></a>
## What actually shipped (2026-07)

The shape: two `vim.pack` plugins (nvim-dap-go unpinned — no tags exist;
neotest-golang pinned `^2`), Mason-installed `delve` + `gotestsum`,
`require('dap-go').setup()` called **exactly once** at startup (originally in
`debugging.lua`; since moved into `golang.lua` by the follow-up plan), and the
neotest-golang adapter registered in `testing.lua` with `runner = 'gotestsum'`,
`dap_mode = 'manual'`, and a `dap_manual_config` supplying
`{ name, type = 'go', request = 'launch', mode = 'test' }` — neotest-golang
injects `program`/`args`/`cwd` itself. GUIDE.md was restructured to give the
generic engines their own `## Debugging` / `## Testing` sections plus a `## Go`
section. Deviations from the plan, all deliberate:

- **Two bugs caught by a post-implementation review**, fixed in a follow-up
  commit — both were live defects in the first cut:
  - `dap_manual_config` had been written as a **table literal**. neotest-golang
    mutates what it gets back (sets `.program`, appends `-test.run <regex>` to
    `.args`), so the literal was one shared table and each `<leader>nd` appended
    another filter to it. A run with no regex would inherit the stale filter and
    silently debug the *previous* test. It is now a **function returning a fresh
    table** (upstream's type is `table|fun(): table`, and it calls it).
  - **`outputMode = 'remote'` was missing.** dap-go sets it on all seven of its
    own configs; delve defaults to local output mode, which a detached server
    adapter can't forward — so a debugged Go test emitted no `t.Log`/`println`
    output at all.
- **Both Go plugin loads are `pcall`-guarded.** `init.lua` wraps nothing, so a
  throw in `debugging.lua` would abort every module after it — and since the
  dap-go setup sits above the keymaps, a broken *Go* plugin would have taken
  *Rust* debugging with it. Same for the neotest-golang adapter, which would
  otherwise have killed neotest wholesale, Rust tests included. nvim-dap-go has
  no tags and tracks main, which makes this the likeliest thing here to break.
- **Startup cost accepted, not paid down.** The eager adapters add ~9-13ms to
  every session (neotest-golang is most of it — it pulls plenary's lib chain at
  require time), including sessions that never open a `.go` file. Logged against
  item #7 of `plans/nvim-startup-performance.md`, whose payoff this roughly
  doubles; deferring belongs with that item, not bolted on here.

---

## Verification

### Status (2026-07-13)

Verified interactively against `fixtures/` (which now carries a `go.mod` and
`animal_test.go`, so `animal.go` is a real module — delve needs one to build and
neotest needs tests to find):

- **Done** — cold-start `<F5>` in `animal.go` offers the 7-entry picker, stops at
  the breakpoint, dap-ui opens with populated Locals/stack/REPL.
- **Done** — `#require('dap').configurations.go` reads **7** after a debug
  session (the dap-go duplication bug stays dead).
- **Done** — `<leader>nd` stops inside `TestDescribe` under delve; `<leader>nf`
  gives `✓2 ✗1` with the deliberately-failing `TestSoundIsWrong` red, under a
  `neotest-golang` summary root.

**TODO — the one check still outstanding: the `-test.run` state-leak.**
Debug `TestDescribe` with `<leader>nd`, terminate it, then put the cursor in
`TestMax` and `<leader>nd` again. **The second session must stop inside
`TestMax`.** If it lands back in `TestDescribe`, the `-test.run` filters are
accumulating across runs, which means `dap_manual_config` is not being honored
as a *function* (see [What actually shipped](#what-actually-shipped)) and is
back to being one shared, mutated table. This is the only defect from the
review pass that hasn't been confirmed fixed on a real session — the fix is
proven in a simulated harness, not yet in the editor.
(Re-flagged as finding 5 of the 2026-07-13 post-ship review,
[`go-targets-picker.md`](go-targets-picker.md#post-ship-review) — it guards
against silently debugging the *wrong* test.)

Also still worth doing once: confirm the `t.Log` line (`describing: Rex`) appears
in the `dap>` REPL pane after continuing a debugged test to completion — that is
what `outputMode = 'remote'` buys, and without it a debugged Go test emits no
output at all.

### The duplication regression guard (keep running this)

Use a real module. **Create it under `~/src/`, not `/tmp`** — neotest-golang's
own health check flags a `go.mod` under `/tmp` or `/private/tmp` on macOS as a
known-problematic path. Immediately after a `<leader>nd` debug session
terminates, re-run `:lua= #require('dap').configurations.go` → **still 7**. If
it reads 21, `dap_mode = 'manual'` isn't in effect and the `<F5>` picker is
accumulating stale entries per debugged test. (The rest of the original
nine-step pass — install, a shell-side `dlv debug` codesigning sanity check,
`:checkhealth neotest-golang`, the program/test debug walkthroughs, the
Rust/LSP no-regression and clean-load checks — passed in 2026-07 and lives in
git history.)

## Risks / gotchas

- **The `dap_mode = 'manual'` config-duplication trap** (see
  [Upstream facts](#upstream-facts)). If a future refactor drops it back to the
  default, the `<F5>` picker silently grows by 14 entries per debugged test.
  The regression guard above is the check; keep it.
- **delve on macOS.** Resolution relies on Mason's `PATH` prepend. If `dlv` isn't
  found: `require('dap-go').setup({ delve = { path = vim.fn.expand('~/.local/share/nvim/mason/bin/dlv') } })`.
  delve can also require a one-time developer-mode/codesigning approval — run
  `dlv debug` once *in a shell* to surface it outside nvim, where it's legible.
- **`-race` needs cgo + a C compiler** (Xcode CLT). If tests error or crawl,
  override `go_test_args` in `testing.lua`.
- **neotest-golang v2 needs the `main`-branch Go parser.** Satisfied today; if
  `nvim-treesitter` is ever moved back to `master`, Go test discovery breaks.
- **`dap_manual_config`'s `mode = 'test'`** is required for delve to debug a test
  binary — neotest injects `program`/`args`/`cwd` but not `mode`. If a test debug
  ever launches the wrong thing, this key is the first suspect.
- **GUIDE heading renames are grep-visible** — but the stale hits from the 2026-07
  restructure were *inside* GUIDE.md (its TOC and keymap-index rows), not in
  `lua/`. Don't trust a `grep -rn 'GUIDE.md' lua/` sweep alone; it comes back
  clean.

Rollback is clean: revert the edits; delve/gotestsum and the two plugins are
separately managed (Mason / `vim.pack`), no orphan cleanup needed.

---

## Alternatives considered

### Adding a run/build layer via go.nvim (CUT — viable follow-up)

`ray-x/go.nvim` (module `go`) is the ecosystem's closest thing to rustaceanvim.
It would supply `:GoRun` (`nargs='*'`, so `:GoRun ./cmd/foo` handles any project
layout), `:GoBuild`, `:GoImports`, and `:GoCodeAction`, bound `<leader>cR` /
`<leader>cb` / `<leader>ci` / `<leader>ca` for parity with Rust's `<leader>cR`
runnables. Source-verified hybrid knobs (from its `default_config`) that would be
**load-bearing** to keep it from fighting this config: `lsp_cfg = false`,
`lsp_keymaps = false`, `lsp_codelens = false`, `lsp_inlay_hints = { enable = false }`,
`lsp_document_formatting = false` (conform owns formatting), `dap_debug = false`
(nvim-dap-go owns DAP). `guihua.lua` is optional — without it `:GoCodeAction`
falls back to `vim.ui.select`, which this config routes to the snacks picker.

**Why cut:** it's a large, opinionated plugin whose default behavior is to own
gopls, DAP, and formatting — all three already owned here — so the entire
integration is a set of negations. That's a lot of surface for a "run" command,
and it's orthogonal to debugging. It would also force the module name
`golang.lua` (a `lua/go.lua` would shadow go.nvim's `go` module — same rule as
`debugging.lua`-not-`dap.lua`).

**If picked up later:** it slots into the existing `lua/golang.lua` (created
since by the targets-picker plan), lazily set up on the first Go buffer, plus a
`## Go` GUIDE update. Nothing in this plan blocks it.

### Hand-rolled `go run .` keymap (also cut)

A `<leader>cR` that spawns `go run .` in a reused toggleterm — no plugin. Rejected
as the run story because `go run .` only runs the *buffer's own directory*: it
fails for library files and can't reach a `cmd/foo/` main, which is exactly the
papercut `:GoRun`'s arg support solves. Not worth a bespoke keymap that's wrong
for common layouts; `<leader>Tb` + `go run ./cmd/foo` in a terminal is honest and
already works.

### Monkeypatching `dap-go.setup()` (rejected in favor of `dap_mode = 'manual'`)

The duplication bug could also be killed by wrapping dap-go's `setup` to reset
`dap.configurations.go = nil` before delegating, making *every* caller
(including neotest-golang's) idempotent. Rejected: it patches a third-party
module's function at runtime to fix a bug in how a *different* third-party module
calls it, and it silently breaks if either changes. `dap_mode = 'manual'` is an
upstream-sanctioned option that removes the interaction entirely.
