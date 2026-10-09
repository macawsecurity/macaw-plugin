#!/bin/bash
# The installer writes the sidecar URL into the registered command, so a
# non-default port reaches this hook too. Hardcoding 18820 here sent session
# tracking to a port nothing served.
#
#   $1  enforce | observe        $2  sidecar base URL
MODE="${1:-enforce}"

SIDECAR_BASE="${2:-http://127.0.0.1:18820}"
TIMEOUT_SECONDS=5

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

# -o /dev/null: a session hook's stdout is parsed as its result. Without it the
# response body reaches the harness, which reads it as malformed hook output.
# -m: a sidecar that accepts the connection and then stalls would otherwise hold
# every session open until the harness timeout fires.
input=$(cat)
if ! curl -s -f -o /dev/null -m "$TIMEOUT_SECONDS" -X POST \
      -H "Content-Type: application/json" \
      -d "$input" \
      "${SIDECAR_BASE}/claudecode/session_start" 2>/dev/null; then
    if [ "$MODE" = "observe" ]; then
        macaw_observe_rotate
        macaw_observe "$input"
        # Said once, because SessionStart fires once. Which mode is running is
        # not something to discover from the absence of denials later.
        # stderr, not stdout: this hook's stdout is read as its result.
        echo "MACAW: observing. No sidecar on ${SIDECAR_BASE}, so tool calls are" >&2
        echo "recorded to ~/.macaw/logs and not gated. View them with 'macaw-sidecar --view'." >&2
    fi
fi

exit 0
