# Improve nerd-font icon rendering in Neovim pickers

## Context

The workspace symbol picker (`pickers/symbols.lua`) uses LSP-kind icons via
`mini.icons`. With the current font, codicon-family glyphs (`nf-cod-*`) render
visibly smaller than letters in the same row — the icons look "shrunken" next
to the symbol name. Already worked around in the picker by overriding the LSP
kind glyphs to material-design (`nf-md-*`) alternatives, which render closer
to letter height.

This plan covers a font-level improvement so the issue doesn't recur for every
new picker that introduces icons.

## Recommended path: add Symbols Nerd Font Mono as a fallback

Instead of switching the primary programming font, layer
**Symbols Nerd Font Mono** as a fallback chain entry. Letters continue to come
from the existing programming font; missing or off-sized icon ranges resolve
to Symbols Nerd Font Mono, which is purpose-built to match monospace cell
metrics. No aesthetic change to source code; icons gain consistent sizing.

### Steps

1. Install the font (one-time):
   ```sh
   brew install --cask font-symbols-only-nerd-font
   ```
2. Add a fallback entry to the terminal's font config. iTerm2 is configured
   under `~/.config/iterm2/` here; the exact key depends on terminal:
   - **iTerm2**: Preferences → Profiles → Text → "Use a different font for
     non-ASCII text" → pick `Symbols Nerd Font Mono`.
   - **Ghostty** (if migrating later): `font-family = "Symbols Nerd Font Mono"`
     listed *after* the primary font in `config`.
   - **WezTerm/Kitty/Alacritty**: each supports a `font_features` /
     `font_family` fallback list — Symbols Nerd Font Mono goes last.
3. Reopen the terminal; reload nvim. Codicon glyphs (if any survive in other
   pickers) should now render at letterform height.

## Alternative: switch primary font to JetBrainsMono Nerd Font

Drop-in replacement that renders codicons closer to letter height by default,
without needing a fallback chain. Choose this if step 1 above isn't sufficient
or if a font-stack approach is more friction than it's worth.

```sh
brew install --cask font-jetbrains-mono-nerd-font
```

Then point the terminal's primary font at `JetBrainsMono Nerd Font Mono`.

## Fonts to avoid for icon-heavy UIs

- **FiraCode Nerd Font** — ligatures look great, but codicons render small.
- **Hack Nerd Font** — icons sit at ~75% of letter height.

## Files potentially affected

- `nvim/.config/nvim/lua/pickers/symbols.lua` — once a better font is in place,
  the local `KIND_ICONS` override could be reduced or removed in favor of
  mini.icons defaults. Optional cleanup; not required.
- Terminal config (outside this repo currently): iTerm2 GUI prefs, or future
  Ghostty config.

## Verification

1. Open `<leader>ss`, type a query that hits multiple symbol kinds (function,
   variable, class, field). Each row's icon should sit on the same baseline as
   the symbol name and appear at the same approximate weight/height.
2. Open `<leader>m` (buffers) — devicons should look unchanged or improved.
3. `:lua vim.print(vim.fn.has('gui_running'))` is irrelevant; the test is
   purely visual, in the terminal.
