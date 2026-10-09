#!/bin/bash
# macaw-cx-audit.sh - fire-and-forget audit for Codex lifecycle events.
#
# Usage:  macaw-cx-audit.sh <route> <mode> [url]
#   e.g.  macaw-cx-audit.sh session_start | post_tool | session_end
#
# FAIL-OPEN on purpose, matching Claude Code's macaw-post-tool.sh: these events
# fire after the fact, so the action has already happened and a logging failure
# must not disrupt the session. The gate is macaw-cx-gate.sh; this is not it.

set -uo pipefail

ROUTE="${1:-post_tool}"
MODE="${2:-enforce}"
SIDECAR_BASE="${3:-http://127.0.0.1:18820}"
case "$ROUTE" in session_end) TIMEOUT_SECONDS=2 ;; *) TIMEOUT_SECONDS=5 ;; esac

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

input=$(cat)

if ! printf '%s' "$input" | curl -sf -m "$TIMEOUT_SECONDS" -X POST \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "${SIDECAR_BASE}/codex/${ROUTE}" >/dev/null 2>&1; then
    [ "$MODE" = "observe" ] && macaw_observe "$input"
fi

exit 0
