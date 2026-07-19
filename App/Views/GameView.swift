import SwiftUI
import UIKit
import CribbageEngine

/// Live game screen. Everything fits without scrolling: score cards, board
/// (flexing to the available space), and the peg pad.
struct GameView: View {
    @Environment(AppState.self) private var app
    @AppStorage("scoringHintSeen") private var scoringHintSeen = false
    @State private var showingAbandonConfirm = false

    var body: some View {
        Group {
            if let session = app.session {
                content(session: session)
            } else {
                ContentUnavailableView(
                    "No game in progress",
                    systemImage: "rectangle.dashed",
                    description: Text("Start a new game from the form.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAbandonConfirm = true
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("End or restart game")
            }
        }
        .confirmationDialog(
            "Abandon this game? It won't be saved.",
            isPresented: $showingAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) {
                app.abandonGame()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 4)
            }
        }
        .overlay {
            if !scoringHintSeen && app.hasLiveGame {
                ScoringHintOverlay(dismiss: { scoringHintSeen = true })
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private func content(session: LiveSession) -> some View {
        let game = session.game
        VStack(spacing: 8) {
            scoreHeader(game: game, match: session.match)
            BoardView(game: game, focusTrack: app.selectedTrack)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if game.isOver {
                GameOverPanel()
            } else {
                PegPadView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onAppear {
            if app.selectedTrack >= game.config.mode.trackCount {
                app.selectedTrack = 0
            }
        }
    }

    private func scoreHeader(game: Game, match: MatchState?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                ForEach(0..<game.config.mode.trackCount, id: \.self) { track in
                    scoreCard(game: game, track: track)
                }
            }
            HStack {
                Text("\(game.config.playerNames[game.dealerSeat]) deals")
                if let match {
                    Spacer()
                    Text(matchSummary(match, trackCount: game.config.mode.trackCount))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func scoreCard(game: Game, track: Int) -> some View {
        let selected = app.selectedTrack == track
        let isCrib = game.cribTrack == track
        return Button {
            app.selectedTrack = track
        } label: {
            VStack(spacing: 1) {
                Text(game.config.trackName(track) + (isCrib ? " · crib" : ""))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Text("\(game.score(ofTrack: track))")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(selected ? Color.white : TrackStyle.color(track, config: game.config))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? TrackStyle.color(track, config: game.config) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(TrackStyle.color(track, config: game.config), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(game: game, track: track, isCrib: isCrib))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityText(game: Game, track: Int, isCrib: Bool) -> String {
        var text = "\(game.config.trackName(track)): \(game.score(ofTrack: track)) points"
        if isCrib { text += ", has the crib" }
        return text
    }

    private func matchSummary(_ match: MatchState, trackCount: Int) -> String {
        let points = (0..<trackCount).map { "\(match.gamePoints(forTrack: $0))" }
        return "Match \(points.joined(separator: "–")) (best of \(match.config.bestOf))"
    }
}

/// Transient peg confirmation with one-tap undo.
struct ToastView: View {
    @Environment(AppState.self) private var app
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.subheadline.bold())
            if toast.undoable {
                Button("Undo") { app.undo() }
                    .font(.subheadline.bold())
                    .underline()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(.thinMaterial))
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if app.toast?.id == toast.id {
                app.toast = nil
            }
        }
    }
}

/// One-time explanation of the scoring flow.
struct ScoringHintOverlay: View {
    var dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("How scoring works")
                    .font(.headline)
                Text("1. Tap a player's card at the top — the colored outline shows who's pegging.")
                Text("2. Tap what they scored (15, Pair, Go…) — their peg advances instantly.")
                Text("3. Use Count hand to tally a full hand from the cards, and Undo to fix any mis-peg.")
                Button("Got it") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .font(.subheadline)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            .padding(28)
        }
    }
}

/// Shown in place of the peg pad once someone reaches the target score.
struct GameOverPanel: View {
    @Environment(AppState.self) private var app

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
            VStack(spacing: 10) {
                Label(
                    "\(name) wins \(game.score(ofTrack: winner))–\(loserScores(game, winner: winner))",
                    systemImage: "trophy"
                )
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
                        Button("Finish") { app.concludeGame(startNext: false) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.vertical, 8)
        )
    }

    private func loserScores(_ game: Game, winner: Int) -> String {
        (0..<game.config.mode.trackCount)
            .filter { $0 != winner }
            .map { "\(game.score(ofTrack: $0))" }
            .joined(separator: "–")
    }
}
