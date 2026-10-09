#!/bin/bash
# macaw-user-prompt.sh [enforce|observe] - records what was asked.
#
# UserPromptSubmit is the only payload carrying the prompt TEXT. PreToolUse and
# PostToolUse both carry its prompt_id, so the link from a prompt to the tools
# it caused needs nothing else - but without this the viewer would have the
# shape of a conversation and none of its content.
#
# Observe only. There is no /claudecode/prompt route: with a sidecar present
# the proxy already records the turn, and this hook has nothing to add.
MODE="${1:-enforce}"

. "$(dirname "${BASH_SOURCE[0]}")/macaw-observe.sh"

input=$(cat)
[ "$MODE" = "observe" ] && macaw_observe "$input"

# Silent. UserPromptSubmit stdout is injected into the model's context, so
# anything written here would end up in the prompt itself.
exit 0
