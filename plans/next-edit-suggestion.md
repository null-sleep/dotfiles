# Plan: Next Edit Suggestion (NLE)

NLE is the cursor/vs code copilot in editor code suggestion/prediction feature.

Neovim best out of the box solutions:
- https://github.com/milanglacier/minuet-ai.nvim#duet-next-edit-prediction
- https://github.com/zbirenbaum/copilot.lua

Tl;DR you need a fast model to do this. Which ideally has been trained for NLE
- OpenAPI spec for this exists: https://zed.dev/docs/ai/edit-prediction
- You may have t 

### F**k it, I'll do it myself

May have to work on and existing project like minuet to implement this. Some plugins support co-pilot or other models so 

- [Zed has an open source model](https://huggingface.co/zefd-industries/zeta) for this. Unclear what kind of resources may be required to run it.
  - How to run it yourself: https://www.youtube.com/watch?v=e53UrWRT-Vo
  - https://github.com/boltlessengineer/zeta.nvim
  - https://github.com/g0t4/zeta.nvim
  - https://github.com/g0t4/zed-zeta-server
  - https://www.reddit.com/r/neovim/comments/1ms8gh3/ive_become_obsessed_with_the_idea_of_edit/


