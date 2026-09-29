import AppKit

enum Clipboard {
    /// Puts everything on a single pasteboard item, so one ⌘V does the right thing anywhere:
    /// - text (terminals, Claude Code, Codex): the prompt, the copied texts, then the screenshot file paths;
    /// - image + HTML (chat apps, Slack, Notes…): all screenshots stacked into one image, with the prompt.
    static func copy(_ shots: [Shot], prompt: String, paths: [String]) {
        let item = NSPasteboardItem()
        let png = stacked(shots)
        if let png {
            item.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = shots.compactMap(\.text).map { "```\n\($0)\n```" }.joined(separator: "\n\n")
        // Spaces around each path: agents turn paths into image chips and would glue them to the prompt.
        let files = paths.map { " \($0) " }.joined()
        let text = [prompt, quotes, files].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !text.isEmpty { item.setString(text, forType: .string) }
        if let png, !prompt.isEmpty {
            let escaped = prompt.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
            item.setString("<p>\(escaped)</p><img src=\"data:image/png;base64,\(png.base64EncodedString())\">", forType: .html)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        DoubleCopyWatcher.ignoredChange = pasteboard.changeCount
    }

    private static func stacked(_ shots: [Shot]) -> Data? {
        let pngs = shots.compactMap(\.png)
        let images = pngs.compactMap { NSBitmapImageRep(data: $0)?.cgImage }
        guard images.count > 1 else { return pngs.first }
        let gap = 24
        let width = images.map(\.width).max() ?? 0
        let height = images.map(\.height).reduce(0, +) + gap * (images.count - 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height // Core Graphics' origin is bottom-left: draw from the top down
        for image in images {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: image.width, height: image.height))
            top -= gap
        }
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}
