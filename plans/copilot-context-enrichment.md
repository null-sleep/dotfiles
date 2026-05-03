# Plan: Enrich Copilot LSP Context for Better Inline Completions

## Problem

Copilot's inline completion (`textDocument/inlineCompletion`) has a narrow
view of your project. It sees the current buffer content and snippets from
open buffers — nothing more. When types, interfaces, or related functions
live in files you don't have open, Copilot has no context to draw on and
produces generic or missing suggestions.

**Concrete example:** `Animal` interface defines `Sound()` and `Name()` in
the same file. You add `type Human struct{}` and place your cursor to
implement the methods. Copilot should suggest both method stubs but doesn't
— even though the interface is right there. The model quality varies, but
the context problem is real: move `Animal` to a separate file and close
that buffer, and Copilot will never suggest the right signatures.

## How the competition solves this

### Copilot (GitHub) — what we have

- Current file + snippets from open buffers
- No project indexing
- No LSP semantic info (doesn't talk to gopls/pyright/etc.)
- Context sent via standard LSP `textDocument/didChange` sync

### Codeium / Windsurf

- Lightweight local repo scan on project open
- Builds an index of file structure, imports, type relationships
- Retrieves relevant snippets from across the project at completion time
- Sends enriched context to their own cloud models
- Has Neovim plugins (`Exafunction/codeium.nvim`)
- Trade-off: separate account, code sent to Codeium's servers, suggestion
  quality generally a step below Copilot for complex code

### Zed (Zeta / Edit Predictions)

- Uses recent edit history + syntax tree context + open files
- Lighter than full repo indexing — focused on edit-aware prediction
- Custom Zeta model is proprietary to Zed, not available externally
- NES (Copilot's `copilotInlineEdit`) is the closest Neovim equivalent
  for the "edit prediction" part

### Cursor

- Full repo embedding into a vector database at project open
- RAG pipeline: retrieves relevant chunks on every completion request
- Also uses LSP semantics (type definitions, references) to find related code
- Sends a much richer context window to the model
- Controls both sides of the pipe (editor + backend)
- Trade-off: heavy indexing, privacy implications, paid product

### Summary

| Tool | Context scope | Indexing | Uses LSP semantics |
|---|---|---|---|
| Copilot | Current file + open buffers | None | No |
| Codeium | Current file + repo-aware retrieval | Light local scan | No |
| Zed (Zeta) | Recent edits + syntax tree + open files | Edit-history focused | Partial (syntax tree) |
| Cursor | Full repo + LSP semantics | Heavy (embeddings + RAG) | Yes |

The gap: Copilot's model is good, but it's starved of context. Cursor and
Codeium solve this by owning the backend. We can't change Copilot's backend
— but we can change what it sees.

## Experimental approach: LSP notification interception

### Core idea

Intercept the `textDocument/didChange` notification that Neovim sends to
the Copilot LSP client. Before the notification reaches Copilot, enrich the
document content with type information, interface definitions, and related
function signatures gathered from other LSP servers (gopls, pyright, etc.)
and treesitter.

Copilot reads the buffer text verbatim. If we prepend context as comments
at the top, Copilot's model sees it as part of the file — no protocol
changes needed.

### Architecture

```
  Buffer changes
       │
       ▼
  Neovim LSP client
       │
       ├──► gopls / pyright / ts_ls  (unchanged)
       │
       ▼
  Interceptor (our plugin)
       │
       ├── 1. Gather context from other LSPs
       │      • workspace/symbol → related types
       │      • textDocument/typeDefinition → interfaces to implement
       │      • textDocument/documentSymbol → outlines of related files
       │
       ├── 2. Gather context from treesitter
       │      • AST-based: struct fields, function signatures, imports
       │
       ├── 3. Format as comment block
       │      • Language-appropriate comment syntax (// for Go, # for Python)
       │      • Compact: type outlines, not full implementations
       │
       ├── 4. Prepend to document content in the notification
       │      • Adjust cursor position offset (+N lines)
       │
       └──► Copilot LSP (sees enriched content)
              │
              ▼
         Completion response
              │
              ▼
         Position de-offset (strip the N-line prefix)
              │
              ▼
         Ghost text rendered at correct position
```

### Implementation plan

#### Step 1: Intercept Copilot's notify method

```lua
-- After Copilot client attaches
local client = vim.lsp.get_client_by_id(copilot_client_id)
local original_notify = client.notify

client.notify = function(method, params, ...)
  if method == 'textDocument/didChange' then
    params = enrich_params(params)
  end
  return original_notify(method, params, ...)
end
```

#### Step 2: Force full-sync mode

Copilot supports both incremental and full document sync. Incremental sync
sends diffs — modifying diffs to include prepended context is fragile and
error-prone. Force full sync so we always get the complete document text:

```lua
-- In vim.lsp.config('copilot', ...)
-- Check if there's a capability override for textDocumentSync.change
-- to force TextDocumentSyncKind.Full (1) instead of Incremental (2)
```

If the Copilot server advertises incremental sync and we can't override it,
we may need to convert incremental changes back to full content in the
interceptor.

#### Step 3: Gather context (the hard part)

Sources of context, in priority order:

1. **Current buffer's imports/requires** → resolve to file paths → read
   outlines via `textDocument/documentSymbol`
2. **Type at cursor** → `textDocument/typeDefinition` → interface/base
   class definition → extract method signatures
3. **Workspace symbols matching cursor word** → `workspace/symbol` →
   find related types/functions across the project
4. **Treesitter AST** → extract struct/class outlines from related files
   without needing an LSP round-trip

Context gathering must be **cached and async** — we can't block every
keystroke with LSP requests. Strategy:
- Cache symbol outlines per-file (invalidate on `BufWritePost`)
- Pre-fetch outlines for imported/required files on `BufEnter`
- Use stale cache during typing, refresh in background

#### Step 4: Format and prepend

```go
// [copilot-context] Auto-generated type context — do not edit
// file: animal.go
// type Animal interface { Sound() string; Name() string }
// type Cat struct { name string }
// func (c Cat) Sound() string
// func (c Cat) Name() string
// [/copilot-context]

type Human struct {
    name string
}
```

Rules:
- Use the buffer's filetype for comment syntax
- One-line-per-symbol: type signature only, no bodies
- Cap at ~50 lines to avoid drowning the model
- Include a marker so we can strip it from responses

#### Step 5: De-offset completion positions

Copilot returns completion items with line/column positions relative to the
enriched document. Subtract the context block line count to map back to the
real buffer positions.

### Unknowns and risks

| Risk | Severity | Mitigation |
|---|---|---|
| Copilot ignores/is confused by comment context | High | Test with minimal examples first — this technique works in VS Code extensions, so the model likely handles it |
| Full-sync can't be forced | Medium | Convert incremental to full in the interceptor (reconstruct buffer content) |
| Latency from context gathering | Medium | Cache aggressively, gather async, use stale data during typing |
| Position offset bugs | Medium | Thorough testing with multi-line completions, edge cases at buffer boundaries |
| Copilot rate-limits or rejects large documents | Low | Cap context at 50 lines, monitor for 429s or empty responses |
| Context becomes stale mid-editing | Low | Acceptable — even stale type info is better than none |

### Scope for a prototype

Minimal viable experiment — just enough to validate the approach:

1. Intercept `notify` on Copilot client
2. Hardcode a context block (skip dynamic gathering)
3. Verify Copilot sees the enriched content and produces better suggestions
4. Add position de-offsetting
5. Test with the `Animal`/`Human` example

If the hardcoded test works, then build out dynamic context gathering.

### Not in scope (future)

- Full repo indexing / embeddings
- Cross-file reference graph
- Context from git history (recent changes to related files)
- Applying this to NES (`copilotInlineEdit`) — different LSP method, may
  need separate interception
