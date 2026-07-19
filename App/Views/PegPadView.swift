import SwiftUI
import UIKit
import CribbageEngine

/// The scoring controls, in one of two styles:
/// - "numbers": big +1…+5 buttons build a pending total; Peg commits it.
/// - "named": combo buttons (15, Pair, …) peg instantly, plus a stepper.
/// The pending counter zeroes out after each commit.
struct PegPadView: View {
    @Environment(AppState.self) private var app
    @AppStorage("scoreStyle") private var scoreStyle = "numbers"
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var pending = 0

    private struct QuickScore: Identifiable {
        let label: String
        let points: Int
        let reason: PegReason
        var id: String { label }
    }

    private let quickScores: [QuickScore] = [
        QuickScore(label: "15", points: 2, reason: .fifteen),
        QuickScore(label: "Pair", points: 2, reason: .pair),
        QuickScore(label: "Run 3", points: 3, reason: .run(3)),
        QuickScore(label: "Run 4", points: 4, reason: .run(4)),
        QuickScore(label: "Run 5", points: 5, reason: .run(5)),
        QuickScore(label: "Go", points: 1, reason: .go),
        QuickScore(label: "Last", points: 1, reason: .lastCard),
        QuickScore(label: "31", points: 2, reason: .thirtyOne),
        QuickScore(label: "Nobs", points: 1, reason: .nobs),
        QuickScore(label: "Heels", points: 2, reason: .heels),
    ]

    var body: some View {
        VStack(spacing: 8) {
            if scoreStyle == "numbers" {
                numbersPad
            } else {
                namedPad
            }
            actionRow
        }
        .onChange(of: app.selectedTrack) {
            pending = 0 // pending points belong to a player
        }
        .onChange(of: scoreStyle) {
            pending = 0
        }
    }

    // MARK: - Numbers style

    private var numbersPad: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        pending = min(29, pending + n)
                    } label: {
                        Text("+\(n)")
                            .font(.title2.bold().monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrackStyle.color(app.selectedTrack))
                    .accessibilityLabel("Add \(n) points")
                }
            }
            HStack(spacing: 6) {
                Button {
                    pending = 0
                } label: {
                    Image(systemName: "delete.left")
                        .frame(width: 56, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.darkGray))
                .disabled(pending == 0)
                .accessibilityLabel("Clear pending points")

                commitButton(minHeight: 44)
            }
        }
    }

    // MARK: - Named style

    private var namedPad: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(quickScores) { quick in
                    Button {
                        peg(points: quick.points, reason: quick.reason)
                    } label: {
                        VStack(spacing: 0) {
                            Text(quick.label)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("+\(quick.points)")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrackStyle.color(app.selectedTrack))
                    .accessibilityLabel("\(quick.label), \(quick.points) points")
                }
            }
            HStack(spacing: 6) {
                stepButton("minus") {
                    pending = max(0, pending - 1)
                }
                commitButton(minHeight: 36)
                stepButton("plus") {
                    pending = min(29, pending + 1)
                }
            }
        }
    }

    // MARK: - Shared pieces

    private func commitButton(minHeight: CGFloat) -> some View {
        Button {
            guard pending > 0 else { return }
            peg(points: pending, reason: .manual)
            pending = 0 // the counter zeroes out after the peg advances
        } label: {
            Text(pending > 0 ? "Peg +\(pending)" : "Peg")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(TrackStyle.color(app.selectedTrack))
        .disabled(pending == 0)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button {
                app.undo()
                haptic(.rigid)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .disabled(!(app.session?.game.canUndo ?? false))

            Button {
                app.selectedTab = .calc
            } label: {
                Label("Count hand", systemImage: "square.grid.3x2")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }

            Button {
                app.completeHand()
                haptic(.light)
            } label: {
                Label("Next hand", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
        }
        .font(.footnote.bold())
        .buttonStyle(.borderedProminent)
        .tint(Color(.darkGray))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(.darkGray))
        .accessibilityLabel(symbol == "plus" ? "Increase points" : "Decrease points")
    }

    private func peg(points: Int, reason: PegReason) {
        app.peg(track: app.selectedTrack, points: points, reason: reason)
        haptic(.medium)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
