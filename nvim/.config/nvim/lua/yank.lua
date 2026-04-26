-- Yank helpers — write to system clipboard ('+' register) and notify.
--
-- Normal mode: path helpers work as-is; line-based helpers (claude_ref,
-- github_url) use the cursor line as a single-line reference.
-- Visual mode: line-based helpers use the selection range.
--
-- Deferred ideas (not built yet):
--   * Branch-name URL variant (e.g. <leader>yU) alongside the SHA permalink.
--   * Inline-snippet form for claude_ref that includes a fenced code block.

local M = {}

-- Write to system clipboard and echo what was copied.
local function copy(text)
  vim.fn.setreg('+', text)
  vim.notify(text)
end

-- Current visual selection's line range, low-to-high. Uses 'v' (anchor) and
-- '.' (cursor) instead of '<'/'>' marks because those are stale until you exit
-- visual mode — these reflect the live selection.
local function visual_range()
  local s = vim.fn.line('v')
  local e = vim.fn.line('.')
  if s > e then s, e = e, s end
  return s, e
end

-- "42" for a single line, "42-58" for a range.
local function format_range(s, e)
  return s == e and tostring(s) or (s .. '-' .. e)
end

-- Run `git -C dir <args>`, return first line of stdout, or nil on failure.
local function git(dir, ...)
  local out = vim.fn.systemlist({ 'git', '-C', dir, ... })
  if vim.v.shell_error ~= 0 then return nil end
  return out[1]
end

-- Absolute path to the repo root containing the current file, or nil.
local function git_root()
  return git(vim.fn.expand('%:p:h'), 'rev-parse', '--show-toplevel')
end

-- Current buffer's path relative to the repo root (e.g. "foo/bar.lua"), or nil
-- if not in a repo.
local function repo_relative_path()
  local root = git_root()
  if not root then return nil end
  local abs = vim.fn.expand('%:p')
  return abs:sub(#root + 2)
end

-- Yank: path relative to CWD, e.g. "foo/bar.lua".
function M.relative_path()
  copy(vim.fn.expand('%'))
end

-- Yank: absolute path, e.g. "/Users/dhruv/foo/bar.lua".
function M.absolute_path()
  copy(vim.fn.expand('%:p'))
end

-- Yank: Claude @-mention reference for the current visual selection, e.g.
-- "@foo/bar.lua:42-58". Falls back to absolute path outside a repo.
function M.claude_ref()
  local path = repo_relative_path() or vim.fn.expand('%:p')
  local s, e = visual_range()
  copy('@' .. path .. ':' .. format_range(s, e))
end

-- Yank: Claude @-mention reference using the absolute path, e.g.
-- "@/Users/dhruv/foo/bar.lua:42-58". Useful when sharing across repos or when
-- the relative path would be ambiguous.
function M.claude_ref_absolute()
  local s, e = visual_range()
  copy('@' .. vim.fn.expand('%:p') .. ':' .. format_range(s, e))
end

-- Yank: GitHub permalink to the current visual selection, pinned to HEAD's
-- commit SHA, e.g. "https://github.com/owner/repo/blob/<sha>/foo/bar.lua#L42-L58".
function M.github_url()
  local root = git_root()
  if not root then
    vim.notify('Not in a git repo', vim.log.levels.ERROR)
    return
  end

  local remote = git(root, 'remote', 'get-url', 'origin')
  if not remote then
    vim.notify('No origin remote', vim.log.levels.ERROR)
    return
  end

  local owner, repo = remote:match('github%.com[:/]([^/]+)/(.+)$')
  if not owner then
    vim.notify('Not a GitHub remote: ' .. remote, vim.log.levels.ERROR)
    return
  end
  repo = repo:gsub('%.git$', '')

  local sha = git(root, 'rev-parse', 'HEAD')
  if not sha then
    vim.notify('Could not read HEAD SHA', vim.log.levels.ERROR)
    return
  end

  local path = repo_relative_path()
  local s, e = visual_range()
  local frag = s == e and ('#L' .. s) or ('#L' .. s .. '-L' .. e)
  copy(string.format('https://github.com/%s/%s/blob/%s/%s%s', owner, repo, sha, path, frag))
end

return M
