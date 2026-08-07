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

-- `#L`, not `:` — that's Claude Code's documented mention shape
-- (@file#L100-110), what ai_context.lua's M.ref already emits for the
-- <leader>a* sends. Single-line refs (#L42) also match GitHub's permalink
-- fragment; ranges don't (GitHub wants #L42-L58 — see github_url_for below).
-- Not routed through ai_context.M.ref on purpose: that one is cwd-relative
-- and self-quotes, while these are repo-relative (or absolute) for sharing
-- outside this checkout. Only claude and cursor resolve a line range at all —
-- opencode wants `#a-b` without the L and may not accept it from the TUI, pi
-- has no range syntax — so on those the path still resolves and the range
-- reads as a hint.

-- Yank: Claude @-mention reference for the current visual selection, e.g.
-- "@foo/bar.lua#L42-58". Falls back to absolute path outside a repo.
function M.claude_ref()
  local path = repo_relative_path() or vim.fn.expand('%:p')
  local s, e = visual_range()
  copy('@' .. path .. '#L' .. format_range(s, e))
end

-- Yank: Claude @-mention reference using the absolute path, e.g.
-- "@/Users/dhruv/foo/bar.lua#L42-58". Useful when sharing across repos or when
-- the relative path would be ambiguous.
function M.claude_ref_absolute()
  local s, e = visual_range()
  copy('@' .. vim.fn.expand('%:p') .. '#L' .. format_range(s, e))
end

-- Build a GitHub permalink for an absolute file path, pinned to HEAD's commit
-- SHA, with an optional #L line (or #La-Lb range). Returns the URL, or nil + an
-- error message. Shared by M.github_url (current buffer) and the picker's
-- copy_github_url action (an arbitrary item path + its row).
function M.github_url_for(abs, s, e)
  local root = git(vim.fn.fnamemodify(abs, ':h'), 'rev-parse', '--show-toplevel')
  if not root then return nil, 'Not in a git repo' end
  local remote = git(root, 'remote', 'get-url', 'origin')
  if not remote then return nil, 'No origin remote' end
  local owner, repo = remote:match('github%.com[:/]([^/]+)/(.+)$')
  if not owner then return nil, 'Not a GitHub remote: ' .. remote end
  repo = repo:gsub('%.git$', '')
  local sha = git(root, 'rev-parse', 'HEAD')
  if not sha then return nil, 'Could not read HEAD SHA' end
  local path = abs:sub(#root + 2)
  local frag = ''
  if s then frag = (not e or s == e) and ('#L' .. s) or ('#L' .. s .. '-L' .. e) end
  return string.format('https://github.com/%s/%s/blob/%s/%s%s', owner, repo, sha, path, frag)
end

-- Yank: GitHub permalink to the current visual selection, e.g.
-- "https://github.com/owner/repo/blob/<sha>/foo/bar.lua#L42-L58".
function M.github_url()
  local url, err = M.github_url_for(vim.fn.expand('%:p'), visual_range())
  if url then copy(url) else vim.notify(err, vim.log.levels.ERROR) end
end

return M
