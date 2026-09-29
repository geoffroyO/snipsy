"""Local bridge between the Snipsy menu bar app and Claude Code / Codex sessions.

GET  /sessions -> sessions registered by hook.py
POST /send     -> {"session", "comment", "shots": [{"png": <base64> | "text": <str>, "app": <source app>}]}
                  written to ~/.snipsy/inbox/<session>/<id>/ as N.png / N.txt
POST /clip     -> {"shots": [...]} saved to ~/.snipsy/clips/<id>/, returns their paths so the
                  app can put them on the clipboard (terminals paste text, not images)

Only the native app can talk to it: requests must carry the X-Snipsy header and no
Origin. Web pages always send an Origin, and can't add custom headers cross-origin.
"""
import base64, http.server, json, os, pathlib, re, shutil, time

PORT = int(os.environ.get("SNIPSY_PORT", 7823))  # overridable for tests
BASE = pathlib.Path.home() / ".snipsy"
STALE = 3 * 86400  # safety net for sessions whose process we couldn't identify
CLIP_TTL = 7 * 86400  # clipboard screenshots are kept a week
MAX_TEXT = 200_000  # characters per copied text


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def decode(shot):
    """A screenshot's PNG bytes, or a copied text; raises ValueError if it's neither."""
    if isinstance(shot.get("png"), str):
        return base64.b64decode(shot["png"], validate=True)
    if isinstance(shot.get("text"), str) and 0 < len(shot["text"]) <= MAX_TEXT:
        return shot["text"]
    raise ValueError


class Handler(http.server.BaseHTTPRequestHandler):
    def allowed(self):
        return (
            self.headers.get("Host") == f"127.0.0.1:{PORT}"
            and self.headers.get("X-Snipsy") == "1"
            and "Origin" not in self.headers
        )

    def reply(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.allowed() or self.path != "/sessions":
            return self.reply(403, {"error": "forbidden"})
        sessions = []
        for f in (BASE / "sessions").glob("*.json"):
            s = json.loads(f.read_text())
            if time.time() - s["ts"] > STALE or (s.get("pid") and not alive(s["pid"])):
                f.unlink(missing_ok=True)  # agent quit or crashed without SessionEnd
            else:
                sessions.append(s)
        self.reply(200, sorted(sessions, key=lambda s: -s["ts"]))

    def do_POST(self):
        if not self.allowed() or self.path not in ("/send", "/clip"):
            return self.reply(403, {"error": "forbidden"})
        try:
            d = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            shots = d["shots"]
            if not shots:
                raise ValueError
            items = [decode(s) for s in shots]  # bytes (screenshot) or str (copied text)
            if self.path == "/clip":
                if not all(isinstance(i, bytes) for i in items):
                    raise ValueError
                return self.clip(items)
            session, comment = d["session"], d.get("comment", "")
            if not re.fullmatch(r"[\w-]+", session):
                raise ValueError
        except (KeyError, TypeError, ValueError):
            return self.reply(400, {"error": "bad request"})

        dest = BASE / "inbox" / session / time.strftime("%Y%m%d-%H%M%S")
        dest.mkdir(parents=True, exist_ok=True)
        apps = {}  # source app -> file names
        for i, (shot, item) in enumerate(zip(shots, items), 1):
            name = f"{i}.png" if isinstance(item, bytes) else f"{i}.txt"
            if isinstance(item, bytes):
                (dest / name).write_bytes(item)
            else:
                (dest / name).write_text(item)
            apps.setdefault(shot.get("app") or "screen", []).append(name)
        sources = "\n".join(f"From {app}: {', '.join(names)}" for app, names in apps.items())
        (dest / "comment.txt").write_text(comment.strip() + "\n\n" + sources + "\n")
        self.reply(200, {"ok": True})

    def clip(self, images):
        clips = BASE / "clips"
        for old in clips.glob("*"):
            if time.time() - old.stat().st_mtime > CLIP_TTL:
                shutil.rmtree(old, ignore_errors=True)
        dest = clips / time.strftime("%Y%m%d-%H%M%S")
        dest.mkdir(parents=True, exist_ok=True)
        paths = []
        for i, png in enumerate(images, 1):
            (dest / f"{i}.png").write_bytes(png)
            paths.append(str(dest / f"{i}.png"))
        self.reply(200, {"paths": paths})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
