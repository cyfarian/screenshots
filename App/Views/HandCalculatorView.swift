import SwiftUI
import CribbageEngine

/// Pick 4 hand cards + a starter and see the itemized count. While a game is
/// live the total can be pegged straight to any track, including the muggins
/// flow for under-claimed hands.
struct HandCalculatorView: View {
    @Environment(AppState.self) private var app

    @State private var selection: [Card] = []
    @State private var isCrib = false
    @State private var claimedPoints: Int?
    @State private var pegBusy = false

    private var hand: [Card] { Array(selection.prefix(4)) }
    private var starter: Card? { selection.count >= 5 ? selection[4] : nil }

    private var breakdown: ScoreBreakdown? {
        guard let starter, hand.count == 4 else { return nil }
        return HandScorer.score(hand: hand, starter: starter, isCrib: isCrib)
    }

    var body: some View {
        List {
            Section {
                CardPickerView(selection: $selection)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                statusRow
                Toggle("Score as crib", isOn: $isCrib)
                if !selection.isEmpty {
                    Button("Clear cards", role: .destructive) {
                        selection.removeAll()
                        claimedPoints = nil
                    }
                }
            } footer: {
                Text("Tap four cards for the hand, then a fifth for the starter.")
            }

            if let breakdown {
                breakdownSection(breakdown)
                if let starter, HandScorer.starterIsHeels(starter) {
                    Section {
                        Label("Starter is a jack — dealer pegs 2 for heels at the cut.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                if let game = app.session?.game, !game.isOver {
                    pegSection(breakdown: breakdown, game: game)
                }
            }
        }
        .navigationTitle("Count")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.selectedTab = .game
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Back to game")
            }
        }
        .onChange(of: selection) {
            claimedPoints = nil
        }
    }

    private var statusRow: some View {
        HStack {
            ForEach(0..<5, id: \.self) { slot in
                let label = slot < selection.count ? selection[slot].displayName : "—"
                Text(label)
                    .font(.callout.bold())
                    .foregroundStyle(
                        slot < selection.count && selection[slot].suit.isRed
                            ? Color.red : Color.primary
                    )
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(slot == 4 ? Color.orange.opacity(0.15) : Color.gray.opacity(0.12))
                    )
            }
        }
    }

    private func breakdownSection(_ breakdown: ScoreBreakdown) -> some View {
        Section("Count") {
            if breakdown.items.isEmpty {
                Text("Nineteen! (no points)")
                    .foregroundStyle(.secondary)
            }
            ForEach(breakdown.items) { item in
                HStack {
                    Text(item.label)
                    Text(item.cards.map(\.displayName).joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(item.points)")
                        .monospacedDigit()
                }
            }
            HStack {
                Text("Total").bold()
                Spacer()
                Text("\(breakdown.total)")
                    .font(.title3.bold().monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func pegSection(breakdown: ScoreBreakdown, game: Game) -> some View {
        let trackCount = game.config.mode.trackCount
        let track = min(app.selectedTrack, trackCount - 1)
        let trackName = game.config.trackName(track)
        Section("Score it") {
            // Who pegs: same selection as the game screen's score cards.
            HStack(spacing: 6) {
                ForEach(0..<trackCount, id: \.self) { t in
                    Button {
                        app.selectedTrack = t
                    } label: {
                        Text(game.config.trackName(t))
                            .font(.footnote.bold())
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(TrackStyle.color(t, config: game.config))
                    .opacity(t == track ? 1 : 0.45)
                    .accessibilityAddTraits(t == track ? .isSelected : [])
                }
            }

            Button {
                guardedPeg {
                    let reason: PegReason = isCrib ? .cribCount : .handCount
                    app.peg(track: track, points: breakdown.total, reason: reason, breakdown: breakdown)
                    finishPeg()
                }
            } label: {
                Label("Score \(breakdown.total) for \(trackName)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }
            .disabled(breakdown.total == 0 || pegBusy)

            if game.config.mugginsEnabled && breakdown.total > 0 {
                mugginsControls(breakdown: breakdown, track: track, game: game)
            }
        }
    }

    @ViewBuilder
    private func mugginsControls(breakdown: ScoreBreakdown, track: Int, game: Game) -> some View {
        let claimed = claimedPoints ?? breakdown.total
        Stepper(
            "Player claimed: \(claimed)",
            value: Binding(
                get: { claimedPoints ?? breakdown.total },
                set: { claimedPoints = $0 }
            ),
            in: 0...breakdown.total
        )
        if claimed < breakdown.total {
            let missed = breakdown.total - claimed
            ForEach(otherTracks(than: track, in: game), id: \.self) { other in
                Button("Muggins! \(game.config.trackName(other)) takes the missed \(missed)") {
                    guardedPeg {
                        let reason: PegReason = isCrib ? .cribCount : .handCount
                        if claimed > 0 {
                            app.peg(track: track, points: claimed, reason: reason, breakdown: breakdown)
                        }
                        app.peg(track: other, points: missed, reason: .muggins)
                        finishPeg()
                    }
                }
                .foregroundStyle(.orange)
                .disabled(pegBusy)
            }
        }
    }

    /// One peg action per breakdown — blocks accidental double-taps.
    private func guardedPeg(_ action: () -> Void) {
        guard !pegBusy else { return }
        pegBusy = true
        action()
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            pegBusy = false
        }
    }

    private func finishPeg() {
        selection.removeAll()
        claimedPoints = nil
        isCrib = false
        app.selectedTab = .game
    }

    private func otherTracks(than track: Int, in game: Game) -> [Int] {
        (0..<game.config.mode.trackCount).filter { $0 != track }
    }
}
