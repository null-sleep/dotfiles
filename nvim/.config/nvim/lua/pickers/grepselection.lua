-- pickers/grepselection.lua — snacks picker over a literal grep of the current
-- visual selection, multi-line included. Bound to <leader>ss in visual mode;
-- complements <leader>sw (grep_word: whole-word) and live <leader>sg grep.
--
-- WHY CUSTOM (not Snacks.picker.grep_word with args): snacks' grep source
-- parses rg's output one physical line at a time, so a match spanning a
-- newline breaks the parser. `rg --json --multiline` instead emits each
-- match as one JSON line regardless of span, keeping parsing safe.
-- --fixed-strings makes the selection literal: no regex escaping, no word
-- boundaries, you find precisely what you selected.

local M = {}

local PATH_WIDTH = 40 -- display cells for the relpath:lnum column
local SEPARATOR = '  '

-- Parse `rg --json` stdout into picker items. Each "match" event is one JSON
-- line even when the match spans several source lines; d.lines.text holds the
-- whole matched block (first source line onward), so the first line is the
-- display text and the newline count is how many extra lines it covers.
local function parse(stdout, cwd)
  local items = {}
  for line in vim.gsplit(stdout or '', '\n', { plain = true }) do
    if line ~= '' then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and obj.type == 'match' then
        local d = obj.data
        local relpath = d.path.text
        local abs = relpath:sub(1, 1) == '/' and relpath or (cwd .. '/' .. relpath)
        local full = d.lines.text or '' -- whole matched block, keeps its newlines
        -- d.lines.text carries rg's trailing terminator; drop that one newline
        -- so a single-line match counts 0 extra lines.
        local block = full:gsub('\n$', '')
        local firstline = block:gsub('\n.*$', '')
        local extra = select(2, block:gsub('\n', '')) -- source lines beyond the first
        -- Submatch offsets are bytes into d.lines.text (col 0 = d.line_number).
        -- Walk `end` across newlines to a (row, col) so the preview can
        -- highlight the whole span (snacks draws pos→end_pos as one extmark).
        local sm = d.submatches[1] or { start = 0, ['end'] = #firstline }
        local prefix = full:sub(1, sm['end']) -- bytes before the match end
        local nl = select(2, prefix:gsub('\n', ''))
        local last_nl = 0
        do
          local p = prefix:find('\n')
          while p do last_nl, p = p, prefix:find('\n', p + 1) end
        end
        items[#items + 1] = {
          text = relpath .. ':' .. d.line_number .. ' ' .. firstline, -- what the matcher scores
          file = vim.fs.normalize(abs),
          pos = { d.line_number, sm.start },
          end_pos = { d.line_number + nl, sm['end'] - last_nl },
          relpath = relpath,
          firstline = firstline,
          extra = extra,
        }
      end
    end
  end
  return items
end

-- Search the current visual selection. Call from a visual-mode ('x') mapping:
-- Snacks' visual util reads it while the selection is still active, then exits
-- visual mode. rg runs async; the picker opens once results are in.
function M.search()
  local vis = Snacks.picker.util.visual()
  local sel = vis and vis.text
  if not sel or sel == '' then
    vim.notify('grep selection: no visual selection', vim.log.levels.WARN)
    return
  end

  local cwd = vim.uv.cwd()
  -- Flags mirror the snacks grep source (picker.lua): --hidden so dot-dirs
  -- like .config/ and .github/ are searched, .git and node_modules excluded.
  local cmd = {
    'rg', '--json', '--multiline', '--fixed-strings', '--smart-case',
    '--color=never', '--hidden', '--glob=!.git', '--glob=!node_modules', '--', sel,
  }
  vim.system(cmd, { text = true, cwd = cwd }, function(res)
    local items = parse(res.stdout, cwd)
    vim.schedule(function()
      if #items == 0 then
        vim.notify('grep selection: no matches', vim.log.levels.INFO)
        return
      end
      -- Title carries a one-line preview of the selection (newlines flattened
      -- to ⏎ so a multi-line span can't break the title bar).
      local preview = sel:gsub('\n', ' ⏎ ')
      if vim.api.nvim_strwidth(preview) > 50 then
        preview = vim.fn.strcharpart(preview, 0, 49) .. '…'
      end

      Snacks.picker.pick({
        source = 'grep_selection',
        items = items,
        title = 'Grep selection: ' .. preview,
        format = function(item, _)
          local ret = {} ---@type snacks.picker.Highlight[]
          -- relpath:lnum, truncated from the left so the identifying tail
          -- (filename + line) survives when the path is long.
          local path = Snacks.picker.util.truncate(item.relpath .. ':' .. item.pos[1], PATH_WIDTH, true)
          ret[#ret + 1] = { Snacks.picker.util.align(path, PATH_WIDTH), 'Comment' }
          ret[#ret + 1] = { SEPARATOR }
          if item.extra > 0 then -- badge multi-line matches with their extra span
            ret[#ret + 1] = { '+' .. item.extra .. '↵', 'Special' }
            ret[#ret + 1] = { ' ' }
          end
          Snacks.picker.highlight.format(item, vim.trim(item.firstline), ret)
          return ret
        end,
      })
    end)
  end)
end

return M
