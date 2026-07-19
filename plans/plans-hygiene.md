# plans/ hygiene — organization + leanness conventions (proposal)

**Status:** proposal / not adopted — written 2026-07-18, immediately after the
plans/ consolidation (26 docs / ~660K → 21 docs / ~430K; see the
`Part-of: plans/ consolidation (2026-07-18)` commit series). These are the
recommendations that came out of that audit, saved for later review. Nothing
below is in force until explicitly adopted (likely as a conventions section in
`plans/README.md` and/or a line in the repo CLAUDE.md files).

---

## 1. Organization recommendations

- **Standardize the status header.** The shrunk docs converged on a good shape
  by accident — make it a convention: every doc opens with a 2–4 line block
  stating *state* (planned / active / shipped-kept-for / parked+revival-trigger),
  *intent* in one sentence, and *why it still exists* if shipped. The index
  groups by state; when each doc self-declares the same state, index↔doc drift
  becomes mechanically greppable.
- **Add a tiny `plans-audit` checklist or skill** (like the existing
  `keymap-audit`): orphan docs not in the index, dangling links to deleted
  docs, state mismatch between doc header and index section, line-number
  citations. The consolidation audit found three orphans, one dangling code
  ref, and two mislabels — all four checks are one-liner greps worth
  automating.
- **Citation convention: anchors, never line numbers.** Code comments cite
  docs by `<a id>` anchor or exact heading; docs cite code by symbol/function
  name. The one line-number citation we had
  (`go-run-debug-test.md:264-267`, cited from python-debug-test.md) broke on
  the first shrink. Same rule GUIDE.md already has for heading grep-anchors —
  extend it to plans explicitly.
- **No archive directory.** Tempting after a purge, but git history *is* the
  archive and the deletion convention already says so; an `archive/` would
  just re-accumulate the weight.
- **Long-term exit for shipped decision records:** their traps and "why"
  mostly belong in code comments or GUIDE.md next to what they explain (the
  `dap_mode = 'manual'` rationale already half-lives in `testing.lua`). When a
  shipped doc's reference core dwindles to a couple of traps, migrate those
  into the code and delete the doc — that's the terminal state of the
  pipeline.

## 2. Keeping docs lean and intent-focused

Plan docs can carry more detail than other repo docs — the goal is relevance,
not brevity for its own sake.

- **The keep test: "does a future edit need this to act?"** Spec, traps,
  contracts, open items, reopen conditions — yes. How-we-got-here narrative —
  git history. That single question separated the ~4,500 cut lines from the
  ~2,500 kept ones in the consolidation.
- **Fold reviews in, never chronicle them.** Review findings should mutate the
  spec silently; `[review — pass 2's blocker]` tags and pass-by-pass headers
  are process residue that ages instantly (python-debug-test.md is the
  cautionary example — its tags are still pending cleanup).
- **Prune-on-land in the same change** — the same rule already enforced for
  GUIDE.md and README updates. The commit that ships a plan's last step also
  shrinks the doc to its reference core. That discipline's absence is what
  created the five giant docs.
- **Skip verbatim implementation Lua in plans.** Both big shipped docs proved
  full code sketches diverge from what ships and then read as misinformation
  (multi-claude specced a telescope picker; go-targets' §1-§7 code drifted on
  id numbering and handler order). Spec shape + constraints + gotchas; let the
  code be the code.
- **Keep "Rejected / Decided against" sections religiously** — cheapest
  re-litigation insurance in the whole system; they earned their keep
  everywhere in the audit.
- **Size as a smell, not a rule:** past ~400–500 lines, a plan doc almost
  certainly contains narrative; a periodic SPEC/REFERENCE/NARRATIVE pass over
  the biggest file in `plans/` would have caught the drift a month earlier.

---

## Additional color (added at save time)

### A status-header template

```markdown
# <Title — what this builds/decides>

**Status:** planned | active | shipped (kept for: <reasons>) | parked
  (revive when: <trigger>) — <date of last state change>
**Intent:** <one sentence — what a future session uses this doc for.>
```

The two-line version is the whole ask; docs that shipped or parked add the
parenthetical. The consolidation's shrunk docs (go-run, tvs-picker,
keymap-tracker, ghostty-followups) are live examples of the shape.

### The audit one-liners (seed for a `plans-audit` skill)

```sh
# Orphans: docs with no plans/README.md entry
for f in plans/*.md; do b=$(basename $f); [ "$b" = README.md ] && continue
  grep -q "$b" plans/README.md || echo "orphan: $b"; done

# Dangling doc links: referenced .md files that don't exist
grep -rhoE '\([a-z0-9-]+\.md' plans/*.md | tr -d '(' | sort -u |
  while read f; do [ -e "plans/$f" ] || echo "dangling: $f"; done

# Line-number citations into plan docs (fragile by construction)
grep -rnE '[a-z-]+\.md:[0-9]+' plans/ nvim/.config/nvim/lua/

# Size smell: anything over ~500 lines deserves a NARRATIVE pass
wc -l plans/*.md | sort -rn | head -5
```

A skill version would also check state mismatch (doc header vs index section),
which needs the standardized header first.

### Evidence from the 2026-07-18 consolidation (why these rules)

- The five biggest docs (~345K of ~660K) were all *shipped* work whose
  implementation narrative had been kept alongside the load-bearing parts —
  exactly what prune-on-land prevents.
- Three docs were index orphans; one code comment pointed at a deleted doc;
  two plans cited another doc as something it wasn't ("the keymap inventory").
  All four defect classes are trivially greppable — hence the audit skill.
- Two "ready to build" specs (harpoon2, af-ac's `<leader>ab` half) had rotted
  against the telescope→snacks migration because full mechanism detail was
  written down before build time. Shape + constraints would have survived; the
  verbatim keymap tables didn't.
- One doc (terminal-fresh-splits) outlived its premise entirely — the config
  rewrite removed the keymaps it patched. A periodic state check would have
  caught it; instead it sat under "ready to build" in the index.

### Adoption sketch (when picked up)

1. Add a short `## Conventions` section to `plans/README.md` (status header,
   keep test, prune-on-land, anchor citations, rejected-sections rule).
2. Add one line to the repo CLAUDE.md tying plan-shipping to the same
   "update docs in the same change" rule that GUIDE.md/README already have.
3. Optionally: create the `plans-audit` skill from the one-liners above.
4. Sweep existing docs' headers to the template (mostly done by the
   consolidation; the untouched live specs need only the two-line block).
