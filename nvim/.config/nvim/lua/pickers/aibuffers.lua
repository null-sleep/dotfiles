-- pickers/aibuffers.lua — multi-select picker: which open buffers to send to
-- the AI CLI as `@relpath` mentions.
--
-- USAGE
--   require('pickers.aibuffers').open()        (bound to <leader>ab)
--   <Tab> toggle a row, <c-a> select/deselect all (snacks defaults), <CR> send
--
-- WHY
--   The old <leader>ab sent sidekick's `{buffers}` var wholesale — no way to
--   leave a scratch/unrelated file out. All rows start preselected, so bare
--   <CR> keeps the old send-everything behavior; <Tab>/<c-a> narrow it.
--   Preselecting must run in `picker:find({ on_done = ... })` — snacks'
--   public post-matcher hook (fires immediately if already done) — because
--   `list:select_all()` on a not-yet-populated list is a no-op.
--
--   Deliberately no <M-N> quick-pick / <C-x> kill, unlike the other pickers here:
--   quick_pick_actions() does view(i) + confirm, and confirm reads the whole
--   multi-selection — with every row preselected, <M-3> would send ALL
--   buffers, not row 3.

local ai_context = require('ai_context')

local M = {}

function M.open()
  local items = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if ai_context.is_file(b) then
      local name = vim.api.nvim_buf_get_name(b)
      items[#items + 1] = { buf = b, file = name, text = name }
    end
  end

  if #items == 0 then
    vim.notify('No file buffers to send', vim.log.levels.INFO)
    return
  end

  local picker = Snacks.picker.pick({
    source = 'ai_buffers',
    title = 'Send buffers to AI (<Tab> toggle, <C-a> all)',
    finder = function() return items end,
    format = 'filename',
    layout = { preset = 'select' },
    confirm = function(picker)
      local sel = picker:selected({ fallback = true })
      picker:close()
      local refs = {}
      for _, item in ipairs(sel) do
        refs[#refs + 1] = ai_context.ref(item.file, vim.fn.getcwd())
      end
      if #refs > 0 then
        require('ai').send({ msg = table.concat(refs, ' ') })
      end
    end,
  })

  -- Preselect all rows post-matcher — see header.
  picker:find({ on_done = function()
    if not picker.closed then picker.list:select_all() end
  end })
end

return M
