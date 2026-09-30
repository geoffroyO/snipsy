import AppKit
import SwiftUI

enum Links {
    static let repository = URL(string: "https://github.com/geoffroyO/snipsy")!
    static let marketplace = "geoffroyO/snipsy"
}

/// Checklist to get Snipsy talking to Claude Code and Codex, plus preferences.
struct SetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupStep(number: 1, title: "Allow screen capture", done: model.hasScreenPermission) {
                if model.hasScreenPermission {
                    Text("Granted. Snipsy only captures the area you select.")
                } else {
                    Text("macOS asks once. Snipsy only captures the area you select, and nothing leaves your Mac.")
                    HStack {
                        Button("Allow") { ScreenCapture.requestPermission() }
                        Button("Open Settings") { ScreenCapture.openSettings() }
                    }
                    .buttonStyle(CrayonButtonStyle(prominent: false))
                    HStack(spacing: 6) {
                        Text("Already allowed? macOS applies it after a restart.").foregroundStyle(Color.mute)
                        Button("Restart Snipsy") { NSApp.relaunch() }
                            .buttonStyle(.link)
                            .tint(.crayonBlue)
                    }
                }
            }

            SetupStep(number: 2, title: "Connect your coding agent", done: !model.sessions.isEmpty) {
                Text("Paste one command in your terminal, then start a new session.")
                AgentCard(agent: .claude, sessions: count(.claude),
                          command: "claude plugin marketplace add \(Links.marketplace) && claude plugin install snipsy@snipsy",
                          note: "Works in the terminal and in the Claude app's Code tab.")
                AgentCard(agent: .codex, sessions: count(.codex),
                          command: "codex plugin marketplace add \(Links.marketplace) && codex plugin add snipsy@snipsy",
                          note: "Works in the terminal and in the ChatGPT app. Codex asks you to approve Snipsy's hooks once (or run /hooks).")
            }

            Label {
                Text("**ChatGPT, Claude and other chats** need nothing: choose *Clipboard* and paste with ⌘V.")
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(Color.crayonBlue)
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)

            InstantDelivery(active: model.sessions.contains(where: \.isInstant))

            Divider().overlay(Color.pencil.opacity(0.3))

            Toggle("Open Snipsy at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))

            HStack {
                Link("GitHub", destination: Links.repository)
                Text("·").foregroundStyle(Color.mute)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .foregroundStyle(Color.mute)
                Text("·").foregroundStyle(Color.mute)
                Button("Check for updates") { model.checkForUpdates?() }
                    .buttonStyle(.link)
                Spacer()
                Button("Quit Snipsy") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.mute)
            }
            .font(.system(size: 11))
            .tint(.crayonBlue)
        }
    }

    private func count(_ agent: Agent) -> Int {
        model.sessions.filter { $0.agent == agent }.count
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.crayonGreen : Color.card)
                Circle().strokeBorder(done ? Color.crayonGreen : Color.pencil, lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityLabel(done ? "Done" : "Step \(number)")

            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.hand(16, bold: true))
                content
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One agent: status, and its install command (folded away once connected).
private struct AgentCard: View {
    let agent: Agent
    let sessions: Int
    let command: String
    let note: String
    @State private var expanded: Bool?

    private var isConnected: Bool { sessions > 0 }
    private var isExpanded: Bool { expanded ?? !isConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { expanded = !isExpanded } label: {
                HStack(spacing: 8) {
                    AgentTag(agent: agent)
                    Spacer()
                    if isConnected {
                        Label(sessions == 1 ? "1 session" : "\(sessions) sessions", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.crayonGreen)
                    } else {
                        Text("Not connected").foregroundStyle(Color.mute)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.mute)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .font(.system(size: 11, weight: .medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(agent.title): \(isConnected ? "connected" : "not connected")")

            if isExpanded {
                CommandRow(command: command)
                Text(note).font(.system(size: 11)).foregroundStyle(Color.mute)
            }
        }
        .padding(10)
        .background(Sketch(cornerRadius: 10, seed: Double(agent.title.count)).fill(Color.card.opacity(0.6)))
        .sketchBorder(isConnected ? agent.color.opacity(0.7) : .pencil.opacity(0.45), radius: 10,
                      width: 1.3, seed: Double(agent.title.count))
    }
}

/// Optional Claude Code channel: screenshots arrive without typing a message.
private struct InstantDelivery: View {
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(Color.crayonOrange)
                Text("Instant delivery").font(.hand(15, bold: true))
                AgentTag(agent: .claude, compact: true)
                Text("optional").font(.system(size: 11)).foregroundStyle(Color.mute)
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.crayonGreen)
                }
            }
            Text("Start Claude Code like this and it reacts as soon as you hit Send, without waiting for your next message:")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            CommandRow(command: "claude --dangerously-load-development-channels plugin:snipsy@snipsy")
        }
    }
}

private struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                DoubleCopyWatcher.ignoredChange = NSPasteboard.general.changeCount
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? Color.crayonGreen : Color.mute)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .card(radius: 8, seed: Double(command.count))
    }
}
