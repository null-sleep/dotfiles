local M = {}

function M.strip_trailing_ws(first, last)
  local view = vim.fn.winsaveview()
  vim.cmd(('keepjumps keeppatterns %d,%ds/\\s\\+$//e'):format(first, last))
  vim.fn.winrestview(view)
end

-- Characters/patterns that mark a line as "structural" — never join a
-- structural line onto the previous line as a continuation.
local structural_starts = {
  '^%-%-%-',           -- --- separator
  '^[%-%*%+%•]%s',    -- ASCII bullets and •
  '^[\226\200\147]%s', -- – en-dash (U+2013, UTF-8: E2 80 93)
  '^[\226\143\186]',   -- ⏺ record symbol (U+23FA, UTF-8: E2 8F BA)
  '^%d+[%.%)]%s',      -- numbered items: "1. " or "1) "
  '^#+%s',             -- markdown headings
  '^>%s',              -- blockquotes
  '^|',                -- tables
}

local terminal_punct = '[%.%!%?%:%)"\'%]%}]$'

local function is_structural(line)
  for _, pat in ipairs(structural_starts) do
    if line:match(pat) then return true end
  end
  return false
end

local function ends_sentence(line)
  return line:match(terminal_punct) ~= nil
end

function M.clean_pasted(first, last)
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)

  -- Normalize NBSP (U+00A0, UTF-8: C2 A0) to regular space, then strip
  -- leading/trailing whitespace and strip ⏺ prefix from Claude UI bullets.
  for i, line in ipairs(lines) do
    line = line:gsub('\194\160', ' ')
    line = line:gsub('^%s+', ''):gsub('%s+$', '')
    -- Strip Claude Code's ⏺ turn marker (keep the text after it)
    line = line:gsub('^[\226\143\186]%s*', '')
    lines[i] = line
  end

  -- Single-pass reflow: join line[i+1] onto line[i] iff:
  --   - line[i] doesn't end in sentence-terminal punctuation, AND
  --   - line[i+1] doesn't look structural (bullet, separator, heading, etc.)
  -- Blank lines always flush and are preserved as paragraph breaks.
  local out = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line == '' then
      table.insert(out, '')
      i = i + 1
    else
      -- Accumulate continuations
      while i < #lines do
        local next = lines[i + 1]
        if next == '' or is_structural(next) or ends_sentence(line) then
          break
        end
        line = line .. ' ' .. next
        i = i + 1
      end
      -- Collapse internal runs of whitespace introduced by joining
      line = line:gsub('%s%s+', ' ')
      table.insert(out, line)
      i = i + 1
    end
  end

  vim.api.nvim_buf_set_lines(0, first - 1, last, false, out)
  vim.fn.setreg('+', table.concat(out, '\n'))
end

return M
