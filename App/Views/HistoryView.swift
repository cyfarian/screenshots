import SwiftUI
import CribbageEngine

struct HistoryView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            if !app.stats.isEmpty {
                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("Player Stats", systemImage: "chart.bar.fill")
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
        .navigationTitle("History")
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
                Text("🏆 \(game.config.trackName(winner))")
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

struct StatsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            ForEach(app.stats) { player in
                Section(player.name) {
                    row("Record", "\(player.wins)–\(player.losses)")
                    row("Skunks given", "\(player.skunksGiven)")
                    row("Skunks taken", "\(player.skunksTaken)")
                    if player.handsCounted > 0 {
                        row("Average hand", String(format: "%.1f", player.averageHand))
                        row("Best hand", "\(player.bestHand)")
                    }
                }
            }
            if app.stats.isEmpty {
                Text("Finish a game to see stats.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Stats")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
