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
--   Both modes also share:
--     1. cwd filter when lua_ls is attached anywhere in the session: drop
--        symbols outside the project root, otherwise lua_ls + lazydev
--        flood the picker with neovim runtime + mason library symbols.
--        Other LSPs already scope to the workspace.
--     2. Score by name_query only (first prompt token). entry.ordinal is
--        the bare symbol name; an __index sorter wrapper rewrites the
--        prompt to its first token before delegating to generic_sorter.
--        fzf-native's space-as-AND tokenization would otherwise drop
--        every entry the moment the user typed a space, since the path
--        token has nothing in the ordinal to match.
--     3. Match-character highlights on the name only, computed against
--        name_query. Telescope+fzf-native's auto-highlighter is suppressed
--        via the sorter's highlighter override; highlights are computed
--        inside entry.display using vim.fn.matchfuzzypos. Path-cell
--        highlights are intentionally omitted — entry_display byte offsets
--        through the multi-byte name pad and dynamic client column are
--        awkward to compute, and the filter is the load-bearing UX.
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

local channel         = require('plenary.async.control').channel
local actions         = require('telescope.actions')
local builtin         = require('telescope.builtin')
local conf            = require('telescope.config').values
local entry_display   = require('telescope.pickers.entry_display')
local finders         = require('telescope.finders')
local make_entry      = require('telescope.make_entry')
local pickers         = require('telescope.pickers')

local SYMBOL_KIND     = vim.lsp.protocol.SymbolKind -- numeric kind -> string label

local ICON_WIDTH      = 2                           -- display cells reserved for the kind icon
local NAME_WIDTH      = 30                          -- display cells reserved for the symbol name
local KIND_WIDTH      = 13                          -- longest LSP kind label is "TypeParameter" (13 chars)
local SEPARATOR       = '  '                        -- two spaces between columns

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
-- These are Unicode private-use-area code points (nf-md-* range); actual
-- glyph rendering is font-specific. Sizing here is tuned for Hack Nerd Font.
-- Highlight groups still come from mini.icons so colors match the rest of
-- the editor.
local KIND_ICONS      = {
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

-- Highlight group per LSP kind, populated lazily on first kind_icon call.
-- Lazy (rather than at module load) because mini.icons may itself load
-- lazily — by the time the user opens the picker it's reliably available,
-- but at require time of this module it may not be. Once populated, every
-- kind_icon call is two table lookups; the previous shape ran a pcall +
-- require + icons.get on every visible row, every redraw.
local KIND_HLS

local function init_kind_hls()
    KIND_HLS = {}
    local ok, mini_icons = pcall(require, 'mini.icons')
    if not ok then return end
    for kind in pairs(KIND_ICONS) do
        local _, hl = mini_icons.get('lsp', kind:lower())
        KIND_HLS[kind] = hl
    end
end

local function kind_icon(symbol_type)
    if not KIND_HLS then init_kind_hls() end
    local kind = symbol_type or ''
    return KIND_ICONS[kind] or '·', KIND_HLS[kind] or 'Comment'
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

-- Split the prompt at the first run of whitespace. First token is the
-- symbol-name query (sent to the LSP, scored against entry.ordinal); the
-- remainder is the path query (used to fuzzy-narrow results by relpath).
-- Empty prompt → both empty. Whitespace-only prompt → both empty.
local function split_prompt(prompt)
    prompt = prompt or ''
    local name, path = prompt:match('^(%S*)%s+(.*)$')
    return name or prompt, path or ''
end

-- Sorter that scores against the first prompt token only, delegating to
-- the configured generic_sorter. Without this rewrite, fzf-native treats
-- "foo bar" as AND-of-tokens against entry.ordinal (= symbol name), and
-- the "bar" token — meant for the path filter, not the name — would drop
-- every entry.
--
-- Built as an __index wrapper around the inner sorter (rather than via
-- Sorter:new) because fzf-native's scoring_function reads self.prompt_cache
-- which is initialized lazily on its `start` method. With Sorter:new,
-- telescope dispatches start/finish to the wrapper and they never reach
-- the inner sorter, so prompt_cache stays nil and scoring crashes — the
-- visible symptom is an empty result list. The __index pattern lets
-- start/finish/etc. fall through to inner; we pass `wrapper` as self in
-- scoring_function so cache writes done by inner during start land on
-- the same table inner reads from later.
-- Highlighter is stubbed: fzf-native would otherwise re-highlight using the
-- full prompt against the rendered row (icon + name + client + path),
-- conflicting with the per-cell highlights set in entry.display.
local function first_token_sorter()
    local inner = conf.generic_sorter({})
    local wrapper
    wrapper = setmetatable({
        scoring_function = function(_, prompt, line, entry)
            local name_query = split_prompt(prompt)
            if name_query == '' then return -1 end
            return inner.scoring_function(wrapper, name_query, line, entry)
        end,
        highlighter = function() return {} end,
    }, { __index = inner })
    return wrapper
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
    local pending   = {} -- client_id -> request_id

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

    maybe_done() -- in case every request failed to dispatch synchronously

    return function()
        for client_id, req_id in pairs(pending) do
            local client = vim.lsp.get_client_by_id(client_id)
            if client then client:cancel_request(req_id) end
        end
    end
end

-- DATA FLOW (workspace picker, per keystroke):
--   1. User types          → on_input_filter_cb sets current_prompt.
--   2. Telescope's dynamic finder calls make_requester(scope)(prompt).
--   3. make_requester       splits prompt into name_query + path_query,
--                           cancels any prior in-flight request, fans
--                           workspace/symbol(name_query) to LSPs,
--                           normalizes responses via convert_symbols,
--                           precomputes item.relpath, then narrows by
--                           path_query via vim.fn.matchfuzzy(key='relpath').
--   4. entry_maker          turns each item into a Telescope entry with
--                           ordinal = item.name (path is *not* in ordinal).
--   5. first_token_sorter   scores entries by name_query only, delegating
--                           to fzf-native's generic_sorter on that token.
--   6. entry.display(e)     renders each visible row; name_match_highlights
--                           lights up matching chars in the name column,
--                           computed against split_prompt(current_prompt).
--
-- Per-prompt requester for finders.new_dynamic. `scope` is 'all' (every
-- session client) or 'buffer' (clients attached to the current buffer).
-- No caching — the dynamic finder refires on every keystroke; cancel()
-- aborts the previous in-flight LSP request, so re-issuing on each
-- path-token edit is the simplest correct shape.
local function make_requester(scope)
    local cancel = function() end

    return function(prompt)
        cancel()

        local name_query, path_query = split_prompt(prompt)
        if name_query == '' then return {} end

        local pool = scope == 'buffer'
            and vim.lsp.get_clients({ bufnr = 0 })
            or vim.lsp.get_clients()

        local clients = vim.tbl_filter(function(c)
            local caps = c.server_capabilities
            return caps and caps.workspaceSymbolProvider
        end, pool)

        if #clients == 0 then return {} end

        local tx, rx = channel.oneshot()
        cancel = request_all(clients, { query = name_query }, tx)

        local responses = rx()
        local items = {}
        for _, res in pairs(responses) do
            if res.result then
                for _, item in ipairs(convert_symbols(res.result, res.client.name)) do
                    table.insert(items, item)
                end
            end
        end

        -- Stash a project-relative path on every item up front. Two consumers
        -- read it: the path filter below (matchfuzzy needs the field for its
        -- `key` lookup) and entry.display (the path column renders this same
        -- string). Computing it once here avoids a second fnamemodify per
        -- visible row on every redraw, and keeps the filter scoring against
        -- exactly what the user sees in the path column — typing "utils"
        -- shouldn't earn extra score from "/Users/dhruv/..." chars.
        for _, item in ipairs(items) do
            item.relpath = vim.fn.fnamemodify(item.filename, ':.')
        end

        if path_query ~= '' then
            items = vim.fn.matchfuzzy(items, path_query, { key = 'relpath' })
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
    local columns     = {
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
    table.insert(columns, { remaining = true }) -- path

    local displayer = entry_display.create({ separator = SEPARATOR, items = columns })

    local current_prompt = ''

    -- Telescope pipeline glue: every item produced by make_requester (the
    -- dynamic finder's fn) is fed through entry_maker to become a Telescope
    -- entry. Required fields:
    --   value    — the source item (used by previewer / actions)
    --   ordinal  — the string the sorter scores against (bare symbol name)
    --   display  — fn(entry) → rendered row (string + per-cell highlights)
    -- The lua_ls cwd guard drops items outside the project root: lua_ls +
    -- lazydev otherwise return Neovim runtime and Mason library symbols that
    -- swamp the picker. Skipped when lua_ls isn't attached anywhere.
    -- entry.display closes over `current_prompt`, which on_input_filter_cb
    -- (below) updates on every keystroke; the highlight pass uses the first
    -- token of that prompt so match-chars only light up in the name column.
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
            -- Project-relative path, precomputed in make_requester. Used both
            -- for the path-narrow fuzzy filter and for the rendered path cell.
            relpath     = item.relpath,
            ordinal     = item.name,
            display     = function(e)
                local icon, icon_hl = kind_icon(e.symbol_type)
                local name_query    = split_prompt(current_prompt)
                local hls           = name_match_highlights(e.symbol_name, name_query, name_byte_col(icon))

                local cells         = {
                    { icon,          icon_hl },
                    { e.symbol_name, function() return hls end },
                }
                if show_client then
                    table.insert(cells, { e.client_name or '', 'Comment' })
                end
                table.insert(cells, { e.relpath, 'Comment' })
                return displayer(cells)
            end,
        }
    end

    pickers.new(VERTICAL_LAYOUT, {
        prompt_title       = show_client and 'Workspace Symbols (all LSPs)' or 'Workspace Symbols (buffer LSP)',
        finder             = finders.new_dynamic({
            fn          = make_requester(scope),
            entry_maker = entry_maker,
        }),
        previewer          = conf.qflist_previewer({}),
        sorter             = first_token_sorter(),
        on_input_filter_cb = function(input)
            current_prompt = input or ''
        end,
        attach_mappings    = function(_, map)
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
            { remaining = true }, -- line number
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
                    { icon,       icon_hl },
                    name,
                    { kind_label, 'TelescopeResultsField' },
                    { lnum,       'Comment' },
                })
            end

            return entry
        end,
    }))
end

return M
