---
description: Report what your agent did - sessions, prompts, tool calls, estimated cost
allowed-tools: Bash(python3:*)
---

Run this and show the output:

!`python3 "${CLAUDE_PLUGIN_ROOT}/bin/observe_view.py"`

Show it exactly as it is, with no summary, commentary or reformatting, and add
nothing after it. It is already the whole report, including the last line about
what to do next.
