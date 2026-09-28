import AppKit
@preconcurrency import ScreenCaptureKit

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

    /// Captures `rect` (global Cocoa coordinates) on `screen` as PNG, without Snipsy's own windows.
    static func capture(_ rect: CGRect, on screen: NSScreen) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display,
                                     excludingApplications: content.applications.filter { $0.processID == pid },
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        // ScreenCaptureKit wants display-local points with a top-left origin.
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.width = Int(rect.width * screen.backingScaleFactor)
        config.height = Int(rect.height * screen.backingScaleFactor)
        config.captureResolution = .best
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        return png
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound, encodingFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Couldn't find that display. Try again."
        case .encodingFailed: "Couldn't encode the screenshot."
        }
    }
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
