# MACAW for Claude Code and Codex

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.2.6-green.svg)](https://github.com/macawsecurity/macaw-plugin)
[![Harness](https://img.shields.io/badge/harness-Claude%20Code%20%7C%20Codex-blue.svg)](https://github.com/macawsecurity/macaw-plugin)

**Hooks that put every tool call, prompt, and skill load a coding agent makes through a policy decision before it runs.**

## What This Is

*Alignment is a property of the model. Control is a property of the system.*

An agent crosses four boundaries as it works: context, data, prompts, and tool
calls — which includes MCP servers and skills. These plugins put a hook on all
four.

MACAW is a **distributed zero-trust mesh**: every hook is a **policy
enforcement point**, so the controls are preventative and deterministic even
though the agent driving them is not. Install one and get:

- **A decision before the call** — with a MACAW sidecar on the machine, every
  crossing waits for an allow or a block
- **A record without one** — no sidecar, no account and no key: the hook writes
  what happened and gets out of the way
- **Nothing off the machine** — the hooks talk to 127.0.0.1, carry no
  credentials, and send no telemetry
- **A readable enforcement path** — nine short shell scripts, each a `curl` and
  an exit code

Learn more: https://macawsecurity.ai

## Installation

**Claude Code:**

```
/plugin marketplace add macawsecurity/macaw-plugin
/plugin install macaw-cc@macaw
```

**Codex:**

```bash
codex plugin marketplace add macawsecurity/macaw-plugin
codex plugin add macaw-cx@macaw
```

Codex asks you to trust the hooks on first run. Review them and accept; nothing
fires until you do. The trust is keyed to each hook's command line, so later
updates to the scripts themselves do not ask again.

## How It Works

```
┌─────────────────┐     ┌────────────────┐     ┌──────────────┐
│  Claude Code    │────▶│   MACAW hook   │────▶│  the call    │
│  Codex          │     │   PreToolUse   │     │  runs        │
└─────────────────┘     └───────┬────────┘     └──────────────┘
                                │
                   ┌────────────┴────────────┐
                   ▼                         ▼
        ┌─────────────────────┐   ┌─────────────────────┐
        │ sidecar on 18820    │   │ no sidecar          │
        │ ─────────────────── │   │ ─────────────────── │
        │ asks for a decision │   │ records the call    │
        │ allow or block      │   │ allows it           │
        └──────────┬──────────┘   └─────────────────────┘
                   │                 ~/.macaw/logs/
                   │
  ─ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─    network
                   │
                   ▼
        ┌─────────────────────┐
        │ MACAW control plane │
        │ ─────────────────── │
        │ • Policy engine     │
        │ • Approvals         │
        │ • Signed audit      │
        └─────────────────────┘
```

The sidecar fetches policy from the control plane and enforces it in place. The
policy enforcement point sits on the machine, in the path of the call, and the
agent has no route around it — it cannot reach the control plane, and it cannot
approve its own request.

Decisions are logged to the control plane. The log carries no file contents, no
prompt text and no invocation parameters — that data stays on the same machine,
container or app as the agent.

Everything that reaches a sidecar is treated identically in both modes. Only
"there was nothing to ask" differs:

| | plugin (observe) | `macaw-sidecar --install` (enforce) |
|---|---|---|
| sidecar unreachable, timeout, HTTP error | record, allow | **block** |
| sidecar returns nothing | **block** | **block** |
| sidecar denies | **block** | **block** |
| sidecar allows | allow | allow |

Observe does not soften a deny. An empty reply blocks in both modes — the
sidecar answered without deciding.

The port is fixed at 18820. Hooks take their configuration from the command
they were registered with, never from the environment: an address an export can
change is an address an attacker can change. A plugin manifest has no way to
set that command's arguments, so if your sidecar is on another port, use the
binary — it writes the port into the hooks it registers.

## What Gets Recorded

```
~/.macaw/logs/observe-YYYY-MM-DD.jsonl
```

One line per event — session start, prompt, tool call, tool result — written as
the harness reported it, with a timestamp in front. The file rotates at 4 MB,
roughly ten thousand calls, keeping one previous generation.

```bash
macaw-sidecar --view        # session → prompt → tool, if you have the binary
jq . ~/.macaw/logs/observe-*.jsonl
```

The log is local and unsigned. Only the sidecar produces a signed audit trail.

## Plugins

| plugin | harness | sidecar routes | commands |
|---|---|---|---|
| `macaw-cc` | Claude Code | `/claudecode/*` | `/macaw-cc:observe`, `/macaw-cc:protect` |
| `macaw-cx` | Codex | `/codex/*` | skills `macaw-observe`, `macaw-protect` |

They are separate because both harnesses discover hooks at the same path
(`hooks/hooks.json`), so one bundle cannot give them different ones. Claude Code
cannot install `macaw-cx` at all — it carries no `.claude-plugin/` manifest.

Codex has no plugin slash commands; it rewrites `commands/` into skills with
generated names. So macaw-cx ships the same two as skills, which you ask for
rather than type.

## Hooks

Six scripts for Claude Code, three for Codex.

| hook | script | behaviour |
|---|---|---|
| `PreToolUse` | `macaw-pre-tool.sh` | the gate — decision, or record |
| `UserPromptExpansion` | `macaw-prompt-expansion.sh` | the same, for `/skill` and `/mcp-prompt` loads |
| `UserPromptSubmit` | `macaw-user-prompt.sh` | records the prompt; the only event carrying its text |
| `PostToolUse` | `macaw-post-tool.sh` | audit only, never blocks |
| `SessionStart` / `SessionEnd` | `macaw-session-*.sh` | session bookkeeping, never blocks |
| — | `macaw-observe.sh` | sourced by the others; writes the log |

Codex uses `macaw-cx-gate.sh` (PreToolUse, UserPromptSubmit) and
`macaw-cx-audit.sh` (the rest), because its contract differs: an allow is an
empty body, and a block needs a non-empty stderr or Codex proceeds.

## Moving to Enforcement

```
/macaw-cc:protect
```

Walks through `npx macaw-ai install` — it fetches the binary, creates a
workspace you approve in a browser, and registers hooks that can block. Or run
it yourself:

```bash
npx macaw-ai install
macaw-sidecar --status      # Sidecar: running (pid …, port 18820)
```

## Running Alongside the Binary

Don't. Both record every call, and only the binary can block. Running both
records everything twice.

Installing the binary asks whether to disable the plugin. Say yes.

Installing the plugin into a project that already has binary hooks does not
ask. Remove the hooks block from that project's `.claude/settings.json`.

## Limits

`UserPromptExpansion` fires when **you** type `/skill`. It does not fire when
the model invokes a skill itself — whatever that skill then does is still seen
at `PreToolUse`, but the load is not.

**The model calls are not visible to a plugin.** Hooks see tool calls; routing
the conversation itself through the sidecar needs `ANTHROPIC_BASE_URL`, and a
plugin manifest carries hooks and nothing else. So this records what the agent
did, never what it was asked or answered. `npx macaw-ai install` adds that,
because it writes the setting and launches the harness itself.

## Research

- **[Authenticated Workflows: A Systems Approach to Protecting Agentic AI](https://arxiv.org/abs/2602.10465)**
- **[Protecting Context and Prompts: Deterministic Security for Non-Deterministic AI](https://arxiv.org/abs/2602.10481)**

## Links

- **GitHub**: [github.com/macawsecurity/macaw-plugin](https://github.com/macawsecurity/macaw-plugin)
- **Adapters**: [github.com/macawsecurity/secureAI](https://github.com/macawsecurity/secureAI)
- **Documentation**: [www.macawsecurity.ai/docs](https://www.macawsecurity.ai/docs)
- **Support**: help@macawsecurity.com

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

Attribution travels with the NOTICE file, so anything built on these hooks
carries it.
