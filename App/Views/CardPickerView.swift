import SwiftUI
import CribbageEngine

/// A 52-card grid. Tap to select in order: first four cards are the hand,
/// the fifth is the starter. Tap a selected card to deselect it.
struct CardPickerView: View {
    @Binding var selection: [Card]

    private let ranks = Rank.allCases
    private let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(suits, id: \.self) { suit in
                GridRow {
                    ForEach(ranks, id: \.self) { rank in
                        cardCell(Card(rank, suit))
                    }
                }
            }
        }
    }

    private func cardCell(_ card: Card) -> some View {
        let index = selection.firstIndex(of: card)
        let isStarter = index == 4
        return Button {
            toggle(card)
        } label: {
            VStack(spacing: 0) {
                Text(card.rank.symbol)
                    .font(.caption.bold())
                Text(card.suit.symbol)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(card.suit.isRed ? Color.red : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(background(index: index, isStarter: isStarter))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        index == nil ? Color.gray.opacity(0.3)
                            : isStarter ? Color.orange : Color.accentColor,
                        lineWidth: index == nil ? 0.5 : 2
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(index == nil && selection.count >= 5)
    }

    private func background(index: Int?, isStarter: Bool) -> Color {
        guard index != nil else { return Color(.systemBackground) }
        return isStarter ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.15)
    }

    private func toggle(_ card: Card) {
        if let index = selection.firstIndex(of: card) {
            selection.remove(at: index)
        } else if selection.count < 5 {
            selection.append(card)
        }
    }
}
