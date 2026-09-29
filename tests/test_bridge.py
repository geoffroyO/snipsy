"""End-to-end tests for the plugin bridge (server.py + hook.py), standard library only.

    python3 -m unittest discover tests

Runs a real server on a spare port with a throwaway HOME, so it never touches ~/.snipsy.
"""
import base64, json, os, pathlib, socket, subprocess, sys, tempfile, time, unittest, urllib.error, urllib.request

BRIDGE = pathlib.Path(__file__).resolve().parent.parent / "plugin/bridge"
PNG = base64.b64encode(bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a4c80000000049454e44ae426082"
)).decode()


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class BridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = tempfile.TemporaryDirectory()
        cls.port = free_port()
        cls.env = {**os.environ, "HOME": cls.home.name, "SNIPSY_PORT": str(cls.port), "PYTHONDONTWRITEBYTECODE": "1"}
        cls.server = subprocess.Popen([sys.executable, BRIDGE / "server.py"], env=cls.env)
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", cls.port), 0.1).close()
                break
            except OSError:
                time.sleep(0.05)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait()
        cls.home.cleanup()

    def request(self, path, body=None, headers=None):
        headers = {"X-Snipsy": "1", **(headers or {})}
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data, headers=headers)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            e.close()
            return e.code, None

    def hook(self, event, session, **fields):
        payload = {"hook_event_name": event, "session_id": session, "cwd": "/tmp/demo", **fields}
        out = subprocess.run([sys.executable, BRIDGE / "hook.py"], input=json.dumps(payload),
                             capture_output=True, text=True, env=self.env, check=True)
        return out.stdout

    def test_only_the_app_is_allowed(self):
        self.assertEqual(self.request("/sessions", headers={"X-Snipsy": ""})[0], 403)
        self.assertEqual(self.request("/sessions", headers={"Origin": "https://evil.example"})[0], 403)
        self.assertEqual(self.request("/sessions", headers={"Origin": "chrome-extension://x"})[0], 403)
        self.assertEqual(self.request("/sessions")[0], 200)

    def test_bad_requests(self):
        self.assertEqual(self.request("/send", {"session": "../etc", "shots": [{"png": PNG}]})[0], 400)
        self.assertEqual(self.request("/send", {"session": "s", "shots": [{"png": "not base64!"}]})[0], 400)
        self.assertEqual(self.request("/clip", {"shots": []})[0], 400)

    def test_send_then_deliver_on_next_prompt(self):
        self.hook("SessionStart", "s1")
        sessions = {s["id"]: s for s in self.request("/sessions")[1]}
        self.assertIn("s1", sessions)

        status, _ = self.request("/send", {"session": "s1", "comment": "fix this",
                                           "shots": [{"png": PNG, "app": "Safari"}, {"png": PNG, "app": "Figma"}]})
        self.assertEqual(status, 200)

        delivered = self.hook("UserPromptSubmit", "s1", prompt="<pasted_content id=x> hello")
        self.assertIn("fix this", delivered)
        self.assertIn("From Safari: 1.png", delivered)
        self.assertIn("From Figma: 2.png", delivered)
        files = [line for line in delivered.splitlines() if line.startswith("/")]
        self.assertEqual(len(files), 2)
        self.assertTrue(all(pathlib.Path(f).is_file() for f in files))
        self.assertEqual(self.hook("UserPromptSubmit", "s1", prompt="again").strip(), "")  # delivered once

        sessions = {s["id"]: s for s in self.request("/sessions")[1]}
        self.assertEqual(sessions["s1"]["prompt"], "again")

        self.hook("SessionEnd", "s1")
        self.assertNotIn("s1", {s["id"] for s in self.request("/sessions")[1]})

    def test_codex_sessions_get_codex_instructions(self):
        # Run the hook under a parent process named "codex", like the Codex CLI or the ChatGPT app.
        payload = {"hook_event_name": "UserPromptSubmit", "session_id": "c1", "cwd": "/tmp", "prompt": "hi"}
        command = f'"{sys.executable}" "{BRIDGE / "hook.py"}"; exit $?'  # not a lone command, so bash won't exec it
        run = lambda: subprocess.run(["codex", "-c", command], executable="/bin/bash", input=json.dumps(payload),
                                     capture_output=True, text=True, env=self.env, check=True).stdout
        run()
        self.request("/send", {"session": "c1", "comment": "", "shots": [{"png": PNG}]})
        self.assertIn("view_image", run())
        registered = json.loads(pathlib.Path(self.home.name, ".snipsy/sessions/c1.json").read_text())
        self.assertEqual(registered["agent"], "codex")

    def registered(self, sid):
        return json.loads(pathlib.Path(self.home.name, f".snipsy/sessions/{sid}.json").read_text())

    def test_label_is_the_claude_session_title(self):
        transcript = pathlib.Path(self.home.name, "t1.jsonl")
        transcript.write_text("\n".join([
            json.dumps({"type": "user", "message": "hi"}),
            json.dumps({"type": "ai-title", "aiTitle": "Fix the landing page"}),
        ]) + "\n")
        self.hook("UserPromptSubmit", "t1", prompt="a4ba493cdd5e765a3f0015fdf8e2c1b7d4", transcript_path=str(transcript))
        self.assertEqual(self.registered("t1")["prompt"], "Fix the landing page")
        with transcript.open("a") as f:  # /rename wins over the automatic title
            f.write(json.dumps({"type": "custom-title", "customTitle": "landing"}) + "\n")
        self.hook("UserPromptSubmit", "t1", prompt="again", transcript_path=str(transcript))
        self.assertEqual(self.registered("t1")["prompt"], "landing")

    def test_label_is_the_codex_thread_name(self):
        codex_home = pathlib.Path(self.home.name, "codex-home")
        codex_home.mkdir(exist_ok=True)
        (codex_home / "session_index.jsonl").write_text(json.dumps({"id": "x9", "thread_name": "Compare prices"}) + "\n")
        payload = {"hook_event_name": "SessionStart", "session_id": "x9", "cwd": "/tmp"}
        command = f'"{sys.executable}" "{BRIDGE / "hook.py"}"; exit $?'
        subprocess.run(["codex", "-c", command], executable="/bin/bash", input=json.dumps(payload), text=True,
                       capture_output=True, env={**self.env, "CODEX_HOME": str(codex_home)}, check=True)
        self.assertEqual(self.registered("x9")["prompt"], "Compare prices")

    def test_unreadable_prompts_keep_the_previous_label(self):
        self.hook("UserPromptSubmit", "u1", prompt="fix the navbar on mobile")
        for junk in ["The user sent screenshots from their screen with Snipsy.", "a4ba493cdd5e765a3f0015fdf8e2c1b7d4"]:
            self.hook("UserPromptSubmit", "u1", prompt=junk)
        self.assertEqual(self.registered("u1")["prompt"], "fix the navbar on mobile")

    def test_dead_sessions_are_pruned(self):
        sessions = pathlib.Path(self.home.name, ".snipsy/sessions")
        sessions.mkdir(parents=True, exist_ok=True)
        (sessions / "ghost.json").write_text(json.dumps({"id": "ghost", "prompt": "", "cwd": "/", "ts": time.time(), "pid": 2**22 + 7}))
        self.assertNotIn("ghost", {s["id"] for s in self.request("/sessions")[1]})

    def test_clip_returns_readable_files(self):
        status, body = self.request("/clip", {"shots": [{"png": PNG}, {"png": PNG}]})
        self.assertEqual(status, 200)
        self.assertEqual(len(body["paths"]), 2)
        for path in body["paths"]:
            self.assertEqual(pathlib.Path(path).read_bytes(), base64.b64decode(PNG))


if __name__ == "__main__":
    unittest.main()
