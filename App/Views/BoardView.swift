import SwiftUI
import CribbageEngine

enum TrackStyle {
    static let colors: [Color] = [.red, .blue, .green]

    static func color(_ track: Int) -> Color {
        colors[track % colors.count]
    }
}

/// The pegging board: serpentine rows of holes with two pegs per track,
/// plus skunk (S) and double-skunk (SS) markers.
struct BoardView: View {
    let game: Game

    private var layout: BoardLayout {
        BoardLayout(trackCount: game.config.mode.trackCount, targetScore: game.config.targetScore)
    }

    var body: some View {
        Canvas { context, size in
            drawHoles(context: context, size: size)
            drawSkunkMarkers(context: context, size: size)
            drawPegs(context: context, size: size)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private var aspectRatio: CGFloat {
        // Wider than tall; more lanes need more height.
        let lanes = CGFloat(layout.rowCount * layout.trackCount)
        return max(1.0, 34.0 / lanes)
    }

    private func point(hole: Int, track: Int, size: CGSize) -> CGPoint {
        let p = layout.position(hole: hole, track: track)
        return CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func drawHoles(context: GraphicsContext, size: CGSize) {
        for track in 0..<layout.trackCount {
            let color = TrackStyle.color(track)
            for hole in 0...layout.targetScore {
                let center = point(hole: hole, track: track, size: size)
                // Emphasize every 5th hole the way boards group holes in fives.
                let radius: CGFloat = hole > 0 && hole % 5 == 0 ? 2.4 : 1.7
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(hole == 0 ? 0.9 : 0.25))
                )
            }
        }
    }

    private func drawSkunkMarkers(context: GraphicsContext, size: CGSize) {
        let markers: [(hole: Int, label: String)] = [
            (game.config.skunkThreshold - 1, "S"),
            (game.config.doubleSkunkThreshold - 1, "SS"),
        ]
        for marker in markers {
            guard marker.hole > 0 && marker.hole < game.config.targetScore else { continue }
            let top = point(hole: marker.hole, track: 0, size: size)
            let bottom = point(hole: marker.hole, track: layout.trackCount - 1, size: size)
            var line = Path()
            line.move(to: CGPoint(x: top.x, y: top.y - 6))
            line.addLine(to: CGPoint(x: bottom.x, y: bottom.y + 6))
            context.stroke(line, with: .color(.orange.opacity(0.8)), lineWidth: 1.5)
            context.draw(
                Text(marker.label).font(.system(size: 8, weight: .bold)).foregroundStyle(.orange),
                at: CGPoint(x: top.x, y: top.y - 12)
            )
        }
    }

    private func drawPegs(context: GraphicsContext, size: CGSize) {
        for track in 0..<layout.trackCount {
            let color = TrackStyle.color(track)
            let pegs = game.pegPositions(ofTrack: track)
            for (position, isFront) in [(pegs.back, false), (pegs.front, true)] {
                let center = point(hole: position, track: track, size: size)
                let radius: CGFloat = isFront ? 5 : 4
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
                if isFront {
                    context.stroke(
                        Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)),
                        with: .color(color.opacity(0.5)),
                        lineWidth: 1.5
                    )
                }
            }
        }
    }
}
