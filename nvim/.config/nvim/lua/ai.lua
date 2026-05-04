-- pcall: on first launch vim.pack is still downloading the plugin in the
-- background, so packadd/require will fail. Silently skip — next restart
-- picks it up once the clone finishes.
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return end

require('sidekick').setup({
  cli = {
    -- Use telescope for cli.select() (tool list) and cli.prompt() (prompt library)
    -- so the sidekick UI matches the rest of the config.
    picker = 'telescope',
    win = {
      layout = 'right',  -- CLI opens as a right split; switch to 'float' if preferred
    },
    -- mux: leave disabled. Enable with backend = 'tmux' or 'zellij' if you want
    -- sessions to persist across nvim restarts.
  },
  nes = {
    -- defaults are good: enabled = true, debounce = 100, diff.inline = 'words'
  },
})

-- Add `jj` to exit terminal mode in sidekick CLI buffers. terminal.lua's
-- generic TermOpen autocmd skips sidekick_terminal so sidekick can own its
-- own keymaps; this restores just `jj` without touching <Esc> (which the
-- CLI needs to forward to Claude for interrupts).
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'sidekick_terminal',
  desc = 'Sidekick CLI: jj to exit terminal mode',
  callback = function(args)
    vim.keymap.set('t', 'jj', [[<C-\><C-n>]], { buffer = args.buf })
  end,
})
