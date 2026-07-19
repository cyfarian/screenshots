import SwiftUI
import CribbageEngine

/// Pick 4 hand cards + a starter and see the itemized count. When opened from
/// a live game (`pegTarget` set) the total can be pegged directly, including
/// the muggins flow for under-claimed hands.
struct HandCalculatorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Track to peg for, when opened from a game. Nil = standalone calculator.
    let pegTarget: Int?

    @State private var selection: [Card] = []
    @State private var isCrib = false
    @State private var claimedPoints: Int?

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
                if let track = pegTarget, let game = app.session?.game, !game.isOver {
                    pegSection(breakdown: breakdown, track: track, game: game)
                }
            }
        }
        .navigationTitle("Hand Calculator")
        .navigationBarTitleDisplayMode(.inline)
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
    private func pegSection(breakdown: ScoreBreakdown, track: Int, game: Game) -> some View {
        let name = game.config.trackName(track)
        let mugginsOn = game.config.mugginsEnabled
        Section("Peg it") {
            Button {
                let reason: PegReason = isCrib ? .cribCount : .handCount
                app.peg(track: track, points: breakdown.total, reason: reason, breakdown: breakdown)
                dismiss()
            } label: {
                Label("Peg \(breakdown.total) for \(name)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }
            .disabled(breakdown.total == 0)

            if mugginsOn && breakdown.total > 0 {
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
            if claimed > 0 {
                Button("Peg claimed \(claimed) for \(name(of: track, in: game))") {
                    let reason: PegReason = isCrib ? .cribCount : .handCount
                    app.peg(track: track, points: claimed, reason: reason, breakdown: breakdown)
                }
            }
            ForEach(otherTracks(than: track, in: game), id: \.self) { other in
                Button("Muggins! \(name(of: other, in: game)) takes the missed \(missed)") {
                    app.peg(track: other, points: missed, reason: .muggins)
                    dismiss()
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private func name(of track: Int, in game: Game) -> String {
        game.config.trackName(track)
    }

    private func otherTracks(than track: Int, in game: Game) -> [Int] {
        (0..<game.config.mode.trackCount).filter { $0 != track }
    }
}
