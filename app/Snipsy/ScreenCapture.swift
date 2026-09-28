import AppKit
@preconcurrency import ScreenCaptureKit

/// One display, captured right when the shortcut is pressed.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage

    /// Crops `rect` (global Cocoa coordinates, origin bottom-left) out of the frozen image, as PNG.
    func png(of rect: CGRect) -> Data? {
        let scale = CGFloat(image.width) / screen.frame.width
        let pixels = CGRect(x: (rect.minX - screen.frame.minX) * scale,
                            y: (screen.frame.maxY - rect.maxY) * scale, // CGImage rows start at the top
                            width: rect.width * scale,
                            height: rect.height * scale).integral
        guard let cropped = image.cropping(to: pixels) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards macOS only allows it from System Settings.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Displays and running apps, fetched ahead of time: asking ScreenCaptureKit for them is the
    /// slowest part of a capture (often hundreds of ms), so it must not happen when ⇧⌘2 is pressed.
    private static var content: SCShareableContent?

    /// Fetches the shareable content and warms up the capture pipeline, so the next capture is instant.
    /// Called at launch, when displays change, and after each capture.
    static func prepare() async {
        guard hasPermission else { return }
        content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if let display = content?.displays.first { // the very first screenshot is slower: take a 1 pt one now
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            config.width = 1
            config.height = 1
            _ = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                                            configuration: config)
        }
    }

    /// Captures every display as it is right now (open menus included), without Snipsy's own windows,
    /// all displays in parallel. The selection overlay can already be on screen: it's excluded.
    static func freeze() async throws -> [FrozenScreen] {
        do {
            let current = if let content { content } else { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            return try await capture(using: current)
        } catch {
            // Cached content can go stale (display plugged or unplugged): refetch once.
            let fresh = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            content = fresh
            return try await capture(using: fresh)
        }
    }

    private static func capture(using content: SCShareableContent) async throws -> [FrozenScreen] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == pid }
        let captures = NSScreen.screens.compactMap { screen -> Task<FrozenScreen, Error>? in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.captureResolution = .best
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            return Task { // started together: displays are captured in parallel
                FrozenScreen(screen: screen, image: try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
            }
        }
        guard captures.count == NSScreen.screens.count else { throw CaptureError.displayNotFound }
        var frozen: [FrozenScreen] = []
        for capture in captures { frozen.append(try await capture.value) }
        return frozen
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? { "Couldn't capture the screen. Try again." }
}

extension NSApplication {
    /// Screen Recording permission only takes effect in a new process: reopen Snipsy.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
