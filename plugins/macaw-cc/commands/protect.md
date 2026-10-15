---
description: Get approvals or block risky calls. Free. One click to set up an account.
allowed-tools: Bash(command:*), Bash(npm:*), Bash(macaw-sidecar:*), Bash(mkdir:*), Bash(cat:*), Bash(grep:*), Bash(sleep:*)
---

Move from tracking to getting approvals. Four steps, and stop between them.

**1 — is it already here?**

```bash
if command -v macaw-sidecar >/dev/null; then macaw-sidecar status --json; else echo '{"installed": false}'; fi
```

- **`"running": true`** - it is already protecting. Say so and stop.
- **`"running": false`** - installed but not running. Say `macaw-sidecar start`
  and stop.
- **`"installed": false`** - nothing here. Go on.
- **Not JSON** (help text) - an older version is installed. Go on; the install
  updates it.

Note whether `"config"` names a file: that is an existing MACAW workspace, and
step 3 depends on it.

**2 — say what will happen, then ask**

Print exactly this and wait for an answer. Do not run anything yet.

```
Right now MACAW tracks. This lets it stop things.

Policies decide what needs approval. Those calls wait, and you
approve them in the MACAW console - not in the terminal, where
your agent could reach them.

Free. The first install creates your workspace: a link appears
here, you click it, that's the account.

Where?
  S) every directory, for you - runs as a service, starts at login (default)
  L) this project only
```

If step 1 found a workspace, add: "Your existing workspace is reused - no sign-in
link this time."

**3 — start it, and relay the link**

Only after they answer. `S` or an empty answer is `--system`; `L` is `--local`.
Add `--activate` **only if step 1 found no workspace**: it creates a new one,
ignoring any key already there.

```bash
npm install -g @macaw-ai/coding-agents >/dev/null 2>&1
mkdir -p ~/.macaw && macaw-sidecar install --system --activate > ~/.macaw/install.log 2>&1 &
```

It runs detached so its output can be read while it waits. With `--activate`,
read `~/.macaw/install.log` every few seconds until a line with a URL appears,
for up to a minute, then relay that URL and the code beside it plainly and say
you are waiting.

Do not open the URL, fetch it, or try to approve it yourself. Approval
happening somewhere this session cannot reach is the whole point of it.

**4 — wait for it to finish**

Keep reading the log until it says `Installed` or prints a failure, checking
every ten seconds or so for up to ten minutes. With a sign-in link it sits on
`Waiting for approval...` until they have clicked through; that is expected.

When it finishes, report the workspace name it printed, then:

- **`--system`** - nothing else to do: run `claude` as usual, in any directory.
- **`--local`** - start the agent with `secCC` in this directory. It starts the
  sidecar if it is not running; the hooks block every call when it is not.

This plugin can stay on: it only records. To stop the duplicate local record,
disable it with `/plugin`.

If it fails, show the error as it came out. Do not retry with different
arguments and do not work around it.
