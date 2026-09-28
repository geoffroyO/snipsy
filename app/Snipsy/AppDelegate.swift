import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the menu bar item, the popover, the global shortcut and the capture flow.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var selector: ScreenSelector?
    private var isFreezing = false
    /// Last app the user was in, so captures started from our own popover are still attributed.
    private var lastApp: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugSnapshot.isRequested { return DebugSnapshot.run() }
        if DebugSnapshot.isProbeRequested { return DebugSnapshot.probe() }
        if DebugSnapshot.isFreezeRequested { return DebugSnapshot.freeze() }
        #endif
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snipsy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func captureFromMenu() { startCapture() }
    @objc private func openSetup() { showPopover(tab: .setup) }

    private func showPopover(tab: PanelTab? = nil) {
        if let tab { model.tab = tab }
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.refresh() }
    }

    // MARK: - Capture

    private func startCapture() {
        guard selector == nil, !isFreezing else { return }
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            showPopover(tab: .setup)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost == .current ? lastApp : frontmost?.localizedName
        isFreezing = true

        Task {
            // Freeze the screen first, before anything of ours appears or takes focus:
            // open menus and hover states are kept, like with macOS's own screenshot tool.
            let frozen: [FrozenScreen]
            do {
                frozen = try await ScreenCapture.freeze()
            } catch {
                isFreezing = false
                model.status = .error(error.localizedDescription)
                showPopover(tab: .snip)
                return
            }
            isFreezing = false
            popover.performClose(nil)

            selector = ScreenSelector(frozen: frozen) { [weak self] result in
                guard let self else { return }
                selector = nil
                if let (shot, rect) = result, let png = shot.png(of: rect) {
                    model.add(png: png, app: source)
                } else if model.shots.isEmpty {
                    return // cancelled with nothing to show
                }
                showPopover(tab: .snip)
            }
            selector?.begin()
        }
    }
}
