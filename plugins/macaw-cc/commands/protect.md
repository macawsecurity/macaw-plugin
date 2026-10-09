---
description: Get approvals or block risky calls. Free. One click to set up an account.
allowed-tools: Bash(command:*), Bash(npx:*), Bash(macaw-sidecar:*), Bash(cat:*), Bash(grep:*), Bash(sleep:*)
---

Move from tracking to getting approvals. Four steps, and stop between them.

**1 — is it already here?**

Three facts, none of which depend on anything being on PATH. Run all of
it and read the three lines:

```bash
echo "sidecar: $(curl -s -m 2 -o /dev/null -w '%{http_code}' \
  http://127.0.0.1:18820/health 2>/dev/null || echo 000)"
echo "hooks:   $(grep -l 'macaw-' .claude/settings.json .codex/config.toml \
  "/Library/Application Support/ClaudeCode/managed-settings.json" \
  /etc/claude-code/managed-settings.json /etc/codex/managed_config.toml \
  2>/dev/null | tr '\n' ' ')"
echo "config:  $(ls ~/.macaw/config.json 2>/dev/null)"
```

Then:

- **sidecar 200** - it is already protecting. Say so and stop. Nothing to do.
- **hooks listed, sidecar 000** - installed here but not started. Say
  `macaw-sidecar --start` and stop.
- **config listed** - they already have a MACAW workspace. Installing will
  reuse that key rather than making a new one, and no sign-in link will
  appear. Tell them that before going on.
- **all three empty** - nothing here. Go on.

Ask the port, not the CLI. `macaw-sidecar --status` cannot tell "no sidecar is
running" apart from "the binary is not on PATH", and in a directory that is
not the install directory it is never on PATH - so it reports nothing running
while one is.

**2 — say what will happen, then ask**

Print exactly this and wait for an answer. Do not run anything yet.

```
Right now MACAW tracks. This lets it stop things.

Policies decide what needs approval. Those calls wait, and you
approve them in the MACAW console - not in the terminal, where
your agent could reach them.

Free. First run spins up your workspace: a link appears here, you
click it, that's the account.

Afterwards, turn this plugin off - the install records the same
calls, so leaving both on writes everything twice:
  claude plugin disable macaw-cc@macaw

Run it?
```

**3 — start it, and relay the link**

Only after they agree. Start it detached so its output is readable while it
waits:

```bash
mkdir -p ~/.macaw && npx macaw-ai install > ~/.macaw/install.log 2>&1 &
```

Then read `~/.macaw/install.log` every few seconds until a line beginning
`Open` appears, for up to a minute. Relay that URL and the code beside it
plainly, and say you are waiting.

Do not open the URL, fetch it, or try to approve it yourself. Approval
happening somewhere this session cannot reach is the whole point of it.

**4 — wait for it to finish**

Keep reading the log until it says `Installed` or prints a failure, checking
every ten seconds or so for up to ten minutes. It will sit on
`Waiting for approval...` until they have clicked through, which is expected.

When it finishes, report the workspace name it printed and tell them to start
their agent with `./secCC` rather than `claude` - that is what routes the model
through the sidecar. Tool calls are gated either way.

If it fails, show the error as it came out. Do not retry with different
arguments and do not work around it.
