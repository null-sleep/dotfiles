# RustRover → nvim parity research

**Status:** partially shipped (2026-07-17) — SSR, batch clippy-fix, and the
actions-preview.nvim diff-preview code actions landed; everything else
below still research / not started.
**Date:** 2026-07-17

Follow-up to installing RustRover ([README → RustRover](../README.md#rustrover))
and comparing it against this repo's existing Rust setup (`rustaceanvim` +
`rust-analyzer`, see `nvim/.config/nvim/lua/rust.lua`). Five parallel research
passes (one per capability area) on how much of RustRover's edge can be
closed in Neovim, and what's a genuine, protocol-level gap. Most of it is
still just research — see the Status line above for what's shipped.

---

> Shrunk 2026-07-18: shipped-work narrative in §1/§2 compressed to stubs
> (GUIDE.md owns the shipped docs; full narrative in git history).

## Current state (for gap reference)

Already in this config:

- `rustaceanvim` (pinned `^9`) wired to `~/.cargo/bin/rust-analyzer` (the
  rustup proxy, not Mason's copy), `checkOnSave` via clippy, `:RustLsp`
  keymaps for hover-actions/code-action/runnables/expand-macro/debuggables
  (`rust.lua`).
- `nvim-dap` + `nvim-dap-ui`, auto-wired to Mason's codelldb via
  rustaceanvim's `dap = {}`.
- `diffview.nvim` + `neogit` for git; `aerial.nvim` for outline; `snacks.image`
  (imagemagick backend) already renders SVG/PDF/math, and Mermaid via the
  `mmdr`/`mmdc` shim (avoids mermaid-cli's Chromium dependency).
- **Not present:** any SSR/ast-grep tool, a DB client, an HTTP client, a
  coverage plugin, or a batch/project-wide diagnostics panel (no
  `trouble.nvim` or similar).

---

## Findings by area

### 1. Already there, just needs wiring — SHIPPED 2026-07-17

**Structural search & replace** — shipped as `<leader>cs` (`rust.lua`), a thin
wrapper over rust-analyzer's semantic `:RustLsp ssr` (name-resolution-aware —
in that respect stronger than RustRover's). See GUIDE.md → Rust → "Structural
search & replace (SSR)". Syntactic / multi-language runners-up if ever wanted:
`ast-grep` (+ `grug-far.nvim` for a UI) or `cshuaimin/ssr.nvim`
(treesitter-only; its own docs say prefer the LSP version).

**Batch clippy fixes** — shipped as `<leader>cF` (`rust.lua`): `cargo clippy
--fix --workspace --allow-dirty --allow-staged` in a floating terminal (fixed
id 102) from the nearest `Cargo.toml`. See GUIDE.md → Rust → "Batch-fixing
clippy lints". Full shipped narrative for both: git history.

Separately, rust-analyzer's `checkOnSave` already runs `cargo clippy
--workspace` and publishes diagnostics for the **whole project**, not just
open buffers (flycheck is workspace-scoped by design, confirmed via
[rust-analyzer#12882](https://github.com/rust-lang/rust-analyzer/issues/12882)) —
the diagnostics already exist, there's just no panel surfacing them yet.
**Not shipped** — still open if a project-wide diagnostics panel is wanted:

- Add [`artemave/workspace-diagnostics.nvim`](https://github.com/artemave/workspace-diagnostics.nvim)
  to force-load every project file so diagnostics populate for unopened
  files too, and `folke/trouble.nvim` for the panel/navigation UI.
- Caveat: `trouble.nvim`'s "workspace diagnostics" mode only shows
  diagnostics for buffers the LSP has already reported on — confirmed by
  the maintainer in
  [discussion #574](https://github.com/folke/trouble.nvim/discussions/574) /
  [issue #26](https://github.com/folke/trouble.nvim/issues/26) — it doesn't
  itself trigger a project-wide scan. `workspace-diagnostics.nvim` is what
  does that part.
- No plugin does generic "bulk-apply this one LSP code action everywhere in
  the project" (RustRover's inspection-agnostic batch fix) — `clippy --fix`
  is the de-facto bulk tool for Rust specifically, and covers the common
  case.

### 2. Extract/inline refactors — mostly there, add a preview UI — SHIPPED 2026-07-17

rust-analyzer already exposes the whole extract/inline family as LSP code
actions (extract assists need a visual selection — why they can look
"missing"); `:RustLsp codeAction` renders the *grouped* assists. The missing
diff-preview-before-apply shipped as `actions-preview.nvim`
(`backend = { 'snacks' }`, `lsp.lua`): `<leader>ca` keeps the grouped picker,
`<leader>cp` adds the flat list with preview. See GUIDE.md → LSP, → Rust →
"Code action preview", and → Design Decisions → "Rust keymaps fire on
LspAttach, not FileType" (the latent-bug record found along the way).
(Alternative not taken: `tiny-code-action.nvim`; `nvim-code-action-menu` is
unmaintained — skip.) There is **no first-class "change signature"** assist
in rust-analyzer — see genuine gaps below.

### 3. Debugger visuals — mostly there, rougher UX

nvim-dap-ui already gives a real scopes tree (nested structs/enums/`Vec`/
`HashMap` expand/collapse with `<CR>`, same interaction model as RustRover).
Weak point is pretty-printing quality under LLDB, not the tree — enums with
data, `String`, `Box`/`Rc`/`Arc`, and trait objects can render as raw
internals rather than clean summaries. Setting `sourceLanguages = ["rust"]`
in the launch config improves this but doesn't fully close it.

To close the visual gap:

- [`theHamsta/nvim-dap-virtual-text`](https://github.com/theHamsta/nvim-dap-virtual-text) —
  inline values next to code, RustRover-style.
- [`igorlfs/nvim-dap-view`](https://github.com/igorlfs/nvim-dap-view) — newer
  (2025/26), increasingly the recommended alternative to nvim-dap-ui: single
  toggled window, inline virtual-text value preview + hover built in.
- [`nvim-dap-disasm`](https://codeberg.org/Jorenar/nvim-dap-disasm) — adds a
  disassembly view (works with either UI) — not a memory view, see below.

### 4. Bundled tooling — one evening of plugin installs

| Tool | Plugin | Verdict |
|---|---|---|
| HTTP client | [`kulala.nvim`](https://github.com/mistweaverco/kulala.nvim) | **Full parity** — explicitly targets 100% compatibility with JetBrains' `.http` file format; `.http` files move between nvim and RustRover unmodified. Supersedes the largely-unmaintained `rest.nvim`. |
| DB client | [`vim-dadbod`](https://github.com/tpope/vim-dadbod) + [`vim-dadbod-ui`](https://github.com/kristijanhusak/vim-dadbod-ui) + `vim-dadbod-completion` | Mostly there — connection tree, saved queries, execute-in-buffer. Result grid/row-editing plainer than DataGrip-in-RustRover; no ER diagrams. |
| Code coverage | [`andythigpen/nvim-coverage`](https://github.com/andythigpen/nvim-coverage) | Mostly there via `cargo llvm-cov --lcov --output-path lcov.info` → `:Coverage`. Manual regenerate-then-load loop, not a live "run with coverage" button. (`mr-u0b0dy/crazy-coverage.nvim` is a newer alternative that explicitly advertises Rust/tarpaulin/llvm-cov support if `nvim-coverage` has friction.) |

Rough total: ~4 plugins (dadbod trio counts as one install unit, kulala,
nvim-coverage) + `cargo-llvm-cov`, maybe 30-40 lines of `vim.pack.add` +
config.

Dependency/type diagrams (`cargo-modules`/`cargo-depgraph` → Graphviz `dot`
→ `snacks.image`) were researched here too — not wanted, dropped entirely.

---

## Genuine, unbridgeable gaps

Protocol/engine limits, not missing Neovim polish — RustRover keeps a real
edge here:

1. **Rename that updates `Cargo.toml`/workspace member references**, plus
   reliably-safe cross-crate rename in large, lazily-indexed workspaces.
   rust-analyzer's LSP rename only touches in-source symbol references.
2. **Move an item to another file/module with automatic import fixup**, and
   **change-function-signature-with-call-site-updates**. Upstream
   maintainers have said the LSP code-action protocol can't express this
   well ([rust-analyzer#2178](https://github.com/rust-lang/rust-analyzer/issues/2178),
   [#8340](https://github.com/rust-lang/rust-analyzer/issues/8340)). No nvim
   plugin bridges it.
3. **Data breakpoints** (break-on-write to a field/address). codelldb
   advertises `supportsDataBreakpoints` at the DAP protocol level, but
   nvim-dap's client side has never implemented `dataBreakpointInfo`/
   `setDataBreakpoints` —
   [open issue #1452](https://github.com/mfussenegger/nvim-dap/issues/1452),
   unassigned, opened Feb 2025.
4. **A real memory/hex view.** codelldb supports the `readMemory` DAP
   request, but nvim-dap exposes no visual widget for it — you'd drive it
   manually through the REPL's raw LLDB `memory read` commands
   ([nvim-dap discussion #701](https://github.com/mfussenegger/nvim-dap/discussions/701)).

---

## If this gets picked up

Suggested order, cheapest/highest-value first:

1. ~~`:RustLsp ssr` — zero install, just start using it.~~ **Shipped
   2026-07-17** as `<leader>cs`.
2. ~~`actions-preview.nvim` — diff preview on the code-action flow.~~
   **Shipped 2026-07-17** as global `<leader>ca`/`gra` + Rust's `<leader>cp`.
3. ~~Wire a `cargo clippy --fix --workspace` keymap.~~ **Shipped 2026-07-17**
   as `<leader>cF`. `workspace-diagnostics.nvim` + `trouble.nvim` (the
   project-wide diagnostics *panel* half) is still open.
4. `nvim-dap-virtual-text` (or evaluate switching to `nvim-dap-view`).
5. ~~`kulala.nvim` — HTTP client.~~ Moved to `plans/README.md` → "As-needed
   toolkit" (2026-07-17) — a known-good option, install it when there's an
   actual API to poke at, not on a schedule.
6. ~~`vim-dadbod` + `vim-dadbod-ui` — DB client.~~ Same move, same reason —
   "As-needed toolkit," install when DB work actually gets frequent.
7. `nvim-coverage` + `cargo-llvm-cov` — only if coverage-driven work comes
   up.

Each would need its own `GUIDE.md` section per this repo's nvim `CLAUDE.md`
conventions (Architecture entry, keymap table, Design Decisions note if
there's a non-obvious gotcha).
