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
> load-bearing one is [dap_mode = "manual"](#4-luatestinglua--register-the-neotest-adapter).

## Context

Go is already well served in this config for editing — `gopls` (`lsp.lua`,
configured + enabled), `goimports` on save (conform), `golangci-lint`
(nvim-lint), the `go` treesitter parser, and a `fixtures/animal.go`. What it has
no support for is **debugging** and **testing**.

The generic engines for both already exist and were built to be extended:
`debugging.lua` (nvim-dap + nvim-dap-ui, the `<leader>d*` / `<F5>`–`<F12>`
keymaps) and `testing.lua` (neotest, the `<leader>n*` keymaps). But neither has
a Go adapter, and **nvim-dap registers no adapters or configurations of its
own** — rustaceanvim's `dap = {}` is the config's entire supply. So today, in a
`.go` buffer, a cold-start `<F5>`/`<leader>dc` has nothing to launch, and
`<leader>nd` (debug nearest test) does nothing, because `rustaceanvim.neotest`
is the sole neotest adapter registered.

This plan fills exactly those two gaps, following the two extension recipes
already documented in `GUIDE.md`.

### Upstream facts (source-verified, July 2026)

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

## Changes

**No new Lua module.** With go.nvim cut, the only Go-specific setup left is one
`dap-go` call and one neotest adapter — each belongs in the module that already
owns that engine, which is what `GUIDE.md`'s two extension recipes prescribe. A
`lua/go.lua` holding two lines would be indirection for its own sake. (Rust needs
`rust.lua` only because rustaceanvim also owns rust-analyzer, codelens, and its
own keymaps.)

### 1. `lua/plugins.lua` — two plugins, in the "Rust / Debug / Test" block

```lua
{ src = gh('leoluz/nvim-dap-go') },
{ src = gh('fredrikaverpil/neotest-golang'), version = vim.version.range('^2') },
```

Retitle that block's comment — it is no longer Rust-only. neotest-golang is
pinned to `^2` because it ships breaking majors (v1→v2 changed the treesitter
requirement out from under users), same rationale as `rustaceanvim` `^9` and
`blink.cmp` `1.*`. nvim-dap-go publishes no tags at all, so it cannot be pinned;
leave it bare. No build hooks needed.

### 2. `lua/lsp.lua` — two Mason tools, next to `codelldb` in `ensure_installed`

```lua
'delve',      -- go debug adapter (dlv; consumed by nvim-dap via nvim-dap-go)
'gotestsum',  -- go test runner (neotest-golang; keeps test JSON off stdout)
```

gopls config unchanged. mason-tool-installer's `run_on_start` is on and
`lsp.lua:37` sets `start_delay = 30000`, so these install ~30s after the next
launch with no manual step.

### 3. `lua/debugging.lua` — register the delve adapter

Alongside the existing packadds, then after `dapui.setup()`:

```lua
vim.cmd.packadd('nvim-dap-go')
require('dap-go').setup()   -- registers dap.adapters.go + 7 dap.configurations.go
```

Called **exactly once**, at startup — see §4 for why that matters. Eager loading
is consistent with how this module already packadds nvim-dap and nvim-dap-ui;
`dap-go.setup()` only populates two tables. (If it ever shows in a startup
profile, move it behind a `FileType go` autocmd — the adapter only has to exist
before the first `dap.continue()`.)

This is what makes `<F5>` / `<leader>dc` work from a cold start in a `.go`
buffer: dap now has configurations for the `go` filetype and offers the picker.

**Also fix the now-false header comment** at `debugging.lua:9-12` — "Rust
adapter/configurations are provided by rustaceanvim … so this module only wires
the generic engine + UI + keymaps" stops being true the moment this call lands
in that file.

### 4. `lua/testing.lua` — register the neotest adapter

`packadd` with the others, then replace the commented `require('neotest-golang')`
placeholder in the `adapters` list:

```lua
vim.cmd.packadd('neotest-golang')
...
adapters = {
  require('rustaceanvim.neotest'),
  require('neotest-golang')({
    runner = 'gotestsum',
    -- dap_mode 'manual' is LOAD-BEARING, not a preference. The default
    -- ('dap-go') re-runs dap-go.setup() on every test debug — and dap-go's
    -- setup APPENDS its 7 configs instead of replacing them, so each debugged
    -- test would permanently grow the <F5> picker by 14 stale entries.
    -- 'manual' makes neotest build its own config and never touch dap-go.
    dap_mode = 'manual',
    dap_manual_config = {
      name = 'Neotest Go',
      type = 'go',        -- the adapter dap-go registered in debugging.lua
      request = 'launch',
      mode = 'test',      -- dlv test-binary mode
    },
  }),
},
```

neotest-golang injects `program`, `args`, and `cwd` itself; the four keys above
are the ones it requires from us. This also means `testing.lua` never `require`s
the `dap-go` **module**, so it introduces no new `init.lua` load-order
constraint — it only needs `dap.adapters.go` to exist by the time a debug
actually runs, which `debugging.lua` (loaded earlier) guarantees.

Leave `go_test_args` at its default (`-race` included).

**Also fix the header comment** at `testing.lua:1-7`, which says "Rust now via
rustaceanvim's adapter" and lists only rustaceanvim as a load-order dependency.

### 5. `lua/whichkey.lua` — widen keyword aliases (no new group, no new keymaps)

The `<leader>d*` / `<leader>n*` keys are unchanged and already global; they just
answer to Go now. Make them findable by Go vocabulary in the `<leader>sk` picker:

```lua
['<leader>dc'] = 'debug continue start dap run delve go rust',
['<leader>nd'] = 'neotest debug test dap nearest go delve rust',
```

### 6. `GUIDE.md` — split the shared engines out of the Rust section

Adding a second language invalidates the current structure: the global Debug
(`<leader>d*`) and Test (`<leader>n*`) tables live *inside* `## Rust
(rustaceanvim + DAP + neotest)` because Rust was the only language, and two
paragraphs there now state outright that Rust is the only language that can start
a session. Per `CLAUDE.md`'s keymap-ownership rule (one key, one table, one
home), restructure Part 2 into:

- **`## Debugging (nvim-dap)`** *(new)* — owns the global `<leader>d*` +
  `<F5>`/`<F9>`–`<F12>` table, dap-ui's auto-open/close behavior, breakpoint
  signs, a **language-support matrix** (Rust → rustaceanvim/codelldb; Go →
  nvim-dap-go/delve; anything else → no adapter, `<F5>` does nothing), and the
  "Extending DAP to other languages" recipe (moved here from Rust).
- **`## Testing (neotest)`** *(new)* — owns the global `<leader>n*` table, the
  adapter list, and "Extending neotest to other languages" (moved here).
- **`## Rust (rustaceanvim)`** *(renamed, trimmed)* — keeps only Rust-specific
  material: the `K` / `<leader>ca` / `<leader>cR` / `<leader>cm` / `<leader>cC` /
  `<leader>dR` / `grx` table, rust-analyzer ownership, standalone `.rs` files,
  the codelldb/liblldb troubleshooting note. Links to the two new sections.
- **`## Go (delve + neotest)`** *(new)* — Go's own setup and behavior: what Mason
  installs (`delve`, `gotestsum`), the seven launch configurations dap-go
  registers (by their real names, listed above), a debug walkthrough (breakpoint
  → `<F5>` → pick "Debug"), the `dap_mode = 'manual'` rationale, the `-race`/cgo
  note, and delve's macOS codesigning gotcha.

Mandatory hygiene the earlier draft missed:

- **Explicit anchors.** All four headings carry parentheses (and `Go (delve +
  neotest)` a `+`), which per `nvim/.config/nvim/CLAUDE.md` → "Anchor-link
  hygiene" slugify inconsistently. Add `<a id="debugging"></a>`,
  `<a id="testing"></a>`, `<a id="go"></a>` above them and link the TOC to those.
  The Rust section already has `<a id="rust"></a>`, so its anchor survives the
  rename.
- **Slug collision.** GUIDE already has `### Debugging` (line ~2107) and
  `### Testing` (~2129) *inside* the Rust section. They must be removed/renamed
  as part of the move, or `#debugging` / `#testing` become ambiguous.
- **Stale keymap-index rows.** The real breakage is inside GUIDE.md itself, not
  in `lua/` (`grep -rn 'GUIDE.md' lua/` returns **no** Rust/DAP/neotest hits).
  These three rows point at tables that will no longer live in the Rust section:
  - `GUIDE.md:642` — `<leader>c*` (Rust ft) → `[Rust](#rust) → Keymaps`
  - `GUIDE.md:643` — `<leader>d*`, `<F5>`-`<F12>` → `[Rust](#rust) → Keymaps (Debug table)`
  - `GUIDE.md:644` — `<leader>n*` → `[Rust](#rust) → Keymaps (Test table)`

  643 and 644 must be re-pointed at the new Debugging/Testing sections; 642 stays
  with Rust. Plus `GUIDE.md:47` (TOC entry) and the heading at 2044-2045.
- **Re-point the extension recipes.** Both "how to add a language" examples
  currently use Go as the hypothetical (`GUIDE.md:2181` `require('neotest-golang')`,
  `:2192` `require('dap-go').setup()`). After this change Go *is* the shipped
  config, so a recipe demonstrating an already-added language reads as a bug.
  Re-point both at Python (`nvim-dap-python` / `neotest-python`) when moving them.

The two "Rust is the only language…" paragraphs (added 2026-07 under Rust →
Debugging/Testing) get **deleted**, not edited — the language-support matrix is
where that fact now lives, and it stays true as languages are added.

### 7. `README.md` — no change expected

delve and gotestsum arrive through Mason's `ensure_installed`, which README does
not enumerate tool-by-tool (it doesn't mention `codelldb` either), and Go's
toolchain is already a documented prerequisite under `## Languages`. Both are
source-built by Mason, which is precisely the case README's existing Mason
callout (194-201) already covers. Nothing on the fresh-machine bootstrap path
changes. Re-verify at implementation time; if delve turns out to need a manual
macOS codesigning step, that step goes in README's `## Neovim` section, per the
README-owns-setup rule.

---

## Files touched

| File | Change |
|---|---|
| `lua/plugins.lua` | +2 `vim.pack` entries (nvim-dap-go unpinned — no tags exist; neotest-golang `^2`); retitle the block comment |
| `lua/lsp.lua` | +`delve`, +`gotestsum` in mason-tool-installer `ensure_installed` |
| `lua/debugging.lua` | +`packadd` + `require('dap-go').setup()`; fix the stale "Rust adapter" header comment |
| `lua/testing.lua` | +`packadd` + `require('neotest-golang')({...})` with `dap_mode = 'manual'`; fix the stale header comment |
| `lua/whichkey.lua` | widen `<leader>dc` / `<leader>nd` keyword aliases |
| `GUIDE.md` | split out `## Debugging` + `## Testing`, trim/rename `## Rust`, add `## Go`, fix rows 47/642-644, add explicit anchors, re-point both extension recipes at Python |
| `nvim-pack-lock.json` | regenerated after the plugins install (committed) |

No new module, no `init.lua` change, no new keymaps. Paths under
`/Users/dhruv/src/dotfiles/nvim/.config/nvim/` (Stow source; live via the
`~/.config/nvim` symlink).

## Commits

Per-change commits carrying a `Part-of: go debug + test support` trailer:

1. `feat(nvim): install delve + gotestsum and the Go dap/neotest plugins` (plugins.lua, lsp.lua, lock)
2. `feat(nvim): register the delve adapter with nvim-dap` (debugging.lua)
3. `feat(nvim): register the neotest-golang adapter` (testing.lua, whichkey.lua)
4. `docs(nvim): give DAP and neotest their own GUIDE sections` (GUIDE.md — the pure restructure, no Go content)
5. `docs(nvim): document Go debugging and testing` (GUIDE.md — the new Go section)

Splitting 4 from 5 keeps the move/rename diff reviewable on its own.

<a id="what-actually-shipped"></a>
### What actually shipped (2026-07)

Implemented and committed. Deviations from the above, all deliberate:

- **GUIDE landed as one commit, not two.** The restructure and the Go section
  touch interleaved regions of the same file; splitting them would have meant
  hand-staging hunks for little review benefit.
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
accumulating across runs, which means `dap_manual_config` is not being honored as
a *function* (see §4) and is back to being one shared, mutated table. This is the
only defect from the review pass that hasn't been confirmed fixed on a real
session — the fix is proven in a simulated harness, not yet in the editor.
(Re-flagged as finding 5 of the 2026-07-13 post-ship review,
[`go-targets-picker.md`](go-targets-picker.md#post-ship-review) — it guards
against silently debugging the *wrong* test.)

Also still worth doing once: confirm the `t.Log` line (`describing: Rex`) appears
in the `dap>` REPL pane after continuing a debugged test to completion — that is
what `outputMode = 'remote'` buys, and without it a debugged Go test emits no
output at all.

### The full pass

Use a real module. **Create it under `~/src/`, not `/tmp`** — neotest-golang's own
health check flags a `go.mod` under `/tmp` or `/private/tmp` on macOS as a
known-problematic path.

1. **Install:** restart nvim — `vim.pack` fetches nvim-dap-go + neotest-golang;
   mason-tool-installer auto-builds `delve` + `gotestsum` ~30s in. Confirm
   `~/.local/share/nvim/mason/bin/dlv` exists.
2. **delve sanity (macOS):** run `dlv debug` once from the scratch module *in a
   shell* before trusting the editor path — it surfaces any codesigning prompt
   outside nvim, where it's legible.
3. **Health:** `:checkhealth neotest-golang` — it checks `go`/`dlv`/`gotestsum` on
   `PATH`, `go.mod` discovery, the Go parser + query compatibility, and
   `-race`-without-cgo. (Do **not** rely on `:checkhealth dap` for the adapter:
   `dap.adapters.go` is a *function*, and dap's health check prints "Adapter is a
   function. Can't validate it". Its nvim-treesitter branch probe also can't see
   `vim.pack`'s install path, so "could not locate nvim-treesitter" there is
   expected noise, not a failure.) Assert the dap side directly instead:
   `:lua= #require('dap').configurations.go` → **7**.
4. **Program debug (the headline):** breakpoint in `main()` (`<leader>db`/`<F9>`),
   then `<F5>` **from a cold start** → config picker appears → "Debug" → stops at
   the breakpoint, dap-ui auto-opens (scopes/stack/REPL); step with
   `<F10>`/`<F11>`/`<F12>`; `<leader>dq` terminates and the UI auto-closes.
5. **Test run + debug:** `<leader>nn` / `<leader>nf` run tests (signs +
   `<leader>ns` summary tree); breakpoint + `<leader>nd` stops inside the test
   under delve.
6. **Regression test for the duplication bug:** immediately after step 5's
   `<leader>nd` session terminates, re-run `:lua= #require('dap').configurations.go`
   → **still 7**. If it reads 21, `dap_mode = 'manual'` isn't in effect and the
   `<F5>` picker is accumulating stale entries.
7. **No regression in Rust:** `<leader>dR` still debugs and `<leader>nn` still runs
   tests in a Cargo project (proves the second neotest adapter didn't displace
   `rustaceanvim.neotest`).
8. **Formatting/LSP untouched:** save a `.go` file — goimports still runs;
   `:checkhealth vim.lsp` still shows exactly one gopls client.
9. **Clean load:** `:messages` / `:Notifications` — no errors, no orphan-plugin
   warning.

## Risks / gotchas

- **The `dap_mode = 'manual'` config-duplication trap** (see §4). If a future
  refactor drops it back to the default, the `<F5>` picker silently grows by 14
  entries per debugged test. Step 6 above is the guard; keep it.
- **delve on macOS.** Resolution relies on Mason's `PATH` prepend. If `dlv` isn't
  found: `require('dap-go').setup({ delve = { path = vim.fn.expand('~/.local/share/nvim/mason/bin/dlv') } })`.
  delve can also require a one-time developer-mode/codesigning approval — hence
  the CLI `dlv debug` in step 2.
- **`-race` needs cgo + a C compiler** (Xcode CLT). If tests error or crawl,
  override `go_test_args` in `testing.lua`.
- **neotest-golang v2 needs the `main`-branch Go parser.** Satisfied today; if
  `nvim-treesitter` is ever moved back to `master`, Go test discovery breaks.
- **`dap_manual_config`'s `mode = 'test'`** is required for delve to debug a test
  binary — neotest injects `program`/`args`/`cwd` but not `mode`. Verify at
  implementation; if a test debug launches the wrong thing, this key is the
  first suspect.
- **GUIDE heading rename is grep-visible** — but the stale hits are *inside*
  GUIDE.md (rows 47, 642-644, 2044-2045), not in `lua/`. Don't trust the
  `grep -rn 'GUIDE.md' lua/` sweep alone; it comes back clean.

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

**If picked up later:** it slots in cleanly as a new `lua/golang.lua`, lazily set
up on the first Go buffer, plus `require('golang')` in `init.lua` and a `## Go`
GUIDE update. Nothing in this plan blocks it.

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
