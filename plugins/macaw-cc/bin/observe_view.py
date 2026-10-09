#!/usr/bin/env python3
"""Report what a coding agent did: session -> prompt -> tool, with what it cost.

  macaw-sidecar --view                 today
  macaw-sidecar --view --all           every day on file
  macaw-sidecar --view <file.jsonl>

Input is the JSONL the MACAW hooks write locally, one line per event.

Attribution is read, never guessed. Claude Code stamps prompt_id on
UserPromptSubmit, PreToolUse and PostToolUse; Codex stamps turn_id on the same
three. A tool call belongs to the prompt named in its own payload.

Cost is not in those payloads. The harness keeps its own transcript and writes
one accounting record there - dollars, tokens per model, lines added and
removed - and every hook payload carries that transcript's path. This opens it
while rendering, reads that single record, and closes it.

Nothing from the transcript is written back. The log on disk stays a record of
what the agent did; it never becomes a copy of the conversation. A session with
no transcript, or one still running, is reported without the cost column rather
than not reported at all.

Dollar figures come from the harness, which computes them from token counts and
its own price list. They are an estimate of what the work would cost at API
rates, not a billing record, and a subscription is not billed this way. When
the harness reports that it could not price a model, the total is marked as a
floor.
"""
import glob
import json
import os
import sys
from collections import OrderedDict

LOG_DIR = os.environ.get("MACAW_OBSERVE_DIR",
                         os.path.expanduser("~/.macaw/logs"))

DIM, BOLD, RESET = "\033[2m", "\033[1m", "\033[0m"
RED, YEL, CYA = "\033[31m", "\033[33m", "\033[36m"
if not sys.stdout.isatty():
    DIM = BOLD = RESET = RED = YEL = CYA = ""


def load(paths):
    """Every record, in file order, skipping anything unparseable."""
    for path in paths:
        try:
            with open(path) as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        yield json.loads(line)
                    except ValueError:
                        continue
        except OSError:
            continue


def turn_of(rec):
    """Both harnesses name the turn; they just use different words for it."""
    return rec.get("prompt_id") or rec.get("turn_id") or "-"


def summarise(params, cwd=None):
    """One line for a tool call. Prefer the field a human would have typed.

    Paths are shown relative to the session's directory. An absolute path to
    somewhere inside the workspace is noise, and it is long enough to push the
    part that matters off the line - but a path OUTSIDE the workspace stays
    absolute, because that is exactly the thing worth noticing.
    """
    if not isinstance(params, dict):
        return str(params)[:100]
    for key in ("command", "file_path", "path", "pattern", "url", "prompt"):
        val = params.get(key)
        if not val:
            continue
        text = " ".join(str(val).split())
        if cwd and text.startswith(cwd + os.sep):
            text = text[len(cwd) + 1:]
        return text[:100]
    return " ".join(json.dumps(params).split())[:100]


def build(records):
    """sessions[sid] = {cwd, turns: {tid: {prompt, tools: [...]}}}"""
    sessions = OrderedDict()
    outcomes = {}        # tool_use_id -> (ok, ms)

    for rec in records:
        sid = rec.get("session_id") or "unknown"
        s = sessions.setdefault(sid, {"cwd": None, "first": None, "last": None,
                                      "transcript": None, "turns": OrderedDict()})
        if rec.get("cwd") and not s["cwd"]:
            s["cwd"] = rec["cwd"]
        if rec.get("transcript_path") and not s["transcript"]:
            s["transcript"] = rec["transcript_path"]

        event = rec.get("hook_event_name", "")
        tid = turn_of(rec)
        t = s["turns"].setdefault(tid, {"prompt": None, "tools": []})

        ts = rec.get("ts", "")
        if ts:
            # setdefault would not replace the None the session starts with.
            if not s["first"]:
                s["first"] = ts
            s["last"] = ts

        if event == "UserPromptSubmit":
            t["prompt"] = " ".join((rec.get("prompt") or "").split())
        elif event == "PreToolUse":
            t["tools"].append({
                "id": rec.get("tool_use_id"),
                "name": rec.get("tool_name", "?"),
                "params": rec.get("tool_input"),
                "ts": rec.get("ts", ""),
            })
        elif event == "PostToolUse":
            resp = rec.get("tool_response") or {}
            ok = not (isinstance(resp, dict) and
                      (resp.get("interrupted") or resp.get("is_error")))
            outcomes[rec.get("tool_use_id")] = (ok, rec.get("duration_ms"))

    return sessions, outcomes


def clock(ts):
    """2026-10-05T23:35:13Z -> 23:35:13"""
    return ts[11:19] if len(ts) >= 19 else ""


def thousands(n):
    """147 -> 147, 32076 -> 32.1K, 1420000 -> 1.4M"""
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return f"{n / 1000:.1f}K".replace(".0K", "K")
    return f"{n / 1_000_000:.1f}M".replace(".0M", "M")


def read_cost(path):
    """The harness's accounting record for one session, or None.

    Written at session end, so a session still running has none.
    """
    if not path:
        return None
    try:
        with open(path) as fh:
            state = None
            for line in fh:
                if '"cost-state"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("type") == "cost-state":
                    state = rec     # last one wins
    except OSError:
        return None
    if not state:
        return None

    out = think = 0
    for usage in (state.get("modelUsage") or {}).values():
        out += usage.get("outputTokens", 0)
        think += usage.get("thinkingTokens", 0)
    return {
        "usd": state.get("totalCostUSD") or 0.0,
        # The harness sets this when it has no price for a model it saw, which
        # makes the total a floor rather than a figure. Shown as 0.28+.
        "partial": bool(state.get("hasUnknownModelCost")),
        "out": out,
        "think": think,
        "added": state.get("totalLinesAdded") or 0,
        "removed": state.get("totalLinesRemoved") or 0,
    }


def cost_line(c):
    """est $0.10 · 147 out · +12/-3

    Labelled on every line, not once at the top: a single session gets read,
    quoted and screenshotted on its own.
    """
    if not c:
        return ""
    money = f"est ${c['usd']:.2f}" if c["usd"] >= 0.005 else "est <$0.01"
    if c.get("partial"):
        money += "+"
    bits = [money, f"{thousands(c['out'])} out"]
    if c["added"] or c["removed"]:
        bits.append(f"+{c['added']}/-{c['removed']}")
    return "  ·  ".join(bits)


HARNESS = "claude"


# What the two tiers look like from here. Printed by this renderer rather than
# left to the model that invoked it, so it says the same thing every time and
# names a command that exists on this harness.
# Codex has no plugin slash commands, so naming one would be naming something
# that does not exist. Asking is how its skills are reached, and macaw-protect
# does the same walkthrough from inside the session; the bare command is kept
# as the version that works whether or not the skill is matched.
UPGRADE = {
    "claude": [
        "/macaw-cc:protect  uses policies to block and ask for approvals",
        "(in MACAW console). First run spins up your workspace.",
    ],
    "codex": [
        "Ask to turn on blocking: uses policies to block and ask for approvals",
        "(in MACAW console). First run spins up your workspace.",
        "Or run: npx macaw-ai install",
    ],
}


def sidecar_running(port=18820):
    """A sidecar answering means policy is already being applied."""
    import urllib.request
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1)
        return True
    except Exception:
        return False


def footer(tools):
    """One line of counts, then what to do about them."""
    from collections import Counter

    SHELL = {"Bash", "shell", "exec", "apply_patch"}
    WRITE = {"Write", "Edit", "NotebookEdit", "MultiEdit", "apply_patch"}
    NET   = {"WebFetch", "WebSearch", "Fetch"}

    kinds = Counter()
    for name in (t["name"] for t in tools):
        if name in SHELL:   kinds["shell"] += 1
        elif name in WRITE: kinds["write"] += 1
        elif name in NET:   kinds["network"] += 1
        else:               kinds["read"] += 1

    if kinds:
        # "1 writes" reads as a typo in a line whose whole job is to be
        # believed. shell and network are already right either way.
        plural = {"read": "reads", "write": "writes"}
        parts = ", ".join(f"{n} {plural.get(k, k) if n != 1 else k}"
                          for k, n in kinds.most_common())
        n = len(tools)
        print(f"{DIM}{n} tool call{'' if n == 1 else 's'} - {parts}{RESET}")

    if sidecar_running():
        print(f"{DIM}Protecting. Approvals go to your MACAW console.{RESET}\n")
        return

    for line in UPGRADE[HARNESS]:
        print(f"{DIM}{line}{RESET}")
    print()

def render(sessions, outcomes):
    shown = [(sid, s) for sid, s in sessions.items()
             if any(t["prompt"] or t["tools"] for t in s["turns"].values())]
    if not shown:
        print("Nothing observed yet. Run a session with the macaw plugin "
              "installed and no sidecar running.")
        return

    # The console leads with totals; so does this, in one line rather than a row
    # of cards.
    n_turns = sum(len([t for t in s["turns"].values() if t["prompt"] or t["tools"]])
                  for _, s in shown)
    n_tools = sum(len(t["tools"]) for _, s in shown for t in s["turns"].values())
    n_fail = sum(1 for ok, _ in outcomes.values() if ok is False)
    fails = f", {RED}{n_fail} failed{RESET}" if n_fail else ""

    costs = {sid: read_cost(s["transcript"]) for sid, s in shown}
    have = [c for c in costs.values() if c]
    total = ""
    if have:
        total = "  " + cost_line({
            "usd":     sum(c["usd"] for c in have),
            "partial": any(c.get("partial") for c in have),
            "out":     sum(c["out"] for c in have),
            "think":   sum(c["think"] for c in have),
            "added":   sum(c["added"] for c in have),
            "removed": sum(c["removed"] for c in have),
        })
    print(f"\n{BOLD}{len(shown)} session(s){RESET}  {DIM}{n_turns} prompts, "
          f"{n_tools} tool calls{RESET}{fails}{DIM}{total}{RESET}")

    for sid, s in shown:
        turns = [t for t in s["turns"].values() if t["prompt"] or t["tools"]]
        tools = [tool for t in turns for tool in t["tools"]]
        ok_n = sum(1 for tl in tools if outcomes.get(tl["id"], (None,))[0] is True)
        bad_n = sum(1 for tl in tools if outcomes.get(tl["id"], (None,))[0] is False)
        span = ""
        if s["first"]:
            span = f"{clock(s['first'])} → {clock(s['last'])}"
        tally = f"{len(tools)} tools"
        if ok_n or bad_n:
            tally += f" ({ok_n}✓" + (f" {bad_n}✗" if bad_n else "") + ")"

        money = cost_line(costs.get(sid))
        print(f"\n{BOLD}{sid[:8]}{RESET}  {DIM}{span}   "
              f"{len(turns)} prompts  {tally}"
              + (f"  ·  {money}" if money else "") + RESET)
        if s["cwd"]:
            print(f"  {DIM}{s['cwd']}{RESET}")

        for t in turns:
            prompt = t["prompt"] or f"{DIM}(prompt not recorded){RESET}"
            print(f"\n  {CYA}▸{RESET} {prompt[:110]}")
            for tool in t["tools"]:
                ok, ms = outcomes.get(tool["id"], (None, None))
                mark = " " if ok is None else ("✓" if ok else f"{RED}✗{RESET}")
                took = f" {DIM}{ms}ms{RESET}" if ms else ""
                summary = summarise(tool["params"], s["cwd"])
                print(f"  {DIM}{clock(tool['ts'])}{RESET} {mark} "
                      f"{BOLD}{tool['name']}{RESET}  {summary}{took}")
    print()
    footer([tool for _, s in shown
            for t in s["turns"].values() for tool in t["tools"]])


def main(argv):
    args = [a for a in argv if not a.startswith("-")]
    if args:
        paths = args
    elif "--all" in argv:
        paths = sorted(glob.glob(os.path.join(LOG_DIR, "observe-*.jsonl")))
    else:
        today = os.path.join(LOG_DIR, "observe-*.jsonl")
        paths = sorted(glob.glob(today))[-1:]

    if not paths:
        print(f"No observation logs in {LOG_DIR}.")
        return 1

    sessions, outcomes = build(load(paths))
    render(sessions, outcomes)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
