# Plan: Nvim AI Integration

## Context
Evaluate nvim plugins for Claude integration. Ideal requirements: select code in visual mode
and send to Claude, see inline diffs for changes in nvim.

---

## codecompanion.nvim vs avante.nvim vs claude-code.nvim

### Core requirements

| Requirement | codecompanion.nvim | avante.nvim | claude-code.nvim |
|---|---|---|---|
| Visual select → send to Claude | Yes (inline + chat) | Yes (`<leader>ae` edit, `<leader>aa` ask) | No |
| Inline diffs for changes | Yes (accept/reject with `gda`/`gdr`) | Yes (git-conflict style, `co`/`ct`/`ca`) | No |

### Feature comparison

| Feature | codecompanion.nvim | avante.nvim | claude-code.nvim |
|---|---|---|---|
| **Stars** | 6.5k | 17.8k | 2k |
| **Last active** | Apr 19, 2026 | Mar 30, 2026 | Feb 2026 (stagnant) |
| **UI** | Chat in split/float, inline edits in buffer | Sidebar + inline conflict markers | Raw terminal buffer |
| **Claude API direct** | Yes | Yes (default provider) | No (wraps CLI) |
| **Claude subscription auth** | No | Yes (`auth_type = "max"` — use Pro/Max without API key) | N/A |
| **Agentic mode** | Yes (`@agent` — file ops, search, commands) | Yes (bash, file ops, web search, git) | No (Claude CLI does this itself) |
| **Multi-provider** | 12+ providers + ACP adapters | 10+ providers + ACP | Claude Code CLI only |
| **Project context** | `#buffer`, `#selection`, `#viewport`, `/file`, `/symbols` | `@codebase`, `@file`, `@buffers`, `@diagnostics`, RAG | None (CLI reads files itself) |
| **MCP support** | Yes | Yes (via mcphub.nvim) | No |
| **Chat history** | Multiple simultaneous chats | Session management, `/compact` | No |
| **Dependencies** | plenary, curl | plenary, nui.nvim, cargo or curl (Rust binary) | plenary, `claude` CLI |
| **Min nvim version** | 0.11.0 | 0.10.1 | 0.7.0 |

### Unique standouts

**codecompanion.nvim:**
- ACP support wraps Claude Code CLI, Codex, Gemini CLI as chat participants inside nvim
- `#viewport` shares exactly what's on screen, `#terminal` shares terminal output
- `/symbols` uses treesitter to send token-efficient file outlines
- Reads `CLAUDE.md` and `.cursor/rules` natively
- Most actively maintained (committed Apr 19, 2026)

**avante.nvim:**
- **Zen Mode** — full-screen "vibe coding" mode (Claude Code CLI feel but in nvim)
- **Dual Boost** — query two providers, synthesize best response
- **Fast Apply** — Morph models apply changes at 2500-4500 tokens/sec
- **Claude Pro/Max auth** — use your subscription, no API key needed
- Most popular (17.8k stars)

**claude-code.nvim:**
- Simplest — just a toggle terminal for Claude CLI
- Auto-reloads files Claude modifies on disk
- Quality-of-life wrapper, not a deep integration
- Development has largely stalled

### Recommendation

**claude-code.nvim** doesn't meet the core requirements — no visual selection, no diffs.

Between the other two:
- **avante.nvim** if you want a Cursor-like experience with a sidebar, conflict-style diffs,
  and the option to use your Claude subscription directly
- **codecompanion.nvim** if you want a more "Vim native" feel with chat buffers, deeper
  extensibility, and the ability to wrap Claude Code CLI as an ACP backend

Both are solid. avante.nvim is more opinionated/batteries-included. codecompanion.nvim is more
composable/extensible.

---

## Decision: codecompanion.nvim

**Chosen:** codecompanion.nvim with ACP adapter (Claude Code CLI)

**Why:**
- ACP adapter wraps existing `claude` CLI — works with enterprise auth, no API key needed
- More composable/extensible than avante.nvim
- Most actively maintained (committed Apr 19, 2026)
- Vim-native feel with chat buffers rather than sidebar
- Deeper integration with existing plugins (telescope for file pickers, blink.cmp for completion)

**Setup details:**
- Config file: `lua/ai.lua`
- Adapter: `claude_code` (ACP — wraps `claude` CLI)
- Interactions: Chat + Inline enabled, CLI left as comments
- Keymaps: `<leader>a` prefix (AI) — avoids conflict with `<leader>ca` (LSP code action)
- Chat opens as vertical split (40% width)
- File/buffer/symbol pickers use telescope

---

## Detailed plugin notes

### codecompanion.nvim

**Repo:** https://github.com/olimorris/codecompanion.nvim

**Five interaction types:**
1. **Chat** — conversational buffer with markdown rendering
2. **Inline** — LLM writes code directly into buffer with diff preview
3. **CLI** — terminal wrapper around agent CLIs (Claude Code, Codex, Gemini CLI)
4. **Cmd** — generate nvim commands in the command-line
5. **Background** — runs tasks in background (title generation, message compaction)

**Chat buffer context:**
- Editor context: `#buffer`, `#selection`, `#diagnostics`, `#diff`, `#viewport`, `#terminal`, `#quickfix`, `#messages`, `#buffers`
- Slash commands: `/buffer`, `/file`, `/fetch`, `/image`, `/symbols`, `/help`, `/compact`, `/rules`, `/mcp`, `/resume`, `/now`
- Tools/agents: `@agent`, `@files`, `@create_file`, `@delete_file`, `@read_file`, `@insert_edit_into_file`, `@grep_search`, `@file_search`, `@run_command`, `@get_diagnostics`, `@get_changed_files`, `@ask_questions`, `@fetch_webpage`

**Built-in prompts:** `/commit`, `/explain`, `/fix`, `/lsp`, `/tests` + custom prompts

**Claude models supported:** claude-opus-4-7, claude-sonnet-4-6 (default), claude-haiku-4-5, and older models. Supports extended thinking, prompt caching, extended output (128K tokens). Anthropic server-side tools: `code_execution`, `memory`, `web_fetch`, `web_search`.

**Dependencies:** plenary.nvim, nvim >= 0.11.0, curl. Optional: treesitter (yaml parser), render-markdown.nvim, blink.cmp/nvim-cmp, telescope.

---

### avante.nvim

**Repo:** https://github.com/yetone/avante.nvim

**Core workflows:**
- `<leader>aa` — ask about selected code in sidebar
- `<leader>ae` — edit selected code via AI
- Inline conflict markers with `co` (ours), `ct` (theirs), `ca` (all), `cb` (both)
- `A` applies all suggestions, `a` applies at cursor

**Agentic tools:** `rag_search`, `python`, `git_diff`, `git_commit`, `glob`, `search_keyword`, `read_file`, `create_file`, `move_path`, `delete_path`, `bash`, `web_search`, `fetch` + custom tools

**Context mechanisms:**
- `@codebase` — project-wide context with repo mapping
- `@file`, `@buffers`, `@quickfix`, `@diagnostics` mentions
- `avante.md` project instructions file
- RAG service (Docker-based codebase indexing)
- Neo-tree/nvim-tree integration for adding files from explorer

**Unique features:**
- Zen Mode: full-screen terminal-like experience
- Dual Boost: query two providers, synthesize best response
- Fast Apply: Morph models for instant code application (96-98% accuracy, 2500-4500+ tokens/sec)
- Claude Pro/Max subscription auth (no API key needed)
- Web search: Tavily, SerpApi, Google, Kagi, Brave, SearXNG

**Dependencies:** plenary.nvim, nui.nvim, nvim >= 0.10.1, cargo or curl (Rust binary). Optional: render-markdown.nvim, nvim-web-devicons, telescope/mini.pick/fzf-lua, copilot.lua, img-clip.nvim.

---

### claude-code.nvim

**Repo:** https://github.com/greggh/claude-code.nvim

**What it does:** Terminal wrapper for `claude` CLI. Opens a toggleable terminal buffer, auto-detects git root, auto-reloads files modified by Claude.

**Features:**
- Toggle with `<C-,>`, floating or split window
- Auto-reload modified files (polls every 1s with checktime)
- Multi-instance support (one per git root)
- Command variants: `:ClaudeCodeContinue`, `:ClaudeCodeResume`, `:ClaudeCodeVerbose`
- Window nav keymaps (`<C-h/j/k/l>`)
- which-key integration

**What it does NOT do:** No visual selection, no inline diffs, no buffer context awareness, no output parsing, no code action integration.

**Dependencies:** plenary.nvim, `claude` CLI, nvim >= 0.7.0

---

## Setup debugging notes (Apr 20, 2026)

Plugin was set up and then removed due to a reliability issue. Notes below to reproduce
the working setup and document the issue.

### Prerequisites

```bash
# Install the ACP adapter binary
npm install -g @agentclientprotocol/claude-agent-acp

# Generate OAuth token (valid 1 year) — needs interactive terminal
claude setup-token

# Add to ~/.zshenv (secrets not in dotfiles repo)
export CLAUDE_CODE_OAUTH_TOKEN=<your-token>
```

### Working config (lua/ai.lua)

```lua
vim.cmd.packadd('codecompanion.nvim')

require('codecompanion').setup({
  adapters = {
    acp = {
      claude_code = function()
        return require('codecompanion.adapters').extend('claude_code', {})
      end,
    },
  },

  interactions = {
    chat = {
      adapter = 'claude_code',
      slash_commands = {
        buffer   = { opts = { provider = 'telescope' } },
        file     = { opts = { provider = 'telescope' } },
        symbols  = { opts = { provider = 'telescope' } },
      },
    },
    inline = {
      adapter = 'claude_code',
    },
    -- cli = {
    --   agent = 'claude_code',
    --   agents = {
    --     claude_code = {
    --       cmd = 'claude',
    --       args = {},
    --       description = 'Claude Code CLI',
    --       provider = 'terminal',
    --     },
    --   },
    -- },
  },

  display = {
    chat = {
      window = { layout = 'vertical', width = 0.4 },
    },
    diff = { enabled = true },
  },

  opts = { log_level = 'ERROR' },
})

-- Workaround for stale ACP connection (see Known Issue below)
local function reset_and_chat()
  for k in pairs(package.loaded) do
    if k:match('^codecompanion%.acp') then package.loaded[k] = nil end
  end
  vim.cmd('CodeCompanionChat Toggle')
end

vim.keymap.set('n',          '<leader>ac', reset_and_chat,                        { desc = 'AI: Toggle chat' })
vim.keymap.set({'n', 'v'},   '<leader>ai', '<cmd>CodeCompanion<cr>',              { desc = 'AI: Inline prompt' })
vim.keymap.set('v',          '<leader>aa', '<cmd>CodeCompanionChat Add<cr>',      { desc = 'AI: Add to chat' })
vim.keymap.set({'n', 'v'},   '<leader>ap', '<cmd>CodeCompanionActions<cr>',       { desc = 'AI: Action palette' })
```

### Other files to change when re-adding

- `lua/plugins.lua` — add `{ src = gh('olimorris/codecompanion.nvim'), version = vim.version.range('^19.0.0') }`
- `init.lua` — add `require('ai')`
- `lua/whichkey.lua` — add `{ '<leader>a', group = 'AI' }`

### Known issue: ACP init fails in some repos

**Symptom:** `[acp::connect_and_authenticate] Failed to initialize` — `claude-agent-acp`
starts then immediately exits with `code=1`. Happens in `services` but not `dotfiles`.

**Root cause:** The first ACP connection attempt fails. Clearing the codecompanion ACP module
cache (`package.loaded`) and retrying works. The exact trigger is unclear — the binary works
fine when tested manually from the same directory with the same env vars via `vim.system`.
Suspected to be a timing/async issue in codecompanion's `connect_and_authenticate` flow where
the process exits before the JSON-RPC init message is sent.

**Workaround:** The `reset_and_chat` function above clears the ACP module cache before each
chat toggle. This ensures a fresh connection and fixes the issue.

**Debugging tips:**
- Set `opts.log_level = 'DEBUG'` in the setup call
- Check `~/.local/state/nvim/codecompanion.log`
- Look for "Process started" + "Process exited (code=1)" in the same second
- Manual test: `:lua print(vim.env.CLAUDE_CODE_OAUTH_TOKEN and "token found" or "NOT found")`
- Run `:checkhealth codecompanion`

### Keymaps reference

| Keymap | Mode | Action |
|---|---|---|
| `<Space>ac` | normal | Toggle chat |
| `<Space>ai` | normal, visual | Inline prompt |
| `<Space>aa` | visual | Add selection to chat |
| `<Space>ap` | normal, visual | Action palette |
| `gda` | normal | Accept inline edit |
| `gdr` | normal | Reject inline edit |

---

## TODO
- [x] Decide between avante.nvim and codecompanion.nvim → codecompanion.nvim
- [ ] Re-add plugin and verify fix works reliably in services
- [ ] Test visual select → send to Claude workflow (`<leader>ai` in visual mode)
- [ ] Test inline diff accept/reject workflow (`gda` / `gdr`)
- [ ] Test chat with `#buffer`, `/file`, `@agent` context features
- [ ] Explore CLI interaction mode
- [ ] Consider adding render-markdown.nvim for better chat buffer rendering
- [ ] Investigate root cause of ACP init failure in services
