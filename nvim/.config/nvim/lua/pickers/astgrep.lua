-- pickers/astgrep.lua — live structural (AST) search (<leader>sa project,
-- <leader>sA current file). Pattern syntax, keys, and worked examples:
-- GUIDE.md "Structural search (ast-grep)".
--
-- Every keystroke re-runs `ast-grep run --json=stream --pattern <prompt>`
-- (snacks' proc finder: args array, no shell — quotes in patterns are safe)
-- and decodes the JSONL into jumpable items. ast-grep reads from disk, so
-- unsaved edits aren't matched.
--
-- Language: defaults to the current buffer's filetype via the allowlist
-- below; <M-l> in the picker switches it. A filetype NOT in the allowlist
-- falls back to omitting --lang (ast-grep infers per file extension) — an
-- unsupported --lang value exits 2 with no stdout, which with notify=false
-- would look like a silently-empty picker, hence allowlist not passthrough.

local M = {}

-- filetype -> ast-grep --lang value. Only names the installed binary accepts
-- (verified against ast-grep 0.45; `sh` and `typescriptreact` are rejected,
-- hence the aliases).
local FT_TO_LANG = {
  lua = 'lua', rust = 'rust', go = 'go', python = 'python',
  typescript = 'typescript', tsx = 'tsx', typescriptreact = 'tsx',
  javascript = 'javascript', javascriptreact = 'javascript',
  bash = 'bash', sh = 'bash', markdown = 'markdown', yaml = 'yaml',
  json = 'json', c = 'c', cpp = 'cpp', html = 'html', css = 'css',
  ruby = 'ruby',
}

-- Choices for the <M-l> switcher: unique langs + auto (no --lang).
local AUTO = 'auto (all languages)'
local LANG_CHOICES = (function()
  local seen, out = {}, {}
  for _, lang in pairs(FT_TO_LANG) do
    if not seen[lang] then seen[lang] = true; out[#out + 1] = lang end
  end
  table.sort(out)
  table.insert(out, 1, AUTO)
  return out
end)()

-- ast-grep's range columns are *character* offsets; extmarks/cursor want
-- bytes. Convert against the matched physical line (strict=false clamps).
local function byte_col(line, char_col)
  local ok, col = pcall(vim.str_byteindex, line, 'utf-32', char_col, false)
  return ok and col or char_col
end

-- One JSONL line -> snacks item (grep.lua's field contract: file/pos/
-- end_pos for preview+jump+qf, `line` for display, `text` for the matcher,
-- `positions` for the in-row match highlight). `msg.lines` holds the full
-- source lines spanning the match; start.column indexes the first,
-- end.column the last.
local function to_item(item, cwd)
  local ok, msg = pcall(vim.json.decode, item.text)
  if not ok or type(msg) ~= 'table' or not msg.range then return false end
  local first = msg.lines:match('^[^\n]*')
  local last = msg.lines:match('[^\n]*$')
  item.cwd = cwd
  item.file = msg.file
  item.pos = { msg.range.start.line + 1, byte_col(first, msg.range.start.column) }
  item.end_pos = { msg.range['end'].line + 1, byte_col(last, msg.range['end'].column) }
  item.line = first
  item.text = msg.file .. ':' .. item.pos[1] .. ': ' .. first
  -- Highlight the matched span within the row (SnacksPickerSearch), like
  -- grep rows: 1-based byte indices into `line`. Multi-line matches
  -- highlight to the end of the first line.
  local stop = item.pos[1] == item.end_pos[1] and item.end_pos[2] or #first
  local positions = {}
  for i = item.pos[2] + 1, stop do positions[#positions + 1] = i end
  item.positions = #positions > 0 and positions or nil
end

---@param opts? { scope?: 'project'|'file' }
function M.search(opts)
  opts = opts or {}
  local file_scope = opts.scope == 'file'
  local target -- file-scope only: absolute path (relative breaks outside cwd)
  if file_scope then
    target = vim.api.nvim_buf_get_name(0)
    if target == '' then
      vim.notify('ast-grep: no file for this buffer', vim.log.levels.WARN)
      return
    end
  end
  local lang = FT_TO_LANG[vim.bo.filetype]
  local cwd = vim.fn.getcwd()
  -- Visual selection seeds the prompt. visual() self-guards (nil outside
  -- visual mode) and exits visual mode itself; newlines flatten to spaces —
  -- the prompt is one line, and Lua is newline-insensitive.
  local vis = Snacks.picker.util.visual()

  return Snacks.picker.pick({
    -- Distinct sources so sa/sA don't toggle-close each other (same trap as
    -- pickers/qfhistory.lua); same-key re-press still toggle-closes itself.
    source = file_scope and 'astgrep_file' or 'astgrep',
    title = 'ast-grep (' .. (lang or 'auto') .. (file_scope and ', file' or '') .. ')',
    live = true,
    supports_live = true,
    format = 'file',
    show_empty = true,
    search = vis and vis.text:gsub('%s*\n%s*', ' ') or nil,
    lang = lang, -- read back by the finder; <M-l> action rewrites it
    finder = function(popts, ctx)
      if ctx.filter.search == '' then return function() end end
      -- ` -- ` splits pattern from raw CLI args (live-grep convention).
      local pattern, pargs = Snacks.picker.util.parse(ctx.filter.search)
      local args = { 'run', '--json=stream', '--pattern', pattern }
      if popts.lang then vim.list_extend(args, { '--lang', popts.lang }) end
      -- Honor snacks' stock <a-h>/<a-i> toggles (title chips + resume for
      -- free; the toggle actions just flip these opts and re-run us).
      if popts.hidden then vim.list_extend(args, { '--no-ignore', 'hidden' }) end
      if popts.ignored then vim.list_extend(args, { '--no-ignore', 'vcs', '--no-ignore', 'dot' }) end
      vim.list_extend(args, pargs)
      if target then args[#args + 1] = target end
      return require('snacks.picker.source.proc').proc(ctx:opts({
        cmd = 'ast-grep',
        args = args,
        cwd = cwd,
        notify = false, -- half-typed patterns exit non-zero constantly
        transform = function(item) return to_item(item, cwd) end,
      }), ctx)
    end,
    actions = {
      astgrep_lang = function(picker)
        vim.ui.select(LANG_CHOICES, { prompt = 'ast-grep language' }, function(choice)
          if not choice then return end
          local new_lang = choice ~= AUTO and choice or nil
          picker.opts.lang = new_lang
          picker.init_opts.lang = new_lang -- so <leader>sr resume keeps it
          picker.list:set_target()
          picker:find()
        end)
      end,
    },
    win = {
      input = {
        keys = {
          -- mode i too — a bare string binds normal-mode only, dead while
          -- live-typing. Shadows the global <A-l> "Split: wider" inside the
          -- picker input (buffer-local, deliberate).
          ['<M-l>'] = { 'astgrep_lang', mode = { 'i', 'n' }, desc = 'Switch language' },
        },
      },
    },
  })
end

return M
