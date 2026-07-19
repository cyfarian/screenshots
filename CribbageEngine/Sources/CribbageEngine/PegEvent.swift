import Foundation

/// Why points were pegged. Also carries zero-point structural markers
/// (`handComplete`) that drive dealer rotation.
public enum PegReason: Codable, Hashable, Sendable {
    case fifteen
    case pair
    case run(Int)
    case nobs
    case heels
    case go
    case lastCard
    case thirtyOne
    case handCount
    case cribCount
    case muggins
    case manual
    case handComplete

    public var label: String {
        switch self {
        case .fifteen: return "Fifteen"
        case .pair: return "Pair"
        case .run(let n): return "Run of \(n)"
        case .nobs: return "Nobs"
        case .heels: return "Heels"
        case .go: return "Go"
        case .lastCard: return "Last card"
        case .thirtyOne: return "Thirty-one"
        case .handCount: return "Hand"
        case .cribCount: return "Crib"
        case .muggins: return "Muggins"
        case .manual: return "Points"
        case .handComplete: return "Next hand"
        }
    }
}

/// One scoring action in a game. The event log is the single source of truth:
/// scores, peg positions, dealer rotation, and undo all derive from it.
public struct PegEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Index of the track (player, or team in partners play) that pegged.
    public let trackIndex: Int
    public let points: Int
    public let reason: PegReason
    public let date: Date
    /// Optional itemized breakdown when the hand calculator pegged this.
    public let breakdown: ScoreBreakdown?

    public init(
        trackIndex: Int,
        points: Int,
        reason: PegReason,
        date: Date = Date(),
        breakdown: ScoreBreakdown? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.trackIndex = trackIndex
        self.points = points
        self.reason = reason
        self.date = date
        self.breakdown = breakdown
    }
}
