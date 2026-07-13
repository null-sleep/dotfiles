-- snacks.nvim setup: the picker module (fuzzy finder) plus the scratch and
-- indent module options. There must be exactly one require('snacks').setup()
-- call, so this file owns it; scratch.lua keeps only the scratch keymaps.
-- Picker background and decision record: plans/telescope-vs-snacks-picker.md.
vim.cmd.packadd('snacks.nvim')

-- Global picker layout: preview on the right when wide, below when narrow;
-- flips at 160 columns, evaluated per picker open. Kept as a function on
-- purpose: Snacks.config.merge only deep-merges dicts, so a function layout
-- is *replaced* wholesale by any source/call-site layout table instead of
-- leaking keys into it (a table form here would deep-merge into every
-- picker that only sets `preset`, e.g. the compact select-preset popups).
local function pick_layout()
  return {
    preset = vim.o.columns >= 160 and 'default' or 'vertical',
    -- Taller than the presets' 0.8, matching the pre-migration telescope
    -- look. Only reaches pickers that resolve this function; pinned
    -- layouts (select popups, symbols) are unaffected.
    layout = { height = 0.9 },
  }
end

-- After selecting a result, scroll so the cursor lands ~20% from the top.
-- CURSOR_TOP_RATIO: 0.0 = top of window, 0.5 = center (zz), 1.0 = bottom
local CURSOR_TOP_RATIO = 0.20

-- Global <CR> confirm: snacks' default jump + the scroll adjustment above.
-- Two snacks-internals constraints (see snacks picker actions.lua):
--  * <C-s>/<C-v> splits run *through* confirm ({ action = 'confirm', cmd =
--    'split' }) — `action` must be forwarded to jump() or every split key
--    silently degrades to an in-place edit.
--  * jump() is async while the input is in insert mode (stopinsert +
--    vim.schedule + early return, ending in `norm! zzzv`), so a naive "jump
--    then scroll" runs before the file is open and then gets clobbered.
--    Mirror the same stopinsert-and-reschedule dance so jump() runs
--    synchronously before the winrestview.
local function confirm_and_scroll(picker, item, action)
  if vim.fn.mode():sub(1, 1) == 'i' then
    vim.cmd.stopinsert()
    vim.schedule(function() confirm_and_scroll(picker, item, action) end)
    return
  end
  -- pcall: a stale item position (e.g. a mark past EOF of a shrunk file)
  -- makes jump's nvim_win_set_cursor throw — degrade to a warning instead
  -- of a stack trace. The buffer is usually open at that point, just not
  -- at the intended line.
  local ok, err = pcall(require('snacks.picker.actions').jump, picker, item, action)
  if not ok then
    vim.notify('picker jump: ' .. tostring(err), vim.log.levels.WARN)
    return
  end
  local offset = math.floor(vim.api.nvim_win_get_height(0) * CURSOR_TOP_RATIO)
  vim.fn.winrestview({ topline = math.max(1, vim.fn.line('.') - offset) })
end

-- Send the picker's current item (or multi-selection) to the active sidekick
-- CLI session as space-separated path:line refs (the sidekick README's <a-a>
-- integration, bound to <M-a> here to match the rest of this config).
-- util.path() returns nil for non-file items (help tags, keymaps, ...), so
-- those are skipped and the action no-ops gracefully on them.
local function send_to_sidekick(picker)
  local items = picker:selected({ fallback = true })
  local refs = {}
  for _, item in ipairs(items) do
    local path = Snacks.picker.util.path(item)
    if path then
      refs[#refs + 1] = item.pos and (path .. ':' .. item.pos[1]) or path
    end
  end
  picker:close()
  if #refs > 0 then
    require('ai').send({ msg = table.concat(refs, ' ') })
  end
end

require('snacks').setup({
  picker = {
    -- snacks owns vim.ui.select (consumers: nvim-tree confirmations,
    -- rustaceanvim runnables, sidekick's prompt library).
    ui_select = true,
    layout = pick_layout,
    matcher = {
      -- Boost results by recency+frequency of use (files/recent/buffers/...).
      -- Persisted store is created on first use under stdpath('data');
      -- sqlite via the system libsqlite3, with a plain-file fallback.
      frecency = true,
    },
    actions = {
      confirm = confirm_and_scroll,
      send_to_sidekick = send_to_sidekick,
    },
    win = {
      input = {
        keys = {
          -- One-press close from insert mode. 'cancel', not 'close': cancel
          -- re-pins focus to the launch window before closing.
          ['<Esc>'] = { 'cancel', mode = { 'n', 'i' } },
          ['<M-a>'] = { 'send_to_sidekick', mode = { 'i', 'n' } },
          -- <C-h> aliases the default `?` help popup (shows this picker's
          -- live keymaps); shadows the global "move to left split" <C-h>
          -- only while the picker input is focused.
          ['<C-h>'] = { 'toggle_help_input', mode = { 'i', 'n' } },
        },
      },
      list = {
        keys = {
          ['<M-a>'] = 'send_to_sidekick',
        },
      },
    },
    sources = {
      -- Include hidden files/dirs (e.g. .github/) in results. .git/ is
      -- excluded by the finders' defaults; node_modules needs the explicit
      -- exclude (it's only skipped by default when gitignored).
      files = { hidden = true, exclude = { 'node_modules' } },
      grep = { hidden = true, exclude = { 'node_modules' } },
      -- lines (<leader>sb, <leader>s/) ships a source-level layout — a
      -- bottom-docked full-width ivy strip that "previews" by scrolling the
      -- main window — which silently beats the global layout above.
      -- Assigning the same function replaces that table wholesale
      -- (including its `preview = "main"`), restoring the standard
      -- two-pane look with a real preview pane.
      lines = {
        layout = pick_layout,
        -- Match grep's empty state: an empty prompt shows *nothing* (0/0,
        -- both panes blank) instead of every buffer line — which rendered
        -- the document you're already looking at, twice. The stock finder
        -- runs only once (fuzzy pickers filter via the matcher, and an
        -- empty pattern matches everything), so the emptiness has to be
        -- produced by the finder and re-produced when the prompt flips.
        show_empty = true,  -- 0 items on open must not auto-close the picker
        finder = function(opts, ctx)
          if ctx.filter.pattern == '' then return {} end
          return require('snacks.picker.source.lines').lines(opts, ctx)
        end,
        filter = {
          -- Runs on every input change; returning true re-runs the finder.
          -- Only the empty <-> non-empty flips need it — everything else is
          -- normal matcher work on the already-collected lines.
          transform = function(picker, filter)
            local prev = picker.finder.filter
            return ((not prev or prev.pattern == '') ~= (filter.pattern == ''))
          end,
        },
      },
    },
  },
  scratch = {
    win = {
      width = 100,
      height = 30,
      border = 'rounded',  -- match toggleterm's curved float style (nvim_open_win vocabulary differs)
    },
  },
  -- Indent guides off by default; toggle on with <leader>tg. `enabled = false`
  -- survives snacks' auto-enable (setup only forces enabled=true when it's nil),
  -- so the module never activates on BufReadPost and Snacks.indent.enabled stays
  -- false until the first toggle. char/scope/animate are still registered here,
  -- so enable() picks them up when it fires.
  indent = {
    enabled  = false,
    indent   = { char = '▏' },
    scope    = { char = '▏' },
    animate  = { enabled = false },
  },
})
