import CoreGraphics
import SpriteKit
import XCTest
@testable import Brim

/// Scene geometry and cosmetic simulation (pure, no rendering), plus a smoke test that the scene builds.
final class SceneTests: XCTestCase {

    func testHalfWidthInterpolatesAndClamps() {
        let profile = [CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 100), CGPoint(x: 30, y: 140)]
        XCTAssertEqual(ScenePaths.halfWidth(profile, at: -5), 20, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.halfWidth(profile, at: 50), 25, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.halfWidth(profile, at: 120), 30, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.halfWidth(profile, at: 500), 30, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.halfWidth([], at: 10), 0, accuracy: 0.0001)
    }

    func testSmoothKeepsEndpointsAndAddsPoints() {
        let pts = [CGPoint(x: 0, y: 300), CGPoint(x: 10, y: 260), CGPoint(x: 18, y: 180), CGPoint(x: 22, y: 60)]
        let ws: [CGFloat] = [6, 7, 8, 8]
        let s = ScenePaths.smooth(pts, widths: ws, maxStep: 7)
        XCTAssertEqual(s.points.count, s.widths.count)
        XCTAssertGreaterThan(s.points.count, pts.count)
        XCTAssertEqual(s.points.first!.x, pts.first!.x, accuracy: 0.0001)
        XCTAssertEqual(s.points.last!.y, pts.last!.y, accuracy: 0.0001)
    }

    func testRibbonBuildsAClosedOutline() {
        let path = CGMutablePath()
        ScenePaths.addRibbon(path, points: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 50), CGPoint(x: 0, y: 0)],
                             widths: [10, 10, 10])
        XCTAssertFalse(path.isEmpty)
        let b = path.boundingBoxOfPath
        XCTAssertEqual(b.width, 10, accuracy: 1.5)
        XCTAssertGreaterThanOrEqual(b.height, 100)
    }

    func testRunsSplitOnGaps() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 200), CGPoint(x: 0, y: 210)]
        let r = ScenePaths.runs(pts, gap: 50)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0], 0..<2)
        XCTAssertEqual(r[1], 2..<4)
        XCTAssertTrue(ScenePaths.runs([], gap: 10).isEmpty)
    }

    func testOffsetPolygonGrowsBothWindings() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        for poly in [square, Array(square.reversed())] {
            let o = ScenePaths.bounds(ScenePaths.offsetPolygon(poly, by: 2))
            XCTAssertEqual(o.minX, -2, accuracy: 0.01)
            XCTAssertEqual(o.maxX, 12, accuracy: 0.01)
        }
    }

    func testLocalWorldRoundTrip() {
        let pivot = CGPoint(x: 375, y: 590)
        let p = CGPoint(x: 420, y: 650)
        let r: CGFloat = 0.7
        let back = ScenePaths.toWorld(ScenePaths.toLocal(p, pivot: pivot, radians: r), pivot: pivot, radians: r)
        XCTAssertEqual(back.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.0001)
        // Positive jug angle = clockwise on screen: a point to the right of the pivot moves down in world space.
        let w = ScenePaths.toWorld(CGPoint(x: 50, y: 0), pivot: .zero, radians: .pi / 2)
        XCTAssertEqual(w.y, -50, accuracy: 0.0001)
    }

    func testXOnPolygon() {
        let tri = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 10, y: 20)]
        XCTAssertEqual(ScenePaths.xOnPolygon(tri, atY: 10, rightmost: false) ?? -1, 5, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.xOnPolygon(tri, atY: 10, rightmost: true) ?? -1, 15, accuracy: 0.0001)
        XCTAssertNil(ScenePaths.xOnPolygon(tri, atY: 30, rightmost: true))
    }

    func testWaveSettlesAndKeepsTheLevelHonest() {
        var w = SceneWave()
        w.kick(at: 0.3, impulse: -40)
        w.slosh(20)
        w.step(1.0 / 120.0)
        XCTAssertGreaterThan(w.energy, 0.1)
        XCTAssertEqual(w.mean, 0, accuracy: 0.0001)
        for _ in 0..<(120 * 6) { w.step(1.0 / 120.0) }
        XCTAssertLessThan(w.energy, 0.2)
        XCTAssertEqual(w.mean, 0, accuracy: 0.0001)
        for x in w.h { XCTAssertTrue(x.isFinite) }
    }

    func testRNGIsDeterministicAndInRange() {
        var a = SceneRNG(seed: 42)
        var b = SceneRNG(seed: 42)
        for _ in 0..<100 {
            let x = a.unit()
            XCTAssertEqual(x, b.unit())
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThan(x, 1)
        }
    }

    @MainActor
    func testSceneBuildsAtLayoutSize() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), creaseFromTop: 455...495)
        let scene = GameScene(layout: layout)
        XCTAssertEqual(scene.size.width, layout.size.width, accuracy: 0.001)
        XCTAssertEqual(scene.size.height, layout.size.height, accuracy: 0.001)
        scene.reduceMotion = true
        scene.venue = .potionShop
        XCTAssertNil(scene.driver)
    }
}
