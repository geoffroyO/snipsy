import SwiftUI

/// Captures, destination, comment, send.
struct SnipView: View {
    @Bindable var model: AppModel
    let capture: () -> Void
    @FocusState private var commentFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            shots
            DestinationPicker(model: model)
            commentField

            Button {
                Task { await model.send() }
            } label: {
                if model.isSending {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Text(model.destination?.actionTitle ?? "Send")
                }
            }
            .buttonStyle(CrayonButtonStyle())
            .disabled(!model.canSend)

            StatusLine(model: model)
        }
        .onAppear { commentFocused = true } // typing and ↑/↓ work right away
    }

    @ViewBuilder private var shots: some View {
        if model.shots.isEmpty {
            AddTile(title: "Capture an area", subtitle: "⇧⌘2 for an area · ⌘C ⌘C for text", action: capture)
                .frame(height: 96)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(model.shots.enumerated()), id: \.element.id) { index, shot in
                    ShotTile(shot: shot, tilt: index.isMultiple(of: 2) ? -2 : 1.6) { model.remove(shot) }
                }
                AddTile(title: "+ area", action: capture)
                    .aspectRatio(4 / 3, contentMode: .fit)
            }
            .padding(.top, 4)
        }
    }

    private var commentField: some View {
        TextEditor(text: $model.comment)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused($commentFocused)
            .onKeyPress(.return, phases: .down) { press in
                // ↵ sends, like a chat. ⌘↵ (or ⇧↵) inserts a new line at the cursor.
                if press.modifiers.contains(.command) || press.modifiers.contains(.shift) {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.insertNewlineIgnoringFieldEditor(nil)
                } else if model.canSend {
                    Task { await model.send() }
                }
                return .handled
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(height: 70)
            .overlay(alignment: .topLeading) {
                if model.comment.isEmpty {
                    Text(model.destination == .clipboard ? "Your prompt (copied with the image)" : "What should it look at?")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mute.opacity(0.8))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            }
            .card(radius: 10, border: commentFocused ? .crayonOrange : .pencil, seed: 3)
    }
}

// MARK: - Shots

private struct ShotTile: View {
    let shot: Shot
    let tilt: Double
    let onRemove: () -> Void

    var body: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipped()
            .padding(4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .rotationEffect(.degrees(tilt))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.crayonOrange))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 7, y: -7)
                .accessibilityLabel("Remove screenshot")
            }
            .help(shot.app.map { "From \($0)" } ?? (shot.text == nil ? "Screenshot" : "Copied text"))
    }

    /// A screenshot, or the first lines of copied text on a quote card.
    @ViewBuilder private var content: some View {
        if let image = shot.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\u{201C}").font(.hand(22, bold: true)).foregroundStyle(Color.crayonOrange).frame(height: 14)
                Text(shot.text ?? "")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.ink)
                    .lineLimit(5)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.card)
        }
    }
}

private struct AddTile: View {
    let title: String
    var subtitle: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.hand(16, bold: true))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.mute) }
            }
            .foregroundStyle(Color.crayonBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Sketch(cornerRadius: 10, seed: 6).fill(Color.crayonBlue.opacity(isHovered ? 0.1 : 0.04)))
            .sketchBorder(.crayonBlue, radius: 10, width: 2, dashed: true, seed: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Destinations

/// Sessions grouped by agent, then the clipboard for any other chat.
private struct DestinationPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send to").font(.hand(15, bold: true))
                Text("↑↓").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.mute.opacity(0.8))
                    .help("Use the arrow keys to switch")
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mute)
                .help("Refresh sessions")
                .accessibilityLabel("Refresh sessions")
            }

            if model.sessions.isEmpty {
                noSessions
            } else {
                sessionList
            }

            HStack(spacing: 6) {
                Text("or").font(.system(size: 11)).foregroundStyle(Color.mute)
                chip("Clipboard", systemImage: "doc.on.clipboard", destination: .clipboard)
                Text("to paste into any chat").font(.system(size: 11)).foregroundStyle(Color.mute)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var sessionList: some View {
        let groups = Agent.allCases.compactMap { agent -> (Agent, [Session])? in
            let sessions = model.sessions.filter { $0.agent == agent }
            return sessions.isEmpty ? nil : (agent, sessions)
        }
        let list = VStack(alignment: .leading, spacing: 5) {
            ForEach(groups, id: \.0) { agent, sessions in
                AgentTag(agent: agent).padding(.top, 3)
                ForEach(sessions) { session in
                    SessionRow(session: session, isSelected: model.destinationID == Destination.session(session).id) {
                        model.destinationID = Destination.session(session).id
                    }
                    .id(Destination.session(session).id)
                }
            }
        }
        if model.sessions.count > 5 {
            ScrollViewReader { proxy in
                // Room around the rows: their crayon outlines overflow a little and ScrollView clips.
                ScrollView { list.padding(.horizontal, 4).padding(.vertical, 8).padding(.trailing, 6) }
                    .frame(height: 196)
                    // Soft fade at the edges, so rows scrolling out look intentional rather than cut.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                 .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onAppear { proxy.scrollTo(model.destinationID, anchor: .center) }
                    .onChange(of: model.destinationID) { _, id in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } // keep the selection visible
                    }
            }
        } else {
            list
        }
    }

    private var noSessions: some View {
        Button { model.tab = .setup } label: {
            HStack(spacing: 8) {
                Image(systemName: model.bridge == .offline ? "powerplug" : "terminal")
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.bridge == .offline ? "Claude Code / Codex not connected" : "No open session")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.bridge == .offline ? "Install the plugin in Setup" : "Start a Claude Code or Codex session")
                        .font(.system(size: 11)).foregroundStyle(Color.mute)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.mute)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .card(radius: 10, seed: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, systemImage: String, destination: Destination) -> some View {
        let isSelected = model.destinationID == destination.id
        return Button { model.destinationID = destination.id } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.ink : Color.mute)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .fixedSize()
                .background(Sketch(cornerRadius: 8, seed: Double(title.count)).fill(isSelected ? Color.card : .clear))
                .sketchBorder(isSelected ? .crayonOrange : .pencil.opacity(0.4), radius: 8,
                              width: isSelected ? 1.6 : 1, seed: Double(title.count))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? session.agent.color : Color.mute)
                Text(session.project)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(session.prompt.isEmpty ? "new session" : session.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mute)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if session.isInstant {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.crayonOrange)
                        .help("Instant delivery")
                        .accessibilityLabel("Instant delivery")
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Sketch(cornerRadius: 9, seed: Double(session.id.count)).fill(Color.card.opacity(isSelected ? 1 : 0.55)))
            .sketchBorder(isSelected ? session.agent.color : .pencil.opacity(0.35), radius: 9,
                          width: isSelected ? 1.8 : 1, seed: Double(session.id.count))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.cwd)
        .accessibilityLabel("\(session.agent.title) session in \(session.project)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Status

private struct StatusLine: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.status {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Color.crayonGreen)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.crayonOrangeDark)
            case nil:
                Text(hint).foregroundStyle(Color.mute)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var hint: String {
        switch model.destination {
        case .session(let session) where session.isInstant:
            "⚡ \(session.agent.title) reacts as soon as you send."
        case .session(let session):
            "Arrives in \(session.agent.title) with your next message."
        case .clipboard:
            "Copies your prompt, the copied text and the screenshots (file paths for terminals, the image for chats). Paste with ⌘V."
        case nil:
            ""
        }
    }
}
