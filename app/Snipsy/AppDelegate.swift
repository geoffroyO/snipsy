import AppKit
import Carbon.HIToolbox
import Sparkle
import SwiftUI

/// Owns the menu bar item, the popover, the global shortcut and the capture flow.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var selector: ScreenSelector?
    /// ↑/↓ while the panel is open, whatever has focus in it.
    private var arrowKeys: Any?
    /// ⌘C ⌘C anywhere adds the copied text (or image) to the tray.
    private var doubleCopy: DoubleCopyWatcher?
    /// Sparkle: checks the feed in Info.plist (SUFeedURL) and installs signed updates.
    private var updater: SPUStandardUpdaterController?
    /// Last app the user was in, so captures started from our own popover are still attributed.
    private var lastApp: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugSnapshot.isRequested { return DebugSnapshot.run() }
        if DebugSnapshot.isProbeRequested { return DebugSnapshot.probe() }
        if DebugSnapshot.isFreezeRequested { return DebugSnapshot.freeze() }
        #endif
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        model.checkForUpdates = { [weak self] in self?.checkForUpdates() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snipsy")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: PanelView(model: model, capture: { [weak self] in self?.startCapture() }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua) // the paper look is designed for light mode

        model.onSent = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                self?.popover.performClose(nil)
            }
        }

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.startCapture()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != .current else { return }
            let name = app.localizedName
            MainActor.assumeIsolated { self?.lastApp = name }
        }

        // A local monitor sees the panel's key events before any view, so the arrows work even
        // when the prompt field doesn't have focus (e.g. after clicking a session).
        arrowKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let key = event.keyCode, flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self.switchDestination(key: key, flags: flags) }
            return handled ? nil : event
        }

        doubleCopy = DoubleCopyWatcher { [weak self] pasteboard in self?.addCopied(from: pasteboard) }
        doubleCopy?.start()

        // Capture must be instant: fetch displays and warm up ScreenCaptureKit now, and again when they change.
        Task { await ScreenCapture.prepare() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in await ScreenCapture.prepare() }
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "arrows") { return testArrowKeys() }
        #endif

        // First run (or something missing): open straight on Setup.
        Task {
            await model.refresh()
            if !model.hasScreenPermission || model.bridge != .online { showPopover(tab: .setup) }
        }
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Area", action: #selector(captureFromMenu), keyEquivalent: "2")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(withTitle: "Setup…", action: #selector(openSetup), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snipsy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func captureFromMenu() { startCapture() }
    @objc private func openSetup() { showPopover(tab: .setup) }

    @objc private func checkForUpdates() {
        popover.performClose(nil)
        NSApp.activate() // menu bar app: bring Sparkle's window to the front
        updater?.checkForUpdates(nil)
    }

    private func showPopover(tab: PanelTab? = nil) {
        if let tab { model.tab = tab }
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.async { [weak self] in self?.focusPrompt() } // once the panel is laid out
        Task { await model.refresh() }
    }

    /// Puts the cursor in the prompt field, so the user can type (or use ↑/↓) without clicking.
    private func focusPrompt() {
        guard model.tab == .snip, let window = popover.contentViewController?.view.window,
              let field = window.contentView?.firstDescendant(of: NSTextView.self) else { return }
        window.makeFirstResponder(field)
    }

    /// ↑/↓ select the previous/next destination; in a multi-line prompt they move the cursor instead.
    private func switchDestination(key: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let up: UInt16 = 126, down: UInt16 = 125
        guard popover.isShown, model.tab == .snip, key == up || key == down,
              flags.intersection([.command, .option, .control, .shift]).isEmpty,
              !model.comment.contains("\n") else { return false }
        model.moveDestination(by: key == up ? -1 : 1)
        return true
    }

    #if DEBUG
    /// `Snipsy -arrows 1`: opens the panel with sample sessions, takes focus away from the prompt,
    /// sends ↓ ↓ ↑ as real key events, prints the selection after each, quits.
    private func testArrowKeys() {
        model.sessions = ["a", "b", "c"].map { Session(id: $0, cwd: "/tmp/\($0)", prompt: $0, channel: false, agentID: "claude") }
        popover.behavior = .applicationDefined // launched from a terminal, a transient popover closes at once
        Task {
            try? await Task.sleep(for: .milliseconds(500)) // status item laid out
            showPopover(tab: .snip)
            try? await Task.sleep(for: .milliseconds(600))
            let responder = popover.contentViewController?.view.window?.firstResponder
            print("panel shown: \(popover.isShown), prompt focused: \(responder is NSTextView)")
            model.sessions = ["a", "b", "c"].map { Session(id: $0, cwd: "/tmp/\($0)", prompt: $0, channel: false, agentID: "claude") }
            model.destinationID = "session:a"
            popover.contentViewController?.view.window?.makeFirstResponder(nil) // arrows must work without focus too
            for key: UInt16 in [125, 125, 126] {
                let window = popover.contentViewController?.view.window
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window?.windowNumber ?? 0, context: nil,
                                                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key) {
                    NSApp.postEvent(event, atStart: false)
                }
                try? await Task.sleep(for: .milliseconds(200))
                print("after \(key == 125 ? "↓" : "↑"):", model.destinationID ?? "nil")
            }
            NSApp.terminate(nil)
        }
    }
    #endif

    // MARK: - Double copy

    private func addCopied(from pasteboard: NSPasteboard) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost == .current ? lastApp : frontmost?.localizedName
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.add(text: text, app: source)
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
                  let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            model.add(png: png, app: source)
        } else {
            return
        }
        showPopover(tab: .snip)
    }

    // MARK: - Capture

    private func startCapture() {
        guard selector == nil else { return }
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            showPopover(tab: .setup)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost == .current ? lastApp : frontmost?.localizedName

        // The crosshair shows up instantly; the screen is captured at the same time, without our
        // overlay, and the selection is cropped from that frozen image.
        let freezing = Task { try await ScreenCapture.freeze() }
        popover.performClose(nil)
        let selector = ScreenSelector { [weak self] result in
            guard let self else { return }
            self.selector = nil
            Task {
                defer { Task { await ScreenCapture.prepare() } } // ready for the next one
                guard let (screen, rect) = result else {
                    if !self.model.shots.isEmpty { self.showPopover(tab: .snip) }
                    return
                }
                do {
                    let frozen = try await freezing.value
                    if let png = frozen.first(where: { $0.screen == screen })?.png(of: rect) {
                        self.model.add(png: png, app: source)
                    }
                } catch {
                    self.model.status = .error(error.localizedDescription)
                }
                self.showPopover(tab: .snip)
            }
        }
        self.selector = selector
        selector.begin()
        Task { if let frozen = try? await freezing.value { selector.show(frozen) } }
    }
}

private extension NSView {
    /// Depth-first search for the first subview of the given type.
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for view in subviews {
            if let match = view as? T ?? view.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
