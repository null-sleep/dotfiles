# Zed: spell-check extension choice

Status: decided and installed (2026-11-15). **Codebook** is in
`auto_install_extensions` in `zed/.config/zed/settings.json`. Findings come
from web searches of the Zed extension pages and project READMEs, not from
running the alternatives.

## Options

- **Codebook** ([zed.dev/extensions/codebook](https://zed.dev/extensions/codebook),
  [blopker/codebook](https://github.com/blopker/codebook)) — Tree-sitter plus
  the Spellbook (Hunspell-compatible) engine. Checks only comments, string
  literals and identifiers, not keywords or syntax. Local, free, no account.
  The extension fetches and updates the `codebook-lsp` binary. Code actions fix
  a word or add it to a project or global dictionary; a CLI lint mode suits CI.
  Same binary works in nvim. Spelling only: no grammar, loose capitalization,
  and young, so expect odd flags.
- **Typos** ([zed.dev/extensions/typos](https://zed.dev/extensions/typos),
  `typos-lsp`) — flags only a fixed list of known misspellings, so almost no
  noise but it misses anything unlisted. Configured by `.typos.toml` or
  `lsp.typos.initialization_options` in Zed settings. Best as a CI or
  pre-commit check.
- **LanguageTool** ([zed.dev/extensions/languagetool-lsp](https://zed.dev/extensions/languagetool-lsp),
  v0.2.1) — grammar and style for prose, not code-aware. Only 4 downloads, so
  new or niche. No Zed extension for LTEX, the usual LanguageTool LSP.
  Self-hosting needs Java and a server.
- **Harper** ([zed-extensions/harper](https://github.com/zed-extensions/harper))
  — lightweight local grammar checker, no Java. The better prose option than
  LanguageTool in Zed. Vale also has a Zed extension.

## Decision

Codebook, since this repo is config, scripts and comments, where identifier
spelling is the main risk and only Codebook is code-aware.

- Too noisy: fall back to Typos.
- Want prose checking for `README.md` and `docs/`: add Harper, not
  LanguageTool.

## Unverified

- Typos' marketplace version and whether it splits identifiers.
- Codebook's noise level on this repo's shell and Lua files.
