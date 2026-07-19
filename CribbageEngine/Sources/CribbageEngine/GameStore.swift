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
///
/// Payloads are wrapped with a schema version so future model changes can
/// migrate old files instead of silently failing to decode them. Files
/// written before versioning existed (0.x) are read via a legacy fallback.
public final class GameStore {
    public static let schemaVersion = 1

    private struct Versioned<Payload: Codable>: Codable {
        let schemaVersion: Int
        let payload: Payload
    }

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

    // MARK: - Versioned decode

    private func decodePayload<T: Codable>(_ type: T.Type, from data: Data) -> T? {
        if let versioned = try? decoder.decode(Versioned<T>.self, from: data) {
            // Migrations chain here as the schema evolves. A payload from a
            // NEWER schema than this build understands is left untouched.
            guard versioned.schemaVersion <= Self.schemaVersion else { return nil }
            return versioned.payload
        }
        // Legacy pre-versioning payload written by 0.x builds.
        return try? decoder.decode(T.self, from: data)
    }

    private func encodePayload<T: Codable>(_ payload: T) throws -> Data {
        try encoder.encode(Versioned(schemaVersion: Self.schemaVersion, payload: payload))
    }

    // MARK: - Live session

    public func saveCurrent(_ session: LiveSession) throws {
        try encodePayload(session).write(to: currentURL, options: .atomic)
    }

    public func loadCurrent() -> LiveSession? {
        guard let data = try? Data(contentsOf: currentURL) else { return nil }
        return decodePayload(LiveSession.self, from: data)
    }

    public func clearCurrent() {
        try? FileManager.default.removeItem(at: currentURL)
    }

    // MARK: - Finished games

    public func archive(_ game: Game) throws {
        let url = finishedURL.appendingPathComponent("\(game.id.uuidString).json")
        try encodePayload(game).write(to: url, options: .atomic)
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
                return decodePayload(Game.self, from: data)
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    public func deleteFinished(id: UUID) {
        let url = finishedURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
