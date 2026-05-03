vim.cmd.packadd('lualine.nvim')

require('lualine').setup({
  options = {
    -- 'auto' reads the active colorscheme's highlight groups — no manual
    -- theme changes needed when switching themes in themes.lua.
    theme = 'auto',

    -- Powerline-style separators (require a Nerd Font).
    -- Replace with { left = '', right = '' } for no separators (flat style).
    section_separators    = { left = '', right = '' },
    component_separators  = { left = '', right = '' },

    -- Single global statusline at the bottom (nvim 0.7+).
    -- Set to false for per-window statuslines.
    globalstatus = true,

    -- Filetypes where lualine is hidden entirely.
    disabled_filetypes = {
      statusline = { 'alpha', 'dashboard', 'starter' },
    },
  },

  sections = {
    lualine_a = { 'mode' },
    lualine_b = {
      {
        'filename',
        path = 1,  -- relative path
        fmt = function(name, ctx)
          -- Clean up raw terminal buffer names:
          --   toggleterm: "t//path/49473:/bin/zsh;#toggleterm#1" → "Terminal #1"
          --   sidekick:   "term://path//PID:/opt/homebrew/bin/claude:6" → "Claude CLI"
          if vim.bo.filetype == 'toggleterm' then
            local nr = vim.b.toggle_number or 1
            return 'Terminal #' .. nr
          end
          local bufname = vim.api.nvim_buf_get_name(0)
          local cli = bufname:match('/bin/(%w+)$') or bufname:match('/bin/(%w+):')
          if cli and bufname:match('^term://') then
            return cli:sub(1, 1):upper() .. cli:sub(2) .. ' CLI'
          end
          return name
        end,
      },
    },
    lualine_c = { 'branch', 'diff', 'diagnostics' },
    lualine_x = {
      {
        'lsp_status',
        fmt = function(status)
          -- Shorten "copilot" to a icon to save statusline space.
          return status:gsub('copilot', '')
        end,
      },
    },
    lualine_y = { 'searchcount', 'progress' },
    lualine_z = { 'location' },
  },

  inactive_sections = {
    lualine_c = { { 'filename', path = 1 } },
    lualine_x = { 'location' },
  },

  -- Auto-hide statusline in these plugin windows and show a minimal one instead.
  extensions = { 'quickfix', 'mason' },
})
