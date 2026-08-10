#!/bin/bash
# Claude Code hook -> nvim agent_events bridge
# (plans/sidekick-agent-event-pipeline.md, consumed by the agent view —
# plans/sidekick-agent-view.md). Registered once per event+matcher in the
# stowed settings.json, each registration passing its own hardcoded category:
# Claude exposes no matcher to the hook subprocess, so the category MUST be
# baked into which registration fired.
#
# Hard correctness requirements — a plumbing bug must never block or alter a
# real Claude turn (Stop's exit-2 path "prevents Claude from stopping"):
# always exit 0, timeout the RPC, and interpolate ONLY the mktemp path into
# the remote expression (session names carry free user text; the tmpfile
# path is ours).

# No-op outside a sidekick-managed nvim session. Hooks are process-global:
# this fires for every claude invocation on the machine (Terminal.app, CI).
[ -n "$NVIM" ] && [ -n "$SIDEKICK_SESSION" ] || exit 0
category="$1"
[ -n "$category" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v timeout >/dev/null 2>&1 || exit 0

tmpfile=$(mktemp) || exit 0
# Own the cleanup: a dead/unreachable nvim must not leak tmpfiles.
trap 'rm -f "$tmpfile"' EXIT

# Envelope {session, category, raw}; raw keeps the hook's stdin verbatim
# (as JSON when it parses, as a string otherwise) for live inspection —
# field names beyond the envelope are unverified until observed.
raw=$(cat)
jq -n -c --arg session "$SIDEKICK_SESSION" --arg category "$category" --arg raw "$raw" \
  '{session: $session, category: $category, raw: ($raw | fromjson? // $raw)}' \
  > "$tmpfile" 2>/dev/null || exit 0

# timeout guards a stale $NVIM (nvim crashed/restarted since spawn) from
# hanging Claude's own turn completion.
timeout 2 nvim --server "$NVIM" --remote-expr \
  "v:lua.require('agent_events').handle('$tmpfile')" >/dev/null 2>&1

exit 0
