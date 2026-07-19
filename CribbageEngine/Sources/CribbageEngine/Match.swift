import Foundation

/// Compact record of a finished game, kept in match state and history.
public struct GameResult: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let winnerTrack: Int
    public let scores: [Int]
    public let skunks: [SkunkLevel?]
    public let date: Date

    public init(game: Game) {
        precondition(game.isOver, "GameResult requires a finished game")
        self.id = game.id
        let winner = game.winnerTrack ?? 0
        self.winnerTrack = winner
        let tracks = 0..<game.config.mode.trackCount
        self.scores = tracks.map { game.score(ofTrack: $0) }
        self.skunks = tracks.map { game.skunkResult(ofTrack: $0) }
        self.date = game.completedAt ?? game.createdAt
    }

    /// Games the winner earned toward the match (skunks count extra when enabled).
    public func matchValue(skunksCountExtra: Bool) -> Int {
        guard skunksCountExtra else { return 1 }
        let worstLoss = skunks.compactMap { $0 }.map(\.matchValue).max() ?? 1
        return worstLoss
    }
}

public struct MatchConfig: Codable, Hashable, Sendable {
    /// Best-of-N; first side past N/2 game-points wins.
    public var bestOf: Int
    public var skunksCountExtra: Bool

    public init(bestOf: Int = 3, skunksCountExtra: Bool = false) {
        self.bestOf = bestOf
        self.skunksCountExtra = skunksCountExtra
    }

    public var winsNeeded: Int { bestOf / 2 + 1 }
}

/// Running best-of-N match state across games.
public struct MatchState: Codable, Hashable, Sendable {
    public var config: MatchConfig
    public private(set) var results: [GameResult]

    public init(config: MatchConfig) {
        self.config = config
        self.results = []
    }

    public mutating func record(_ result: GameResult) {
        results.append(result)
    }

    public func gamePoints(forTrack track: Int) -> Int {
        results.filter { $0.winnerTrack == track }
            .reduce(0) { $0 + $1.matchValue(skunksCountExtra: config.skunksCountExtra) }
    }

    public func winnerTrack(trackCount: Int) -> Int? {
        (0..<trackCount).first { gamePoints(forTrack: $0) >= config.winsNeeded }
    }
}
