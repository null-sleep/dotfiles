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
  -- read-only buffers like help pages and diffs. `qf`: quicker.nvim makes the
  -- quickfix window a modifiable buffer named `quickfix-<n>` (quickfix.lua) —
  -- auto-saving it dumps the list to a stray real file in the cwd and applies
  -- the edits before the deliberate `:w` that's meant to gate them.
  condition = function(buf)
    local excluded = { 'oil', 'snacks_picker_input', 'mason', 'gitcommit', 'gitrebase', 'harpoon', 'grug-far', 'qf' }
    local ft = vim.bo[buf].filetype
    for _, v in ipairs(excluded) do
      if ft == v then return false end
    end
    return vim.bo[buf].modifiable
  end,
})
