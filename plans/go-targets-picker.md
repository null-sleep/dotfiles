# Go targets picker (`go list` → snacks → delve / `go run`)

> **Status: SHIPPED (2026-07).** Landed in three commits (`15ec98f` the
> `golang.lua` module move, `7537657` the picker, `edf8334` the docs).
> `<leader>dR` debugs and `<leader>cR` runs any `main` package in the module,
> from any buffer. Two review findings changed the shipped code from the sketch
> below: the run terminal takes a fixed `id = 101` (an unset id lands in
> `terminal.lua`'s reserved 1-99 count-addressable pool; since 2026-07-27 run
> output is a bottom-split buffer via `utils.split_terminal_action`, no id),
> and the abort handler is registered *before* the spawn is scheduled. Kept as the decision record —
> the `go list -e` exit-code trap and delve's `program`-must-be-a-folder contract
> are the parts worth re-reading before touching this code.
> A post-ship review (2026-07-13) upheld the design but recorded five
> findings and four drawbacks; the four code fixes (findings 1-4) were
> applied 2026-07-14. Everything still to do — the interactive checks not
> yet run and the deferred decisions from both plans — is consolidated in
> [Open items](#open-items) below; the findings' full text lives in
> [Post-ship review](#post-ship-review).

> Follow-up to [`plans/go-run-debug-test.md`](go-run-debug-test.md), which
> shipped Go debugging (nvim-dap-go + delve) and testing (neotest-golang). That
> plan deliberately cut the *run* story and left `<leader>dR` in Go as a plain
> `dap.continue()`. This plan closes the one gap that left: Go's "start a debug
> session" key lists generic launch **configs**, while Rust's lists real
> **targets**. It also revisits — and reverses — the "no `go run`" decision,
> because the reason it was cut (a hand-rolled `go run .` can't reach
> `cmd/foo/`) is exactly what a targets picker fixes.

---

<a id="open-items"></a>
> Shrunk to decision-record core 2026-07-18: Context, the Changes
> implementation spec, and superseded alternatives were pruned (git history
> has the full versions).

## Open items

The feature shipped; this is what a returning session should pick up. Full
rationale for each entry lives where it's linked — nothing is duplicated here.

### Code fixes (from the post-ship review)

Each was a verified defect with a concrete fix in
[Post-ship review](#post-ship-review); the number is that finding's number.
**All four applied 2026-07-14** (GUIDE.md updated in the same change for the
two behavior changes: the zero-mains WARN and the disabled-`<leader>dR` stub).

- [x] **1 — library-only module gets an ERROR for a normal state**
  (`pickers/gotargets.lua`). Split `found == 0`: `code == 0` → WARN "No main
  packages in this module", close the picker; `code ~= 0` → keep the ERROR +
  stderr. ([finding 1](#post-ship-review))
- [x] **2 — abort-race comment overstates the nil-check**
  (`pickers/gotargets.lua`). An abort in the one-tick `async:schedule` window
  still spawned an unwatched `go list`. Added `if async:aborted() then return
  end` atop the scheduled fn and reworded the comment. ([finding 2](#post-ship-review))
- [x] **3 — `dap_ok = false` silently unmaps `<leader>dR`**
  (`golang.lua`). Now mapped to a `vim.notify('Go debugging disabled …')`
  stub, per the repo's guard-code-only-keymaps rule. ([finding 3](#post-ship-review))
- [x] **4 — `id = 101` comment misstates the `<C-]>` cycle**
  (`pickers/gotargets.lua`). Comment fixed: the id only buys count-address
  stability; the terminal stays in the `<C-]>` cycle deliberately (cycling
  back to program output is useful). ([finding 4](#post-ship-review))

### Left to test

No item in [Verification](#verification) has recorded evidence of an
interactive run; the 2026-07-13 headless load test covers only the config-count
half of item 5 and that `require('pickers.gotargets')` loads cleanly. Also
pending from [`go-run-debug-test.md`](go-run-debug-test.md):

- [ ] **`-test.run` state-leak** — debug `TestDescribe`, terminate, then
  `<leader>nd` in `TestMax`; it must stop in `TestMax`, not leak the old
  filter. (finding 5; lives in
  [`go-run-debug-test.md` → Verification](go-run-debug-test.md#verification))
- [ ] **`t.Log` reaches the `dap>` REPL** — after continuing a debugged test to
  completion, `describing: Rex` must appear (what `outputMode = 'remote'` buys).
  ([`go-run-debug-test.md` → Verification](go-run-debug-test.md#verification))
- [ ] **[V1](#verification)** — enumeration: from a library file, the picker
  lists exactly the module's `main` packages (no library/test packages).
- [ ] **[V2](#verification)** — debug a `main` package you're not sitting in
  (the plan's reason to exist).
- [ ] **[V3](#verification)** — the debuggee's stdout reaches the `dap>` REPL
  (proves `outputMode = 'remote'`).
- [ ] **[V4](#verification)** — `<leader>cR` runs, and the float stays open
  after the program exits (`close_on_exit = false`); works from a library buffer.
- [ ] **[V5](#verification)** — cold-start `<F5>` still opens the seven-config
  picker. (The `#configurations.go == 7` half is confirmed by the headless test.)
- [ ] **[V6](#verification)** — no `go.mod` → one WARN, no picker, no stack trace.
- [ ] **[V7](#verification)** — a broken package doesn't hide good targets (the
  `-e` guard), with the stderr surfaced as a WARN.
- [ ] **[V8](#verification)** — big module: the picker opens immediately, and
  `<Esc>` mid-load kills the `go list` subprocess rather than orphaning it.
- [ ] **[V9](#verification)** — no Rust regression (`<leader>dR`/`<leader>cR`
  and neotest still work in a Cargo project).
- [ ] **[V10](#verification)** — clean load: `:messages` / `:Notifications` /
  `:checkhealth`. (Module require is confirmed headless; the interactive pass is not.)

### Open questions / deferred decisions

Swept from both plans; each is decided-for-now, listed so it isn't rediscovered
from scratch. Rationale stays where it's linked.

- [ ] **`GOWORK` / multi-module workspaces out of scope** — `vim.fs.root`
  finds the nearest `go.mod`; a `go.work` spanning modules lists only the
  buffer's. ([Risks / gotchas](#risks-gotchas))
- [ ] **No args prompt on either action** — "revisit only if it bites"; args
  stay on dap-go's Debug (Arguments) and a shell. (see "Notes on the sketch"
  under [Changes → 1](#change-gotargets))
- [ ] **Future `kind = 'test'` group** — `ntests` is collected but unused; a
  ~10-line change if package-level test debug is ever wanted.
  ([Design decision 3](#decision-main-only);
  [Alternatives](#alternatives-considered))
- [ ] **ray-x/go.nvim follow-up** — kept on the books; there's nothing left
  worth the plugin now that `go run` ships. ([Alternatives](#alternatives-considered);
  [`go-run-debug-test.md` → Alternatives](go-run-debug-test.md#alternatives-considered))
- [ ] **dap-ui doesn't close on disconnect** — add `disconnect` to the
  close-listener list only if it recurs in practice.
  ([Post-ship review](#post-ship-review), recorded drawbacks)
- [ ] **`build_flags` config fork** — a future `dap-go.setup({ delve =
  { build_flags } })` reaches `<F5>` but not `debug_target()`'s table;
  mitigation is a mirror comment in `debug_target`.
  ([Post-ship review](#post-ship-review), recorded drawbacks)
- [ ] **Cite symbols, not line numbers, for unpinned plugins** — nvim-dap-go is
  tag-less; `dap-go.lua:19`-style citations drift on update.
  ([Post-ship review](#post-ship-review), recorded drawbacks)
- [ ] **Startup cost deferred** — the eager Go adapters add ~9-13ms; paying it
  down belongs with item #7 of `plans/nvim-startup-performance.md`, not here.
  ([`go-run-debug-test.md` → What actually shipped](go-run-debug-test.md#what-actually-shipped))

## Verified upstream facts (July 2026)

Everything below was read out of installed source or measured on this machine.
Where a claim contradicts this repo's own docs, that's called out.

### delve's DAP launch contract

From delve v1.27.0's `LaunchConfig` (`~/go/pkg/mod/github.com/go-delve/delve@v1.27.0/service/dap/types.go:68-101`):

- **`mode`** — valid values are exactly `exec`, `debug`, `test`, `replay`,
  `core` (`types.go:41-47`, `isValidLaunchMode`). Default when omitted is
  `"debug"` (`service/dap/server.go:1043-1051`).
- **`program`** — *"Path to the program **folder** (or any go file within that
  folder) when in `debug` or `test` mode"* (`types.go:78-85`). So an **absolute
  package directory** is the correct value — which is what `go list`'s `.Dir`
  gives us. An *import path* is **not** documented as accepted; do not pass one.
- **`cwd`** — working directory of the debuggee; *"If not specified or empty,
  Delve's working directory is used"* (`types.go:93-101`) — i.e. nvim's cwd,
  which is not necessarily the module root. Set it explicitly.
- **`outputMode`** (`types.go:159-160`) — dap-go sets `"remote"` on all seven of
  its launch configs (`dap-go.lua:20`, `output_mode = "remote"` in
  `default_config`). `plans/go-run-debug-test.md` already records why: without
  it, a detached delve server can't forward the debuggee's stdout, and the
  program appears to print nothing. **This applies to a hand-built config too** —
  we are launching through the same detached adapter (`detached = true` on
  non-Windows, `dap-go.lua:19`), so `outputMode = 'remote'` is mandatory here.

### nvim-dap's `run()`

`M.run(config, opts)` — `~/.local/share/nvim/site/pack/core/opt/nvim-dap/lua/dap.lua:614`.

- `config` is a plain table; it goes through `prepare_config` (variable
  expansion, `on_config` listeners) and then straight to
  `dap.adapters[config.type]` — which dap-go registered as a **function**
  adapter, so `type = 'go'` resolves without any further setup on our side.
- `opts` (`dap.run.opts`, `dap.lua:608-611`) documents `new` and `before`; it
  also honors **`filetype`** (`dap.lua:624`: `opts.filetype = opts.filetype or
  vim.bo.filetype`), which becomes `session.filetype` and is used for source
  resolution and the debug terminal. Because our confirm handler runs while the
  picker's own buffer may still be current, **pass `{ filetype = 'go' }`
  explicitly** rather than letting it read `vim.bo.filetype` off a picker buffer.
- `dap.run()` is precisely how dap-go itself starts a test debug
  (`dap-go.lua:198-215`, `debug_test`), with `program = <package dir>`,
  `mode = 'test'`, `outputMode = 'remote'`. Our config is the same shape.

### `go list` — measured, not guessed

Command (one line per package, `|`-separated; no Go import path or package dir
can contain `|`):

```sh
go list -e -f '{{if eq .Name "main"}}main{{else}}pkg{{end}}|{{.ImportPath}}|{{.Dir}}|{{len .TestGoFiles}}|{{if .GoFiles}}{{index .GoFiles 0}}{{end}}' ./...
```

**`-e` is load-bearing, and so is ignoring the exit code.** Without `-e`, a
*single* broken package anywhere in the module — an unresolved import mid-`go
get`, a half-typed file — makes `go list` **exit 1**, even though it still prints
every other package to stdout. Measured:

```
$ go list -f '{{.Name}}|{{.ImportPath}}' ./...          # one package has a bad import
broken/b.go:3:8: no required module provides package github.com/nope/doesnotexist
broken|example.com/gp/broken
main|example.com/gp/cmd/foo                             # ← the target IS here
exit=1
$ go list -e -f '{{.Name}}|{{.ImportPath}}' ./... ; echo $?
broken|example.com/gp/broken
main|example.com/gp/cmd/foo
exit=0
```

So the finder must **parse stdout regardless of exit status**, and only report an
error when *no* lines parsed. An early `if res.code ~= 0 then return end` would
hand you an empty picker exactly when you are mid-edit and reaching for the
debugger — the moment the feature is most wanted. Surface `stderr` as a warning
when the exit was non-zero *and* targets were still found; error only when both
fail.

Measured on this machine (`go1.26.4 darwin/arm64`), warm cache, best of 3:

| Module | Packages | Wall time |
|---|---|---|
| `/Users/dhruv/src/dotfiles/fixtures` | 1 | **0.05s** |
| `/Users/dhruv/src/google-api-go-client` | 675 | **0.37-0.56s** |

First-ever run in `google-api-go-client` (needed to download two modules):
**2.9s**. That is the worst case that matters — it happens once per
module/dependency change, but it *will* happen, and it is far past the point
where a blocking call is acceptable.

Behavior, verified by building a throwaway module with `cmd/foo`, `cmd/bar`,
`internal/util` (+ test), a nested `go.mod`, and a `//go:build linux`-only
package:

- **main packages** are exactly `.Name == "main"`. Three of google-api-go-client's
  675 packages are main; the rest are libraries — the signal-to-noise argument
  for filtering is real.
- **test-bearing packages**: `len .TestGoFiles` (in-package) and
  `len .XTestGoFiles` (`_test` package) are non-zero.
- **Nested modules are skipped silently.** `./...` from the outer module does not
  descend into a directory containing its own `go.mod`. So a multi-module repo
  lists only the module you are in — which is the correct behavior *provided*
  the root is resolved from the **buffer**, not from nvim's cwd.
- **Build-tag-excluded packages simply don't appear**, with exit 0 and no error
  (a `//go:build linux`-only package is invisible on macOS). Acceptable, and
  arguably correct: you can't debug it here anyway.
- **`vendor/`** is not matched by `./...` (Go ≥1.9), so no vendored noise.
- **Outside a module**: `go env GOMOD` prints `/dev/null` and `go list ./...`
  **exits 1** with `pattern ./...: directory prefix . does not contain main
  module or its selected dependencies`. Must be handled before we shell out.
- **`go run <import-path>` works from anywhere inside the module** — verified:
  `cd internal/util && go run example.com/demo/cmd/foo` prints
  `hello from foo`. This is the fact that kills the old objection to a Go run
  keymap (§ Alternatives in `plans/go-run-debug-test.md`: *"`go run .` only runs
  the buffer's own directory"*). With a target picked from `go list`, we run
  `go run <ImportPath>` with `cwd = module root` and every layout works.

## Design decisions

### 1. `<leader>dR` becomes the targets picker; the 7 configs stay on `<F5>`/`<leader>dc`

Shipped as specced: `<leader>dR` opens the targets picker; the seven
dap-go configs stay reachable via `<F5>`/`<leader>dc`. Full rationale in
git history.

### 2. Yes to a Go `<leader>cR` (run)

Shipped as specced: same picker, `<leader>cR` confirm runs `go run` in a
toggleterm split instead of launching delve. Full rationale in git history.
(Since 2026-07-27 output goes to a bottom-split buffer via
`utils.split_terminal_action`; picker and targeting unchanged.)

<a id="decision-main-only"></a>
### 3. Main packages only — tests stay with neotest

**Recommendation: the picker lists `main` packages, nothing else.**

- neotest already owns tests at **function** granularity (`<leader>nn` nearest,
  `<leader>nf` file, `<leader>nd` debug nearest) and shows results as gutter
  signs + a summary tree. A package-level "debug all tests in `internal/util`"
  is strictly *coarser* — under delve, with no `-test.run` filter, it stops at
  your breakpoint in whichever test reaches it first, which is rarely what
  anyone wants.
- The escape hatch already exists for the one case neotest doesn't cover
  (debugging the current package's tests without neotest in the loop): dap-go's
  **Debug test (go.mod)** on `<F5>`.
- Signal-to-noise is the load-bearing argument: in `google-api-go-client` a
  main-only list is **3 items**; adding test-bearing packages would make it
  dozens and bury the binaries. The whole point of this feature is that the list
  is short enough to pounce on with `<M-1>`.

The enumeration collects `len .TestGoFiles` anyway (one extra template field,
zero extra cost), so a future `kind = 'test'` group is a ~10-line change if this
judgment turns out wrong. Recorded, not built.

### 4. Outside a module: warn and stop. Slow `go list`: async, no cache.

- **No `go.mod`** → `vim.fs.root(buf_dir, 'go.mod')` returns `nil` → a WARN
  notify (`Not in a Go module (no go.mod up the tree)`) and return, mirroring
  `pickers/gitstatus.lua:28-31`'s "Not a git repository". **No fallback to
  `dap.continue()`**: without a module, delve cannot build *anything*
  (GUIDE.md → Go → "You need a `go.mod`"), so falling back to a picker of seven
  configs that all fail at the build step would be a worse lie than a clear
  warning. Resolve the root from the **buffer's** directory, not `vim.uv.cwd()`
  — same rule as `pickers/gitstatus.lua:24-27`; this is also what makes
  multi-module repos behave.
  **Post-ship (finding 1):** the sibling case — *inside* a module that has no
  `main` package at all (a library/SDK repo) — is mishandled: it fires an ERROR
  with empty stderr instead of a WARN/INFO. See [Open items](#open-items).
- **Speed** → **async, no cache.** 0.4-0.6s of blocked UI on a mid-size module
  is already bad; the 2.9s cold case is unusable. The `symbols.lua` async-finder
  pattern opens the picker instantly and streams items in, so the cost is
  invisible below ~200ms and merely *visible* (spinner, live list) above it. A
  cache is rejected: it would need invalidation on every file add/rename/move
  (new `cmd/` dirs are exactly when you reach for this), and it buys ~0.4s on a
  gesture used a few times an hour.

### 5. Where the code lives: a new `lua/golang.lua` + `lua/pickers/gotargets.lua`

Shipped as specced: `lua/golang.lua` (language module: adapter config, run
terminal) + `lua/pickers/gotargets.lua` (enumerate/pick/launch). Naming and
split rationale in git history.

## Changes

<a id="change-gotargets"></a>
Pruned 2026-07-18 — the full §1-§7 implementation spec (code sketches for
`pickers/gotargets.lua`, `golang.lua`, the `debugging.lua` handoff, keymaps,
GUIDE/CLAUDE edits) shipped and the code deviated from it (id=101,
abort-handler order, post-ship findings 1-4). The shipped code is the source
of truth; the original spec lives in git history.

## Verification

> **Status (2026-07-14):** none of items 1-10 has recorded evidence of an
> interactive run. The only evidence on the books is the 2026-07-13 headless
> load test — it confirms the `#require('dap').configurations.go == 7` half of
> item 5 and that `require('pickers.gotargets')` loads cleanly, nothing else.
> Everything still to run is tracked in [Open items](#open-items) → "Left to
> test"; do not read this checklist as done.

Use `fixtures/` (a real single-package module) **and** a `cmd/foo`-style module —
the second is the whole point and `fixtures/` cannot prove it. Build one under
`~/src/` (not `/tmp` — neotest-golang's health check flags `/tmp` go.mods on
macOS) with `cmd/foo`, `cmd/bar`, and an `internal/util` library + test.

1. **Enumeration** — in `internal/util/util.go` (a *library* file, the case
   today's config cannot serve), `<leader>dR`. The picker lists **exactly two**
   items: `.../cmd/foo` and `.../cmd/bar`. No library packages, no test packages.
2. **Debug the one you're not in** — breakpoint in `cmd/bar/main.go`, then from
   `internal/util/util.go` press `<leader>dR` → pick `cmd/bar` → delve stops at
   the breakpoint, dap-ui opens. This single check is the plan's reason to exist.
3. **stdout reaches dap** — let it run to completion; the program's
   `fmt.Println` output appears in the `dap>` REPL pane. If it doesn't,
   `outputMode = 'remote'` is missing or misspelled (delve silently drops output
   in `local` mode behind a detached adapter).
4. **Run** — `<leader>cR` → pick `cmd/foo` → a float terminal shows `hello from
   foo` and **stays open** after exit (`close_on_exit = false`). Repeat from a
   library buffer; it must still work (this is the `go run .` failure the old
   plan cut a feature over).
5. **The raw configs survive** — `<F5>` from a cold start still opens the
   seven-entry config picker, and `:lua= #require('dap').configurations.go`
   reads **7** (not 14 — the dap-go double-setup regression guard from
   `plans/go-run-debug-test.md`; moving the `setup()` call between files is
   exactly the kind of edit that could accidentally call it twice).
6. **No go.mod** — create a bare `.go` file outside any module (`~/scratch.go`,
   with no `go.mod` anywhere up the tree), press `<leader>dR` → one WARN notify,
   no picker, no stack trace.
7. **A broken package doesn't hide the good targets** (the `-e` regression
   guard). In the scratch module, add a package with an unresolvable import
   (`import _ "github.com/nope/doesnotexist"`), then `<leader>dR` from anywhere:
   `cmd/foo` and `cmd/bar` **still list**, with a WARN carrying go's stderr. If
   the picker comes back empty, `-e` is missing or the finder is bailing on a
   non-zero exit code — the single most likely regression in this whole change.
8. **Big module** — open a file in a large module (`~/src/google-api-go-client`,
   675 packages, if it's still on the machine — otherwise any big one). The picker
   window appears **immediately** (not after 0.5s), fills with its main packages,
   and nvim never blocks (type into the prompt while it loads). Then `<Esc>` it
   mid-load: the `go list` subprocess must be killed, not orphaned.
9. **No regression in Rust** — `<leader>dR` and `<leader>cR` in a Cargo project
   still hit rustaceanvim, and `<leader>nn`/`<leader>nd` still run/debug tests in
   both languages (proves the `dap-go.setup()` move didn't disturb neotest).
10. **Clean load** — `:messages` / `:Notifications` clean; `:checkhealth` shows no
   new complaints.

<a id="risks-gotchas"></a>
## Risks / gotchas

- **`go list` inherits the environment nvim was launched with.** A `GOFLAGS`,
  `GOOS`, or `GOWORK` set in the user's shell profile but not in nvim's env (or
  vice versa) makes the picker's list differ from the terminal's. Same class of
  bug as the Mason/`PATH` ordering note in `rust.lua:14-22`. If a package is
  mysteriously absent, run the exact command in `:!` before suspecting the Lua.
- **`GOWORK` / multi-module workspaces are out of scope.** `vim.fs.root(dir,
  'go.mod')` finds the *nearest* module; a `go.work` spanning several modules
  will enumerate only the one the buffer is in. That is a defensible default
  (and matches `go list ./...`), but it will surprise someone eventually.
  Documented, not solved. Adding `go.work` to the root markers and using
  `go list -f ... all` is the fix if it ever matters — note it would also drag in
  every dependency, so it needs a `.Module.Main` filter.
- **Build-tag-excluded mains are invisible** (verified: exit 0, silently absent).
  A `//go:build linux` main simply won't be in the list on macOS. There is no
  error to surface, which makes this hard to debug from the picker's side.
- **A 2.9s first `go list`** (dependency download) shows an empty picker with a
  spinner for that whole time. Acceptable, but if it reads as broken, the fix is
  a `vim.notify` after ~1s, not a cache.
- **`dap.run()` skips `dap.continue()`'s buffer plumbing.** `continue()` reads
  `vim.b['dap-srcft']` and the buffer's filetype (`dap.lua:303-304`, `529`); we
  bypass all of it by calling `run()` directly, which is why `{ filetype = 'go' }`
  is passed explicitly. If stepping into a frame with no source path ever
  highlights as the wrong language, this is the knob.
- **toggleterm float reuse.** [Stale: the shipped code soon grew a no-kill
  guard (a second `<leader>cR` re-shows a live run), and since 2026-07-27 run
  output doesn't use toggleterm at all.] `run_term:shutdown()` on a second run kills
  a still-running program without asking. That is the intended edit-run loop
  behavior (and matches how most run integrations behave), but it means
  `<leader>cR` twice in a row silently drops the first process. If that bites,
  switch to a count-addressed terminal id instead of a single shared one. **As
  shipped**, the run terminal took a fixed `id = 101` — but per **finding 4**
  (see [Open items](#open-items)) that id does *not* keep it out of the `<C-]>`
  cycle (`cycle_term` filters on `hidden`, not id range); the in-code comment
  about the id/`<C-]>` relationship is wrong and needs either a reword or
  `hidden = true`.
- **The `format` icon** (`󰟓`, nf-md-language_go) assumes a Nerd Font, which this
  config already requires everywhere (`pickers/symbols.lua:110-138` does the
  same). Fine, but don't put it in a GUIDE table cell — the repo `CLAUDE.md`'s
  no-emoji-in-table-cells rule exists because render-markdown breaks column
  alignment on variable-width glyphs.

## Alternatives considered

### Add test packages to the picker (or a second `<leader>nT` "debug package tests")

Deferred, with the enumeration already collecting `len .TestGoFiles` so it stays
a ~10-line change. neotest owns tests at function granularity and does it better;
a package-granularity test debug is a coarse tool that would double the list
length to serve a rare case that dap-go's **Debug test (go.mod)** already covers.

### ray-x/go.nvim for the run layer (`:GoRun`)

Still cut, and now for a second reason. `plans/go-run-debug-test.md` cut it
because integrating it is a list of negations (`lsp_cfg = false`,
`dap_debug = false`, `lsp_document_formatting = false`, …) to stop it owning
gopls, DAP, and formatting. With this plan, its remaining draw — `:GoRun
./cmd/foo` — is delivered by 15 lines of toggleterm, with a *picker* instead of a
typed path. There is nothing left worth the plugin.

---

<a id="post-ship-review"></a>
## Post-ship review findings (2026-07-13)

A full-stack review after shipping: the config code, the installed plugin
sources (nvim-dap, nvim-dap-go, snacks' async util, toggleterm), and a
headless load test (`#dap.configurations.go` → 7, the picker module requires
cleanly). **The design held** — no findings against the architecture, the
`-e`/exit-code handling, `outputMode = 'remote'`, or the main-only scope.
One strength verified in passing that nothing had documented: `dap.run()`
records `last_run` (`nvim-dap/lua/dap.lua:626`), so **`<leader>dl` correctly
re-launches a picker-chosen target**.

### Findings

Findings 1-4 were applied on 2026-07-14 (the entries below are the review
record, kept as written); finding 5 is an interactive check, tracked under
"Left to test" in [Open items](#open-items).

1. **A library-only module gets an ERROR for a normal state**
   (`pickers/gotargets.lua:171-180`). `found == 0` is reported as a real error
   ("bad module, go missing"), but a module with no `main` package at all — an
   SDK or library repo — is legitimate; there, `<leader>dR`/`<leader>cR` fires
   a red ERROR with an empty stderr appended and leaves the empty picker open.
   Split the cases: `code == 0` and zero mains → WARN/INFO "no main packages
   in this module" (and close the picker); `code ~= 0` and zero mains → keep
   the ERROR with stderr. Most likely finding to bite a real session.

2. **The abort-race comment overstates what the nil-check covers**
   (`pickers/gotargets.lua:113-120`). snacks' async fires `abort` handlers
   when the coroutine dies, but it does **not** cancel the `vim.schedule`
   callback queued by `async:schedule()` — an abort landing in that one-tick
   window runs the handler with `obj == nil`, and the queued callback then
   spawns `go list` anyway, unwatched. Consequence: a short-lived orphan
   process; the comment's claim "nothing spawned, nothing to kill" is false.
   Fix: `if async:aborted() then return end` at the top of the scheduled
   function, and reword the comment.

3. **`dap_ok = false` silently unmaps `<leader>dR` in Go buffers**
   (`golang.lua:41-44`). The startup WARN has long scrolled away by the time
   the key is pressed, and per the repo's own rule (nvim `CLAUDE.md` →
   guarding code-only keymaps) a silent decline reads as a broken keymap.
   Map a `vim.notify('Go debugging disabled — nvim-dap-go failed to load')`
   stub instead of not mapping it.

4. **The `id = 101` comment misstates the `<C-]>` cycle**
   (`pickers/gotargets.lua:75-79`). `cycle_term` (`terminal.lua:44-48`)
   filters on `hidden`, not on id range — the bottom panel stays out of the
   cycle because it is `hidden = true`, and the run terminal (not hidden) is
   **in** the cycle at any id. Either keep that (arguably useful: cycle back
   to the program's output) and fix the comment — `id = 101` buys
   count-address stability and nothing else — or add `hidden = true`.
   Related, undocumented: `<C-\>`'s open-panel handler closes floats with
   `t.id ~= 100` (`terminal.lua:103-106`), so opening the bottom panel hides a
   still-running run float.

5. **The `-test.run` state-leak verification is still outstanding.** It
   belongs to [`go-run-debug-test.md`](go-run-debug-test.md) (its Verification
   section), but it guards `dap_manual_config`-as-a-function — i.e. against
   *silently debugging the wrong test*, a failure that lies. Two minutes in
   the editor; do it.

### Recorded drawbacks (no action planned)

- **The picker's hand-built config forks from dap-go's config-level knobs.**
  A future `dap-go.setup({ delve = { build_flags = ... } })` applies to the
  `<F5>` configs (six of the seven — `Attach` carries no `buildFlags`, and
  `Debug (Arguments & Build Flags)` prompts for its own) but not to
  `debug_target()`'s table, so the same breakpoint could build under `<F5>`
  and fail under `<leader>dR`. dap-go
  keeps its resolved config in a file-local (`internal_global_config`), so it
  cannot be inherited; the mitigation is a comment in `debug_target` saying
  config-level setup options must be mirrored there. Adapter-level options
  (dlv path, port) are shared automatically — only config-level ones fork.
- **Upstream line-number citations drift on `vim.pack.update()`.** Comments
  cite `dap-go.lua:19`, `dap.lua:624`, delve `types.go:78-85`; the lockfile
  pins those revisions today, but nvim-dap-go is tag-less and tracks main,
  and the update that breaks something is exactly when the numbers go stale.
  Prefer symbol names (`default_config.delve.detached`,
  `LaunchConfig.Program`) over line numbers when citing unpinned plugins.
- **dap-ui doesn't close on disconnect-ended sessions**
  (`debugging.lua:28-30` closes on `event_terminated`/`event_exited` only) —
  an Attach session ended from the delve side can leave the UI open. GUIDE
  already hedges ("if it ever lingers, `<leader>du` toggles it"); add
  `disconnect` to the close-listener list if it recurs in practice.
- **The pcall guard covers load time only.** With nvim-dap-go unpinned, the
  likelier post-update failure is behavioral (an adapter signature change),
  which surfaces as an uncaught error mid-`dap.run`. Known and accepted —
  the guard's coverage ends at `setup()`.
