import Foundation

/// The coding agents the plugin supports.
enum Agent: String, CaseIterable {
    case claude, codex

    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var short: String { self == .claude ? "Claude" : "Codex" }
}

/// A Claude Code or Codex session registered by the plugin's hook.
struct Session: Decodable, Identifiable, Hashable {
    let id: String
    let cwd: String
    let prompt: String
    let channel: Bool?
    /// Raw `agent` field; kept as a string so an unknown value never breaks the whole list.
    let agentID: String?

    enum CodingKeys: String, CodingKey {
        case id, cwd, prompt, channel, agentID = "agent"
    }

    var agent: Agent { agentID.flatMap(Agent.init(rawValue:)) ?? .claude }

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }

    /// Started with the Snipsy channel: screenshots are pushed instantly.
    var isInstant: Bool { channel == true }
}

/// Client for the plugin's local bridge (`plugin/bridge/server.py`).
enum Bridge {
    private static let base = URL(string: "http://127.0.0.1:7823")!

    static func sessions() async throws -> [Session] {
        let (data, response) = try await URLSession.shared.data(for: request("sessions"))
        try check(response)
        return try JSONDecoder().decode([Session].self, from: data)
    }

    static func send(_ shots: [Shot], comment: String, to sessionID: String) async throws {
        struct Payload: Encodable {
            struct Item: Encodable { let png: String?; let text: String?; let app: String? }
            let session: String
            let comment: String
            let shots: [Item]
        }
        var request = request("send")
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(
            session: sessionID,
            comment: comment,
            shots: shots.map { .init(png: $0.png?.base64EncodedString(), text: $0.text, app: $0.app) }
        ))
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }

    /// Saves the screenshots as files the user's other apps can read, returns their paths.
    static func saveClip(_ shots: [Shot]) async throws -> [String] {
        let pngs = shots.compactMap(\.png)
        guard !pngs.isEmpty else { return [] }
        struct Payload: Encodable { struct Item: Encodable { let png: String }; let shots: [Item] }
        struct Reply: Decodable { let paths: [String] }
        var request = request("clip")
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(shots: pngs.map { .init(png: $0.base64EncodedString()) }))
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try JSONDecoder().decode(Reply.self, from: data).paths
    }

    private static func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.setValue("1", forHTTPHeaderField: "X-Snipsy") // the bridge rejects anything without it
        request.timeoutInterval = 3
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}
