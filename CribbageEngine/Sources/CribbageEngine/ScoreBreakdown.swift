import Foundation

public enum ScoreKind: String, Codable, Sendable {
    case fifteen, pair, run, flush, nobs

    public var label: String {
        switch self {
        case .fifteen: return "Fifteen"
        case .pair: return "Pair"
        case .run: return "Run"
        case .flush: return "Flush"
        case .nobs: return "Nobs"
        }
    }
}

/// One scoring combination within a counted hand, e.g. "Fifteen: 5♣ + 10♦ = 2".
public struct ScoreItem: Hashable, Codable, Sendable, Identifiable {
    public let kind: ScoreKind
    public let cards: [Card]
    public let points: Int

    public init(kind: ScoreKind, cards: [Card], points: Int) {
        self.kind = kind
        self.cards = cards
        self.points = points
    }

    public var id: String {
        kind.rawValue + ":" + cards.map(\.displayName).joined(separator: "+")
    }

    public var label: String {
        switch kind {
        case .run: return "Run of \(cards.count)"
        default: return kind.label
        }
    }
}

/// The full itemized count of a hand.
public struct ScoreBreakdown: Hashable, Codable, Sendable {
    public let items: [ScoreItem]

    public init(items: [ScoreItem]) {
        self.items = items
    }

    public var total: Int { items.reduce(0) { $0 + $1.points } }
}
