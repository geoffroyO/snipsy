import SwiftUI

/// Content of the menu bar popover: header, tab switch, and the active tab.
struct PanelView: View {
    @Bindable var model: AppModel
    let capture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.tab {
            case .snip: SnipView(model: model, capture: capture)
            case .setup: SetupView(model: model)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(PaperBackground())
        .foregroundStyle(Color.ink)
        .task {
            // Live while the popover is open: sessions appear as soon as an agent registers them
            // (the Codex app only creates a session on its first message).
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(-4))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Snipsy").font(.hand(22, bold: true))
                Text("⇧⌘2 to capture")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mute)
            }
            Spacer()
            TabSwitch(selection: $model.tab, setupNeedsAttention: model.needsSetup)
        }
    }
}

private struct TabSwitch: View {
    @Binding var selection: PanelTab
    let setupNeedsAttention: Bool

    var body: some View {
        HStack(spacing: 4) {
            tab("Snip", .snip)
            tab("Setup", .setup)
                .overlay(alignment: .topTrailing) {
                    if setupNeedsAttention {
                        Circle().fill(Color.crayonOrange).frame(width: 7, height: 7).offset(x: -2, y: 2)
                            .accessibilityLabel("Setup needs attention")
                    }
                }
        }
    }

    private func tab(_ title: String, _ value: PanelTab) -> some View {
        let isSelected = selection == value
        return Button { selection = value } label: {
            Text(title)
                .font(.hand(15, bold: isSelected))
                .foregroundStyle(isSelected ? Color.ink : Color.mute)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background {
                    if isSelected { Sketch(cornerRadius: 8, seed: 9).fill(Color.card) }
                }
                .sketchBorder(isSelected ? .pencil : .clear, radius: 8, width: 1.3, seed: 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
