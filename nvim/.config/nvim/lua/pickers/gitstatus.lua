-- pickers/gitstatus.lua — snacks git-status picker with number-jump quick-pick.
--
-- USAGE
--   require('pickers.gitstatus').open()        (bound to <leader>sm)
--
-- WHY A CUSTOM WRAPPER
--   snacks' builtin git_status covers the hard parts the old telescope
--   version hand-rolled (staging toggle on <Tab> with auto-refresh, diff
--   preview). This wrapper adds the two local conventions on top:
--   a row-index first column so <M-1>..<M-9> jumps to row N (matching
--   pickers/buffer.lua), and resolving the repo from the current buffer's
--   directory instead of nvim's cwd.
--
--   Row indices are item.idx (finder order); after a staging toggle the
--   finder re-runs and indices reset, same as the old picker.

local common = require('pickers.common')

local M = {}

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

  -- Clean repo → notify instead of opening an empty picker. Checked
  -- synchronously up front (git status is fast at this repo's scale) rather
  -- than racing the picker's async finder for an emptiness check.
  local changes = vim.fn.systemlist({ 'git', '-C', git_root, 'status', '--porcelain', '-uall' })
  if vim.v.shell_error == 0 and #changes == 0 then
    vim.notify('No changes found', vim.log.levels.INFO)
    return
  end

  local qp_actions, qp_keys = common.quick_pick_actions()

  -- Git XY status → icon + highlight, keeping the old telescope picker's
  -- glyph vocabulary (+ ~ - → ! ?) instead of snacks' letter rendering.
  -- X = staged column, Y = unstaged column, straight from porcelain v1.
  local GIT_ABBREV = {
    A = { icon = '+', hl = 'SnacksPickerGitStatusAdded' },
    U = { icon = '‡', hl = 'SnacksPickerGitStatusAdded' },
    M = { icon = '~', hl = 'SnacksPickerGitStatusModified' },
    C = { icon = '>', hl = 'SnacksPickerGitStatusCopied' },
    R = { icon = '→', hl = 'SnacksPickerGitStatusRenamed' },
    D = { icon = '-', hl = 'SnacksPickerGitStatusDeleted' },
    ['?'] = { icon = '?', hl = 'SnacksPickerGitStatusUntracked' },
  }

  return Snacks.picker.git_status({
    cwd = git_root,
    actions = qp_actions,
    -- Custom diff preview instead of the builtin git_status one, for two
    -- look reasons: classic full-width diff coloring (the default 'fancy'
    -- style draws per-file chip boxes that look broken in a short pane),
    -- and no per-file header noise — the preview is already scoped to the
    -- highlighted file, so the `diff --git`/`index`/`---`/`+++` block is
    -- dead weight. Everything before the first `@@` hunk is dropped
    -- *positionally* (a body line may legitimately start with `---` — e.g.
    -- a deleted lua comment — so pattern-filtering would corrupt it).
    -- Untracked/added files have no diff and show the file itself, same as
    -- the builtin.
    preview = function(ctx)
      if (ctx.item.status or ''):find('^[A?]') then
        return Snacks.picker.preview.file(ctx)
      end
      local args = { 'git', '-C', git_root, '--no-pager', 'diff' }
      if ctx.item.status:find('[UAD][UAD]') then
        args[#args + 1] = '--cc'      -- combined diff for conflicts
      elseif ctx.item.status:sub(1, 1) ~= ' ' then
        args[#args + 1] = '--cached'  -- staged changes
      end
      vim.list_extend(args, { '--', ctx.item.file })
      local lines = vim.fn.systemlist(args)
      local start = 1
      for i, l in ipairs(lines) do
        if l:find('^@@') then
          start = i
          break
        end
      end
      ctx.item.preview = {
        text = table.concat(lines, '\n', start),
        ft = 'diff',
        loc = false,
      }
      return Snacks.picker.preview.preview(ctx)
    end,
    -- Plain filename colors — the two status-icon columns already carry the
    -- state, and the old picker didn't recolor paths either.
    formatters = { file = { git_status_hl = false } },
    format = function(item, picker)
      local ret = {}  ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      local status = item.status or '  '
      local x, y = GIT_ABBREV[status:sub(1, 1)], GIT_ABBREV[status:sub(2, 2)]
      ret[#ret + 1] = { Snacks.picker.util.align(x and x.icon or ' ', 2), x and x.hl }
      ret[#ret + 1] = { Snacks.picker.util.align(y and y.icon or ' ', 2), y and y.hl }
      vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
      return ret
    end,
    -- Only the <M-N> keys are added here; the source's own <Tab> (stage
    -- toggle) and <c-r> (restore) bindings survive the deep-merge.
    -- nowrap: long diff lines truncate instead of wrapping into unreadable
    -- fragments (matches the old telescope preview's behavior).
    win = {
      input = { keys = qp_keys },
      list = { keys = qp_keys },
      preview = { wo = { wrap = false } },
    },
  })
end

return M
