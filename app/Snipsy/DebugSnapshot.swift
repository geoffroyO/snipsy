#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `Snipsy -snapshot 1` renders both tabs with sample data to PNGs in the
/// app's temporary directory, then quits. Lets the UI be checked without clicking around.
enum DebugSnapshot {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "snapshot") }
    static var isProbeRequested: Bool { UserDefaults.standard.bool(forKey: "probe") }
    static var isFreezeRequested: Bool { UserDefaults.standard.bool(forKey: "freeze") }

    /// `Snipsy -freeze 1`: freeze the screen, crop the top-left 400×300 pt of the main display, save it, quit.
    static func freeze() {
        Task {
            do {
                let shots = try await ScreenCapture.freeze()
                for shot in shots {
                    let f = shot.screen.frame
                    let rect = CGRect(x: f.minX, y: f.maxY - 300, width: 400, height: 300) // top-left corner
                    let url = FileManager.default.temporaryDirectory.appending(path: "freeze-\(Int(f.minX)).png")
                    try shot.png(of: rect)?.write(to: url)
                    print("frozen \(shot.image.width)x\(shot.image.height) for \(Int(f.width))x\(Int(f.height)) pt -> \(url.path)")
                }
            } catch {
                print("freeze ERROR:", error)
            }
            NSApp.terminate(nil)
        }
    }

    /// `Snipsy -probe 1`: query the bridge exactly like the app does, print the result, quit.
    static func probe() {
        Task {
            do {
                let sessions = try await Bridge.sessions()
                print("bridge OK:", sessions.map { "\($0.agent.title) \($0.project) [\($0.prompt)]" })
                let icon = NSApp.applicationIconImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
                    .representation(using: .png, properties: [:]) ?? Data()
                let paths = try await Bridge.saveClip([Shot(png: icon, app: nil, image: NSApp.applicationIconImage)])
                Clipboard.copy([Shot(png: icon, app: nil, image: NSApp.applicationIconImage)], prompt: "probe prompt", paths: paths)
                print("clip OK:", paths)
            } catch {
                print("bridge ERROR:", error)
            }
            NSApp.terminate(nil)
        }
    }

    static func run() {
        let model = AppModel()
        let sample = NSApp.applicationIconImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:]) ?? Data()
        model.add(png: sample, app: "Safari")
        model.add(png: sample, app: "Figma")
        model.comment = "The button is misaligned on mobile"
        model.sessions = [
            Session(id: "a", cwd: "/Users/me/Developer/snipsy", prompt: "polish the menu bar UI", channel: true, agentID: "claude"),
            Session(id: "b", cwd: "/Users/me/Developer/api", prompt: "fix the auth bug", channel: false, agentID: "claude"),
            Session(id: "c", cwd: "/Users/me/Developer/webapp", prompt: "why is the navbar overlapping?", channel: false, agentID: "codex"),
        ] + (1...5).map { i in
            Session(id: "x\(i)", cwd: "/Users/me/Developer/service-\(i)", prompt: "refactor the payment module step \(i)",
                    channel: false, agentID: i.isMultiple(of: 2) ? "codex" : "claude")
        }
        model.bridge = .online
        model.hasScreenPermission = false

        let shots: [(PanelTab, String, String)] = [
            (.snip, "snip", "session:c"), (.snip, "snip-clipboard", "clipboard"), (.setup, "setup", "session:a"),
        ]
        for (tab, name, destination) in shots {
            model.tab = tab
            model.destinationID = destination
            let view = NSHostingView(rootView: PanelView(model: model, capture: {}))
            view.frame.size = view.fittingSize
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: .aqua)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        }
        // What "Paste into a chat" puts on the clipboard: every shot stacked into one image.
        Clipboard.copy(model.shots, prompt: model.comment, paths: ["/tmp/1.png", "/tmp/2.png"])
        let pasted = FileManager.default.temporaryDirectory.appending(path: "snapshot-clipboard.png")
        try? NSPasteboard.general.data(forType: .png)?.write(to: pasted)
        print(pasted.path)
        NSApp.terminate(nil)
    }
}
#endif
