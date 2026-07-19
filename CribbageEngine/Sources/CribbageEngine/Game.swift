import Foundation

public enum GameError: Error, Equatable {
    case gameOver
    case invalidTrack
    case nonPositivePoints
}

/// How seats map to scoring tracks.
public enum GameMode: String, Codable, CaseIterable, Sendable {
    /// Two players, two tracks.
    case twoPlayer
    /// Three players, three tracks.
    case threePlayer
    /// Four players in two partnerships, two tracks.
    case fourPlayerPartners

    public var playerCount: Int {
        switch self {
        case .twoPlayer: return 2
        case .threePlayer: return 3
        case .fourPlayerPartners: return 4
        }
    }

    public var trackCount: Int {
        switch self {
        case .twoPlayer, .fourPlayerPartners: return 2
        case .threePlayer: return 3
        }
    }

    /// Track that player `seat` (0-based, in deal order) pegs on.
    /// In partners play, seats 0 & 2 are one team, 1 & 3 the other.
    public func trackIndex(forSeat seat: Int) -> Int {
        self == .fourPlayerPartners ? seat % 2 : seat
    }

    public var label: String {
        switch self {
        case .twoPlayer: return "2 Players"
        case .threePlayer: return "3 Players"
        case .fourPlayerPartners: return "4 Players (Teams)"
        }
    }
}

public struct GameConfig: Codable, Hashable, Sendable {
    public var mode: GameMode
    /// One name per seat, in deal order.
    public var playerNames: [String]
    /// Team names for partners play; ignored otherwise.
    public var teamNames: [String]
    public var targetScore: Int
    public var skunkThreshold: Int
    public var doubleSkunkThreshold: Int
    public var mugginsEnabled: Bool
    public var startingDealerSeat: Int

    public init(
        mode: GameMode,
        playerNames: [String],
        teamNames: [String] = [],
        targetScore: Int = 121,
        skunkThreshold: Int = 91,
        doubleSkunkThreshold: Int = 61,
        mugginsEnabled: Bool = false,
        startingDealerSeat: Int = 0
    ) {
        self.mode = mode
        self.playerNames = playerNames
        self.teamNames = teamNames
        self.targetScore = targetScore
        self.skunkThreshold = skunkThreshold
        self.doubleSkunkThreshold = doubleSkunkThreshold
        self.mugginsEnabled = mugginsEnabled
        self.startingDealerSeat = startingDealerSeat
    }

    /// Display name for a track (player name, or team name in partners play).
    public func trackName(_ track: Int) -> String {
        switch mode {
        case .fourPlayerPartners:
            if track < teamNames.count, !teamNames[track].isEmpty {
                return teamNames[track]
            }
            let members = playerNames.enumerated()
                .filter { mode.trackIndex(forSeat: $0.offset) == track }
                .map(\.element)
            return members.joined(separator: " & ")
        default:
            return track < playerNames.count ? playerNames[track] : "Player \(track + 1)"
        }
    }
}

/// Full state of one cribbage game, derived from an append-only event log.
public struct Game: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var config: GameConfig
    public private(set) var events: [PegEvent]
    public let createdAt: Date
    public var completedAt: Date?

    public init(config: GameConfig, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.config = config
        self.events = []
        self.createdAt = createdAt
        self.completedAt = nil
    }

    // MARK: - Derived state

    /// Current score of a track, capped at the target.
    public func score(ofTrack track: Int) -> Int {
        min(rawScore(ofTrack: track), config.targetScore)
    }

    private func rawScore(ofTrack track: Int) -> Int {
        events.filter { $0.trackIndex == track }.reduce(0) { $0 + $1.points }
    }

    /// Front peg = current score; back peg = score before the track's last move.
    public func pegPositions(ofTrack track: Int) -> (front: Int, back: Int) {
        let front = score(ofTrack: track)
        let lastPoints = events.last { $0.trackIndex == track && $0.points > 0 }?.points ?? 0
        return (front, max(0, front - lastPoints))
    }

    public var winnerTrack: Int? {
        for event in events where event.points > 0 {
            // Winner is whoever first reaches the target as events replay in order.
            if scoreUpTo(event: event, track: event.trackIndex) >= config.targetScore {
                return event.trackIndex
            }
        }
        return nil
    }

    private func scoreUpTo(event: PegEvent, track: Int) -> Int {
        var sum = 0
        for e in events where e.trackIndex == track {
            sum += e.points
            if e.id == event.id { break }
        }
        return sum
    }

    public var isOver: Bool { winnerTrack != nil }

    /// Number of completed hands so far.
    public var handNumber: Int {
        events.filter { $0.reason == .handComplete }.count
    }

    /// Seat (0-based) of the current dealer.
    public var dealerSeat: Int {
        (config.startingDealerSeat + handNumber) % config.mode.playerCount
    }

    /// Track holding the crib this hand.
    public var cribTrack: Int {
        config.mode.trackIndex(forSeat: dealerSeat)
    }

    /// Whether the losing side was skunked / double-skunked (nil while in play).
    public func skunkResult(ofTrack track: Int) -> SkunkLevel? {
        guard let winner = winnerTrack, track != winner else { return nil }
        let s = score(ofTrack: track)
        if s < config.doubleSkunkThreshold { return .doubleSkunk }
        if s < config.skunkThreshold { return .skunk }
        return SkunkLevel.none
    }

    // MARK: - Mutations

    /// Applies a scoring event. Throws once the game is over.
    @discardableResult
    public mutating func peg(
        track: Int,
        points: Int,
        reason: PegReason,
        breakdown: ScoreBreakdown? = nil,
        date: Date = Date()
    ) throws -> PegEvent {
        guard !isOver else { throw GameError.gameOver }
        guard track >= 0 && track < config.mode.trackCount else { throw GameError.invalidTrack }
        guard points > 0 else { throw GameError.nonPositivePoints }
        let event = PegEvent(
            trackIndex: track, points: points, reason: reason,
            date: date, breakdown: breakdown
        )
        events.append(event)
        if isOver {
            completedAt = date
        }
        return event
    }

    /// Marks the current hand finished, advancing the dealer.
    public mutating func completeHand(date: Date = Date()) throws {
        guard !isOver else { throw GameError.gameOver }
        events.append(PegEvent(trackIndex: cribTrack, points: 0, reason: .handComplete, date: date))
    }

    /// Removes the most recent event (scoring or hand marker). Reopens a won game.
    @discardableResult
    public mutating func undo() -> PegEvent? {
        guard let last = events.popLast() else { return nil }
        if !isOver {
            completedAt = nil
        }
        return last
    }

    public var canUndo: Bool { !events.isEmpty }
}

public enum SkunkLevel: String, Codable, Sendable {
    case none
    case skunk
    case doubleSkunk

    /// Games this win is worth in match play (win = 1, skunk = 2, double = 3).
    public var matchValue: Int {
        switch self {
        case .none: return 1
        case .skunk: return 2
        case .doubleSkunk: return 3
        }
    }
}
