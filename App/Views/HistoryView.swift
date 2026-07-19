import SwiftUI
import CribbageEngine

/// Both histories in one place: the live game's pegging log, and the archive
/// of finished games with per-player stats.
struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var scope: Scope = .thisGame
    @State private var appliedDefaultScope = false

    enum Scope: Hashable {
        case thisGame, allGames
    }

    var body: some View {
        List {
            Section {
                Picker("History scope", selection: $scope) {
                    Text("This game").tag(Scope.thisGame)
                    Text("All games").tag(Scope.allGames)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if scope == .thisGame {
                thisGameSection
            } else {
                allGamesSections
            }
        }
        .navigationTitle("History")
        .onAppear {
            if !appliedDefaultScope {
                scope = app.hasLiveGame ? .thisGame : .allGames
                appliedDefaultScope = true
            }
        }
    }

    // MARK: - This game

    @ViewBuilder
    private var thisGameSection: some View {
        Section("This game's pegging") {
            if let game = app.session?.game {
                if game.events.isEmpty {
                    Text("Nothing pegged yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(game.events.reversed()) { event in
                    HStack {
                        Circle()
                            .fill(TrackStyle.color(event.trackIndex))
                            .frame(width: 10, height: 10)
                        Text(game.config.trackName(event.trackIndex))
                        Text(event.reason.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if event.points > 0 {
                            Text("+\(event.points)")
                                .monospacedDigit()
                                .bold()
                        }
                    }
                    .font(.subheadline)
                }
            } else {
                Text("No game in progress.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - All games

    @ViewBuilder
    private var allGamesSections: some View {
        ForEach(app.stats) { player in
            Section(player.name) {
                statRow("Record", "\(player.wins)–\(player.losses)")
                statRow("Skunks given / taken", "\(player.skunksGiven) / \(player.skunksTaken)")
                if player.handsCounted > 0 {
                    statRow("Average hand", String(format: "%.1f", player.averageHand))
                    statRow("Best hand", "\(player.bestHand)")
                }
            }
        }
        Section("Finished games") {
            if app.finishedGames.isEmpty {
                Text("No finished games yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.finishedGames) { game in
                    gameRow(game)
                }
                .onDelete { offsets in
                    // Resolve ids first: each delete reloads the array.
                    let ids = offsets.map { app.finishedGames[$0].id }
                    for id in ids {
                        app.deleteFinishedGame(id: id)
                    }
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func gameRow(_ game: Game) -> some View {
        let winner = game.winnerTrack ?? 0
        let scores = (0..<game.config.mode.trackCount)
            .map { "\(game.config.trackName($0)) \(game.score(ofTrack: $0))" }
            .joined(separator: "  •  ")
        let skunkNote = (0..<game.config.mode.trackCount)
            .compactMap { track -> String? in
                switch game.skunkResult(ofTrack: track) {
                case .skunk: return "skunk"
                case .doubleSkunk: return "double skunk"
                default: return nil
                }
            }
            .first

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(game.config.trackName(winner), systemImage: "trophy")
                    .font(.headline)
                if let skunkNote {
                    Text(skunkNote)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(
                    (game.completedAt ?? game.createdAt)
                        .formatted(date: .abbreviated, time: .shortened)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(scores)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
