#!/bin/bash
# macaw-post-tool.sh - Audit logging hook (fail-open is OK here)
#
# PostToolUse runs AFTER the action completes - it's audit logging only.
# Fail-open is acceptable because:
# 1. The action already happened (can't block it)
# 2. Audit failures shouldn't disrupt user workflow
# 3. Sidecar unavailability is logged locally by Claude Code

MODE="${1:-enforce}"

SIDECAR_BASE="${2:-http://127.0.0.1:18820}"
SIDECAR_URL="${SIDECAR_BASE}/claudecode/post_tool"
TIMEOUT_SECONDS=5

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

input=$(cat)

# Fire-and-forget audit logging (timeout prevents hanging). -o /dev/null keeps
# the response body out of stdout, which the harness reads as hook output.
if ! curl -sf -m "$TIMEOUT_SECONDS" -o /dev/null -X POST \
      -H "Content-Type: application/json" \
      -d "$input" \
      "$SIDECAR_URL" 2>/dev/null; then
    # This payload carries tool_response and duration_ms, so it is where an
    # outcome comes from. Without it the record would show every call as
    # attempted and none as finished.
    [ "$MODE" = "observe" ] && macaw_observe "$input"
fi

exit 0
