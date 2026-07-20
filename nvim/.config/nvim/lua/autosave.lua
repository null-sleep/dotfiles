vim.cmd.packadd('auto-save.nvim')

require('auto-save').setup({
  enabled = true,
  trigger_events = {
    -- Must list QuitPre/VimSuspend explicitly: Config:set_options deep-merges
    -- with "keep", so a specified key replaces the plugin default wholesale
    -- rather than adding to it. Without them a pending deferred save is never
    -- flushed on quit or suspend.
    immediate_save = { 'BufLeave', 'FocusLost', 'QuitPre', 'VimSuspend' },
    defer_save     = { 'InsertLeave', 'TextChanged' }, -- save after delay on these
  },
  debounce_delay = 1000,  -- ms to wait after last change before saving (matches VS Code setting)
  -- Skip auto-save for special UI buffers where saving mid-edit would cause
  -- problems (e.g. gitcommit would save an incomplete message), and for
  -- read-only buffers like help pages and diffs.
  condition = function(buf)
    local excluded = { 'oil', 'snacks_picker_input', 'mason', 'gitcommit', 'gitrebase', 'harpoon' }
    local ft = vim.bo[buf].filetype
    for _, v in ipairs(excluded) do
      if ft == v then return false end
    end
    return vim.bo[buf].modifiable
  end,
})
