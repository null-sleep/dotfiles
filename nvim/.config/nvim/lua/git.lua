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
    -- stage_hunk is a toggle: on an unstaged hunk it stages, on a staged
    -- hunk it unstages — which is why there is no separate undo-stage map
    -- (gitsigns deprecated undo_stage_hunk in favor of the toggle; the old
    -- key also had different semantics — it popped the *last-staged* hunk
    -- from anywhere, the toggle needs the cursor on the hunk).
    -- stage_hunk/reset_hunk also accept a range for visual-mode partial staging:
    --   map('v', '<leader>hs', function() gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, ...)
    --   map('v', '<leader>hr', function() gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, ...)
    map('n', '<leader>hs', gs.stage_hunk,                                  'Git hunk: Stage/unstage (toggle)')
    map('n', '<leader>hr', gs.reset_hunk,                                  'Git hunk: Reset')
    map('n', '<leader>hp', gs.preview_hunk,                                'Git hunk: Preview')
    map('n', '<leader>hb', function() gs.blame_line({ full = true }) end,  'Git hunk: Blame line')
    map('n', '<leader>tb', gs.toggle_current_line_blame,                   'Toggle: Inline blame')
  end,
})

-- Buffer-local keymaps for git editor buffers (git commit, git rebase -i,
-- Neogit's commit tab — all gitcommit/gitrebase filetype). <leader>w confirms,
-- <leader>x aborts. Standalone as $EDITOR they :quit/:cq the client; on the
-- flatten/Neogit parent path that would quit the host, so we wipe the buffer
-- instead (abort empties + writes first so git aborts on an empty message/todo).
vim.api.nvim_create_autocmd('FileType', {
  group    = vim.api.nvim_create_augroup('UserGitEditor', { clear = true }),
  pattern  = { 'gitcommit', 'gitrebase' },
  callback = function(args)
    local function is_standalone_editor()
      return #vim.fn.getbufinfo({ buflisted = 1 }) <= 1 and not vim.g._flatten_blocking
    end
    -- Wipe this buffer to unblock the guest, but show the displaced buffer
    -- (flatten_prev_buf) first: wiping a still-displayed buffer closes its
    -- window when another exists (e.g. the sidekick split), dropping the code.
    local function close_buffer()
      local prev = vim.b[args.buf].flatten_prev_buf
      if prev and vim.api.nvim_buf_is_valid(prev) then
        vim.api.nvim_win_set_buf(0, prev)
      end
      vim.cmd('bwipeout! ' .. args.buf)
    end
    local function confirm()
      vim.cmd('write')
      if is_standalone_editor() then
        vim.cmd('quit')
      else
        close_buffer()
      end
    end
    local function abort()
      if is_standalone_editor() then
        vim.cmd('cquit')
      else
        vim.cmd('silent %delete _')
        vim.cmd('write')
        close_buffer()
      end
    end
    vim.keymap.set('n', '<leader>w', confirm, { buffer = args.buf, desc = 'Git: confirm (save + close buffer)' })
    vim.keymap.set('n', '<leader>x', abort,   { buffer = args.buf, desc = 'Git: abort' })
  end,
})

-- Scrollbar with git, diagnostic, search and cursor marks.
-- Gitsigns integration is automatic — satellite detects gitsigns via package.loaded.
vim.cmd.packadd('satellite.nvim')

require('satellite').setup({
  current_only = true,    -- show scrollbar only on the focused window
  winblend     = 50,      -- scrollbar transparency (0 = opaque, 100 = invisible)
  width        = 2,
  excluded_filetypes = {
    'mason',
    -- snacks picker floats — without these the list window grows a stray
    -- satellite scrollbar
    'snacks_picker_input', 'snacks_picker_list', 'snacks_picker_preview',
  },
  handlers = {
    cursor     = { enable = true },
    search     = { enable = true },
    diagnostic = { enable = true },
    gitsigns   = { enable = true },
    marks      = { enable = false },  -- marks off by default, enable if you use vim marks
    quickfix   = { enable = true },
  },
})
