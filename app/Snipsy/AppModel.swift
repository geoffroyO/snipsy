import AppKit
import Observation
import ServiceManagement

/// Something the user snipped: a screenshot, or text grabbed with ⌘C ⌘C.
struct Shot: Identifiable {
    let id = UUID()
    let app: String?
    var png: Data?
    var image: NSImage?
    var text: String?
}

enum PanelTab: Hashable {
    case snip, setup
}

enum BridgeState {
    case unknown, offline, online
}

enum Status: Equatable {
    case success(String), error(String)
}

@Observable
final class AppModel {
    var tab: PanelTab = .snip
    var shots: [Shot] = []
    var comment = ""
    var sessions: [Session] = []
    var bridge: BridgeState = .unknown
    var status: Status?
    var isSending = false
    var hasScreenPermission = ScreenCapture.hasPermission
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// `Destination.id` of the selected destination, persisted across launches.
    var destinationID: String? {
        didSet { UserDefaults.standard.set(destinationID, forKey: "destination") }
    }

    /// Called after a successful send (the app delegate closes the popover).
    @ObservationIgnored var onSent: (() -> Void)?
    /// Opens Sparkle's update check (set by the app delegate).
    @ObservationIgnored var checkForUpdates: (() -> Void)?

    init() {
        destinationID = UserDefaults.standard.string(forKey: "destination")
    }

    var destinations: [Destination] {
        sessions.map(Destination.session) + [.clipboard]
    }
    var destination: Destination? { destinations.first { $0.id == destinationID } }
    var canSend: Bool { !shots.isEmpty && destination != nil && !isSending }
    var needsSetup: Bool { !hasScreenPermission || bridge == .offline }

    func refresh() async {
        hasScreenPermission = ScreenCapture.hasPermission
        launchAtLogin = SMAppService.mainApp.status == .enabled
        do {
            sessions = try await Bridge.sessions()
            bridge = .online
        } catch {
            sessions = []
            bridge = .offline
        }
        if destination == nil { destinationID = destinations.first?.id }
    }

    func add(png: Data, app: String?) {
        guard let image = NSImage(data: png) else { return }
        shots.append(Shot(app: app, png: png, image: image))
        status = nil
    }

    func add(text: String, app: String?) {
        shots.append(Shot(app: app, text: text))
        status = nil
    }

    func remove(_ shot: Shot) {
        shots.removeAll { $0.id == shot.id }
    }

    func send() async {
        guard let destination, !shots.isEmpty else { return }
        switch destination {
        case .session(let session):
            isSending = true
            defer { isSending = false }
            do {
                try await Bridge.send(shots, comment: comment, to: session.id)
                comment = ""
                status = .success(session.isInstant ? "Sent! \(session.agent.title) is on it."
                                                    : "Sent! It arrives with your next message.")
            } catch {
                status = .error("Couldn't reach \(session.agent.title). Is the session still open?")
                await refresh()
                return
            }
        case .clipboard:
            // File paths need the bridge; without it we still copy the image and the prompt.
            let paths = (try? await Bridge.saveClip(shots)) ?? []
            Clipboard.copy(shots, prompt: comment, paths: paths)
            status = .success(paths.isEmpty ? "Copied image and prompt. Paste with ⌘V."
                                            : "Copied prompt, file paths and image. Paste with ⌘V.")
            comment = ""
        }
        shots = []
        onSent?()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = .error("Couldn't change the login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
