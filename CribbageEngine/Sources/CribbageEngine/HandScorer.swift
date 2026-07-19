import Foundation

/// Scores a cribbage hand (4 cards + starter) per standard rules.
public enum HandScorer {

    /// Counts a hand. `hand` must contain exactly 4 cards; `isCrib` applies the
    /// crib flush rule (only a 5-card flush counts).
    public static func score(hand: [Card], starter: Card, isCrib: Bool = false) -> ScoreBreakdown {
        precondition(hand.count == 4, "A cribbage hand has exactly 4 cards")
        let all = hand + [starter]
        var items: [ScoreItem] = []
        items += fifteens(in: all)
        items += pairs(in: all)
        items += runs(in: all)
        items += flush(hand: hand, starter: starter, isCrib: isCrib)
        items += nobs(hand: hand, starter: starter)
        return ScoreBreakdown(items: items)
    }

    // MARK: - Combinations

    /// Every distinct subset of 2+ cards whose counting values sum to 15 scores 2.
    private static func fifteens(in cards: [Card]) -> [ScoreItem] {
        var items: [ScoreItem] = []
        let n = cards.count
        for mask in 1..<(1 << n) {
            guard mask.nonzeroBitCount >= 2 else { continue }
            var sum = 0
            var subset: [Card] = []
            for i in 0..<n where mask & (1 << i) != 0 {
                sum += cards[i].rank.value
                subset.append(cards[i])
            }
            if sum == 15 {
                items.append(ScoreItem(kind: .fifteen, cards: subset, points: 2))
            }
        }
        return items
    }

    /// Each distinct pair of same-rank cards scores 2 (so trips = 6, quads = 12).
    private static func pairs(in cards: [Card]) -> [ScoreItem] {
        var items: [ScoreItem] = []
        for i in 0..<cards.count {
            for j in (i + 1)..<cards.count where cards[i].rank == cards[j].rank {
                items.append(ScoreItem(kind: .pair, cards: [cards[i], cards[j]], points: 2))
            }
        }
        return items
    }

    /// Maximal consecutive-rank sequences of 3+ score their length once per
    /// distinct card combination (e.g. 4-4-5-6 = two runs of 3).
    private static func runs(in cards: [Card]) -> [ScoreItem] {
        var byRank: [Int: [Card]] = [:]
        for card in cards {
            byRank[card.rank.rawValue, default: []].append(card)
        }
        let present = byRank.keys.sorted()
        var items: [ScoreItem] = []
        var i = 0
        while i < present.count {
            // Extend a maximal consecutive streak starting at present[i].
            var j = i
            while j + 1 < present.count && present[j + 1] == present[j] + 1 {
                j += 1
            }
            let length = j - i + 1
            if length >= 3 {
                let groups = present[i...j].map { byRank[$0]! }
                items += combinations(of: groups).map {
                    ScoreItem(kind: .run, cards: $0, points: length)
                }
            }
            i = j + 1
        }
        return items
    }

    /// Cartesian product picking one card from each rank group.
    private static func combinations(of groups: [[Card]]) -> [[Card]] {
        var result: [[Card]] = [[]]
        for group in groups {
            result = result.flatMap { prefix in group.map { prefix + [$0] } }
        }
        return result
    }

    /// Four hand cards of one suit score 4 (+1 if the starter matches).
    /// In the crib only a 5-card flush counts.
    private static func flush(hand: [Card], starter: Card, isCrib: Bool) -> [ScoreItem] {
        let suit = hand[0].suit
        guard hand.allSatisfy({ $0.suit == suit }) else { return [] }
        if starter.suit == suit {
            return [ScoreItem(kind: .flush, cards: hand + [starter], points: 5)]
        }
        if isCrib {
            return []
        }
        return [ScoreItem(kind: .flush, cards: hand, points: 4)]
    }

    /// A jack in hand matching the starter's suit scores 1.
    private static func nobs(hand: [Card], starter: Card) -> [ScoreItem] {
        hand.filter { $0.rank == .jack && $0.suit == starter.suit }
            .map { ScoreItem(kind: .nobs, cards: [$0, starter], points: 1) }
    }

    /// True when the starter is a jack ("his heels" — dealer pegs 2 at the cut).
    public static func starterIsHeels(_ starter: Card) -> Bool {
        starter.rank == .jack
    }
}
