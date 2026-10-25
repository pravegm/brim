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

    func testPuddleRunsDecodeCoresEncoding() {
        // Core: each puddle is a left-to-right run of points 12 apart; separate puddles are further apart.
        let y: CGFloat = 104
        let pts = [CGPoint(x: 288, y: y), CGPoint(x: 300, y: y), CGPoint(x: 312, y: y),
                   CGPoint(x: 450, y: y),
                   CGPoint(x: 500, y: y), CGPoint(x: 512, y: y)]
        let runs = ScenePaths.puddleRuns(pts, spacing: 12)
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].center.x, 300, accuracy: 0.001)
        XCTAssertEqual(runs[0].halfSpan, 12, accuracy: 0.001)
        XCTAssertEqual(runs[0].count, 3)
        XCTAssertEqual(runs[1].halfSpan, 0, accuracy: 0.001)
        XCTAssertEqual(runs[2].center.x, 506, accuracy: 0.001)
        // A run that restarts to the left is a new puddle even if it overlaps.
        let back = ScenePaths.puddleRuns([CGPoint(x: 300, y: y), CGPoint(x: 312, y: y), CGPoint(x: 296, y: y),
                                          CGPoint(x: 308, y: y)], spacing: 12)
        XCTAssertEqual(back.count, 2)
        XCTAssertTrue(ScenePaths.puddleRuns([], spacing: 12).isEmpty)
    }

    func testStreamIsFatAtATypicalPourAndWiderForThickDrinks() {
        let coreMax = CGFloat(CoreTuning.streamWidthMax)
        // Core's width at the lip is max · √flow; a typical pour is flow ≈ 0.35.
        let typical = coreMax * CGFloat(0.35.squareRoot())
        let w = ScenePaths.streamDisplayWidth(typical, coreMax: coreMax, thick: false)
        XCTAssertGreaterThanOrEqual(w, 20)
        XCTAssertEqual(ScenePaths.streamDisplayWidth(coreMax, coreMax: coreMax, thick: false), 26, accuracy: 0.5)
        let thick = ScenePaths.streamDisplayWidth(typical, coreMax: coreMax, thick: true)
        XCTAssertEqual(thick / w, 1.6, accuracy: 0.05)
        XCTAssertEqual(ScenePaths.streamDisplayWidth(0, coreMax: coreMax, thick: false), 0, accuracy: 0.0001)
        var last: CGFloat = 0
        for i in 1...20 {
            let x = ScenePaths.streamDisplayWidth(coreMax * CGFloat(i) / 20, coreMax: coreMax, thick: false)
            XCTAssertGreaterThanOrEqual(x, last)
            last = x
        }
    }

    func testPillCutsAHoleAndDistances() {
        let pill = ScenePaths.pillClockwise(centerX: 0, minY: 0, maxY: 100, halfWidth: 15)
        XCTAssertLessThan(ScenePaths.signedArea(pill), 0)               // clockwise
        let b = ScenePaths.bounds(pill)
        XCTAssertEqual(b.width, 30, accuracy: 0.01)
        XCTAssertEqual(b.height, 100, accuracy: 0.01)
        XCTAssertEqual(ScenePaths.distanceToPolyline(CGPoint(x: 0, y: 5), [CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0)]),
                       5, accuracy: 0.0001)
        XCTAssertEqual(ScenePaths.distanceToSegment(CGPoint(x: 13, y: 4), CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0)),
                       5, accuracy: 0.0001)
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let below = ScenePaths.polylineBelow(square, order: [0, 1, 2, 3, 0], level: 3)
        XCTAssertFalse(below.isEmpty)
        XCTAssertLessThanOrEqual(below.boundingBoxOfPath.maxY, 3 + 0.0001)
    }

    /// ROUND-3 decision 3: no stamp or streak pop may reach the crease band, for every glass, on the Duo and phones,
    /// through the Perfect hop.
    @MainActor
    func testStampsAndStreakPopsStayOffTheCrease() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let keepOut = layout.creaseMinY - 8
        let cases: [(CGFloat, ClosedRange<CGFloat>)] = [(372, 14...656), (340, 130...540), (418, 130...540)]
        for shape in GlassCatalog.all {
            for (x, safe) in cases {
                let glass = SceneGlass(id: 1, darkBackdrop: false)
                let state = GlassState(id: 1, shape: shape, liquid: LiquidCatalog.liquid(.lemonade), x: x, phase: .served,
                                       liquidHeight: shape.interiorHeight * 0.7, foamHeight: 0,
                                       lineHeight: shape.interiorHeight * 0.7, lineOpacity: 1, inPerfectBand: true,
                                       overflowing: false, patienceLeft: nil, patienceTotal: nil, result: .perfect)
                var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: false, tail: nil,
                                   advanced: true, reduceMotion: false, band: 0.025, projected: nil, safeX: safe,
                                   keepOutTop: keepOut)
                glass.update(state, f)
                glass.celebrate()
                glass.showStreak(5, reduceMotion: false, safeX: safe, keepOutTop: keepOut)
                XCTAssertLessThanOrEqual(glass.lastStreakReachWorld ?? 0, keepOut + 0.5, "\(shape.id) streak at x \(x)")
                for k in 1...45 {
                    f.time = 1 + Double(k) / 60
                    glass.update(state, f)
                    XCTAssertLessThanOrEqual(glass.stampReachWorld ?? 0, keepOut + 0.5, "\(shape.id) stamp at x \(x)")
                }
            }
        }
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

    func testWobbleRespectsTheThickRopeCap() {
        var pts: [CGPoint] = []
        var ws: [CGFloat] = []
        for i in 0..<60 { pts.append(CGPoint(x: 0, y: 600 - CGFloat(i) * 10)); ws.append(46) }
        for k in 0..<10 {
            var w = pts
            ScenePaths.wobble(&w, widths: ws, amplitude: 0.14, time: CGFloat(k) * 0.37, maxOffset: 3)
            for p in w { XCTAssertLessThanOrEqual(abs(p.x), 3.01) }
        }
    }

    /// REVIEW-3 P1-2: a broken tail is 3–6 drops (not a bead chain), sized 60–100 %, spacing growing down the fall.
    @MainActor
    func testBrokenTailIsAFewVariedDropsWithGrowingSpacing() {
        XCTAssertEqual(SceneStream.dropCount(forLength: 10), 1)
        for len in stride(from: CGFloat(30), through: 600, by: 15) {
            let n = SceneStream.dropCount(forLength: len)
            XCTAssertGreaterThanOrEqual(n, 3)
            XCTAssertLessThanOrEqual(n, 6)
            XCTAssertEqual(SceneStream.dropOffset(0, of: n, length: len), 0, accuracy: 0.0001)   // starts at the lip
            var lastGap: CGFloat = 0
            for k in 1..<n {
                let gap = SceneStream.dropOffset(k, of: n, length: len) - SceneStream.dropOffset(k - 1, of: n, length: len)
                XCTAssertGreaterThan(gap, lastGap - 0.0001)
                lastGap = gap
            }
            XCTAssertLessThanOrEqual(SceneStream.dropOffset(n - 1, of: n, length: len), len)
        }
        for s in SceneStream.dropSizes {
            XCTAssertGreaterThanOrEqual(s, 0.6)
            XCTAssertLessThanOrEqual(s, 1.0)
        }
        XCTAssertNotEqual(SceneStream.dropSizes.min(), SceneStream.dropSizes.max())
        // Gone within ~0.4 s of the stop.
        XCTAssertLessThanOrEqual(SceneStream.tailFadeDelay + SceneStream.tailFade, 0.41)
    }

    /// A stopped stream draws without traps, then empties.
    @MainActor
    func testStoppedStreamBreaksUpAndClears() {
        let stream = SceneStream()
        let liquid = LiquidCatalog.liquid(.orangeJuice)
        var points: [StreamPoint] = []
        for i in 0..<40 { points.append(StreamPoint(position: CGPoint(x: 360, y: 560 - CGFloat(i) * 8), width: 10)) }
        stream.update(points: points, droplets: [], liquid: liquid, time: 1, landing: nil,
                      lip: CGPoint(x: 360, y: 560))
        for k in 1...30 {
            stream.update(points: points, droplets: [], liquid: liquid, time: 1 + Double(k) / 60, landing: nil, lip: nil)
        }
        XCTAssertFalse(stream.root.isHidden)
        stream.update(points: [], droplets: [], liquid: liquid, time: 2, landing: nil, lip: nil)
        XCTAssertTrue(stream.root.isHidden)
    }

    /// REVIEW-3 P1-1: the glass waiting in the slot is drawn smaller, lower and dimmer, and grows to full size as it
    /// slides to the stop.
    @MainActor
    func testWaitingGlassIsSmallerDimmerAndGrowsWhenItsTurnComes() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let shape = GlassCatalog.all[0]
        let glass = SceneGlass(id: 3, darkBackdrop: false)
        var state = GlassState(id: 3, shape: shape, liquid: LiquidCatalog.liquid(.lemonade), x: 165, phase: .arriving,
                               liquidHeight: 0, foamHeight: 0, lineHeight: shape.interiorHeight * 0.7, lineOpacity: 0,
                               inPerfectBand: false, overflowing: false, patienceLeft: nil, patienceTotal: nil, result: nil)
        XCTAssertTrue(state.isWaitingInSlot)
        var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: false, tail: nil, advanced: true,
                           reduceMotion: false, band: 0.025, projected: nil, safeX: 14...656,
                           keepOutTop: layout.creaseMinY - 8)
        f.waitingScale = 0.82
        f.waitingDrop = 10
        f.waitingAlpha = 0.6
        glass.update(state, f)
        XCTAssertEqual(glass.displayScale, 0.82, accuracy: 0.001)
        XCTAssertEqual(glass.dropY, 10, accuracy: 0.001)
        XCTAssertEqual(glass.drawnAlpha, 0.6, accuracy: 0.01)
        let small = glass.worldFrame
        XCTAssertLessThan(small.minY, layout.counterY - 6 - 9)

        // Its turn: the line appears and it slides; within 0.5 s it is a full-size, fully opaque glass.
        state.lineOpacity = 1
        for k in 1...30 {
            f.time = 1 + Double(k) / 60
            state.x = 165 + CGFloat(k) * 6.6
            glass.update(state, f)
        }
        XCTAssertEqual(glass.displayScale, 1, accuracy: 0.001)
        XCTAssertEqual(glass.dropY, 0, accuracy: 0.001)
        XCTAssertEqual(glass.drawnAlpha, 1, accuracy: 0.001)
        XCTAssertGreaterThan(glass.worldFrame.width, small.width * 1.15)
    }

    /// On a phone the waiting glass never sits on the bezel: its reported frame keeps clear of the crop.
    @MainActor
    func testWaitingGlassFrameStaysInsideThePhoneCrop() {
        let layout = WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false)
        let session = GameSession(mode: .shift(LevelCatalog.levels.first?.id ?? "1-1"), layout: layout, seed: 3)
        let scene = GameScene(layout: layout)
        let driver = SceneTestDriver(session)
        scene.driver = driver
        scene.reset(for: session.snapshot)
        var t: TimeInterval = 50
        for frame in 0..<(60 * 8) {
            let s = Double(frame) / 60
            driver.tilt = s < 0.5 ? 0 : (s.truncatingRemainder(dividingBy: 3) < 1.6 ? 48 : 0)
            t += 1.0 / 60.0
            scene.update(t)
            if let w = scene.waitingGlassWorldFrame {
                XCTAssertGreaterThanOrEqual(w.minX, layout.visibleRect.minX + 3.9)
                if let a = scene.activeGlassWorldFrame { XCTAssertLessThan(w.maxX, a.maxX) }
            }
        }
    }

    @MainActor
    func testGrownPuddleSpreadsPastTheCoaster() {
        XCTAssertGreaterThan(PuddleView.displayWidth(radius: 30), 160)
        XCTAssertGreaterThan(PuddleView.displayWidth(radius: 105), 330)
        XCTAssertGreaterThan(PuddleView.displayWidth(radius: 60), PuddleView.displayWidth(radius: 30))
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
            // Every signature vessel builds and draws (mid-pour).
            driver.tilt = 48
            for v in VenueID.allCases {
                scene.venue = v
                for _ in 0..<20 {
                    t += 1.0 / 60.0
                    scene.update(t)
                }
            }
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
