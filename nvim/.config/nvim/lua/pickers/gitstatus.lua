-- pickers/gitstatus.lua — snacks git-status picker with number-jump quick-pick.
--
-- USAGE
--   require('pickers.gitstatus').open()        (bound to <leader>sm)
--   count-prefixed, e.g. 5<leader>sm            (last 5 commits, see below)
--
-- WHY A CUSTOM WRAPPER
--   snacks' builtin git_status covers the hard parts (staging toggle on
--   <Tab> with auto-refresh, diff preview). This wrapper adds the local
--   conventions: a row-index first column so <M-1>..<M-9> jumps to row N
--   (matching pickers/buffer.lua), repo resolution from the current
--   buffer's directory instead of nvim's cwd, and a decluttered preview.
--
--   Row indices are item.idx (finder order); a staging toggle re-runs the
--   finder and indices reset.
--
-- COUNT PREFIX -> RANGE MODE
--   A count prefix switches the source to snacks' git_diff (base =
--   'HEAD~N'), matching the `gd N` shell function (git diff HEAD~N) exactly
--   — HEAD~N is always an ancestor of HEAD, so git_diff's `--merge-base`
--   resolves to it directly. Bare <leader>sm is unaffected. Range mode adds
--   a commit-hash column: blank if no range commit touched the file, plain
--   hash if one did, hash+`~` (modified color) if it's also still dirty.

local common = require('pickers.common')

local M = {}

-- Shared by both preview paths below: drop everything before the first `@@`
-- hunk header (positionally, not by pattern — a body line may legitimately
-- start with `---`, e.g. a deleted lua comment) and compute real file line
-- numbers for the gutter (see M.statuscol) by walking hunk headers.
local function render_diff_lines(ctx, lines)
  local start = 1
  for i, l in ipairs(lines) do
    if l:find('^@@') then
      start = i
      break
    end
  end
  local nums, new_lnum, width = {}, nil, 0
  for i = start, #lines do
    local l = lines[i]
    local hunk_start = l:match('^@@ %-%d+[^+]*%+(%d+)')
    local n = ''
    if hunk_start then
      new_lnum = tonumber(hunk_start)
    elseif new_lnum and l:sub(1, 1) ~= '-' and l:sub(1, 1) ~= '\\' then
      n = tostring(new_lnum)
      new_lnum = new_lnum + 1
    end
    nums[#nums + 1] = n
    width = math.max(width, #n)
  end
  for i, n in ipairs(nums) do
    nums[i] = (' '):rep(width - #n) .. n
  end
  ctx.item.preview = {
    text = table.concat(lines, '\n', start),
    ft = 'diff',
    loc = false,
  }
  local ret = Snacks.picker.preview.preview(ctx)
  vim.b[ctx.buf].diff_lnums = nums
  return ret
end

-- Range mode only: newest commit in range..HEAD that touched each file (one
-- `git show --name-only` per commit — N is small, whatever the user typed).
local function commits_by_file(git_root, range_base)
  local hashes = vim.fn.systemlist({ 'git', '-C', git_root, 'log', '--format=%h', range_base .. '..HEAD' })
  local map = {}
  for _, hash in ipairs(hashes) do
    local files = vim.fn.systemlist({ 'git', '-C', git_root, 'show', '--format=', '--name-only', hash })
    for _, f in ipairs(files) do
      if f ~= '' and not map[f] then map[f] = hash end
    end
  end
  return map
end

-- Range mode only: files with changes not yet committed, so a file touched
-- by a range commit AND still dirty can be flagged (see format() below).
local function dirty_file_set(git_root)
  local out = vim.fn.systemlist({ 'git', '-C', git_root, 'status', '--porcelain', '-uall' })
  local set = {}
  for _, line in ipairs(out) do
    local file = line:match('^..%s+(.+)$')
    if file then
      local _, renamed_to = file:match('^(.-) %-> (.+)$')
      set[renamed_to or file] = true
    end
  end
  return set
end

function M.open()
  -- Resolve git toplevel from the current buffer's directory, not nvim's cwd
  -- (same as yank.lua) — editing a file outside the cwd's repo must show THAT
  -- file's repo status. Unnamed buffers fall back to cwd. List-form
  -- systemlist so no shell parses the path.
  local dir = vim.fn.expand('%:p:h')
  if dir == '' then dir = vim.fn.getcwd() end
  local git_root = vim.fn.systemlist({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' })[1]
  if vim.v.shell_error ~= 0 or not git_root then
    vim.notify('Not a git repository', vim.log.levels.WARN)
    return
  end

  -- A count prefix (5<leader>sm) switches into range mode; see header comment.
  local n = vim.v.count
  local range_base = n > 0 and ('HEAD~%d'):format(n) or nil
  local commit_for_file, dirty_files  -- populated below in range mode only

  if range_base then
    -- Same --merge-base flag git_diff itself uses. Exit 0 = no changes,
    -- 1 = changes, else = bad ref (e.g. fewer than N commits exist).
    vim.fn.system({ 'git', '-C', git_root, 'diff', '--quiet', '--merge-base', range_base })
    local code = vim.v.shell_error
    if code == 0 then
      vim.notify('No changes in the last ' .. n .. ' commit(s)', vim.log.levels.INFO)
      return
    elseif code ~= 1 then
      vim.notify('Invalid range: fewer than ' .. n .. ' commits, or bad ref', vim.log.levels.WARN)
      return
    end
    commit_for_file = commits_by_file(git_root, range_base)
    dirty_files = dirty_file_set(git_root)
  else
    -- Clean repo → notify instead of opening an empty picker. Checked
    -- synchronously up front (git status is fast at this repo's scale) rather
    -- than racing the picker's async finder for an emptiness check.
    local changes = vim.fn.systemlist({ 'git', '-C', git_root, 'status', '--porcelain', '-uall' })
    if vim.v.shell_error == 0 and #changes == 0 then
      vim.notify('No changes found', vim.log.levels.INFO)
      return
    end
  end

  local qp_actions, qp_keys = common.quick_pick_actions()

  -- Git XY status → icon + highlight (+ ~ - → ! ? glyphs instead of
  -- snacks' letter rendering). X = staged, Y = unstaged, per porcelain v1.
  local GIT_ABBREV = {
    A = { icon = '+', hl = 'SnacksPickerGitStatusAdded' },
    U = { icon = '‡', hl = 'SnacksPickerGitStatusAdded' },
    M = { icon = '~', hl = 'SnacksPickerGitStatusModified' },
    C = { icon = '>', hl = 'SnacksPickerGitStatusCopied' },
    R = { icon = '→', hl = 'SnacksPickerGitStatusRenamed' },
    D = { icon = '-', hl = 'SnacksPickerGitStatusDeleted' },
    ['?'] = { icon = '?', hl = 'SnacksPickerGitStatusUntracked' },
  }

  local picker_opts = {
    cwd = git_root,
    actions = qp_actions,
    -- Custom diff preview: classic full-width diff coloring (the 'fancy'
    -- default draws per-file chip boxes that break in a short pane) and no
    -- per-file header. Untracked/added files show the file itself. Range
    -- mode already has the full diff text as item.diff — no re-shelling.
    preview = function(ctx)
      if range_base then
        return render_diff_lines(ctx, vim.split(ctx.item.diff or '', '\n', { plain = true }))
      end
      if (ctx.item.status or ''):find('^[A?]') then
        local ret = Snacks.picker.preview.file(ctx)
        if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
          vim.b[ctx.buf].diff_lnums = nil  -- scratch buffers are reused
        end
        return ret
      end
      local args = { 'git', '-C', git_root, '--no-pager', 'diff' }
      if ctx.item.status:find('[UAD][UAD]') then
        args[#args + 1] = '--cc'      -- combined diff for conflicts
      elseif ctx.item.status:sub(1, 1) ~= ' ' then
        args[#args + 1] = '--cached'  -- staged changes
      end
      vim.list_extend(args, { '--', ctx.item.file })
      return render_diff_lines(ctx, vim.fn.systemlist(args))
    end,
    -- Plain filename colors — the two status-icon columns already carry the
    -- state, and the old picker didn't recolor paths either.
    formatters = { file = { git_status_hl = false } },
    format = function(item, picker)
      local ret = {}  ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      local status = item.status
      if not status and item.block then
        -- git_diff items carry no XY porcelain code; derive one the same
        -- way snacks' own format.git_status() does, in column 2 (unstaged)
        -- to match a normal-mode unstaged file's column.
        local b = item.block
        local letter = b.new and 'A' or b.delete and 'D' or b.rename and 'R' or b.copy and 'C' or 'M'
        status = ' ' .. letter
      end
      status = status or '  '
      local x, y = GIT_ABBREV[status:sub(1, 1)], GIT_ABBREV[status:sub(2, 2)]
      ret[#ret + 1] = { Snacks.picker.util.align(x and x.icon or ' ', 2), x and x.hl }
      ret[#ret + 1] = { Snacks.picker.util.align(y and y.icon or ' ', 2), y and y.hl }
      if range_base then
        -- Which commit last touched this file, if any: blank when the file
        -- is purely uncommitted (no commit in range touched it); dimmed when
        -- cleanly committed (nothing more to see here); a trailing `~` in
        -- the louder commit color when it's also still dirty on top — that
        -- combination is the one worth catching your eye.
        local hash = commit_for_file[item.file]
        local text, hl = '', nil
        if hash and dirty_files[item.file] then
          text, hl = hash .. '~', 'SnacksPickerGitCommit'
        elseif hash then
          text, hl = hash, 'SnacksPickerDimmed'
        end
        ret[#ret + 1] = { Snacks.picker.util.align(text, 8), hl }
      end
      vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
      return ret
    end,
    -- Only the <M-N> keys are added here; the source's own <Tab> (stage
    -- toggle) and <c-r> (restore) bindings survive the deep-merge.
    -- Preview window: nowrap (long diff lines truncate instead of wrapping
    -- into fragments) and a statuscolumn showing real file line numbers
    -- instead of the diff buffer's meaningless 1..N (see M.statuscol).
    win = {
      input = { keys = qp_keys },
      list = { keys = qp_keys },
      preview = {
        wo = {
          wrap = false,
          number = false,
          relativenumber = false,
          statuscolumn = "%!v:lua.require'pickers.gitstatus'.statuscol()",
        },
      },
    },
  }

  if range_base then
    picker_opts.base = range_base
    picker_opts.group = true
    return Snacks.picker.git_diff(picker_opts)
  end
  return Snacks.picker.git_status(picker_opts)
end

-- statuscolumn callback for the diff preview window: renders the real
-- file line number computed by the preview above (b:diff_lnums, indexed by
-- v:lnum). Falls back to normal numbering for buffers without it (the
-- untracked-file preview).
function M.statuscol()
  local win = vim.g.statusline_winid
  local buf = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
  local nums = buf and vim.b[buf].diff_lnums
  if not nums then
    return '%=%l '
  end
  return '%=%#LineNr#' .. (nums[vim.v.lnum] or '') .. ' '
end

return M
