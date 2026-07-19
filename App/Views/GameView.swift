import SwiftUI
import CribbageEngine

struct GameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrack = 0
    @State private var showingHistory = false
    @State private var showingAbandonConfirm = false

    var body: some View {
        Group {
            if let session = app.session {
                content(session: session)
            } else {
                ContentUnavailableView(
                    "No game in progress",
                    systemImage: "rectangle.dashed",
                    description: Text("Start a new game from the home screen.")
                )
            }
        }
        .navigationTitle("Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Event history") { showingHistory = true }
                    Button("Abandon game", role: .destructive) { showingAbandonConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            EventHistorySheet()
        }
        .confirmationDialog(
            "Abandon this game?", isPresented: $showingAbandonConfirm, titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) {
                app.abandonGame()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(session: LiveSession) -> some View {
        let game = session.game
        VStack(spacing: 12) {
            scoreHeader(game: game, match: session.match)
            BoardView(game: game)
                .padding(.horizontal)
            if game.isOver {
                GameOverPanel(dismissGameView: { dismiss() })
            } else {
                PegPadView(selectedTrack: $selectedTrack)
            }
        }
        .onAppear {
            if selectedTrack >= game.config.mode.trackCount {
                selectedTrack = 0
            }
        }
    }

    private func scoreHeader(game: Game, match: MatchState?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ForEach(0..<game.config.mode.trackCount, id: \.self) { track in
                    scoreCard(game: game, track: track)
                }
            }
            .padding(.horizontal)
            HStack {
                Label(
                    "\(game.config.trackName(game.cribTrack))'s crib — \(game.config.playerNames[game.dealerSeat]) deals",
                    systemImage: "tray.full"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let match {
                    Spacer()
                    Text(matchSummary(match, trackCount: game.config.mode.trackCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func scoreCard(game: Game, track: Int) -> some View {
        let selected = selectedTrack == track
        return Button {
            selectedTrack = track
        } label: {
            VStack(spacing: 2) {
                Text(game.config.trackName(track))
                    .font(.caption)
                    .lineLimit(1)
                Text("\(game.score(ofTrack: track))")
                    .font(.title2.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TrackStyle.color(track).opacity(selected ? 0.25 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(TrackStyle.color(track), lineWidth: selected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private func matchSummary(_ match: MatchState, trackCount: Int) -> String {
        let points = (0..<trackCount).map { "\(match.gamePoints(forTrack: $0))" }
        return "Match \(points.joined(separator: "–")) (best of \(match.config.bestOf))"
    }
}

/// Shown in place of the peg pad once someone reaches the target score.
struct GameOverPanel: View {
    @Environment(AppState.self) private var app
    var dismissGameView: () -> Void

    var body: some View {
        guard let session = app.session, let winner = session.game.winnerTrack else {
            return AnyView(EmptyView())
        }
        let game = session.game
        let name = game.config.trackName(winner)
        let skunks = (0..<game.config.mode.trackCount)
            .compactMap { track -> String? in
                switch game.skunkResult(ofTrack: track) {
                case .skunk: return "\(game.config.trackName(track)) was skunked!"
                case .doubleSkunk: return "\(game.config.trackName(track)) was double-skunked!"
                default: return nil
                }
            }
        let trackCount = game.config.mode.trackCount
        let matchOngoing = session.match != nil
            && session.match!.winnerTrack(trackCount: trackCount) == nil

        return AnyView(
            VStack(spacing: 12) {
                Text("🏆 \(name) wins \(game.score(ofTrack: winner))–\(loserScores(game, winner: winner))")
                    .font(.title3.bold())
                ForEach(skunks, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(.orange)
                }
                HStack {
                    Button("Undo last peg") { app.undo() }
                        .buttonStyle(.bordered)
                    if matchOngoing {
                        Button("Next game") { app.concludeGame(startNext: true) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Finish") {
                            app.concludeGame(startNext: false)
                            dismissGameView()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        )
    }

    private func loserScores(_ game: Game, winner: Int) -> String {
        (0..<game.config.mode.trackCount)
            .filter { $0 != winner }
            .map { "\(game.score(ofTrack: $0))" }
            .joined(separator: "–")
    }
}

/// Reverse-chronological list of every peg event, with undo.
struct EventHistorySheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let game = app.session?.game {
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
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo last") { app.undo() }
                        .disabled(!(app.session?.game.canUndo ?? false))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
