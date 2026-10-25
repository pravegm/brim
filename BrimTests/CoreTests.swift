import CoreGraphics
import Foundation
import Testing
@testable import Brim

struct CoreTests {

    // MARK: Helpers

    /// The Duo inner canvas in tabletop pose (a fold: the flat gate is on).
    private func duoLayout() -> WorldLayout {
        return WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
    }

    /// A regular iPhone (no fold: touch control, no flat gate).
    private func phoneLayout() -> WorldLayout {
        return WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false)
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

    /// Lid tilt at which the standard jug with this fill starts to pour.
    private func pourLid(fill: Double) -> Double {
        let jugAngle: Double = JugGeometry.pourThreshold(JugGeometry.standard, fill: fill)
        return jugAngle / 1.55 + Rules.deadZone
    }

    private func activeGlass(_ s: GameSession) -> GlassState? {
        return s.snapshot.glasses.first(where: { (g: GlassState) -> Bool in g.phase == .filling && g.result == nil })
    }

    /// Where the stream crosses height `y` (interpolated along the ribbon), if it reaches that low.
    private func streamX(at y: CGFloat, _ stream: [StreamPoint]) -> CGFloat? {
        if stream.count < 2 { return nil }
        var i: Int = 1
        while i < stream.count {
            let a: CGPoint = stream[i - 1].position
            let b: CGPoint = stream[i].position
            if a.y >= y && b.y <= y && a.y > b.y {
                let t: CGFloat = (a.y - y) / (a.y - b.y)
                return a.x + (b.x - a.x) * t
            }
            i += 1
        }
        return nil
    }

    /// A calm, careful hand: pours `offset` degrees of lid past the current pour point while far from the line, a
    /// trickle near it, and lays the jug flat once the projection reaches `stopAt`.
    private func carefulTilt(_ s: GameSession, offset: Double, stopAt: Double, stopped: inout Bool) -> Double {
        if stopped { return 0 }
        if activeGlass(s) == nil { return 0 }
        let projected: Double = s.snapshot.telemetry.projectedDistanceToLine
        if projected >= stopAt {
            stopped = true
            return 0
        }
        let start: Double = pourLid(fill: max(0.03, s.snapshot.jug.fill))
        return projected < -0.15 ? start + offset : start + 7
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
            #expect(g.interiorHeight >= 120 && g.interiorHeight <= 300, "\(g.id) interior \(g.interiorHeight)")
            #expect(g.rimHalfWidth >= 30 && g.rimHalfWidth <= 95, "\(g.id) rim \(g.rimHalfWidth)")
            var lastY: CGFloat = -1
            for p in g.profile {
                #expect(p.y > lastY)
                lastY = p.y
            }
        }
        #expect(GlassCatalog.shape("nope").id == "tumbler")
    }

    @Test func glassesAreHeroSizedAndClearOfTheCrease() {
        let layout: WorldLayout = duoLayout()
        let tumbler: GlassShape = GlassCatalog.shape("tumbler")
        let outerRim: CGFloat = 2 * (tumbler.rimHalfWidth + tumbler.wall)
        #expect(outerRim >= 110 && outerRim <= 130, "tumbler rim \(outerRim)")
        for g in GlassCatalog.all {
            let rimY: CGFloat = layout.counterY + g.baseThickness + g.interiorHeight
            #expect(rimY <= layout.creaseMinY - 40, "\(g.id) rim at \(rimY)")
            #expect(g.baseThickness + g.interiorHeight <= GlassCatalog.maxStandingHeight)
        }
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

    @Test func jugIsLiddedWithASpoutChannelToTheLip() {
        let jug: JugShape = JugGeometry.standard
        let n: Int = jug.outline.count
        #expect(JugGeometry.lidIndices.upperBound < n)
        #expect(jug.outline[JugGeometry.lipIndex] == jug.lip)
        #expect(jug.pivot == jug.lip)
        // The lid is the top of the jug, above the lip; the channel runs up from the neck to the lip.
        for i in JugGeometry.lidIndices { #expect(jug.outline[i].y > jug.lip.y) }
        let neck: CGPoint = jug.outline[JugGeometry.spoutChannelIndices.lowerBound]
        #expect(neck.y < jug.lip.y && neck.x < jug.lip.x)
        // Drawn size ~170 × 230 with walls: interior ~146 wide body (+ spout) and ~216 tall.
        let b: CGRect = CorePolygonBounds.of(jug.outline)
        #expect(b.width >= 150 && b.width <= 185, "width \(b.width)")
        #expect(b.height >= 200 && b.height <= 230, "height \(b.height)")
        // Tipped past its pour point, the liquid fills the channel right up to the lip.
        let threshold: Double = JugGeometry.pourThreshold(jug, fill: 0.6)
        let pose = JugGeometry.pose(jug, angle: threshold + 10, fill: 0.6, at: CGPoint(x: 0, y: 0))
        #expect(pose.headAboveLip > CGFloat(0))
        var nearLip: Bool = false
        for p in pose.liquid where abs(p.x - pose.lip.x) < 1 && abs(p.y - pose.lip.y) < 1 { nearLip = true }
        #expect(nearLip)
    }

    @Test func jugStaysClearOfTheHUDAndInsideTheVisibleBand() {
        let layout: WorldLayout = duoLayout()
        let s: GameSession = GameSession(mode: .practice, layout: layout, seed: 1)
        var tilt: Double = 0
        while tilt <= 90 {
            s.step(dt: 1.0 / 60.0, tilt: tilt)
            let jug: JugState = s.snapshot.jug
            var minX: CGFloat = CGFloat.greatestFiniteMagnitude
            var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude
            var minY: CGFloat = CGFloat.greatestFiniteMagnitude
            var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude
            for p in jug.outline {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            // Interior + 9 pt walls must stay inside x 130…540 (with room for the handle) and below the HUD band.
            #expect(maxY + 9 <= 842 - 10, "tilt \(tilt): top \(maxY)")
            #expect(minX - 9 >= 140, "tilt \(tilt): left \(minX)")
            if tilt <= 6 { #expect(minX - 9 - 60 >= 130, "upright handle room \(minX)") }
            #expect(maxX + 9 <= 540, "tilt \(tilt): right \(maxX)")
            #expect(minY >= layout.creaseMaxY, "tilt \(tilt): bottom \(minY)")
            // Mid and low jugs pour at ≥ 55° of jug angle: there the lip sits 50…90 pt above the crease.
            if s.snapshot.jug.angle >= 55 {
                let above: CGFloat = jug.lip.y - layout.creaseMaxY
                #expect(above >= 50 && above <= 90, "tilt \(tilt): lip +\(above)")
            }
            tilt += 2
        }
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

    // MARK: GameSession basics

    @Test func sessionIsDeterministicForTheSameSeed() {
        let layout: WorldLayout = duoLayout()
        let a: GameSession = GameSession(mode: .rush, layout: layout, seed: 42)
        let b: GameSession = GameSession(mode: .rush, layout: layout, seed: 42)
        var ea: [String] = []
        var eb: [String] = []
        var t: Double = 0
        while t < 12 {
            let tilt: Double = t < 1 ? 0 : 40 + 25 * sin(t * 1.7)
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
        #expect(a.snapshot.puddles == b.snapshot.puddles)
        let ha: [CGFloat] = a.snapshot.glasses.map { (g: GlassState) -> CGFloat in g.liquidHeight }
        let hb: [CGFloat] = b.snapshot.glasses.map { (g: GlassState) -> CGFloat in g.liquidHeight }
        #expect(ha == hb)
    }

    @Test func holdingTiltZeroNeverPours() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 7)
        let startFill: Double = s.snapshot.jug.fill
        var events: [GameEvent] = []
        run(s, seconds: 10, tilt: 0, events: &events)
        let starts: Int = count(events) { (e: GameEvent) -> Bool in
            if case .pourStarted = e { return true }
            return false
        }
        #expect(starts == 0)
        #expect(s.snapshot.jug.fill == startFill)
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
        let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 15
        var t: Double = 0
        var sawStream: Bool = false
        while t < 15 && s.snapshot.telemetry.projectedDistanceToLine < -0.01 {
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            if !s.snapshot.stream.isEmpty { sawStream = true }
            t += 1.0 / 60.0
        }
        #expect(sawStream)
        #expect(t < 15)
        // Measure the jug now: once the glass is served, the next order may bring a different drink and a fresh jug.
        let fillAfterPour: Double = s.snapshot.jug.fill
        run(s, seconds: 3.0, tilt: 0, events: &events)

        let judged: [Judgement] = servedJudgements(events)
        #expect(judged.count == 1)
        if let j = judged.first {
            #expect(j.isHit, "judged \(j)")
        }
        #expect(fillAfterPour < 0.9)
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

    // MARK: Pour feel (round 2 targets)

    @Test func tumblerFillsToTheLineInTwoToThreeSecondsAtAComfortableTilt() {
        // Practice on a phone: no gate, endless basics; find tumblers and time the pour from first landing to the line.
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: phoneLayout(), seed: 4)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let glass = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        #expect(glass.shape.id == "tumbler")
        let line: CGFloat = glass.lineHeight
        // A mid-fill jug (the typical state mid-shift), 15° of lid past the pour point.
        s.debugSetJugFill(0.6)
        let tilt: Double = pourLid(fill: 0.6) + 15
        var t: Double = 0
        var firstLanding: Double? = nil
        var reached: Double? = nil
        while t < 10 && reached == nil {
            s.step(dt: 1.0 / 60.0, tilt: tilt)
            t += 1.0 / 60.0
            guard let g = s.snapshot.glasses.first(where: { (x: GlassState) -> Bool in x.id == glass.id }) else { break }
            if firstLanding == nil && g.liquidHeight > 0 { firstLanding = t }
            if g.liquidHeight >= line { reached = t }
        }
        let start: Double = firstLanding ?? 0
        let end: Double = reached ?? 99
        let fillTime: Double = end - start
        #expect(fillTime >= 1.6 && fillTime <= 3.2, "fill time \(fillTime)")
    }

    @Test func streamLandsWithinEightPointsOfTheGlassCentre() {
        // Every glass style the campaign uses, poured at shallow, typical and steep tilts from full to low jugs.
        let levels: [String] = ["1-2", "1-4", "1-7", "3-3", "3-5", "5-2"]
        var samples: Int = 0
        var worst: CGFloat = 0
        for id in levels {
            let s: GameSession = GameSession(mode: .shift(id), layout: duoLayout(), seed: 21)
            var events: [GameEvent] = []
            run(s, seconds: 1.0, tilt: 0, events: &events)
            let offsets: [Double] = [4, 10, 18, 28, 40]
            var k: Int = 0
            var glassID: Int = -1
            var stopped: Bool = false
            var t: Double = 0
            while t < 60 && !s.isFinished {
                if let g = activeGlass(s) {
                    if g.id != glassID {
                        glassID = g.id
                        stopped = false
                        k += 1
                    }
                    let tilt: Double = carefulTilt(s, offset: offsets[k % offsets.count], stopAt: -0.02, stopped: &stopped)
                    s.step(dt: 1.0 / 60.0, tilt: tilt)
                    if let g2 = activeGlass(s) {
                        let rimY: CGFloat = s.layout.counterY + g2.shape.baseThickness + g2.shape.interiorHeight
                        if let x = streamX(at: rimY, s.snapshot.stream), s.snapshot.jug.flow > 0.05 {
                            let off: CGFloat = abs(x - g2.x)
                            worst = max(worst, off)
                            samples += 1
                        }
                    }
                } else {
                    s.step(dt: 1.0 / 60.0, tilt: 0)
                }
                t += 1.0 / 60.0
            }
        }
        #expect(samples > 200)
        #expect(worst <= 8, "worst landing offset \(worst)")
    }

    @Test func noStreamFromAnUprightJugEvenForThickDrinks() {
        for id in ["1-1", "3-1", "3-3"] {   // water, milkshake, honey
            let s: GameSession = GameSession(mode: .shift(id), layout: duoLayout(), seed: 8)
            var events: [GameEvent] = []
            run(s, seconds: 1.0, tilt: 0, events: &events)
            let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 20
            run(s, seconds: 0.8, tilt: tilt, events: &events)
            #expect(s.snapshot.jug.flow > 0.2, "\(id) should be pouring")
            // Slam it flat: the rope in the spout thins and snaps within ropeMaxTime.
            run(s, seconds: CoreTuning.ropeMaxTime + 0.05, tilt: 0, events: &events)
            #expect(s.snapshot.jug.angle == 0)
            #expect(s.snapshot.jug.flow == 0, "\(id) still flowing upright")
            // Whatever was in the air lands; nothing leaves the lip of an upright jug.
            run(s, seconds: 1.0, tilt: 0, events: &events)
            #expect(s.snapshot.stream.isEmpty, "\(id) stream from an upright jug")
        }
    }

    @Test func viscousDrinksStillTrailAfterTheyAreTippedBack() {
        // Honey keeps coming briefly after the hand stops (the rope), water stops almost at once.
        func tail(_ id: String) -> Double {
            let s: GameSession = GameSession(mode: .shift(id), layout: duoLayout(), seed: 8)
            var events: [GameEvent] = []
            run(s, seconds: 1.0, tilt: 0, events: &events)
            run(s, seconds: 0.8, tilt: pourLid(fill: s.snapshot.jug.fill) + 20, events: &events)
            let before: Double = s.snapshot.jug.fill
            run(s, seconds: 1.0, tilt: 0, events: &events)
            return before - s.snapshot.jug.fill
        }
        let water: Double = tail("1-1")
        let honey: Double = tail("3-3")
        #expect(honey > water * 2, "honey tail \(honey) vs water \(water)")
    }

    // MARK: Flat gate

    @Test func duoRunStartsBehindTheFlatGate() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 2)
        #expect(s.snapshot.needsFlat)
        var events: [GameEvent] = []
        // Held up like a laptop from the start: nothing pours and the jug stays upright.
        run(s, seconds: 3.0, tilt: 70, events: &events)
        #expect(s.snapshot.needsFlat)
        #expect(s.snapshot.jug.angle == 0)
        #expect(s.snapshot.stream.isEmpty)
        let starts: Int = count(events) { (e: GameEvent) -> Bool in
            if case .pourStarted = e { return true }
            return false
        }
        #expect(starts == 0)
        // Patience is paused while the gate is closed (1-1 has none; 1-3 has 14 s — checked below).
        // Lay it flat: the gate opens once.
        run(s, seconds: 0.2, tilt: 0, events: &events)
        #expect(!s.snapshot.needsFlat)
        let armed: Int = count(events) { (e: GameEvent) -> Bool in
            if case .flatArmed = e { return true }
            return false
        }
        #expect(armed == 1)
        run(s, seconds: 1.0, tilt: pourLid(fill: s.snapshot.jug.fill) + 15, events: &events)
        #expect(!s.snapshot.stream.isEmpty)
        // Resume: the App re-arms the gate.
        s.requireFlat()
        #expect(s.snapshot.needsFlat)
        run(s, seconds: 0.6, tilt: 60, events: &events)
        #expect(s.snapshot.jug.flow == 0)
        #expect(s.snapshot.jug.angle == 0)
    }

    @Test func flatGatePausesPatienceAndIsSkippedWithoutAFold() {
        let gated: GameSession = GameSession(mode: .shift("1-3"), layout: duoLayout(), seed: 2)
        var events: [GameEvent] = []
        run(gated, seconds: 4.0, tilt: 50, events: &events)
        let left: Double? = gated.snapshot.glasses.first?.patienceLeft
        #expect(left == Double(14))

        let phone: GameSession = GameSession(mode: .shift("1-1"), layout: phoneLayout(), seed: 2)
        #expect(!phone.snapshot.needsFlat)
        var phoneEvents: [GameEvent] = []
        run(phone, seconds: 1.0, tilt: 0, events: &phoneEvents)
        run(phone, seconds: 1.0, tilt: pourLid(fill: phone.snapshot.jug.fill) + 15, events: &phoneEvents)
        #expect(!phone.snapshot.stream.isEmpty)
        phone.requireFlat()
        #expect(!phone.snapshot.needsFlat)
        let armed: Int = count(phoneEvents) { (e: GameEvent) -> Bool in
            if case .flatArmed = e { return true }
            return false
        }
        #expect(armed == 0)

        let practice: GameSession = GameSession(mode: .practice, layout: duoLayout(), seed: 2)
        #expect(!practice.snapshot.needsFlat)
    }

    // MARK: Serving rhythm

    @Test func lockedInThenAQuickVerdictAndAFastChangeover() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 6)
        var t: Double = 0
        var stopped: Bool = false
        var glassID: Int = -1
        var lockTimes: [Int: Double] = [:]
        var idleSince: Double? = nil
        var verdictDelays: [Double] = []
        var lockToVerdict: [Double] = []
        var servedAt: [Double] = []
        var arrivedAt: [Double] = []
        var perfects: Int = 0
        var locks: Int = 0
        while t < 60 && !s.isFinished {
            var tilt: Double = 0
            if let g = activeGlass(s) {
                if g.id != glassID {
                    glassID = g.id
                    stopped = false
                }
                tilt = carefulTilt(s, offset: 16, stopAt: -0.004, stopped: &stopped)
            }
            let events: [GameEvent] = s.step(dt: 1.0 / 60.0, tilt: tilt)
            t += 1.0 / 60.0
            // "The stream finished landing": nothing flowing and nothing in the air.
            let idle: Bool = s.snapshot.jug.flow == 0 && s.snapshot.stream.isEmpty && s.snapshot.droplets.isEmpty
            if idle {
                if idleSince == nil { idleSince = t }
            } else {
                idleSince = nil
            }
            for e in events {
                switch e {
                case .lockedIn(let id):
                    locks += 1
                    lockTimes[id] = t
                    let inBand: Bool = s.snapshot.glasses.first(where: { (g: GlassState) -> Bool in g.id == id })?.inPerfectBand ?? false
                    #expect(inBand)
                case .served(let id, let j, _):
                    servedAt.append(t)
                    if j == .perfect { perfects += 1 }
                    if let since = idleSince { verdictDelays.append(t - since) }
                    if let lt = lockTimes[id] { lockToVerdict.append(t - lt) }
                case .glassArrived:
                    arrivedAt.append(t)
                default:
                    break
                }
            }
        }
        #expect(s.isFinished)
        #expect(perfects >= 4, "perfects \(perfects)")
        #expect(locks >= perfects)
        for d in verdictDelays { #expect(d <= 0.5, "verdict \(d) s after the stream landed") }
        for d in lockToVerdict { #expect(d >= 0.2 && d <= 0.45, "lock → verdict \(d)") }
        // Changeover: verdict → next glass in place.
        var i: Int = 0
        while i + 1 < arrivedAt.count && i < servedAt.count {
            let gap: Double = arrivedAt[i + 1] - servedAt[i]
            #expect(gap > 0 && gap <= 0.9, "changeover \(gap)")
            i += 1
        }
    }

    // MARK: Spill

    @Test func floodingIsJudgedSpillLiveAndPuddlesSpread() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 5)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        var t: Double = 0
        var overflowed: Bool = false
        var spillSameStep: Bool = false
        while t < 15 && !overflowed {
            let step: [GameEvent] = s.step(dt: 1.0 / 60.0, tilt: 70)
            var sawOverflow: Bool = false
            for e in step {
                events.append(e)
                if case .overflowStarted = e { sawOverflow = true }
                if case .served(_, let j, _) = e, j == .spill, sawOverflow { spillSameStep = true }
            }
            if sawOverflow { overflowed = true }
            t += 1.0 / 60.0
        }
        #expect(overflowed)
        #expect(spillSameStep)
        let firstPoints: Int = s.snapshot.puddles.count
        #expect(firstPoints >= 1)
        // Keep pouring a beat (the hand is late): the overflow keeps sheeting and the puddle spreads.
        run(s, seconds: 0.6, tilt: 70, events: &events)
        run(s, seconds: 2.0, tilt: 0, events: &events)
        let judged: [Judgement] = servedJudgements(events)
        let first: Judgement? = judged.first
        #expect(first == Judgement.spill)
        #expect(s.snapshot.strikes == 1)
        let points: [CGPoint] = s.snapshot.puddles
        #expect(points.count >= 6, "puddle points \(points.count)")
        var lo: CGFloat = CGFloat.greatestFiniteMagnitude
        var hi: CGFloat = -CGFloat.greatestFiniteMagnitude
        for p in points {
            #expect(p.y == s.layout.counterY)
            lo = min(lo, p.x)
            hi = max(hi, p.x)
        }
        #expect(hi - lo >= 70, "puddle span \(hi - lo)")
        #expect(lo >= 130 && hi <= 540)
    }

    // MARK: Modes

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

/// Bounding box of a point list (test helper; Core has no such public helper).
enum CorePolygonBounds {
    static func of(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return CGRect.zero }
        var minX: CGFloat = first.x
        var maxX: CGFloat = first.x
        var minY: CGFloat = first.y
        var maxY: CGFloat = first.y
        for p in pts {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
