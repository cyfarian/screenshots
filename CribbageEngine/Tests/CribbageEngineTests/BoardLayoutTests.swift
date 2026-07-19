import XCTest
@testable import CribbageEngine

final class BoardLayoutTests: XCTestCase {

    func testAllPositionsInUnitSquareAndDistinct() {
        for trackCount in 1...3 {
            let layout = BoardLayout(trackCount: trackCount)
            var seen = Set<String>()
            for track in 0..<trackCount {
                for hole in 0...layout.targetScore {
                    let p = layout.position(hole: hole, track: track)
                    XCTAssertTrue(p.x > 0 && p.x < 1, "x out of range at hole \(hole)")
                    XCTAssertTrue(p.y > 0 && p.y < 1, "y out of range at hole \(hole)")
                    let key = "\(track):\(Int(p.x * 10_000)):\(Int(p.y * 10_000))"
                    XCTAssertTrue(seen.insert(key).inserted, "overlap at hole \(hole) track \(track)")
                }
            }
        }
    }

    func testSerpentineAlternatesDirection() {
        let layout = BoardLayout(trackCount: 2)
        // Row 0 flows left to right, row 1 right to left.
        let a = layout.position(hole: 0, track: 0)
        let b = layout.position(hole: 14, track: 0)
        XCTAssertLessThan(a.x, b.x)
        let c = layout.position(hole: 15, track: 0)
        let d = layout.position(hole: 29, track: 0)
        XCTAssertGreaterThan(c.x, d.x)
        // Hole 15 sits directly under hole 14 (same column, next row).
        XCTAssertEqual(b.x, c.x, accuracy: 0.0001)
        XCTAssertLessThan(b.y, c.y)
    }

    func testRowCount() {
        let layout = BoardLayout(trackCount: 2, columns: 15, targetScore: 121)
        XCTAssertEqual(layout.rowCount, 9) // 122 holes / 15 per row
        XCTAssertEqual(layout.row(ofHole: 0), 0)
        XCTAssertEqual(layout.row(ofHole: 121), 8)
    }

    func testTracksStackWithinRows() {
        let layout = BoardLayout(trackCount: 3)
        let t0 = layout.position(hole: 5, track: 0)
        let t1 = layout.position(hole: 5, track: 1)
        let t2 = layout.position(hole: 5, track: 2)
        XCTAssertEqual(t0.x, t1.x, accuracy: 0.0001)
        XCTAssertEqual(t1.x, t2.x, accuracy: 0.0001)
        XCTAssertLessThan(t0.y, t1.y)
        XCTAssertLessThan(t1.y, t2.y)
    }
}
