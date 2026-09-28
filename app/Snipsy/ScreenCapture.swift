import AppKit
@preconcurrency import ScreenCaptureKit

/// One display, captured the instant the shortcut is pressed.
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

    /// Captures every display as it is right now (open menus included), without Snipsy's own windows.
    /// Like macOS's screenshot tool, the selection then happens on this frozen image, so nothing on
    /// screen can change or close in the meantime.
    static func freeze() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == pid }
        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.captureResolution = .best
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frozen.append(FrozenScreen(screen: screen, image: image))
        }
        guard !frozen.isEmpty else { throw CaptureError.displayNotFound }
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
