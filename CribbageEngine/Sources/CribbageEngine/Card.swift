import Foundation

/// A playing-card rank. `rawValue` is the run-order value (ace low, 1...13).
public enum Rank: Int, CaseIterable, Codable, Comparable, Sendable {
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king

    /// The counting value used for fifteens and pegging (face cards count 10).
    public var value: Int { min(rawValue, 10) }

    public var symbol: String {
        switch self {
        case .ace: return "A"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        default: return String(rawValue)
        }
    }

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum Suit: String, CaseIterable, Codable, Sendable {
    case clubs, diamonds, hearts, spades

    public var symbol: String {
        switch self {
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    public var isRed: Bool { self == .diamonds || self == .hearts }
}

public struct Card: Hashable, Codable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    public var displayName: String { rank.symbol + suit.symbol }

    public static var fullDeck: [Card] {
        Suit.allCases.flatMap { suit in Rank.allCases.map { Card($0, suit) } }
    }
}
