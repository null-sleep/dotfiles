-- pickers/symbols.lua — VSCode-style workspace + document symbol pickers.
--
-- WORKSPACE PICKER (M.workspace, bound to <leader>ss)
--   Two modes, switched by M.toggle_buffer_only() (bound to <leader>ts):
--
--   * Multi-LSP (default): fan workspace/symbol out to every active LSP
--     client, not just the ones attached to the current buffer. Lets you
--     search Go symbols from a markdown buffer when gopls is alive on
--     another buffer. See neovim/neovim#24799 for the upstream-blessed
--     pattern. Display columns: kind icon, symbol name, lsp name, path.
--
--   * Buffer-only: query only clients attached to the current buffer.
--     Display columns: kind icon, symbol name, path (no lsp column —
--     one client per buffer in practice → column is noise).
--
--   Both modes share a single normalized item shape produced by
--   convert_symbols():
--
--     { kind, name, filename, lnum, col, client_name }
--
--   This bypasses vim.lsp.util.symbols_to_items (which formats text as
--   "[Kind] name in containerName") and telescope's gen_from_lsp_symbols
--   (which then captures "name in containerName" as the displayed symbol
--   name). gopls populates containerName with the package import path,
--   which leaks "in _/Users/.../pkg" into the name column under the
--   stock pipeline. We read symbol.name directly off the LSP response
--   instead, so every server's results render uniformly.
--
--   Both modes also share:
--     1. cwd filter when lua_ls is attached anywhere in the session: drop
--        symbols outside the project root, otherwise lua_ls + lazydev
--        flood the picker with neovim runtime + mason library symbols.
--        Other LSPs already scope to the workspace.
--     2. Score by symbol name only: ordinal = name, so a query like
--        `picker` ranks an exact `picker` match above unrelated symbols
--        whose file path happens to contain `picker`.
--     3. Match-character highlights on the name only. Telescope+fzf-native's
--        auto-highlighter runs against the displayed string, so it would
--        otherwise light up matches inside the path too. Suppressed via a
--        sorter wrapper; highlights are computed inside entry.display
--        using vim.fn.matchfuzzypos.
--     4. Vertical layout (preview below results, 50%) instead of the
--        global horizontal layout.
--
-- DOCUMENT PICKER (M.document, bound to <leader>sS)
--   Single-buffer outline. Reuses telescope's lsp_document_symbols (still
--   parsing item.text via gen_from_lsp_symbols) since document symbols
--   come from a single client and don't carry containerName ambiguity.
--   Columns: icon, name, kind word, line number. Kind is included in the
--   ordinal so typing "function" / "variable" filters by kind alongside
--   name search.

local channel       = require('plenary.async.control').channel
local actions       = require('telescope.actions')
local builtin       = require('telescope.builtin')
local conf          = require('telescope.config').values
local entry_display = require('telescope.pickers.entry_display')
local finders       = require('telescope.finders')
local make_entry    = require('telescope.make_entry')
local pickers       = require('telescope.pickers')

local SYMBOL_KIND = vim.lsp.protocol.SymbolKind  -- numeric kind -> string label

local ICON_WIDTH = 2     -- display cells reserved for the kind icon
local NAME_WIDTH = 30    -- display cells reserved for the symbol name
local KIND_WIDTH = 13    -- longest LSP kind label is "TypeParameter" (13 chars)
local SEPARATOR  = '  '  -- two spaces between columns

-- Vertical layout: prompt top, results middle, preview bottom (50%).
-- Overrides the global horizontal layout for symbol pickers only.
local VERTICAL_LAYOUT = {
  layout_strategy = 'vertical',
  layout_config = {
    vertical = {
      width           = 0.9,
      height          = 0.9,
      prompt_position = 'top',
      mirror          = true,
      preview_height  = 0.5,
    },
  },
}

-- Material-design-leaning glyphs that render at letter-height. Overrides
-- mini.icons' codicon set for this picker only — codicons are designed for
-- VSCode's narrow sidebar and look smaller than text in terminal nerd fonts.
-- Highlight groups still come from mini.icons so colors match the rest of
-- the editor.
local KIND_ICONS = {
  Array         = '󰅪',
  Boolean       = '󰨙',
  Class         = '󰌗',
  Constant      = '󰏿',
  Constructor   = '󰒓',
  Enum          = '󰕘',
  EnumMember    = '󰕘',
  Event         = '󱐋',
  Field         = '󰜢',
  File          = '󰈙',
  Folder        = '󰉋',
  Function      = '󰊕',
  Interface     = '󰕮',
  Key           = '󰌋',
  Method        = '󰊕',
  Module        = '󰅩',
  Namespace     = '󰦮',
  Null          = '󰟢',
  Number        = '󰎠',
  Object        = '󰅩',
  Operator      = '󰪚',
  Package       = '󰏗',
  Property      = '󰖷',
  String        = '󰀬',
  Struct        = '󰙅',
  TypeParameter = '󰬛',
  Variable      = '󰀫',
}

local function kind_icon(symbol_type)
  local kind  = symbol_type or ''
  local icon  = KIND_ICONS[kind] or '·'
  local hl    = 'Comment'
  local ok, icons = pcall(require, 'mini.icons')
  if ok then
    local _, mini_hl = icons.get('lsp', kind:lower())
    if mini_hl then hl = mini_hl end
  end
  return icon, hl
end

-- Byte offset where the name column starts in the rendered string. The icon
-- may be a multi-byte glyph displayed in 1 cell; entry_display pads with
-- ASCII spaces (1 byte each) to ICON_WIDTH cells.
local function name_byte_col(icon)
  local icon_cells = vim.fn.strdisplaywidth(icon)
  local pad_cells  = math.max(0, ICON_WIDTH - icon_cells)
  return #icon + pad_cells + #SEPARATOR
end

local function name_match_highlights(name, prompt, name_col)
  local hls = {}
  if prompt == '' or name == '' then return hls end
  local _, positions = vim.fn.matchfuzzypos({ name }, prompt)
  if positions and positions[1] then
    for _, byte_idx in ipairs(positions[1]) do
      table.insert(hls, {
        { name_col + byte_idx, name_col + byte_idx + 1 },
        'TelescopeMatching',
      })
    end
  end
  return hls
end

-- Wrap the configured sorter to suppress fzf-native's display-string
-- highlighter. Scoring still flows through the underlying sorter against
-- entry.ordinal (which we set to the bare symbol name).
local function name_only_sorter()
  return setmetatable({
    highlighter = function() return {} end,
  }, { __index = conf.generic_sorter({}) })
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
        kind        = SYMBOL_KIND[sym.kind] or 'Unknown',
        name        = clean_symbol_name(sym.name or ''),
        filename    = vim.uri_to_fname(loc.uri),
        lnum        = loc.range.start.line + 1,
        col         = loc.range.start.character + 1,
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
  local pending   = {}  -- client_id -> request_id

  local function maybe_done()
    if remaining == 0 then on_done(responses) end
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

  maybe_done()  -- in case every request failed to dispatch synchronously

  return function()
    for client_id, req_id in pairs(pending) do
      local client = vim.lsp.get_client_by_id(client_id)
      if client then client:cancel_request(req_id) end
    end
  end
end

-- Per-prompt requester for finders.new_dynamic. `scope` is 'all' (every
-- session client) or 'buffer' (clients attached to the current buffer).
local function make_requester(scope)
  local cancel = function() end

  return function(prompt)
    cancel()

    local pool = scope == 'buffer'
      and vim.lsp.get_clients({ bufnr = 0 })
      or  vim.lsp.get_clients()

    local clients = vim.tbl_filter(function(c)
      local caps = c.server_capabilities
      return caps and caps.workspaceSymbolProvider
    end, pool)

    if #clients == 0 then return {} end

    local tx, rx = channel.oneshot()
    cancel = request_all(clients, { query = prompt }, tx)

    local responses = rx()
    local items = {}
    for _, res in pairs(responses) do
      if res.result then
        for _, item in ipairs(convert_symbols(res.result, res.client.name)) do
          table.insert(items, item)
        end
      end
    end

    return items
  end
end

local M = {}

-- Module-level toggle. false = multi-LSP fan-out (default); true = clients
-- attached to current buffer only. Session-scoped: resets on Neovim restart.
local buffer_only = false

function M.toggle_buffer_only()
  buffer_only = not buffer_only
  vim.notify(
    'Symbol search: ' .. (buffer_only and 'buffer LSP only' or 'all active LSPs'),
    vim.log.levels.INFO)
end

function M.workspace()
  local show_client = not buffer_only
  local scope       = buffer_only and 'buffer' or 'all'
  local has_lua_ls  = #vim.lsp.get_clients({ name = 'lua_ls' }) > 0
  local cwd         = vim.uv.cwd()

  -- Build columns: icon, name, [client], path. Client column is sized to
  -- the longest active session client name when shown.
  local columns = {
    { width = ICON_WIDTH },
    { width = NAME_WIDTH },
  }
  if show_client then
    local client_width = 6
    for _, c in ipairs(vim.lsp.get_clients()) do
      client_width = math.max(client_width, vim.fn.strdisplaywidth(c.name))
    end
    table.insert(columns, { width = client_width })
  end
  table.insert(columns, { remaining = true })  -- path

  local displayer = entry_display.create({ separator = SEPARATOR, items = columns })

  local current_prompt = ''

  local entry_maker = function(item)
    if has_lua_ls and not vim.startswith(item.filename, cwd) then return nil end

    return {
      value       = item,
      filename    = item.filename,
      path        = item.filename,
      lnum        = item.lnum,
      col         = item.col,
      symbol_name = item.name,
      symbol_type = item.kind,
      client_name = item.client_name,
      ordinal     = item.name,
      display     = function(e)
        local icon, icon_hl = kind_icon(e.symbol_type)
        local relpath = vim.fn.fnamemodify(e.filename, ':.')
        local hls     = name_match_highlights(e.symbol_name, current_prompt, name_byte_col(icon))

        local cells = {
          { icon, icon_hl },
          { e.symbol_name, function() return hls end },
        }
        if show_client then
          table.insert(cells, { e.client_name or '', 'Comment' })
        end
        table.insert(cells, { relpath, 'Comment' })
        return displayer(cells)
      end,
    }
  end

  pickers.new(VERTICAL_LAYOUT, {
    prompt_title = show_client and 'Workspace Symbols (all LSPs)' or 'Workspace Symbols (buffer LSP)',
    finder = finders.new_dynamic({
      fn          = make_requester(scope),
      entry_maker = entry_maker,
    }),
    previewer = conf.qflist_previewer({}),
    sorter    = name_only_sorter(),
    on_input_filter_cb = function(input)
      current_prompt = input or ''
    end,
    attach_mappings = function(_, map)
      map('i', '<c-space>', actions.to_fuzzy_refine)
      return true
    end,
  }):find()
end

function M.document()
  local base = make_entry.gen_from_lsp_symbols({})

  -- Telescope's `symbols` opt filters by LSP kind. Default here is unfiltered
  -- so the picker can navigate to any binding (variables, fields, etc.).
  -- To restrict to "structural" symbols (top-level navigation only — what
  -- VSCode's outline shows by default), pass:
  --   symbols = { 'function', 'method', 'class', 'struct', 'interface',
  --               'module', 'constructor' }
  -- as an opt to lsp_document_symbols below.

  local doc_displayer = entry_display.create({
    separator = SEPARATOR,
    items = {
      { width = ICON_WIDTH },
      { width = NAME_WIDTH },
      { width = KIND_WIDTH },
      { remaining = true },  -- line number
    },
  })

  builtin.lsp_document_symbols(vim.tbl_extend('force', VERTICAL_LAYOUT, {
    prompt_title = 'Document Symbols',
    entry_maker  = function(item)
      local entry = base(item)
      if not entry then return nil end

      local kind = entry.symbol_type or ''
      -- Include kind in the ordinal so typing "function" / "variable" filters
      -- by kind alongside the name search. fzf-native's default highlighter
      -- (not suppressed here) lights up matches in both name and kind columns.
      entry.ordinal = (entry.symbol_name or '') .. ' ' .. kind

      entry.display = function(e)
        local icon, icon_hl = kind_icon(e.symbol_type)
        local name = e.symbol_name or ''
        local kind_label = (e.symbol_type or ''):lower()
        local lnum = e.lnum and tostring(e.lnum) or ''

        return doc_displayer({
          { icon, icon_hl },
          name,
          { kind_label, 'TelescopeResultsField' },
          { lnum, 'Comment' },
        })
      end

      return entry
    end,
  }))
end

return M
