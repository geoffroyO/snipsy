import AppKit

/// Detects ⌘C pressed twice in a row, in any app: two clipboard changes 60–600 ms apart.
///
/// Only the pasteboard's change counter is polled, which needs no permission and doesn't read
/// anything; the contents are read once, when a double copy is detected.
final class DoubleCopyWatcher {
    /// Snipsy's own clipboard writes (Copy button, setup commands) must not count.
    static var ignoredChange: Int?

    private var timer: Timer?
    private var lastCount = NSPasteboard.general.changeCount
    private var lastChange: Date?
    private let onDoubleCopy: (NSPasteboard) -> Void

    init(onDoubleCopy: @escaping (NSPasteboard) -> Void) {
        self.onDoubleCopy = onDoubleCopy
    }

    func start() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let count = NSPasteboard.general.changeCount
        guard count != lastCount else { return }
        let steps = count - lastCount
        lastCount = count
        if count == Self.ignoredChange { return }

        let now = Date()
        // Several changes within one 50 ms tick come from a single copy, not a double press.
        if steps == 1, let last = lastChange, (0.06...0.6).contains(now.timeIntervalSince(last)) {
            lastChange = nil
            onDoubleCopy(.general)
        } else {
            lastChange = now
        }
    }
}
