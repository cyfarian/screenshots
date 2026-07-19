import Foundation

/// Pure geometry for a traditional serpentine cribbage board: vertical legs
/// joined by semicircular U-turns, with one parallel lane per track running
/// the whole path. The start is at the bottom-left, the finish at the
/// bottom-right. Hole 0 is the start position; holes 1...target are scoring
/// holes, spaced evenly along the path (1 board unit apart).
///
/// Coordinates are in "board units" with the origin at the top-left;
/// scale by `min(viewWidth / boardSize.width, viewHeight / boardSize.height)`
/// to render without distortion.
public struct BoardLayout: Sendable {
    public let trackCount: Int
    /// Number of vertical straight sections.
    public let legs: Int
    public let targetScore: Int
    /// Perpendicular distance between adjacent lanes.
    public let laneGap: Double = 1.0

    /// Horizontal distance between adjacent leg centerlines.
    private let columnSpacing: Double
    /// U-turn radius (semicircle joining adjacent legs).
    private let turnRadius: Double
    /// Length of each vertical leg.
    private let legLength: Double
    /// Widest lane offset from the centerline.
    private let maxLaneOffset: Double
    private let margin: Double = 1.6
    /// x of leg 0's centerline / y of the top of the legs.
    private let originX: Double
    private let legTopY: Double

    public init(trackCount: Int, legs: Int = 6, targetScore: Int = 121) {
        precondition(trackCount >= 1 && legs >= 2 && targetScore >= 1)
        self.trackCount = trackCount
        self.legs = legs
        self.targetScore = targetScore

        let trackWidth = Double(trackCount - 1) * laneGap
        columnSpacing = trackWidth + 2.5
        turnRadius = columnSpacing / 2
        let arcTotal = Double(legs - 1) * Double.pi * turnRadius
        legLength = (Double(targetScore) - arcTotal) / Double(legs)
        precondition(legLength > 1, "Too many legs for this target score")
        maxLaneOffset = trackWidth / 2
        originX = margin + maxLaneOffset
        legTopY = margin + maxLaneOffset + turnRadius
    }

    /// Total drawing area in board units.
    public var boardSize: (width: Double, height: Double) {
        (
            Double(legs - 1) * columnSpacing + 2 * (maxLaneOffset + margin),
            legLength + 2 * turnRadius + 2 * (maxLaneOffset + margin)
        )
    }

    /// width / height, for sizing a view container.
    public var aspectRatio: Double {
        let size = boardSize
        return size.width / size.height
    }

    /// Position of `hole` (0...targetScore) on `track`, in board units.
    public func position(hole: Int, track: Int) -> (x: Double, y: Double) {
        precondition(hole >= 0 && hole <= targetScore)
        precondition(track >= 0 && track < trackCount)
        return lanePoint(atDistance: Double(hole), track: track)
    }

    /// Centerline position at a hole (midway between the lanes), for ticks
    /// and labels that span the whole track.
    public func centerPosition(hole: Int) -> (x: Double, y: Double) {
        precondition(hole >= 0 && hole <= targetScore)
        return centerPoint(atDistance: Double(hole))
    }

    /// Unit vector perpendicular to the path at a hole (for tick marks).
    public func perpendicular(atHole hole: Int) -> (x: Double, y: Double) {
        normalVector(atDistance: Double(hole))
    }

    /// Dense polyline along one lane, for drawing the track ribbon.
    public func lanePoints(track: Int, samplesPerUnit: Int = 4) -> [(x: Double, y: Double)] {
        let total = Double(targetScore)
        let count = Int(total) * samplesPerUnit
        return (0...count).map { i in
            lanePoint(atDistance: total * Double(i) / Double(count), track: track)
        }
    }

    // MARK: - Path math

    /// Signed lane offset from the centerline for a track.
    private func laneOffset(_ track: Int) -> Double {
        (Double(track) - Double(trackCount - 1) / 2) * laneGap
    }

    private func lanePoint(atDistance d: Double, track: Int) -> (x: Double, y: Double) {
        let p = centerPoint(atDistance: d)
        let n = normalVector(atDistance: d)
        let e = laneOffset(track)
        return (p.x + e * n.x, p.y + e * n.y)
    }

    /// Locates the segment (leg or U-turn) containing distance `d`, returning
    /// the segment index and the distance into it. Even segments are legs;
    /// odd segments are turns.
    private func locate(_ d: Double) -> (segment: Int, offset: Double) {
        var remaining = max(0, min(d, Double(targetScore)))
        var segment = 0
        while true {
            let length = segment % 2 == 0 ? legLength : Double.pi * turnRadius
            let isLast = segment == 2 * (legs - 1)
            if remaining <= length || isLast {
                return (segment, min(remaining, length))
            }
            remaining -= length
            segment += 1
        }
    }

    private func centerPoint(atDistance d: Double) -> (x: Double, y: Double) {
        let (segment, offset) = locate(d)
        let legIndex = segment / 2
        let x = originX + Double(legIndex) * columnSpacing
        let yBottom = legTopY + legLength
        if segment % 2 == 0 {
            // Vertical leg: even legs travel up, odd legs travel down.
            return legIndex % 2 == 0
                ? (x, yBottom - offset)
                : (x, legTopY + offset)
        }
        let cx = x + columnSpacing / 2
        if legIndex % 2 == 0 {
            // Top U-turn, sweeping over the top from this leg to the next.
            let phi = Double.pi - offset / turnRadius
            return (cx + turnRadius * cos(phi), legTopY - turnRadius * sin(phi))
        } else {
            // Bottom U-turn, sweeping under the bottom.
            let phi = Double.pi + offset / turnRadius
            return (cx + turnRadius * cos(phi), yBottom - turnRadius * sin(phi))
        }
    }

    private func normalVector(atDistance d: Double) -> (x: Double, y: Double) {
        let (segment, offset) = locate(d)
        let legIndex = segment / 2
        if segment % 2 == 0 {
            return legIndex % 2 == 0 ? (-1, 0) : (1, 0)
        }
        if legIndex % 2 == 0 {
            let phi = Double.pi - offset / turnRadius
            return (cos(phi), -sin(phi))
        } else {
            let phi = Double.pi + offset / turnRadius
            return (-cos(phi), sin(phi))
        }
    }
}
