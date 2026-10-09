#!/bin/bash
# macaw-pre-tool.sh [enforce|observe] - the gate.
#
# Security model. Only "there was nothing to ask" differs between the modes;
# every other outcome is identical:
#
#                                   enforce              observe
#   sidecar unreachable             BLOCK (exit 2)       record, ALLOW
#   sidecar timeout (curl -m)       BLOCK (exit 2)       record, ALLOW
#   sidecar HTTP error (curl -f)    BLOCK (exit 2)       record, ALLOW
#   sidecar returns nothing         BLOCK (exit 2)       BLOCK (exit 2)
#   sidecar returns deny            BLOCK (via JSON)     BLOCK (via JSON)
#   sidecar returns allow           ALLOW (via JSON)     ALLOW (via JSON)
#
# The three that differ are all "there was nothing to ask". Everything that
# reaches a sidecar is treated the same way in both modes - observe does not
# soften a deny, and an empty reply still blocks, because something answered
# and what it said was not a decision.
#
#   enforce   the default, and what `macaw-sidecar --install` registers. An installed
#             gate that stops gating during an outage is not a gate.
#   observe   what the plugin registers when it is the only thing installed:
#             there is no enforcement to lose, and blocking every tool on a
#             machine that never had a sidecar is just a broken install.
#
# Both arguments are fixed in the registered command at package time, never
# read from the environment. An exported MACAW_SIDECAR_URL used to point this
# at any server the caller liked, which answers "allow" as easily as the real
# one - enforcement that an export can switch off is not enforcement. The
# timeout is a constant for the same reason: set it to zero and every call
# fails, which in observe mode is allowed, so a deny could be escaped by
# making the question time out.
#
#   $1  enforce | observe
#   $2  sidecar base URL (default http://127.0.0.1:18820)
MODE="${1:-enforce}"

SIDECAR_BASE="${2:-http://127.0.0.1:18820}"
SIDECAR_URL="${SIDECAR_BASE}/claudecode/tool"
TIMEOUT_SECONDS=180

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

input=$(cat)

# Call sidecar: -s silent, -f fail on HTTP errors, -m timeout
response=$(echo "$input" | curl -sf -m "$TIMEOUT_SECONDS" -X POST \
  -H "Content-Type: application/json" \
  -d @- \
  "$SIDECAR_URL" 2>/dev/null)

curl_exit=$?

# No sidecar. In observe mode that is the expected state, not a failure.
# stderr reaches the transcript, so a block always carries its reason -
# without it an unreachable sidecar looks like an unexplained refusal.
if [ $curl_exit -ne 0 ]; then
    if [ "$MODE" = "observe" ]; then
        macaw_observe "$input"
        exit 0
    fi
    echo "MACAW: no sidecar at ${SIDECAR_BASE} (curl $curl_exit). Blocking." >&2
    echo "Start it with 'macaw-sidecar --start', or check 'macaw-sidecar --status'." >&2
    exit 2  # BLOCKING ERROR - Claude Code will block the tool
fi

# Reached the sidecar but got nothing back. This is a failure in both modes:
# something answered, and what it said was not a decision.
if [ -z "$response" ]; then
    echo "MACAW: sidecar at ${SIDECAR_BASE} returned nothing. Blocking." >&2
    exit 2  # BLOCKING ERROR
fi

# Pass sidecar's JSON response (allow/deny decision)
echo "$response"
exit 0
