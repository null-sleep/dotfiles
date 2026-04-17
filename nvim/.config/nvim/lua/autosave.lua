vim.cmd.packadd('auto-save.nvim')

require('auto-save').setup({
  enabled = true,
  trigger_events = {
    immediate_save = { 'BufLeave', 'FocusLost' },  -- save immediately on these
    defer_save     = { 'InsertLeave', 'TextChanged' }, -- save after delay on these
  },
  debounce_delay = 1000,  -- ms to wait after last change before saving (matches VS Code setting)
  -- do not autosave these filetypes
  condition = function(buf)
    local excluded = { 'oil', 'TelescopePrompt', 'mason', 'gitcommit', 'harpoon' }
    local ft = vim.bo[buf].filetype
    for _, v in ipairs(excluded) do
      if ft == v then return false end
    end
    return vim.bo[buf].modifiable
  end,
})
