vim.cmd.packadd('persistence.nvim')

require('persistence').setup({
  -- Sessions saved per directory + git branch, so switching branches gives
  -- you a clean slate without losing the other branch's open files.
  branch = true,
})

-- Keep terminals out of saved sessions. Restoring a terminal only re-spawns a
-- fresh shell (no scrollback, no in-session command history — that lives in the
-- shell's own histfile) into a window, so there's nothing to gain. Worse, the
-- restored sidekick CLI buffer isn't in sidekick's runtime registry, so
-- <leader>aa toggle can no longer manage it (it tracks the pre-warmed instance).
-- Dropping this flag makes mksession omit terminal *windows* entirely from the
-- saved layout (verified: no empty-split placeholder is left behind), so this
-- one line is the whole fix.
vim.opt.sessionoptions:remove('terminal')

-- Don't save sessions for throwaway directories — ten of the twenty-four here
-- were /private/tmp and $TMPDIR scratchpads that only clutter <leader>qS.
-- cleanup.lua sweeps ones already on disk through the same is_tmp_path.
--
-- Re-checked on DirChanged: the startup cwd isn't necessarily the one
-- persistence saves under. Only ever stops, never starts — <leader>qd stops
-- saving deliberately, and a cd shouldn't undo that.
local function stop_in_tmpdir()
  if require('utils').is_tmp_path(vim.fn.getcwd()) then
    require('persistence').stop()
  end
end

stop_in_tmpdir()
vim.api.nvim_create_autocmd('DirChanged', {
  group = vim.api.nvim_create_augroup('UserSessionTmpdir', { clear = true }),
  desc = 'Session: stop saving after cd-ing into a temp directory',
  callback = stop_in_tmpdir,
})

-- A synthetic (no-file) window can't be session-serialized: mksession has no
-- filename to record, so a restored session shows a blank `enew` scratch split
-- where the panel was. The general fix is to close such windows before the
-- session is written, keeping that junk out of the saved layout; you reopen the
-- panel on demand. We deliberately don't persist "was it open?" to auto-reopen
-- — that would need `sessionoptions+=globals`, a footgun that bakes unrelated
-- globals into every session. See GUIDE.md "Synthetic sidebar buffers can't be
-- session-serialized".
--
-- Aerial's outline, nvim-tree's explorer, and grug-far's transient results
-- buffer are the synthetic-buffer panels handled today — all closed here.
-- (nvim-tree was wrongly assumed to be handled elsewhere and left out until
-- this bug surfaced; same blank-buffer failure mode.) Safe to close in
-- PersistenceSavePre: it only fires from persistence's VimLeavePre hook, i.e.
-- nvim is already quitting.
vim.api.nvim_create_autocmd('User', {
  group   = vim.api.nvim_create_augroup('UserSessionSave', { clear = true }),
  pattern = 'PersistenceSavePre',
  desc = 'Session: close synthetic-buffer panels (aerial, nvim-tree, grug-far) before mksession so they leave no blank scratch window',
  callback = function()
    require('aerial').close_all()
    require('nvim-tree.api').tree.close_in_all_tabs()
    -- grug-far's is a *named* nofile buffer, so mksession serializes any window
    -- showing it → junk split on restore. Close those windows (buffer is
    -- bufhidden=wipe, so it goes too), then wipe any left. Inline, not grug-far's
    -- own close (conditional, and can pop a confirm() at quit). pcall: last-win E444.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'grug-far' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'grug-far' then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end,
})

-- Restore session for the current directory (most common)
vim.keymap.set('n', '<leader>qs', function() require('persistence').load() end,
  { desc = 'Session: Restore' })

-- Pick from all saved sessions
vim.keymap.set('n', '<leader>qS', function() require('persistence').select() end,
  { desc = 'Session: Select' })

-- Restore the last session regardless of directory
vim.keymap.set('n', '<leader>ql', function() require('persistence').load({ last = true }) end,
  { desc = 'Session: Restore last' })

-- Stop saving — useful when you want to quit without persisting current state
vim.keymap.set('n', '<leader>qd', function() require('persistence').stop() end,
  { desc = 'Session: Stop saving' })
