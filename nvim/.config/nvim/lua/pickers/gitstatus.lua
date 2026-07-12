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

  return Snacks.picker.git_status({
    cwd = git_root,
    actions = qp_actions,
    format = function(item, picker)
      local ret = {}  ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      vim.list_extend(ret, Snacks.picker.format.git_status(item, picker))
      return ret
    end,
    -- Only the <M-N> keys are added here; the source's own <Tab> (stage
    -- toggle) and <c-r> (restore) bindings survive the deep-merge.
    win = {
      input = { keys = qp_keys },
      list = { keys = qp_keys },
    },
  })
end

return M
