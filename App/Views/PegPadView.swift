import SwiftUI
import UIKit
import CribbageEngine

/// The scoring controls: quick buttons for common pegging scores, a custom
/// amount stepper, hand counting, undo, and next-hand.
struct PegPadView: View {
    @Environment(AppState.self) private var app
    @Binding var selectedTrack: Int
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var customPoints = 1

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
        QuickScore(label: "Last card", points: 1, reason: .lastCard),
        QuickScore(label: "31", points: 2, reason: .thirtyOne),
        QuickScore(label: "Nobs", points: 1, reason: .nobs),
        QuickScore(label: "Heels", points: 2, reason: .heels),
    ]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
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
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(TrackStyle.color(selectedTrack))
                }
            }

            HStack(spacing: 8) {
                Stepper("+\(customPoints)", value: $customPoints, in: 1...29)
                    .font(.headline.monospacedDigit())
                    .fixedSize()
                Button {
                    peg(points: customPoints, reason: .manual)
                } label: {
                    Text("Peg +\(customPoints)")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(TrackStyle.color(selectedTrack))
            }

            HStack(spacing: 8) {
                Button {
                    app.undo()
                    haptic(.rigid)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(!(app.session?.game.canUndo ?? false))

                NavigationLink {
                    HandCalculatorView(pegTarget: selectedTrack)
                } label: {
                    Label("Count hand", systemImage: "square.grid.3x2")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)

                Button {
                    app.completeHand()
                    haptic(.light)
                } label: {
                    Label("Next hand", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func peg(points: Int, reason: PegReason) {
        app.peg(track: selectedTrack, points: points, reason: reason)
        haptic(.medium)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
