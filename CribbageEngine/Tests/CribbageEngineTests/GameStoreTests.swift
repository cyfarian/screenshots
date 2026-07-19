import XCTest
@testable import CribbageEngine

final class GameStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: GameStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = GameStore(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sampleGame() throws -> Game {
        var game = Game(config: GameConfig(mode: .twoPlayer, playerNames: ["Alice", "Bob"]))
        try game.peg(track: 0, points: 2, reason: .fifteen)
        try game.peg(
            track: 1, points: 4, reason: .handCount,
            breakdown: HandScorer.score(
                hand: [Card(.two, .hearts), Card(.six, .hearts), Card(.nine, .hearts), Card(.king, .hearts)],
                starter: Card(.four, .clubs)
            )
        )
        return game
    }

    func testLiveSessionRoundTrip() throws {
        let game = try sampleGame()
        let match = MatchState(config: MatchConfig(bestOf: 5, skunksCountExtra: true))
        try store.saveCurrent(LiveSession(game: game, match: match))

        // Compare fields, not whole values: ISO-8601 dates drop sub-second
        // precision, so Date round trips are not bit-identical.
        let loaded = store.loadCurrent()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.game.id, game.id)
        XCTAssertEqual(loaded?.game.events.map(\.id), game.events.map(\.id))
        XCTAssertEqual(loaded?.game.score(ofTrack: 0), 2)
        XCTAssertEqual(loaded?.game.score(ofTrack: 1), 4)
        XCTAssertEqual(loaded?.match?.config.bestOf, 5)

        store.clearCurrent()
        XCTAssertNil(store.loadCurrent())
    }

    func testArchiveAndLoadFinished() throws {
        var game = try sampleGame()
        try game.peg(track: 0, points: 121, reason: .manual)
        XCTAssertTrue(game.isOver)
        try store.archive(game)

        let finished = store.loadFinished()
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished[0].id, game.id)
        XCTAssertEqual(finished[0].winnerTrack, 0)
        XCTAssertEqual(finished[0].events.count, 3)
        // Breakdown survives the round trip (flush 4 + two fifteens = 8).
        XCTAssertEqual(finished[0].events[1].breakdown?.total, 8)

        store.deleteFinished(id: game.id)
        XCTAssertTrue(store.loadFinished().isEmpty)
    }

    func testLoadCurrentWhenMissingReturnsNil() {
        XCTAssertNil(store.loadCurrent())
        XCTAssertTrue(store.loadFinished().isEmpty)
    }

    func testLegacyUnversionedFileStillLoads() throws {
        // 0.x builds wrote the session without a schema wrapper.
        let game = try sampleGame()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = try encoder.encode(LiveSession(game: game))
        try legacy.write(to: tempDir.appendingPathComponent("current.json"))

        let loaded = store.loadCurrent()
        XCTAssertEqual(loaded?.game.id, game.id)

        // Re-saving upgrades to the versioned wrapper.
        try store.saveCurrent(loaded!)
        let raw = try Data(contentsOf: tempDir.appendingPathComponent("current.json"))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("schemaVersion"))
    }

    func testFutureSchemaVersionIsNotMisread() throws {
        let json = #"{"schemaVersion": 999, "payload": {"anything": true}}"#
        try Data(json.utf8).write(to: tempDir.appendingPathComponent("current.json"))
        XCTAssertNil(store.loadCurrent())
    }
}
