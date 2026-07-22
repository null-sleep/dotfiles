# Add Cursor alongside Claude in sidekick

> **Status:** design settled (UX locked 2026-07-21; revised 2026-07-22 —
> dropped the dedicated `<leader>as` Cursor summon, `<leader>an`'s agent picker
> is now the single creation door). Implementation not started. This doc starts
> as the **UX/design decisions** and will grow implementation details as the
> change is built. Code is the source of truth once it lands.

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
highlight to `claude` with Enter-through, so a new Claude session costs no extra
keystroke over today's behaviour; picking `cursor` is the deliberate
one-extra-step case.

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
  global renderer just work.

### 6. Visual cue — not needed (agent TUIs self-identify)

No winbar/statusline agent tag. The two agents' TUIs look different enough
(Claude Code vs cursor-agent) that you can tell which panel you're in at a
glance, with the `<leader>al` picker's name + cwd as a backstop. This closes
critique #7 (the `<M-n>` agent-scoped vs `<M-]>`/`<M-[>` pool-wide asymmetry):
the cue is the panel itself, not a keymap or added chrome. A dedicated status
indicator, if ever wanted, belongs to the
[sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) work, not
here.

## Code changes (outline — details TBD)

All in `ai.lua` unless noted; keymaps in `keymaps.lua`; docs in `GUIDE.md`
(and README if any setup step changes).

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

1. **`create_session` clones the session's own tool preset**, not always
   claude's — the load-bearing fix that makes name → binary real. The
   name → agent parse must be a **strict anchored prefix** over the closed
   agent set (`^(claude|cursor)\b`), so a label like picking *claude* + typing
   `cursor-migration` (→ `claude: cursor-migration`) can't mis-parse and spawn
   the wrong binary — the exact "name is cosmetic" bug this change kills,
   reintroduced worse if the parse is loose.
2. **`_next_auto_name` gains an agent arg, keeps the single global counter** —
   name = `<agent> <n>` where `n` is the existing global high-water mark
   (`M._auto_seq`). Numbers are shared across agents, so a run may yield
   `claude 2`, `cursor 3`, `claude 4` — non-contiguous per agent, deliberately
   (see [Out of scope](#out-of-scope-until-asked)). What matters is the agent
   *prefix* upholding the invariant, not contiguous numbering.
3. **Keep `cursor` in `cli.tools`** — drop it from the claude-only prune loop
   (`ai.lua:155`). One extra static preset; the perf concern there was the
   *discovery* backends shelling out, which stay stubbed.
4. **Hoist prewarm's hardcoded `'claude'` to a `PRIMARY` constant**; claude-only
   pre-warm otherwise unchanged (guards already tool-specific).
5. **`fallback_active` keeps `claude` as home base** — its name-sort already
   puts `claude` ahead of `cursor`, so this is consistent for free (the owned
   asymmetry in Decision 1).
6. **`M.new_session` (`<leader>an`) gains an agent-pick step** — a
   `vim.ui.select({'claude','cursor'})` (snacks, matching the config) before
   the existing label `vim.ui.input`; **default the highlight to `claude` with
   Enter-through** so the common new-Claude path costs no extra keystroke;
   `<Esc>` at either step cancels. The chosen agent threads through to
   `create_session` and `_next_auto_name`.
7. **`M.new_auto` / `<M-n>`** forks the active session's agent instead of always
   claude. `<M-l>`/`<M-]>`/`<M-[>` need no change — already pool-wide.
8. **Add a load-guard for the cursor preset** analogous to `ai.lua:515` (which
   only checks claude's `format`), so a reshaped/missing cursor preset surfaces
   at startup instead of silently spawning the wrong binary.
9. **Guard a missing `cursor-agent` binary** — before spawning a cursor session,
   check `vim.fn.executable('cursor-agent')` and `notify` if absent, instead of
   spawning a terminal that dies immediately. The detach sweep's never-attached
   GC (`ai.lua:276`) already cleans up the leaked name, so nothing wedges — this
   just replaces a silent flinch with a clear message. In scope for the build.
10. **Docs:** GUIDE.md AI keymap table gains the `<leader>an` agent-pick note and
   the agent-aware `<M-n>` note; per repo rules the doc update lands in the same
   change. (No new keymap — `<leader>an` already exists.)

## Open / next

- Fill in the implementation details for each numbered change above (exact
  signatures, where the agent name is threaded through `new_session` →
  `create_session` / `new_auto`, and the anchored name → agent parse).
- Verify a cursor session doesn't perturb the pre-warm guards or the detach
  sweep in practice (should be inert, but confirm).

<a id="out-of-scope-until-asked"></a>

## Out of scope (until asked)

Deliberately *not* in this change; noted so they're a conscious deferral, not an
oversight. Don't build these until explicitly requested.

- **Per-agent contiguous numbering.** The global counter (Decision 2, change #2)
  yields mixed sequences like `claude 2`, `cursor 3`. That's fine — simple and
  correct. Making each agent number from 1 independently (`claude 2`, `cursor 2`)
  would need `M._auto_seq` to go per-agent; revisit only if the mixed numbering
  ever actually bothers you.
- **Winbar/statusline agent tag.** Not needed — the agent TUIs self-identify
  (Decision 6). If ever wanted, it rides with the
  [sidekick-agent-event-pipeline.md](sidekick-agent-event-pipeline.md) status
  work, not here.
- **Cursor as a persistent home base.** `fallback_active` stays claude-first
  (Decision 1's owned asymmetry). Teaching it to prefer the last-used agent is a
  later call, only if Cursor becomes a working default.
