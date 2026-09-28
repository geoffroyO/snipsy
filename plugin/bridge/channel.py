"""Claude Code channel: pushes Snipsy screenshots into the session instantly.

Registered by the plugin as MCP server "snipsy"; only active when Claude Code runs with
  claude --dangerously-load-development-channels plugin:snipsy@snipsy
Otherwise it stays idle (Claude Code would silently drop its events) and hook.py
delivers on the next prompt instead.
"""
import json, pathlib, sys, threading, time

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from hook import BASE, agent_proc, has_channel, take  # noqa: E402

lock = threading.Lock()


def send(msg):
    with lock:
        sys.stdout.write(json.dumps(msg) + "\n")
        sys.stdout.flush()


def poll(pid):
    while True:
        # Resolve our session each time: /clear starts a new session id in the same process.
        mine = [json.loads(f.read_text()) for f in (BASE / "sessions").glob("*.json")]
        mine = [s for s in mine if s.get("pid") == pid]
        if mine:
            for text in take(max(mine, key=lambda s: s["ts"])["id"]):
                send({"jsonrpc": "2.0", "method": "notifications/claude/channel", "params": {"content": text}})
        time.sleep(0.4)


pid, agent, args = agent_proc()
if pid and agent == "claude" and has_channel(args):
    threading.Thread(target=poll, args=(pid,), daemon=True).start()

for line in sys.stdin:
    req = json.loads(line)
    if "id" not in req:
        continue  # notifications (initialized, cancelled…)
    if req["method"] == "initialize":
        result = {
            "protocolVersion": req["params"]["protocolVersion"],
            "capabilities": {"experimental": {"claude/channel": {}}},
            "serverInfo": {"name": "snipsy", "version": "1.0.0"},
            "instructions": 'Events from <channel source="snipsy"> are the user sending screenshots '
                            "(file paths + a comment) from the Snipsy menu bar app. Treat each one like a "
                            "message from the user: read the images and answer the comment.",
        }
    elif req["method"] == "ping":
        result = {}
    else:
        send({"jsonrpc": "2.0", "id": req["id"], "error": {"code": -32601, "message": "method not found"}})
        continue
    send({"jsonrpc": "2.0", "id": req["id"], "result": result})
