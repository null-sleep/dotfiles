-- pickers/symbols.lua — VSCode-style workspace + document symbol pickers.
--
-- WORKSPACE PICKER (M.workspace, bound to <leader>ss)
--   Two modes, switched by M.toggle_buffer_only() (bound to <leader>ts):
--
--   * Multi-LSP (default): fan workspace/symbol out to every active LSP
--     client, not just the ones attached to the current buffer. Lets you
--     search Go symbols from a markdown buffer when gopls is alive on
--     another buffer. See neovim/neovim#24799 for the upstream-blessed
--     pattern. snacks' builtin lsp_workspace_symbols only queries
--     buffer-attached clients, which is why this stays custom. Display
--     columns: kind icon, symbol name, kind, lsp name, path:line,
--     source line (treesitter-highlighted).
--
--   * Buffer-only: query only clients attached to the current buffer.
--     Same columns minus the lsp one (one client per buffer in
--     practice → column is noise).
--
--   Both modes share a single normalized item shape produced by
--   convert_symbols():
--
--     { kind, name, filename, lnum, col, client_name }
--
--   This bypasses vim.lsp.util.symbols_to_items (which formats text as
--   "[Kind] name in containerName"): gopls populates containerName with
--   the package import path, which would leak "in _/Users/.../pkg" into
--   the name column. We read symbol.name directly off the LSP response
--   instead, so every server's results render uniformly.
--
--   PROMPT GRAMMAR: split at the first whitespace. The first token is
--   the symbol-name query — sent to the LSP and used for ranking. The
--   remainder narrows results by file path via vim.fn.matchfuzzy on the
--   relative path. Examples:
--     "render"        → name=render, no path filter
--     "render utils"  → name=render, results restricted to paths
--                       fuzzy-matching "utils"
--     "render a b"    → name=render, path query is "a b"
--   Empty name_query is not sent to the LSP — most servers return
--   nothing for an empty query, we short-circuit to an empty result
--   list.
--
--   The picker runs in snacks live mode (the prompt re-fires the finder
--   per keystroke). In live mode snacks' fuzzy matcher does not score, so
--   the finder itself ranks items by name_query via vim.fn.matchfuzzy and
--   `sort = {fields = {'idx'}}` preserves that order. <c-g> buffers results
--   into the fuzzy matcher, which scores item.text = everything the row
--   displays (name, kind, client, path — name first so it dominates), so
--   the frozen set can be refined by any visible info; field-scoped
--   queries (kind:class, client_name:gopls, relpath:go$) work there too.
--
--   Both modes also share:
--     1. cwd filter when lua_ls is attached anywhere in the session: drop
--        symbols outside the project root, otherwise lua_ls + lazydev
--        flood the picker with neovim runtime + mason library symbols.
--        Other LSPs already scope to the workspace.
--     2. Match-character highlights on the name only, computed against
--        name_query with vim.fn.matchfuzzypos inside the format function
--        (snacks computes no match positions in live mode). Path-cell
--        highlights are intentionally omitted — the filter is the
--        load-bearing UX.
--     3. Vertical layout (preview below results) pinned regardless of
--        terminal width (the global default would switch to horizontal on
--        wide terminals, which doesn't suit tall symbol lists).
--
-- DOCUMENT PICKER (M.document, bound to <leader>sd)
--   Single-buffer outline. Wraps snacks' builtin lsp_symbols with the
--   kind filter fully opened up (the builtin hides variables/fields in
--   several filetypes by default; this picker navigates to any binding)
--   and a flat, line-sorted list (tree = false). Columns: icon, name,
--   kind word, line number, source line (treesitter-highlighted). The
--   builtin puts the kind in item.text so typing "function" / "variable"
--   filters by kind alongside name search. Opens preselected on the
--   symbol at/nearest above the cursor ("where am I") once the first
--   matcher pass materializes items (the same matcher-done hook snacks'
--   own resume uses).
--
-- SOURCE-LINE COLUMN (both pickers)
--   The trailing column renders the symbol's actual line of code through
--   Snacks.picker.highlight.format, which treesitter-highlights the
--   string by the file's language and caches per item. Loaded buffers are
--   read via the API; other files from disk (readfile(f, '', lnum) reads
--   only the first lnum lines), fetched lazily per visible row.

local Async = require('snacks.picker.util.async')

local SYMBOL_KIND = vim.lsp.protocol.SymbolKind -- numeric kind -> string label

local ICON_WIDTH = 2 -- display cells reserved for the kind icon
local NAME_WIDTH = 30 -- display cells reserved for the symbol name
local KIND_WIDTH = 13 -- longest LSP kind label is "TypeParameter" (13 chars)
local LNUM_WIDTH = 5 -- display cells reserved for the line number
local PATH_WIDTH = 38 -- display cells for the workspace picker's path:line cell
local SEPARATOR = '  ' -- two spaces between columns

-- Always use vertical layout (preview below results) — symbol lists are tall
-- by nature, so vertical is better regardless of terminal width; pinned here
-- rather than letting the global width-based preset switch to horizontal.
local VERTICAL_LAYOUT = {
  preset = 'vertical',
  layout = { width = 0.9, height = 0.9 },
}

-- Material-design-leaning glyphs that render at letter-height. Overrides
-- mini.icons' codicon set for this picker only — codicons are designed for
-- VSCode's narrow sidebar and look smaller than text in terminal nerd fonts.
-- These are Unicode private-use-area code points (nf-md-* range); actual
-- glyph rendering is font-specific. Sizing here is tuned for Hack Nerd Font.
-- Highlight groups still come from mini.icons so colors match the rest of
-- the editor.
local KIND_ICONS = {
  Array = '󰅪',
  Boolean = '󰨙',
  Class = '󰌗',
  Constant = '󰏿',
  Constructor = '󰒓',
  Enum = '󰕘',
  EnumMember = '󰕘',
  Event = '󱐋',
  Field = '󰜢',
  File = '󰈙',
  Folder = '󰉋',
  Function = '󰊕',
  Interface = '󰕮',
  Key = '󰌋',
  Method = '󰊕',
  Module = '󰅩',
  Namespace = '󰦮',
  Null = '󰟢',
  Number = '󰎠',
  Object = '󰅩',
  Operator = '󰪚',
  Package = '󰏗',
  Property = '󰖷',
  String = '󰀬',
  Struct = '󰙅',
  TypeParameter = '󰬛',
  Variable = '󰀫',
}

-- Highlight group per LSP kind, populated lazily on first kind_icon call.
-- Lazy (rather than at module load) because mini.icons may itself load
-- lazily — by the time the user opens the picker it's reliably available,
-- but at require time of this module it may not be. Once populated, every
-- kind_icon call is two table lookups.
local KIND_HLS

local function init_kind_hls()
  KIND_HLS = {}
  local ok, mini_icons = pcall(require, 'mini.icons')
  if not ok then
    return
  end
  for kind in pairs(KIND_ICONS) do
    local _, hl = mini_icons.get('lsp', kind:lower())
    KIND_HLS[kind] = hl
  end
end

local function kind_icon(symbol_type)
  if not KIND_HLS then
    init_kind_hls()
  end
  local kind = symbol_type or ''
  return KIND_ICONS[kind] or '·', KIND_HLS[kind] or 'Comment'
end

-- Append the symbol-name column to `ret` as matched/unmatched runs so only
-- the matching characters light up (SnacksPickerMatch), padded/truncated to
-- exactly NAME_WIDTH display cells. Positions come from vim.fn.matchfuzzypos
-- against the full name; multi-byte names render unhighlighted (byte-run
-- splitting would risk cutting a UTF-8 sequence, and symbol names are
-- effectively always ASCII).
local function name_cells(name, name_query, ret)
  local truncated = vim.api.nvim_strwidth(name) > NAME_WIDTH
  local prefix = truncated and vim.fn.strcharpart(name, 0, NAME_WIDTH - 1) or name

  local pos_set
  if name_query ~= '' and #name == vim.fn.strchars(name) then
    local _, positions = vim.fn.matchfuzzypos({ name }, name_query)
    if positions and positions[1] and #positions[1] > 0 then
      pos_set = {}
      for _, p in ipairs(positions[1]) do
        pos_set[p] = true
      end
    end
  end

  if pos_set then
    local i, n = 0, #prefix
    while i < n do
      local j = i
      local matched = pos_set[i] or false
      while j < n and (pos_set[j] or false) == matched do
        j = j + 1
      end
      ret[#ret + 1] = { prefix:sub(i + 1, j), matched and 'SnacksPickerMatch' or nil }
      i = j
    end
  elseif #prefix > 0 then
    ret[#ret + 1] = { prefix }
  end

  if truncated then
    ret[#ret + 1] = { '…' }
  end
  local pad = NAME_WIDTH - vim.api.nvim_strwidth(prefix) - (truncated and 1 or 0)
  if pad > 0 then
    ret[#ret + 1] = { (' '):rep(pad) }
  end
end

-- Split the prompt at the first run of whitespace. First token is the
-- symbol-name query (sent to the LSP, used for ranking); the remainder is
-- the path query (used to fuzzy-narrow results by relpath). Empty prompt →
-- both empty. Whitespace-only prompt → both empty.
local function split_prompt(prompt)
  prompt = prompt or ''
  local name, path = prompt:match('^(%S*)%s+(.*)$')
  return name or prompt, path or ''
end

-- gopls embeds the package import path directly into `symbol.name` for
-- top-level decls (e.g. `_/Users/dhruv/src/dotfiles.Cat`) — that's not
-- containerName, it's literally what the server returns as the name. Strip
-- the path prefix when the name looks path-qualified (contains a `/`),
-- keeping just the segment after the final dot. Names without a slash
-- (e.g. `Dog.Name`, qualified Lua field) are left intact since the dot is
-- meaningful structure, not a package separator.
local function clean_symbol_name(name)
  if name:find('/', 1, true) then
    return name:match('([^.]+)$') or name
  end
  return name
end

-- Normalized item produced by convert_symbols(). Both workspace modes (and
-- any future caller) consume items in this exact shape.
--
--   kind        — string label from vim.lsp.protocol.SymbolKind
--   name        — the bare symbol name (cleaned of gopls path prefixes)
--   filename    — absolute path resolved from `symbol.location.uri`
--   lnum, col   — 1-indexed (col is character offset; close enough for
--                 navigation, exact byte positioning is reserved for the
--                 jump itself)
--   client_name — `client.name` of the LSP that returned this symbol
local function convert_symbols(symbols, client_name)
  local items = {}
  for _, sym in ipairs(symbols or {}) do
    local loc = sym.location
    if loc and loc.uri and loc.range then
      table.insert(items, {
        kind = SYMBOL_KIND[sym.kind] or 'Unknown',
        name = clean_symbol_name(sym.name or ''),
        filename = vim.uri_to_fname(loc.uri),
        lnum = loc.range.start.line + 1,
        col = loc.range.start.character + 1,
        client_name = client_name,
      })
    end
  end
  return items
end

-- Fan workspace/symbol out to every client. Returns a cancel fn that aborts
-- any in-flight requests (used when the user types a new prompt char before
-- the previous round has settled).
local function request_all(clients, params, on_done)
  local responses = {}
  local remaining = #clients
  local pending = {} -- client_id -> request_id

  local function maybe_done()
    if remaining == 0 then
      on_done(responses)
    end
  end

  for _, client in ipairs(clients) do
    local ok, req_id = client:request('workspace/symbol', params, function(err, result)
      responses[client.id] = { err = err, result = result, client = client }
      pending[client.id] = nil
      remaining = remaining - 1
      maybe_done()
    end)
    if ok then
      pending[client.id] = req_id
    else
      remaining = remaining - 1
    end
  end

  maybe_done() -- in case every request failed to dispatch synchronously

  return function()
    for client_id, req_id in pairs(pending) do
      local client = vim.lsp.get_client_by_id(client_id)
      if client then
        client:cancel_request(req_id)
      end
    end
  end
end

-- Lazy source-line access, cached per picker open. Loaded buffers are read
-- via the API; everything else from disk — readfile(f, '', lnum) reads only
-- the first lnum lines. snacks calls format only for visible rows, so this
-- stays cheap even for huge result sets.
local function make_source_line()
  local file_lines = {} -- filename -> { lines = {...}, upto = n }
  return function(filename, lnum)
    local buf = vim.fn.bufnr(filename)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      return vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
    end
    local cached = file_lines[filename]
    if not cached or cached.upto < lnum then
      local ok, lines = pcall(vim.fn.readfile, filename, '', lnum)
      cached = { lines = ok and lines or {}, upto = lnum }
      file_lines[filename] = cached
    end
    return cached.lines[lnum] or ''
  end
end

local M = {}

-- Module-level toggle. false = multi-LSP fan-out (default); true = clients
-- attached to current buffer only. Session-scoped: resets on Neovim restart.
local buffer_only = false

function M.toggle_buffer_only()
  buffer_only = not buffer_only
  vim.notify('Symbol search: ' .. (buffer_only and 'buffer LSP only' or 'all active LSPs'), vim.log.levels.INFO)
end

-- DATA FLOW (workspace picker, per keystroke):
--   1. User types             → snacks live mode re-runs the finder with
--                               ctx.filter.search as the prompt (the prior
--                               finder task is aborted; the abort hook
--                               cancels its in-flight LSP requests).
--   2. finder                 splits prompt into name_query + path_query,
--                             fans workspace/symbol(name_query) out via
--                             request_all, suspends the finder coroutine
--                             until every response lands (the same
--                             suspend/resume shape as snacks' own LSP
--                             source), normalizes via convert_symbols,
--                             applies the lua_ls cwd guard, narrows by
--                             path_query, then ranks by name_query — both
--                             via vim.fn.matchfuzzy.
--   3. sort = {'idx'}         preserves that finder ranking (the matcher
--                             does not score in live mode).
--   4. format                 renders each visible row; name_cells lights
--                             up matching chars in the name column only.
function M.workspace()
  local show_client = not buffer_only
  local scope = buffer_only and 'buffer' or 'all'
  -- Captured now, while the user's buffer is still current: inside the
  -- finder the current buffer is the picker's own prompt buffer, so a
  -- get_clients({ bufnr = 0 }) there would find no clients and buffer-only
  -- mode would always return nothing.
  local origin_buf = vim.api.nvim_get_current_buf()
  local has_lua_ls = #vim.lsp.get_clients({ name = 'lua_ls' }) > 0
  local cwd = vim.uv.cwd()
  local source_line = make_source_line()

  -- Client column is sized to the longest active session client name.
  local client_width = 6
  if show_client then
    for _, c in ipairs(vim.lsp.get_clients()) do
      client_width = math.max(client_width, vim.fn.strdisplaywidth(c.name))
    end
  end

  return Snacks.picker.pick({
    -- The lsp_ prefix matters: snacks' resume snapshots finder items only
    -- for lsp_*-named sources, so <leader>sr restores the frozen result
    -- list instead of re-firing the live LSP query.
    source = 'lsp_symbols_workspace',
    title = show_client and 'Workspace Symbols (all LSPs)' or 'Workspace Symbols (buffer LSP)',
    live = true,
    supports_live = true,
    sort = { fields = { 'idx' } },
    layout = VERTICAL_LAYOUT,
    finder = function(_, ctx)
      local name_query, path_query = split_prompt(ctx.filter.search)
      if name_query == '' then
        return {}
      end

      local pool = scope == 'buffer' and vim.lsp.get_clients({ bufnr = origin_buf }) or vim.lsp.get_clients()
      local clients = vim.tbl_filter(function(c)
        local caps = c.server_capabilities
        return caps and caps.workspaceSymbolProvider
      end, pool)
      if #clients == 0 then
        return {}
      end

      -- The producer coroutine is stepped by snacks' scheduler from a uv
      -- check handle — a *fast event context*, where nvim API and vim.fn
      -- calls are forbidden. Anything that touches them runs on the main
      -- loop via async:schedule (which suspends until the scheduled fn has
      -- run) — the same reason snacks' own LSP requester vim.schedule's its
      -- request dispatch.
      ---@async
      return function(cb)
        local async = Async.running()
        local responses
        local cancel_fn
        async:schedule(function()
          cancel_fn = request_all(clients, { query = name_query }, function(res)
            responses = res
            async:resume()
          end)
        end)
        async:on('abort', vim.schedule_wrap(function()
          if cancel_fn then
            cancel_fn()
          end
        end))
        while not responses and not async:aborted() do
          async:suspend()
        end
        if not responses then
          return -- aborted: a newer keystroke owns the picker now
        end

        local items = async:schedule(function()
          local out = {}
          for _, res in pairs(responses) do
            if res.result then
              for _, item in ipairs(convert_symbols(res.result, res.client.name)) do
                -- lua_ls cwd guard: lua_ls + lazydev otherwise return Neovim
                -- runtime and Mason library symbols that swamp the picker.
                if not (has_lua_ls and not vim.startswith(item.filename, cwd)) then
                  item.relpath = vim.fn.fnamemodify(item.filename, ':.')
                  out[#out + 1] = item
                end
              end
            end
          end

          if path_query ~= '' then
            out = vim.fn.matchfuzzy(out, path_query, { key = 'relpath' })
          end
          -- Rank (and filter) by fuzzy match on the name. Matches the old
          -- sorter's behavior: entries whose name doesn't fuzzy-match the
          -- first prompt token drop out even if the server returned them.
          return vim.fn.matchfuzzy(out, name_query, { key = 'name' })
        end)

        for _, item in ipairs(items or {}) do
          cb({
            -- What the fuzzy matcher scores after <c-g>: everything the row
            -- displays, so "class" or "gopls" or a path fragment filters
            -- too. Name first so it dominates ranking; field-scoped queries
            -- (kind:class, client_name:gopls, relpath:go$) also work since
            -- these are all item fields.
            text = item.name .. ' ' .. item.kind:lower() .. ' '
              .. (item.client_name or '') .. ' ' .. item.relpath,
            name = item.name,
            kind = item.kind,
            client_name = item.client_name,
            file = item.filename,
            pos = { item.lnum, item.col - 1 },
            relpath = item.relpath,
          })
        end
      end
    end,
    format = function(item, picker)
      local ret = {} ---@type snacks.picker.Highlight[]
      local icon, icon_hl = kind_icon(item.kind)
      ret[#ret + 1] = { Snacks.picker.util.align(icon, ICON_WIDTH), icon_hl }
      local name_query = split_prompt(picker:filter().search)
      name_cells(item.name, name_query, ret)
      ret[#ret + 1] = { SEPARATOR }
      ret[#ret + 1] = { Snacks.picker.util.align((item.kind or ''):lower(), KIND_WIDTH), 'Function' }
      ret[#ret + 1] = { SEPARATOR }
      if show_client then
        ret[#ret + 1] = { Snacks.picker.util.align(item.client_name or '', client_width), 'Comment' }
        ret[#ret + 1] = { SEPARATOR }
      end
      -- Truncate from the left ("…rc/pickers/symbols.lua:42"), not the right:
      -- the tail (filename + line) is what identifies the hit, the leading
      -- directories are the disposable part. align()'s own truncate cuts the
      -- wrong end, so truncate first and align the already-fitting string.
      local path = (item.relpath or '') .. ':' .. item.pos[1]
      path = Snacks.picker.util.truncate(path, PATH_WIDTH, true)
      ret[#ret + 1] = { Snacks.picker.util.align(path, PATH_WIDTH), 'Comment' }
      ret[#ret + 1] = { SEPARATOR }
      local trimmed = vim.trim(source_line(item.file, item.pos[1]))
      Snacks.picker.highlight.format(item, trimmed, ret)
      return ret
    end,
  })
end

function M.document()
  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
  local source_line = make_source_line()

  local picker = Snacks.picker.lsp_symbols({
    title = 'Document Symbols',
    layout = VERTICAL_LAYOUT,
    -- Flat, line-sorted list (no tree) — matches the old picker's outline.
    tree = false,
    -- Fully open up the kind filter so the picker can navigate to any
    -- binding (variables, fields, etc.). Every filetype key snacks defines
    -- must be overridden — a bare `default = true` would deep-merge *around*
    -- the built-in lua/markdown/help lists and keep hiding locals there.
    filter = { default = true, lua = true, markdown = true, help = true },
    format = function(item, _)
      local ret = {} ---@type snacks.picker.Highlight[]
      local icon, icon_hl = kind_icon(item.kind)
      ret[#ret + 1] = { Snacks.picker.util.align(icon, ICON_WIDTH), icon_hl }
      ret[#ret + 1] = { Snacks.picker.util.align(item.name or '', NAME_WIDTH, { truncate = true }) }
      ret[#ret + 1] = { SEPARATOR }
      ret[#ret + 1] = { Snacks.picker.util.align((item.kind or ''):lower(), KIND_WIDTH), 'Function' }
      ret[#ret + 1] = { SEPARATOR }
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.pos[1]), LNUM_WIDTH), 'Comment' }
      ret[#ret + 1] = { SEPARATOR }
      local trimmed = vim.trim(source_line(item.file, item.pos[1]))
      Snacks.picker.highlight.format(item, trimmed, ret)
      return ret
    end,
  })

  -- Preselect the symbol at (or nearest above) the cursor — "where am I".
  -- The LSP finder populates asynchronously, so this waits for the first
  -- matcher pass to materialize items (the same hook snacks' resume uses);
  -- the flag keeps later matcher runs (every keystroke) from yanking the
  -- selection back.
  local preselected = false
  picker.matcher.task:on('done', vim.schedule_wrap(function()
    if preselected or picker.closed then
      return
    end
    preselected = true
    local best_idx, best_dist
    for i, item in ipairs(picker:items()) do
      local lnum = item.pos and item.pos[1] or 0
      if lnum <= cursor_lnum and (not best_dist or cursor_lnum - lnum < best_dist) then
        best_dist = cursor_lnum - lnum
        best_idx = i
      end
    end
    if best_idx then
      picker.list:view(best_idx)
    end
  end))

  return picker
end

return M
