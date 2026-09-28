"""Hook for Claude Code and Codex (SessionStart / UserPromptSubmit / SessionEnd).

Both agents use the same hook protocol. Registers the session so the Snipsy app can
target it, starts server.py if needed, and on each prompt hands this session its pending
screenshots (for Claude Code sessions started with the Snipsy channel, channel.py
delivers them instantly instead).
"""
import json, os, pathlib, re, socket, subprocess, sys, time

BASE = pathlib.Path.home() / ".snipsy"
PORT = int(os.environ.get("SNIPSY_PORT", 7823))  # overridable for tests
CHANNEL_FLAG = "--dangerously-load-development-channels"
AGENTS = ("claude", "codex")
# How each agent should open the images we hand it.
VIEW_TOOL = {"claude": "the Read tool", "codex": "the view_image tool"}


def agent_proc():
    """(pid, name, args) of the coding agent (Claude Code or Codex) we run under.

    The name comes from the process tree when possible. Otherwise (desktop apps, whose
    binaries may be named differently) from the environment: only Codex sets PLUGIN_ROOT.
    """
    fallback = "codex" if "PLUGIN_ROOT" in os.environ else "claude"
    pid = os.getppid()
    while pid > 1:
        # args, not comm: ps truncates comm to 16 chars when claude is launched by full path
        out = subprocess.run(["ps", "-o", "ppid=,args=", "-p", str(pid)], capture_output=True, text=True).stdout.split(None, 1)
        if len(out) < 2:
            break
        name = os.path.basename(out[1].split()[0])
        if name in AGENTS:
            return pid, name, out[1]
        pid = int(out[0])
    return None, fallback, ""


def has_channel(args):
    return CHANNEL_FLAG in args and "plugin:snipsy@" in args


def take(sid, agent="claude"):
    """Move this session's pending sends to done/ and return one message per send."""
    inbox = BASE / "inbox" / sid
    msgs = []
    for d in sorted(p for p in inbox.glob("*") if p.is_dir() and p.name != "done"):
        dest = inbox / "done" / d.name
        dest.parent.mkdir(exist_ok=True)
        try:
            d.rename(dest)  # atomic: hook and channel can race safely
        except FileNotFoundError:  # the channel (or another hook run) took it first
            continue
        shots = sorted(dest.glob("*.png"), key=lambda p: int(p.stem))
        msgs.append(
            f"The user sent screenshots from their screen with Snipsy. Open them with {VIEW_TOOL.get(agent, 'your image tool')}:\n"
            + "\n".join(str(p) for p in shots)
            + "\nTheir comment:\n" + (dest / "comment.txt").read_text()
        )
    return msgs


def ensure_server():
    try:
        socket.create_connection(("127.0.0.1", PORT), 0.2).close()
    except OSError:
        subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name("server.py"))],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    ev = json.load(sys.stdin)
    sid, name = ev["session_id"], ev["hook_event_name"]
    reg = BASE / "sessions" / f"{sid}.json"

    if name == "SessionEnd":
        reg.unlink(missing_ok=True)
        sys.exit()

    ensure_server()
    s = json.loads(reg.read_text()) if reg.exists() else {"id": sid, "prompt": ""}
    pid, agent, args = agent_proc()
    s.update(cwd=ev.get("cwd", s.get("cwd", "")), ts=time.time(), pid=pid, agent=agent,
             channel=agent == "claude" and has_channel(args))
    if name == "UserPromptSubmit":
        prompt = re.sub(r"<[^>]+>", " ", ev.get("prompt", ""))  # drop markup like <pasted_content …>
        s["prompt"] = " ".join(prompt.split())[:80]
    reg.parent.mkdir(parents=True, exist_ok=True)
    reg.write_text(json.dumps(s))

    if name == "UserPromptSubmit":
        print("\n\n".join(take(sid, agent)))
