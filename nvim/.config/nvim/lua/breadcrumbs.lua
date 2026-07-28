-- dropbar.nvim — Zed-style winbar breadcrumb (`module > Class > method`),
-- crumbs clickable. ON TRIAL (2026-07-28, 2nd attempt) behind <leader>tw, to
-- A/B it against treesitter_context.lua's sticky header, which pins the same
-- chain; rationale in GUIDE.md "Breadcrumbs (dropbar)". (`tb` is gitsigns'
-- blame.) Eager: the winbar has to exist the moment a buffer opens.
vim.cmd.packadd('dropbar.nvim')

-- Run-once globals for re-source safety (GUIDE.md "Re-source safety"; same
-- pattern as filetree.lua's `_lsp_file_ops_setup`). setup() replaces
-- configs.opts.bar.enable with the wrapper below, so `:source %` would
-- re-capture that wrapper and freeze the toggle on its dead `enabled` upvalue.
if _G._dropbar_default_enable == nil then
  _G._dropbar_default_enable = require('dropbar.configs').opts.bar.enable
end
if _G._dropbar_enabled == nil then
  _G._dropbar_enabled = true
end

local DROPBAR_WINBAR = '%{%v:lua.dropbar()%}'  -- what dropbar installs (utils/bar.lua)

-- setup() sets vim.g.loaded_dropbar, which stops dropbar's own plugin/ file
-- from calling setup() itself on the first FileType.
require('dropbar').setup({
  bar = {
    -- dropbar's default enables terminal buffers, which would put a breadcrumb
    -- on the sidekick CLI panel; defer to it for everything else.
    enable = function(buf, win, info)
      if not _G._dropbar_enabled or require('buffers').is_special(buf) then return false end
      return _G._dropbar_default_enable(buf, win, info)
    end,
  },
})

-- attach() only ever *sets* the winbar, so toggling off has to clear it.
vim.keymap.set('n', '<leader>tw', function()
  _G._dropbar_enabled = not _G._dropbar_enabled
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if _G._dropbar_enabled then
      require('dropbar.utils.bar').attach(vim.api.nvim_win_get_buf(win), win)
    elseif vim.wo[win].winbar == DROPBAR_WINBAR then
      vim.wo[win][0].winbar = ''
    end
  end
  vim.notify('Breadcrumbs: ' .. (_G._dropbar_enabled and 'on' or 'off'))
end, { desc = 'Toggle: Breadcrumbs (dropbar)' })
