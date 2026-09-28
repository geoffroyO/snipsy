import SwiftUI

// Crayon-on-paper look, matching the app icon.

extension Color {
    static let paper = Color(red: 0.961, green: 0.937, blue: 0.890)
    static let card = Color(red: 1.0, green: 0.992, blue: 0.969)
    static let ink = Color(red: 0.231, green: 0.212, blue: 0.192)
    static let mute = Color(red: 0.525, green: 0.494, blue: 0.447)
    static let pencil = Color(red: 0.431, green: 0.404, blue: 0.361)
    static let crayonOrange = Color(red: 0.871, green: 0.431, blue: 0.251)
    static let crayonOrangeDark = Color(red: 0.698, green: 0.306, blue: 0.157)
    static let crayonBlue = Color(red: 0.408, green: 0.565, blue: 0.784)
    static let crayonGreen = Color(red: 0.310, green: 0.580, blue: 0.360)
}

extension Font {
    /// Noteworthy ships with macOS.
    static func hand(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
    }
}

/// A rounded rectangle traced by hand: the outline wobbles a little, deterministically per seed.
struct Sketch: Shape {
    var cornerRadius: CGFloat = 10
    var seed: Double = 1
    var wobble: CGFloat = 1.1

    func path(in rect: CGRect) -> Path {
        let base = RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        let steps = max(24, Int(2 * (rect.width + rect.height) / 7))
        var path = Path()
        for i in 0...steps {
            let t = max(CGFloat(i) / CGFloat(steps), 0.0001)
            guard let p = base.trimmedPath(from: 0, to: t).currentPoint else { continue }
            let n = CGFloat(sin(Double(i) * 1.7 + seed * 3.1) + sin(Double(i) * 0.53 + seed)) * wobble / 2
            let point = CGPoint(x: p.x + n, y: p.y - n)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Double-traced pencil outline.
    func sketchBorder(_ color: Color = .pencil, radius: CGFloat = 10, width: CGFloat = 1.6,
                      dashed: Bool = false, seed: Double = 1) -> some View {
        let dash: [CGFloat] = dashed ? [6, 4] : []
        return overlay {
            ZStack {
                Sketch(cornerRadius: radius, seed: seed)
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
                Sketch(cornerRadius: radius, seed: seed + 7, wobble: 1.5)
                    .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: width * 0.7, lineCap: .round, dash: dash))
            }
            .allowsHitTesting(false)
        }
    }

    /// Filled card with a pencil outline.
    func card(radius: CGFloat = 10, border: Color = .pencil, seed: Double = 1) -> some View {
        background(Sketch(cornerRadius: radius, seed: seed).fill(Color.card))
            .sketchBorder(border, radius: radius, seed: seed)
    }
}

/// Paper with faint diagonal crayon hatching.
struct PaperBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.paper))
            var hatching = Path()
            var x = -size.height
            while x < size.width {
                hatching.move(to: CGPoint(x: x, y: size.height))
                hatching.addLine(to: CGPoint(x: x + size.height * 0.53, y: 0))
                x += 7
            }
            context.stroke(hatching, with: .color(Color(red: 0.59, green: 0.47, blue: 0.31).opacity(0.07)), lineWidth: 1.2)
        }
    }
}

struct CrayonButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hand(prominent ? 17 : 14, bold: true))
            .foregroundStyle(prominent ? Color.white : Color.ink)
            .frame(maxWidth: prominent ? .infinity : nil)
            .padding(.vertical, prominent ? 7 : 3)
            .padding(.horizontal, 12)
            .background(Sketch(cornerRadius: 11, seed: 4).fill(prominent ? Color.crayonOrange : Color.card))
            .sketchBorder(prominent ? .crayonOrangeDark : .pencil, radius: 11, width: 1.8, seed: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Agents

extension Color {
    static let codexInk = Color(red: 0.17, green: 0.18, blue: 0.21)
}

extension Agent {
    var color: Color { self == .claude ? .crayonOrange : .codexInk }
}

/// Small colored label naming the agent, used wherever a session appears.
struct AgentTag: View {
    let agent: Agent
    var compact = false

    var body: some View {
        Text(compact ? agent.short : agent.title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(agent.color))
            .fixedSize()
    }
}
