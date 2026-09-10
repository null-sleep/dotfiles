# Code review: which skill to use

## Always use the personal `review-pr` skill

Any request to review a pull request, review a diff or branch before merge,
"look over this PR", "do a code review", or similar → invoke the personal
**`review-pr`** skill and follow it exactly: Phase 0 (gather context), then
Phase 1 (evaluate), Phase 2 (devil's advocate), Phase 3 (documentation, only
on explicit request). Do not skip or merge phases.

Canonical source, one file for every tool (the `SKILL.md` symlink this
machine's `setup-review-pr.sh` created):

    ~/src/dotfiles/claude/.claude/skills/review-pr/SKILL.md

Linked into each agent host by `claude/setup-review-pr.sh`:

| Host | Path |
| --- | --- |
| Claude Code | `~/.claude/skills/review-pr` |
| Cursor, pi, omp, OpenCode | `~/.agents/skills/review-pr` |
| Codex | `~/.codex/skills/review-pr` |

## Never use these instead

Any other review skill — a project-level `.claude/skills/review-pr/` or
`.claude/skills/code-review/` in a project checkout, a plugin or marketplace
review skill or command, a bundled `code-review` / `security-review`, a
built-in review command that bypasses the phases, or anything that emits a
`review.json` for a CI pipeline to post — is **not** the personal review flow
and must not be selected for a review request, even when a project-local one
looks more specific.

This rule is deliberately categorical, not a denylist: new review skills
appear without notice, and an unlisted one is still covered.

Known examples, non-exhaustive: `warpdotdev/common-skills`' `review-pr` (the
`review.json` one); `pr-review-toolkit`; and tracked copies that individual
project checkouts ship for their own contributors.

If one of those is somehow already loaded when a review starts, stop and use
the personal `review-pr` skill instead.

A project-specific *companion* check is a different thing and is fine — run it
in addition to `review-pr`, never instead of it.

## Never post to GitHub

The skill is user-output only. Reading GitHub is fine (`gh pr view`,
`gh pr diff`, GET via `gh api`). Publishing anything — review comments,
replies, approvals, request-changes, resolving threads, editing PR bodies —
requires an explicit per-request instruction to post, which does not carry
forward to the next batch. Absent that, the deliverable is drafts shown in the
conversation.

## Re-linking after a restow or a new machine

    bash ~/src/dotfiles/claude/setup-review-pr.sh

Idempotent. Run it after `stow -R --no-folding claude`, which leaves the
untracked `SKILL.md` symlink absent or dangling.
