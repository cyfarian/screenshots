import Foundation

/// Pure geometry for drawing the board: normalized (0...1) coordinates for
/// every peg hole on every track, arranged as a serpentine of rows.
/// Hole 0 is the start position; holes 1...target are scoring holes.
public struct BoardLayout: Sendable {
    public let trackCount: Int
    public let columns: Int
    public let targetScore: Int

    public init(trackCount: Int, columns: Int = 15, targetScore: Int = 121) {
        precondition(trackCount >= 1 && columns >= 2 && targetScore >= 1)
        self.trackCount = trackCount
        self.columns = columns
        self.targetScore = targetScore
    }

    /// Total holes per track including the start hole.
    public var holesPerTrack: Int { targetScore + 1 }

    /// Number of serpentine rows.
    public var rowCount: Int { (holesPerTrack + columns - 1) / columns }

    /// Row (0-based, top to bottom) containing a hole.
    public func row(ofHole hole: Int) -> Int { hole / columns }

    /// Normalized position of `hole` (0...targetScore) on `track`.
    /// x and y are in 0...1; multiply by the rendered size to get points.
    public func position(hole: Int, track: Int) -> (x: Double, y: Double) {
        precondition(hole >= 0 && hole <= targetScore)
        precondition(track >= 0 && track < trackCount)
        let r = hole / columns
        var c = hole % columns
        if r % 2 == 1 { c = columns - 1 - c }
        let lanes = rowCount * trackCount
        let lane = r * trackCount + track
        let x = (Double(c) + 0.5) / Double(columns)
        let y = (Double(lane) + 0.5) / Double(lanes)
        return (x, y)
    }

    /// Whether the serpentine flows left-to-right in the given row.
    public func rowIsLeftToRight(_ row: Int) -> Bool { row % 2 == 0 }
}
