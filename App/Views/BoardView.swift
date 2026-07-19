import SwiftUI
import CribbageEngine

enum TrackStyle {
    static let colors: [Color] = [.red, .blue, .green]

    static func color(_ track: Int) -> Color {
        colors[track % colors.count]
    }
}

/// A traditional serpentine cribbage board: parallel colored lanes winding
/// through U-turns, hole dots grouped in fives, milestone numbers, skunk
/// lines, and two pegs per track. All geometry comes from `BoardLayout`.
struct BoardView: View {
    let game: Game

    private var layout: BoardLayout {
        BoardLayout(trackCount: game.config.mode.trackCount, targetScore: game.config.targetScore)
    }

    var body: some View {
        Canvas { context, size in
            let board = layout.boardSize
            let scale = min(size.width / board.width, size.height / board.height)
            let offsetX = (size.width - board.width * scale) / 2
            let offsetY = (size.height - board.height * scale) / 2
            let point: ((x: Double, y: Double)) -> CGPoint = { p in
                CGPoint(x: offsetX + p.x * scale, y: offsetY + p.y * scale)
            }

            drawRibbons(context: context, scale: scale, point: point)
            drawTicksAndLabels(context: context, scale: scale, point: point)
            drawHoles(context: context, scale: scale, point: point)
            drawSkunkLines(context: context, scale: scale, point: point)
            drawStartFinish(context: context, scale: scale, point: point)
            drawPegs(context: context, scale: scale, point: point)
        }
        .aspectRatio(layout.aspectRatio, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Layers

    private func drawRibbons(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        for track in 0..<layout.trackCount {
            let samples = layout.lanePoints(track: track)
            var path = Path()
            path.move(to: point(samples[0]))
            for sample in samples.dropFirst() {
                path.addLine(to: point(sample))
            }
            context.stroke(
                path,
                with: .color(TrackStyle.color(track).opacity(0.18)),
                style: StrokeStyle(
                    lineWidth: 0.82 * layout.laneGap * scale,
                    lineCap: .round, lineJoin: .round
                )
            )
        }
    }

    private func drawTicksAndLabels(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        let skunkHoles: Set<Int> = [
            game.config.skunkThreshold - 1, game.config.doubleSkunkThreshold - 1,
        ]
        let halfWidth = Double(layout.trackCount - 1) * layout.laneGap / 2

        for hole in stride(from: 5, to: layout.targetScore, by: 5) {
            let center = layout.centerPosition(hole: hole)
            let normal = layout.perpendicular(atHole: hole)

            if !skunkHoles.contains(hole) {
                let reach = halfWidth + 0.55
                var tick = Path()
                tick.move(to: point((center.x + reach * normal.x, center.y + reach * normal.y)))
                tick.addLine(to: point((center.x - reach * normal.x, center.y - reach * normal.y)))
                context.stroke(tick, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            }

            if hole % 10 == 0 {
                let reach = halfWidth + 1.05
                let at = point((center.x + reach * normal.x, center.y + reach * normal.y))
                context.draw(
                    Text("\(hole)")
                        .font(.system(size: max(7, 0.5 * scale), weight: .medium))
                        .foregroundStyle(.secondary),
                    at: at
                )
            }
        }
    }

    private func drawHoles(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        for track in 0..<layout.trackCount {
            for hole in 0...layout.targetScore {
                let center = point(layout.position(hole: hole, track: track))
                let radius = (hole > 0 && hole % 5 == 0 ? 0.16 : 0.12) * layout.laneGap * scale
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.45)))
            }
        }
    }

    private func drawSkunkLines(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        let halfWidth = Double(layout.trackCount - 1) * layout.laneGap / 2
        let markers: [(hole: Int, label: String)] = [
            (game.config.skunkThreshold - 1, "S"),
            (game.config.doubleSkunkThreshold - 1, "SS"),
        ]
        for marker in markers where marker.hole > 0 && marker.hole < layout.targetScore {
            let center = layout.centerPosition(hole: marker.hole)
            let normal = layout.perpendicular(atHole: marker.hole)
            let reach = halfWidth + 0.7
            var line = Path()
            line.move(to: point((center.x + reach * normal.x, center.y + reach * normal.y)))
            line.addLine(to: point((center.x - reach * normal.x, center.y - reach * normal.y)))
            context.stroke(line, with: .color(.orange), lineWidth: max(2, 0.12 * scale))
            let labelAt = point((
                center.x + (reach + 0.55) * normal.x,
                center.y + (reach + 0.55) * normal.y
            ))
            context.draw(
                Text(marker.label)
                    .font(.system(size: max(7, 0.45 * scale), weight: .bold))
                    .foregroundStyle(.orange),
                at: labelAt
            )
        }
    }

    private func drawStartFinish(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        let start = layout.centerPosition(hole: 0)
        let finish = layout.centerPosition(hole: layout.targetScore)
        let font = Font.system(size: max(7, 0.42 * scale), weight: .semibold)
        context.draw(
            Text("START").font(font).foregroundStyle(.secondary),
            at: point((start.x, start.y + 0.9))
        )
        context.draw(
            Text("FINISH").font(font).foregroundStyle(.secondary),
            at: point((finish.x, finish.y + 0.9))
        )
    }

    private func drawPegs(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint
    ) {
        for track in 0..<layout.trackCount {
            let color = TrackStyle.color(track)
            let pegs = game.pegPositions(ofTrack: track)
            for (position, isFront) in [(pegs.back, false), (pegs.front, true)] {
                let center = point(layout.position(hole: position, track: track))
                let radius = (isFront ? 0.36 : 0.28) * layout.laneGap * scale
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: max(1, 0.06 * scale)
                )
            }
        }
    }
}
