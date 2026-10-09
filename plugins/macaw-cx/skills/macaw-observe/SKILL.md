---
name: macaw-observe
description: Report what this agent did - sessions, prompts, tool calls and estimated cost - from the MACAW log. Use when asked what the agent has been doing, what it ran, what it touched, or what a session cost.
---

# What this agent did

Run this and show the output:

```bash
python3 ~/.codex/plugins/cache/macaw/macaw-cx/*/bin/observe_view.py
```

Show it exactly as it is, with no summary, commentary or reformatting, and add
nothing after it. It is already the whole report, including the last line about
what to do next.
