import SwiftUI
import UIKit
import CribbageEngine

/// The scoring controls: quick buttons for common pegging scores, a build-up
/// counter that zeroes out after each peg, hand counting, undo, next hand.
struct PegPadView: View {
    @Environment(AppState.self) private var app
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var customPoints = 0

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
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(TrackStyle.color(app.selectedTrack))
                    .accessibilityLabel("\(quick.label), \(quick.points) points")
                }
            }

            HStack(spacing: 6) {
                stepButton("minus") {
                    customPoints = max(0, customPoints - 1)
                }
                Button {
                    guard customPoints > 0 else { return }
                    peg(points: customPoints, reason: .manual)
                    customPoints = 0 // the counter zeroes out after the peg advances
                } label: {
                    Text(customPoints > 0 ? "Peg +\(customPoints)" : "Peg")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(TrackStyle.color(app.selectedTrack))
                .disabled(customPoints == 0)
                stepButton("plus") {
                    customPoints = min(29, customPoints + 1)
                }
            }

            HStack(spacing: 6) {
                Button {
                    app.undo()
                    haptic(.rigid)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!(app.session?.game.canUndo ?? false))

                Button {
                    app.selectedTab = .calc
                } label: {
                    Label("Count hand", systemImage: "square.grid.3x2")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)

                Button {
                    app.completeHand()
                    haptic(.light)
                } label: {
                    Label("Next hand", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 34)
        }
        .buttonStyle(.bordered)
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
