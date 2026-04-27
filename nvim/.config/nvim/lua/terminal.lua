vim.cmd.packadd('toggleterm.nvim')

require('toggleterm').setup({
  open_mapping = [[<c-\>]],
  direction = 'float',
  float_opts = {
    border = 'curved',
    width = function()
      return math.floor(vim.o.columns * 0.85)
    end,
    height = function()
      return math.floor(vim.o.lines * 0.85)
    end,
  },
  shade_terminals = false,
  start_in_insert = true,
  close_on_exit = true,
})

-- Terminal-mode keymaps (buffer-local, set when any terminal opens).
-- NOTE: <Esc> exits terminal mode in all terminal buffers. If you add
-- lazygit or other TUI integrations, guard this with a filetype check.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Terminal keymaps: Esc and split navigation',
  callback = function()
    local opts = { buffer = 0 }
    vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], opts)
    vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
    vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
    vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
    vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
  end,
})

vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle: Terminal' })
