import SwiftUI
import CribbageEngine

enum TrackStyle {
    static let palettes: [String: [Color]] = [
        "classic": [.red, .blue, .green],
        // Okabe–Ito hues: distinguishable with common color-vision deficiencies.
        "colorblind": [
            Color(red: 0.0, green: 0.447, blue: 0.698),
            Color(red: 0.902, green: 0.624, blue: 0.0),
            Color(red: 0.0, green: 0.62, blue: 0.451),
        ],
        "modern": [
            Color(red: 0.486, green: 0.302, blue: 1.0),
            Color(red: 0.0, green: 0.537, blue: 0.482),
            Color(red: 0.957, green: 0.318, blue: 0.118),
        ],
    ]

    static func color(_ track: Int) -> Color {
        let name = UserDefaults.standard.string(forKey: "palette") ?? "classic"
        let colors = palettes[name] ?? palettes["classic"]!
        return colors[track % colors.count]
    }
}

/// A traditional serpentine cribbage board. The front peg animates along the
/// track when points are scored.
struct BoardView: View {
    let game: Game

    /// In-flight front-peg animation for one track.
    private struct PegAnimation: Equatable {
        let track: Int
        let from: Int
        let to: Int
        let start: Date
    }

    private static let animationDuration: TimeInterval = 0.45

    @State private var animation: PegAnimation?

    private var layout: BoardLayout {
        BoardLayout(trackCount: game.config.mode.trackCount, targetScore: game.config.targetScore)
    }

    private var frontPegs: [Int] {
        (0..<game.config.mode.trackCount).map { game.pegPositions(ofTrack: $0).front }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
            Canvas { context, size in
                draw(context: context, size: size, now: timeline.date)
            }
        }
        .aspectRatio(layout.aspectRatio, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onChange(of: frontPegs) { old, new in
            for track in 0..<min(old.count, new.count) where old[track] != new[track] {
                animation = PegAnimation(track: track, from: old[track], to: new[track], start: Date())
            }
        }
        .accessibilityLabel(Text(boardSummary))
    }

    private var isAnimating: Bool {
        guard let animation else { return false }
        return Date().timeIntervalSince(animation.start) < Self.animationDuration
    }

    private var boardSummary: String {
        let parts = (0..<game.config.mode.trackCount)
            .map { "\(game.config.trackName($0)) at \(game.score(ofTrack: $0)) of \(game.config.targetScore)" }
        return "Cribbage board. " + parts.joined(separator: ", ") + "."
    }

    /// Front-peg distance for a track at a moment in time (fractional mid-animation).
    private func frontDistance(track: Int, now: Date) -> Double {
        let target = Double(game.pegPositions(ofTrack: track).front)
        guard let animation, animation.track == track else { return target }
        let elapsed = now.timeIntervalSince(animation.start)
        guard elapsed >= 0 && elapsed < Self.animationDuration else { return target }
        let t = elapsed / Self.animationDuration
        let eased = 1 - pow(1 - t, 3)
        return Double(animation.from) + (Double(animation.to) - Double(animation.from)) * eased
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, now: Date) {
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
        drawPegs(context: context, scale: scale, point: point, now: now)
    }

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
                with: .color(TrackStyle.color(track).opacity(0.34)),
                style: StrokeStyle(
                    lineWidth: 0.95 * layout.laneGap * scale,
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
                context.stroke(tick, with: .color(.secondary.opacity(0.8)), lineWidth: 1)
            }

            if hole % 10 == 0 && !skunkHoles.contains(hole) {
                let reach = halfWidth + 1.05
                let at = point((center.x + reach * normal.x, center.y + reach * normal.y))
                context.draw(
                    Text(verbatim: "\(hole)")
                        .font(.system(size: max(8, 0.58 * scale), weight: .semibold))
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
                let radius = (hole > 0 && hole % 5 == 0 ? 0.19 : 0.15) * layout.laneGap * scale
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.75)))
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
                Text(verbatim: marker.label)
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
            Text(verbatim: "START").font(font).foregroundStyle(.secondary),
            at: point((start.x, start.y + 1.3))
        )
        context.draw(
            Text(verbatim: "FINISH").font(font).foregroundStyle(.secondary),
            at: point((finish.x, finish.y + 1.3))
        )
        // Lane initials, so lanes aren't identified by color alone.
        for track in 0..<layout.trackCount {
            let p0 = layout.position(hole: 0, track: track)
            let initial = String(game.config.trackName(track).prefix(1)).uppercased()
            context.draw(
                Text(verbatim: initial)
                    .font(.system(size: max(8, 0.55 * scale), weight: .heavy))
                    .foregroundStyle(TrackStyle.color(track)),
                at: point((p0.x, p0.y + 0.62))
            )
        }
    }

    private func drawPegs(
        context: GraphicsContext, scale: CGFloat,
        point: ((x: Double, y: Double)) -> CGPoint,
        now: Date
    ) {
        for track in 0..<layout.trackCount {
            let color = TrackStyle.color(track)
            let pegs = game.pegPositions(ofTrack: track)
            let front = frontDistance(track: track, now: now)
            let backCenter = point(layout.position(hole: pegs.back, track: track))
            let frontCenter = point(layout.position(atDistance: front, track: track))
            for (center, isFront) in [(backCenter, false), (frontCenter, true)] {
                let radius = (isFront ? 0.42 : 0.32) * layout.laneGap * scale
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
