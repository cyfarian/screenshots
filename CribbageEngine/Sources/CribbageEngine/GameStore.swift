import Foundation

/// What's on the table right now: the live game plus optional match wrapper.
public struct LiveSession: Codable, Hashable, Sendable {
    public var game: Game
    public var match: MatchState?

    public init(game: Game, match: MatchState? = nil) {
        self.game = game
        self.match = match
    }
}

/// JSON-file persistence for the live session and finished games.
/// Inject a base directory; the app uses Application Support, tests a temp dir.
public final class GameStore {
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var currentURL: URL { baseURL.appendingPathComponent("current.json") }
    private var finishedURL: URL { baseURL.appendingPathComponent("finished", isDirectory: true) }

    public init(baseURL: URL) {
        self.baseURL = baseURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: finishedURL, withIntermediateDirectories: true)
    }

    // MARK: - Live session

    public func saveCurrent(_ session: LiveSession) throws {
        let data = try encoder.encode(session)
        try data.write(to: currentURL, options: .atomic)
    }

    public func loadCurrent() -> LiveSession? {
        guard let data = try? Data(contentsOf: currentURL) else { return nil }
        return try? decoder.decode(LiveSession.self, from: data)
    }

    public func clearCurrent() {
        try? FileManager.default.removeItem(at: currentURL)
    }

    // MARK: - Finished games

    public func archive(_ game: Game) throws {
        let url = finishedURL.appendingPathComponent("\(game.id.uuidString).json")
        let data = try encoder.encode(game)
        try data.write(to: url, options: .atomic)
    }

    /// All finished games, most recent first.
    public func loadFinished() -> [Game] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: finishedURL, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Game.self, from: data)
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    public func deleteFinished(id: UUID) {
        let url = finishedURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
