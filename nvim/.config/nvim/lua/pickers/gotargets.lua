-- pickers/gotargets.lua — Go run/debug targets picker (the `go list` answer to
-- rust-analyzer's runnables/debuggables).
--
-- USAGE
--   require('pickers.gotargets').open('debug')   -- <leader>dR in a go buffer
--   require('pickers.gotargets').open('run')     -- <leader>cR in a go buffer
--
-- WHY THIS EXISTS
--   dap-go's seven launch configs are not targets: "Debug" is ${file} and
--   "Debug Package" is ${fileDirname} (nvim-dap-go/lua/dap-go.lua:105-133),
--   so neither can launch a main package you aren't already sitting in. In a
--   cmd/foo layout that's the whole job. `go list` is Go's target provider.
-- See plans/go-targets-picker.md for the full design rationale.

local Async = require('snacks.picker.util.async')
local common = require('pickers.common')

local M = {}

-- One line per package. `|` is safe: neither an import path nor a package dir
-- can contain it. Fields: kind, import path, abs dir, #in-package test files,
-- first .go file (used for the preview only).
local LIST_FORMAT = table.concat({
  '{{if eq .Name "main"}}main{{else}}pkg{{end}}',
  '{{.ImportPath}}',
  '{{.Dir}}',
  '{{len .TestGoFiles}}',
  '{{if .GoFiles}}{{index .GoFiles 0}}{{end}}',
}, '|')

-- Module root from the BUFFER's directory, not nvim's cwd (same rule as
-- pickers/gitstatus.lua): editing a file in another repo/module must enumerate
-- THAT module. nil = no go.mod up the tree.
local function module_root()
  local dir = vim.fn.expand('%:p:h')
  if dir == '' then dir = vim.uv.cwd() end
  return vim.fs.root(dir, 'go.mod')
end

local function debug_target(item, root)
  -- program = the package DIRECTORY: delve's LaunchConfig.Program is "path to
  -- the program folder ... when in debug or test mode" (delve
  -- service/dap/types.go:78-85). An import path is not accepted there.
  -- outputMode = 'remote' is mandatory, not decorative: the adapter runs delve
  -- detached (nvim-dap-go/lua/dap-go.lua:19), and a detached server can't
  -- forward the debuggee's stdout in delve's default 'local' output mode — the
  -- program would appear to print nothing. dap-go sets it on all seven of its
  -- own configs for the same reason.
  -- filetype is passed explicitly because dap.run() otherwise reads
  -- vim.bo.filetype (dap.lua:624), which may still be the picker's buffer.
  require('dap').run({
    type = 'go',
    name = 'Debug ' .. item.importpath,
    request = 'launch',
    mode = 'debug',
    program = item.dir,
    cwd = root,
    outputMode = 'remote',
  }, { filetype = 'go' })
end

local run_term -- reused across runs; a second run replaces the first

local function run_target(item, root)
  local Terminal = require('toggleterm.terminal').Terminal
  if run_term then
    run_term:shutdown()
  end
  -- `go run <import-path>` from the module root reaches any main package in the
  -- module, from any buffer — which is exactly what a hand-rolled `go run .`
  -- could not do (plans/go-run-debug-test.md, Alternatives).
  -- close_on_exit = false so the program's output survives its exit.
  run_term = Terminal:new({
    -- Fixed high id, same convention as terminal.lua's bottom panel (id = 100):
    -- without an explicit id, toggleterm hands out the lowest free integer, which
    -- would drop this terminal into the 1-99 pool reserved for count-addressable
    -- floats (2<C-\>, 3<C-\>) and the <C-]> cycle list — and its id would shift
    -- between runs, since shutdown() frees it again.
    id = 101,
    cmd = 'go run ' .. vim.fn.shellescape(item.importpath),
    dir = root,
    direction = 'float',
    close_on_exit = false,
  })
  run_term:toggle()
end

--- @param mode 'debug'|'run'
function M.open(mode)
  local root = module_root()
  if not root then
    vim.notify('Not in a Go module (no go.mod up the tree)', vim.log.levels.WARN)
    return
  end

  local qp_actions, qp_keys = common.quick_pick_actions()

  return Snacks.picker.pick({
    source = 'go_targets',
    title = mode == 'debug' and 'Go debuggables' or 'Go runnables',
    actions = qp_actions,
    win = { input = { keys = qp_keys }, list = { keys = qp_keys } },
    -- Async finder (the pickers/symbols.lua shape): the picker window opens
    -- immediately and fills when `go list` returns. Measured: 0.05s on
    -- fixtures/, 0.4-0.6s on a 675-package module, ~3s the first time a module's
    -- deps aren't downloaded yet — all of which would be a visible freeze if
    -- this were a :wait().
    ---@async
    finder = function(_, ctx)
      return function(cb)
        local async = Async.running()
        local res, obj
        -- Registered BEFORE the schedule() below, not after: schedule() suspends
        -- the coroutine, so an abort arriving while we're parked inside it would
        -- otherwise land before this handler exists — and the `go list` would run
        -- on unwatched. The nil-check covers the reverse window (abort before
        -- vim.system has even been called; nothing spawned, nothing to kill).
        async:on('abort', function()
          if obj then pcall(function() obj:kill(15) end) end
        end)
        async:schedule(function()
          obj = vim.system(
            -- -e: keep going past a broken package. Without it a single bad
            -- import anywhere in the module exits 1 — with every good target
            -- still on stdout. See plans/go-targets-picker.md "go list —
            -- measured". DO NOT drop -e or bail on a non-zero exit below: doing
            -- so hands an empty picker to the user exactly when one broken
            -- package elsewhere in the module makes go list unhappy — the
            -- moment this feature is most wanted.
            { 'go', 'list', '-e', '-f', LIST_FORMAT, './...' },
            { cwd = root, text = true },
            -- schedule_wrap: vim.system's on_exit may run in a fast event
            -- context; resuming the picker coroutine from there is not safe.
            vim.schedule_wrap(function(r) res = r; async:resume() end)
          )
        end)
        while not res and not async:aborted() do
          async:suspend()
        end
        if not res or async:aborted() then return end

        -- Parse stdout NO MATTER the exit code: `go list` reports per-package
        -- errors on stderr and still emits the packages it did resolve. Only a
        -- run that yields zero parseable targets is a real failure. See the
        -- comment above the vim.system call — this is the single most likely
        -- thing to get "cleaned up" back into a regression.
        local found = 0
        for line in vim.gsplit(res.stdout or '', '\n', { trimempty = true }) do
          local kind, importpath, dir, ntests, first = line:match('^(.-)|(.-)|(.-)|(.-)|(.*)$')
          -- main packages only — see plans/go-targets-picker.md §3 (tests stay
          -- with neotest). ntests is parsed but unused: it's the hook for a
          -- future test group, and free to collect.
          if kind == 'main' then
            found = found + 1
            cb({
              text = importpath, -- what the fuzzy matcher scores
              importpath = importpath,
              dir = dir,
              relpath = vim.fs.relpath(root, dir) or dir,
              ntests = tonumber(ntests) or 0,
              -- Free source preview via snacks' default file previewer
              -- (picker/config/init.lua:197-202 keys it off item.file).
              file = first ~= '' and vim.fs.joinpath(dir, first) or nil,
            })
          end
        end

        -- Nothing at all → real error (bad module, go missing). Something, but
        -- go list also complained → the module has a broken package somewhere;
        -- say so, but still show the targets that did resolve.
        if found == 0 then
          vim.schedule(function()
            vim.notify('go list found no main packages\n' .. (res.stderr or ''), vim.log.levels.ERROR)
          end)
        elseif res.code ~= 0 then
          vim.schedule(function()
            vim.notify('go list reported errors (showing what resolved):\n' .. (res.stderr or ''),
              vim.log.levels.WARN)
          end)
        end
      end
    end,
    format = function(item, picker)
      local ret = {} ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.idx), 2), 'SnacksPickerBufNr' }
      ret[#ret + 1] = { ' ' }
      ret[#ret + 1] = { '󰟓 ', 'SnacksPickerIcon' }
      ret[#ret + 1] = { Snacks.picker.util.align(item.importpath, 50, { truncate = true }) }
      ret[#ret + 1] = { '  ' }
      ret[#ret + 1] = { item.relpath, 'Comment' }
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      -- Close first, then launch on the next tick: dap-ui / toggleterm both
      -- open windows, and doing that while the picker's floats are still up
      -- lands the new window in the wrong place (same close-then-schedule dance
      -- snacks' own ui_select uses, picker/select.lua:56-63).
      vim.schedule(function()
        if mode == 'debug' then
          debug_target(item, root)
        else
          run_target(item, root)
        end
      end)
    end,
  })
end

return M
