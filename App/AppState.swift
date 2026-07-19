import Foundation
import Observation
import UIKit
import CribbageEngine

/// A transient confirmation shown after each peg, with one-tap undo.
struct ToastMessage: Equatable, Identifiable {
    let id: UUID
    let text: String
    let undoable: Bool

    init(text: String, undoable: Bool = true) {
        self.id = UUID()
        self.text = text
        self.undoable = undoable
    }
}

/// Root observable state: owns the live session, persistence, and history.
@Observable
final class AppState {
    var session: LiveSession?
    private(set) var finishedGames: [Game] = []
    var lastError: String?
    var toast: ToastMessage?
    var selectedTab: AppTab = .game
    var selectedTrack = 0

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
        selectedTrack = 0
        persist()
    }

    /// Archives the finished game; starts the next match game when asked.
    func concludeGame(startNext: Bool) {
        guard var current = session, current.game.isOver else { return }
        do {
            try store.archive(current.game)
        } catch {
            lastError = "The finished game couldn't be archived: \(error.localizedDescription)"
        }
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
            persist()
        } else {
            session = nil
            store.clearCurrent()
        }
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
        guard var current = session else { return }
        do {
            try current.game.peg(track: track, points: points, reason: reason, breakdown: breakdown)
            session = current
            persist()
            let name = current.game.config.trackName(track)
            toast = ToastMessage(text: "+\(points) \(reason.label) — \(name)")
            announce("\(name) pegs \(points) for \(reason.label), now \(current.game.score(ofTrack: track))")
        } catch {
            // Game already over — the victory panel is showing.
        }
    }

    func completeHand() {
        guard var current = session else { return }
        do {
            try current.game.completeHand()
            session = current
            persist()
            let dealer = current.game.config.playerNames[current.game.dealerSeat]
            toast = ToastMessage(text: "Next hand — \(dealer) deals", undoable: false)
        } catch {}
    }

    func undo() {
        guard var current = session else { return }
        _ = current.game.undo()
        session = current
        toast = nil
        persist()
    }

    private func persist() {
        guard let session else { return }
        do {
            try store.saveCurrent(session)
        } catch {
            lastError = "The game couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
