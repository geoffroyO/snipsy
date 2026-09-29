"""Hook for Claude Code and Codex (SessionStart / UserPromptSubmit / SessionEnd).

Both agents use the same hook protocol. Registers the session so the Snipsy app can
target it, starts server.py if needed, and on each prompt hands this session its pending
screenshots (for Claude Code sessions started with the Snipsy channel, channel.py
delivers them instantly instead).
"""
import json, os, pathlib, re, signal, socket, subprocess, sys, time

sys.dont_write_bytecode = True  # importing server.py below must not leave __pycache__ around
from server import VERSION  # noqa: E402

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
        items = sorted((p for p in dest.iterdir() if p.stem.isdigit()), key=lambda p: int(p.stem))
        lines = ["The user sent this from their screen with Snipsy."]
        shots = [str(p) for p in items if p.suffix == ".png"]
        if shots:
            lines += [f"Screenshots, open them with {VIEW_TOOL.get(agent, 'your image tool')}:", *shots]
        for text in (p for p in items if p.suffix == ".txt"):
            lines += [f"Copied text ({text.name}):", "```", text.read_text(), "```"]
        msgs.append("\n".join(lines) + "\nTheir comment:\n" + (dest / "comment.txt").read_text())
    return msgs


def session_title(ev, agent, sid):
    """The title the agent shows for this session, or None if it has none yet.

    Claude Code appends `custom-title` (/rename) and `ai-title` records to the transcript;
    Codex keeps `thread_name` in $CODEX_HOME/session_index.jsonl.
    """
    if agent == "codex":
        index = pathlib.Path(os.environ.get("CODEX_HOME", pathlib.Path.home() / ".codex")) / "session_index.jsonl"
        title = None
        try:
            with index.open() as f:
                for line in f:  # small file; the last entry for the session wins
                    if sid in line:
                        title = json.loads(line).get("thread_name") or title
        except (OSError, ValueError):
            pass
        return title

    path = ev.get("transcript_path")
    if not path:
        return None
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - 2_000_000))  # titles are re-appended often: the tail is enough
            lines = f.read().decode(errors="ignore").splitlines()
    except OSError:
        return None
    keys = {"custom-title": "customTitle", "ai-title": "aiTitle"}
    found = {}
    for line in reversed(lines):
        if "-title" not in line:  # cheap filter before parsing
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        kind = record.get("type")
        if kind in keys and kind not in found:
            found[kind] = record.get(keys[kind])
        if "custom-title" in found:
            break
    return found.get("custom-title") or found.get("ai-title")


def readable(prompt):
    """A user prompt worth showing as a label, or None (Snipsy deliveries, markup, IDs/keys...)."""
    text = " ".join(re.sub(r"<[^>]+>", " ", prompt).split())
    if not text or text.startswith("The user sent") or "channel source=" in prompt:
        return None
    words = text.split()
    if len(words) < 3 and any(len(w) > 24 for w in words):  # a lone hash, token or path
        return None
    return text[:80]


def running_bridge():
    """(pid, version) of the bridge listening on PORT, or None if the port is free."""
    try:
        socket.create_connection(("127.0.0.1", PORT), 0.2).close()
    except OSError:
        return None
    try:
        info = json.loads((BASE / "server.json").read_text())
        return info["pid"], info["version"]
    except (OSError, ValueError, KeyError):  # bridges before 1.5 didn't record themselves
        pids = subprocess.run(["lsof", "-ti", f"tcp:{PORT}", "-sTCP:LISTEN"], capture_output=True, text=True).stdout.split()
        return (int(pids[0]) if pids else None), "0"


def ensure_server():
    """Start the bridge, or replace a running one that's older than this plugin (never newer)."""
    running = running_bridge()
    if running:
        pid, version = running
        older = tuple(map(int, version.split("."))) < tuple(map(int, VERSION.split(".")))
        args = subprocess.run(["ps", "-o", "args=", "-p", str(pid)], capture_output=True, text=True).stdout if pid else ""
        if not older or "server.py" not in args:  # up to date, or not our bridge: leave it
            return
        os.kill(pid, signal.SIGTERM)
        for _ in range(40):  # wait for the port to be released
            if running_bridge() is None:
                break
            time.sleep(0.05)
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
    # Label shown in the app: the session's own title, else the last readable prompt.
    title = session_title(ev, agent, sid)
    if title:
        s["prompt"] = title[:80]
    elif name == "UserPromptSubmit":
        s["prompt"] = readable(ev.get("prompt", "")) or s["prompt"]
    reg.parent.mkdir(parents=True, exist_ok=True)
    reg.write_text(json.dumps(s))

    if name == "UserPromptSubmit":
        print("\n\n".join(take(sid, agent)))
