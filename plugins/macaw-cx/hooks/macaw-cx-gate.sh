#!/bin/bash
# macaw-cx-gate.sh - FAIL-CLOSE gate for Codex PreToolUse / UserPromptSubmit.
#
# Usage (from config.toml):  macaw-cx-gate.sh <route> <mode> [url]
#   e.g.  macaw-cx-gate.sh tool
#         macaw-cx-gate.sh prompt
#
# Codex's PreToolUse contract differs from Claude Code's in two ways that matter,
# both verified in codex-rs/hooks/src:
#
#   1. A bare permissionDecision:"allow" is REJECTED as unsupported, and "ask"
#      is rejected outright. Allow is expressed as exit 0 with empty stdout.
#
#   2. exit 2 blocks ONLY when stderr is non-empty. exit 2 with empty stderr is
#      recorded as a failed hook and Codex PROCEEDS. Claude Code blocks on bare
#      exit 2, so porting its script verbatim would fail open here.
#
# Everything else fails open too - any other exit code, a spawn error, or a
# timeout all let the call through. So this script must convert every failure
# into "exit 2 + reason on stderr" itself.
#
# Timeout layering (mirrors Claude Code, which survives the harness timeout the
# same way):
#
#   approval wait      300s   how long MACAW waits for a human
#   curl  -m           330s   outlasts the poll so we get its answer back
#   config.toml timeout 480s  never fires, because curl always caps first
#
# The script's timeout must stay below the harness timeout. If the harness one
# fires first, Codex records a failure and proceeds - the hole this ordering
# exists to close.

set -uo pipefail

ROUTE="${1:-tool}"
MODE="${2:-enforce}"
SIDECAR_BASE="${3:-http://127.0.0.1:18820}"
SIDECAR_URL="${SIDECAR_BASE}/codex/${ROUTE}"
TIMEOUT_SECONDS=330

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

block() {
    # Codex requires a non-empty stderr reason for exit 2 to block.
    printf '%s\n' "$1" >&2
    exit 2
}

# Any unexpected failure in this script is a block, not a pass.
trap 'block "MACAW gate failed unexpectedly - blocked (fail-closed)."' ERR

input=$(cat)

# -s silent, -f fail on HTTP >= 400, -m cap below the harness timeout.
#
# Wrapped in `if` so the ERR trap does not claim it: a curl failure here is
# handled by the checks below, not unexpected. A command in a test is exempt
# from the trap; a bare assignment is not.
if reason=$(printf '%s' "$input" | curl -sf -m "$TIMEOUT_SECONDS" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "$SIDECAR_URL" 2>/dev/null); then
    curl_exit=0
else
    curl_exit=$?
fi

# Unreachable, HTTP error, or slower than the sidecar should ever be. In
# observe mode there is no sidecar to reach and that is the expected state:
# record the call and let it run. A deny below still denies in both modes -
# this branch is only "there was nothing to ask".
if [ $curl_exit -ne 0 ]; then
    if [ "$MODE" = "observe" ]; then
        macaw_observe "$input"
        exit 0
    fi
    block "MACAW sidecar unreachable or errored (curl $curl_exit) - blocked (fail-closed)."
fi

# Response contract: empty body allows, any body is the deny reason.
if [ -n "${reason//[[:space:]]/}" ]; then
    block "$reason"
fi

exit 0
