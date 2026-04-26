vim.cmd.packadd('gitsigns.nvim')

require('gitsigns').setup({
  attach_to_untracked = true,
  signs = {
    add          = { text = '▎' },
    change       = { text = '▎' },
    delete       = { text = '▂' },
    topdelete    = { text = '▔' },
    changedelete = { text = '▎' },
    untracked    = { text = '░' },
  },
  on_attach = function(buf)
    local gs = require('gitsigns')
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    -- Navigation — ]c/[c are also vim's native diff-chunk motions, so in diff
    -- mode (vimdiff, :diffsplit, :Gitsigns diffthis) we fall back to the
    -- built-in behaviour. bang = true avoids triggering this mapping recursively.
    -- Pattern from gitsigns README.
    map('n', ']c', function()
      if vim.wo.diff then
        vim.cmd.normal({ ']c', bang = true })
      else
        gs.nav_hunk('next')
      end
    end, 'Git hunk: Next')
    map('n', '[c', function()
      if vim.wo.diff then
        vim.cmd.normal({ '[c', bang = true })
      else
        gs.nav_hunk('prev')
      end
    end, 'Git hunk: Previous')

    -- Actions
    -- stage_hunk/reset_hunk also accept a range for visual-mode partial staging:
    --   map('v', '<leader>hs', function() gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, ...)
    --   map('v', '<leader>hr', function() gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, ...)
    map('n', '<leader>hs', gs.stage_hunk,                                  'Git hunk: Stage')
    map('n', '<leader>hr', gs.reset_hunk,                                  'Git hunk: Reset')
    map('n', '<leader>hu', gs.undo_stage_hunk,                             'Git hunk: Undo stage')
    map('n', '<leader>hp', gs.preview_hunk,                                'Git hunk: Preview')
    map('n', '<leader>hb', function() gs.blame_line({ full = true }) end,  'Git hunk: Blame line')
    map('n', '<leader>tb', gs.toggle_current_line_blame,                   'Toggle: Inline blame')
  end,
})

-- Scrollbar with git, diagnostic, search and cursor marks.
-- Gitsigns integration is automatic — satellite detects gitsigns via package.loaded.
vim.cmd.packadd('satellite.nvim')

require('satellite').setup({
  current_only = true,    -- show scrollbar only on the focused window
  winblend     = 50,      -- scrollbar transparency (0 = opaque, 100 = invisible)
  width        = 2,
  excluded_filetypes = { 'TelescopePrompt', 'mason' },
  handlers = {
    cursor     = { enable = true },
    search     = { enable = true },
    diagnostic = { enable = true },
    gitsigns   = { enable = true },
    marks      = { enable = false },  -- marks off by default, enable if you use vim marks
    quickfix   = { enable = true },
  },
})
