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

    func testClipKeepsTheRightSide() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let below = ScenePaths.bounds(ScenePaths.clip(square, level: 4, below: true))
        XCTAssertEqual(below.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(below.maxY, 4, accuracy: 0.0001)
        let above = ScenePaths.bounds(ScenePaths.clip(square, level: 4, below: false))
        XCTAssertEqual(above.minY, 4, accuracy: 0.0001)
        XCTAssertEqual(above.maxY, 10, accuracy: 0.0001)
        XCTAssertTrue(ScenePaths.clip(square, level: 20, below: false).isEmpty)
    }

    func testPolylineAboveOnlyKeepsTheTop() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let path = ScenePaths.polylineAbove(square, order: [0, 1, 2, 3, 0], level: 8)
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThanOrEqual(path.boundingBoxOfPath.minY, 8 - 0.0001)
        XCTAssertTrue(ScenePaths.polylineAbove(square, order: [0, 1, 2, 3, 0], level: 30).isEmpty)
    }

    func testPuddleBlobsMergeNearbyMarks() {
        let pts = [CGPoint(x: 300, y: 104), CGPoint(x: 310, y: 104), CGPoint(x: 305, y: 104), CGPoint(x: 500, y: 104)]
        let blobs = ScenePaths.puddleBlobs(pts, radius: 34)
        XCTAssertEqual(blobs.count, 2)
        XCTAssertEqual(blobs[0].count, 3)
        XCTAssertEqual(blobs[0].center.x, 305, accuracy: 0.001)
        XCTAssertEqual(blobs[1].count, 1)
        XCTAssertTrue(ScenePaths.puddleBlobs([], radius: 10).isEmpty)
    }

    func testWobbleLeavesTheSpoutAlone() {
        var pts: [CGPoint] = []
        var ws: [CGFloat] = []
        for i in 0..<30 { pts.append(CGPoint(x: 0, y: 400 - CGFloat(i) * 10)); ws.append(20) }
        var w = pts
        ScenePaths.wobble(&w, widths: ws, amplitude: 0.2, time: 1.3)
        XCTAssertEqual(w.count, pts.count)
        XCTAssertEqual(w[0].x, pts[0].x, accuracy: 0.0001)
        for p in w {
            XCTAssertTrue(p.x.isFinite)
            XCTAssertLessThanOrEqual(abs(p.x), 4.01)          // ≤ amplitude × width
        }
    }

    func testEveryVenueHasAPaletteAndDuskIsDark() {
        for v in VenueID.allCases {
            let p = ScenePalette.forVenue(v)
            XCTAssertEqual(p.venue, v)
            XCTAssertFalse(p.dusk)
            let d = p.duskified()
            XCTAssertTrue(d.dusk)
            XCTAssertTrue(d.isDark)
        }
    }

    @MainActor
    func testBackdropPaintsForEveryLook() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        for v in VenueID.allCases {
            let tex = SceneArt.backdrop(layout: layout, palette: ScenePalette.forVenue(v), dailyNumber: nil, scale: 1)
            XCTAssertGreaterThan(tex.size().width, 0)
        }
        let dusk = SceneArt.backdrop(layout: layout, palette: ScenePalette.forVenue(nil).duskified(), dailyNumber: 297, scale: 1)
        XCTAssertGreaterThan(dusk.size().height, 0)
        let phone = WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false)
        let tex = SceneArt.backdrop(layout: phone, palette: ScenePalette.forVenue(.conveyor), dailyNumber: 12, scale: 1)
        XCTAssertGreaterThan(tex.size().width, 0)
    }

    @MainActor
    func testSafeRangeMatchesThePhoneCrop() {
        let phone = GameScene(layout: WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false))
        XCTAssertGreaterThanOrEqual(phone.safeX.lowerBound, 125)
        XCTAssertLessThanOrEqual(phone.safeX.upperBound, 545)
        let duo = GameScene(layout: WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true))
        XCTAssertLessThan(duo.safeX.lowerBound, 30)
        XCTAssertGreaterThan(duo.safeX.upperBound, 640)
    }

    /// Drives a real session through the scene for a few seconds (pour, serve, FX) to catch runtime traps.
    @MainActor
    func testSceneRendersARealSession() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let modes: [GameMode] = [.shift(LevelCatalog.levels.first?.id ?? "1-1"), .rush, .daily(297)]
        for mode in modes {
            let session = GameSession(mode: mode, layout: layout, seed: 7)
            let scene = GameScene(layout: layout)
            let driver = SceneTestDriver(session)
            scene.driver = driver
            scene.reset(for: session.snapshot)
            var t: TimeInterval = 100
            for frame in 0..<(60 * 9) {
                let s = Double(frame) / 60
                // Flat first (the gate), then lift to pour, then lay flat again, repeatedly.
                let phase = s.truncatingRemainder(dividingBy: 3)
                driver.tilt = s < 0.5 ? 0 : (phase < 1.6 ? 48 : 0)
                t += 1.0 / 60.0
                scene.update(t)
            }
            XCTAssertFalse(scene.jugWorldBounds.isNull)
            scene.venue = .potionShop
            scene.rushLook = true
            scene.dailyNumber = 300
            scene.update(t + 1.0 / 60.0)
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
        scene.rushLook = true
        scene.dailyNumber = 297
        XCTAssertNil(scene.driver)
    }
}

/// Steps a real GameSession for the scene smoke test.
@MainActor
private final class SceneTestDriver: SceneDriver {
    let session: GameSession
    var tilt: Double = 0

    init(_ session: GameSession) {
        self.session = session
    }

    func advance(dt: Double, now: TimeInterval) -> (GameSnapshot, [GameEvent])? {
        let events = session.step(dt: dt, tilt: tilt)
        return (session.snapshot, events)
    }
}
