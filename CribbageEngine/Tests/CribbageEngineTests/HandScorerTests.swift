import XCTest
@testable import CribbageEngine

final class HandScorerTests: XCTestCase {

    private func total(_ hand: [Card], _ starter: Card, crib: Bool = false) -> Int {
        HandScorer.score(hand: hand, starter: starter, isCrib: crib).total
    }

    // MARK: - Named hands (expected values cross-checked independently)

    func testPerfect29Hand() {
        let hand = [Card(.five, .hearts), Card(.five, .diamonds), Card(.five, .spades), Card(.jack, .clubs)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.five, .clubs))
        XCTAssertEqual(breakdown.total, 29)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .fifteen }.count, 8)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .pair }.count, 6)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .nobs }.count, 1)
    }

    func testZeroHand() {
        let hand = [Card(.two, .clubs), Card(.four, .hearts), Card(.six, .diamonds), Card(.eight, .spades)]
        XCTAssertEqual(total(hand, Card(.ten, .hearts)), 0)
    }

    func testDoubleDoubleRun44566() {
        // 4-4-5-6-6: fifteens 8, pairs 4, runs 12 = 24
        let hand = [Card(.four, .clubs), Card(.four, .diamonds), Card(.five, .hearts), Card(.six, .spades)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.six, .diamonds))
        XCTAssertEqual(breakdown.total, 24)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .run }.reduce(0) { $0 + $1.points }, 12)
    }

    func testDoubleRun7899() {
        // 7-8-9-9 + K: fifteen 2, pair 2, two runs of 3 = 10
        let hand = [Card(.seven, .clubs), Card(.eight, .diamonds), Card(.nine, .hearts), Card(.nine, .spades)]
        XCTAssertEqual(total(hand, Card(.king, .clubs)), 10)
    }

    func testTripleRun3334() {
        // 3-3-3-4 + 5: fifteens 6, pairs 6, three runs of 3 = 21
        let hand = [Card(.three, .clubs), Card(.three, .diamonds), Card(.three, .hearts), Card(.four, .spades)]
        XCTAssertEqual(total(hand, Card(.five, .clubs)), 21)
    }

    func testRunOfFive() {
        // 6-7-8-9-10: fifteens 4 (6+9, 7+8), run of 5 = 9
        let hand = [Card(.six, .clubs), Card(.seven, .diamonds), Card(.eight, .hearts), Card(.nine, .spades)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.ten, .clubs))
        XCTAssertEqual(breakdown.total, 9)
        let runs = breakdown.items.filter { $0.kind == .run }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].points, 5)
    }

    func testAceIsLowAndNotWrapAround() {
        // Q-K-A is not a run
        let hand = [Card(.queen, .clubs), Card(.king, .diamonds), Card(.ace, .hearts), Card(.seven, .spades)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.four, .clubs))
        XCTAssertTrue(breakdown.items.filter { $0.kind == .run }.isEmpty)
    }

    // MARK: - Flush rules

    func testFourCardFlushInHand() {
        let hand = [Card(.two, .hearts), Card(.six, .hearts), Card(.nine, .hearts), Card(.king, .hearts)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.four, .clubs))
        XCTAssertEqual(breakdown.items.filter { $0.kind == .flush }.first?.points, 4)
        XCTAssertEqual(breakdown.total, 8) // + fifteens 2+9+4 and 6+9
    }

    func testFourCardFlushDoesNotCountInCrib() {
        let hand = [Card(.two, .hearts), Card(.six, .hearts), Card(.nine, .hearts), Card(.king, .hearts)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.four, .clubs), isCrib: true)
        XCTAssertTrue(breakdown.items.filter { $0.kind == .flush }.isEmpty)
        XCTAssertEqual(breakdown.total, 4)
    }

    func testFiveCardFlushCountsInCrib() {
        let hand = [Card(.two, .hearts), Card(.six, .hearts), Card(.nine, .hearts), Card(.king, .hearts)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.four, .hearts), isCrib: true)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .flush }.first?.points, 5)
        XCTAssertEqual(breakdown.total, 9)
    }

    // MARK: - Nobs / heels

    func testNobs() {
        let hand = [Card(.jack, .diamonds), Card(.two, .clubs), Card(.six, .hearts), Card(.nine, .spades)]
        XCTAssertEqual(total(hand, Card(.king, .diamonds)), 3) // 6+9 fifteen + nobs
    }

    func testNoNobsWhenSuitDiffers() {
        let hand = [Card(.jack, .diamonds), Card(.two, .clubs), Card(.six, .hearts), Card(.nine, .spades)]
        let breakdown = HandScorer.score(hand: hand, starter: Card(.king, .spades))
        XCTAssertTrue(breakdown.items.filter { $0.kind == .nobs }.isEmpty)
    }

    func testHeels() {
        XCTAssertTrue(HandScorer.starterIsHeels(Card(.jack, .clubs)))
        XCTAssertFalse(HandScorer.starterIsHeels(Card(.ten, .clubs)))
    }

    // MARK: - Brute-force cross-check against an independent scorer

    func testAgainstNaiveScorerOnRandomHands() {
        var generator = SplitMix64(seed: 0xC41BBA6E)
        for _ in 0..<3000 {
            var deck = Card.fullDeck.shuffled(using: &generator)
            let hand = Array(deck.prefix(4))
            deck.removeFirst(4)
            let starter = deck[0]
            let isCrib = Bool.random(using: &generator)
            let fast = HandScorer.score(hand: hand, starter: starter, isCrib: isCrib).total
            let naive = NaiveScorer.score(hand: hand, starter: starter, isCrib: isCrib)
            XCTAssertEqual(
                fast, naive,
                "Mismatch for \(hand.map(\.displayName)) + \(starter.displayName) crib=\(isCrib)"
            )
        }
    }
}

/// Deliberately different formulation of the rules, used only to cross-check.
enum NaiveScorer {
    static func score(hand: [Card], starter: Card, isCrib: Bool) -> Int {
        let all = hand + [starter]
        var points = 0

        // Fifteens: all subsets via recursion instead of bitmask.
        func countFifteens(_ index: Int, _ sum: Int, _ size: Int) -> Int {
            if index == all.count {
                return (sum == 15 && size >= 2) ? 1 : 0
            }
            return countFifteens(index + 1, sum, size)
                + countFifteens(index + 1, sum + all[index].rank.value, size + 1)
        }
        points += 2 * countFifteens(0, 0, 0)

        // Pairs from rank counts.
        var rankCounts: [Int: Int] = [:]
        for card in all { rankCounts[card.rank.rawValue, default: 0] += 1 }
        points += rankCounts.values.reduce(0) { $0 + $1 * ($1 - 1) }

        // Runs: for the longest length L in 5,4,3, count L-card subsets that
        // are straights; stop at the first L with any.
        outer: for length in stride(from: 5, through: 3, by: -1) {
            var straights = 0
            for subset in subsets(of: all, size: length) {
                let ranks = subset.map { $0.rank.rawValue }.sorted()
                let isStraight = Set(ranks).count == length
                    && ranks.last! - ranks.first! == length - 1
                if isStraight { straights += 1 }
            }
            if straights > 0 {
                points += length * straights
                break outer
            }
        }

        // Flush.
        if Set(hand.map(\.suit)).count == 1 {
            if starter.suit == hand[0].suit {
                points += 5
            } else if !isCrib {
                points += 4
            }
        }

        // Nobs.
        if hand.contains(Card(.jack, starter.suit)) { points += 1 }

        return points
    }

    private static func subsets(of cards: [Card], size: Int) -> [[Card]] {
        guard size <= cards.count else { return [] }
        var result: [[Card]] = []
        for mask in 0..<(1 << cards.count) where mask.nonzeroBitCount == size {
            result.append((0..<cards.count).filter { mask & (1 << $0) != 0 }.map { cards[$0] })
        }
        return result
    }
}

/// Deterministic RNG so the random cross-check is reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
