import AppKit

/// A rectangle the user dragged, in global Cocoa coordinates (origin bottom-left of the main display).
struct ScreenSelection {
    let rect: CGRect
    let screen: NSScreen
}

/// Covers every display with a dimmed overlay to drag out a capture area. Esc cancels.
final class ScreenSelector {
    private var windows: [NSWindow] = []
    private let completion: (ScreenSelection?) -> Void

    init(completion: @escaping (ScreenSelection?) -> Void) {
        self.completion = completion
    }

    func begin() {
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = SelectionView { [weak self] rect in self?.finish(rect, on: screen) }
            window.setFrame(screen.frame, display: false)
            return window
        }
        NSApp.activate()
        windows.forEach { $0.orderFrontRegardless() }
        let underMouse = windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        (underMouse ?? windows.first)?.makeKey()
    }

    private func finish(_ rect: CGRect?, on screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion(rect.map { ScreenSelection(rect: $0, screen: screen) })
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private var start: NSPoint?
    private var current: NSPoint?
    private let onFinish: (CGRect?) -> Void

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selection, rect.width > 4, rect.height > 4, let window else {
            onFinish(nil)
            return
        }
        onFinish(window.convertToScreen(convert(rect, to: nil)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } else { super.keyDown(with: event) } // 53 = Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.24, green: 0.18, blue: 0.12, alpha: 0.28).setFill()
        bounds.fill()

        guard let rect = selection else {
            drawHint("Drag to capture · Esc to cancel")
            return
        }
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        let border = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        border.setLineDash([7, 4], count: 2, phase: 0)
        NSColor(srgbRed: 0.408, green: 0.565, blue: 0.784, alpha: 1).setStroke()
        border.stroke()

        let size = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        size.draw(at: NSPoint(x: rect.minX, y: max(rect.minY - 18, 4)), withAttributes: attributes)
    }

    private func drawHint(_ text: String) {
        let font = NSFont(name: "Noteworthy-Bold", size: 16) ?? .systemFont(ofSize: 15, weight: .semibold)
        let string = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.231, green: 0.212, blue: 0.192, alpha: 1),
        ]
        let size = string.size(withAttributes: attributes)
        let pill = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - size.height - 60,
                          width: size.width + 28, height: size.height + 12)
        NSColor(srgbRed: 0.961, green: 0.937, blue: 0.890, alpha: 1).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
        string.draw(at: NSPoint(x: pill.minX + 14, y: pill.minY + 6), withAttributes: attributes)
    }
}
