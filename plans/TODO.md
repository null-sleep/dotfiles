# TODO

Shipped items are pruned as they land (see GUIDE.md for what exists today:
aerial outline, Neogit + diffview, nvim-dap debugging, neotest).

2.a Git Integration and Workflow — DONE except:
  - enable spell check when reviewing?
2.b GitHub Integration: octo.nvim — lets you view, comment and review GitHub PRs
  - Heavy plugin may want to avoid or defer
3. telescope picker - where to show the preview, if we can make it dynamic
4. telescope picker - selecting an item places in near top of the screen
5. filter picker
  - Active filter display (marked high priority in the plan): when filters are
    on, nothing in the prompt/title/statusline tells you. You can be searching
    filtered without realizing it.
  - Persistence across sessions: filters reset on nvim restart.
6. Markdown editor auto lists/headings... etc.
7. Learn jump words, sentences etc shortcuts. Make a new vim basics md file
8. [What if I never?] Project tree
  - neo-tree.nvim
  - oil.nvim
10. trouble.nvim — a proper diagnostic list window. You have <leader>cd which opens telescope for diagnostics, but trouble gives a persistent, navigable panel that's better for working through a build full of errors.
11. Spell Check
  - Add the spell source to blink.cmp so suggestions appear inline while typing
  - Map something ergonomic to 1z= for quick fixes
12. Next Edit Prediction: https://github.com/BlinkResearchLabs/blink-edit.nvim
13. Harpoon — quick file navigation and marking. I have a lot of files open at once and I often want to jump back and forth between a few of them.
14. I should not, but if I did: https://nvimluau.dev/romgrk-barbar-nvim
15. Low effort way of showing buffer name of inactive windows?
19. Neovide direct open should load zsh env vars. See related plan.
20. Learn colapse/expand code blocks, and other text objects like sentences, paragraphs, etc.

## AI reccs

 ### Moderate value:
- Snippets — blink.cmp already lists snippets as a completion source but there's no snippet engine feeding it. Adding friendly-snippets (a snippet collection) with blink.cmp's built-in snippet support would make that source actually fire.
- grug-far.nvim (or spectre) — project-wide find-and-replace with a live preview buffer. <leader>sg gives you grep but not replace.

### Nice to have:
- Indent guides (indent-blankline.nvim or mini.indentscope) — visual context in deeply nested code
