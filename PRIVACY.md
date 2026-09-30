# Snipsy privacy policy

*Last updated: September 30, 2026*

Snipsy does not collect, store or share any personal data.

- **Screenshots and comments** are captured only when you select an area yourself. They are sent over a local connection (`127.0.0.1`) to the Snipsy bridge running on your own Mac, and written to `~/.snipsy/` so that your Claude Code or Codex session can read them. If you pick *Clipboard*, they are only copied to your clipboard. Snipsy never sends them anywhere else.
- **What happens next** is up to the tool you send it to (Claude Code, Codex, ChatGPT, Claude…), which handles it like any other file you share with it, under its own terms and privacy policy.
- **No analytics, no tracking, no accounts.**
- **Network**: besides the local bridge, Snipsy only contacts github.com to check for updates (about once an hour) and download them, using the open-source Sparkle framework. The request only fetches the list of available versions; no information about you or your Mac is sent.
- **Permissions**: Screen Recording, used only to capture the area you select.

Questions: open an issue on [github.com/geoffroyO/snipsy](https://github.com/geoffroyO/snipsy/issues).
