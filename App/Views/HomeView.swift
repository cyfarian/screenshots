import SwiftUI
import CribbageEngine

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var showingNewGame = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let session = app.session {
                        NavigationLink {
                            GameView()
                        } label: {
                            liveGameRow(session)
                        }
                    }
                    Button {
                        showingNewGame = true
                    } label: {
                        Label(app.hasLiveGame ? "Start Over" : "New Game", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                Section("Tools") {
                    NavigationLink {
                        HandCalculatorView(pegTarget: nil)
                    } label: {
                        Label("Hand Calculator", systemImage: "square.grid.3x2")
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("History & Stats", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Cribbage")
            .sheet(isPresented: $showingNewGame) {
                NewGameSheet()
            }
        }
    }

    private func liveGameRow(_ session: LiveSession) -> some View {
        let game = session.game
        let names = (0..<game.config.mode.trackCount)
            .map { "\(game.config.trackName($0)) \(game.score(ofTrack: $0))" }
        return VStack(alignment: .leading, spacing: 4) {
            Label("Resume Game", systemImage: "play.circle.fill")
                .font(.headline)
            Text(names.joined(separator: "  •  "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let match = session.match {
                Text("Match: best of \(match.config.bestOf), game \(match.results.count + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
