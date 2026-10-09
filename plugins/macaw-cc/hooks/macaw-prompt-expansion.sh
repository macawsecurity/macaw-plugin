#!/bin/bash
# macaw-prompt-expansion.sh [enforce|observe] - the load gate for /skill and
# /mcp-prompt expansions.
#
# Mirrors macaw-pre-tool.sh, including its modes. Only "there was nothing to
# ask" differs between them; every other outcome is identical:
#
#                                   enforce              observe
#   sidecar unreachable             BLOCK                record, ALLOW
#   sidecar timeout (curl -m)       BLOCK                record, ALLOW
#   sidecar HTTP error (curl -f)    BLOCK                record, ALLOW
#   sidecar returns nothing         BLOCK                BLOCK
#   sidecar says block              BLOCK                BLOCK
#   sidecar allows                  ALLOW                ALLOW
#
# A block is JSON on stdout, not exit 2: this event reads its decision from the
# body. An allow emits nothing, so it is not injected into the prompt as
# context.
#
# Both arguments are fixed in the registered command at package time, never
# read from the environment - see macaw-pre-tool.sh for why.
#
#   $1  enforce | observe        $2  sidecar base URL
MODE="${1:-enforce}"

SIDECAR_BASE="${2:-http://127.0.0.1:18820}"
SIDECAR_URL="${SIDECAR_BASE}/claudecode/expansion"
TIMEOUT_SECONDS=180

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

input=$(cat)

response=$(printf '%s' "$input" | curl -sf -m "$TIMEOUT_SECONDS" -X POST \
    -H "Content-Type: application/json" -d @- "$SIDECAR_URL" 2>/dev/null)
curl_exit=$?

# No sidecar. In observe mode that is the expected state, not a failure -
# blocking every skill load on a machine that never had a sidecar is a broken
# install, not a gate.
if [ $curl_exit -ne 0 ]; then
    if [ "$MODE" = "observe" ]; then
        macaw_observe "$input"
        exit 0
    fi
    echo '{"decision":"block","reason":"MACAW sidecar unreachable — load blocked (fail-closed)."}'
    exit 0
fi

# Reached the sidecar and it said nothing. A failure in both modes: something
# answered, and what it said was not a decision.
if [ -z "$response" ]; then
    echo '{"decision":"block","reason":"MACAW sidecar returned nothing — load blocked."}'
    exit 0
fi

# Emit the block decision only; an allow ({}) produces no output.
case "$response" in
    *'"decision"'*) echo "$response" ;;
esac
exit 0
