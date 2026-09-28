import SwiftUI

@main
struct SnipsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar only (LSUIElement): the UI lives in the status item's popover.
        Settings { EmptyView() }
    }
}
