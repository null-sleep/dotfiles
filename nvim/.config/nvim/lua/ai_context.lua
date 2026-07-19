-- Claude-native `@file#L<n>`/`@file#L<a>-<b>` context refs, registered as
-- sidekick cli.context overrides for `{position}`/`{function}`/`{class}` in
-- ai.lua's setup — covers <leader>at/af/ac ({this} maps to {position} for
-- file buffers).
--
-- Why override: sidekick's own renderers emit an off-by-one column, a
-- type/name prefix that's unreliable across languages, and only the START of
-- a function/class. Claude Code's native mention shape is the line-granular
-- `#L` form (sidekick's own claude hook already rewrites linewise ranges to
-- it), so emit that directly.
--
-- No `require('sidekick.*')` anywhere: this must load while sidekick.nvim is
-- still downloading (ai.lua's packadd pcall) and from pickers without
-- ai.lua's side effects — M.is_file inlines sidekick's Loc.is_file.
--
-- Drift risk (nothing asserts these): assumes sidekick keeps (a)
-- Config.cli.context checked before built-ins, (b) {this} → {position} for
-- file buffers, (c) the ctx shape (1-based row/col), and (d)
-- textobject_at_point's signature. All failures are soft — stock :L:C
-- output, or af/ac no-op — so either symptom after a plugin update means
-- one of these moved.

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

  -- Self-quote: the claude format hook only quotes SidekickLocFile-highlighted
  -- chunks, which plain-string returns bypass — reproduce its rule here.
  -- Quotes wrap the NAME only; `#L…` stays outside.
  if name:find('[^%w/_%.%-]') then name = '"' .. name .. '"' end

  local ref = '@' .. name
  -- nil from = file-only ref (a legitimate caller shape, not an error).
  if from ~= nil then
    ref = ref .. '#L' .. from
    -- `to and to ~= from`: `nil ~= 72` is true in Lua (would concat nil for
    -- from-only callers); `to == from` collapses to one line, not `#L5-5`.
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

  -- textobject_at_point wants a (1,0)-based pos but ctx.col is 1-based, so
  -- col - 1. (Sidekick passes ctx.col raw — that IS its off-by-one bug.)
  local shared = require('nvim-treesitter-textobjects.shared')
  local ok, range = pcall(shared.textobject_at_point, query, 'textobjects', ctx.buf, { ctx.row, ctx.col - 1 })
  if not ok or not range then return nil end

  -- Range6 is 0-based, end-EXCLUSIVE: ecol > 0 → last 1-based line is
  -- erow + 1; ecol == 0 → the end sits at col 0 of the line AFTER the last
  -- content line, so last = erow. (Verified: animal.go Describe() → #L70-76.)
  local srow, _, _, erow, ecol = unpack(range)
  local last = ecol == 0 and erow or erow + 1
  return M.ref(vim.api.nvim_buf_get_name(ctx.buf), ctx.cwd, srow + 1, last)
end

-- Overrides `{quickfix}` (<leader>aq): stock's bullet list with `#L` refs
-- instead of `:L:C` locations; entry text collapsed to one line.
local function quickfix(ctx)
  local info = vim.fn.getqflist({ items = 0, title = 0 })
  if not info.items or #info.items == 0 then return nil end
  local lines = {}
  local title = info.title or ''
  if title ~= '' and not title:match('^:%S') then
    lines[#lines + 1] = 'Quickfix: ' .. title
  end
  for _, item in ipairs(info.items) do
    local name = item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_get_name(item.bufnr) or ''
    local from = item.lnum and item.lnum > 0 and item.lnum or nil
    local to = item.end_lnum and item.end_lnum > 0 and item.end_lnum or nil
    local parts = { '-', name ~= '' and M.ref(name, ctx.cwd, from, to) or '@[No Name]' }
    if item.type and item.type ~= '' then
      parts[#parts + 1] = ('[%s]'):format(item.type:upper())
    end
    local text = (item.text or ''):gsub('%s+', ' '):gsub('%s+$', '')
    if text ~= '' then parts[#parts + 1] = text end
    lines[#lines + 1] = table.concat(parts, ' ')
  end
  return lines
end

-- Covers <leader>at/af/ac/aq (looked up before sidekick's built-ins).
M.overrides = {
  position = position,
  ['function'] = function(ctx) return textobject(ctx, '@function.outer') end,
  class = function(ctx) return textobject(ctx, '@class.outer') end,
  quickfix = quickfix,
}

return M
