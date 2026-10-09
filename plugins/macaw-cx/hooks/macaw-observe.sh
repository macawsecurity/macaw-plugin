#!/bin/bash
# Sourced by the hooks. Records an event when there is no sidecar to ask.
#
# The hook payload already carries everything the viewer needs - Claude Code
# puts prompt_id on PreToolUse and PostToolUse, and Codex puts turn_id on both,
# so a tool is attributed to the prompt that caused it without inference. The
# payload is written through unchanged with a timestamp in front, rather than
# picking fields and defining a schema that would then have to track two
# harnesses.

# A bare $HOME is fatal under `set -u`, which the gates run with, and a
# sandboxed harness need not pass one - Codex does not, so sourcing this killed
# the Codex gate before it could ask anything, and the gate failed closed on
# every call. Empty when there is no HOME: there is nowhere of the user's to
# write, and /tmp is shared and world-writable, which is not a place to keep a
# record of what an agent did. macaw_observe then does nothing.
MACAW_OBSERVE_DIR="${MACAW_OBSERVE_DIR:-${HOME:+$HOME/.macaw/logs}}"

# Bytes, not lines: size is a stat where a line count is a read of the file.
# Roughly ten thousand calls.
MACAW_OBSERVE_MAX="${MACAW_OBSERVE_MAX:-4000000}"

macaw_observe_file() {
    echo "$MACAW_OBSERVE_DIR/observe-$(date -u +%Y-%m-%d).jsonl"
}

macaw_observe() {
    # $1 the raw hook payload (a JSON object)
    local payload="$1" file
    [ -z "$payload" ] && return 0
    case "$payload" in "{"*) ;; *) return 0 ;; esac   # not an object; drop it

    # Runs on every tool call, so it forks once: `date`. The day is sliced off
    # that same string rather than asked for again, mkdir runs only when the
    # directory is genuinely absent, and rotation is checked once per session
    # from the SessionStart hook. printf and the slice are builtins.
    [ -d "$MACAW_OBSERVE_DIR" ] || mkdir -p "$MACAW_OBSERVE_DIR" 2>/dev/null || return 0

    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    file="$MACAW_OBSERVE_DIR/observe-${now:0:10}.jsonl"

    # Splice ts in as the first key. Appending would need the closing brace
    # rewritten; prefixing only needs the opening one.
    printf '{"ts":"%s",%s\n' "$now" "${payload#\{}" >> "$file" 2>/dev/null || true
}

macaw_observe_rotate() {
    # Called once per session rather than once per tool call. A session that
    # runs past the cap is rotated at the next one, which bounds the file at
    # the cap plus a session.
    local file
    file="$(macaw_observe_file)"
    [ -f "$file" ] || return 0
    [ "$(wc -c < "$file" 2>/dev/null || echo 0)" -gt "$MACAW_OBSERVE_MAX" ] || return 0
    # One generation. <file>.1 is not rendered, so the view's cost stays flat.
    mv -f "$file" "$file.1" 2>/dev/null || true
}
