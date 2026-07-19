import XCTest
@testable import CribbageEngine

/// Scores every hand in shared/hand-fixtures.json — the same file the web
/// app's engine tests consume — so the two implementations cannot drift.
final class HandFixtureTests: XCTestCase {

    private struct FixtureCard: Decodable {
        let rank: Int
        let suit: String

        var card: Card {
            Card(Rank(rawValue: rank)!, Suit(rawValue: suit)!)
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let hand: [FixtureCard]
        let starter: FixtureCard
        let isCrib: Bool
        let expectedTotal: Int
    }

    private struct FixtureFile: Decodable {
        let version: Int
        let fixtures: [Fixture]
    }

    func testSharedFixtures() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CribbageEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CribbageEngine
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("shared/hand-fixtures.json")
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(FixtureFile.self, from: data)
        XCTAssertGreaterThan(file.fixtures.count, 100)

        for fixture in file.fixtures {
            let total = HandScorer.score(
                hand: fixture.hand.map(\.card),
                starter: fixture.starter.card,
                isCrib: fixture.isCrib
            ).total
            XCTAssertEqual(total, fixture.expectedTotal, fixture.name)
        }
    }
}
