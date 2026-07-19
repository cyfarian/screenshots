import Foundation
import Observation
import CribbageEngine

/// Root observable state: owns the live session, persistence, and history.
@Observable
final class AppState {
    var session: LiveSession?
    private(set) var finishedGames: [Game] = []
    var lastError: String?

    private let store: GameStore

    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CribbageScore", isDirectory: true)
        store = GameStore(baseURL: base)
        session = store.loadCurrent()
        finishedGames = store.loadFinished()
    }

    var hasLiveGame: Bool { session != nil }

    var stats: [PlayerStats] { Stats.compute(from: finishedGames) }

    // MARK: - Game lifecycle

    func startGame(config: GameConfig, matchConfig: MatchConfig?) {
        let game = Game(config: config)
        let match = matchConfig.map { MatchState(config: $0) }
        session = LiveSession(game: game, match: match)
        persist()
    }

    /// Archives the finished game; starts the next match game when asked.
    func concludeGame(startNext: Bool) {
        guard var current = session, current.game.isOver else { return }
        try? store.archive(current.game)
        finishedGames = store.loadFinished()
        current.match?.record(GameResult(game: current.game))

        let trackCount = current.game.config.mode.trackCount
        let matchDone = current.match?.winnerTrack(trackCount: trackCount) != nil
        if startNext, current.match != nil, !matchDone {
            var config = current.game.config
            // Loser of the previous game deals first in the next one.
            if let winner = current.game.winnerTrack {
                let losers = (0..<config.mode.playerCount)
                    .filter { config.mode.trackIndex(forSeat: $0) != winner }
                config.startingDealerSeat = losers.first ?? 0
            }
            current.game = Game(config: config)
            session = current
        } else {
            session = nil
            store.clearCurrent()
        }
        persist()
    }

    func abandonGame() {
        session = nil
        store.clearCurrent()
    }

    func deleteFinishedGame(id: UUID) {
        store.deleteFinished(id: id)
        finishedGames = store.loadFinished()
    }

    // MARK: - Scoring actions

    func peg(track: Int, points: Int, reason: PegReason, breakdown: ScoreBreakdown? = nil) {
        mutateGame { _ = try $0.peg(track: track, points: points, reason: reason, breakdown: breakdown) }
    }

    func completeHand() {
        mutateGame { try $0.completeHand() }
    }

    func undo() {
        guard var current = session else { return }
        _ = current.game.undo()
        session = current
        persist()
    }

    private func mutateGame(_ mutation: (inout Game) throws -> Void) {
        guard var current = session else { return }
        do {
            try mutation(&current.game)
            session = current
            persist()
        } catch {
            lastError = "\(error)"
        }
    }

    private func persist() {
        guard let session else { return }
        try? store.saveCurrent(session)
    }
}
