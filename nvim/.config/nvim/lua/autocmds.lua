-- General editor autocmds that aren't owned by a specific feature module.
-- (Feature-local autocmds still live with their feature: checktime in
-- configs.lua, lint-on-save in linting.lua, the FileCreated subscribe in
-- filetree.lua, etc.)
-- One augroup, cleared on re-source so `:source %` never duplicates handlers
-- (see GUIDE.md "Re-source safety").
local augroup = vim.api.nvim_create_augroup('UserAutocmds', { clear = true })
local buffers = require('buffers')

-- Auto-create missing parent directories when writing a file, so
-- `:e src/new/deep/file.lua` followed by `:w` doesn't fail with "no such
-- file or directory" — nvim writes the intervening dirs for you.
-- Only real file buffers: an empty `buftype` means an ordinary on-disk file,
-- so this skips acwrite scheme buffers (`fugitive://`, `oil://` — which route
-- writes through BufWriteCmd and don't fire BufWritePre anyway) plus
-- nofile/terminal/prompt in one check, no URL-scheme allowlist to keep current.
-- mkdir is pcall'd: an uncaught error in BufWritePre aborts the write, so a
-- failure (E739 when a path component is a file, permission denied) must not
-- silently drop the save — warn instead.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = augroup,
  desc = 'Create missing parent dirs on save',
  callback = function(args)
    if vim.bo[args.buf].buftype ~= '' then return end
    local dir = vim.fs.dirname(vim.fs.abspath(args.match))
    if vim.fn.isdirectory(dir) == 0 then
      local ok, err = pcall(vim.fn.mkdir, dir, 'p')
      if not ok then
        vim.notify('mkdir failed for ' .. dir .. ': ' .. err, vim.log.levels.WARN)
      end
    end
  end,
})

-- Restore the cursor to its last position when reopening a file. Neovim core
-- still does NOT do this (verified against 0.12.4's `_defaults.lua`). Reads
-- the `"` mark (last cursor position, persisted in the shada file) on
-- BufReadPost and jumps there.
--
-- NOTE FOR FUTURE WORK — this handler fires on `BufReadPost`, which runs for
-- every file *read from disk*. It is deliberately NOT guarded by
-- buftype/`is_special()`, and that's safe because:
--   * synthetic panels (nvim-tree, aerial, sidekick, `:terminal`) are built
--     in memory and never fire BufReadPost, so they can't reach this code;
--   * snacks scratch buffers are disk-backed and MAY fire it, but restoring
--     their cursor is harmless (desirable, even);
--   * the only real disk files we must skip are gitcommit/gitrebase (you
--     always want line 1 there) — handled by the filetype check below.
-- If some future plugin abuses BufReadPost on a synthetic buffer and this
-- misbehaves, the fix is a `vim.bo[args.buf].buftype == ''` guard here — not
-- needed today. See GUIDE.md "Cursor-restore rides BufReadPost".
vim.api.nvim_create_autocmd('BufReadPost', {
  group = augroup,
  desc = 'Restore last cursor position',
  callback = function(args)
    -- Run at most once per buffer — BufReadPost can fire again on a later `:e`.
    if vim.b[args.buf].last_loc_restored then return end
    vim.b[args.buf].last_loc_restored = true
    -- Only touch the cursor when this buffer is the one in the current window
    -- (a background `:bufload` fires BufReadPost too, and we set the mark on
    -- window 0 below — don't move an unrelated window's cursor).
    if vim.api.nvim_win_get_buf(0) ~= args.buf then return end
    local ft = vim.bo[args.buf].filetype
    -- gitcommit/gitrebase always want line 1. (diff mode also reads files from
    -- disk, but 'diff' isn't set yet at BufReadPost; a stray jump there is
    -- harmless and `gg` fixes it, so it's not worth guarding.)
    if ft == 'gitcommit' or ft == 'gitrebase' then return end
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(args.buf)
    -- Only jump if the saved line is still within the (possibly shrunk) file.
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Briefly flash yanked text so you can see exactly what landed in the
-- register. Extra useful here because of the split-clipboard maps (`y` yanks
-- to the system clipboard, `dd`/`x`/`c` stay in the default register — see
-- keymaps.lua): the flash confirms which characters/lines were captured.
vim.api.nvim_create_autocmd('TextYankPost', {
  group = augroup,
  desc = 'Highlight yanked text',
  callback = function() vim.hl.on_yank() end,
})

-- `q` closes transient, read-only help and quickfix/loclist windows the way
-- `q` already closes a Neogit or fugitive buffer — so you don't reach for
-- `:q`. Scoped tightly to the `help`/`quickfix` buftypes on purpose: `nofile`
-- was NOT included because it over-matches (diffview diff panes, LSP hover/
-- diagnostic floats, mini.notify history, code-ish scratch), the exact
-- over-reach buffers.lua warns about — and help/quickfix are the only buffers
-- with an unambiguous "q closes me" convention. Skips any buffer that already
-- binds `q` (a quickfix enhancer, say) so a plugin's own map is never
-- clobbered. `silent!` swallows E444 on the last window. Note: this shadows
-- macro-recording `q` in these two window types (a non-issue for help/qf).
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = augroup,
  desc = 'Map q to close transient windows',
  callback = function(args)
    local buf = args.buf
    local bt = vim.bo[buf].buftype
    if bt ~= 'help' and bt ~= 'quickfix' then return end
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if m.lhs == 'q' then return end
    end
    vim.keymap.set('n', 'q', '<Cmd>silent! close<CR>', { buffer = buf, desc = 'Close window' })
  end,
})

-- Quit nvim when the only non-floating windows left are sidebars. Without
-- this, closing your last code window leaves a lone nvim-tree/aerial panel
-- sitting there and you have to close it by hand. Generalized from the old
-- nvim-tree-only handler to every sidebar via `is_sidebar()` — which is
-- deliberately NARROWER than `is_special()`: a lone toggleterm is special but
-- must NOT trigger a quit. Window arithmetic: if total minus floating minus
-- sidebars == 1, the one remaining normal window is the one being quit, so
-- close the sidebars and let nvim exit.
vim.api.nvim_create_autocmd('QuitPre', {
  group = augroup,
  desc = 'Quit nvim when only sidebars remain',
  callback = function()
    local sidebar_wins, floating, total = {}, 0, 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      total = total + 1
      if vim.api.nvim_win_get_config(w).relative ~= '' then
        floating = floating + 1
      elseif buffers.is_sidebar(vim.api.nvim_win_get_buf(w)) then
        table.insert(sidebar_wins, w)
      end
    end
    if total - floating - #sidebar_wins == 1 then
      for _, w in ipairs(sidebar_wins) do
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end,
})

-- Don't let the list panels scroll off their own content — a file tree showing
-- three files and twenty blank rows (or scrolled right until the names are gone
-- entirely) is just dead space. This is the fix for that symptom; scrolloff/
-- sidescrolloff are NOT (a common misreading, and one this config already shipped
-- once as a no-op). Those two only pad the view around the CURSOR: they have no
-- effect at EOF, and they don't constrain the view at all when it's scrolled
-- directly — a trackpad <ScrollWheelDown>/<ScrollWheelRight> moves topline/leftcol
-- without moving the cursor. Nothing but clamping the view stops that, on either
-- axis.
--
-- Its own list, deliberately not buffers.lua's `sidebar_filetypes` — which today
-- holds these same two entries but answers "is this a docked sidebar" (for the
-- quit-when-only-sidebars handler above). Registering a future panel there
-- shouldn't silently opt it into scroll clamping. Same reasoning the module
-- header gives for keeping autosave/statusline lists separate.
--
-- Both panels are nowrap, so screen rows map 1:1 to lines and the last legal
-- topline is a simple subtraction. Horizontally, the widest line is measured in
-- display cells (strdisplaywidth — the tree is full of multi-cell devicons) and
-- compared against the window's text area, which is the window width minus
-- `textoff` (sign/fold/number columns).
local clamped_panels = { NvimTree = true, aerial = true }

vim.api.nvim_create_autocmd('WinScrolled', {
  group = augroup,
  desc = 'Panels: clamp scroll to the panel content, both axes',
  callback = function(args)
    -- WinScrolled sets <amatch> to the id of the window that scrolled, which is
    -- not necessarily the current one (any window in the tabpage can fire it).
    local win = tonumber(args.match)
    if not win or not vim.api.nvim_win_is_valid(win) then return end
    local buf = vim.api.nvim_win_get_buf(win)
    if not clamped_panels[vim.bo[buf].filetype] then return end
    vim.api.nvim_win_call(win, function()
      local view = vim.fn.winsaveview()
      local restore = false

      local maxtop = math.max(1, vim.api.nvim_buf_line_count(buf)
        - vim.api.nvim_win_get_height(win) + 1)
      if view.topline > maxtop then
        view.topline = maxtop
        restore = true
      end

      if view.leftcol > 0 then
        local widest = 0
        for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          widest = math.max(widest, vim.fn.strdisplaywidth(line))
        end
        local textwidth = vim.api.nvim_win_get_width(win)
          - (vim.fn.getwininfo(win)[1].textoff or 0)
        local maxleft = math.max(0, widest - textwidth)
        if view.leftcol > maxleft then
          view.leftcol = maxleft
          restore = true
        end
      end

      if restore then vim.fn.winrestview(view) end
    end)
  end,
})
