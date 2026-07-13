# Go targets picker (`go list` → snacks → delve / `go run`)

> Follow-up to [`plans/go-run-debug-test.md`](go-run-debug-test.md), which
> shipped Go debugging (nvim-dap-go + delve) and testing (neotest-golang). That
> plan deliberately cut the *run* story and left `<leader>dR` in Go as a plain
> `dap.continue()`. This plan closes the one gap that left: Go's "start a debug
> session" key lists generic launch **configs**, while Rust's lists real
> **targets**. It also revisits — and reverses — the "no `go run`" decision,
> because the reason it was cut (a hand-rolled `go run .` can't reach
> `cmd/foo/`) is exactly what a targets picker fixes.

## Context

Today, in a `.go` buffer:

- `<leader>dR` → `dap.continue()` (`lua/debugging.lua:45-52`) → with no session
  running, nvim-dap opens a `vim.ui.select` (→ snacks) over the **seven**
  `dap.configurations.go` entries that `require('dap-go').setup()` registered.
- In a `.rs` buffer, `<leader>dR` → `:RustLsp debuggables` (`lua/rust.lua:82`) →
  a list of **real cargo targets** from rust-analyzer, and `<leader>cR` →
  runnables → `cargo run` on the picked target.

The seven Go entries are not targets — they are *tools*, and every one of them is
anchored to the buffer you already have open. dap-go hard-codes
`program = "${fileDirname}"` for "Debug Package"
(`~/.local/share/nvim/site/pack/core/opt/nvim-dap-go/lua/dap-go.lua:135`), and
nvim-dap expands `${fileDirname}` to `vim.fn.expand('%:p:h')` — the *current
file's own directory* (`nvim-dap/lua/dap.lua:369-371`). So:

| Config | `program` | What you can actually debug |
|---|---|---|
| Debug | `${file}` | the file you are looking at |
| Debug Package | `${fileDirname}` | the package the file you are looking at lives in |

There is **no entry in the list that can launch a `main` package you are not
already sitting in.** In a `cmd/foo` / `cmd/bar` layout — the standard Go
service layout — debugging `cmd/bar` means: open a file under `cmd/bar/`, then
`<leader>dR`, then pick. From a library file (`internal/store/store.go`), the
list offers nothing that builds: "Debug" and "Debug Package" both point at a
non-main package and delve fails at the build step.

`GUIDE.md`'s Go section already documents this honestly ("All of these are
anchored to the current file … None of them lets you pick a different `main`
package") and points at this plan. So there is no doc bug to fix here — the job
is to close the gap the docs already admit to.

This plan adds the missing provider — Go has no rust-analyzer to ask, but it
has `go list`, which is exactly a target enumerator — and wires it to the two
keys Rust already uses: `<leader>dR` (debug) and `<leader>cR` (run).

---

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

### snacks picker API (as this repo already uses it)

Read from `~/.local/share/nvim/site/pack/core/opt/snacks.nvim/lua/snacks/picker/`
and from this config's own pickers.

- **Entry point**: `Snacks.picker.pick(opts)` (`picker/init.lua:66`). Fields we
  need are all on `snacks.picker.Config` (`picker/config/defaults.lua:69-115`):
  `source`, `title`, `items` **or** `finder`, `format`, `confirm`, `layout`,
  `actions`, `sort`, `preview`.
- **Custom items + custom confirm** — the canonical minimal example is snacks'
  own `vim.ui.select` implementation (`picker/select.lua:14-70`): a `finder`
  returning plain item tables, a `format`, and `actions.confirm =
  function(picker, item) picker:close(); vim.schedule(...) end`. `confirm` is
  also accepted as a top-level shortcut (`defaults.lua:107`).
- **Async finder** — the in-repo model is `lua/pickers/symbols.lua:406-469`: the
  finder returns `function(cb)`, grabs `require('snacks.picker.util.async').running()`,
  kicks the async work off inside `async:schedule(...)`, spins on
  `async:suspend()` until the result lands, then `cb(item)` per item. This opens
  the picker **immediately** and fills it when the data arrives — which is what
  we want for a 0.4-2.9s `go list`. **The producer coroutine runs in a fast
  event context** (stepped from a uv check handle), so anything touching the
  nvim API must go through `async:schedule` / `vim.schedule` — `symbols.lua:399-404`
  spells this out.
- **Default previewer** is `Snacks.picker.preview.file` when `opts.preview` is
  unset (`picker/config/init.lua:197-202`), keyed off `item.file`. Setting
  `item.file = <pkg dir>/<first GoFile>` gets us a free source preview of the
  target with zero extra code.
- **Format** returns `snacks.picker.Highlight[]`; column padding via
  `Snacks.picker.util.align(text, width, { truncate = true })` — see
  `pickers/symbols.lua:474-489` and `pickers/gitstatus.lua:123-131`.
- **`<M-1>`..`<M-9>` quick-pick** is a repo convention available as
  `require('pickers.common').quick_pick_actions()` (`pickers/common.lua:14-25`),
  returning `actions` + `keys` fragments. A 2-8 item target list is the ideal
  case for it.

---

## Design decisions

### 1. `<leader>dR` becomes the targets picker; the 7 configs stay on `<F5>`/`<leader>dc`

**Recommendation: replace, don't add a third key.**

The dR/F5 split already exists in Rust and is documented as the house rule
(`GUIDE.md` → Rust → Debugging entry point): **`<leader>dR` = "start a session
by picking a target", `<F5>`/`<leader>dc` = the raw dap engine (resume, or the
config picker on a cold start).** Go currently violates this by making `<leader>dR`
a literal alias of `<leader>dc` — the GUIDE even has to apologize for it ("Same
gesture, different list"). Pointing `<leader>dR` at the targets picker makes the
two languages *actually* parallel instead of nominally parallel.

Nothing is lost: `dap.continue()` on `<F5>` / `<leader>dc` still opens the
seven-config picker verbatim, which remains the way to reach **Attach**,
**Debug (Arguments)**, and **Debug test (go.mod)**. Those are genuinely
different tools, not targets, and they belong behind the engine key.

### 2. Yes to a Go `<leader>cR` (run)

**Recommendation: ship it, in the same picker, with a different confirm action.**

`plans/go-run-debug-test.md` cut a hand-rolled run keymap for one reason: *"`go
run .` only runs the buffer's own directory: it fails for library files and
can't reach a `cmd/foo/` main"*. That objection is entirely about **not knowing
what to run** — and the targets picker is the answer to exactly that question.
Once the user has picked `example.com/demo/cmd/foo` from a list, `go run
example.com/demo/cmd/foo` from the module root is correct from any buffer in
the module (verified above). The marginal cost over the debug picker is ~15
lines: same finder, same format, `confirm` spawns a toggleterm instead of
calling `dap.run`.

It also completes the symmetry that motivates this whole plan — Rust has
`<leader>cR` runnables *and* `<leader>dR` debuggables; giving Go one without the
other would leave the same "why is this different in Go" papercut, just moved.

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
- **Speed** → **async, no cache.** 0.4-0.6s of blocked UI on a mid-size module
  is already bad; the 2.9s cold case is unusable. The `symbols.lua` async-finder
  pattern opens the picker instantly and streams items in, so the cost is
  invisible below ~200ms and merely *visible* (spinner, live list) above it. A
  cache is rejected: it would need invalidation on every file add/rename/move
  (new `cmd/` dirs are exactly when you reach for this), and it buys ~0.4s on a
  gesture used a few times an hour.

### 5. Where the code lives: a new `lua/golang.lua` + `lua/pickers/gotargets.lua`

`plans/go-run-debug-test.md` argued "**No new Lua module** … a `lua/go.lua`
holding two lines would be indirection for its own sake". That was right *then*
— the Go-specific surface was one `dap-go.setup()` call and one neotest adapter.
It is wrong now: this plan adds a target enumerator, a custom picker, a dap
launcher, a terminal launcher, and two buffer-local keymaps. That is precisely
the "Rust needs `rust.lua` because rustaceanvim also owns … its own keymaps"
threshold that plan named.

**Naming: `golang.lua`, not `go.lua`.** The repo's rule (`nvim/.config/nvim/CLAUDE.md`
→ "Topic files avoid shadowing a plugin's own Lua module name") says don't take
a name a plugin owns. `lua/go.lua` is `require('go')` — the exact module name of
**ray-x/go.nvim**, which `plans/go-run-debug-test.md` keeps on the books as a
live follow-up ("If picked up later: it slots in cleanly as a new
`lua/golang.lua`"). Taking `go.lua` now would either block that follow-up or
force a rename later. `golang.lua` costs one syllable and is the name that plan
already reserved.

**The picker itself goes in `lua/pickers/gotargets.lua`**, per the established
split: every custom snacks picker in this config lives under `pickers/` and is
invoked as `require('pickers.<x>').open()` from a keymap (`keymaps.lua:14-21`,
`140-144`, `272`). `golang.lua` then stays thin: the dap-go setup (moved out of
`debugging.lua`) plus the `FileType go` keymaps. Bonus: `pickers.go` /
`pickers.gotargets` is namespaced, so the shadowing question doesn't even arise
for that file.

**`debugging.lua` gives up its Go block.** The `require('dap-go').setup()` call
and the `FileType go` autocmd currently sit in `debugging.lua:23-55` only
because Go had no module of its own — GUIDE.md says so in as many words
("Go's `nvim-dap-go` call lives directly in `debugging.lua` since Go has no
other language module to own it"). Now it does, and `debugging.lua` goes back to
being the generic engine, exactly like it is for Rust.

---

## Changes

### 1. `lua/pickers/gotargets.lua` — new: enumerate + pick + launch

```lua
-- pickers/gotargets.lua — Go run/debug targets picker (the `go list` answer to
-- rust-analyzer's runnables/debuggables).
--
-- USAGE
--   require('pickers.gotargets').open('debug')   -- <leader>dR in a go buffer
--   require('pickers.gotargets').open('run')     -- <leader>cR in a go buffer
--
-- WHY THIS EXISTS
--   dap-go's seven launch configs are not targets: "Debug" is ${file} and
--   "Debug Package" is ${fileDirname} (nvim-dap-go/lua/dap-go.lua:105-133),
--   so neither can launch a main package you aren't already sitting in. In a
--   cmd/foo layout that's the whole job. `go list` is Go's target provider.

local Async = require('snacks.picker.util.async')
local common = require('pickers.common')

local M = {}

-- One line per package. `|` is safe: neither an import path nor a package dir
-- can contain it. Fields: kind, import path, abs dir, #in-package test files,
-- first .go file (used for the preview only).
local LIST_FORMAT = table.concat({
  '{{if eq .Name "main"}}main{{else}}pkg{{end}}',
  '{{.ImportPath}}',
  '{{.Dir}}',
  '{{len .TestGoFiles}}',
  '{{if .GoFiles}}{{index .GoFiles 0}}{{end}}',
}, '|')

-- Module root from the BUFFER's directory, not nvim's cwd (same rule as
-- pickers/gitstatus.lua): editing a file in another repo/module must enumerate
-- THAT module. nil = no go.mod up the tree.
local function module_root()
  local dir = vim.fn.expand('%:p:h')
  if dir == '' then dir = vim.uv.cwd() end
  return vim.fs.root(dir, 'go.mod')
end

local function debug_target(item, root)
  -- program = the package DIRECTORY: delve's LaunchConfig.Program is "path to
  -- the program folder ... when in debug or test mode" (delve
  -- service/dap/types.go:78-85). An import path is not accepted there.
  -- outputMode = 'remote' is mandatory, not decorative: the adapter runs delve
  -- detached (nvim-dap-go/lua/dap-go.lua:19), and a detached server can't
  -- forward the debuggee's stdout in delve's default 'local' output mode — the
  -- program would appear to print nothing. dap-go sets it on all seven of its
  -- own configs for the same reason.
  -- filetype is passed explicitly because dap.run() otherwise reads
  -- vim.bo.filetype (dap.lua:624), which may still be the picker's buffer.
  require('dap').run({
    type = 'go',
    name = 'Debug ' .. item.importpath,
    request = 'launch',
    mode = 'debug',
    program = item.dir,
    cwd = root,
    outputMode = 'remote',
  }, { filetype = 'go' })
end

local run_term  -- reused across runs; a second run replaces the first

local function run_target(item, root)
  local Terminal = require('toggleterm.terminal').Terminal
  if run_term then
    run_term:shutdown()
  end
  -- `go run <import-path>` from the module root reaches any main package in the
  -- module, from any buffer — which is exactly what a hand-rolled `go run .`
  -- could not do (plans/go-run-debug-test.md, Alternatives).
  -- close_on_exit = false so the program's output survives its exit.
  run_term = Terminal:new({
    cmd = 'go run ' .. vim.fn.shellescape(item.importpath),
    dir = root,
    direction = 'float',
    close_on_exit = false,
  })
  run_term:toggle()
end

--- @param mode 'debug'|'run'
function M.open(mode)
  local root = module_root()
  if not root then
    vim.notify('Not in a Go module (no go.mod up the tree)', vim.log.levels.WARN)
    return
  end

  local qp_actions, qp_keys = common.quick_pick_actions()

  return Snacks.picker.pick({
    source = 'go_targets',
    title = mode == 'debug' and 'Go debuggables' or 'Go runnables',
    actions = qp_actions,
    win = { input = { keys = qp_keys }, list = { keys = qp_keys } },
    -- Async finder (the pickers/symbols.lua shape): the picker window opens
    -- immediately and fills when `go list` returns. Measured: 0.05s on
    -- fixtures/, 0.4-0.6s on a 675-package module, ~3s the first time a module's
    -- deps aren't downloaded yet — all of which would be a visible freeze if
    -- this were a :wait().
    ---@async
    finder = function(_, cb_ctx)
      return function(cb)
        local async = Async.running()
        local res, obj
        async:schedule(function()
          obj = vim.system(
            -- -e: keep going past a broken package. Without it a single bad
            -- import anywhere in the module exits 1 — with every good target
            -- still on stdout. See "go list — measured" above.
            { 'go', 'list', '-e', '-f', LIST_FORMAT, './...' },
            { cwd = root, text = true },
            -- schedule_wrap: vim.system's on_exit may run in a fast event
            -- context; resuming the picker coroutine from there is not safe.
            vim.schedule_wrap(function(r) res = r; async:resume() end)
          )
        end)
        -- Don't leave a 3s `go list` running if the user escapes the picker
        -- (symbols.lua cancels its in-flight LSP requests the same way).
        async:on('abort', function()
          if obj then pcall(function() obj:kill(15) end) end
        end)
        while not res and not async:aborted() do
          async:suspend()
        end
        if not res or async:aborted() then return end

        -- Parse stdout NO MATTER the exit code: `go list` reports per-package
        -- errors on stderr and still emits the packages it did resolve. Only a
        -- run that yields zero parseable targets is a real failure.
        local found = 0
        for line in vim.gsplit(res.stdout or '', '\n', { trimempty = true }) do
          local kind, importpath, dir, ntests, first = line:match('^(.-)|(.-)|(.-)|(.-)|(.*)$')
          -- main packages only — see plans/go-targets-picker.md §3 (tests stay
          -- with neotest). ntests is parsed but unused: it's the hook for a
          -- future test group, and free to collect.
          if kind == 'main' then
            found = found + 1
            cb({
              text = importpath,              -- what the fuzzy matcher scores
              importpath = importpath,
              dir = dir,
              relpath = vim.fs.relpath(root, dir) or dir,
              ntests = tonumber(ntests) or 0,
              -- Free source preview via snacks' default file previewer
              -- (picker/config/init.lua:197-202 keys it off item.file).
              file = first ~= '' and vim.fs.joinpath(dir, first) or nil,
            })
          end
        end

        -- Nothing at all → real error (bad module, go missing). Something, but
        -- go list also complained → the module has a broken package somewhere;
        -- say so, but still show the targets that did resolve.
        if found == 0 then
          vim.schedule(function()
            vim.notify('go list found no main packages\n' .. (res.stderr or ''), vim.log.levels.ERROR)
          end)
        elseif res.code ~= 0 then
          vim.schedule(function()
            vim.notify('go list reported errors (showing what resolved):\n' .. (res.stderr or ''),
              vim.log.levels.WARN)
          end)
        end
      end
    end,
    format = function(item, picker)
      local ret = {} ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      ret[#ret + 1] = { '󰟓 ', 'SnacksPickerIcon' }
      ret[#ret + 1] = { Snacks.picker.util.align(item.importpath, 50, { truncate = true }) }
      ret[#ret + 1] = { '  ' }
      ret[#ret + 1] = { item.relpath, 'Comment' }
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      -- Close first, then launch on the next tick: dap-ui / toggleterm both
      -- open windows, and doing that while the picker's floats are still up
      -- lands the new window in the wrong place (same close-then-schedule dance
      -- snacks' own ui_select uses, picker/select.lua:56-63).
      vim.schedule(function()
        if mode == 'debug' then
          debug_target(item, root)
        else
          run_target(item, root)
        end
      end)
    end,
  })
end

return M
```

Notes on the sketch:

- `vim.fs.relpath` and `vim.fs.root` are both present on this machine's Neovim
  (checked: `0.12.4`, both non-nil).
- No args prompt on either action (v1). Rust's `<leader>cR` has none either;
  args stay available through dap-go's **Debug (Arguments)** on `<F5>` and
  through a terminal for `go run`. Revisit only if it bites.

### 2. `lua/golang.lua` — new: the Go language module

```lua
-- golang.lua — Go's language module: the delve adapter registration plus the
-- buffer-local Go keymaps. The mirror of rust.lua (which owns rustaceanvim +
-- the Rust ft keymaps), so debugging.lua can stay a generic engine.
--
-- Named golang.lua, NOT go.lua: `require('go')` is ray-x/go.nvim's module name,
-- and that plugin is a live follow-up (plans/go-run-debug-test.md). Same rule as
-- debugging.lua-not-dap.lua. Editing/formatting/linting for Go stay where they
-- are (gopls in lsp.lua, goimports in format.lua, golangci-lint in linting.lua).

-- pcall-guarded: nvim-dap-go publishes no git tags, so it tracks main and can
-- break under us. init.lua wraps nothing, so an uncaught throw here would abort
-- every module after it.
local dap_ok = pcall(function()
  vim.cmd.packadd('nvim-dap-go')
  require('dap-go').setup()  -- dap.adapters.go + 7 dap.configurations.go
end)

if not dap_ok then
  vim.notify('nvim-dap-go failed to load — Go debugging disabled', vim.log.levels.WARN)
end

-- NOTE: no early `return` on dap_ok. <leader>cR (run in a terminal) has nothing
-- to do with dap, so a broken nvim-dap-go must not take it down with it — only
-- <leader>dR is gated below.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  group = vim.api.nvim_create_augroup('UserGoKeys', { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    -- Deliberately the same two keys Rust binds in rust.lua, with the same
    -- meanings: dR = pick a target and debug it, cR = pick a target and run it.
    if dap_ok then
      map('<leader>dR', function() require('pickers.gotargets').open('debug') end,
        'Debug: Go debuggables')
    end
    map('<leader>cR', function() require('pickers.gotargets').open('run') end,
      'Go: Runnables (run)')
  end,
})
```

Note the picker is `require`d **inside** the keymap callback, so `go list`, the
picker, and toggleterm cost nothing until the key is pressed.

### 3. `lua/debugging.lua` — hand the Go block to `golang.lua`

Delete `debugging.lua:23-55` (the pcall'd `dap-go` packadd/setup, the
`UserGoDebug` autocmd mapping `<leader>dR` → `dap.continue()`, and the `else`
notify). Update the header comment at `debugging.lua:9-13` back to "adapters and
configurations come from the language modules (`rust.lua`, `golang.lua`)".

The keymaps, signs, and dap-ui listeners below are untouched; `<F5>` /
`<leader>dc` keep opening dap-go's seven-config picker exactly as today.

### 3b. Stale references the move creates (grep before committing)

Moving `dap-go.setup()` out of `debugging.lua` falsifies three places that name
it. Per the repo's "grep for stale references" rule these are part of the change,
not follow-ups:

- `lua/testing.lua:43` — the comment `type = 'go', -- the adapter dap-go registered in debugging.lua`
- `GUIDE.md:76` — `debugging.lua`'s Architecture bullet, which says it "Also sets
  up nvim-dap-go (the delve adapter + Go launch configs)". That clause moves to a
  new `golang.lua` bullet.
- `GUIDE.md:2319` — "`require('dap-go').setup()` (called once, in `debugging.lua`)".

### 4. `init.lua` — one new `require`

```lua
require('rust')       -- rustaceanvim (must precede testing: provides rustaceanvim.neotest)
require('debugging')  -- nvim-dap + dap-ui
require('golang')     -- nvim-dap-go (delve adapter) + Go ft keymaps  <-- new
require('testing')    -- neotest
```

`golang` **must** come after `debugging`: `require('dap-go').setup()` calls
`require('dap')` and mutates `dap.adapters` / `dap.configurations`
(`dap-go.lua:186-193`), so nvim-dap has to be on the runtimepath first —
`debugging.lua:15-17` is what `packadd`s it. It must come *before* nothing —
`testing.lua`'s neotest-golang adapter never requires the `dap-go` module (it
runs `dap_mode = 'manual'`), it only needs `dap.adapters.go` to exist by the
time a test is debugged. Placing it between `debugging` and `testing` is the
conservative order.

### 5. `lua/whichkey.lua` — aliases and tags

These are **two separate tables** in `lua/whichkey.lua` — `keywords` (~line 108)
and `tags` (~line 131). Do not paste them into one literal; each key must appear
once per table.

```lua
-- in `keywords` (feeds the <leader>sk fuzzy picker)
['<leader>dR'] = 'debug rust debuggables rustaceanvim go delve targets packages main picker',
['<leader>cR'] = 'run rust runnables cargo rustaceanvim go targets packages main picker',
```

```lua
-- in `tags` (preserve the existing inline comment on the <leader>dR entry)
['<leader>cR'] = { 'rust', 'go', 'run' },
['<leader>dR'] = { 'rust', 'go' },   -- was { 'rust' }
```

No new group, no new prefix — both keys already exist.

### 6. `GUIDE.md` — four edits

Per `nvim/.config/nvim/CLAUDE.md` (new module → Architecture entry + Load order;
new keymap → the owning feature's table; keymap ownership = one mapping, one
table):

1. **`Architecture` → `File responsibilities`** (bullet list, ~line 58): add
   `golang.lua` (delve adapter + Go ft keymaps) and `pickers/gotargets.lua`
   (`go list` → snacks → delve/`go run`). Extend the **`Load order`** line
   (~line 114) with `golang` between `debugging` and `testing`, and say why
   (needs nvim-dap on the rtp).
2. **`Keymap index` → `By prefix`** (line ~642): the row
   `` `<leader>c*` (Rust ft), `K` (Rust ft) | Rust actions | rust.lua ``
   becomes two rows, or gains a Go sibling row —
   `` `<leader>cR`/`<leader>dR` (Go ft) | Go run/debug targets | golang.lua | [Go](#go) → Keymaps ``.
   (`<leader>d*` / `<leader>n*` rows are unchanged — those are still global.)
3. **`## Debugging (nvim-dap)` → Language support** (line ~2072): the Go row's
   "Cold-start entry point" stays `<leader>dR` but the meaning changes. **Delete
   the paragraph** beginning *"**`<leader>dR` is the 'start a session by picking
   one' key in both languages**… Same gesture, different list — Go has no target
   provider…"* and replace it with the now-true version: both languages
   enumerate real targets (rust-analyzer for Rust, `go list` for Go); `<F5>` /
   `<leader>dc` remains the raw-config path in Go. Also update the "Supplied by"
   cell for Go from `nvim-dap-go (debugging.lua)` → `nvim-dap-go (golang.lua)`,
   and the **Extending DAP** recipe's parenthetical ("Go's `nvim-dap-go` call
   lives directly in `debugging.lua` since Go has no other language module to
   own it") — it now does.
4. **`## Go (delve + neotest)`** (line ~2295): the section takes the brunt.
   - Rewrite the *"There's no dedicated `go.lua`"* paragraph — there is now a
     `golang.lua`; keep the naming rationale (go.nvim would shadow `go.lua`).
   - The *Common workflows* bullets already describe the configs accurately
     (`Debug` = `${file}`, `Debug Package` = `${fileDirname}`), and the paragraph
     below them already states that none of them can launch a `main` you aren't
     sitting in, pointing here. Keep both; just delete the forward-reference to
     this plan once it has shipped.
   - Rewrite **"Debug a program (not a test)"** around the targets picker:
     `<leader>dR` → pick a `main` package (any package in the module, from any
     buffer) → delve builds and launches it. Keep the seven-config list, but
     move it under `<F5>`/`<leader>dc` where it now belongs, with the honest
     framing: those are *tools* (attach, args, build flags, raw test), not
     targets.
   - Add **"Run a program"** (mirrors Rust's "Running a program"): `<leader>cR`
     → pick a `main` package → `go run <import-path>` in a float terminal from
     the module root; `<leader>Tb` + a shell for anything needing args.
   - Add a **Keymaps** table to the Go section (buffer-local, `go` filetype —
     the exact shape of Rust's):

     | Keymap | Action |
     |---|---|
     | `<leader>dR` | Debuggables — pick a `main` package, debug it under delve |
     | `<leader>cR` | Runnables — pick a `main` package, `go run` it in a terminal |

     The same two *keys* appear in Rust's table, which brushes against the
     "never document the same key in two tables" rule — resolved in §6b below,
     by amending the rule rather than asserting an exception to it.
   - Extend **"You need a `go.mod`"** with the picker's behavior: no module →
     one WARN, no picker (and no misleading fallback).
   - Note the enumeration's blind spots in one line: nested modules are not
     descended into (open a file in that module instead) and build-tag-excluded
     packages don't appear.
5. **`## Picker (snacks.nvim)`** — if its section lists the custom pickers under
   `pickers/`, add `gotargets.lua` to that list (check at implementation time;
   `pickers/theme.lua` and `pickers/keybindings.lua` are the precedent).

### 6b. `nvim/.config/nvim/CLAUDE.md` — amend the keymap-ownership rule

The Go Keymaps table puts `<leader>dR` and `<leader>cR` in a second table, while
Rust's table already lists the same two *keys*. That reads as a violation of
"**Never document the same key in two tables**" — and the honest move is to amend
the rule, not to assert an exception inside a plan nobody will re-read.

These are genuinely *different mappings*: buffer-local to different filetypes,
bound by different modules, doing different things. The rule exists to stop one
mapping from being documented — and going stale — in two places, which this does
not do. So amend `nvim/.config/nvim/CLAUDE.md` → "Keymap ownership rule" to read:
one **mapping**, one table; a key bound buffer-locally by several language modules
is documented once **per language section**, and never in the shared/global
tables. Do it in the same commit as the Go table — a convention amended after the
fact is a convention nobody trusts.

### 7. `README.md` — no change

No new binary, no new stow package, no new machine setup: `go` (already a
documented prerequisite under `## Languages`) and `dlv` (already installed by
Mason) are the entire dependency set. Per the repo `CLAUDE.md` rule, this was
checked, not assumed — the fresh-machine bootstrap path is unchanged.

---

## Files touched

| File | Change |
|---|---|
| `lua/pickers/gotargets.lua` | **new** — `go list` enumerator, async snacks picker, `dap.run` + toggleterm launchers |
| `lua/golang.lua` | **new** — pcall'd `dap-go` setup (moved) + `FileType go` keymaps (`<leader>dR`, `<leader>cR`) |
| `lua/debugging.lua` | −23 lines: the Go block moves out; header comment back to "engine only" |
| `init.lua` | +`require('golang')`, after `debugging`, before `testing` |
| `lua/whichkey.lua` | widen `<leader>dR` / `<leader>cR` keyword aliases + tags |
| `GUIDE.md` | Architecture + Load order; `By prefix` row; Debugging → Language support (delete the "no target provider" paragraph); Go section (new Keymaps table, run/debug workflows) |
| `lua/testing.lua` | comment fix only (`:43` names `debugging.lua` as dap-go's home) |
| `nvim/.config/nvim/CLAUDE.md` | amend the keymap-ownership rule for per-filetype tables (§6b) |
| `README.md` | none (verified: no new setup step) |

No new plugin, no `nvim-pack-lock.json` change, no Mason addition.

## Commits

Per-change commits with a `Part-of: go targets picker` trailer:

1. `refactor(nvim): give Go its own language module` — `golang.lua` +
   `debugging.lua` + `init.lua` + the `testing.lua` comment. **Behavior-identical:**
   this commit's `golang.lua` carries the *existing* `<leader>dR` →
   `dap.continue()` mapping verbatim (commit 2 replaces it), so the move is a move
   and reviewable as one.
2. `feat(nvim): add a Go run/debug targets picker` — `pickers/gotargets.lua`, the
   two keymaps in `golang.lua` (replacing the `dap.continue()` one), `whichkey.lua`.
3. `docs(nvim): document the Go targets picker` — `GUIDE.md` + the
   `CLAUDE.md` keymap-ownership amendment.

## Verification

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
- **toggleterm float reuse.** `run_term:shutdown()` on a second run kills a still-
  running program without asking. That is the intended edit-run loop behavior
  (and matches how most run integrations behave), but it means `<leader>cR` twice
  in a row silently drops the first process. If that bites, switch to a
  count-addressed terminal id instead of a single shared one.
- **The `format` icon** (`󰟓`, nf-md-language_go) assumes a Nerd Font, which this
  config already requires everywhere (`pickers/symbols.lua:110-138` does the
  same). Fine, but don't put it in a GUIDE table cell — the repo `CLAUDE.md`'s
  no-emoji-in-table-cells rule exists because render-markdown breaks column
  alignment on variable-width glyphs.

## Alternatives considered

### Keep `<leader>dR` = `dap.continue()` and put targets on a new key (e.g. `<leader>dT`)

Rejected. It preserves a mapping whose only purpose is to be a *worse alias* of
`<F5>` — the GUIDE already has to explain why the Go and Rust `<leader>dR` do
different things. A third key would make the muscle-memory story worse, not
better, and nothing is lost by demoting the seven configs to the engine key that
already opens them.

### Add test packages to the picker (or a second `<leader>nT` "debug package tests")

Deferred, with the enumeration already collecting `len .TestGoFiles` so it stays
a ~10-line change. neotest owns tests at function granularity and does it better;
a package-granularity test debug is a coarse tool that would double the list
length to serve a rare case that dap-go's **Debug test (go.mod)** already covers.

### `gopls`'s `workspace/symbol` or a codelens instead of `go list`

gopls exposes no "runnables" request — the Go LSP has no equivalent of
rust-analyzer's `experimental/runnables`, which is exactly why this gap exists in
the first place. `go list` is the only complete enumerator, and at 0.05-0.6s it's
fast enough to run per-invocation.

### Blocking `vim.system():wait()` and `Snacks.picker.pick({ items = ... })`

Simpler by ~15 lines (no `Async`, no streaming finder) and tempting given
`gitui.lua:94` already does a blocking `:wait()` for `git remote show origin`.
Rejected on the measurements: that git call is a one-off at startup, whereas this
is an interactive gesture, and 0.4-0.6s (let alone 2.9s) of frozen editor on
every press is exactly the kind of papercut this config removes elsewhere. The
async finder pattern is already proven in-repo (`pickers/symbols.lua`), so the
cost is copying a known-good shape, not inventing one.

### `lua/go.lua` instead of `lua/golang.lua`

Rejected: `require('go')` is ray-x/go.nvim's module name, and that plugin remains
a live follow-up in `plans/go-run-debug-test.md` (which already reserved the name
`golang.lua` for exactly this reason). The repo convention —
`debugging.lua`-not-`dap.lua`, `gitui.lua`-not-`neogit.lua` — is to never take a
name a plugin owns, even when the plugin isn't installed *yet*.

### Everything in one `golang.lua` (no `pickers/gotargets.lua`)

Viable — the whole feature is ~180 lines. Rejected for consistency: every custom
snacks picker in this config lives in `pickers/` and is called as
`require('pickers.<x>').open()` from a keymap. Splitting also keeps `golang.lua`
readable as what it is (adapter registration + two keymaps) and keeps the picker
lazily required until the key is actually pressed.

### ray-x/go.nvim for the run layer (`:GoRun`)

Still cut, and now for a second reason. `plans/go-run-debug-test.md` cut it
because integrating it is a list of negations (`lsp_cfg = false`,
`dap_debug = false`, `lsp_document_formatting = false`, …) to stop it owning
gopls, DAP, and formatting. With this plan, its remaining draw — `:GoRun
./cmd/foo` — is delivered by 15 lines of toggleterm, with a *picker* instead of a
typed path. There is nothing left worth the plugin.
