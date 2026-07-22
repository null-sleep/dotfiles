# Add Cursor alongside Claude in sidekick

> **Status:** implemented 2026-07-22, all manual verification steps passed
> (UX locked 2026-07-21; revised 2026-07-22 — dropped the dedicated
> `<leader>as` Cursor summon, `<leader>an`'s agent picker is now the single
> creation door; implementation plan + two UX amendments added 2026-07-22,
> see [Implementation plan](#implementation-plan)). This doc holds the UX
> decisions and the implementation plan in one place. Code is the source of
> truth.

## Goal

Sidekick's multi-session setup in `nvim/.config/nvim/lua/ai.lua` has only ever
run Claude. Add **Cursor** (`cursor-agent`) as a second agent, reachable from
the same nvim config, without disturbing the Claude workflow. See
[sidekick-multi-claude-sessions.md](sidekick-multi-claude-sessions.md) for how
the multi-session system works today.

## The constraint: `ai.lua` is claude all the way down

Adding Cursor isn't a config toggle — the session machinery is Claude-specific
in five places, not "agent-generic with a claude default":

- `M.active = 'claude'` and `fallback_active()` returns `'claude'` as home base.
- Session names encode the tool: `claude`, `claude 2`, `claude 3`
  (`_next_auto_name` matches `^claude (%d+)$`).
- `create_session` (`ai.lua:560`) **clones the claude preset** for every
  dynamic session — so today a session's name is cosmetic; the binary is always
  `claude`. This is the one load-bearing thing that has to change.
- Pre-warm spawns `claude` specifically, and Guard 1/Guard 2 match
  `t.tool.name == 'claude'`.
- The tool list is pruned to claude-only for perf (`ai.lua:155`); `<leader>as`
  (sidekick's tool launcher) was dropped as redundant.

So Cursor introduces a **second axis** (which agent) crossed with the existing
one (which session).

### Two facts about the cursor preset (confirmed 2026-07-21)

- sidekick ships a `cursor` preset (`cli/cursor.lua`): `cmd = {"cursor-agent"}`,
  but it's **bare** — no `format`, no `resume`/`continue`. Claude's preset has
  all three.
- The missing `format` turned out **not to matter** (see "Sends" below): the
  refs come from a *global* renderer, not the per-tool preset.

## Locked UX decisions (2026-07-21, rev. 2026-07-22)

### 1. Mental model — flat pool

Cursor is **just another named session** alongside `claude`, `claude 2`:
`cursor`, `cursor 2`. All generic keys already work on it once it's active —
`<leader>aa` toggle, `<leader>al` picker (already shows name + cwd, so mixed
tools display fine), `<leader>ad` kill, `<M-]>`/`<M-[>` cycle, sends. No
grouping layer, no per-tool active-session memory. The session **name carries
the tool identity**, and (unlike today) actually drives the binary.

Rejected: a tool-axis / grouped model (pick a tool, then a session within it) —
overkill unless several of *each* agent run routinely; costs a new selection
layer and more keymaps.

**Claude stays the home-base agent (owned asymmetry).** `M.active` defaults to
`claude`, only claude is pre-warmed (Decision 4), and `fallback_active` returns
`claude` when a killed session leaves nothing else — its name-sort also favours
`claude` over `cursor`. So killing your last Cursor session drops you back to
Claude, and Cursor can't be a *persistent* home base. This is deliberate, not
an oversight: Claude is the primary agent, Cursor the one reached for
occasionally. Because neither agent has a dedicated summon key (Decision 2),
this is the *only* remaining asymmetry, and it lives in fallback/prewarm/default
— not in the keymaps. If Cursor use ever grows into "my default for this
project," revisit `fallback_active` to prefer the last-used agent — a later
call, not this change.

### 2. Spawn entry — one door: `<leader>an` with an agent picker

**`<leader>an`** — new session with an **agent picker**: choose the agent
(claude / cursor), then a label — blank Enter = auto-numbered *new* session of
that agent, a typed label re-attaches if it exists, `<Esc>` cancels at either
step. This is the **single door** for creating sessions, and it's how you make
the **first** Cursor session (and every one after). (Previously claude-only:
label prompt, blank = auto claude.)

**No dedicated per-agent summon key.** An earlier draft added `<leader>as` (a
one-key Cursor summon, toggle like `<leader>aa`); dropped 2026-07-22 because it
gave the *secondary* agent a fast path the *primary* one lacked — an asymmetry
that fought the flat-pool framing — and it overloaded a key that already means
"send selection" in visual mode (`keymaps.lua:472`). One creation door keeps the
model symmetric: both agents are born the same way, and after birth every
generic key (`<leader>aa` toggle, `<leader>al` picker, `<M-]>` cycle, sends)
targets the active session regardless of agent.

**Keep the common path fast.** Since `<leader>an` is now the *only* way to make
a session, the agent picker must not tax the common new-Claude case: default its
highlight to `claude`, so plain `<CR>` confirms it. *(Amended 2026-07-22: a
`vim.ui.select` step cannot Enter-through for free — new-claude is
`<leader>an` `<CR>` `<CR>`, one Enter more than today. Accepted; picking
`cursor` stays the deliberate extra step.)*

### 3. In-CLI nav — `<M-n>` forks same agent; `<M-l>`/`<M-]>`/`<M-[>` stay pool-wide

- **`<M-n>` fast-fork becomes agent-aware (free):** the in-CLI `<M-n>` (fork a
  new auto-numbered session) currently always forks claude. Make it fork **the
  active session's agent** — in a cursor panel `<M-n>` yields `cursor 2`; in
  claude, `claude 2`. Cursor gets in-CLI forking with no new key.
- **`<M-l>` (switch/kill picker), `<M-]>`/`<M-[>` (cycle) do NOT care about
  agent** — they operate over the **whole** pool: the picker lists every
  session (claude and cursor alike, distinguished by name + cwd), and the cycle
  walks all of them. This is inherent to the flat pool (Decision 1); called out
  explicitly because it's the deliberate contrast with `<M-n>`, which is the
  one nav key that *is* agent-scoped.

### 4. Pre-warm — claude only

Keep pre-warming just `claude` (the primary); Cursor cold-starts on first
creation via `<leader>an`. Warming two would double the startup cost the whole pre-warm hack
exists to hide. Guards 1/2 already match `name == 'claude'` specifically, so a
live cursor session neither suppresses nor hijacks the claude pre-warm — the
`ai.lua:416` comment already anticipated a second tool being re-added.

### 5. Sends — agent-agnostic, target the current/last-used window (no work)

The context-send family — `<leader>at` (+ visual), `ap`, `af`, `ac`, `ae`,
`aE`, `ab`, `aq`, visual `as`, and the `ao` prompt — should always land in the
**last-used / current** sidekick window, whichever agent it is (or a non-agent
detail: it's just "the active session"). This already works and needs no change:

- **Routing:** `M.send` sends to `M.active`, and the `WinEnter` stamp
  (`sidekick_cli`) keeps `M.active` equal to whichever CLI window you last
  entered — claude or cursor. So sends follow focus, agent-agnostically, with a
  second running session never triggering a pick-a-target flow.
- **Formatting:** the refs (`@file#L42`, `@file#L10-20`, `@file`) come from the
  **global** `ai_context.overrides` renderer (`Config.cli.context`), which is
  tool-agnostic. Cursor confirmed (2026-07-21) it parses all three forms — `@`
  as path sugar, `#L` as a 1-based line/range, relative-to-cwd. So cursor
  sessions need **no per-tool `format`**: the bare cursor preset + the existing
  global renderer just work. *(Narrowed 2026-07-22: that covers the overridden
  family — `{this}`/`{function}`/`{class}`/`{quickfix}` — and file-only refs.
  Diagnostics (`<leader>ae`/`aE`) bypass the overrides and emit sidekick's
  stock ` :L10-L20` form, which only claude's per-tool `format` hook rewrites
  to `#L`. Verified 2026-07-22: cursor-agent resolves the stock form too — no
  `format` shim needed.)*

### 6. Visual cue — not needed (agent TUIs self-identify)

No winbar/statusline agent tag. The two agents' TUIs look different enough
(Claude Code vs cursor-agent) that you can tell which panel you're in at a
glance, with the `<leader>al` picker's name + cwd as a backstop. This closes
critique #7 (the `<M-n>` agent-scoped vs `<M-]>`/`<M-[>` pool-wide asymmetry):
the cue is the panel itself, not a keymap or added chrome. A dedicated status
indicator, if ever wanted, belongs to the
[sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) work, not
here.

<a id="implementation-plan"></a>
## Implementation plan (2026-07-22)

All in `ai.lua` unless noted; statusline fix in `statusline.lua`; keymaps in
`keymaps.lua`; docs in `GUIDE.md` plus one README cross-ref. An adversarial
review of this plan against the sidekick source is folded in — the load-guard
hardening, guard ordering, `statusline.lua`, and diagnostics-send items below
came out of it.

> **Load-bearing invariant: every session name begins with its agent token.**
> `claude`, `claude 2`, `cursor`, `cursor 3`, `claude: foo`, `cursor: bar` — all
> prefixed by their agent (the number is a shared global counter, so it's the
> *prefix* that carries agent identity, not contiguous per-agent numbering).
> There is no separate agent field: a dynamic session's
> preset is keyed by its name, so `tool.name` *is* the session name, and the
> agent is recovered by parsing the leading token (`^(claude|cursor)\b`). Every
> name producer (`new_session`, `_next_auto_name`, `create_session`) must uphold
> this, and every agent-scoped consumer (binary selection, `<M-n>` fork,
> anti-cosmetic-bug guard) depends on it. Break it in one place and
> agent-recovery silently misroutes.

### Amendments to the locked UX (2026-07-22)

- **Bare name first (auto-naming).** If no session named exactly `<agent>` is
  running, blank/auto naming uses the bare agent name (`cursor`); otherwise
  `<agent> <n>` from the shared global counter. So the first blank-created
  cursor session is `cursor`, later ones `cursor <n>`. Applies to `<leader>an`
  blank-Enter *and* the `<M-n>` fork — so `<M-n>` from `cursor 2` with bare
  `cursor` dead yields `cursor`, not `cursor 3` (accepted; it's still a new
  session). Supersedes the earlier "auto name is always `<agent> <n>`"; the
  counter stays single and global.
- **The picker costs one extra Enter** (see Decision 2's amendment).
- *(2026-07-22 follow-up: the picker currently ranks `cursor` first as a
  trial — `<CR><CR>` makes a cursor session; TODO in `new_session` to
  consider reverting to claude-first. Home base is unchanged: pre-warm and
  fallback stay claude.)*

### ai.lua changes

Constants + parse at the top of the file (above `local M = ...` so the
pre-packadd section can use them):

```lua
local AGENTS = { 'claude', 'cursor' }   -- AGENTS[1] is the primary / home base
local PRIMARY = AGENTS[1]

-- Strict anchored name → agent parse over the closed agent set. The name IS
-- the identity ('cursor', 'cursor 2', 'claude: foo'); next char must be
-- ' ' or ':' so 'claude: cursor-migration' parses as claude.
local function agent_of(name)
  for _, a in ipairs(AGENTS) do
    if name == a or name:find('^' .. a .. '[ :]') then return a end
  end
end
```

Then, in file order:

1. **`M = { active = PRIMARY, ... }`; `fallback_active` returns `PRIMARY`** —
   behaviourally identical (claude stays home base; its name-sort already
   favours `claude` < `cursor`, the owned asymmetry in Decision 1).
2. **Prune loop keeps both agents** (`vim.tbl_contains(AGENTS, name)`).
   Comment rewrite: the launcher stays unbound *by design* (single door), not
   because only one tool exists — and cursor's preset is bare (`cmd`/
   `is_proc`/`url`, no `sessions()` scanner), so the shell-out trap the prune
   exists for doesn't return.
3. **Pre-warm `'claude'` literals → `PRIMARY`** (Guard 1, `cli.show`,
   Guard 2, `cli.hide`). Guards stay tool-specific: live cursor sessions
   neither suppress nor hijack the claude pre-warm.
4. **Cursor load-guard** beside the claude `format` guard. `tool.get` never
   throws for a missing preset — the risk is indexing `.config.cmd[1]` on the
   `config = {}` it returns, which unguarded would abort `ai.lua` before
   `return M` and take every AI keymap down. Guard the whole access,
   notify-and-continue (same containment rationale as the claude guard):

   ```lua
   local ok, t = pcall(function()
     return require('sidekick.cli.tool').get('cursor').config
   end)
   if not ok or type(t.cmd) ~= 'table' or t.cmd[1] ~= 'cursor-agent' then
     vim.notify('sidekick: cursor preset missing/reshaped — cursor sessions may spawn the wrong binary',
       vim.log.levels.ERROR)
   end
   ```

5. **`M._next_auto_name(agent)`** returns `agent .. ' ' .. n`; single global
   `M._auto_seq`, floored over **both** agents' `^<agent> (%d+)$` names so a
   re-source can't collide with any live numbered session.
6. **`auto_name(agent)`** — the bare-first rule, shared by blank-Enter and
   `<M-n>`:

   ```lua
   local function auto_name(agent)
     if #require('sidekick.cli.state').get({ name = agent, started = true }) == 0 then
       return agent
     end
     return M._next_auto_name(agent)
   end
   ```

7. **`create_session(name)`** — the load-bearing fix. Both guards
   `notify + return` **before** `set_active`/`show_solo` (else a missing
   binary wedges `M.active` on an unspawnable built-in name, which the detach
   sweep never GCs since built-ins aren't in `_dynamic`):
   - `agent_of(name)` nil → ERROR-notify + return (a non-parsing name means a
     producer broke the prefix invariant; never silently default).
   - `vim.fn.executable(tool.get(agent).config.cmd[1]) == 0` → notify +
     return (agent-generic missing-binary guard; replaces the silent
     instantly-dying terminal).
   - Only then clone **the agent's own preset**
     (`vim.deepcopy(require('sidekick.cli.tool').get(agent).config)`), then
     the existing `set_active` + `show_solo`.
8. **`M.new_auto()`** (`<M-n>`):
   `create_session(auto_name(agent_of(M.active) or PRIMARY))` — forks the
   active session's agent. `<M-l>`/`<M-]>`/`<M-[>` unchanged — pool-wide.
9. **`M.new_session()`** (`<leader>an`): `vim.ui.select(AGENTS, ...)` (claude
   first → default highlight) wrapping the existing `vim.ui.input`; `<Esc>`
   at either step cancels; prompt de-clauded
   (`('New %s session (blank = auto): '):format(agent)`); label branch
   `agent .. ': ' .. input`, blank branch `auto_name(agent)`; the ≥16-char
   label warning unchanged.
10. **Comment sweep:** module header, `_next_auto_name` examples,
    `create_session`'s "clone claude's preset", the prune/`<leader>as` note.

Unchanged by design: `M.send`/WinEnter routing, `show_solo`, the detach
sweep, `<M-l>`/`<M-]>`/`<M-[>`/`<C-]>` (pool-wide), `ai_context.lua`,
`pickers/aibuffers.lua` (routes through `ai.send`, file-only refs). The
in-CLI `u` is per-agent since the 2026-07-22 follow-up: Ctrl+_ in claude,
Ctrl+U (kill-line) in cursor — the original "benign no-op" assumption was
wrong; binary inspection showed cursor-agent has no input-undo at all and
0x1F *cycles the model* there. Details in `ai.lua`'s keymap comment and
GUIDE.md.

### statusline.lua

The focused-CLI label matches `bufname:match('/bin/(%w+)$')` /
`('/bin/(%w+):')` against `known_clis` — `%w+` stops at `cursor-agent`'s
hyphen, so a cursor panel falls through to the raw `term://…` path. Broaden
the captures to `[%w-]+`, add `cursor-agent` to `known_clis`, and map its
display name to `Cursor` (naive title-casing yields "Cursor-agent CLI").

### keymaps.lua

`<leader>an` desc → agent-picker wording; the section-header comment
de-clauded; the stale `<leader>as` reservation comment rewritten (cursor now
*is* in `cli.tools`; the launcher stays unbound by design); the `<leader>ad`
confirm comment's "Claude conversation" generalized.

### Docs (same commit as the code)

- **GUIDE.md AI section:** `<leader>an` paragraph (picker, +1 Enter,
  bare-first naming, `cursor: label`); `<M-n>` prose + table row
  (agent-scoped fork, bare-resurrect note); "no tool launcher" rationale
  (single door, not single-tool prune); sessions paragraph (clone the
  *agent's* preset, name-prefix invariant, claude-only pre-warm); `u`-in-CLI
  claude-specific note.
- **GUIDE.md "Sidekick's session backends shell out on every lookup":** fix
  the counts (12 → 2 tools kept; `sk/cli/cursor.lua` *is* now dofile'd) while
  preserving the safety argument — cursor's preset is bare, no scanner.
- **README.md:** one cross-ref line in `## Cursor CLI (cursor-agent)` to the
  nvim integration; no setup change.

### Verification

Smoke: `env -u NVIM nvim --headless "+lua require('ai');
io.stderr:write('AI_LOADED\n')" +q 2>&1` — assert `AI_LOADED` appears
(flatten-proof; bare exit-0 proves nothing) and no `sidekick:` guard notify.

Manual:
1. `<leader>an` `<CR>` `<CR>` → new claude session (one extra Enter,
   accepted).
2. `<leader>an` → cursor → blank → session `cursor` running `cursor-agent`;
   statusline shows a Cursor label, not a raw `term://` path.
3. `<M-n>` in the cursor panel → `cursor <n>` (bare `cursor` is running); in
   a claude panel it still forks claude.
4. `<leader>at` (normal + visual) / `<leader>ap` into cursor → refs resolve.
5. `<leader>ae` into cursor — arrives as stock ` :L<a>-L<b>` (no claude
   rewrite); if cursor-agent doesn't resolve it, add a minimal cursor
   `format` shim (claude's `:L` → `#L` gsub) and record the outcome here.
6. `<leader>al` lists mixed sessions; `<M-]>`/`<M-[>` cycle across agents.
7. Kill the last cursor session (`<leader>ad`) → active falls back to claude.
8. Missing binary (strip `~/.local/bin` from PATH): pick cursor → clear
   notify, `M.active` unchanged, nothing leaked (check `<leader>al`).
9. Pre-warm still warms exactly one claude with a cursor session alive.

## Open / next

All resolved 2026-07-22:

- ~~Fill in the implementation details~~ — see
  [Implementation plan](#implementation-plan).
- ~~Verify pre-warm guards / detach sweep with a cursor session~~ — verified
  inert (verification steps 7/9 passed).
- ~~Verify diagnostics sends resolve in cursor-agent~~ — they do, in the
  stock ` :L` form; no `format` shim needed (verification step 5 passed).

<a id="out-of-scope-until-asked"></a>

## Out of scope (until asked)

Deliberately *not* in this change; noted so they're a conscious deferral, not an
oversight. Don't build these until explicitly requested.

- **Per-agent contiguous numbering.** The global counter (Decision 2;
  implementation-plan change #5) yields mixed sequences like `claude 2`,
  `cursor 3` (bare-first naming doesn't change this — it only affects the
  *first* blank-created session of an agent). That's fine — simple and
  correct. Making each agent number from 1 independently (`claude 2`,
  `cursor 2`) would need `M._auto_seq` to go per-agent; revisit only if the
  mixed numbering ever actually bothers you.
- **Winbar/statusline agent tag.** Not needed — the agent TUIs self-identify
  (Decision 6). If ever wanted, it rides with the
  [sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) status
  work, not here.
- **Cursor as a persistent home base.** `fallback_active` stays claude-first
  (Decision 1's owned asymmetry). Teaching it to prefer the last-used agent is a
  later call, only if Cursor becomes a working default.
