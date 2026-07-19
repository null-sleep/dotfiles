-- Claude-native `@file#L<n>`/`@file#L<a>-<b>` context ref builders, registered
-- as sidekick.nvim context overrides for `{position}`/`{function}`/`{class}`
-- (routed through by <leader>at (normal+visual), <leader>af, <leader>ac —
-- `{this}` maps to `{position}` for file buffers; wired in as `cli.context`
-- in ai.lua's sidekick.setup()).
--
-- Why: sidekick's own renderers emit a `:L<row>:C<col>` location whose
-- column is off by one on the textobject path (1-based col fed straight into
-- an API wanting (1,0)-based), prefixed with a treesitter type/name that's
-- unreliable across languages. Claude Code's native mention shape is
-- `@relpath#L<n>`/`@relpath#L<a>-<b>` (sidekick's own `sk/cli/claude.lua`
-- hook already rewrites its `:L1-L2` output into exactly this for linewise
-- ranges) — so we emit that shape directly and skip sidekick's column
-- tracking and name lookup entirely.
--
-- No `require('sidekick.*')` anywhere in this file: it must load during the
-- first-launch race where sidekick.nvim is still downloading (ai.lua's
-- packadd pcall) and be `require`-able from pickers without pulling in
-- ai.lua's setup side effects. `M.is_file` inlines sidekick's own
-- `Loc.is_file` rather than requiring `sidekick.cli.context.location`.

local M = {}

-- Shared ref builder (also used by pickers later for the same shape).
---@param name string absolute or relative file path
---@param cwd? string defaults to the cwd
---@param from? integer 1-based start line; omit for a file-only ref
---@param to? integer 1-based end line; omit (or == from) collapses to one line
function M.ref(name, cwd, from, to)
  -- relpath returns nil when `name` is already relative or outside `cwd` —
  -- keeping `name` unchanged in that case is the deliberate fallback.
  local ok, rel = pcall(vim.fs.relpath, cwd or vim.fn.getcwd(), name)
  if ok and rel and rel ~= '' and rel ~= '.' then name = rel end

  -- Self-quote: sidekick's claude format hook only quotes chunks it has
  -- highlighted `SidekickLocFile`; a plain-string context return like ours
  -- bypasses that pass, so reproduce its own rule
  -- (`str:find("[^%w/_%.%-]")`) here. Quotes wrap the NAME only — `#L…`
  -- stays outside, matching Claude Code's native mention shape.
  if name:find('[^%w/_%.%-]') then name = '"' .. name .. '"' end

  local ref = '@' .. name
  -- `from ~= nil`, not truthiness: nil is the real "no line info" signal —
  -- callers legitimately pass no `from` at all for file-only refs.
  if from ~= nil then
    ref = ref .. '#L' .. from
    -- `to and to ~= from`, in that order: `nil ~= 72` is true in Lua, so a
    -- bare `to ~= from` would concatenate nil for from-only callers.
    -- `to == from` collapses to a single line instead of `#L5-5`.
    if to and to ~= from then ref = ref .. '-' .. to end
  end
  return ref
end

-- Inlined from sidekick.cli.context.location's `Loc.is_file` — see header.
---@param buf integer
function M.is_file(buf)
  return vim.bo[buf].buflisted
    and (vim.bo[buf].buftype == '' or vim.bo[buf].buftype == 'help')
    and vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)) == 1
end

-- Overrides `{position}` (what `{this}` maps to for file buffers). ctx.range
-- is set only for a visual selection (rows pre-normalized upstream); columns
-- are deliberately dropped — Claude's `#L` mention is line-granular only.
local function position(ctx)
  if not M.is_file(ctx.buf) then return nil end -- sidekick then warns "Nothing to send."
  local from = ctx.range and ctx.range.from[1] or ctx.row
  local to = ctx.range and ctx.range.to[1] or nil
  return M.ref(vim.api.nvim_buf_get_name(ctx.buf), ctx.cwd, from, to)
end

-- Overrides `{function}`/`{class}`. Guard order mirrors sidekick's own
-- cli/context/textobject.lua:21-56, so this fails the same way (nil) when a
-- precondition (plugin/parser/query) is missing.
local function textobject(ctx, query)
  if not M.is_file(ctx.buf) then return nil end
  if not pcall(require, 'nvim-treesitter-textobjects.shared') then return nil end
  local ok_parser, parser = pcall(vim.treesitter.get_parser, ctx.buf)
  if not ok_parser or not parser then return nil end
  parser:parse()
  if not vim.treesitter.query.get(parser:lang(), 'textobjects') then return nil end

  -- Trap: textobject_at_point wants a (1,0)-based pos (nvim_win_get_cursor's
  -- convention — shared.lua only adjusts the row internally), but ctx.col is
  -- 1-based. Sidekick's own textobject.lua passes ctx.col raw — that IS its
  -- column off-by-one bug; do not copy that call.
  local shared = require('nvim-treesitter-textobjects.shared')
  local ok, range = pcall(shared.textobject_at_point, query, 'textobjects', ctx.buf, { ctx.row, ctx.col - 1 })
  if not ok or not range then return nil end

  -- Range6 is 0-based, end-exclusive: [srow, scol, sbyte, erow, ecol, ebyte].
  -- ecol > 0 means erow (0-based) IS the last content line -> 1-based last =
  -- erow + 1. ecol == 0 means the end sits at col 0 of the line AFTER the
  -- last content line, and that 0-based erow already equals that line's
  -- 1-based number, so last = erow. Verified against fixtures/animal.go's
  -- `func (z Zoo) Describe()` (1-based lines 70-76).
  local srow, _, _, erow, ecol = unpack(range)
  local last = ecol == 0 and erow or erow + 1
  return M.ref(vim.api.nvim_buf_get_name(ctx.buf), ctx.cwd, srow + 1, last)
end

-- Looked up by name from Config.cli.context BEFORE sidekick's own built-ins
-- (sidekick/cli/context/init.lua M.fn) — these three keys cover
-- <leader>at/af/ac.
M.overrides = {
  position = position,
  ['function'] = function(ctx) return textobject(ctx, '@function.outer') end,
  class = function(ctx) return textobject(ctx, '@class.outer') end,
}

return M
