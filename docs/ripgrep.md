# ripgrep (`rg`) — a practical guide

A learn-by-example guide to using `rg` well. Every command here was run against
real files; the outputs described are what actually happened. For the custom
file types this repo adds (`-trs`, `-ttest`, …) see [This repo's config](#repo-config)
and `ripgrep/.config/ripgrep/ripgreprc`.

## Contents

- [The mental model](#mental-model)
- [1. Basic searches](#basics)
- [2. Case sensitivity](#case-sensitivity)
- [3. The pattern is a regex](#regex)
- [4. Where to search — file types (`-t`)](#file-types)
- [5. Where to search — globs (`-g`)](#globs)
- [6. Hidden & ignored files](#hidden-ignored)
- [7. Controlling the output](#output)
- [8. Cookbook — real tasks](#cookbook)
- [This repo's config](#repo-config)
- [Gotchas cheat-sheet](#gotchas)
- [Flag quick-reference](#flag-reference)

---

<a id="mental-model"></a>
## The mental model

Four defaults explain 90% of ripgrep's behavior. Internalize these and the rest
follows:

1. **Recursive from the current directory.** `rg foo` searches every file under
   `.` — no `-r`, no path needed.
2. **It respects your ignore files and skips noise.** By default it obeys
   `.gitignore` / `.ignore` / `.rgignore`, skips hidden files/dirs (dotfiles),
   and skips binary files. This is why `rg` is fast and quiet where `grep -r`
   is slow and noisy.
3. **Case-sensitive by default.** `rg foo` does **not** match `Foo` or `FOO`.
   (It is *not* smart-case out of the box — you opt into that with `-S`.)
4. **The pattern is a regex**, using Rust's regex engine — fast, but no
   backreferences or look-around unless you pass `-P` (PCRE2).

Everything below is about *overriding* these defaults deliberately.

---

<a id="basics"></a>
## 1. Basic searches

```bash
rg foo                      # 'foo' in every non-ignored file under .
rg foo src/                 # restrict to a path (file or dir)
rg foo src/ lib/ a.txt      # multiple paths
rg 'foo bar'                # a pattern with a space — quote it
rg foo -l                   # just the FILE NAMES that contain foo
rg foo -c                   # per-file COUNT of matching lines
rg foд                      # unicode works
```

`rg` prints, per file: a heading (the filename), then `line:match` rows. Pipe
to a pager or add flags (§7) to reshape that.

---

<a id="case-sensitivity"></a>
## 2. Case sensitivity

Default is case-sensitive. Three switches:

```bash
rg foo         # case-SENSITIVE (default): matches foo, not Foo/FOO
rg -i foo      # ignore case: foo, Foo, FOO all match
rg -s foo      # force case-sensitive (useful to override a config default)
rg -S Foo      # SMART-case: case-insensitive if the pattern is all-lowercase,
               #   case-sensitive the moment you type an uppercase letter.
```

`rg -S foo` matches `Foo`; `rg -S Foo` matches only `Foo`. Smart-case is the
most ergonomic for interactive use — but note it's **opt-in**.

---

<a id="regex"></a>
## 3. The pattern is a regex

The pattern is a regular expression by default. That's powerful but bites you
when you search for text containing regex metacharacters (`. * + ? ( ) [ ] { }
| ^ $ \`).

```bash
rg 'res.status'        # '.' matches ANY char — also matches 'resXstatus'
rg -F 'res.status'     # -F / --fixed-strings: literal, '.' is just a dot
rg 'foo|bar'           # alternation: foo OR bar
rg '^import'           # anchor: lines starting with import
rg ';$'                # anchor: lines ending with ;
rg '\bfoo\b'           # word boundaries
rg -w foo              # same as \bfoo\b but simpler: -w / --word-regexp
rg -x 'foo.*'          # -x / --line-regexp: the WHOLE line must match
rg '\d{3}-\d{4}'       # digits: phone-number-ish
rg 'TODO|FIXME|XXX'    # find all the markers
```

Two engines:

```bash
rg -P 'foo(?=bar)'     # -P / PCRE2: look-ahead, look-behind, backreferences.
                       #   Needs an rg built with PCRE2 (Homebrew's is).
rg -U 'start[\s\S]*?end'   # -U / --multiline: let a match span newlines.
                           #   Note '.' still won't cross lines — use [\s\S]
                           #   or '(?s)' / --multiline-dotall for that.
```

Multiple patterns and inverting:

```bash
rg -e foo -e bar       # -e: match foo OR bar (repeatable)
rg -e '--flag'         # -e is REQUIRED when a pattern starts with '-'
rg -v foo              # -v / --invert-match: lines that do NOT contain foo
rg -v '^\s*//' -tgo    # e.g. non-comment lines
```

> **`rg` never edits files.** `-r`/`--replace` only rewrites what's *printed*
> (see §7). There's no in-place edit — pipe to `sed`/`sd` for that.

---

<a id="file-types"></a>
## 4. Where to search — file types (`-t`)

A **file type** is a named bundle of globs. Instead of `-g '*.go'` you say
`-t go`, and ripgrep looks it up. This is the cleanest way to scope by
language, and ripgrep ships **200+** built-in types.

```bash
rg foo -t go           # only Go files          (long form)
rg foo -tgo            # only Go files          (attached form — same thing)
rg foo -t py -t js     # Python OR JavaScript   (repeat -t to union)
rg foo -T test         # -T / --type-not: EXCLUDE a type
rg foo -tgo -Ttest     # combine: Go files, minus test files
```

Discover and inspect types:

```bash
rg --type-list         # every type + the globs it maps to (built-in AND custom)
rg --type-list | rg '^go:'      # what does 'go' actually cover?   → go: *.go
rg --type-list | rg -i react    # is there a type for X? (check support)
```

**Type names are curated labels, not extensions.** Most match (`go`, `lua`,
`py`, `ts`, `md`) but many don't — `rust` not `rs`, `protobuf` not `proto`,
`cpp` not `cc`, `sh` covers every shell. So `-trs` fails on stock ripgrep
(`unrecognized file type: rs`) until you alias it (below). When in doubt,
`rg --type-list` instead of guessing `-t<ext>`.

### Making your own types (`--type-add`)

Three levels, from one-off to permanent:

**1. Inline, for a single command** — define and use in one go:

```bash
rg foo --type-add 'web:*.{ts,tsx,vue}' -tweb     # one glob-set, used once
rg foo --type-add 'rs:*.rs' -trs                 # alias an awkward built-in name
```

The syntax is `--type-add 'NAME:GLOB'`. Repeat `--type-add` with the same NAME
to add more globs to it (they union). Braces expand: `*.{ts,tsx}` = `*.ts` OR
`*.tsx`.

**2. Compose types from other types** with `include:`:

```bash
# a 'web' type that IS the js + ts + css built-ins, combined
rg foo --type-add 'web:include:js,ts,css' -tweb
```

**3. Permanent, in your config** — put `--type-add` lines in the file at
`$RIPGREP_CONFIG_PATH` and they're available in *every* `rg` call. That's
exactly what this repo does (see [config](#repo-config)); an excerpt:

```
--type-add=rs:*.rs                             # alias → enables -trs
--type-add=gotest:*_test.go                    # a Go-tests type
--type-add=pytest:{test_*,*_test}.py           # brace alternation
--type-add=test:include:gotest,pytest,…        # umbrella, composed from the above
```

...which is what makes `-trs`, `-ttest`, and `-Ttest` work everywhere on this
machine.

**Two hard limits of types** (both bit us building the config above):

- **Name-only matching.** Type globs match the file *name*, never the path —
  so directory conventions (Rust's `tests/`, Go's `testdata/`) **cannot** be a
  type. Use a `-g` glob (§5) for those.
- **Include-only.** A type is a set of *inclusion* globs; you can't put a `!`
  exclusion inside one (`--type-add 'src:!*_test.go'` doesn't work). Express
  exclusions with `-T<type>` or `-g '!…'` at search time instead.

---

<a id="globs"></a>
## 5. Where to search — globs (`-g`)

`-g` filters by path/name glob. Include by default; prefix `!` to exclude.

```bash
rg foo -g '*.go'             # include: only *.go
rg foo -g '!*_test.go'       # exclude: skip *_test.go
rg foo -g '*.go' -g '!*_test.go'   # combine: go files, minus tests
rg foo --iglob '*readme*'    # --iglob: case-INSENSITIVE name match
```

### Glob anchoring (the part everyone gets wrong)

ripgrep globs use **gitignore semantics**. Whether the glob contains a `/`
changes everything (all rows tested against `top.go`, `src/handlers/h.go`,
`deep/a/handlers/d.go`, `src/util.go`):

| Glob | Anchored? | Matches |
|---|---|---|
| `*.go` | no `/` → **basename, any depth** | all four `.go` files |
| `handlers/**` | has `/` → **anchored to the search root** | *nothing* (no top-level `handlers/`) |
| `**/handlers/**` | `**/` prefix → **any depth** | `src/handlers/h.go`, `deep/a/handlers/d.go` |
| `src/**` | anchored, `src` is at root | everything under `src/` |
| `src/**/*.go` | anchored root, `.go` any depth below | `src/handlers/h.go`, `src/util.go` |

Rule of thumb: **no slash = matches the filename anywhere; any slash = the
whole path is matched from the root.** Prefix with `**/` to un-anchor.

### The `-g`-overrides-`-t` trap

This is the subtle one. An **include** `-g` glob becomes the whitelist and
**overrides** a `-t` type filter; an **exclude** (`!`) glob does not.

```bash
# GOAL: 'foo' in Rust files whose NAME contains 'price'.

rg foo -g 'price*' -trs      # WRONG twice over:
                             #   • 'price*' = STARTS with price (misses get_price.rs)
                             #   • the include -g overrides -trs → leaks price.py, price.txt
rg foo -g '*price*.rs'       # RIGHT: fold the extension into the glob.
```

Why: an include `-g` defines the file set outright, so the type filter is
ignored. You **cannot AND a name-glob with `-t`** — bake the extension into the
glob instead. But an **exclude** glob combines with `-t` perfectly, because it
only removes files rather than defining a whitelist:

```bash
rg foo -tgo -g '!*_test.go'  # CORRECT: -tgo holds; just drops the test files.
```

So: `-t` + `-g '!…'` (exclude) → fine. `-t` + `-g '…'` (include) → the glob
wins.

---

<a id="hidden-ignored"></a>
## 6. Hidden & ignored files

By default `rg` skips dotfiles and honors `.gitignore`. Peel that back in
stages:

```bash
rg foo --hidden              # also search hidden files/dirs (.github/, .env…)
rg foo --no-ignore           # ignore .gitignore/.ignore (search node_modules/ etc.)
rg foo -u                    # -u   = --no-ignore
rg foo -uu                   # -uu  = --no-ignore + --hidden
rg foo -uuu                  # -uuu = also search BINARY files
rg foo --hidden -g '!.git'   # hidden, but still skip the .git dir explicitly
```

`-u`/`-uu`/`-uuu` ("unrestricted") is the fastest way to say "just search
everything." Reach for it when a file you *know* exists isn't turning up — it's
almost always ignore/hidden filtering hiding it.

### Compressed files & preprocessing

`rg` can also look *inside* files it can't read as plain text:

```bash
rg -z foo                  # -z / --search-zip: search INSIDE gz, bz2, xz, zip, …
```

For anything else (PDFs, docx, images-with-text), `--pre PROG` runs `PROG
<file>` on each file and searches the program's stdout. Wrap tools that don't
already write to stdout, and use `--pre-glob` to limit *which* files pay the
(slow) preprocessing cost:

```bash
# a wrapper script `rgpre` on PATH:
#   #!/bin/sh
#   case "$1" in *.pdf) exec pdftotext "$1" - ;; *) exec cat "$1" ;; esac
rg foo --pre rgpre --pre-glob '*.pdf'   # grep the text of PDFs
```

---

<a id="output"></a>
## 7. Controlling the output

```bash
rg foo -l                    # files WITH a match (names only)
rg foo --files-without-match # files with NO match
rg foo -c                    # count of matching LINES per file
rg foo --count-matches       # count of MATCHES (multiple per line counted)
rg foo -o                    # print only the matched text, not the whole line
rg foo -n                    # force line numbers (default when to a terminal)
rg foo -N                    # no line numbers
rg foo --column              # add column numbers
rg foo -A2 -B2               # 2 lines of context After / Before
rg foo -C3                   # 3 lines of context both sides
rg foo -H                    # always show the filename (even for one file)
rg foo --no-heading          # grep-style file:line:text on every row
rg foo --stats               # summary: matches, files searched, time
rg --files                   # DON'T search — just list files rg would search
rg --files -g '*.go'         #   → a fast, ignore-aware file finder
rg -q foo && echo found      # -q / --quiet: no output, exit code only (scripts)
```

Non-destructive **replace preview** — combine `-o`/`-r` to reshape matches
(files are never modified):

```bash
rg -o 'foo=(\d+)' -r 'N=$1' app/b.go   # prints 'N=42' for a line 'foo=42'
rg 'TODO' -r 'DONE'                     # preview a rename across the tree
```

Machine-readable:

```bash
rg foo --json                # one JSON object per match — feed to jq / tools
rg foo --vimgrep             # file:line:col:text, one match per line (editor quickfix)
```

---

<a id="cookbook"></a>
## 8. Cookbook — real tasks

```bash
# Find a function definition across a Go project, tests excluded
rg -tgo -Ttest 'func handleRequest'

# Every TODO/FIXME with 1 line of context, only in source (this repo's config)
rg 'TODO|FIXME' -Ttest -C1

# Search only Rust files whose name contains 'price'
rg foo -g '*price*.rs'

# Case-insensitive search for an env var name in shell + config files
rg -i -tsh -g '*.env' RIPGREP_CONFIG_PATH

# List which files import a module (names only), TS/TSX
rg -l "from ['\"]react['\"]" -g '*.{ts,tsx}'

# Count how many times a symbol appears, per file, most-used last
rg -c mySymbol | sort -t: -k2 -n

# Find a literal string with regex chars in it
rg -F 'array[0].length'

# A phone-number-shaped pattern, whole word
rg -w '\d{3}-\d{3}-\d{4}'

# Multi-line: a struct/block spanning lines
rg -U 'type \w+ struct \{[\s\S]*?\}'

# PCRE look-behind: 'value' only when preceded by 'default '
rg -P '(?<=default )value'

# Use rg as a fuzzy-free file finder, respecting .gitignore
rg --files -g '!*_test.go' -tgo

# What files would a search touch? (debug an unexpected empty result)
rg foo --files-without-match --stats
rg foo --debug 2>&1 | head        # shows WHY files are skipped
```

### Rust-specific

Using this repo's `-trs` alias and `test` type (see [config](#repo-config)):

```bash
# Every fn definition (also catches `pub fn` and `async fn`)
rg -trs '^\s*(pub\s+)?(async\s+)?fn \w+'

# Audit panic-on-None/Err smells
rg -trs '\.(unwrap|expect)\('

# Risky or unfinished spots
rg -trs 'todo!|unimplemented!|panic!|\bunsafe\b'

# All derive attributes / all macro definitions
rg -trs '#\[derive\('
rg -trs 'macro_rules!'

# Which crates/modules are imported (extract the root of each `use`)
rg -trs -o '^use +(\w+)' -r '$1' | sort -u

# A struct with its fields, or a #[test] fn with its attribute (multiline)
rg -trs -U 'struct \w+ \{[\s\S]*?\}'
rg -trs -U '#\[test\][\s\S]*?fn \w+'

# impl blocks for a specific type
rg -trs 'impl(<[^>]*>)? +Price\b'

# Find a fn in Rust SOURCE, excluding test files; or search only tests
rg -trs -Ttest 'fn handle_request'
rg -ttest 'fn '
```

Remember Rust's caveat: unit tests are inline `#[cfg(test)]`, not separate
files, so `-Ttest` only drops the `*_test.rs` test *files* — it can't exclude
inline unit-test modules. Grep those out with a pattern if needed
(e.g. narrow to a module) rather than a type.

---

<a id="repo-config"></a>
## This repo's config

`rg` reads flags from the file at `$RIPGREP_CONFIG_PATH` on every invocation.
This repo ships one as the [`ripgrep` stow package](../README.md#ripgrep) —
`ripgrep/.config/ripgrep/ripgreprc`, with `RIPGREP_CONFIG_PATH` exported from
`zsh`. It contains **only `--type-add` lines** (which merely register types and
change no behavior), because the *same file is read by the Neovim snacks
snacks pickers* when they shell out to `rg` — a stray `--smart-case` or
`--hidden` there would silently reshape every picker search.

What it adds:

```bash
rg foo -trs            # 'rs' alias for the built-in 'rust' type
rg foo -Ttest          # exclude test files (any language: gotest, pytest, …)
rg foo -ttest          # search ONLY test files, any language
rg foo -tgotest        # or a single language's tests
```

To add your own: put more `--type-add=name:glob` lines in that file
(remember: **type globs are name-only** — no directory matching — and
include-only, so no `!` exclusions inside a type). Anything you'd type
per-search that changes *behavior* should stay on the command line, not in the
config.

Related: [`plans/telescope-vs-snacks-picker.md`](../plans/telescope-vs-snacks-picker.md)
covers using these types from inside the editor pickers (`-tgo -Ttest` in a
live-grep-args / snacks `--` prompt).

---

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **Case-sensitive by default.** `rg foo` misses `Foo`. Use `-i` or `-S`.
- **The pattern is a regex.** Searching for `a.b()` or `arr[0]`? Use `-F`.
- **Include `-g` overrides `-t`.** `-g '*price*' -trs` leaks non-Rust files.
  Fold the extension into the glob (`*price*.rs`). Exclude globs (`-g '!…'`)
  *do* combine with `-t`.
- **Glob anchoring:** a glob with a `/` is anchored to the search root; without
  a `/` it matches the basename at any depth. Prefix `**/` to un-anchor.
- **Type globs are name-only** and include-only — no directory matching, no
  `!` exclusions inside a `--type-add`.
- **Type names ≠ extensions** — `rust` not `rs` (until you alias it),
  `protobuf` not `proto`. Check `rg --type-list`.
- **Ignore/hidden filtering hides files.** Missing an expected result? Try
  `-uu`, or `--debug` to see why a file was skipped.
- **Quote your patterns and globs.** `rg *.go` lets the *shell* expand `*.go`
  first; you want `rg -g '*.go'` (rg does the globbing).

---

<a id="flag-reference"></a>
## Flag quick-reference

| Flag | Meaning |
|---|---|
| `-i` / `-s` / `-S` | ignore-case / case-sensitive / smart-case |
| `-F` | fixed-strings (literal, not regex) |
| `-w` / `-x` | word-boundary / whole-line match |
| `-e` / `-v` | explicit/repeatable pattern / invert-match |
| `-P` / `-U` | PCRE2 (look-around) / multiline |
| `-t` / `-T` | include / exclude a file type |
| `-g` / `--iglob` | glob filter / case-insensitive glob |
| `--hidden` / `-u`/`-uu`/`-uuu` | search hidden / progressively unrestricted |
| `-z` / `--pre` | search inside compressed files / preprocess each file |
| `-l` / `--files-without-match` | files with / without a match |
| `-c` / `--count-matches` | count lines / count matches |
| `-o` / `-r` | only-matching / replace in output (non-destructive) |
| `-n` / `-N` / `--column` | line numbers on / off / add columns |
| `-A` / `-B` / `-C` | context after / before / both |
| `-q` | quiet — exit code only, no output |
| `--no-heading` / `--vimgrep` / `--json` | grep-style / editor / machine output |
| `--files` | list files instead of searching |
| `--type-list` / `--type-add` | list types / define one inline |
| `--stats` / `--debug` | summary / explain what got skipped |
