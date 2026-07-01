# Go run / debug / test in Neovim (hybrid: go.nvim + generic dap/neotest)

## Context

We added Rust run/debug/test to the Neovim config (`~/.config/nvim`, Stow source at `/Users/dhruv/src/dotfiles/nvim/.config/nvim/`) via rustaceanvim + nvim-dap + nvim-dap-ui + neotest, committed as `db39cfb`. This plan does the same for **Go**.

**Chosen approach — hybrid:** go.nvim provides the run/build/imports/code-action *commands* (the rustaceanvim-style Go layer that fills gopls's missing "run" story), while **debugging and testing reuse the generic infra already built** — nvim-dap + dap-ui via **nvim-dap-go**, and neotest via **neotest-golang**. go.nvim is configured to NOT touch LSP, DAP, or formatting, so it doesn't fight the existing gopls config, nvim-dap-go, or conform.nvim.

What already exists and is reused unchanged: gopls (`lsp.lua:282`, configured + enabled), the whole `debugging.lua` engine + `<leader>d*`/`<F5>`–`<F12>` keymaps, neotest + `<leader>n*` keymaps, conform.nvim formatting (goimports on save), `goimports`/`golangci-lint` tooling, the `go` treesitter parser.

External APIs verified against current upstream (July 2026), incl. an adversarial review and direct source reads of go.nvim:
- **go.nvim** (`ray-x/go.nvim`, module `go`): `require('go').setup(opts)`. Hybrid knobs confirmed in `lua/go.lua` default_config: `lsp_cfg=false` (skip its gopls), `lsp_keymaps=false`, `lsp_codelens=false`, `lsp_inlay_hints={enable=false}`, `dap_debug=false` (skip its dap), `lsp_document_formatting=false` (conform owns formatting). Format-on-save is opt-in (a BufWritePre autocmd you add yourself) — not default, so no conflict. Commands (from `lua/go/commands.lua`): `:GoRun` (`nargs='*'` — takes args, so `:GoRun ./cmd/foo` handles any layout), `:GoBuild`, `:GoImports`, `:GoCodeAction` (range), `:GoCodeLenAct`. Requires Neovim 0.12 (satisfied). `guihua.lua` is **optional** — our four commands work without it (`:GoCodeAction` falls back to `vim.ui.select`, which this config routes to telescope). Source: https://github.com/ray-x/go.nvim (`lua/go.lua`, `lua/go/commands.lua`)
- **nvim-dap-go** (`leoluz/nvim-dap-go`, module `dap-go`): `require('dap-go').setup()` registers `dap.adapters.go` + `dap.configurations.go`; `dap.continue()` in a Go buffer picks among them. Needs nvim-dap first. delve `path` defaults to `"dlv"`. Source: https://github.com/leoluz/nvim-dap-go
- **neotest-golang** (`fredrikaverpil/neotest-golang`): instantiated as a **function call** `require('neotest-golang')(opts)` (bare table misbehaves). DAP test-debug is on by default (`dap_mode="dap-go"`; `dap_go_enabled` no longer exists). Default `go_test_args` includes `-race` (needs cgo + C compiler; Xcode CLT covers it). Sources: https://fredrikaverpil.github.io/neotest-golang/config/, https://raw.githubusercontent.com/fredrikaverpil/neotest-golang/main/lua/neotest-golang/options.lua
- **delve**: Mason package `delve` (exe `dlv`), built from source via `go install` (Go toolchain already present); found on Mason's PATH-prepended bin. Source: https://mason-registry.dev/registry/list

---

## Changes

### 1. New module `lua/golang.lua`

**Named `golang.lua`, NOT `go.lua`** — go.nvim's own module is `go`, so a `lua/go.lua` in the config would shadow the plugin (`require('go')` would load our file instead of go.nvim). Same shadowing rule as `linting.lua`-not-`lint.lua` and `debugging.lua`-not-`dap.lua`.

Loads lazily on the first Go buffer (mirrors rustaceanvim's ftplugin laziness — non-Go sessions pay nothing), sets up go.nvim (hybrid) + dap-go, and registers buffer-local Go keymaps.

```lua
-- Go tooling. HYBRID: go.nvim supplies the run/build/imports/code-action commands
-- (the rustaceanvim-style layer), while debugging + testing reuse the generic
-- nvim-dap/dap-ui (debugging.lua) and neotest (testing.lua) via nvim-dap-go and
-- neotest-golang. go.nvim is told NOT to touch LSP / DAP / formatting so it doesn't
-- fight the existing gopls, nvim-dap-go, and conform.nvim setups.
--
-- Named golang.lua: go.nvim's Lua module is `go`, so naming this file go.lua would
-- shadow the plugin. Loaded lazily on the first Go buffer; dap-go needs nvim-dap
-- (debugging.lua), always loaded earlier.

local setup_done = false

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  group = vim.api.nvim_create_augroup('UserGo', { clear = true }),
  callback = function(ev)
    if not setup_done then
      vim.cmd.packadd('go.nvim')
      require('go').setup({
        lsp_cfg = false,                     -- keep our own gopls (lsp.lua)
        lsp_keymaps = false,                 -- our LspAttach owns keymaps
        lsp_codelens = false,                -- we use native vim.lsp.codelens
        lsp_inlay_hints = { enable = false },  -- gopls config already does hints
        lsp_document_formatting = false,     -- conform.nvim owns formatting
        dap_debug = false,                   -- use nvim-dap-go, not go.nvim's dap
        luasnip = false,
      })

      vim.cmd.packadd('nvim-dap-go')
      require('dap-go').setup()              -- delve via Mason's PATH bin (dlv)
      setup_done = true
    end

    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    -- Run/build/imports/code-action via go.nvim (parallel to Rust's <leader>cR etc.)
    map('<leader>cR', '<cmd>GoRun<cr>',        'Go: Run (go run)')
    map('<leader>cb', '<cmd>GoBuild<cr>',      'Go: Build')
    -- guihua.lua is omitted (optional dep), so :GoCodeAction falls back to
    -- vim.ui.select — which this config routes to telescope. Add ray-x/guihua.lua
    -- to plugins.lua later if you want go.nvim's richer floating-menu UI (or any
    -- go.nvim feature that requires guihua).
    map('<leader>ca', '<cmd>GoCodeAction<cr>', 'Go: Code action')   -- buffer-local override, like Rust
    map('<leader>ci', '<cmd>GoImports<cr>',    'Go: Organize imports')
    -- Program debug: generic <leader>dc / <F5> (dap.continue lists dap-go configs).
    -- Test debug: generic <leader>nd (neotest strategy='dap' -> dap-go). No extra maps.
  end,
})
```

Keymap rationale:
- `:GoRun` **accepts args** (`:GoRun ./cmd/foo`), so it beats a hand-rolled `go run .` — no `cmd/` layout papercut.
- `<leader>ca` is overridden buffer-locally to `:GoCodeAction` (Go-specific actions), exactly like Rust overrides it to `RustLsp('codeAction')`.
- Program debugging = generic `<leader>dc`/`<F5>`; test debugging = generic `<leader>nd`. No Go-specific debug maps (would duplicate the generic ones).
- `:GoImports` is a convenience; conform already runs goimports on save, so it's for on-demand use.

### 2. `lua/plugins.lua` — add three plugins (in the "Rust / Debug / Test" block, ~line 53-61)

```lua
{ src = gh('ray-x/go.nvim') },
{ src = gh('leoluz/nvim-dap-go') },
{ src = gh('fredrikaverpil/neotest-golang') },
```

No version pins. `guihua.lua` is intentionally omitted (optional; our commands don't need it). None need a build hook.

### 3. `lua/lsp.lua` — add delve to mason-tool-installer `ensure_installed` (~line 29-40, next to `codelldb`)

```lua
'delve',  -- go debug adapter (dlv; consumed by nvim-dap via nvim-dap-go)
```

gopls config unchanged.

### 4. `lua/testing.lua` — add the neotest-golang adapter

`packadd` near the other packadds, and add to the `adapters` list **as a function call** (replacing the commented `require('neotest-golang')` example ~line 18):

```lua
vim.cmd.packadd('neotest-golang')   -- with the other packadds at top
...
adapters = {
  require('rustaceanvim.neotest'),
  require('neotest-golang')({}),    -- FUNCTION CALL; dap_mode defaults to "dap-go"
},
```

### 5. `init.lua` — load `require('golang')` after debugging

```lua
require('rust')       -- rustaceanvim (must precede testing)
require('debugging')  -- nvim-dap + dap-ui
require('golang')     -- go.nvim (hybrid) + nvim-dap-go; after debugging for dap
require('testing')    -- neotest (+ rust + go adapters)
```

Only "after `debugging`" matters (dap must exist when `dap-go.setup()` runs — and with lazy setup that's on first Go buffer anyway). Before `testing` is tidy grouping, not required.

### 6. `lua/whichkey.lua` — widen keyword aliases (no new group)

```lua
['<leader>cR'] = 'rust runnables run cargo rustaceanvim go gorun program main',
['<leader>cb'] = 'go build gobuild compile',
['<leader>ci'] = 'go imports goimports organize',
['<leader>nd'] = 'neotest debug test dap nearest go delve rust',
```

### 7. `GUIDE.md` — doc parity (concise Go section)

Add `## Go (go.nvim + gopls + DAP + neotest)` mirroring the Rust section: the hybrid split (go.nvim for commands; generic dap/neotest for debug/test), running (`<leader>cR`/`:GoRun`, incl. `:GoRun ./cmd/foo`), building (`<leader>cb`), debugging (`<leader>dc`), testing (`<leader>nn`/`<leader>nd`), a keymap table, and troubleshooting (delve on PATH; `-race` needs cgo/Xcode CLT). Add a `golang.lua` row to the File-responsibilities table and update the Load-order line to `... debugging -> golang -> testing ...`.

---

## Files touched

| File | Change |
|---|---|
| `lua/golang.lua` | **new** — lazy go.nvim (hybrid) + nvim-dap-go setup + buffer-local Go keymaps |
| `lua/plugins.lua` | +3 `vim.pack` entries (go.nvim, nvim-dap-go, neotest-golang) |
| `lua/lsp.lua` | +`delve` in mason-tool-installer `ensure_installed` |
| `lua/testing.lua` | +`packadd` + `require('neotest-golang')({})` in adapters |
| `init.lua` | +`require('golang')` after debugging |
| `lua/whichkey.lua` | widen keyword aliases (`<leader>cR`/`cb`/`ci`/`nd`) |
| `GUIDE.md` | Go section + File-responsibilities row + Load-order line |

Paths under `/Users/dhruv/src/dotfiles/nvim/.config/nvim/` (Stow source; live via the `~/.config/nvim` symlink).

---

## Verification

Scratch Go module (`~/tmp/gdemo/`: `go mod init demo`, a `main.go` printing a var, a `main_test.go` with one `TestX`):

1. **Install:** restart nvim — `vim.pack` installs go.nvim + nvim-dap-go + neotest-golang; `:Mason`/`:MasonToolsInstall` builds `delve`. `:!which dlv` → `~/.local/share/nvim/mason/bin/dlv`.
2. **No shadow / single gopls:** open a `.go` file; `:checkhealth vim.lsp` shows exactly one gopls client (go.nvim didn't add a second — `lsp_cfg=false` worked). `:lua= require('go')` resolves to the plugin, not our module (proves `golang.lua` naming avoided the shadow).
3. **delve sanity (macOS):** run `dlv debug` once from the scratch module in a shell before trusting `<leader>dc`.
4. **Adapter registered:** `:lua= require('dap').configurations.go` lists dap-go's entries; `:checkhealth dap` shows the go adapter.
5. **Run/build:** `<leader>cR` (or `:GoRun`) runs the package; `:GoRun ./...`/args work; `<leader>cb` builds.
6. **Program debug:** breakpoint in `main()` (`<leader>db`/`<F9>`), `<leader>dc` → pick "Debug" → stops at breakpoint, dap-ui auto-opens; step `<F10>`/`<F11>`/`<F12>`.
7. **Test run/debug:** `<leader>nn`/`<leader>nf` run tests (neotest signs + `<leader>ns` summary); breakpoint + `<leader>nd` debugs via delve.
8. **Formatting unchanged:** save a Go file — conform's goimports runs, and go.nvim does NOT double-format (no BufWritePre added, `lsp_document_formatting=false`).
9. **Clean load:** `:messages` / `:Notifications` — no errors, no orphan-plugin warning.

## Risks / gotchas

- **Module name:** must be `golang.lua` (not `go.lua`) or it shadows go.nvim's `go` module — breaking `require('go').setup()`.
- **go.nvim must stay out of LSP/DAP/format:** the `lsp_cfg=false` / `dap_debug=false` / `lsp_document_formatting=false` (and `lsp_keymaps`/`lsp_codelens`/`lsp_inlay_hints`) knobs are load-bearing for the hybrid — without them go.nvim double-configures gopls, adds its own dap keymaps, and can auto-format, fighting the existing setup.
- **neotest-golang must be invoked:** `require('neotest-golang')({})`, not the bare table. `dap_go_enabled` is obsolete — don't use it.
- **Load order:** `require('golang')` after `require('debugging')`.
- **delve on PATH / macOS:** relies on Mason's PATH-prepend; if `dlv` isn't found set `require('dap-go').setup({ delve = { path = vim.fn.expand('~/.local/share/nvim/mason/bin/dlv') } })`. delve may need one-time developer-mode auth on macOS (verify with a CLI `dlv debug`).
- **`-race` test default:** neotest-golang runs `-race` (needs cgo + C compiler; Xcode CLT covers it). Override `go_test_args` in `testing.lua` if it errors or is slow.
- **guihua omitted:** `:GoCodeAction` uses `vim.ui.select` (telescope) instead of guihua's float. Add `ray-x/guihua.lua` later if you want the richer UI or go.nvim features that need it.

Rollback is clean: delete `golang.lua`, revert the 6 edits; delve/plugins are separately managed (Mason / vim.pack), no orphan cleanup needed.

---

## Alternatives considered

Two approaches were weighed for the "run"/commands layer. We chose **Option A (hybrid, above)**. Option B is recorded here in case the go.nvim dependency proves undesirable later.

### Option A — Hybrid with go.nvim (CHOSEN)

go.nvim supplies `:GoRun`/`:GoBuild`/`:GoImports`/`:GoCodeAction`; debug/test reuse nvim-dap-go + neotest-golang. Detailed above.

- **Pros:** real run/build/imports/code-action commands (the true rustaceanvim parallel); `:GoRun` takes args (`:GoRun ./cmd/foo`) so any project layout works; Go-specific code actions via `<leader>ca`.
- **Cons:** pulls in a large, opinionated plugin (go.nvim); requires the `lsp_cfg=false`/`dap_debug=false`/`lsp_document_formatting=false` knobs to keep it from fighting the existing gopls/dap/conform setup; `golang.lua` naming needed to avoid shadowing go.nvim's `go` module.

### Option B — Minimal, hand-rolled run (NOT chosen)

Skip go.nvim entirely. Keep only **nvim-dap-go** (debug) + **neotest-golang** (test), and hand-roll the run keymap. Everything else (plugins.lua adds 2 not 3 plugins, delve, testing.lua adapter, init.lua, whichkey) is the same; the module is `lua/go.lua` (no go.nvim to shadow, so `go.lua` is safe here).

`lua/go.lua` (run keymap only, reusing one toggleterm to avoid stacking splits):

```lua
local setup_done = false
local run_term  -- single reused run terminal

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  group = vim.api.nvim_create_augroup('UserGo', { clear = true }),
  callback = function(ev)
    if not setup_done then
      vim.cmd.packadd('nvim-dap-go')
      require('dap-go').setup()
      setup_done = true
    end
    vim.keymap.set('n', '<leader>cR', function()
      if run_term then pcall(function() run_term:shutdown() end) end
      run_term = require('toggleterm.terminal').Terminal:new({
        cmd = 'go run .', dir = vim.fn.expand('%:p:h'),
        direction = 'horizontal', close_on_exit = false,
      })
      run_term:open()
    end, { buffer = ev.buf, desc = 'Go: Run (go run .)' })
  end,
})
```

- **Pros:** leanest — one fewer heavy plugin; no gopls/dap/format coexistence config; no module-shadow concern.
- **Cons:** no `:GoBuild`/`:GoImports`/code-action niceties; `go run .` runs the buffer's directory only — it fails for library files and doesn't handle a `cmd/foo/` main (no args like `:GoRun`); the run keymap must manually manage a reused terminal to avoid stacking splits.

**Why A over B:** parity with the Rust setup and a real "run" story were the goals; go.nvim is the ecosystem's rustaceanvim-equivalent and `:GoRun`'s arg support removes the `cmd/` papercut. B remains a clean fallback if go.nvim ever feels too heavy.
