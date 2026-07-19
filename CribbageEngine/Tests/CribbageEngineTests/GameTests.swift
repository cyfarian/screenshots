import XCTest
@testable import CribbageEngine

final class GameTests: XCTestCase {

    private func twoPlayerGame(muggins: Bool = false) -> Game {
        Game(config: GameConfig(
            mode: .twoPlayer,
            playerNames: ["Alice", "Bob"],
            mugginsEnabled: muggins
        ))
    }

    func testScoresAccumulatePerTrack() throws {
        var game = twoPlayerGame()
        try game.peg(track: 0, points: 2, reason: .fifteen)
        try game.peg(track: 1, points: 3, reason: .run(3))
        try game.peg(track: 0, points: 2, reason: .pair)
        XCTAssertEqual(game.score(ofTrack: 0), 4)
        XCTAssertEqual(game.score(ofTrack: 1), 3)
    }

    func testPegPositions() throws {
        var game = twoPlayerGame()
        try game.peg(track: 0, points: 6, reason: .handCount)
        try game.peg(track: 0, points: 4, reason: .cribCount)
        let pegs = game.pegPositions(ofTrack: 0)
        XCTAssertEqual(pegs.front, 10)
        XCTAssertEqual(pegs.back, 6)
        let idle = game.pegPositions(ofTrack: 1)
        XCTAssertEqual(idle.front, 0)
        XCTAssertEqual(idle.back, 0)
    }

    func testUndoRemovesLastEvent() throws {
        var game = twoPlayerGame()
        try game.peg(track: 0, points: 2, reason: .fifteen)
        try game.peg(track: 1, points: 2, reason: .pair)
        XCTAssertNotNil(game.undo())
        XCTAssertEqual(game.score(ofTrack: 1), 0)
        XCTAssertEqual(game.score(ofTrack: 0), 2)
        XCTAssertNotNil(game.undo())
        XCTAssertNil(game.undo())
        XCTAssertFalse(game.canUndo)
    }

    func testDealerRotationTwoPlayer() throws {
        var game = twoPlayerGame()
        XCTAssertEqual(game.dealerSeat, 0)
        XCTAssertEqual(game.cribTrack, 0)
        try game.completeHand()
        XCTAssertEqual(game.dealerSeat, 1)
        try game.completeHand()
        XCTAssertEqual(game.dealerSeat, 0)
        _ = game.undo()
        XCTAssertEqual(game.dealerSeat, 1)
    }

    func testDealerRotationPartnersMapsSeatsToTeams() throws {
        var game = Game(config: GameConfig(
            mode: .fourPlayerPartners,
            playerNames: ["A", "B", "C", "D"],
            teamNames: ["Team 1", "Team 2"]
        ))
        // Seats 0,2 -> track 0; seats 1,3 -> track 1
        XCTAssertEqual(game.cribTrack, 0)
        try game.completeHand()
        XCTAssertEqual(game.dealerSeat, 1)
        XCTAssertEqual(game.cribTrack, 1)
        try game.completeHand()
        XCTAssertEqual(game.dealerSeat, 2)
        XCTAssertEqual(game.cribTrack, 0)
        XCTAssertEqual(game.config.trackName(0), "Team 1")
    }

    func testWinDetectionAndEventRejectionAfterWin() throws {
        var game = twoPlayerGame()
        try game.peg(track: 0, points: 120, reason: .manual)
        XCTAssertFalse(game.isOver)
        try game.peg(track: 0, points: 12, reason: .handCount)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.winnerTrack, 0)
        XCTAssertEqual(game.score(ofTrack: 0), 121) // capped
        XCTAssertNotNil(game.completedAt)
        XCTAssertThrowsError(try game.peg(track: 1, points: 2, reason: .pair)) {
            XCTAssertEqual($0 as? GameError, .gameOver)
        }
        // Undo reopens the game.
        _ = game.undo()
        XCTAssertFalse(game.isOver)
        XCTAssertNil(game.completedAt)
    }

    func testSkunkDetection() throws {
        var game = twoPlayerGame()
        try game.peg(track: 1, points: 70, reason: .manual) // 70: below 91, above 61
        try game.peg(track: 0, points: 121, reason: .manual)
        XCTAssertEqual(game.skunkResult(ofTrack: 1), .skunk)
        XCTAssertNil(game.skunkResult(ofTrack: 0)) // winner has no skunk result
    }

    func testDoubleSkunkAndNoSkunk() throws {
        var doubleSkunked = twoPlayerGame()
        try doubleSkunked.peg(track: 1, points: 60, reason: .manual)
        try doubleSkunked.peg(track: 0, points: 121, reason: .manual)
        XCTAssertEqual(doubleSkunked.skunkResult(ofTrack: 1), .doubleSkunk)

        var clean = twoPlayerGame()
        try clean.peg(track: 1, points: 95, reason: .manual)
        try clean.peg(track: 0, points: 121, reason: .manual)
        XCTAssertEqual(clean.skunkResult(ofTrack: 1), SkunkLevel.none)
    }

    func testInvalidPegs() {
        var game = twoPlayerGame()
        XCTAssertThrowsError(try game.peg(track: 5, points: 2, reason: .pair))
        XCTAssertThrowsError(try game.peg(track: 0, points: 0, reason: .manual))
        XCTAssertThrowsError(try game.peg(track: 0, points: -3, reason: .manual))
    }

    func testMatchScoringWithSkunks() throws {
        var match = MatchState(config: MatchConfig(bestOf: 3, skunksCountExtra: true))

        var game1 = twoPlayerGame()
        try game1.peg(track: 1, points: 70, reason: .manual)
        try game1.peg(track: 0, points: 121, reason: .manual)
        match.record(GameResult(game: game1))
        // Track 1 was skunked -> worth 2 game points
        XCTAssertEqual(match.gamePoints(forTrack: 0), 2)
        XCTAssertEqual(match.winnerTrack(trackCount: 2), 0)

        var plain = MatchState(config: MatchConfig(bestOf: 3, skunksCountExtra: false))
        plain.record(GameResult(game: game1))
        XCTAssertEqual(plain.gamePoints(forTrack: 0), 1)
        XCTAssertNil(plain.winnerTrack(trackCount: 2))
    }

    func testStatsComputation() throws {
        var game = twoPlayerGame()
        try game.peg(track: 0, points: 12, reason: .handCount)
        try game.peg(track: 1, points: 8, reason: .handCount)
        try game.peg(track: 0, points: 121, reason: .manual)
        let stats = Stats.compute(from: [game])
        let alice = stats.first { $0.name == "Alice" }!
        let bob = stats.first { $0.name == "Bob" }!
        XCTAssertEqual(alice.wins, 1)
        XCTAssertEqual(alice.bestHand, 12)
        XCTAssertEqual(alice.skunksGiven, 1) // Bob finished at 8 (double skunk)
        XCTAssertEqual(bob.wins, 0)
        XCTAssertEqual(bob.gamesPlayed, 1)
        XCTAssertEqual(bob.skunksTaken, 1)
        XCTAssertEqual(bob.averageHand, 8.0, accuracy: 0.001)
    }
}
