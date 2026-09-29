---
name: snipsy
description: Complete guide to Snipsy, the macOS menu bar app this plugin connects to. Use whenever the user asks what Snipsy is, whether it works on their system, how to install, set up, use, update or uninstall it, how screenshots reach Claude Code or Codex, how instant delivery works, where files are stored, or why Snipsy doesn't see their session, can't capture the screen, or screenshots don't arrive.
---

# Snipsy

Snipsy is a free, open-source **macOS menu bar app**. The user presses **⇧⌘2**, drags an area of their screen, writes a prompt, and sends it straight into a **Claude Code** or **Codex** session, or copies it to paste into any chat.

It has two parts, and **both are needed**:

| Part | What it does | How to get it |
|---|---|---|
| **Snipsy.app** | Captures the screen, lets the user pick a session and write a prompt | Download from GitHub (below) |
| **This plugin** | Registers sessions, runs a small local bridge, delivers the screenshots | `plugin install` (already done if you are reading this) |

Installing the plugin alone does nothing visible: **the user must also install the app.** Always tell them so when they ask how it works.

## Requirements

- **macOS 14 (Sonoma) or later. Snipsy is macOS only**: there is no Windows or Linux version of the app, and none is planned. On other systems, the closest alternative is pasting screenshots into the agent directly.
- **Python 3** for the bridge, from the Xcode command line tools (`xcode-select --install`) or Homebrew. Check with `python3 --version`.
- **Claude Code** (terminal, or the Claude desktop app's Code tab) and/or **Codex** (terminal, or the ChatGPT desktop app, which includes Codex).
- **Instant delivery** is optional and Claude Code only (see below).

## Install

1. **Download the app**: https://github.com/geoffroyO/snipsy/releases/latest → `Snipsy.dmg` → drag Snipsy to **Applications** → open it. A ✂️ appears in the menu bar and the *Setup* tab opens.
2. **Allow screen capture**: *Setup* → **Allow** → accept in System Settings → **Restart Snipsy** (macOS only applies the permission to a new launch).
3. **Install the plugin** for the agents they use:
   - Claude Code: `claude plugin marketplace add geoffroyO/snipsy && claude plugin install snipsy@snipsy`
   - Codex: `codex plugin marketplace add geoffroyO/snipsy && codex plugin add snipsy@snipsy`, then **approve Snipsy's hooks** once (Codex prompts for it, or run `/hooks` and trust them). Until they are approved, Codex sessions never appear.
4. **Start a new session.** Sessions that were already open when the plugin was installed don't load it.

The *Setup* tab is a live checklist: each step turns green once it works, and it shows how many Claude Code and Codex sessions are connected.

## How it works

```
Snipsy.app ──HTTP──▶ bridge/server.py (127.0.0.1:7823) ──▶ ~/.snipsy/inbox/<session>/
                                                             ├─▶ hook.py     delivers with the next prompt
                                                             └─▶ channel.py  delivers instantly (Claude Code ⚡)
```

- The plugin's **hooks** run at session start, on every prompt and at session end. They register the session in `~/.snipsy/sessions/` (project folder, last message, agent), start the bridge if needed, and hand the session any screenshots waiting for it.
- The **bridge** is a tiny Python HTTP server on `127.0.0.1:7823`. It lists sessions for the app and stores what the app sends. It only accepts the app: requests without its `X-Snipsy` header, or coming from a web page (with an `Origin`), are rejected.
- Sessions whose process has exited disappear from the list automatically.
- The same plugin serves both agents: Claude Code and Codex use the same hook protocol.

## Use

1. **⇧⌘2** anywhere (or click ✂️ → *+ area*). The screen freezes like macOS's own screenshot tool (open menus stay visible); drag the area, or press Esc to cancel.
2. Add more areas if needed, even from other apps. Remove one with its orange ✕.
   **Text too**: select text anywhere and press **⌘C ⌘C** (copy twice, quickly, like DeepL). It lands in the tray as a quote card next to the screenshots. Copying an image twice adds the image. The first time, macOS may ask to let Snipsy paste from other apps: allow it.
3. **Send to**: sessions are grouped by agent, orange **Claude Code** and dark **Codex**, each labeled with its project folder and last message. ⚡ marks instant delivery. The list refreshes live.
4. Write a prompt. **↵ sends**, **⌘↵** (or ⇧↵) inserts a new line.
5. Or choose **Clipboard**: Snipsy copies the prompt, the screenshots' file paths (for terminals, including Claude Code and Codex, which turn the paths into attached images) and the image itself (for chat apps like ChatGPT or Claude.ai). Paste with ⌘V.

Other: right-click ✂️ for a menu (Capture, Setup, Check for Updates, Quit); *Setup* has **Open at login**.

## Delivery

- **Default (Claude Code and Codex)**: screenshots arrive with the user's **next message** in that session. The hook appends them to the prompt; nothing is lost if the user waits.
- **Instant (Claude Code only, research preview)**: start Claude Code with
  ```
  claude --dangerously-load-development-channels plugin:snipsy@snipsy
  ```
  and confirm the warning at startup. Screenshots then arrive as soon as the user hits Send, without typing anything. This relies on Claude Code's experimental *channels*; the desktop app doesn't accept launch flags, so it can't use it.

**When a Snipsy delivery arrives in your session**, you get the screenshots' file paths, any copied text inline in code blocks, and the user's comment. Open every image (Claude Code: the Read tool; Codex: the view_image tool), read the copied text, then answer the comment as if the user had typed it.

## Update and uninstall

- **Update the plugin**: `claude plugin marketplace update snipsy && claude plugin update snipsy@snipsy` (Codex: `codex plugin remove snipsy@snipsy && codex plugin add snipsy@snipsy`), then start a new session.
- **Update the app**: automatic. Snipsy checks for updates itself (Sparkle) and offers to install them; to check now, right-click ✂️ → *Check for Updates…* or use the link at the bottom of *Setup*.
- **Uninstall**: quit Snipsy from its menu, delete it from Applications, `claude plugin uninstall snipsy@snipsy` / `codex plugin remove snipsy@snipsy`, and optionally `rm -rf ~/.snipsy`.

## Privacy

Screenshots never leave the Mac: the app sends them only to the bridge on 127.0.0.1. No analytics, no account. The only other network request is the update check against github.com (Sparkle, at most daily, with the user's consent, no system data sent). Screenshots are only taken of the area the user selects, stored in `~/.snipsy/inbox/` for their session, and clipboard copies are kept 7 days in `~/.snipsy/clips/`. What the agent does with an image afterwards follows that agent's own terms.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Plugin installed but nothing happens | The app isn't installed: download it (Install, step 1). |
| Session missing from *Send to* | Start a **new** session after installing the plugin. In the ChatGPT/Codex app, a session appears after its **first message**. |
| "Claude Code / Codex not connected" | No open session has the plugin: install it, start a session. Check the bridge: `curl -s -H 'X-Snipsy: 1' http://127.0.0.1:7823/sessions` should list sessions. |
| Codex sessions never appear | Snipsy's hooks aren't approved: run `/hooks` in Codex and trust them. |
| "Hook failed" messages in Codex | Usually another plugin's hooks; Snipsy's hooks print nothing except when delivering screenshots. |
| Screen capture not detected | System Settings → Privacy & Security → Screen Recording → enable Snipsy, then *Restart Snipsy*. |
| Screenshots never arrive | They come with the next message: send one. Or use instant delivery (Claude Code). |
| Bridge won't start | `python3 --version` must work; install the Xcode command line tools. Port 7823 must be free. |

## FAQ

- **Windows / Linux?** No, the app is macOS only.
- **Does it cost anything?** No, it's free and open source (MIT).
- **Which agents?** Claude Code and Codex, in the terminal or their desktop apps. Any other chat through Clipboard.
- **Is it made by Anthropic or OpenAI?** No, it's an independent project.

Source, issues and README: https://github.com/geoffroyO/snipsy
