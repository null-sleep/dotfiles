# Python debug + test in Neovim (nvim-dap-python + neotest-python)

> **Status: PLANNED (2026-07-14).** Not started. Sibling of
> [`go-run-debug-test.md`](go-run-debug-test.md) and
> [`go-targets-picker.md`](go-targets-picker.md) — read those first; this plan
> copies their shape (a language module + a Mason-installed adapter + a neotest
> adapter + buffer-local keymaps).
>
> **Scope:** full parity with the Rust/Go stacks, **plus** the thing neither of
> them needed — a **venv story** ([§0](#the-venv-convention): adopt `uv`, but
> standardise on the `<project>/.venv` it creates, so non-uv repos need nothing),
> because Python's interpreter is not discoverable the way `cargo`/`go` make
> theirs. The **targets picker** (the `go list` analogue) is **deferred**: the
> design question "what *is* a Python run target?" is unanswered, and is parked
> in [Deferred](#deferred-targets-picker).
>
> **Adversarially reviewed three times (2026-07-14), pre-implementation.** Each pass
> found a blocker in the previous pass's *fix*, which is the argument for having run
> them:
> - **Pass 1** — a pyright `before_init` that reassigned `config.settings` instead of
>   mutating it (so the plan's centrepiece silently sent pyright nothing), and a module
>   cycle that could permanently disable Python debugging for a session. Plus a
>   `<leader>dR` that duplicated `<F5>`.
> - **Pass 2** — the resolver's `vim.fs.find` used a *function* predicate, which types
>   entries from scandir and therefore **skips a symlinked `.venv`** outright.
> - **Pass 3** — the table form still walks to `/`: with no `stop`, one stray `~/.venv`
>   becomes the interpreter for **every** venv-less project (pyright, debugpy and pytest
>   at once). And `warn_if_unsynced` stat'd `<root>/.venv` directly, so it lied at every
>   uv **workspace member** and every `venv/`-named project. Both fixed in §2. Pass 3
>   also found that two comments defended invariants that *cannot be violated* — a
>   rationale that is wrong is worse than none, because it's what hid the walk bug.
>
> Findings that shaped the design are flagged **[review]** where they land.

## Context

Python is already well served for **editing** here — `pyright` (`lsp.lua`,
enabled, no custom settings), `ruff` on save (`format.lua:22`) and as a linter
(`linting.lua:29`), the `python` treesitter parser, and `fixtures/animal.py`.
What it has **no** support for is **debugging** and **testing** — exactly the
gap Go had before `go-run-debug-test.md`. The generic engines already exist and
were built to be extended: `debugging.lua` (nvim-dap + dap-ui, `<leader>d*` /
`<F5>`–`<F12>`) and `testing.lua` (neotest, `<leader>n*`). Neither has a Python
adapter, so today a cold `<F5>` in a `.py` buffer has nothing to launch and
`<leader>nd` does nothing.

But Python has one problem Rust and Go simply don't have, and it is why this is
more than a two-line diff: **cargo and go know their own toolchain; Python does
not.** There is no "the interpreter" — there's a project venv, and every tool
guesses at it differently:

- **pyright never looks for `.venv` at all.** With no `python.pythonPath` it
  shells out to `python3` from `$PATH` (`fullAccessHost.ts:297-318`) — here,
  Homebrew's 3.12, whose site-packages has none of the project's dependencies.
  **This is already broken today**; fixing it is in scope.
- **nvim-dap-python** scans `VIRTUAL_ENV` → `CONDA_PREFIX` → its `resolve_python`
  hook → `venv`/`.venv`/`env`/`.env` under cwd *and every LSP client's root_dir*
  (`dap-python.lua:99-129`).
- **neotest-python** globs `*/pyvenv.cfg` under *its own* root (`pyproject.toml`,
  `setup.cfg`, `mypy.ini`, `pytest.ini`, `setup.py` — notably **not** `.git`),
  then **memoizes the answer for the whole session** (`base.lua:26,32-34`).

Three guesses, three different root-marker sets, one wrong by default and one
cached forever. So the spine of this plan is: **one resolver, one leaf module,
three call sites.**

And underneath that: **this machine has no venv workflow at all** — no `uv`, no
`poetry`, no `pyenv`, no `conda`, and nothing in `README.md` telling you to make
a `.venv`. A resolver that resolves nothing is theatre, so §0 lands the
convention it is built around: **`uv` for creating envs, `<project>/.venv` as the
universal contract** — which is where uv puts them anyway, so a repo that has
never heard of uv keeps working with zero special-casing.

### Upstream facts (source-verified, July 2026)

Every claim below was read out of upstream source, not docs prose, and survived
two adversarial passes.

- **nvim-dap-python** (`mfussenegger/nvim-dap-python`, module `dap-python`) —
  **publishes no git tags** (the GitHub tags API returns `[]`), so it cannot be
  pinned. Same as nvim-dap-go.
  - `setup(x)` registers **the adapter interpreter**, not the debuggee's. It
    dispatches on the basename: `debugpy-adapter` → `command = <path>, args = {}`
    (L280-289) — Mason's bin; `uv` → `uv run --with debugpy python -m
    debugpy.adapter` (L270-279), which is a trap (see
    [Alternatives](#alternatives-considered)).
  - `include_configs` defaults to **true** and `console` defaults to
    **`integratedTerminal`** (`default_setup_opts`, L168-172) — no opts needed.
    It registers 4 configs: `file`, `file:args`, `attach`, `file:doctest`
    (L314-357). **So a cold `<F5>` in a `.py` buffer works**, unlike Rust.
  - The **debuggee** interpreter is resolved **per launch** in `enrich_config`
    (L153-157), *only if* the config pins neither `python` nor `pythonPath`. No
    restart needed when the venv changes.
  - **Do not** pass `setup(_, { pythonPath = ... })`: it bakes the interpreter
    into all 4 configs (L320/336/357) and short-circuits `enrich_config`,
    freezing the very resolution we want dynamic. Hook `M.resolve_python`
    instead — but note it is consulted **third**, after `VIRTUAL_ENV` (L100) and
    `CONDA_PREFIX` (L104), and those two are used **with no stat**.
  - `M.resolve_python()` is called **with no arguments**, so it resolves against
    whatever buffer is current at launch [review — matters for the deferred
    picker; see there].
  - `setup()` never stats the adapter binary. **A `pcall` around it cannot catch
    a missing debugpy** [review] — that surfaces as a spawn error at `<F5>` time.
- **debugpy is cross-interpreter by design.** The adapter launches the debuggee
  as `<debuggee python> <the ADAPTER's launcher path>`
  (`debugpy/adapter/launchers.py:85-87`), so **the project venv does not need
  debugpy installed** — including a uv-managed CPython. Mason's `debugpy` builds
  an isolated pyvenv and exposes `debugpy-adapter`
  (`mason-registry/packages/debugpy/package.yaml`: `source: pkg:pypi/debugpy@1.8.21`,
  `bin: debugpy-adapter: pyvenv:debugpy.adapter`), and Mason's `bin/` is already
  first on nvim's `PATH` (see the PATH note in `rust.lua`).
  - **Caveat:** with *no* `python`/`pythonPath` on the config, debugpy silently
    debugs **Mason's own venv interpreter** (`adapter/clients.py:326-328`:
    `if not len(python): python = [sys.executable]`). **The resolver must never
    return nil.**
  - debugpy 1.8.x requires the debuggee be Python ≥ 3.10 (`setup.py:163`). A
    minor-version mismatch against Mason's wheel only costs pydevd's C speedups
    (pure-Python fallback: slower stepping, still correct).
- **neotest-python** (`nvim-neotest/neotest-python`) — **also untagged**;
  unpinnable, so it needs the same `pcall` guard neotest-golang has.
  - The `python` opt **may be a `fun(root)`** (`init.lua:19-36`); passing it
    **replaces** `base.get_python_command` wholesale — the only way around the
    session-long memoization in `base.lua:26`. A string return is wrapped into a
    list for you (`init.lua:26-28`). It is re-evaluated on **every discovery and
    every run** (`adapter.lua:63,85`) — i.e. **per discovered file**, which is
    why the resolver must be cheap [review].
  - **A second cache** [review]: `stored_runners` (`base.lua:179-198`) memoizes
    pytest-vs-unittest per python-command **for the session**, decided by shelling
    out `python -c "import pytest"`. Two consequences: `pip install pytest` after
    nvim started → stuck on unittest until restart; and a *broken* interpreter
    makes the probe fail and **silently downgrades to unittest**, cached.
  - `dap = {...}` is merged `vim.tbl_extend('keep', {...base...}, dap_args)`
    (`base.lua:167-177`) — **first table wins**. `justMyCode = false` lands (not a
    base key), but `cwd`, `python`, `program`, `args`, `type`, `request`, `name`
    **cannot be overridden**, and `cwd` is hard-coded to **nvim's cwd**, not the
    test root [review].
  - `console` **is** an addable key there — and adding it would **break test
    output** [review]: neotest's dap strategy captures the debuggee via
    `dap.listeners.after.event_output` (`neotest/client/strategies/dap/init.lua:64`),
    and `integratedTerminal` routes stdout to a pty instead of DAP Output events.
    Leave `console` off neotest's config.
  - Its own `filter_dir` excludes `venv` but **not `.venv`** (`adapter.lua:58-60`),
    while `is_test_file` matches any `test_*.py`/`*_test.py` (`base.lua:6-13`) — so
    discovery walks into `.venv/**/site-packages` [review].
- **neotest core**: `discovery.filter_dir` is **ANDed** with the adapter's, not a
  replacement (`neotest/client/init.lua:276-281`), and `config.projects`'
  metatable falls back to the global config (`config/init.lua:468-472`). Default
  is `nil`, so adding a global one clobbers nothing [review — verified].
- **pyright** — the working settings key is **`python.pythonPath`** (nested under
  `python`), per `pyright/docs/settings.md:41`. Changing it needs **no restart**:
  `onDidChangeConfiguration` → `updateSettingsForAllWorkspaces()`
  (`languageServerBase.ts:725-731`), and nvim-lspconfig ships the command that
  pokes it: `:LspPyrightSetPythonPath <path>`.
  - **The trap** [review]: settings must be **mutated in place** in `before_init`.
    `Client.create` binds `settings = config.settings` *once* (nvim 0.12
    `lsp/client.lua:409`), and everything that ships settings reads
    `client.settings` (`client.lua:601-602`, `handlers.lua:235-246`). Reassigning
    `config.settings = vim.tbl_deep_extend(...)` — which **returns a new table** —
    detaches it and pyright never sees the pythonPath. Neovim's own docstring at
    `client.lua:36-41` demonstrates the broken pattern; don't copy it.
  - `config.root_dir` **is** populated at `before_init` (`lsp.lua:745-750` sets it
    before `create_and_init_client`), and lspconfig's `lsp/pyright.lua` defines
    **no** `before_init` and ships `settings.python.analysis`, so
    `vim.lsp.config('pyright', {...})` deep-merges cleanly and its `on_attach`
    (which registers `:LspPyrightSetPythonPath`) survives.
- **`vim.fs.find`** has **two implementations** (`runtime/lua/vim/fs.lua:355-381`):
  a **table** of names → `uv.fs_stat` per name (follows symlinks; tests names in the
  given order), and a **function** predicate → a full `readdir` of the directory
  (types come from scandir, so a symlink is `'link'`, **not** `'directory'`).
  **[review — pass 2's blocker]** With `type = 'directory'` the function form
  therefore *silently skips a symlinked `.venv`* and returns matches in
  nondeterministic readdir order. **Use the table form.**
- **`vim.fs.find`'s upward walk runs to `/` unless you pass `stop`**
  (`fs.lua:355-400`: `for parent in M.parents(path) do if stop and parent == stop then
  break end`), and `limit = math.huge` means it never short-circuits either. **[review —
  pass 3's blocker]** That is true of *both* branches — the table form fixes the symlink
  bug, not the walk. With `upward = true`, matches come back **deepest level first**, and
  within a level in the order the name table lists them.
- **toggleterm** keys terminals by id: `if id and terminals[id] then return
  terminals[id] end` (`toggleterm/terminal.lua:203`), and `shutdown()` →
  `terminals[id] = nil` (`:293-297`). A second module calling
  `Terminal:new({ id = 101, cmd = 'python foo.py' })` while `gotargets.lua`'s 101
  is alive gets handed back **the Go terminal with the Go command**, silently
  ignoring `cmd`/`dir`. The `runner.lua` extraction (§6) is a real bug fix.
- **uv** ([docs.astral.sh/uv](https://docs.astral.sh/uv/concepts/projects/layout/)):
  *"uv also manages a persistent environment with the project and its dependencies
  in a `.venv` directory next to the `pyproject.toml`. **By default, it is stored
  inside the project to make it easy for editors to find**."* A uv `.venv` is a
  bog-standard PEP 405 venv with `bin/python` **and** `bin/python3` symlinks
  (`uv-virtualenv/src/virtualenv.rs:264-282`). `uv sync` in `fixtures/` discovers
  `fixtures/pyproject.toml` and does **not** walk up into the dotfiles root; a
  project with no `[build-system]` is not built or installed, only its deps
  (`concepts/projects/config`).

---

<a id="the-venv-convention"></a>
## 0. The venv convention — uv-first, `.venv`-always

This machine has **no** Python env workflow today, so the convention ships first;
everything downstream assumes it.

**The convention is `<project>/.venv`, and `uv` is how we create it.** Because uv
puts its environment exactly where a bare `python3 -m venv .venv` does (quote
above), **not one line of the nvim wiring in this plan is uv-specific**, and every
repo that doesn't use uv keeps working unchanged. uv is a nicer way to *make* the
venv, not a second code path.

- **`Brewfile`** — add `brew "uv"`. Optional at runtime: nothing in the nvim
  config shells out to it.
- **`README.md` → `## Languages`**, extending the existing
  `# Python (pyright LSP + yamllint linter)` comment block (README.md:171-175).
  Both repo styles, one destination:

  ```bash
  brew install uv            # project venv manager (also in the Brewfile)

  # Per project, create the venv nvim will find. pyright, debugpy and neotest all
  # resolve `<project>/.venv/bin/python` (nvim GUIDE.md → "Python"); with no venv
  # they fall back to Homebrew's python3 and every project import reads as
  # unresolved. Both routes below land in the same .venv.

  # uv repo (pyproject.toml + uv.lock) — preferred
  uv sync                    # creates .venv, installs the locked deps
  uv add --dev pytest        # if the project doesn't already depend on it

  # any other repo (requirements.txt, setup.py, or nothing)
  python3 -m venv .venv      # python3 = brew's 3.12 (see the PATH note above)
  .venv/bin/python -m pip install -r requirements.txt   # if present
  .venv/bin/python -m pip install pytest
  ```
  Plus one line: **debugpy is NOT installed into the project venv** — Mason's copy
  debugs it from outside (Upstream facts).

  **`uv` gets no Part 2 README section** [review], and that's consistent, not an
  oversight: `ruff`, `cargo-nextest` and `cargo-audit` are all Brewfile +
  `## Languages` only. A per-project *language toolchain* belongs in `## Languages`;
  Part 2 is for tools with their own config/keymaps. Noted here so the root
  `CLAUDE.md` rule ("new tool → Part 2 section + Contents entry") isn't re-raised
  against it.
- **Root `.gitignore`**: add `.venv/` beside the existing `__pycache__/` entry
  [review — there is no `fixtures/.gitignore`; that ignore lives at the repo root,
  in a block whose comment already names `fixtures/animal.py`]. `fixtures/` is
  **not** a stow package (root `CLAUDE.md`), so `fixtures/.venv` is never
  symlinked into `$HOME`.
- **`fixtures/`** becomes a real uv project (§10) — `pyproject.toml` + a committed
  `uv.lock`, so `uv sync` there reproduces the exact env every verification step
  runs against, and the uv path gets exercised end to end. The plain-venv path
  stays covered by verification 12.

**uv is NOT used for the debug adapter.** `dap-python.setup('uv')` is a trap — see
[Alternatives](#alternatives-considered). Mason's `debugpy-adapter` works in every
repo, uv or not.

---

## Changes

### 1. `lua/plugins.lua` — two plugins, in the "Debug / Test / Language support" block

```lua
  -- nvim-dap-python and neotest-python publish no git tags either (same as
  -- nvim-dap-go), so neither can be pinned; both are pcall-guarded at their
  -- call sites (python.lua, testing.lua).
  { src = gh('mfussenegger/nvim-dap-python') },
  { src = gh('nvim-neotest/neotest-python') },
```

The `python` treesitter parser is already in `ensure_installed` (`plugins.lua:269`).

<a id="2-venv-lua"></a>
### 2. NEW `lua/venv.lua` — the resolver, as a dependency-free leaf module

**[review] A leaf on purpose.** The first draft put the resolver inside
`python.lua`, whose top level `packadd`s nvim-dap-python and calls
`dap_python.setup()` — which asserts `require('dap')` succeeds. But `lsp.lua`
(init.lua:11) needs the resolver *before* `debugging.lua` (init.lua:13) has put
nvim-dap on the runtimepath. A pyright attach firing early would have raised
inside the `pcall`, set `dap_ok = false`, cached `package.loaded.python`, and
**permanently disabled Python debugging for the session** behind one WARN. A
module that only stats the filesystem can't do that.

```lua
-- venv.lua — which Python interpreter is THIS project's? The single answer read by
-- pyright (lsp.lua), debugpy (python.lua) and neotest (testing.lua). Each of those
-- three ships its own venv guess and they disagree; this is the tiebreak.
--
-- Dependency-free on purpose (no packadd, no plugin require): lsp.lua calls it from
-- pyright's before_init, which can run before debugging.lua has put nvim-dap on the rtp.
--
-- NOTHING HERE IS uv-SPECIFIC: uv venv/sync/run all create the env at <project>/.venv
-- ("stored inside the project to make it easy for editors to find"), the same path
-- `python3 -m venv .venv` uses. One lookup covers both worlds. We deliberately do NOT
-- shell out to `uv python find` for an unsynced project: it returns a bare interpreter
-- with none of the project's deps -- worse than failing honestly (see warn_if_unsynced).

local M = {}

-- Byte-for-byte lspconfig's own pyright root_markers, so venv.root() and pyright's
-- root_dir can't disagree. This is a PRIORITY ORDER, not a set: vim.fs.root runs a
-- full upward walk PER MARKER (fs.lua:493-503), so a pyproject.toml five levels up
-- beats a .git one level up. That's what keeps a monorepo package on its own venv
-- instead of the repo-root one -- and .git being last is what makes it work.
M.root_markers = {
  'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg',
  'requirements.txt', 'Pipfile', '.git',
}

-- The names dap-python scans (dap-python.lua:118-126), in its order. NOT because the
-- two must agree -- setting resolve_python makes dap's own scan unreachable, so they
-- CAN'T disagree -- but because this list is what dap would fall back to if python.lua's
-- pcall ever failed, and because we need SOME deterministic order. Nearest level wins;
-- within a level, `venv` before `.venv`.
local VENV_DIRS = { 'venv', '.venv', 'env', '.env' }

-- Positive-only cache: neotest calls the resolver once per DISCOVERED FILE
-- (neotest-python adapter.lua:63), not once per root. Caching only hits keeps that
-- cheap while a miss still re-checks -- so a venv created after startup is picked up
-- without a restart, which is exactly the bug neotest's own always-cache has.
local hits = {}

function M.root(bufnr)
  return vim.fs.root(bufnr or 0, M.root_markers) or vim.fn.getcwd()
end

--- Every venv dir at or above `root`, nearest first. STOP AT $HOME, deliberately:
--- vim.fs.find's upward walk runs to / otherwise (fs.lua:355-400, no short-circuit
--- when limit is huge), and a single stray ~/.venv -- one `python3 -m venv .venv` run
--- in $HOME, ever -- would then silently become the interpreter for EVERY project
--- without its own venv, for pyright, debugpy and pytest at once. fs.find breaks
--- BEFORE testing `stop`, so $HOME itself is excluded, which is what we want.
--- (dap-python never does this: it only tests direct children of its roots.)
local function venv_dirs(root)
  return vim.fs.find(VENV_DIRS, {
    path = root, upward = true, type = 'directory',
    stop = vim.uv.os_homedir(), limit = math.huge,
  })
end

--- Never returns nil OR an empty string: debugpy treats a missing/empty pythonPath as
--- absent and silently debugs Mason's OWN venv instead (adapter/clients.py:326-328) --
--- an interpreter with none of your deps.
---@param root string|nil defaults to the current buffer's project root
function M.python(root)
  -- An empty VIRTUAL_ENV is a broken shell env, not a venv -- but dap-python reads it
  -- with os.getenv and "" is TRUTHY in Lua, so it would return "/bin/python" and never
  -- consult resolve_python. Ignoring it here would therefore not make dap agree with us;
  -- it would split the three tools three ways. So NORMALISE it: vim.env writes go through
  -- os_setenv, which is what dap-python reads.
  if vim.env.VIRTUAL_ENV == '' then vim.env.VIRTUAL_ENV = nil end

  -- VIRTUAL_ENV / CONDA_PREFIX first, and WITHOUT stat'ing them: dap-python returns them
  -- unconditionally (dap-python.lua:99-111) and only consults resolve_python when both
  -- are unset. Stat'ing here would make us fall through to .venv where dap cannot, and
  -- the one-answer invariant would break exactly when a stale VIRTUAL_ENV is the bug.
  local active = vim.env.VIRTUAL_ENV or vim.env.CONDA_PREFIX
  if active and active ~= '' then return active .. '/bin/python' end

  root = root or M.root()
  if hits[root] and vim.uv.fs_stat(hits[root]) then return hits[root] end

  -- A TABLE of names, never a function predicate: vim.fs.find's function branch types
  -- entries from scandir, so a SYMLINKED .venv reports as 'link' and is silently skipped
  -- by type='directory' (and it readdirs each level instead of stat'ing 4 names). The
  -- table branch fs_stat's each name -- following symlinks -- in order. See fs.lua:355-381.
  -- Upward, because neotest-python roots on a different marker set than we do (no .git,
  -- no requirements.txt; but mypy.ini and pytest.ini), and because a uv WORKSPACE keeps
  -- one .venv at the workspace root while each member has only its own pyproject.toml.
  for _, dir in ipairs(venv_dirs(root)) do
    local exe = vim.fs.joinpath(dir, 'bin', 'python')
    if vim.uv.fs_stat(exe) then
      hits[root] = exe
      return exe
    end
  end

  -- Homebrew's 3.12 in a login shell; right for dep-free scripts. exepath returns '' when
  -- python3 isn't on PATH -- and '' would land us back on Mason's interpreter (above), so
  -- hand back a bare name and let the spawn fail loudly instead.
  -- NOTE this line is PATH-dependent: python@3.12 is keg-only and only prepended by
  -- .zshrc_config.zsh, so a GUI-launched nvim (Neovide/Finder) can resolve
  -- /usr/bin/python3 = 3.9, below debugpy 1.8's >=3.10 floor. A project with a venv
  -- never reaches here.
  local py3 = vim.fn.exepath('python3')
  return py3 ~= '' and py3 or 'python3'
end

--- The only uv-aware code in the config, and it only NOTIFIES. A uv.lock (or a pyproject)
--- with NO venv anywhere the resolver looks means the env was never created: pytest won't
--- exist and pyright will invent missing-import errors. Saying "run uv sync" beats letting
--- the user debug the resolver.
--- Gated on venv_dirs(), NOT on a `<root>/.venv` stat: the resolver accepts four names and
--- walks upward, so a `venv/`-named env, or a uv workspace member inheriting the workspace
--- root's .venv, is perfectly resolvable -- and a WARN there would be a lie.
--- Once per root: FileType fires per buffer, and one WARN per opened file is noise.
local warned = {}

function M.warn_if_unsynced(root)
  if warned[root] or #venv_dirs(root) > 0 then return end
  local advice
  if vim.uv.fs_stat(vim.fs.joinpath(root, 'uv.lock')) then
    advice = 'run `uv sync`'
  elseif vim.uv.fs_stat(vim.fs.joinpath(root, 'pyproject.toml')) then
    advice = 'run `uv sync` or `python3 -m venv .venv`'
  else
    return  -- not a project; a loose script needs no venv
  end
  warned[root] = true
  vim.notify('No virtualenv for ' .. root .. ' — ' .. advice, vim.log.levels.WARN)
end

return M
```

### 3. `lua/lsp.lua` — one Mason tool, and pyright's interpreter

Next to `codelldb`/`delve` in `ensure_installed`:

```lua
    'debugpy',        -- python debug adapter (consumed by nvim-dap via nvim-dap-python)
```

And the fix for the pre-existing bug. **Mutate `config.settings` in place** —
reassigning it detaches the table `Client.create` already captured, and pyright
silently never sees the pythonPath (this was the first draft's blocker):

```lua
-- pyright does NOT autodetect .venv: with no python.pythonPath it shells out to
-- `python3` from $PATH (pyright fullAccessHost.ts), i.e. Homebrew's 3.12, whose
-- site-packages has none of the project's deps — every project import then reads as
-- unresolved. Route it through the same resolver dap and neotest use.
-- MUTATE, don't reassign: vim.lsp.client binds client.settings to this exact table at
-- create time and only client.settings is ever sent to the server, so
-- `config.settings = vim.tbl_deep_extend(...)` would write to a detached copy.
-- Changing the venv later needs no restart: :LspPyrightSetPythonPath <path>.
vim.lsp.config('pyright', {
  before_init = function(_, config)
    -- lspconfig's pyright ships settings.python.analysis, so both levels exist today;
    -- the `or {}`s keep this a no-op rather than an error if that ever changes.
    config.settings = config.settings or {}
    config.settings.python = vim.tbl_deep_extend('force', config.settings.python or {},
      { pythonPath = require('venv').python(config.root_dir) })
  end,
})
```

Matches the `vim.lsp.config(...)` pattern `lsp.lua` already uses for
`gopls`/`lua_ls`/`kotlin_language_server`.

### 4. NEW `lua/python.lua` — the language module (mirrors `golang.lua`)

Owns the debugpy adapter registration and the Python ft keymaps — nothing else
(the resolver is §2). Named `python.lua`: no collision (the plugin's module is
`dap-python`), same rule as `debugging.lua`-not-`dap.lua`.

```lua
-- debugpy: 'debugpy-adapter' is Mason's bin (its own isolated pyvenv). That is the
-- ADAPTER's python, NOT the debuggee's — debugpy launches the debuggee as
-- `<debuggee python> <adapter's launcher path>` (debugpy adapter/launchers.py:85-87),
-- so the project venv never needs debugpy installed. Same call LazyVim/AstroNvim make;
-- NOT setup('uv') — see plans/python-debug-test.md, Alternatives.
-- Guarded like golang.lua: nvim-dap-python publishes no tags, and an uncaught error
-- here would abort every module after it in init.lua. NOTE the guard covers LOAD
-- failures only — setup() never stats the binary, so a missing debugpy surfaces as a
-- spawn error at <F5> time, not as this WARN.
local dap_ok = pcall(function()
  vim.cmd.packadd('nvim-dap-python')
  local dap_python = require('dap-python')
  dap_python.setup('debugpy-adapter')
  -- resolve_python, NOT setup(_, { pythonPath = ... }): the opts form bakes the
  -- interpreter into the 4 bundled configs and short-circuits enrich_config, which is
  -- what re-resolves the venv on every launch. This keeps it per-launch.
  dap_python.resolve_python = function() return require('venv').python() end
end)

if not dap_ok then
  vim.notify('nvim-dap-python failed to load — Python debugging disabled', vim.log.levels.WARN)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'python',
  group = vim.api.nvim_create_augroup('UserPythonKeys', { clear = true }),
  callback = function(ev)
    local venv = require('venv')
    -- <leader>cR — run this file in the shared output float, under the project's venv
    -- interpreter. The Rust/Go meaning of cR (pick a target, run it) arrives with the
    -- targets picker; the file is the interim target. shellescape BOTH halves: a
    -- project path can contain spaces.
    vim.keymap.set('n', '<leader>cR', function()
      local file = vim.fn.expand('%:p')
      require('runner').float(
        vim.fn.shellescape(venv.python()) .. ' ' .. vim.fn.shellescape(file), venv.root())
    end, { buffer = ev.buf, desc = 'Python: Run this file' })

    -- One WARN per project whose env was never created — otherwise the first symptom is
    -- pyright inventing missing-import errors and pytest not existing.
    venv.warn_if_unsynced(venv.root(ev.buf))
  end,
})
```

**`<leader>dR` is deliberately NOT bound for Python** [review]. dap-python already
registers a `file` config (`program = '${file}'`), so an interim
"debug-the-current-file" `dR` would be a slower spelling of `<F5>` → pick `file`
— a duplicate key, and a direct contradiction of the nested `CLAUDE.md`'s reason
for language-local keymaps ("the prose explains a gotcha the key alone doesn't
convey — e.g. why `<leader>dR` differs from `<F5>` for a cold start"). For Python
it wouldn't differ. `dR` gets bound when the picker lands and has something `<F5>`
can't do; GUIDE.md's Python section says so, making the *absence* documented
rather than an apparent oversight.

Also declined, explicitly: dap-python's `test_method()`/`test_class()` (superseded
by neotest's `<leader>nn`/`<leader>nd`, which are language-agnostic) and
`include_configs` (already defaults true). `debug_selection()` is the one genuinely
unique capability left — see [Deferred](#deferred-targets-picker).

### 5. `init.lua` — one `require`

```lua
require('golang')     -- ...
require('python')     -- nvim-dap-python (debugpy adapter) + Python ft keymaps
require('testing')    -- neotest
```

Must follow `debugging` (needs nvim-dap on the rtp). `venv.lua` and `runner.lua`
are never `require`d from `init.lua` — leaf modules, pulled in lazily by their
callers — so the line above is the only ordering constraint added.

### 6. NEW `lua/runner.lua` — the shared run-output float

`pickers/gotargets.lua:62-89` owns a toggleterm float at the fixed id `101`, in a
module-local `run_term` handle, shut down before each new run. Python's
`<leader>cR` needs the same, and **two modules each calling
`Terminal:new({ id = 101 })` is a real collision**: toggleterm returns the
*existing* terminal for a known id, silently ignoring the new `cmd`/`dir` — so
`<leader>cR` in Python would re-run the last Go program. Extract it, **handle
included** [review — the handle is the whole point; a copy per module would
reintroduce the bug it fixes], and point `gotargets.lua` at it:

```lua
-- runner.lua — the shared run-output float (toggleterm id 101). A new run replaces the
-- previous one, which is why the handle lives HERE and not in each caller: toggleterm
-- keys terminals by id (terminal.lua:203 returns the existing one for a known id), so
-- two modules holding two id-101 handles would hand each other the wrong terminal.
-- The id registry lives in terminal.lua's comments: 100 = bottom panel,
-- 1-99 = count-addressable floats, 101 = this. The <C-]> cycle filters on `hidden`,
-- not id, so this terminal stays in the cycle — deliberately.

local M = {}

local run_term  -- shared across languages; a second run replaces the first

--- Run `cmd` in `dir`, replacing whatever ran last.
function M.float(cmd, dir)
  local Terminal = require('toggleterm.terminal').Terminal
  if run_term then run_term:shutdown() end   -- frees id 101 (terminal.lua:293-297)
  run_term = Terminal:new({
    id = 101,
    cmd = cmd,
    dir = dir,
    direction = 'float',
    close_on_exit = false,  -- the program's output survives its exit
  })
  run_term:toggle()
end

return M
```

The body is lifted verbatim from `gotargets.lua:62-89` (`run_term` at :62, `run_target`
at :64-89); `gotargets.lua` keeps only the `go run <import-path>` string and calls
`runner.float(cmd, root)`.

The only change to shipped behaviour, and it's mechanical.

### 7. `lua/testing.lua` — the neotest adapter, and a discovery filter

Guarded like the Go one; retires the `require('neotest-python')` placeholder at
`testing.lua:18`:

```lua
local ok_py, py_adapter = pcall(function()
  vim.cmd.packadd('neotest-python')
  return require('neotest-python')({
    -- A FUNCTION, not '.venv/bin/python'. Two reasons, both load-bearing:
    -- (1) neotest-python's own resolver MEMOIZES per root for the whole session
    --     (base.lua python_command_mem); passing `python` replaces that resolver
    --     wholesale, and adapter.lua re-calls it on every discover and every run.
    -- (2) a relative string resolves against nvim's cwd, not the test's root.
    python = function(root) return require('venv').python(root) end,
    -- justMyCode = false so a breakpoint in an installed dependency (site-packages) is
    -- honoured; without it debugpy skips everything it classes as library code.
    -- DO NOT add `console` here: it IS an addable key (the merge is tbl_extend 'keep'),
    -- but neotest's dap strategy captures output via dap.listeners event_output, and
    -- 'integratedTerminal' routes stdout to a pty instead — <leader>no would go empty.
    dap = { justMyCode = false },
  })
end)

if ok_py then
  table.insert(adapters, py_adapter)
else
  vim.notify('neotest-python failed to load — Python tests disabled', vim.log.levels.WARN)
end
```

And in `require('neotest').setup({...})` — **not optional** [review]:
neotest-python's own `filter_dir` excludes `venv` but not `.venv`, and
`site-packages` is full of `test_*.py`, so discovery would crawl the venv:

```lua
require('neotest').setup({
  adapters = adapters,
  -- Discovery must not descend into a virtualenv: site-packages is full of test_*.py,
  -- and neotest-python's own filter only excludes bare `venv`. neotest ANDs this with
  -- each adapter's filter (client/init.lua:276-281), so Go/Rust discovery is unaffected.
  discovery = { filter_dir = function(name) return name ~= '.venv' and name ~= 'venv' end },
})
```

No `runner` opt: neotest-python's detection (pytest if importable, else unittest)
is right, and unlike Go there's no `gotestsum`-shaped reason to override it. Its
result is cached per session (`stored_runners`) — a documented gotcha (Risks), not
a reason to hard-code.

### 8. `lua/whichkey.lua` — keyword aliases only (no new group, no new keymaps)

Extend the `<leader>sk` search keywords/tags: add `python`/`debugpy`/`pytest`/`venv`
to `<leader>dc`, `<leader>nd`, `<leader>cR` (lines 102-108), and `'python'` to the
tag lists for **`<leader>cR` (line 132) and `<leader>nd` (line 139) only**
[review — 133-138 in that block are diffview keys; a blind "131-139" edit would tag
them `python`]. `<leader>dR`'s tags stay `{ rust, go }` — Python doesn't bind it.

### 9. `nvim/.config/nvim/GUIDE.md` — a Python section, and two recipes that stop lying

Per the nested `CLAUDE.md`:

- New Part 2 `## Python (debugpy + neotest)` (after `## Go`, before `## Neovide`)
  with `<a id="python"></a>`, mirroring Go's shape. Its most important subsection
  is **"Which interpreter gets used"**: the resolver, the `VIRTUAL_ENV`-wins rule,
  `:LspPyrightSetPythonPath`, the `.venv` convention, and the troubleshooting set —
  unresolved imports → no `.venv`; tests silently running under unittest → a broken
  interpreter poisoned `stored_runners`, restart; `<leader>cR` runs the venv's
  python but does **not** activate the venv, so a script that shells out to
  `python`/`pytest` gets the system one; `vim.g.loaded_python3_provider = 0`
  (`configs.lua:2`) is a **red herring** — it disables nvim's python3
  *remote-plugin host* only [review]; and `<F5>`'s `integratedTerminal` opens a
  plain split alongside the dap-ui dock (knob: `dap.defaults.python.terminal_win_cmd`).
- `## Contents` TOC row [review]: `- [Python (debugpy + neotest)](#python)` after
  the Go entry (**GUIDE.md:50** — :51 is already Neovide).
- `Architecture` → file-responsibility bullets for `venv.lua`, `python.lua`,
  `runner.lua`; the `Load order` line gets `python` only (the other two are leaves).
- `Keymap index` → *By prefix*: one row, `` `<leader>cR` (Python ft) `` →
  `python.lua` → link. Exactly once; the canonical table is the Python section's.
- `Debugging` → `### Language support` (GUIDE.md:2073 — the real heading, referenced
  by exact title at :2260): add the Python row.
- `Testing` → registered-adapters table: add the Python row.
- **Both extension recipes currently use Python as the worked example**
  (GUIDE.md:2122-2127 shows `require('dap-python').setup('uv')` — already wrong,
  since that's the trap; and :2179-2180 for neotest). Once Python ships, a recipe
  demonstrating an installed language reads as a bug — the trap the Go plan hit
  (`go-run-debug-test.md:264-267`). **Rewrite both as language-agnostic skeletons**
  (`dap.adapters.<x>` + `dap.configurations.<ft>`; "if the plugin registers both
  itself, see `golang.lua`/`python.lua`") citing the **shipped** Go/Python wiring
  [review — pointing them at Elixir would swap a stale example for an *untested*
  one]. A recipe pointing at real code in this repo can't go stale silently.

### 10. `README.md` + `fixtures/` — the convention, and something to actually debug

README: the `## Languages` block from §0. No new heading, no keymap tables (those
belong to GUIDE.md, per the root `CLAUDE.md` ownership rule). Mason-installed
adapters are deliberately not enumerated in README (`codelldb`/`delve` aren't), so
`debugpy` isn't either.

`fixtures/` (Go got `go.mod` + `animal_test.go` for exactly this reason):
- `fixtures/pyproject.toml` — exactly this, no more:

  ```toml
  [project]
  name = "fixtures"
  version = "0.1.0"
  requires-python = ">=3.12"   # WITHOUT this, uv locks against the locking machine's
                               # python and warns — which defeats committing the lock

  [dependency-groups]
  dev = ["pytest>=8"]          # `dev` is in uv's default-groups, so plain `uv sync` installs it
  ```

  **No `[build-system]`** — uv then installs only the deps, never the project itself
  (`concepts/projects/config`), which is what we want (nothing here is a package).
  `[project]` with a name/version **is** required for uv to treat `fixtures/` as a
  project at all [review — "minimal" taken literally would have produced a lock that
  isn't reproducible]. uv reads only `pyproject.toml`, so the `go.mod` and the Mach-O
  binary sitting next to it are invisible to it.

  The file makes `fixtures/` a resolvable root for neotest, pyright and the resolver.
  It does **not** select the test runner
  (nothing in neotest-python reads `[tool.pytest.ini_options]`; only *dap-python's*
  `default_runner()` does, and we never call it) [review], and it does **not**
  become ruff's config (ruff keeps walking for a file with `[tool.ruff]`, and there
  is none), nor does it touch `go.mod`/`animal.rs`.
- `fixtures/uv.lock` — committed (uv's documented practice; it's what makes
  `uv sync` reproducible). It carries a `revision` field that a newer uv may rewrite;
  that churn is accepted for a one-dependency fixture.
- `fixtures/test_animal.py` — pytest tests over `Zoo`/`describe`. `import animal`
  works with **no install step**: pytest's default `prepend` import mode puts the
  test file's dir on `sys.path[0]` [review — the first draft's `pip install -e
  fixtures` would have failed: flat layout, two top-level modules, no build backend].
- `fixtures/.venv/` — created by `uv sync`, ignored via the root `.gitignore` (§0).

---

<a id="deferred-targets-picker"></a>
## Deferred: the targets picker

**TODO — decide what a Python "run target" is, then build `pickers/pytargets.lua`
and bind `<leader>dR`/`<leader>cR` to it.** Go's picker exists because `go list` is
an authoritative target provider and dap-go's configs are `${file}`-anchored. Python
has neither the provider nor the problem in the same shape, and the candidate
answers are all partial:

- Files containing `if __name__ == "__main__":` — the pythonic "main package";
  discoverable with an async `rg` (mirroring gotargets' `vim.system` +
  abort-handler shape; this repo already leans on ripgrep).
- `[project.scripts]` entry points in `pyproject.toml` — real, named console entry
  points, but only meaningful inside an installed venv.
- Packages with a `__main__.py` (`python -m pkg`).
- Test targets — explicitly **out**: those are neotest's, same call as Go's.

Two constraints on whatever it launches, both learned the hard way here:

- It **must set `console = 'integratedTerminal'`** on the config it builds:
  dap-python's bundled configs do (`default_setup_opts`), and a hand-built
  `dap.run()` without it inherits debugpy's `internalConsole` default — program
  stdout goes to the dap REPL, which reads as "my program printed nothing". (This
  applies to hand-built launch configs **only** — never to neotest's, where it
  would break `<leader>no`; see §7.)
- It **must pin `pythonPath` itself** rather than leaning on
  `dap_python.resolve_python`: that hook takes no arguments and resolves against
  the *current* buffer, which during a picker confirm may still be the picker's —
  the same hazard `gotargets.lua:50-59` documents for `filetype`.

Also open: whether `<leader>dR` on a *test* file should route into neotest instead;
and whether `dap-python.debug_selection()` (debug a visual selection — no neotest
equivalent) deserves a key.

---

## Files touched

| File | Change |
|---|---|
| `lua/plugins.lua` | +2 `vim.pack` entries (both unpinnable — no tags) |
| `lua/venv.lua` | **new** — the dependency-free interpreter resolver |
| `lua/lsp.lua` | +`debugpy` in `ensure_installed`; `vim.lsp.config('pyright', ...)` with an in-place `before_init` pythonPath |
| `lua/python.lua` | **new** — debugpy adapter + `<leader>cR` + the unsynced WARN |
| `lua/runner.lua` | **new** — shared run-output float (toggleterm id 101) + its handle, extracted from `gotargets.lua` |
| `lua/pickers/gotargets.lua` | call `runner.float()` instead of its own `Terminal:new`/`run_term` |
| `lua/testing.lua` | +neotest-python adapter (guarded); `discovery.filter_dir` excludes `.venv` |
| `init.lua` | +`require('python')` between `golang` and `testing` |
| `lua/whichkey.lua` | keyword/tag aliases only |
| `GUIDE.md` | new Python section + TOC + Architecture + Load order + By-prefix + 2 tables + rewrite both extension recipes |
| `README.md` | `## Languages`: the venv convention — uv + plain-venv routes (§0) |
| `Brewfile` | +`brew "uv"` |
| `.gitignore` (root) | `.venv/` beside `__pycache__/` |
| `fixtures/` | `pyproject.toml`, `uv.lock`, `test_animal.py` |
| `nvim-pack-lock.json` | regenerated (two new plugins) |
| `plans/python-debug-test.md` | **new** — this plan |
| `plans/README.md` | index entry + a TODO line for the deferred picker |

nvim paths are under `/Users/dhruv/src/dotfiles/nvim/.config/nvim/` (Stow source;
live via the `~/.config/nvim` symlink).

## Build order — eight stages, each one testable before the next

Ordered so that **every stage can be proven before the next one depends on it**, and so
that a failure is always attributable to the one file you just touched. That is *not*
the same as a tidy dependency order: the fixtures come first because nothing downstream
can be verified without a real venv to resolve to, and the resolver is proven as a pure
function before any consumer trusts it.

Each stage is one commit carrying a `Part-of: python debug + test support` trailer.
Every stage's rollback is `git revert` of that single commit. **If a stage's checkpoint
fails, stop — do not stack the next stage on top of it.**

### Stage 1 — a real Python project to point at (no nvim changes)

`feat(fixtures): add a uv-managed pytest project` — `Brewfile` (+`uv`), `fixtures/`
(`pyproject.toml`, `test_animal.py`, `uv.lock`), root `.gitignore` (+`.venv/`).

**Checkpoint (all shell, nvim not involved):**
```bash
brew install uv
cd fixtures && uv sync                      # creates fixtures/.venv
.venv/bin/python -m pytest -q               # tests pass
.venv/bin/python animal.py                  # the program runs
.venv/bin/python -c "import pytest; print(pytest.__file__)"   # inside .venv, not brew
```
Why first: every later checkpoint is really "did the right interpreter get used", and
that question is meaningless until a *wrong* answer and a *right* answer both exist.

### Stage 2 — the resolver, alone (`lua/venv.lua`)

`feat(nvim): resolve the project venv for pyright, debugpy and neotest` — new file, **no
callers yet**. A pure function; test it directly.

**Checkpoint** (`:lua =require('venv').python()` from each context):

| From | Expect |
|---|---|
| `fixtures/animal.py` | `…/fixtures/.venv/bin/python` |
| a `.py` file in a dir with no venv | Homebrew's `python3` |
| after `mv fixtures/.venv /tmp/fx && ln -s /tmp/fx fixtures/.venv` | still resolves (the symlink check) |
| a scratch dir under `$HOME`, with `~/.venv` present | Homebrew's `python3` — **not** `~/.venv/bin/python` (the `stop` check) |
| `VIRTUAL_ENV=/somewhere nvim fixtures/animal.py` | `/somewhere/bin/python` (env wins, by design) |

Plus `:lua require('venv').warn_if_unsynced(vim.fn.getcwd())` in a project with no venv
(WARNs, names `uv sync`) and in `fixtures/` (silent), and a `venv/`-named env (silent —
the false-positive pass 3 caught). Clean up `~/.venv` and the symlink afterwards.

### Stage 3 — pyright reads it (`lua/lsp.lua`, `before_init`)

`feat(nvim): point pyright at the project venv`. First consumer, and the one that fixes
a bug that exists *today* — so it's independently valuable even if the rest is abandoned.

**Checkpoint:** open `fixtures/test_animal.py`, then
`:lua =vim.lsp.get_clients({ name = 'pyright' })[1].settings.python.pythonPath` → the
`.venv` path. `import pytest` shows **no** unresolved-import diagnostic. (Before this
stage, it did — that's the regression test.)

### Stage 4 — the plugins land, inert (`lua/plugins.lua`, `lua/lsp.lua`)

`feat(nvim): install debugpy and the Python dap/neotest plugins` — two `vim.pack` entries
+ `debugpy` in Mason's `ensure_installed` + `nvim-pack-lock.json`.

**Checkpoint:** restart nvim, `:MasonToolsUpdate`, then
`:lua =vim.fn.exepath('debugpy-adapter')` is non-empty. **Nothing else should have
changed** — neither plugin ships a `plugin/` dir and nothing `packadd`s them yet, so
this stage is deliberately a no-op in behaviour. If anything *did* change, that's the
finding.

### Stage 5 — the shared run float (`lua/runner.lua`, `lua/pickers/gotargets.lua`)

`refactor(nvim): extract the shared run-output float into runner.lua`. Pure refactor,
and **Go is its test**: existing behaviour is the spec.

**Checkpoint:** in a Go buffer, `<leader>cR` → picker → the program runs in the float and
its output survives exit. Run it **twice**, picking different targets — the second must
replace the first, not open a second terminal. `<C-]>` still cycles into it.

### Stage 6 — Python debugging (`lua/python.lua`, `init.lua`)

`feat(nvim): add python.lua — debugpy adapter + Python keymaps`.

**Checkpoint** — this is the payoff stage, so test it properly:
1. Breakpoint in `fixtures/animal.py`'s `main()`; `<F5>` → pick `file` → **stops on the
   line**, dap-ui opens, scopes populate, `<F10>`/`<F11>` step, and the program's stdout
   appears in a terminal.
2. `<leader>cR` in `animal.py` → the float runs `…/fixtures/.venv/bin/python animal.py`.
3. **Immediately** `<leader>cR` in a **Go** buffer → it runs the *Go* program (the id-101
   cross-language check — the bug stage 5 exists to prevent).
4. Open a `.py` file in a pyproject-having, venv-less dir → one `uv sync` WARN, **once**,
   not once per file.
5. Break the plugin (`mv` its pack dir aside), restart → startup WARNs, and **Rust/Go
   debugging plus the rest of `init.lua` still work**. Restore.

### Stage 7 — Python testing (`lua/testing.lua`)

`feat(nvim): register the neotest-python adapter` + the `discovery.filter_dir`.

**Checkpoint:**
1. `<leader>nn` in `test_animal.py` → tests run and pass (proves the venv's pytest, not a
   global one — there *is* no global one, which is why stage 1 mattered).
2. `<leader>ns` → the summary shows **only** the fixture's tests, nothing from
   `.venv/**/site-packages` (the `filter_dir` check — without it, pytest's own tests
   flood the tree).
3. `<leader>nd` with a breakpoint in a test → stops; `<leader>no` **shows the test's
   stdout** (the "never add `console` to neotest's dap config" check).
4. Terminate, then `<leader>nd` on a *different* test → stops in the **second** test, not
   the first (the state-leak class of bug that bit the Go stack).
5. `:cd ~`, re-run `<leader>nd` → still passes (neotest hard-codes the debug `cwd` to
   nvim's cwd; this documents the weak spot rather than fixing it).
6. Go and Rust tests still run — the global `filter_dir` is ANDed with each adapter's, so
   it must not have broken them.

### Stage 8 — the fallback path, then the docs

First **prove the plain-venv route** (the promise the whole design rests on — a repo that
has never heard of uv must work):
```bash
rm -rf fixtures/.venv && python3 -m venv fixtures/.venv
fixtures/.venv/bin/python -m pip install pytest
```
Re-run stage 2's first row, stage 3, and stage 7's checks 1 and 3. **Nothing in the config
should notice.** Then `cd fixtures && uv sync` to restore.

Then `docs(nvim): document the Python debug/test stack and the venv convention` —
`GUIDE.md` (§9), `README.md` `## Languages` (§0), `whichkey.lua` (§8). The README text
claims "pyright, debugpy and neotest all resolve `<project>/.venv/bin/python`", which
only became true at stage 7 — which is why the docs land last [review].

**Checkpoint:** `<leader>sk` and search `python` → the new keys surface with their
keywords; GUIDE.md's Python section renders (anchors, no broken TOC link).

## Verification — the full pass

The per-stage checkpoints above are what you run *while building*; this is the end-to-end
sweep to run once everything is in, and again after any later change to `venv.lua`,
`python.lua` or `testing.lua`. It is a superset of the checkpoints.

Bootstrap (this is §0's README block, executed — the uv route):

```bash
brew install uv
cd fixtures && uv sync        # creates fixtures/.venv from the committed uv.lock
```

Every check below is really a check of *which interpreter got used*.

1. **Install:** `:MasonToolsUpdate` (not `:MasonToolsInstall` — the 24h debounce
   silently no-ops), then `:lua =vim.fn.exepath('debugpy-adapter')` is non-empty.
2. **Resolver:** from `fixtures/animal.py`, `:lua =require('venv').python()` →
   `.../fixtures/.venv/bin/python`, **not** `/opt/homebrew/.../python3`.
3. **pyright agrees** (the blocker pass 1 caught — this is its regression test):
   `:lua =vim.lsp.get_clients({ name = 'pyright' })[1].settings.python.pythonPath`
   → the same `.venv` path. Then `import pytest` in a fixture file → **no**
   unresolved-import diagnostic (it exists only in the venv).
4. **Cold `<F5>`:** breakpoint in `animal.py`'s `main()`, `<F5>` → pick `file` →
   stops, dap-ui opens, scopes populate, `<F10>`/`<F11>` step, **program stdout
   appears in a terminal** (the `integratedTerminal` default).
5. **`<leader>cR`** → the float runs `.../fixtures/.venv/bin/python animal.py`;
   output survives exit. Then `<leader>cR` in a **Go** buffer immediately after →
   it runs the *Go* program, not the Python one (the `runner.lua` id-101 regression
   test).
6. **`<leader>nn`** in `test_animal.py` → tests discovered and pass (proves neotest
   found the venv's pytest, not a global one).
7. **`<leader>ns`** (summary) → **only** the fixture's tests; nothing from
   `.venv/**/site-packages` (the `filter_dir` check).
8. **`<leader>nd`** → breakpoint inside a test is hit, and `<leader>no` shows the
   test's stdout (the "don't add `console`" check). For `justMyCode = false`, the
   honest check is a breakpoint **inside an installed dependency** under
   `.venv/**/site-packages` (e.g. step into `pytest`) — `animal.py` is *user* code
   here, so it would hit either way [review — the first draft claimed it as proof].
9. **Debug a second test** right after terminating the first → it stops in the
   *second* test (the `-test.run` state-leak class of bug from the Go stack).
10. **cwd sensitivity:** `:cd ~`, re-run `<leader>nd` → still passes. neotest-python
    hard-codes the debug `cwd` to **nvim's cwd** (`base.lua:172`) and the `dap` opt
    can't override it, so a test reading a relative path breaks here — known, and it
    belongs in GUIDE troubleshooting, not a resolver hunt.
11. **No venv:** a `.py` file in a dir with no `.venv` → resolver returns Homebrew
    python3 and `<F5>` still debugs a dep-free script. In a *project* dir
    (uv.lock/pyproject, no `.venv`) → the `warn_if_unsynced` WARN fires, names
    `uv sync`, and fires **once**, not once per file opened.
12. **The plain-venv route still works** (the fallback the whole design promises):
    `rm -rf fixtures/.venv && python3 -m venv fixtures/.venv &&
    fixtures/.venv/bin/python -m pip install pytest` → repeat 2, 3, 6, 8. Nothing in
    the config should notice. Restore with `uv sync`.
13. **Symlinked venv** (pass 2's blocker — the reason the resolver uses `vim.fs.find`'s
    table form): `mv fixtures/.venv /tmp/fx-venv && ln -s /tmp/fx-venv fixtures/.venv`
    → check 2 still resolves it.
14. **No `$HOME` hijack** (pass 3's blocker — the reason for `stop`): with
    `~/.venv` present (`python3 -m venv ~/.venv`), open a `.py` file in a scratch dir
    under `$HOME` with no venv → `:lua =require('venv').python()` must return
    **Homebrew's python3**, *not* `~/.venv/bin/python`. Then `rm -rf ~/.venv`.
15. **No false "unsynced" WARN**: a project whose env is named `venv/` (not `.venv/`),
    and a uv **workspace member** (member has only `pyproject.toml`; `.venv` and
    `uv.lock` live at the workspace root) → **no WARN**, and check 2 resolves to the
    workspace root's venv.
14. **Broken-plugin path:** rename the nvim-dap-python pack dir → startup WARNs, and
    **Rust/Go debugging plus the rest of `init.lua` still work**.

## Risks / gotchas

- **The `client.settings` aliasing trap** (§3): `config.settings = vim.tbl_deep_extend(...)`
  looks right, is what nvim's own docstring shows, and silently sends pyright nothing.
  Mutate in place. Verification 3 is its regression test.
- **The `pythonPath` freeze trap** (§4): `setup(_, { pythonPath = ... })` looks
  equivalent to hooking `resolve_python` and disables per-launch resolution.
- **The `vim.fs.find` predicate trap** (§2): the function form looks tidier and
  silently skips symlinked venvs (scandir types them `link`, not `directory`). Table
  form. Note the table form still walks to `/` — that's what `stop` is for, next.
- **The unbounded-upward-walk trap** (§2): without `stop`, one stray `~/.venv` — a
  single `python3 -m venv .venv` run in `$HOME`, ever — becomes the interpreter for
  **every** project that lacks its own, silently, for pyright *and* debugpy *and*
  pytest. `stop = vim.uv.os_homedir()`. Do not "simplify" it away.
- **The resolver's cache can't see a *closer* venv appear** (§2): resolve to a parent
  `.venv`, then create one at the project root, and the cached parent path still stats
  fine and keeps winning until restart. Deleting a venv *is* handled (the hit is
  re-stat'd). Not worth a watcher.
- **The neotest `python`-as-string trap** (§7): simpler-looking, wrong twice
  (cwd-relative; and only a *function* bypasses the memoization).
- **A broken interpreter silently downgrades tests to unittest.** `stored_runners`
  (`base.lua:179-198`) decides pytest-vs-unittest once per session per interpreter by
  probing `python -c "import pytest"`. If that probe fails (stale `VIRTUAL_ENV`,
  half-built venv) neotest quietly runs **unittest** and caches it. Symptom: tests
  "run" but find nothing. Cure: fix the venv, **restart nvim** — don't debug the
  resolver. Same cache means `pip install pytest` *after* startup needs a restart.
- **neotest's debug `cwd` is nvim's cwd**, not the test root, and the `dap` opt can't
  override it (`tbl_extend('keep', ...)` — additive only). Bites relative-path tests
  in a session spanning projects.
- **`.venv` created after nvim started:** pyright pinned Homebrew python at init.
  `:LspPyrightSetPythonPath <path>` (no restart); dap and neotest re-resolve on their
  next call (the resolver caches only hits). Not worth a filesystem watcher.
- **`VIRTUAL_ENV` outranks the directory scan** (deliberately, matching dap-python):
  nvim launched from an activated venv A, opening project B, uses A everywhere.
  Consistent, if surprising. The three tools resolve the same *path* — they do **not**
  fail identically when that path is broken (debugpy: spawn error; pyright: phantom
  import errors; neotest: the silent unittest downgrade above).
- **The `pcall` guards the plugin, not the binary**: `dap-python.setup()` never stats
  `debugpy-adapter`, so a missing Mason package surfaces as a raw spawn error at
  `<F5>`, not the startup WARN. Same recorded drawback as Go's: an unpinned plugin's
  *behavioral* break surfaces at debug time, uncaught.
- **The `python3` fallback is PATH-dependent**: `python@3.12` is keg-only and only
  prepended by `.zshrc_config.zsh`, so a GUI-launched nvim can fall back to
  `/usr/bin/python3` (3.9 — below debugpy's ≥3.10 floor). Only reachable in projects
  with no venv.

Rollback is clean: revert the commits; `debugpy` lingers in Mason harmlessly.

---

## Alternatives considered

### `dap-python.setup('uv')` for the adapter (REJECTED — a trap)

uv is adopted for *creating* venvs (§0), but **not** for hosting the debug adapter.
`setup('uv')` registers, verbatim (`dap-python.lua:269-279`):

```lua
args = { 'run', '--with', 'debugpy', 'python', '-m', 'debugpy.adapter' }
```

with **no `--no-project`** and **no `cwd`** on the adapter. `uv run` performs project
discovery from the process cwd and its parents, and *"Locking and syncing are
automatic in uv… when `uv run` is used, the project is locked and synced before
invoking the requested command"* (uv docs, concepts/projects/sync). So pressing
`<F5>` in **any** repo that merely has a `pyproject.toml` — Poetry, hatch,
setuptools, a bare `[tool.*]` stanza — makes uv try to resolve and build *that*
project, and can **write a `uv.lock` and a `.venv` into someone else's repo**, or
fail outright and never start the adapter. In an unsynced uv repo, the first `<F5>`
is a full dependency resolve.

Mason's `debugpy-adapter` has none of those failure modes, works identically in uv
and non-uv repos, and is what LazyVim and AstroNvim both ship (the string `uv` does
not appear in LazyVim's python extra). If we ever did want uv to host the adapter,
the correct invocation is `uv run --no-project --with debugpy python -m
debugpy.adapter`, hand-assigned to `dap.adapters.python` — `setup()` will not build
that for you.

### Teaching the resolver about uv (`uv python find`) — cut

The command exists and is fast, but it's useless here: *"If a `.venv` directory is
found in the working directory or any of the parent directories… it will take
precedence"* — so when a `.venv` exists it returns exactly what the upward walk
already found, and when one doesn't it returns a **bare interpreter with none of the
project's dependencies** (pytest missing, pyright reporting phantom import errors).
A blocking shell-out on a hot path to get a worse answer. `.venv` or an honest
failure, plus the `warn_if_unsynced` nudge (§2).

### venv-selector.nvim (rejected — for now)

What LazyVim and AstroNvim both ship (LazyVim writes *zero* custom venv code and
delegates entirely to it). Maintained; its `regexp` branch merged to `main` in
2025-08. It wires LSP (via a full client stop/start), sets `vim.env.VIRTUAL_ENV`, and
sets `dap_python.resolve_python`.

**Why not:** it solves a problem we don't have — scanning for envs scattered across
`~/.virtualenvs`, conda, pixi, poetry. The layout here is plain `<project>/.venv`. It
costs a plugin, an `fd` dependency, a picker integration, and a full LSP re-index per
switch — **and it still doesn't fix neotest-python's memoization** (nothing in its
source touches neotest). Our resolver is ~40 lines and covers all three tools.
Revisit if the venv layout ever gets messy.

### Just launch nvim from an activated venv (kept as the fast path, not the answer)

Zero code, and it genuinely works: `VIRTUAL_ENV` is priority 1 in all three tools
(pyright included — the venv's `bin` is first on `$PATH`, so its `python3` fallback
*is* the venv python). But it's one venv per nvim process, and it breaks the moment a
session spans two projects — which persistence.nvim sessions routinely do. The
resolver makes this the fast path, not the only path.

### direnv / `.envrc` (rejected)

Exports into the shell, not into a running nvim; `:cd` elsewhere and the env is
stale. Fixing that means a direnv nvim plugin — a plugin again, for a strictly worse
version of the resolver.

### A `runner` opt forcing pytest (cut)

neotest-python's detection (pytest if importable, else unittest) is right, and unlike
Go there's no `gotestsum`-shaped reason to override it. Its session cache is a
documented gotcha (Risks), not a reason to hard-code.

### An interim `<leader>dR` = debug-current-file (cut, see §4)

Would duplicate `<F5>` → `file` exactly. A key that shadows another key is worse than
an unbound key.
