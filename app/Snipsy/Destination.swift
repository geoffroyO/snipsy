import Foundation

/// Where the screenshots go.
enum Destination: Hashable, Identifiable {
    /// A Claude Code or Codex session: delivered through the plugin, with the comment.
    case session(Session)
    /// The clipboard, to paste into any chat (ChatGPT, Claude, Slack…).
    case clipboard

    /// Stable key, persisted to reselect the last destination.
    var id: String {
        switch self {
        case .session(let session): "session:\(session.id)"
        case .clipboard: "clipboard"
        }
    }

    var actionTitle: String {
        switch self {
        case .session: "Send"
        case .clipboard: "Copy"
        }
    }
}
