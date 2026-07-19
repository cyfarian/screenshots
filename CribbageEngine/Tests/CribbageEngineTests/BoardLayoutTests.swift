import XCTest
@testable import CribbageEngine

final class BoardLayoutTests: XCTestCase {

    func testAllPositionsInsideBoardAndDistinct() {
        for trackCount in 1...3 {
            let layout = BoardLayout(trackCount: trackCount)
            let size = layout.boardSize
            var seen = Set<String>()
            for track in 0..<trackCount {
                for hole in 0...layout.targetScore {
                    let p = layout.position(hole: hole, track: track)
                    XCTAssertTrue(p.x > 0 && p.x < size.width, "x out of bounds at hole \(hole)")
                    XCTAssertTrue(p.y > 0 && p.y < size.height, "y out of bounds at hole \(hole)")
                    let key = "\(track):\(Int(p.x * 1000)):\(Int(p.y * 1000))"
                    XCTAssertTrue(seen.insert(key).inserted, "overlap at hole \(hole) track \(track)")
                }
            }
        }
    }

    func testStartsBottomLeftFinishesBottomRight() {
        let layout = BoardLayout(trackCount: 2)
        let size = layout.boardSize
        let start = layout.centerPosition(hole: 0)
        let finish = layout.centerPosition(hole: layout.targetScore)
        XCTAssertLessThan(start.x, size.width * 0.3)
        XCTAssertGreaterThan(start.y, size.height * 0.55)
        XCTAssertGreaterThan(finish.x, size.width * 0.7)
        XCTAssertGreaterThan(finish.y, size.height * 0.55)
    }

    func testConsecutiveHolesEvenlySpacedAlongPath() {
        let layout = BoardLayout(trackCount: 2)
        for hole in 0..<layout.targetScore {
            let a = layout.centerPosition(hole: hole)
            let b = layout.centerPosition(hole: hole + 1)
            let distance = hypot(a.x - b.x, a.y - b.y)
            // Straight sections: exactly 1 unit apart. Turns: chords of the
            // arc, slightly shorter but never collapsed or stretched.
            XCTAssertGreaterThan(distance, 0.5, "holes \(hole)-\(hole + 1) collapsed")
            XCTAssertLessThan(distance, 1.01, "holes \(hole)-\(hole + 1) too far apart")
        }
    }

    func testLanesKeepConstantSeparation() {
        let layout = BoardLayout(trackCount: 3)
        for hole in 0...layout.targetScore {
            let a = layout.position(hole: hole, track: 0)
            let b = layout.position(hole: hole, track: 1)
            let c = layout.position(hole: hole, track: 2)
            XCTAssertEqual(hypot(a.x - b.x, a.y - b.y), layout.laneGap, accuracy: 0.0001)
            XCTAssertEqual(hypot(b.x - c.x, b.y - c.y), layout.laneGap, accuracy: 0.0001)
        }
    }

    func testPerpendicularIsUnitLength() {
        let layout = BoardLayout(trackCount: 2)
        for hole in stride(from: 0, through: layout.targetScore, by: 7) {
            let n = layout.perpendicular(atHole: hole)
            XCTAssertEqual(hypot(n.x, n.y), 1.0, accuracy: 0.0001)
        }
    }

    func testLanePointsStayInsideBoard() {
        let layout = BoardLayout(trackCount: 2)
        let size = layout.boardSize
        for track in 0..<2 {
            let points = layout.lanePoints(track: track)
            XCTAssertGreaterThan(points.count, 200)
            for p in points {
                XCTAssertTrue(p.x > 0 && p.x < size.width)
                XCTAssertTrue(p.y > 0 && p.y < size.height)
            }
        }
    }

    func testAspectRatioRoughlySquareForTwoTracks() {
        let layout = BoardLayout(trackCount: 2)
        XCTAssertGreaterThan(layout.aspectRatio, 0.6)
        XCTAssertLessThan(layout.aspectRatio, 1.6)
    }
}
