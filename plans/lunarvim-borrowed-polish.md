# Polish features to borrow from LunarVim

## Context

Investigated `/Users/dhruv/src/LunarVim` (LunarVim core, 2026-07) for ideas
worth porting into this config. Cross-checked every candidate against the
existing setup so this plan only lists real gaps. LunarVim's big
architectural pieces (the global `lvim` defaults/override table, the
`:LvimReload` in-place module reloader, `User FileOpened`/`DirOpened`
lazy-load events, snapshot-pinned plugin commits, none-ls, the mason
auto-install LSP manager) exist to serve a distributed, lazy.nvim-based
product — none apply to this eager `vim.pack` config (see "Rejected").

File references are into the LunarVim repo unless prefixed otherwise.
Companion exercise: an AstroNvim comparison pass (same 2026-07 batch,
plan since landed and removed from `plans/`) — a few verdicts from it are
cross-referenced below rather than re-litigated.

## Adopt (high value, small code — verified gaps)

### 1. Auto-equalize splits on VimResized

Not present in this config (no `VimResized` autocmd anywhere). Equalizes
all splits when the terminal/GUI window resizes — `tabdo wincmd =` then
restore the current tab. Take LunarVim's *fixed* version (commit
`aa51c20f`) which returns to the active tab afterwards:

```lua
vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    local tab = vim.fn.tabpagenr()
    vim.cmd('tabdo wincmd =')
    vim.cmd('tabnext ' .. tab)
  end,
})
```

Especially relevant here: Neogit opens in a tab, and Neovide resizes are
common. Source: `lua/lvim/core/autocmds.lua` (auto_resize group).

### 2. Lua `gf` on `require()` paths

In lua files, make `gf`/`<C-w>f` jump to the module behind
`require("foo.bar")`: FileType-lua autocmd setting `include`,
`includeexpr` (dots→slashes), `suffixesadd=.lua`, and appending each
runtimepath `/lua` dir to `path`. lazydev provides completion/types but
not this jump. Source: `lua/lvim/core/autocmds.lua:26-45` (credit
nvim-lua-gf). ~15 self-contained lines.

### 3. Command-line `<C-j>`/`<C-k>` wildmenu navigation

Expr maps in cmdline mode: navigate the wildmenu with `<C-j>`/`<C-k>` when
the pum is visible, pass through otherwise. Complements the existing
`<C-j>`/`<C-k>` window-nav muscle memory. Source:
`lua/lvim/keymappings.lua:97-98`.

### 4. Move-line mappings (VSCode-style)

No line-move maps exist here. LunarVim binds `<A-j>`/`<A-k>` across
insert/normal/visual-block — but normal-mode `<A-j>/<A-k>` is taken by
split-resize in this config (`keymaps.lua:97-100`). Use
**`<A-Up>`/`<A-Down>`** instead, in n/i/x:

- n: `:m .+1<CR>==` / `:m .-2<CR>==`
- i: `<Esc>:m .+1<CR>==gi` / `<Esc>:m .-2<CR>==gi`
- x: `:m '>+1<CR>gv-gv` / `:m '<-2<CR>gv-gv`

Source: `lua/lvim/keymappings.lua` (defaults table). `desc` on every map
for the `<leader>sk` picker.

### 5. JSON/YAML language servers with schemastore

Verified gap: no `jsonls`/`yamlls` in the `vim.lsp.enable` list
(`lsp.lua`) — JSON/YAML files currently get no LSP at all. LunarVim ships
`b0o/schemastore.nvim` and wires it in per-server providers
(`lua/lvim/lsp/providers/jsonls.lua`, `providers/yamlls.lua`) for schema
validation/completion on package.json, GitHub workflows, docker-compose,
etc. Port: add schemastore.nvim to `vim.pack.add`, configure both servers
via `vim.lsp.config` with `schemas = require('schemastore').json.schemas()`
(and `yaml.schemas()`), add both to the mason-tool-installer list.

### 6. friendly-snippets

LunarVim ships `rafamadriz/friendly-snippets` (via LuaSnip). This config
has blink.cmp's `snippets` source enabled (`completion.lua`) but no
snippet collection installed — the source is effectively empty outside
LSP-provided snippets. blink.cmp loads friendly-snippets automatically
once it's on the runtimepath; a one-line `vim.pack.add` entry.

## Consider (more code or smaller payoff)

### 7. ts-context-commentstring

LunarVim ships `JoosepAlviste/nvim-ts-context-commentstring` so `gc` uses
the right commentstring in embedded languages (JS inside HTML, CSS in
templates, etc.). Integrates with native commenting via
`vim.g.skip_ts_context_commentstring_module = true` + an `Option` hook.
Only pays off in mixed-language files — low priority for the current
Rust/Go/Python-heavy work, cheap to add when web work picks up.

### 8. Terminal-mode window navigation

LunarVim maps `<C-h/j/k/l>` in terminal mode to `<C-\><C-N><C-w>h` etc.
Verified absent here: `terminal.lua` only binds `<C-]>` (cycle), `<S-CR>`
(linefeed), and panel toggles in t-mode. Today leaving a toggleterm split
requires `<C-\><C-n>` first. Caveat worth testing before adopting:
`<C-h/j/k/l>` are real shell/TUI keys (e.g. `<C-l>` clear, `<C-k>`
kill-line in readline, and the Claude CLI uses several) — may be better
scoped to non-CLI terminals only, or skipped. Source:
`lua/lvim/keymappings.lua` (term_mode block).

### 9. Big-file protection

LunarVim ships `lunarvim/bigfile.nvim`. **Previously adjudicated** in the
AstroNvim comparison pass (Rejected): treesitter is already
guarded here (>50k lines / >1.5MB in `plugins.lua`); revisit only if big
files still lag from blink or indent guides. If it ever lands, the move
is enabling `snacks.bigfile` in the existing snacks.nvim setup — zero new
plugins — not adopting bigfile.nvim.

## Surfaced during the audit — not LunarVim features

(Same convention as astro plan item 10: gaps noticed while comparing, but
LunarVim doesn't ship these either. Recorded so they aren't lost.)

- **Surround editing** — no surround plugin here (no
  nvim-surround/mini.surround). Biggest general editing-power gap found.
  `mini.surround` fits the existing mini.* family (icons/notify/bufremove);
  default `sa/sd/sr` don't collide with current maps.
- **todo-comments.nvim** — TODO/FIXME/HACK highlighting + telescope picker
  + `]t`/`[t`. Picker would need `<leader>sT` (`<leader>st` = themes).
- **nvim-dap-virtual-text** — inline variable values during DAP sessions;
  one-line setup next to the existing dap-ui config in `debugging.lua`.
- **flash.nvim** (weakest) — label-jump motions; overlaps in spirit with
  the hand-built Helix-style structural select (`<M-o>`/`<M-i>`). Only if
  jump-to-arbitrary-position friction actually comes up.

## Rejected (documented so we don't re-litigate)

- **`User FileOpened`/`DirOpened` self-deleting lazy-load events**
  (`core/autocmds.lua:126-155`) — serves lazy.nvim event loading; this
  config loads eagerly via `vim.pack`. Same verdict as `AstroFile` in the
  astro plan.
- **Global `lvim` table + defaults/override layering + `:LvimReload`
  in-place module reloader** (`config/init.lua`, `utils/modules.lua`) —
  distro machinery for user-config separation; single-user config edits
  itself, and nvim 0.12 has `:restart`.
- **Template-generated ftplugin LSP startup** (`lsp/templates.lua`,
  `lsp/manager.lua`) — native `vim.lsp.enable` already does lazy
  FileType-driven server startup; this predates it.
- **none-ls formatters/linters bridge** — conform.nvim + nvim-lint cover
  this without fake-LSP indirection. Its `format_filter` dedupe trick is
  moot: conform's `lsp_format='fallback'` is the same policy.
- **Mason `automatic_installation` LSP manager** — mason-tool-installer
  already owns installs here (24h debounce, auto-update).
- **alpha dashboard / bufferline / navic winbar / vim-illuminate /
  indent-blankline / Comment.nvim / project.nvim / lir.nvim** — all have
  deliberate equivalents or omissions: no-dashboard and no-bufferline are
  choices; native LSP documentHighlight replaces illuminate;
  aerial + treesitter-context replace navic; snacks.indent replaces ibl;
  built-in `gc` replaces Comment.nvim; `vim.fs.root` replaces
  project.nvim; nvim-tree replaces lir.
- **Smart `<Tab>`/`<CR>` cmp chain** (`core/cmp.lua:287-350`) — blink.cmp
  already has a custom Tab chain (menu → Copilot ghost → literal).
- **Floating lazygit** (`core/terminal.lua:153-172`) — Neogit +
  diffview is the chosen git UI.
- **structlog log system, `:LvimInfo` popup** — `:checkhealth` +
  mini.notify cover the need at personal scale.
- **Snapshot commit pinning** (`plugins.lua:362-383`) —
  `nvim-pack-lock.json` already pins.
- **nlsp-settings (JSON per-project LSP config)** — native `exrc`
  (`.nvim.lua`) covers per-project overrides.
- **`<C-q>` quickfix toggle** — superseded by
  `plans/quickfix-improvements.md` (quicker.nvim, `<leader>xq` toggle).
- **`]q`/`[q` quickfix nav** — built into Neovim 0.11+.
- **`<`/`>` visual reselect, yank highlight, `q`-to-close, cursor
  restore, mkdir-on-save, codelens refresh, document highlight** —
  already present (`keymaps.lua:76-77`, `autocmds.lua`, `lsp.lua`).
- **ColorScheme-driven highlight re-derivation**
  (`core/autocmds.lua:105-125`) — the themes.lua per-theme override
  system already handles this, better.

## Implementation notes

- Items 1–2 land in `lua/autocmds.lua` (module exists since the astro
  plan work), items 3–4 in `lua/keymaps.lua`, item 5 in `lua/lsp.lua` +
  `lua/plugins.lua`, item 6 in `lua/plugins.lua` only.
- Per repo convention: GUIDE.md updates land with each feature; every new
  keymap needs `desc` for the keybindings picker; new plugins must be in
  the `vim.pack.add` list or the orphan detector (`plugins.lua:87`) warns.
- Suggested landing order: **Batch A** (pure config, zero risk): 1, 2, 3,
  4. **Batch B** (new plugins): 5, 6. **Batch C**: reassess 7–9 and the
  non-LunarVim extras separately.
- Per-item verification: 1 → resize the OS window with 3 splits open,
  they equalize and the active tab stays put; 2 → `gf` on
  `require('themes')` in init.lua jumps to lua/themes.lua; 3 → `:e <Tab>`
  then `<C-j>/<C-k>` walks matches; 4 → `<A-Down>` in a function reindents
  the moved line; 5 → open package.json, jsonls attaches, bad key gets a
  diagnostic; 6 → blink menu shows snippet entries in a lua file.
