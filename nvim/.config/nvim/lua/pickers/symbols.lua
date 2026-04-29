-- pickers/symbols.lua — VSCode-style workspace + document symbol pickers.
--
-- WORKSPACE PICKER (M.workspace, bound to <leader>ss)
--   1. cwd filter: when lua_ls is attached, drop symbols outside the project
--      root. lua_ls + lazydev otherwise return neovim runtime + mason library
--      symbols, drowning project results. Other LSPs already scope correctly.
--   2. Symbol-first display: kind icon, name (with match highlights), client
--      name, dimmed relative path — instead of telescope's default file-first
--      columns. Vertical layout puts the preview below the results.
--   3. Score by symbol name only: ordinal = symbol_name, so a query like
--      `picker` ranks an exact `picker` match above unrelated symbols whose
--      file path happens to contain `picker`.
--   4. Highlight match characters only on the name. Telescope+fzf-native's
--      auto-highlighter runs against the displayed string, so it would
--      otherwise light up matches inside the path too. Suppressed via a
--      sorter wrapper; highlights are computed inside entry.display using
--      vim.fn.matchfuzzypos.
--
-- DOCUMENT PICKER (M.document, bound to <leader>sS)
--   Same display family (icon + name), plus a kind-word column and line
--   number. Kind word is included in the ordinal so typing "function" or
--   "variable" filters by kind alongside name search. Single file, single
--   LSP, so no path or client column is needed.
--
-- Only these pickers use the customizations below; other pickers and the
-- global telescope sorter are untouched.

local builtin       = require('telescope.builtin')
local conf          = require('telescope.config').values
local entry_display = require('telescope.pickers.entry_display')
local make_entry    = require('telescope.make_entry')

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

-- Resolve "which LSP would have produced this symbol" by mapping the result's
-- filetype to an attached client. Telescope's lsp_dynamic_workspace_symbols
-- merges results from all clients without preserving client_id, so we
-- reconstruct it here. Cached per-call to avoid repeated filetype matching.
local function client_resolver()
  local cache    = {}
  local clients  = vim.lsp.get_clients()
  return function(filename)
    local ft = cache[filename]
    if ft == nil then
      ft = vim.filetype.match({ filename = filename }) or false
      cache[filename] = ft
    end
    if not ft then return '' end
    for _, c in ipairs(clients) do
      if vim.tbl_contains(c.config.filetypes or {}, ft) then
        return c.name
      end
    end
    return ''
  end
end

local M = {}

function M.workspace()
  local has_lua_ls = #vim.lsp.get_clients({ name = 'lua_ls' }) > 0
  local cwd        = vim.uv.cwd()
  local base       = make_entry.gen_from_lsp_symbols({})
  local resolve_client = client_resolver()

  -- Size the client column to the longest attached client name; falls back to
  -- a sensible minimum for projects with no LSP yet attached.
  local client_width = 6
  for _, c in ipairs(vim.lsp.get_clients()) do
    client_width = math.max(client_width, vim.fn.strdisplaywidth(c.name))
  end

  local displayer = entry_display.create({
    separator = SEPARATOR,
    items = {
      { width = ICON_WIDTH },
      { width = NAME_WIDTH },
      { width = client_width },
      { remaining = true },
    },
  })

  local current_prompt = ''

  -- Wrap the configured sorter to suppress fzf-native's display-string
  -- highlighter. Scoring still flows through the underlying sorter against
  -- entry.ordinal (which we set to symbol_name).
  local symbol_sorter = setmetatable({
    highlighter = function() return {} end,
  }, { __index = conf.generic_sorter({}) })

  builtin.lsp_dynamic_workspace_symbols(vim.tbl_extend('force', VERTICAL_LAYOUT, {
    prompt_title = 'Workspace Symbols',
    sorter       = symbol_sorter,
    on_input_filter_cb = function(input)
      current_prompt = input or ''
    end,
    entry_maker = function(item)
      local entry = base(item)
      if not entry or not entry.filename then return nil end
      if has_lua_ls and not vim.startswith(entry.filename, cwd) then
        return nil
      end

      entry.ordinal = entry.symbol_name or ''
      entry.display = function(e)
        local icon, icon_hl = kind_icon(e.symbol_type)
        local name    = e.symbol_name or ''
        local client  = resolve_client(e.filename)
        local relpath = vim.fn.fnamemodify(e.filename, ':.')

        -- Byte offset of the name column in the rendered string. The icon may
        -- be a multi-byte glyph displayed in 1 cell; entry_display pads with
        -- ASCII spaces (1 byte each) to ICON_WIDTH cells.
        local icon_cells = vim.fn.strdisplaywidth(icon)
        local pad_cells  = math.max(0, ICON_WIDTH - icon_cells)
        local name_col   = #icon + pad_cells + #SEPARATOR

        local name_hls = {}
        if current_prompt ~= '' and name ~= '' then
          local _, positions = vim.fn.matchfuzzypos({ name }, current_prompt)
          if positions and positions[1] then
            for _, byte_idx in ipairs(positions[1]) do
              table.insert(name_hls, {
                { name_col + byte_idx, name_col + byte_idx + 1 },
                'TelescopeMatching',
              })
            end
          end
        end

        return displayer({
          { icon, icon_hl },
          { name, function() return name_hls end },
          { client, 'Comment' },
          { relpath, 'Comment' },
        })
      end

      return entry
    end,
  }))
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
