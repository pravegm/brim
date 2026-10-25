import CoreGraphics
import Foundation
import Testing
@testable import Brim

struct CoreTests {

    // MARK: Helpers

    private func duoLayout() -> WorldLayout {
        let crease: ClosedRange<CGFloat> = CGFloat(455.5)...CGFloat(495.5)
        return WorldLayout.make(canvas: CGSize(width: 669, height: 951), creaseFromTop: crease)
    }

    private func run(_ s: GameSession, seconds: Double, tilt: Double, events: inout [GameEvent]) {
        let dt: Double = 1.0 / 60.0
        var t: Double = 0
        while t < seconds {
            events.append(contentsOf: s.step(dt: dt, tilt: tilt))
            t += dt
        }
    }

    private func servedJudgements(_ events: [GameEvent]) -> [Judgement] {
        var out: [Judgement] = []
        for e in events {
            if case .served(_, let j, _) = e { out.append(j) }
        }
        return out
    }

    private func count(_ events: [GameEvent], where match: (GameEvent) -> Bool) -> Int {
        var n: Int = 0
        for e in events where match(e) { n += 1 }
        return n
    }

    // MARK: GlassMath

    @Test func glassVolumeHeightRoundTripForEveryGlass() {
        for g in GlassCatalog.all {
            let interior: CGFloat = g.interiorHeight
            let cap: CGFloat = GlassMath.capacity(g)
            #expect(cap > 0)
            var h: CGFloat = 0
            while h <= interior {
                let v: CGFloat = GlassMath.volume(g, upTo: h)
                let back: CGFloat = GlassMath.height(g, forVolume: v)
                #expect(abs(back - h) < 0.05, "round trip \(g.id) at \(h): \(back)")
                h += interior / 40
            }
            #expect(GlassMath.height(g, forVolume: cap * 2) == interior)
            #expect(GlassMath.height(g, forVolume: 0) == CGFloat(0))
        }
    }

    @Test func glassVolumeIsStrictlyMonotonic() {
        for g in GlassCatalog.all {
            let interior: CGFloat = g.interiorHeight
            var last: CGFloat = -1
            var h: CGFloat = 0
            while h <= interior {
                let v: CGFloat = GlassMath.volume(g, upTo: h)
                #expect(v > last, "\(g.id) not increasing at \(h)")
                last = v
                h += interior / 60
            }
        }
    }

    @Test func glassCatalogHasAllStylesWithSaneSizes() {
        let ids: [String] = GlassCatalog.all.map { (g: GlassShape) -> String in g.id }
        for want in ["tumbler", "highball", "flute", "mug", "bowl", "sundae", "vial", "beaker", "jar", "pint", "shot"] {
            #expect(ids.contains(want), "missing \(want)")
        }
        #expect(Set(ids).count == ids.count)
        for g in GlassCatalog.all {
            #expect(g.interiorHeight >= 80 && g.interiorHeight <= 230)
            #expect(g.rimHalfWidth >= 22 && g.rimHalfWidth <= 75)
            var lastY: CGFloat = -1
            for p in g.profile {
                #expect(p.y > lastY)
                lastY = p.y
            }
        }
        #expect(GlassCatalog.shape("nope").id == "tumbler")
    }

    @Test func liquidCatalogCoversEveryLiquid() {
        #expect(LiquidCatalog.all.count == LiquidID.allCases.count)
        for id in LiquidID.allCases {
            #expect(LiquidCatalog.liquid(id).id == id)
        }
        #expect(LiquidCatalog.liquid(.sand).reposeDegrees > 20)
        #expect(LiquidCatalog.liquid(.honey).lagTau > LiquidCatalog.liquid(.water).lagTau)
        #expect(LiquidCatalog.liquid(.cola).foam != nil)
    }

    // MARK: JugGeometry

    @Test func jugLiquidAreaMatchesVolume() {
        let jug: JugShape = JugGeometry.standard
        let origin: CGPoint = CGPoint(x: 300, y: 500)
        for angle in [0.0, 20.0, 45.0, 70.0, 100.0, 125.0] {
            for fill in [0.1, 0.35, 0.6, 0.9] {
                let pose = JugGeometry.pose(jug, angle: angle, fill: fill, at: origin)
                let area: CGFloat = CorePolygon.area(pose.liquid)
                let want: CGFloat = CGFloat(fill) * jug.capacity
                #expect(abs(area - want) < want * 0.005 + 1, "angle \(angle) fill \(fill): \(area) vs \(want)")
            }
        }
    }

    @Test func fullJugPoursAtSmallAngleButNotAtZero() {
        let jug: JugShape = JugGeometry.standard
        #expect(JugGeometry.head(jug, angle: 0, fill: 1.0) < CGFloat(0))
        #expect(JugGeometry.head(jug, angle: 25, fill: 1.0) > CGFloat(0))
        let threshold: Double = JugGeometry.pourThreshold(jug, fill: 1.0)
        #expect(threshold > 3 && threshold < 20)
    }

    @Test func emptierJugNeedsMoreAngle() {
        let jug: JugShape = JugGeometry.standard
        let fills: [Double] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.08]
        var last: Double = -1
        for f in fills {
            let t: Double = JugGeometry.pourThreshold(jug, fill: f)
            #expect(t > last, "threshold for \(f) = \(t) should exceed \(last)")
            last = t
        }
        #expect(last > 65)
    }

    @Test func liftKeepsUprightJugAboveTheCrease() {
        let layout: WorldLayout = duoLayout()
        let session: GameSession = GameSession(mode: .practice, layout: layout, seed: 1)
        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
        for p in session.snapshot.jug.outline where p.y < minY { minY = p.y }
        #expect(minY >= layout.creaseMaxY)
    }

    // MARK: Rules

    @Test func jugAngleMapping() {
        #expect(Rules.jugAngle(forLidTilt: 0) == 0)
        #expect(Rules.jugAngle(forLidTilt: 5.9) == 0)
        #expect(abs(Rules.jugAngle(forLidTilt: 90) - 130.2) < 0.001)
        #expect(Rules.jugAngle(forLidTilt: 120) == Rules.jugAngle(forLidTilt: 90))
    }

    @Test func judgeBands() {
        let interior: CGFloat = 200
        let line: CGFloat = 100
        #expect(Rules.judge(top: 100, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .perfect)
        #expect(Rules.judge(top: 104, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .perfect)
        #expect(Rules.judge(top: 108, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .great)
        #expect(Rules.judge(top: 92, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .great)
        #expect(Rules.judge(top: 120, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .good)
        #expect(Rules.judge(top: 80, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .good)
        #expect(Rules.judge(top: 70, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .short)
        #expect(Rules.judge(top: 130, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .spill)
        #expect(Rules.judge(top: 100, line: line, interior: interior, overflowed: true, perfectBand: 0.025) == .spill)
    }

    @Test func multiplierTiersAndPoints() {
        #expect(Rules.multiplier(forStreak: 0) == 1)
        #expect(Rules.multiplier(forStreak: 2) == 1)
        #expect(Rules.multiplier(forStreak: 3) == 2)
        #expect(Rules.multiplier(forStreak: 5) == 2)
        #expect(Rules.multiplier(forStreak: 6) == 3)
        #expect(Rules.multiplier(forStreak: 9) == 3)
        #expect(Rules.multiplier(forStreak: 10) == 5)
        #expect(Rules.multiplier(forStreak: 40) == 5)
        #expect(Rules.points(for: .perfect, multiplier: 2) == 2 * Rules.points(for: .perfect, multiplier: 1))
        #expect(Rules.points(for: .spill, multiplier: 5) == 0)
        #expect(Rules.points(for: .short, multiplier: 5) == 0)
        #expect(Rules.points(for: .perfect, multiplier: 1) > Rules.points(for: .great, multiplier: 1))
        #expect(Rules.points(for: .great, multiplier: 1) > Rules.points(for: .good, multiplier: 1))
    }

    @Test func starRules() {
        #expect(Rules.stars(perfects: 6, hits: 6, spills: 0, total: 6) == 3)
        #expect(Rules.stars(perfects: 4, hits: 6, spills: 0, total: 6) == 3)
        #expect(Rules.stars(perfects: 3, hits: 6, spills: 0, total: 6) == 2)
        #expect(Rules.stars(perfects: 5, hits: 5, spills: 1, total: 6) == 2)
        #expect(Rules.stars(perfects: 0, hits: 4, spills: 0, total: 6) == 1)
        #expect(Rules.stars(perfects: 0, hits: 0, spills: 0, total: 0) == 0)
    }

    // MARK: GameSession

    @Test func sessionIsDeterministicForTheSameSeed() {
        let layout: WorldLayout = duoLayout()
        let a: GameSession = GameSession(mode: .rush, layout: layout, seed: 42)
        let b: GameSession = GameSession(mode: .rush, layout: layout, seed: 42)
        var ea: [String] = []
        var eb: [String] = []
        var t: Double = 0
        while t < 12 {
            let tilt: Double = 30 + 25 * sin(t * 1.7)
            for e in a.step(dt: 1.0 / 60.0, tilt: tilt) { ea.append(String(describing: e)) }
            for e in b.step(dt: 1.0 / 60.0, tilt: tilt) { eb.append(String(describing: e)) }
            t += 1.0 / 60.0
        }
        #expect(ea == eb)
        #expect(!ea.isEmpty)
        #expect(a.snapshot.score == b.snapshot.score)
        #expect(a.snapshot.jug.fill == b.snapshot.jug.fill)
        #expect(a.snapshot.stream.count == b.snapshot.stream.count)
        #expect(a.snapshot.glasses.count == b.snapshot.glasses.count)
        let ha: [CGFloat] = a.snapshot.glasses.map { (g: GlassState) -> CGFloat in g.liquidHeight }
        let hb: [CGFloat] = b.snapshot.glasses.map { (g: GlassState) -> CGFloat in g.liquidHeight }
        #expect(ha == hb)
    }

    @Test func holdingTiltZeroNeverPours() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 7)
        var events: [GameEvent] = []
        run(s, seconds: 10, tilt: 0, events: &events)
        let starts: Int = count(events) { (e: GameEvent) -> Bool in
            if case .pourStarted = e { return true }
            return false
        }
        #expect(starts == 0)
        #expect(s.snapshot.jug.fill == 1.0)
        #expect(s.snapshot.stream.isEmpty)
        #expect(s.snapshot.glasses.count == 1)
        #expect(s.snapshot.glasses[0].liquidHeight == CGFloat(0))
        #expect(s.snapshot.glasses[0].phase == .filling)
        #expect(s.snapshot.phase == .playing)
    }

    @Test func scriptedPourFillsTheFirstGlassAndServesIt() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 3)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .playing)

        // Pour at a steady lid tilt until the projection says the line will be reached, then lay it flat.
        var t: Double = 0
        var sawStream: Bool = false
        while t < 15 && s.snapshot.telemetry.projectedDistanceToLine < -0.01 {
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: 35))
            if !s.snapshot.stream.isEmpty { sawStream = true }
            t += 1.0 / 60.0
        }
        #expect(sawStream)
        #expect(t < 15)
        run(s, seconds: 3.0, tilt: 0, events: &events)

        let judged: [Judgement] = servedJudgements(events)
        #expect(judged.count == 1)
        if let j = judged.first {
            #expect(j.isHit, "judged \(j)")
        }
        #expect(s.snapshot.jug.fill < 1.0)
        let pourStarts: Int = count(events) { (e: GameEvent) -> Bool in
            if case .pourStarted = e { return true }
            return false
        }
        #expect(pourStarts >= 1)
        let glugs: Int = count(events) { (e: GameEvent) -> Bool in
            if case .glug = e { return true }
            return false
        }
        #expect(glugs >= 3)
    }

    @Test func floodingProducesASpill() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 5)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        var t: Double = 0
        var overflowed: Bool = false
        while t < 10 && !overflowed {
            for e in s.step(dt: 1.0 / 60.0, tilt: 60) {
                events.append(e)
                if case .overflowStarted = e { overflowed = true }
            }
            t += 1.0 / 60.0
        }
        #expect(overflowed)
        run(s, seconds: 3.0, tilt: 0, events: &events)
        let judged: [Judgement] = servedJudgements(events)
        let first: Judgement? = judged.first
        #expect(first == Judgement.spill)
        #expect(!s.snapshot.puddles.isEmpty)
        #expect(s.snapshot.strikes == 1)
    }

    @Test func rushEndsOnThreeSpills() {
        let s: GameSession = GameSession(mode: .rush, layout: duoLayout(), seed: 11)
        var events: [GameEvent] = []
        var t: Double = 0
        while t < 240 && !s.isFinished {
            s.debugSetJugFill(1.0)
            var tilt: Double = 0
            for g in s.snapshot.glasses where g.phase == .filling && !g.overflowing {
                tilt = 70
            }
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
        }
        #expect(s.isFinished)
        let spills: Int = servedJudgements(events).filter { (j: Judgement) -> Bool in j == .spill }.count
        #expect(spills == 3)
        let finishedCount: Int = count(events) { (e: GameEvent) -> Bool in
            if case .finished = e { return true }
            return false
        }
        #expect(finishedCount == 1)
        #expect(s.result != nil)
        #expect(s.snapshot.phase == .finished)
    }

    @Test func practiceNeverFinishes() {
        let s: GameSession = GameSession(mode: .practice, layout: duoLayout(), seed: 9)
        var events: [GameEvent] = []
        var t: Double = 0
        while t < 40 {
            var tilt: Double = 0
            for g in s.snapshot.glasses where g.phase == .filling && !g.overflowing { tilt = 70 }
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
        }
        #expect(!s.isFinished)
        #expect(s.snapshot.score == 0)
        #expect(servedJudgements(events).count >= 2)
    }

    @Test func dailyHasTenOrdersAndThreeStrikes() {
        let s: GameSession = GameSession(mode: .daily(300), layout: duoLayout(), seed: 300)
        let total: Int? = s.snapshot.ordersTotal
        #expect(total == Int(10))
        #expect(s.snapshot.maxStrikes == 3)
    }
}
