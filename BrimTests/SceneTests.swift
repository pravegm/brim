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

    // MARK: Round 5

    /// ROUND-5 decision 4 + QA-2 P2-15: an "OVER" stamp exists, and the streak pop says "7 IN A ROW".
    @MainActor
    func testStampWordsAndStreakCopy() {
        let all: [Judgement] = [.perfect, .great, .good, .short, .over, .spill]
        var words = Set<String>()
        for j in all {
            words.insert(SceneArt.stampText(j))
            let art = SceneArt.stamp(j)
            XCTAssertGreaterThan(art.size.width, 0)
            XCTAssertGreaterThan(art.size.height, 0)
        }
        XCTAssertEqual(words.count, all.count)
        XCTAssertEqual(SceneArt.stampText(.over), "OVER")
        XCTAssertEqual(SceneArt.stampText(.spill), "SPILL!")
        XCTAssertEqual(SceneArt.streakText(7), "7 IN A ROW")
        for n in [2, 7, 12, 40] {
            XCTAssertFalse(SceneArt.streakText(n).contains("×"))
            XCTAssertFalse(SceneArt.streakText(n).contains("STREAK"))
            XCTAssertGreaterThan(SceneArt.streak(n).size.width, 0)
        }
    }

    /// ROUND-5 decision 4: `.over` stamps only — no spill burst, sheet or shake. Real overflow still spills, once.
    @MainActor
    func testOverPlaysNoSpillFXAndRealOverflowDoes() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift(LevelCatalog.levels.first?.id ?? "1-1"), layout: layout, seed: 5)
        let scene = GameScene(layout: layout)
        let live = SceneTestDriver(session)
        scene.driver = live
        scene.reset(for: session.snapshot)
        var t: TimeInterval = 10
        for _ in 0..<90 {
            t += 1.0 / 60.0
            scene.update(t)
        }
        var snap = session.snapshot
        guard let idx = snap.glasses.firstIndex(where: { $0.phase == .filling }) ?? snap.glasses.indices.first else {
            XCTFail("no glass on the counter")
            return
        }
        let id = snap.glasses[idx].id
        snap.glasses[idx].result = .over
        snap.glasses[idx].overflowing = false
        let scripted = ScriptedSceneDriver(snap)
        scene.driver = scripted

        func play(_ events: [GameEvent], frames: Int = 20) {
            scripted.queue = events
            for _ in 0..<frames {
                t += 1.0 / 60.0
                scripted.snapshot.time += 1.0 / 60.0
                scene.update(t)
            }
        }
        play([.served(glassID: id, judgement: .over, points: 0), .strike(1), .streak(0)])
        XCTAssertEqual(scene.spillFXCount, 0, "OVER must not play the spill burst")

        play([.overflowStarted(glassID: id)])
        XCTAssertEqual(scene.spillFXCount, 1)
        play([.served(glassID: id, judgement: .spill, points: 0)])
        XCTAssertEqual(scene.spillFXCount, 1, "one burst per glass")
    }

    /// ROUND-5 decision 3: a dry jug (stream stopped, refill waits for the next glass) reads empty; a fresh jug doesn't.
    @MainActor
    func testDryJugReadsEmptyAndAFreshJugDoesNot() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift(LevelCatalog.levels.first?.id ?? "1-1"), layout: layout, seed: 2)
        var j = session.snapshot.jug
        let jug = SceneJug()
        jug.update(j, streamWidth: 0, time: 1, dt: 0)
        XCTAssertFalse(jug.isDry)

        j.fill = 0.02
        j.flow = 0
        j.angle = 60
        for k in 1...30 { jug.update(j, streamWidth: 0, time: 1 + Double(k) / 60, dt: 1.0 / 60.0) }
        XCTAssertTrue(jug.isDry)
        XCTAssertEqual(jug.dryAmount, 1, accuracy: 0.001)

        // Still pouring the last drops: not "dry" yet.
        let pouring = SceneJug()
        j.flow = 0.2
        pouring.update(j, streamWidth: 10, time: 1, dt: 0)
        XCTAssertFalse(pouring.isDry)

        // The refill arrives between glasses: the empty look goes at once (no fade on the new jug).
        j.fill = 0.6
        j.flow = 0
        jug.update(j, streamWidth: 0, time: 2, dt: 1.0 / 60.0)
        XCTAssertFalse(jug.isDry)
        XCTAssertEqual(jug.dryAmount, 0, accuracy: 0.0001)
    }

    /// Round-5 frame 19: no bubbles (fizz or plume) in sand; sand heaps under the stream instead. Fizzy potions keep
    /// their bubbles.
    @MainActor
    func testSandNeverBubblesAndHeapsUnderTheStream() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        func pour(_ liquid: LiquidID, into glassID: String) -> SceneGlass {
            var drink = LiquidCatalog.liquid(liquid)
            if liquid == .sand { drink.fizzy = true }       // even if the data said so
            let shape = GlassCatalog.shape(glassID)
            let glass = SceneGlass(id: 9, darkBackdrop: liquid != .sand)
            let h = shape.interiorHeight * 0.4
            let state = GlassState(id: 9, shape: shape, liquid: drink, x: 352, phase: .filling, liquidHeight: h,
                                   foamHeight: 0, lineHeight: shape.interiorHeight * 0.7, lineOpacity: 1,
                                   inPerfectBand: false, overflowing: false, patienceLeft: nil, patienceTotal: nil,
                                   result: nil)
            let surfaceY = layout.counterY + max(0, shape.baseThickness) + h
            var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: true,
                               tail: StreamPoint(position: CGPoint(x: 352, y: surfaceY), width: 12), advanced: true,
                               reduceMotion: false, band: 0.025, projected: nil, safeX: 14...656,
                               keepOutTop: layout.creaseMinY - 8)
            for k in 0..<40 {
                f.time = 1 + Double(k) / 60
                glass.update(state, f)
            }
            return glass
        }
        let sand = pour(.sand, into: "jar")
        XCTAssertTrue(sand.isGranular)
        XCTAssertFalse(sand.showsBubbles)
        XCTAssertGreaterThan(sand.heap, 2)
        XCTAssertLessThanOrEqual(sand.heap, SceneGlass.maxHeap + 0.001)

        let potion = pour(.potionBlue, into: "beaker")
        XCTAssertFalse(potion.isGranular)
        XCTAssertTrue(potion.showsBubbles)
        XCTAssertEqual(potion.heap, 0, accuracy: 0.0001)
    }

    // MARK: Round 6

    private func frame(_ layout: WorldLayout, time: Double, pouring: Bool = false, tail: StreamPoint? = nil) -> GlassFrame {
        return GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: time, pouring: pouring, tail: tail,
                          advanced: true, reduceMotion: false, band: 0.025, projected: nil, safeX: 14...656,
                          keepOutTop: layout.creaseMinY - 8)
    }

    private func glassState(_ shape: GlassShape, _ liquid: LiquidID, phase: GlassPhase, h: CGFloat,
                            lineOpacity: Double = 1) -> GlassState {
        return GlassState(id: 4, shape: shape, liquid: LiquidCatalog.liquid(liquid), x: 352, phase: phase,
                          liquidHeight: h, foamHeight: 0, lineHeight: shape.interiorHeight * 0.7,
                          lineOpacity: lineOpacity, inPerfectBand: false, overflowing: false, patienceLeft: nil,
                          patienceTotal: nil, result: nil)
    }

    /// REVIEW-5 §4: sand heaps into a cone under the stream and slumps flat about half a second after it stops —
    /// no slosh.
    @MainActor
    func testSandConeSlumpsFlatOnceThePourStops() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let shape = GlassCatalog.shape("jar")
        let glass = SceneGlass(id: 4, darkBackdrop: false)
        let h = shape.interiorHeight * 0.4
        let state = glassState(shape, .sand, phase: .filling, h: h)
        let surfaceY = layout.counterY + shape.baseThickness + h
        for k in 0..<40 {
            glass.update(state, frame(layout, time: 1 + Double(k) / 60, pouring: true,
                                      tail: StreamPoint(position: CGPoint(x: 352, y: surfaceY), width: 12)))
        }
        XCTAssertGreaterThan(glass.heap, 4)
        XCTAssertLessThanOrEqual(glass.heap, 7.001)
        for k in 0..<36 { glass.update(state, frame(layout, time: 2 + Double(k) / 60)) }
        XCTAssertLessThan(glass.heap, 0.3, "the cone slumps flat within ~0.6 s")
    }

    /// Decision 3 (Conveyor): the tab drains as the pour window runs out.
    @MainActor
    func testBeltTabDrainsWithThePourWindow() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let shape = GlassCatalog.shape("tumbler")
        let glass = SceneGlass(id: 4, darkBackdrop: false)
        let state = glassState(shape, .orangeJuice, phase: .filling, h: 20)
        var f = frame(layout, time: 1)
        glass.update(state, f)
        XCTAssertNil(glass.tabLevel)
        for (k, w) in [CGFloat(1), 0.6, 0.25, 0].enumerated() {
            f.time = 1 + Double(k + 1) / 60
            f.beltWindow = w
            glass.update(state, f)
            XCTAssertEqual(glass.tabLevel ?? -1, w, accuracy: 0.0001)
        }
    }

    /// Decision 3 (Conveyor): a real belt shift shows the lit pour zone, the next glasses riding in on the belt, and
    /// rings the bell when a glass leaves.
    @MainActor
    func testConveyorShowsThePourZoneTheQueueAndRingsTheBell() {
        guard let level = LevelCatalog.levels(in: .conveyor).first else { return XCTFail("no conveyor shift") }
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift(level.id), layout: layout, seed: 11)
        let scene = GameScene(layout: layout)
        scene.venue = .conveyor
        let driver = SceneTestDriver(session)
        scene.driver = driver
        scene.reset(for: session.snapshot)
        var t: TimeInterval = 20
        var sawZone = false, sawQueue = false
        for frame in 0..<(60 * 16) {
            let s = Double(frame) / 60
            driver.tilt = s < 0.5 ? 0 : (s.truncatingRemainder(dividingBy: 3) < 1.2 ? 46 : 0)
            t += 1.0 / 60.0
            scene.update(t)
            if scene.pourZoneVisible { sawZone = true }
            if !scene.beltQueueKeys.isEmpty { sawQueue = true }
        }
        XCTAssertTrue(sawZone, "the pour zone shows on the belt")
        if level.orders.count > 1 { XCTAssertTrue(sawQueue, "the next glass rides in on the belt") }
        XCTAssertGreaterThanOrEqual(scene.bellRingCount, 1, "the bell rings as a glass leaves")
    }

    /// Decision 3 (Potion Shop): potions shimmer; a faded line leaves a faint tick; other drinks have neither.
    @MainActor
    func testPotionsShimmerAndAFadedLineLeavesAGhostTick() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let shape = GlassCatalog.shape("beaker")
        let potion = SceneGlass(id: 4, darkBackdrop: true)
        let faded = glassState(shape, .potionBlue, phase: .filling, h: 60, lineOpacity: 0)
        for k in 0..<10 { potion.update(faded, frame(layout, time: 1 + Double(k) / 60)) }
        XCTAssertTrue(potion.showsMagic)
        XCTAssertTrue(potion.showsGhostTick)

        let plain = SceneGlass(id: 5, darkBackdrop: false)
        let visible = glassState(shape, .lemonade, phase: .filling, h: 60, lineOpacity: 1)
        for k in 0..<10 { plain.update(visible, frame(layout, time: 1 + Double(k) / 60)) }
        XCTAssertFalse(plain.showsMagic)
        XCTAssertFalse(plain.showsGhostTick)
    }

    /// Decision 3 (Potion Shop): a prefilled glass shows its old drink as a settled layer; an empty one doesn't.
    @MainActor
    func testPrefilledGlassShowsASettledLayer() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let shape = GlassCatalog.shape("vial")
        let pre = SceneGlass(id: 4, darkBackdrop: true)
        var state = glassState(shape, .potionPink, phase: .arriving, h: shape.interiorHeight * 0.2)
        pre.update(state, frame(layout, time: 1))
        XCTAssertEqual(pre.prefillHeight ?? 0, shape.interiorHeight * 0.2, accuracy: 0.01)
        XCTAssertTrue(pre.showsPrefill)
        state.phase = .filling
        state.liquidHeight = shape.interiorHeight * 0.6
        pre.update(state, frame(layout, time: 1.1))
        XCTAssertTrue(pre.showsPrefill)

        let empty = SceneGlass(id: 5, darkBackdrop: true)
        empty.update(glassState(shape, .potionPink, phase: .arriving, h: 0), frame(layout, time: 1))
        XCTAssertNil(empty.prefillHeight)
        XCTAssertFalse(empty.showsPrefill)
    }

    /// Decision 3 (Sand Bar): grains trickle at the lip as `reposeProgress` nears 1, never before 0.7, never in
    /// other drinks, and stop once the sand flows.
    @MainActor
    func testScoopTrickleTelegraphsTheSlide() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift(LevelCatalog.levels.first?.id ?? "1-1"), layout: layout, seed: 2)
        var j = session.snapshot.jug
        j.liquid = LiquidCatalog.liquid(.sand)
        j.fill = 0.7
        j.flow = 0
        j.angle = 40
        let jug = SceneJug()
        j.reposeProgress = 0.5
        jug.update(j, streamWidth: 0, time: 1, dt: 1.0 / 60.0)
        XCTAssertEqual(jug.trickleGrains, 0)
        j.reposeProgress = 0.95
        jug.update(j, streamWidth: 0, time: 1.1, dt: 1.0 / 60.0)
        XCTAssertGreaterThan(jug.trickleGrains, 2)
        j.flow = 0.4
        jug.update(j, streamWidth: 12, time: 1.2, dt: 1.0 / 60.0)
        XCTAssertEqual(jug.trickleGrains, 0)
        j.flow = 0
        j.liquid = LiquidCatalog.liquid(.water)
        jug.update(j, streamWidth: 0, time: 1.3, dt: 1.0 / 60.0)
        XCTAssertEqual(jug.trickleGrains, 0)
    }

    /// Decision 3 (Sand Bar): the hourglass glass stands in a wooden frame; other glasses don't.
    @MainActor
    func testHourglassGetsItsWoodenFrame() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let hourglass = GlassShape(id: "hourglass", name: "Hourglass", style: .jar,
                                   profile: [CGPoint(x: 40, y: 0), CGPoint(x: 46, y: 40), CGPoint(x: 14, y: 100),
                                             CGPoint(x: 46, y: 160), CGPoint(x: 40, y: 200)],
                                   baseThickness: 14, wall: 4)
        let glass = SceneGlass(id: 4, darkBackdrop: false)
        glass.update(glassState(hourglass, .sand, phase: .filling, h: 50), frame(layout, time: 1))
        XCTAssertTrue(glass.hasWoodFrame)
        // Round 7 (QA-3 P2-16): plinth and posts stay inside the body half-width Core's slot contract plans for.
        XCTAssertEqual(glass.worldFrame.width, CGFloat(NextGlassSlot.bodyHalfWidth(hourglass)) * 2, accuracy: 0.01)
        XCTAssertGreaterThan(glass.woodReach, 40)
        XCTAssertLessThanOrEqual(glass.woodReach, CGFloat(NextGlassSlot.bodyHalfWidth(hourglass)) + 0.01)
        let jar = SceneGlass(id: 5, darkBackdrop: false)
        jar.update(glassState(GlassCatalog.shape("jar"), .sand, phase: .filling, h: 50), frame(layout, time: 1))
        XCTAssertFalse(jar.hasWoodFrame)
        XCTAssertEqual(jar.woodReach, 0)
        if GlassCatalog.all.contains(where: { $0.id == "hourglass" }) {
            let shape = GlassCatalog.shape("hourglass")
            let real = SceneGlass(id: 6, darkBackdrop: false)
            real.update(glassState(shape, .sand, phase: .filling, h: 30), frame(layout, time: 1))
            XCTAssertTrue(real.hasWoodFrame)
            XCTAssertLessThanOrEqual(real.woodReach, CGFloat(NextGlassSlot.bodyHalfWidth(shape)) + 0.01)
            XCTAssertEqual(real.worldFrame.width, CGFloat(NextGlassSlot.bodyHalfWidth(shape)) * 2, accuracy: 0.01)
        }
    }

    /// Decision 3 (Sand Bar): its own room — adobe wall and sandstone counter, not the Lemonade Stand recoloured.
    func testSandBarHasItsOwnRoom() {
        let sand = ScenePalette.forVenue(.sandBar)
        let lemon = ScenePalette.forVenue(.lemonadeStand)
        XCTAssertEqual(sand.surface, .sandstone)
        XCTAssertNotEqual(lemon.surface, .sandstone)
        XCTAssertEqual(sand.vessel.form, .scoop)
        // A terracotta adobe wall: clearly warmer (more red than blue) than the Lemonade Stand's cream.
        let w = SceneColor.rgba(sand.wallBottom)
        XCTAssertGreaterThan(w.r - w.b, 0.3)
    }

    /// Decision 2: the scene follows `snapshot.venue` (Rush travels per tier) over the App's `venue`, cross-fading.
    @MainActor
    func testSceneFollowsTheSnapshotVenueWithACrossFade() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .rush, layout: layout, seed: 4)
        var snap = session.snapshot
        snap.venue = .lemonadeStand
        let scene = GameScene(layout: layout)
        scene.venue = .lemonadeStand
        let scripted = ScriptedSceneDriver(snap)
        scene.driver = scripted
        scene.reset(for: snap)
        var t: TimeInterval = 5
        func step(_ n: Int) {
            for _ in 0..<n {
                t += 1.0 / 60.0
                scripted.snapshot.time += 1.0 / 60.0
                scene.update(t)
            }
        }
        step(3)
        XCTAssertEqual(scene.shownVenue, .lemonadeStand)
        XCTAssertEqual(scene.lookCrossFadeCount, 0)
        scripted.snapshot.venue = .sodaFountain
        step(3)
        XCTAssertEqual(scene.shownVenue, .sodaFountain)
        XCTAssertEqual(scene.lookCrossFadeCount, 1)
        scripted.snapshot.venue = .conveyor
        step(3)
        XCTAssertEqual(scene.shownVenue, .conveyor)
        // No venue in the snapshot: the App's choice again.
        scripted.snapshot.venue = nil
        step(2)
        XCTAssertEqual(scene.shownVenue, .lemonadeStand)
    }

    /// Decision 3 (Sand Bar): the dust puff fires once as `reposeProgress` reaches 1, and re-arms after easing back.
    @MainActor
    func testReposePuffFiresOncePerApproach() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift(LevelCatalog.levels.first?.id ?? "1-1"), layout: layout, seed: 4)
        var snap = session.snapshot
        snap.jug.liquid = LiquidCatalog.liquid(.sand)
        let scene = GameScene(layout: layout)
        let scripted = ScriptedSceneDriver(snap)
        scene.driver = scripted
        scene.reset(for: snap)
        var t: TimeInterval = 5
        for rp in [0.2, 0.8, 0.98, 0.99, 1.0, 0.5, 0.9, 0.99] {
            scripted.snapshot.jug.reposeProgress = rp
            t += 1.0 / 60.0
            scripted.snapshot.time += 1.0 / 60.0
            scene.update(t)
        }
        XCTAssertEqual(scene.reposePuffCount, 2)
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

    // MARK: Round 7 (QA-3)

    /// QA-3 P1-1 (CI frame 26): once its glass leaves, the stamp rides out with it (no safe-area clamp pinning it over
    /// the next glass) and fades within ~0.15 s.
    @MainActor
    func testStampRidesOutWithItsLeavingGlass() {
        let layout = WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false)
        let shape = GlassCatalog.all[0]
        let glass = SceneGlass(id: 12, darkBackdrop: true)
        var state = GlassState(id: 12, shape: shape, liquid: LiquidCatalog.liquid(.lemonade), x: 335, phase: .served,
                               liquidHeight: shape.interiorHeight * 0.7, foamHeight: 0,
                               lineHeight: shape.interiorHeight * 0.7, lineOpacity: 1, inPerfectBand: true,
                               overflowing: false, patienceLeft: nil, patienceTotal: nil, result: .perfect)
        var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: false, tail: nil,
                           advanced: true, reduceMotion: false, band: 0.025, projected: nil, safeX: 130...540,
                           keepOutTop: layout.creaseMinY - 8)
        for k in 0..<12 {
            f.time = 1 + Double(k) / 60
            glass.update(state, f)
        }
        guard let x0 = glass.stampWorldX else { return XCTFail("the verdict shows a stamp") }
        XCTAssertEqual(glass.stampLeaveAlpha, 1, accuracy: 0.0001)
        let local = x0 - state.x
        // A frozen frame (dt 0) holds it.
        f.dt = 0
        state.phase = .leaving
        glass.update(state, f)
        XCTAssertEqual(glass.stampLeaveAlpha, 1, accuracy: 0.0001)
        f.dt = 1.0 / 60.0
        var last = x0
        var hiddenAt: Int?
        for k in 1...20 {
            state.x = 335 + CGFloat(k) * 18            // the leave slide (~465 pt in 0.45 s)
            f.time += 1.0 / 60.0
            glass.update(state, f)
            if let sx = glass.stampWorldX {
                XCTAssertEqual(sx - state.x, local, accuracy: 0.01, "rides at its last spot on the glass")
                XCTAssertGreaterThan(sx, last)
                last = sx
            } else if hiddenAt == nil {
                hiddenAt = k
            }
        }
        XCTAssertNotNil(hiddenAt)
        XCTAssertLessThanOrEqual(hiddenAt ?? 99, 9, "gone in ~0.15 s")
        XCTAssertEqual(glass.stampLeaveAlpha, 0, accuracy: 0.0001)
        XCTAssertNil(glass.stampReachWorld)
    }

    /// A served Rush/Conveyor glass for the scripted scene tests below.
    @MainActor
    private func scriptedRush(venue: VenueID, upcoming: [GlassOrder]? = nil)
        -> (scene: GameScene, driver: ScriptedSceneDriver)? {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .rush, layout: layout, seed: 4)
        var snap = session.snapshot
        guard var g = snap.glasses.first else { return nil }
        g.phase = .filling
        g.result = nil
        g.patienceLeft = nil
        g.patienceTotal = nil
        g.lineOpacity = 1
        g.x = 300
        snap.glasses = [g]
        snap.phase = .playing
        snap.venue = venue
        snap.rushTier = 3
        let scene = GameScene(layout: layout)
        scene.upcomingOrders = upcoming
        let driver = ScriptedSceneDriver(snap)
        scene.driver = driver
        scene.reset(for: snap)
        return (scene, driver)
    }

    @MainActor
    private func drive(_ scene: GameScene, _ driver: ScriptedSceneDriver, frames: Int, dx: CGFloat, t: inout TimeInterval) {
        for _ in 0..<frames {
            t += 1.0 / 60.0
            driver.snapshot.time += 1.0 / 60.0
            for i in driver.snapshot.glasses.indices { driver.snapshot.glasses[i].x += dx }
            scene.update(t)
        }
    }

    /// QA-3 P2-4: the bell flicks as a glass that really rode the belt rides off (not at the verdict, never for a glass
    /// that stood still while served), and the last belt glass still flicks it as Rush's room turns into the Diner.
    @MainActor
    func testBellFlicksOnlyForAGlassThatRodeTheBelt() {
        XCTAssertEqual(SceneGlass.rideThreshold, ConveyorBellWatch.rideThreshold, "Scene and Feel use one rule")
        var t: TimeInterval = 5
        // Rode the belt.
        guard let a = scriptedRush(venue: .conveyor) else { return XCTFail("no glass") }
        drive(a.scene, a.driver, frames: 5, dx: 0.5, t: &t)
        a.driver.snapshot.glasses[0].phase = .served
        a.driver.snapshot.glasses[0].result = .great
        drive(a.scene, a.driver, frames: 18, dx: 0.5, t: &t)
        XCTAssertEqual(a.scene.bellRingCount, 0, "not at the verdict: as it rides off")
        a.driver.snapshot.glasses[0].phase = .leaving
        drive(a.scene, a.driver, frames: 3, dx: 12, t: &t)
        XCTAssertEqual(a.scene.bellRingCount, 1)

        // Stood still while served (a counter glass): no bell, even in the Conveyor's room.
        guard let b = scriptedRush(venue: .conveyor) else { return XCTFail("no glass") }
        b.driver.snapshot.glasses[0].phase = .served
        b.driver.snapshot.glasses[0].result = .perfect
        drive(b.scene, b.driver, frames: 18, dx: 0, t: &t)
        b.driver.snapshot.glasses[0].phase = .leaving
        drive(b.scene, b.driver, frames: 3, dx: 12, t: &t)
        XCTAssertEqual(b.scene.bellRingCount, 0)

        // Tier 3→4: the room turns into the Diner at the last belt glass's verdict; it still flicks the (fading) bell.
        guard let c = scriptedRush(venue: .conveyor) else { return XCTFail("no glass") }
        drive(c.scene, c.driver, frames: 5, dx: 0.5, t: &t)
        c.driver.snapshot.glasses[0].phase = .served
        c.driver.snapshot.glasses[0].result = .perfect
        c.driver.snapshot.venue = .milkshakeDiner
        c.driver.snapshot.rushTier = 4
        drive(c.scene, c.driver, frames: 18, dx: 0.5, t: &t)
        c.driver.snapshot.glasses[0].phase = .leaving
        drive(c.scene, c.driver, frames: 3, dx: 12, t: &t)
        XCTAssertEqual(c.scene.shownVenue, .milkshakeDiner)
        XCTAssertEqual(c.scene.bellRingCount, 1)
    }

    /// QA-3 P2-1: Rush's Conveyor tier shows the belt queue from what the App publishes (the snapshot has none), and
    /// only belt orders ride: a next glass with patience (the Diner's, after the tier) is not drawn on the belt.
    @MainActor
    func testRushConveyorTierShowsTheBeltQueue() {
        var t: TimeInterval = 5
        let belt = GlassOrder(glass: "tumbler", liquid: .orangeJuice, line: 0.5)
        guard let a = scriptedRush(venue: .conveyor, upcoming: [belt]) else { return XCTFail("no glass") }
        drive(a.scene, a.driver, frames: 10, dx: 0.5, t: &t)
        XCTAssertEqual(a.scene.beltQueueKeys.count, 1, "the next glass rides in on the belt")

        let diner = GlassOrder(glass: "tumbler", liquid: .lemonade, line: 0.6, patience: 8)
        guard let b = scriptedRush(venue: .conveyor, upcoming: [diner]) else { return XCTFail("no glass") }
        drive(b.scene, b.driver, frames: 10, dx: 0.5, t: &t)
        XCTAssertTrue(b.scene.beltQueueKeys.isEmpty, "a counter glass never rides the belt")

        guard let c = scriptedRush(venue: .conveyor) else { return XCTFail("no glass") }
        drive(c.scene, c.driver, frames: 10, dx: 0.5, t: &t)
        XCTAssertTrue(c.scene.beltQueueKeys.isEmpty, "nothing known, nothing drawn")
    }

    /// QA-3 P2-5: Rush paints the next tier's look ahead, once, at a quiet moment late in the tier (or regardless near
    /// its end), so the tier change itself repaints nothing; the cache stays at three looks.
    @MainActor
    func testRushPaintsTheNextTiersLookAhead() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .rush, layout: layout, seed: 4)
        var snap = session.snapshot
        let every = CoreTuning.rushTierEvery
        snap.phase = .playing
        snap.rushTier = 2
        snap.venue = Rules.rushVenue(tier: 2)
        snap.ordersDone = every + 3
        snap.stream = []
        snap.jug.flow = 0
        let scene = GameScene(layout: layout)
        let driver = ScriptedSceneDriver(snap)
        scene.driver = driver
        scene.reset(for: snap)
        var t: TimeInterval = 5
        drive(scene, driver, frames: 2, dx: 0, t: &t)
        let painted = scene.backdropRenderCount
        XCTAssertGreaterThanOrEqual(painted, 1)
        drive(scene, driver, frames: 5, dx: 0, t: &t)
        XCTAssertEqual(scene.backdropRenderCount, painted, "too early in the tier")

        driver.snapshot.ordersDone = every + GameScene.prewarmFromGlass
        drive(scene, driver, frames: 2, dx: 0, t: &t)
        XCTAssertEqual(scene.backdropRenderCount, painted + 1, "the next look is painted ahead")
        drive(scene, driver, frames: 5, dx: 0, t: &t)
        XCTAssertEqual(scene.backdropRenderCount, painted + 1, "once per tier")

        // The tier change: a cross-fade to a look already painted.
        driver.snapshot.rushTier = 3
        driver.snapshot.venue = Rules.rushVenue(tier: 3)
        driver.snapshot.ordersDone = 2 * every
        drive(scene, driver, frames: 3, dx: 0, t: &t)
        XCTAssertEqual(scene.shownVenue, Rules.rushVenue(tier: 3))
        XCTAssertEqual(scene.lookCrossFadeCount, 1)
        XCTAssertEqual(scene.backdropRenderCount, painted + 1, "no repaint at the tier change")

        // Pouring through the end of a tier: painted anyway, two glasses before the change.
        driver.snapshot.jug.flow = 0.5
        driver.snapshot.ordersDone = 2 * every + GameScene.prewarmFromGlass
        drive(scene, driver, frames: 2, dx: 0, t: &t)
        XCTAssertEqual(scene.backdropRenderCount, painted + 1, "waits for a quiet moment")
        driver.snapshot.ordersDone = 2 * every + GameScene.prewarmForcedFromGlass
        drive(scene, driver, frames: 2, dx: 0, t: &t)
        XCTAssertEqual(scene.backdropRenderCount, painted + 2)
        XCTAssertLessThanOrEqual(scene.cachedLookCount, 3)
    }

    // MARK: Round 8 (REVIEW-6)

    /// N5 (frame 18): the stamp never sits on a tall glass's rim. For every glass, on the Duo and phones, once the pop
    /// and the Perfect hop have settled: either it is above the rim with its ink ≥ 10 pt clear of it (at ≥ 0.8 size),
    /// or it stands beside the glass (clear of its walls, foot, handle, plinth and line tab), inside the crop. Never
    /// above the crease keep-out.
    @MainActor
    func testStampClearsTheRimOrStandsBesideTheGlass() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let keepOut = layout.creaseMinY - 8
        let cases: [(CGFloat, ClosedRange<CGFloat>)] = [(372, 14...656), (340, 130...540), (418, 130...540)]
        var besideIDs: Set<String> = []
        for shape in GlassCatalog.all {
            for (x, safe) in cases {
                for verdict in [Judgement.perfect, .spill, .good] {
                    let glass = SceneGlass(id: 1, darkBackdrop: false)
                    let state = GlassState(id: 1, shape: shape, liquid: LiquidCatalog.liquid(.lemonade), x: x,
                                           phase: .served, liquidHeight: shape.interiorHeight * 0.9, foamHeight: 0,
                                           lineHeight: shape.interiorHeight * 0.9, lineOpacity: 1, inPerfectBand: true,
                                           overflowing: false, patienceLeft: nil, patienceTotal: nil, result: verdict)
                    var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: false, tail: nil,
                                       advanced: true, reduceMotion: false, band: 0.025, projected: nil, safeX: safe,
                                       keepOutTop: keepOut)
                    glass.update(state, f)
                    if verdict == .perfect { glass.celebrate() }
                    for k in 1...45 {
                        f.time = 1 + Double(k) / 60
                        glass.update(state, f)
                        XCTAssertLessThanOrEqual(glass.stampReachWorld ?? 0, keepOut + 0.5, "\(shape.id) crease")
                    }
                    let tag = "\(shape.id) \(verdict) at x \(x)"
                    guard let ink = glass.stampInkWorldRect else {
                        XCTFail("\(tag): no stamp")
                        continue
                    }
                    XCTAssertGreaterThanOrEqual(ink.minX, safe.lowerBound - 0.5, "\(tag): inside the crop")
                    XCTAssertLessThanOrEqual(ink.maxX, safe.upperBound + 0.5, "\(tag): inside the crop")
                    if glass.stampBeside {
                        if x == 372 { besideIDs.insert(shape.id) }
                        let body = glass.bodyWorldXRange
                        let clear = ink.maxX <= body.lowerBound + 0.5 || ink.minX >= body.upperBound - 0.5
                        XCTAssertTrue(clear, "\(tag): beside, not over the glass (ink \(ink), body \(body))")
                        XCTAssertGreaterThanOrEqual(glass.stampWorldScale, SceneGlass.stampFloorScale - 0.001, tag)
                        if x == 372 { XCTAssertLessThan(ink.midX, x, "\(tag): the Duo has room on the left") }
                    } else {
                        XCTAssertGreaterThanOrEqual(ink.minY, glass.rimTopWorld + SceneGlass.stampRimGap - 0.25,
                                                    "\(tag): ≥ 10 pt over the rim")
                        XCTAssertGreaterThanOrEqual(glass.stampWorldScale, SceneGlass.stampMinAboveScale - 0.001, tag)
                    }
                }
            }
        }
        // Frame 18's glass goes beside; an everyday tumbler keeps its stamp over the rim.
        XCTAssertTrue(besideIDs.contains("flute"))
        XCTAssertTrue(besideIDs.contains("highball"))
        XCTAssertFalse(besideIDs.contains("tumbler"))
        XCTAssertFalse(besideIDs.contains("shot"))
    }

    /// N5: a stamp beside the glass rides out with it like any other (QA-3 P1-1), and a streak pop never lands back
    /// over the glass.
    @MainActor
    func testBesideStampRidesOutAndStreakStaysOffTheGlass() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let keepOut = layout.creaseMinY - 8
        let shape = GlassCatalog.shape("flute")
        let glass = SceneGlass(id: 3, darkBackdrop: false)
        var state = GlassState(id: 3, shape: shape, liquid: LiquidCatalog.liquid(.lemonade), x: 372, phase: .served,
                               liquidHeight: shape.interiorHeight * 0.9, foamHeight: 0,
                               lineHeight: shape.interiorHeight * 0.9, lineOpacity: 1, inPerfectBand: true,
                               overflowing: false, patienceLeft: nil, patienceTotal: nil, result: .perfect)
        var f = GlassFrame(counterY: layout.counterY, dt: 1.0 / 60.0, time: 1, pouring: false, tail: nil,
                           advanced: true, reduceMotion: false, band: 0.025, projected: nil, safeX: 14...656,
                           keepOutTop: keepOut)
        glass.update(state, f)
        glass.showStreak(4, reduceMotion: false, safeX: 14...656, keepOutTop: keepOut)
        for k in 1...20 {
            f.time = 1 + Double(k) / 60
            glass.update(state, f)
        }
        XCTAssertTrue(glass.stampBeside)
        XCTAssertLessThanOrEqual(glass.lastStreakReachWorld ?? 0, keepOut + 0.5)
        guard let x0 = glass.stampWorldX else { return XCTFail("a stamp shows") }
        let local = x0 - state.x
        XCTAssertLessThan(local, 0, "left of the glass")
        state.phase = .leaving
        for k in 1...6 {
            state.x = 372 + CGFloat(k) * 18
            f.time += 1.0 / 60.0
            glass.update(state, f)
            if let sx = glass.stampWorldX { XCTAssertEqual(sx - state.x, local, accuracy: 0.01) }
        }
    }

    /// #6 Glass Cabinet lite: `vesselOverride` draws the chosen venue's signature vessel around the same interior,
    /// whatever the backdrop; nil restores the venue's own.
    @MainActor
    func testVesselOverrideDrawsEachVenuesVessel() {
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .practice, layout: layout, seed: 7)
        let scene = GameScene(layout: layout)
        let driver = SceneTestDriver(session)
        scene.driver = driver
        scene.venue = .lemonadeStand
        scene.reset(for: session.snapshot)
        var t: TimeInterval = 100
        func step(_ n: Int) {
            for _ in 0..<n {
                t += 1.0 / 60.0
                scene.update(t)
            }
        }
        driver.tilt = 0
        step(30)
        driver.tilt = 48                    // mid-pour: the tipped vessel with its stream
        step(30)
        let backdrop = scene.shownVenue
        XCTAssertEqual(scene.shownVesselForm, ScenePalette.forVenue(backdrop).vessel.form)
        XCTAssertFalse(scene.jugWorldBounds.isNull)
        for v in VenueID.allCases {
            scene.vesselOverride = v
            step(12)
            let want = ScenePalette.forVenue(v).vessel
            XCTAssertEqual(scene.shownVesselForm, want.form, "\(v)")
            XCTAssertEqual(scene.shownVesselDecal, want.decal, "\(v)")
            XCTAssertEqual(scene.shownVenue, backdrop, "\(v): the backdrop stays")
            XCTAssertFalse(scene.jugWorldBounds.isNull, "\(v) draws")
            guard let parts = scene.shownVesselParts else {
                XCTFail("\(v): vessel not built")
                continue
            }
            switch want.form {
            case .pitcher, .dispenser:
                XCTAssertTrue(parts.lid && parts.handle && !parts.skin, "\(v)")
            case .shakeTin:
                XCTAssertTrue(parts.lid && !parts.handle && parts.skin, "\(v)")
            case .flask:
                XCTAssertTrue(parts.lid && !parts.handle && !parts.skin, "\(v)")
            case .scoop:
                XCTAssertTrue(!parts.lid && parts.handle && parts.skin, "\(v)")
            }
        }
        scene.vesselOverride = nil
        step(4)
        XCTAssertEqual(scene.shownVesselForm, ScenePalette.forVenue(scene.shownVenue).vessel.form)
    }

    /// #6: in Rush the chosen vessel travels with the player through every tier's venue (no vessel cross-fade).
    @MainActor
    func testVesselOverrideHoldsThroughRushTravel() {
        guard let c = scriptedRush(venue: .lemonadeStand) else { return XCTFail("no glass") }
        var t: TimeInterval = 5
        c.scene.vesselOverride = .potionShop
        drive(c.scene, c.driver, frames: 3, dx: 0, t: &t)
        XCTAssertEqual(c.scene.shownVesselForm, .flask)
        for v in [VenueID.sodaFountain, .milkshakeDiner, .conveyor, .sandBar] {
            c.driver.snapshot.venue = v
            drive(c.scene, c.driver, frames: 3, dx: 0, t: &t)
            XCTAssertEqual(c.scene.shownVenue, v)
            XCTAssertEqual(c.scene.shownVesselForm, .flask, "\(v)")
            XCTAssertEqual(c.scene.shownVesselDecal, .moon, "\(v)")
        }
        c.scene.vesselOverride = nil
        drive(c.scene, c.driver, frames: 2, dx: 0, t: &t)
        XCTAssertEqual(c.scene.shownVesselForm, .scoop)
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

/// Replays a fixed snapshot and hands out queued events once (for event → FX tests).
@MainActor
private final class ScriptedSceneDriver: SceneDriver {
    var snapshot: GameSnapshot
    var queue: [GameEvent] = []

    init(_ snapshot: GameSnapshot) {
        self.snapshot = snapshot
    }

    func advance(dt: Double, now: TimeInterval) -> (GameSnapshot, [GameEvent])? {
        let events = queue
        queue = []
        return (snapshot, events)
    }
}
