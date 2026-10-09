#!/bin/bash
# See macaw-session-start.sh: the port comes from the installed configuration.
MODE="${1:-enforce}"

SIDECAR_BASE="${2:-http://127.0.0.1:18820}"
TIMEOUT_SECONDS=5

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

# See macaw-session-start.sh for why stdout is discarded and why -m is set.
input=$(cat)
if ! curl -s -f -o /dev/null -m "$TIMEOUT_SECONDS" -X POST \
      -H "Content-Type: application/json" \
      -d "$input" \
      "${SIDECAR_BASE}/claudecode/session_end" 2>/dev/null; then
    [ "$MODE" = "observe" ] && macaw_observe "$input"
fi

exit 0
