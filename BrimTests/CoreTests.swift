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
        // Round 3 (jugScale 0.93): interior ~158 wide (with the spout) and ~201 tall; ~176 × 219 drawn with walls.
        let b: CGRect = CorePolygonBounds.of(jug.outline)
        #expect(b.width >= 145 && b.width <= 185, "width \(b.width)")
        #expect(b.height >= 190 && b.height <= 230, "height \(b.height)")
        // Same drink volume and pour feel as round 2 (flow and volume are compensated for the scale).
        let drink: Double = Double(jug.capacity) * CoreTuning.jugVolumeScale
        #expect(abs(drink - 86_200) < 1_500, "drink volume \(drink)")
        // Tipped past its pour point, the liquid fills the channel right up to the lip.
        let threshold: Double = JugGeometry.pourThreshold(jug, fill: 0.6)
        let pose = JugGeometry.pose(jug, angle: threshold + 10, fill: 0.6, at: CGPoint(x: 0, y: 0))
        #expect(pose.headAboveLip > CGFloat(0))
        var nearLip: Bool = false
        for p in pose.liquid where abs(p.x - pose.lip.x) < 1 && abs(p.y - pose.lip.y) < 1 { nearLip = true }
        #expect(nearLip)
    }

    @Test func jugStaysClearOfTheHUDTheFoldAndTheLeftEdge() {
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
            // Round 3: the body (interior + 9 pt walls) never left of x 118 (the iPhone crop starts at ~116), inside
            // x ≤ 540, below the HUD band; the upright jug keeps ~60 pt of handle room inside the crop too.
            #expect(maxY + 9 <= 842 - 10, "tilt \(tilt): top \(maxY)")
            #expect(minX - 9 >= 118, "tilt \(tilt): left \(minX)")
            #expect(maxX + 9 <= 540, "tilt \(tilt): right \(maxX)")
            #expect(minY >= layout.creaseMaxY, "tilt \(tilt): bottom \(minY)")
            if jug.angle == 0 {
                // At rest nothing crosses the fold: the walls clear the crease band + its 8 pt keep-out.
                #expect(minY - 9 >= layout.creaseMaxY + 8, "at rest: bottom \(minY)")
                #expect(minX - 9 - 60 >= 118, "upright handle room \(minX)")
            }
            // Mid and low jugs pour at ≥ 55° of jug angle: there the lip sits 50…90 pt above the crease.
            if jug.angle >= 55 {
                let above: CGFloat = jug.lip.y - layout.creaseMaxY
                #expect(above >= 50 && above <= 90, "tilt \(tilt): lip +\(above)")
            }
            tilt += 1
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
        // Round 5 (QA-2 P1-3): past the Good band with nothing over the rim is `over`; `spill` only when it overflowed.
        #expect(Rules.judge(top: 130, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .over)
        #expect(Rules.judge(top: 199, line: line, interior: interior, overflowed: false, perfectBand: 0.025) == .over)
        #expect(Rules.judge(top: 100, line: line, interior: interior, overflowed: true, perfectBand: 0.025) == .spill)
        #expect(Rules.judge(top: 200, line: line, interior: interior, overflowed: true, perfectBand: 0.025) == .spill)
        #expect(!Judgement.over.isHit)
        #expect(Rules.points(for: .over, multiplier: 5) == 0)
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
        // Round 6 balance pass: stars count misses (short / over / spill), not Perfects.
        // No miss → 3★, whatever the Perfect count (the Flawless crown is the all-Perfect goal).
        #expect(Rules.stars(perfects: 6, hits: 6, spills: 0, total: 6) == 3)
        #expect(Rules.stars(perfects: 3, hits: 6, spills: 0, total: 6) == 3)
        #expect(Rules.stars(perfects: 0, hits: 6, spills: 0, total: 6) == 3)
        // One miss → 2★, whether it was a spill or a short / over.
        #expect(Rules.stars(perfects: 5, hits: 5, spills: 1, total: 6) == 2)
        #expect(Rules.stars(perfects: 5, hits: 5, spills: 0, total: 6) == 2)
        #expect(Rules.stars(perfects: 7, hits: 7, spills: 0, total: 8) == 2)
        // Two misses (still cleared: under 3 strikes) → 1★.
        #expect(Rules.stars(perfects: 4, hits: 4, spills: 0, total: 6) == 1)
        #expect(Rules.stars(perfects: 6, hits: 6, spills: 2, total: 8) == 1)
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
        // The glass at the stop, plus the next order waiting in the slot.
        let glasses: [GlassState] = s.snapshot.glasses
        #expect(glasses.count == 2)
        if glasses.count == 2 {
            #expect(glasses[0].liquidHeight == CGFloat(0))
            #expect(glasses[0].phase == .filling)
            #expect(glasses[1].isWaitingInSlot)
            #expect(glasses[1].liquidHeight == CGFloat(0))
        }
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
        var stopMin: CGFloat = CGFloat.greatestFiniteMagnitude
        var stopMax: CGFloat = -CGFloat.greatestFiniteMagnitude
        var stops: Int = 0
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
                        // Round 3: every glass stops left of x 372 (the pour is centred), from full to low jugs.
                        stopMin = min(stopMin, g.x)
                        stopMax = max(stopMax, g.x)
                        stops += 1
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
        #expect(stops >= 20, "glasses placed \(stops)")
        #expect(stopMax <= 372, "stop x up to \(stopMax)")
        #expect(stopMin >= 340, "stop x down to \(stopMin)")
    }

    @Test func everyFirstGlassStopsCentredAndInsideTheVisibleBand() {
        var modes: [GameMode] = [GameMode.rush, GameMode.daily(0), GameMode.daily(297)]
        for l in LevelCatalog.levels where l.conveyorSpeed == nil { modes.append(GameMode.shift(l.id)) }
        for mode in modes {
            for layout in [duoLayout(), phoneLayout()] {
                let s: GameSession = GameSession(mode: mode, layout: layout, seed: 3)
                var events: [GameEvent] = []
                run(s, seconds: 0.7, tilt: 0, events: &events)
                guard let g = activeGlass(s) else {
                    Issue.record("\(mode): no glass in place")
                    continue
                }
                var widest: CGFloat = 0
                for p in g.shape.profile where p.x > widest { widest = p.x }
                let half: CGFloat = widest + g.shape.wall
                #expect(g.x <= 372 && g.x >= 340, "\(mode): stop \(g.x)")
                #expect(g.x - half >= 130 && g.x + half <= 540, "\(mode): glass spans \(g.x - half)…\(g.x + half)")
                #expect(g.x - half >= layout.visibleRect.minX && g.x + half <= layout.visibleRect.maxX)
            }
        }
    }

    // MARK: Next-glass slot (round 3)

    @Test func theNextGlassWaitsInTheSlotThenSlidesToTheStop() {
        for layout in [duoLayout(), phoneLayout()] {
            let s: GameSession = GameSession(mode: .shift("1-1"), layout: layout, seed: 6)
            var events: [GameEvent] = []
            run(s, seconds: 1.2, tilt: 0, events: &events)
            let waiting: [GlassState] = s.snapshot.glasses.filter { (g: GlassState) -> Bool in g.isWaitingInSlot }
            #expect(waiting.count == 1)
            guard let w = waiting.first, let a = activeGlass(s) else {
                Issue.record("no waiting or active glass")
                continue
            }
            // Round 4: the waiting glass is drawn smaller; its coaster keeps 16 pt from the visible edge.
            let wLeft: Double = NextGlassSlot.leftReach(w.shape, hasFold: layout.hasFold)
            let wRight: Double = NextGlassSlot.rightReach(w.shape, hasFold: layout.hasFold)
            let aLeft: Double = NextGlassSlot.bodyHalfWidth(a.shape) + NextGlassSlot.handleReach(a.shape)
            if layout.hasFold {
                #expect(abs(w.x - CGFloat(CoreTuning.nextGlassX)) < 0.5, "slot at \(w.x)")
            }
            // Fully on screen with the margin (nudged right on narrow phones), clear of the glass at the stop, nothing
            // poured in.
            let leftEdge: Double = Double(w.x) - wLeft
            #expect(leftEdge >= Double(layout.visibleRect.minX) + CoreTuning.nextGlassEdgeMargin - 0.01,
                    "slot cropped at \(leftEdge)")
            #expect(Double(w.x) + wRight + CoreTuning.nextGlassGap <= Double(a.x) - aLeft + 0.01, "slot overlaps the stop")
            #expect(w.lineOpacity == 0)
            #expect(w.phase == .arriving)
            #expect(!a.isWaitingInSlot)

            // Serve the glass at the stop: the waiting one is the next to arrive, and the slot refills.
            var stopped: Bool = false
            var glassID: Int = a.id
            var arrivals: [Int] = []
            var t: Double = 0
            while t < 15 && arrivals.isEmpty {
                var tilt: Double = 0
                if let g = activeGlass(s) {
                    if g.id != glassID {
                        glassID = g.id
                        stopped = false
                    }
                    tilt = carefulTilt(s, offset: 15, stopAt: -0.004, stopped: &stopped)
                }
                for e in s.step(dt: 1.0 / 60.0, tilt: tilt) {
                    if case .glassArrived(let id) = e { arrivals.append(id) }
                }
                t += 1.0 / 60.0
            }
            let firstArrival: Int? = arrivals.first
            #expect(firstArrival == w.id)
            let next: [GlassState] = s.snapshot.glasses.filter { (g: GlassState) -> Bool in g.isWaitingInSlot }
            #expect(next.count == 1)
            if let n = next.first { #expect(n.id != w.id && n.id != a.id) }
        }
    }

    @Test func noSlotOnConveyorsOrInPractice() {
        for mode in [GameMode.shift("4-1"), GameMode.shift("4-5"), GameMode.practice] {
            let s: GameSession = GameSession(mode: mode, layout: duoLayout(), seed: 5)
            var t: Double = 0
            var sawWaiting: Bool = false
            while t < 12 && !s.isFinished {
                var tilt: Double = 0
                for g in s.snapshot.glasses where g.phase == .filling && !g.overflowing { tilt = 40 }
                s.step(dt: 1.0 / 60.0, tilt: tilt)
                for g in s.snapshot.glasses where g.isWaitingInSlot { sawWaiting = true }
                t += 1.0 / 60.0
            }
            #expect(!sawWaiting, "\(mode) used the slot")
        }
    }

    // MARK: Next-glass slot margin (round 4, REVIEW-3 P1-4)

    /// Every canvas the game can be played on: the Duo inner display (fold), the Duo's book-pose touch column and
    /// cover, and today's iPhones (no fold).
    private func supportedCanvases() -> [(name: String, layout: WorldLayout)] {
        return [
            (name: "duo-inner", layout: WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)),
            (name: "duo-book-touch", layout: WorldLayout.make(canvas: CGSize(width: 468, height: 669), hasFold: false)),
            (name: "duo-cover", layout: WorldLayout.make(canvas: CGSize(width: 466, height: 678), hasFold: false)),
            (name: "iphone-se", layout: WorldLayout.make(canvas: CGSize(width: 375, height: 667), hasFold: false)),
            (name: "iphone-mini", layout: WorldLayout.make(canvas: CGSize(width: 375, height: 812), hasFold: false)),
            (name: "iphone-16", layout: WorldLayout.make(canvas: CGSize(width: 393, height: 852), hasFold: false)),
            (name: "iphone-18-pro", layout: WorldLayout.make(canvas: CGSize(width: 402, height: 874), hasFold: false)),
            (name: "iphone-air", layout: WorldLayout.make(canvas: CGSize(width: 420, height: 912), hasFold: false)),
            (name: "iphone-pro-max", layout: WorldLayout.make(canvas: CGSize(width: 440, height: 956), hasFold: false)),
        ]
    }

    @Test func nextGlassSlotKeepsSixteenPointsToItsCoasterOnEveryCanvas() {
        #expect(CoreTuning.nextGlassEdgeMargin >= 16)
        let margin: Double = CoreTuning.nextGlassEdgeMargin
        let stopXs: [Double] = [340, 356, 372]
        let tumbler: GlassShape = GlassCatalog.shape("tumbler")
        var problems: [String] = []
        for canvas in supportedCanvases() {
            let layout: WorldLayout = canvas.layout
            let fold: Bool = layout.hasFold
            let minX: Double = Double(layout.visibleRect.minX)
            let scale: Double = NextGlassSlot.scale(hasFold: fold)
            for slot in GlassCatalog.all {
                let coaster: Double = NextGlassSlot.coasterHalfWidth(slot)
                let glassLeft: Double = (NextGlassSlot.bodyHalfWidth(slot) + NextGlassSlot.handleReach(slot)) * scale
                for stop in GlassCatalog.all {
                    for stopX in stopXs {
                        let placed: Double? = NextGlassSlot.x(for: slot, layout: layout, stop: (x: stopX, shape: stop))
                        guard let x = placed else {
                            // The Duo is the product: there the slot always has room.
                            if fold { problems.append("\(canvas.name): no room for \(slot.id) behind \(stop.id) @\(stopX)") }
                            continue
                        }
                        // Measured to the coaster's edge (and to the scaled glass / mug handle if that reaches further).
                        let edge: Double = min(x - coaster, x - glassLeft)
                        if edge < minX + margin - 1e-9 {
                            problems.append("\(canvas.name): \(slot.id) edge \(edge) < \(minX + margin)")
                        }
                        let stopLeft: Double = stopX - NextGlassSlot.bodyHalfWidth(stop) - NextGlassSlot.handleReach(stop)
                        let slotRight: Double = x + NextGlassSlot.bodyHalfWidth(slot) * scale
                        if slotRight + CoreTuning.nextGlassGap > stopLeft + 1e-9 {
                            problems.append("\(canvas.name): \(slot.id) touches \(stop.id) @\(stopX)")
                        }
                    }
                }
            }
            // The everyday case has room on every canvas: a tumbler waiting behind a tumbler.
            for stopX in stopXs {
                let placed: Double? = NextGlassSlot.x(for: tumbler, layout: layout, stop: (x: stopX, shape: tumbler))
                if placed == nil { problems.append("\(canvas.name): no tumbler slot @\(stopX)") }
            }
        }
        #expect(problems == [String]())
    }

    @Test func waitingGlassesInRealRunsKeepTheMargin() {
        var modes: [GameMode] = [GameMode.rush, GameMode.daily(0), GameMode.daily(123), GameMode.daily(297)]
        for l in LevelCatalog.levels where l.conveyorSpeed == nil && l.index % 2 == 1 { modes.append(GameMode.shift(l.id)) }
        let canvases: [WorldLayout] = [
            duoLayout(),
            phoneLayout(),
            WorldLayout.make(canvas: CGSize(width: 375, height: 812), hasFold: false),
        ]
        var problems: [String] = []
        var checked: Int = 0
        for layout in canvases {
            let limit: Double = Double(layout.visibleRect.minX) + CoreTuning.nextGlassEdgeMargin - 0.01
            for mode in modes {
                let s: GameSession = GameSession(mode: mode, layout: layout, seed: 11)
                var stopped: Bool = false
                var glassID: Int = -1
                var lastX: [Int: CGFloat] = [:]
                var t: Double = 0
                while t < 12 && !s.isFinished {
                    var tilt: Double = 0
                    if let g = activeGlass(s) {
                        if g.id != glassID {
                            glassID = g.id
                            stopped = false
                        }
                        tilt = carefulTilt(s, offset: 15, stopAt: -0.01, stopped: &stopped)
                    }
                    s.step(dt: 1.0 / 60.0, tilt: tilt)
                    for w in s.snapshot.glasses where w.isWaitingInSlot {
                        if let prev = lastX[w.id], abs(prev - w.x) < 0.001 {
                            // Standing in the slot.
                            checked += 1
                            let edge: Double = Double(w.x) - NextGlassSlot.leftReach(w.shape, hasFold: layout.hasFold)
                            if edge < limit { problems.append("\(mode) \(w.shape.id): edge \(edge) < \(limit)") }
                        }
                        lastX[w.id] = w.x
                    }
                    t += 1.0 / 60.0
                }
            }
        }
        #expect(checked > 200, "slot frames checked \(checked)")
        #expect(problems.isEmpty, "\(problems.prefix(5))")
    }

    @Test func upcomingOrderNamesTheNextGlass() {
        guard let level = LevelCatalog.level("1-2") else {
            Issue.record("no level 1-2")
            return
        }
        let s: GameSession = GameSession(mode: .shift("1-2"), layout: duoLayout(), seed: 3)
        let expected: GlassOrder? = level.orders[1]
        let atStart: GlassOrder? = s.upcomingOrder
        #expect(atStart == expected)
        var events: [GameEvent] = []
        run(s, seconds: 1.2, tilt: 0, events: &events)
        let waiting: [GlassState] = s.snapshot.glasses.filter { (g: GlassState) -> Bool in g.isWaitingInSlot }
        #expect(waiting.count == 1)
        let later: GlassOrder? = s.upcomingOrder
        #expect(later == expected)
        if let w = waiting.first { #expect(w.shape.id == level.orders[1].glass) }
    }

    @Test func adoptCanvasKeepsTheRunAndFollowsTheFold() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 3)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        let before: Double = s.snapshot.time
        let firstGlass: Int? = activeGlass(s)?.id
        // Book pose, touch column: no fold, so no flat gate.
        s.adoptCanvas(WorldLayout.make(canvas: CGSize(width: 468, height: 669), hasFold: false))
        #expect(s.layout.hasFold == false)
        #expect(s.snapshot.time == before)
        s.requireFlat()
        #expect(s.snapshot.needsFlat == false)
        // Back to tabletop: the gate works again on the next resume.
        s.adoptCanvas(duoLayout())
        s.requireFlat()
        #expect(s.snapshot.needsFlat)
        #expect(s.layout.size == duoLayout().size)
        let sameGlass: Int? = activeGlass(s)?.id
        #expect(sameGlass == firstGlass)
    }

    // MARK: Hot path (round 4, QA P2-8): no allocations, identical numbers

    @Test func allocationFreeAreaAndLevelAreBitForBitTheSame() {
        let jug: JugShape = JugGeometry.standard
        var mismatches: [String] = []
        var scratch: [CGPoint] = []
        var angle: Double = 0
        while angle <= 150 {
            let outline: [CGPoint] = JugGeometry.transform(jug.outline, jug: jug, angle: angle, at: CGPoint(x: 0, y: 0))
            var lo: CGFloat = outline[0].y
            var hi: CGFloat = outline[0].y
            for p in outline {
                lo = min(lo, p.y)
                hi = max(hi, p.y)
            }
            var k: Int = 0
            while k <= 40 {
                let level: CGFloat = lo - 5 + (hi - lo + 10) * CGFloat(k) / 40
                let fast: CGFloat = CorePolygon.areaBelow(outline, level: level)
                let slow: CGFloat = CorePolygon.area(CorePolygon.clipBelow(outline, level: level))
                if fast != slow { mismatches.append("area a=\(angle) level=\(level): \(fast) vs \(slow)") }
                k += 1
            }
            for fill in [0.0, 0.025, 0.3, 0.75, 1.0] {
                // The round-3 bisection, verbatim, as the reference.
                let volume: CGFloat = CGFloat(fill) * jug.capacity
                var rlo: CGFloat = lo
                var rhi: CGFloat = hi
                var it: Int = 0
                while it < 34 {
                    let mid: CGFloat = (rlo + rhi) * 0.5
                    if CorePolygon.area(CorePolygon.clipBelow(outline, level: mid)) < volume { rlo = mid } else { rhi = mid }
                    it += 1
                }
                let total: CGFloat = CorePolygon.area(outline)
                let reference: CGFloat = volume <= 0 ? lo : (volume >= total ? hi : (rlo + rhi) * 0.5)
                let level: CGFloat = CorePolygon.levelForArea(outline, area: volume)
                if level != reference { mismatches.append("level a=\(angle) fill=\(fill): \(level) vs \(reference)") }
                let headA: CGFloat = JugGeometry.head(jug, angle: angle, fill: fill, scratch: &scratch)
                let headB: CGFloat = JugGeometry.head(jug, angle: angle, fill: fill)
                if headA != headB { mismatches.append("head a=\(angle) fill=\(fill)") }
            }
            angle += 7.5
        }
        #expect(mismatches == [String]())
    }

    @Test func theSameSeedAndInputsGiveTheSameRun() {
        func play(_ layout: WorldLayout) -> (Int, Double, Int, [Judgement]) {
            let s: GameSession = GameSession(mode: .rush, layout: layout, seed: 77)
            var stopped: Bool = false
            var glassID: Int = -1
            var t: Double = 0
            while t < 20 && !s.isFinished {
                var tilt: Double = 0
                if let g = activeGlass(s) {
                    if g.id != glassID {
                        glassID = g.id
                        stopped = false
                    }
                    tilt = carefulTilt(s, offset: 18, stopAt: -0.01, stopped: &stopped)
                }
                s.step(dt: 1.0 / 60.0, tilt: tilt)
                t += 1.0 / 60.0
            }
            let judged: [Judgement] = s.result?.judgements ?? []
            return (s.snapshot.score, s.snapshot.jug.fill, s.snapshot.ordersDone, judged)
        }
        for layout in [duoLayout(), phoneLayout()] {
            let a = play(layout)
            let b = play(layout)
            #expect(a.0 == b.0)
            #expect(a.1 == b.1)
            #expect(a.2 == b.2)
            #expect(a.3 == b.3)
            #expect(a.2 >= 2, "only \(a.2) glasses in 20 s")
        }
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
        // Whatever 1-3's first glass allows (balance tuning moves it), none of it is spent behind the gate.
        let full: Double? = gated.snapshot.glasses.first?.patienceTotal
        #expect(full != nil)
        #expect(left == full)

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

    // MARK: Pause mid-pour (round 3, decision 1)

    @Test func pausingMidPourProducesNoJudgementUntilThePlayerPoursAgain() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 12)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let glass = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        // Pour until the glass is about half way to its line, stream running.
        let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 15
        var t: Double = 0
        var half: Bool = false
        while t < 8 && !half {
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
            if let g = activeGlass(s), g.liquidHeight >= g.lineHeight * 0.5 { half = true }
        }
        #expect(half)
        #expect(s.snapshot.jug.flow > 0.05)
        #expect(!s.snapshot.stream.isEmpty)
        let before: CGFloat = activeGlass(s)?.liquidHeight ?? 0

        // The phone is folded shut: the App stops stepping (nothing moves while paused), then on reopening re-arms
        // the flat gate and steps with the phone flat for 2 s.
        s.requireFlat()
        #expect(s.snapshot.needsFlat)
        var after: [GameEvent] = []
        run(s, seconds: 2.0, tilt: 0, events: &after)
        #expect(servedJudgements(after).isEmpty, "judged while resuming: \(servedJudgements(after))")
        let locks: Int = count(after) { (e: GameEvent) -> Bool in
            if case .lockedIn = e { return true }
            return false
        }
        #expect(locks == 0)
        let armed: Int = count(after) { (e: GameEvent) -> Bool in
            if case .flatArmed = e { return true }
            return false
        }
        #expect(armed == 1)
        // What was in the air landed in the glass; nothing more left the jug.
        #expect(s.snapshot.stream.isEmpty)
        #expect(s.snapshot.jug.flow == 0)
        let still: GlassState? = activeGlass(s)
        let stillID: Int? = still?.id
        #expect(stillID == glass.id)
        let landed: CGFloat = still?.liquidHeight ?? 0
        #expect(landed > before, "in-flight stream should land: \(before) → \(landed)")
        #expect(s.snapshot.strikes == 0)

        // Pour again and stop: now it is judged, exactly once.
        var again: [GameEvent] = []
        var stopped: Bool = false
        t = 0
        while t < 10 && servedJudgements(again).isEmpty {
            let tl: Double = carefulTilt(s, offset: 12, stopAt: -0.004, stopped: &stopped)
            again.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tl))
            t += 1.0 / 60.0
        }
        #expect(servedJudgements(again).count == 1)
    }

    @Test func resumeFreezesPatienceBehindTheGateAndNeverStrandsAGlass() {
        let s: GameSession = GameSession(mode: .shift("1-3"), layout: duoLayout(), seed: 4)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        run(s, seconds: 0.7, tilt: pourLid(fill: s.snapshot.jug.fill) + 15, events: &events)
        #expect(s.snapshot.jug.flow > 0.05)
        s.requireFlat()
        let p0: Double? = activeGlass(s)?.patienceLeft
        #expect(p0 != nil)
        // Reopened but held up like a laptop: jug upright, nothing pours, patience frozen, no verdict.
        var held: [GameEvent] = []
        run(s, seconds: 3.0, tilt: 60, events: &held)
        let p1: Double? = activeGlass(s)?.patienceLeft
        #expect(p1 == p0)
        #expect(s.snapshot.needsFlat)
        #expect(s.snapshot.jug.angle == 0)
        #expect(s.snapshot.jug.flow == 0)
        #expect(servedJudgements(held).isEmpty)
        // Laid flat but never poured again: still no verdict for a while…
        var flat: [GameEvent] = []
        run(s, seconds: CoreTuning.resumeServeIdle - 0.5, tilt: 0, events: &flat)
        #expect(servedJudgements(flat).isEmpty)
        // …then the customer takes the glass (nobody is stuck with an unservable glass).
        run(s, seconds: 1.5, tilt: 0, events: &flat)
        #expect(servedJudgements(flat).count == 1)
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
        // Round 6: serveIdle 0.35 → 0.5 s (time to top up a still drink); the lock-in cue still fires at once.
        let idleServe: Double = CoreTuning.serveIdle
        for d in verdictDelays { #expect(d <= idleServe + 0.15, "verdict \(d) s after the stream landed") }
        for d in lockToVerdict { #expect(d >= idleServe - 0.15 && d <= idleServe + 0.1, "lock → verdict \(d)") }
        // Changeover: verdict → next glass in place.
        var i: Int = 0
        while i + 1 < arrivedAt.count && i < servedAt.count {
            let gap: Double = arrivedAt[i + 1] - servedAt[i]
            #expect(gap > 0 && gap <= 0.9, "changeover \(gap)")
            i += 1
        }
    }

    // MARK: Spill

    @Test func floodingIsJudgedSpillLiveAndItsPuddleSpreadsThenDries() {
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
        var spilledID: Int = -1
        for e in events {
            if case .served(let id, let j, _) = e, j == .spill { spilledID = id }
        }
        #expect(spilledID >= 0)
        // Keep pouring a beat (the hand is late): the overflow keeps sheeting and the puddle spreads.
        run(s, seconds: 0.6, tilt: 70, events: &events)
        run(s, seconds: 0.2, tilt: 0, events: &events)
        let judged: [Judgement] = servedJudgements(events)
        let first: Judgement? = judged.first
        #expect(first == Judgement.spill)
        #expect(!judged.contains(Judgement.over))
        #expect(s.snapshot.strikes == 1)
        // The glass is still on the counter (catching the last of the stream): its puddle is wide.
        let stillThere: Bool = s.snapshot.glasses.contains(where: { (g: GlassState) -> Bool in
            g.id == spilledID && g.phase == .served
        })
        #expect(stillThere)
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

        // Round 3: the puddle belongs to that glass. Once it leaves, the puddle shrinks and is gone within ~1.5 s,
        // so the next glass never stands in an old puddle.
        let dt: Double = 1.0 / 60.0
        var dryT: Double = 0
        var leaveT: Double? = nil
        var atLeave: Int = 0
        var midway: Int = -1
        while dryT < 6 {
            s.step(dt: dt, tilt: 0)
            dryT += dt
            let present: Bool = s.snapshot.glasses.contains(where: { (g: GlassState) -> Bool in
                g.id == spilledID && g.phase != .leaving
            })
            if leaveT == nil && !present {
                leaveT = dryT
                atLeave = s.snapshot.puddles.count
            }
            if let lt = leaveT {
                if midway < 0 && dryT >= lt + 0.9 { midway = s.snapshot.puddles.count }
                // (+0.4: the last drops of the stream may still sheet over the rim as it starts to leave.)
                if dryT >= lt + CoreTuning.puddleDryTime + 0.4 { break }
            }
        }
        #expect(leaveT != nil)
        #expect(atLeave >= 6, "puddle when the glass left: \(atLeave)")
        #expect(midway >= 1 && midway < atLeave, "drying puddle \(midway) of \(atLeave)")
        #expect(s.snapshot.puddles.isEmpty, "puddle still there: \(s.snapshot.puddles.count) points")
    }

    // MARK: Round 5 (QA-2): the flat gate at 12°, dry jugs, `over`, settled foam, P2s

    private func swaps(_ events: [GameEvent]) -> Int {
        return count(events) { (e: GameEvent) -> Bool in
            if case .jugSwapped = e { return true }
            return false
        }
    }

    private func pourStarts(_ events: [GameEvent]) -> Int {
        return count(events) { (e: GameEvent) -> Bool in
            if case .pourStarted = e { return true }
            return false
        }
    }

    private func flatArms(_ events: [GameEvent]) -> Int {
        return count(events) { (e: GameEvent) -> Bool in
            if case .flatArmed = e { return true }
            return false
        }
    }

    private func overflows(_ events: [GameEvent]) -> Int {
        return count(events) { (e: GameEvent) -> Bool in
            if case .overflowStarted = e { return true }
            return false
        }
    }

    private func dryOuts(_ events: [GameEvent]) -> Int {
        return count(events) { (e: GameEvent) -> Bool in
            if case .jugEmpty = e { return true }
            return false
        }
    }

    @Test func flatGateOpensWithinTwelveDegreesOfFlat() {
        #expect(Rules.flatGateTilt == 12)
        #expect(Rules.deadZone == 6)
        #expect(Rules.readsFlat(lidTilt: 0))
        #expect(Rules.readsFlat(lidTilt: 11))
        #expect(Rules.readsFlat(lidTilt: 12))
        #expect(!Rules.readsFlat(lidTilt: 13))
        #expect(!Rules.readsFlat(lidTilt: Rules.closedTilt))
        #expect(Rules.jugAngle(forLidTilt: Rules.closedTilt) == 0)
        // Anywhere inside the gate the jug is still too upright to pour, even when full.
        let fullPour: Double = JugGeometry.pourThreshold(JugGeometry.standard, fill: 1.0)
        #expect(Rules.jugAngle(forLidTilt: Rules.flatGateTilt) < fullPour)

        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 2)
        var events: [GameEvent] = []
        // Lid 13° (hinge 167°): still shut.
        run(s, seconds: 2.0, tilt: 13, events: &events)
        #expect(s.snapshot.needsFlat)
        // An input's "closed" tilt (the hinge's closing guard) never opens it either.
        run(s, seconds: 0.5, tilt: Rules.closedTilt, events: &events)
        #expect(s.snapshot.needsFlat)
        #expect(flatArms(events) == 0)
        // Lid 11° (hinge 169°): open, and nothing pours.
        run(s, seconds: 0.3, tilt: 11, events: &events)
        #expect(!s.snapshot.needsFlat)
        #expect(flatArms(events) == 1)
        #expect(s.snapshot.jug.flow == 0)
        #expect(pourStarts(events) == 0)
    }

    @Test func aDryJugMidGlassStopsTheStreamAndRefillsOnlyAfterATipBack() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 13)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let glass = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        // Nearly empty, tipped hard: it runs dry into the glass.
        s.debugSetJugFill(0.05)
        var t: Double = 0
        var dry: Bool = false
        while t < 8 && !dry {
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: 88))
            if s.snapshot.jug.fill == 0 { dry = true }
            t += 1.0 / 60.0
        }
        // Snapshot-visible (Feedback's glug-out, Scene's empty jug): fill 0, no outflow. `.jugEmpty` stays Rush's.
        #expect(dry)
        #expect(s.snapshot.jug.flow == 0)
        #expect(dryOuts(events) == 0)
        // Still held tipped: the jug stays empty, no stream, no swap, no verdict.
        var held: [GameEvent] = []
        run(s, seconds: 2.0, tilt: 88, events: &held)
        #expect(swaps(held) == 0)
        #expect(servedJudgements(held).isEmpty)
        #expect(s.snapshot.jug.fill == 0)
        #expect(s.snapshot.jug.flow == 0)
        #expect(s.snapshot.stream.isEmpty)
        let heldID: Int? = activeGlass(s)?.id
        #expect(heldID == glass.id)
        // Tipped back: not yet at 0.3 s, swapped by 0.55 s.
        var back: [GameEvent] = []
        run(s, seconds: 0.3, tilt: 0, events: &back)
        #expect(swaps(back) == 0)
        run(s, seconds: 0.25, tilt: 0, events: &back)
        #expect(swaps(back) == 1)
        // The glass waits for the player to pour again (round 7: the swap, then lock-in and `serveIdle`, ≈ 1.1 s after
        // the refill; see `aDryJugRefillReachesItsVerdictWithinASecondAndAHalf`); the fresh jug arrives full.
        run(s, seconds: CoreTuning.jugSwapPause + 0.2, tilt: 0, events: &back)
        #expect(servedJudgements(back).isEmpty)
        #expect(s.snapshot.jug.fill >= 0.5)
        // And pours into the same glass.
        let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 12
        run(s, seconds: 0.8, tilt: tilt, events: &back)
        #expect(s.snapshot.jug.flow > 0.05)
        let sameID: Int? = activeGlass(s)?.id
        #expect(sameID == glass.id)
    }

    @Test func aDryJugIsSwappedBetweenGlassesAndNeverGushesWhileHeldTipped() {
        // A shift whose first glass has a timer and whose second is the same still drink.
        let pick: Level? = LevelCatalog.levels.first(where: { (l: Level) -> Bool in
            if l.conveyorSpeed != nil || l.venue == .sandBar || l.orders.count < 2 { return false }
            let a: GlassOrder = l.orders[0]
            return a.patience != nil && a.liquid == l.orders[1].liquid && LiquidCatalog.liquid(a.liquid).foamPerVolume == 0
        })
        guard let level = pick else {
            Issue.record("no shift with a timed first glass")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: duoLayout(), seed: 14)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        s.debugSetJugFill(0.05)
        // Held tipped all the way: dry, then the customer's timer runs out.
        var t: Double = 0
        var servedAt: Double? = nil
        var ranDry: Bool = false
        while t < 40 && servedAt == nil {
            let step: [GameEvent] = s.step(dt: 1.0 / 60.0, tilt: 88)
            events.append(contentsOf: step)
            if s.snapshot.jug.fill == 0 { ranDry = true }
            if !servedJudgements(step).isEmpty { servedAt = t }
            t += 1.0 / 60.0
        }
        #expect(ranDry)
        #expect(servedAt != nil)
        #expect(swaps(events) == 0)
        // Still held tipped: the jug is swapped between glasses, and the full one never pours from the held tilt.
        var after: [GameEvent] = []
        run(s, seconds: 3.0, tilt: 88, events: &after)
        #expect(swaps(after) == 1)
        #expect(pourStarts(after) == 0)
        #expect(s.snapshot.jug.flow == 0)
        #expect(s.snapshot.jug.fill >= 0.5)
        #expect(s.snapshot.jug.angle < Rules.jugAngle(forLidTilt: 88))
        // Tip back, then pour: it pours.
        run(s, seconds: 0.3, tilt: 0, events: &after)
        let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 12
        run(s, seconds: 1.0, tilt: tilt, events: &after)
        #expect(s.snapshot.jug.flow > 0.05)
    }

    @Test func overfillingBelowTheRimIsOverNotSpill() {
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: duoLayout(), seed: 9)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let first = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        let lineFraction: Double = Double(first.lineHeight / first.shape.interiorHeight)
        #expect(lineFraction < 0.85)
        // Well past the Good band (12 %), well short of the rim.
        let stopAt: Double = min(0.2, CoreTuning.goodBand + (1.0 - lineFraction - CoreTuning.goodBand) * 0.5)
        var stopped: Bool = false
        var t: Double = 0
        while t < 20 && servedJudgements(events).isEmpty {
            var tilt: Double = 0
            if !stopped {
                if s.snapshot.telemetry.projectedDistanceToLine >= stopAt {
                    stopped = true
                } else {
                    tilt = pourLid(fill: max(0.03, s.snapshot.jug.fill)) + 10
                }
            }
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
        }
        let judged: [Judgement] = servedJudgements(events)
        #expect(judged == [Judgement.over])
        #expect(overflows(events) == 0)
        #expect(s.snapshot.puddles.isEmpty)
        #expect(s.snapshot.strikes == 1)
        #expect(s.snapshot.streak == 0)
        #expect(s.snapshot.score == 0)
        let after: GlassState? = s.snapshot.glasses.first(where: { (g: GlassState) -> Bool in g.id == first.id })
        if let g = after {
            #expect(!g.overflowing)
            #expect(g.liquidHeight < g.shape.interiorHeight)
            #expect(g.result == Judgement.over)
        }
    }

    @Test func aFoamyDrinkPouredToTheLineIsJudgedOnceTheHeadSettles() {
        // The shift whose first glass is the foamiest drink (root beer today); a phone, so no gate.
        var pick: Level? = nil
        var best: Double = 0
        for l in LevelCatalog.levels where l.conveyorSpeed == nil {
            guard let o = l.orders.first, o.prefill == 0 else { continue }
            let liquid: Liquid = LiquidCatalog.liquid(o.liquid)
            let k: Double = liquid.foamPerVolume * liquid.foamSettle
            if k > best {
                best = k
                pick = l
            }
        }
        guard let level = pick else {
            Issue.record("no foamy shift")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: phoneLayout(), seed: 5)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let first = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        let interior: CGFloat = first.shape.interiorHeight
        let allowance: CGFloat = CGFloat(CoreTuning.foamSettledFraction) * interior
        // Pour the LIQUID to the line (the projection counts at most a settled head), pausing if the head climbs high.
        var stopped: Bool = false
        var pausing: Bool = false
        var stopT: Double? = nil
        var servedT: Double? = nil
        var headAtServe: CGFloat = -1
        var maxHead: CGFloat = 0
        var t: Double = 0
        while t < 30 && servedT == nil {
            var tilt: Double = 0
            if !stopped, let g = activeGlass(s) {
                if s.snapshot.telemetry.projectedDistanceToLine >= -0.01 {
                    stopped = true
                    stopT = t
                } else {
                    let top: CGFloat = g.liquidHeight + g.foamHeight
                    // A careful soda pourer: gentle tip, and pause well before the head nears the rim (the stream
                    // already in the air keeps feeding foam; at +15° and an 80 % pause the head overflowed, run
                    // 40244627843, which is the "pour soda slowly" mechanic working, not what this test checks).
                    if top > interior * 0.62 {
                        pausing = true
                    } else if top < interior * 0.55 {
                        pausing = false
                    }
                    if !pausing { tilt = pourLid(fill: max(0.03, s.snapshot.jug.fill)) + 7 }
                }
            }
            let step: [GameEvent] = s.step(dt: 1.0 / 60.0, tilt: tilt)
            events.append(contentsOf: step)
            t += 1.0 / 60.0
            guard let g = s.snapshot.glasses.first(where: { (x: GlassState) -> Bool in x.id == first.id }) else { break }
            maxHead = max(maxHead, g.foamHeight)
            if !servedJudgements(step).isEmpty {
                servedT = t
                headAtServe = g.foamHeight
            }
        }
        let judged: [Judgement] = servedJudgements(events)
        #expect(judged.count == 1)
        if let j = judged.first { #expect(j.isHit, "judged \(j)") }
        #expect(overflows(events) == 0)
        // The head really was tall (judged with it, this glass would have been stamped over the line)…
        #expect(maxHead > allowance * 2, "head \(maxHead)")
        // …and the verdict waited for it to settle (or for the 3 s cap).
        let waited: Double = (servedT ?? 99) - (stopT ?? 0)
        #expect(headAtServe <= allowance + 0.5 || waited >= 2.9, "served with head \(headAtServe) after \(waited) s")
        #expect(waited <= 4.0, "verdict \(waited) s after stopping")
    }

    @Test func fadingLinesWaitForTheFlatGate() {
        let pick: Level? = LevelCatalog.levels.first(where: { (l: Level) -> Bool in
            guard l.conveyorSpeed == nil, let o = l.orders.first, let fade = o.lineFadesAfter else { return false }
            return (o.patience ?? 99) > fade + 3
        })
        guard let level = pick, let fade = level.orders.first?.lineFadesAfter else {
            Issue.record("no shift with a fading first line")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: duoLayout(), seed: 3)
        var events: [GameEvent] = []
        // Tabletop, not laid flat yet: the line doesn't fade while nothing can pour.
        run(s, seconds: fade + 2.0, tilt: 50, events: &events)
        #expect(s.snapshot.needsFlat)
        let behindGate: Double? = activeGlass(s)?.lineOpacity
        #expect(behindGate == Double(1))
        run(s, seconds: 0.2, tilt: 0, events: &events)
        #expect(!s.snapshot.needsFlat)
        run(s, seconds: max(0, fade - 0.5), tilt: 0, events: &events)
        let early: Double? = activeGlass(s)?.lineOpacity
        #expect(early == Double(1))
        run(s, seconds: 1.0 + CoreTuning.lineFadeDuration, tilt: 0, events: &events)
        let late: Double? = activeGlass(s)?.lineOpacity
        #expect(late == Double(0))
    }

    @Test func theBeltWaitsForTheIntro() {
        guard let level = LevelCatalog.levels.first(where: { (l: Level) -> Bool in l.conveyorSpeed != nil }) else {
            Issue.record("no conveyor shift")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: phoneLayout(), seed: 3)
        var events: [GameEvent] = []
        run(s, seconds: 0.5, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .intro)
        let x0: CGFloat? = activeGlass(s)?.x
        run(s, seconds: 0.25, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .intro)
        let x1: CGFloat? = activeGlass(s)?.x
        #expect(x0 != nil)
        #expect(x1 == x0)
        run(s, seconds: 0.5, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .playing)
        let x2: CGFloat? = activeGlass(s)?.x
        if let a = x1, let b = x2 { #expect(b > a) }
    }

    @Test func conveyorVerdictWaitsForDrinkAlreadyInsideTheGlass() {
        guard let level = LevelCatalog.levels.first(where: { (l: Level) -> Bool in l.conveyorSpeed != nil }) else {
            Issue.record("no conveyor shift")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: phoneLayout(), seed: 4)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        var pending: [(id: Int, t: Double, h: CGFloat, interior: CGFloat)] = []
        var checked: Int = 0
        var problems: [String] = []
        var t: Double = 0
        while t < 25 && !s.isFinished {
            // Pour hard only over the last stretch before the mouth passes the stream (it lands at x ≈ 340…372), so
            // drink is still falling inside the glass when it reaches the exit.
            var tilt: Double = 0
            if let g = activeGlass(s), Double(g.x - g.shape.rimHalfWidth) > 335 {
                tilt = pourLid(fill: max(0.03, s.snapshot.jug.fill)) + 18
            }
            let step: [GameEvent] = s.step(dt: 1.0 / 60.0, tilt: tilt)
            t += 1.0 / 60.0
            for e in step {
                guard case .served(let id, _, _) = e else { continue }
                let g: GlassState? = s.snapshot.glasses.first(where: { (x: GlassState) -> Bool in x.id == id })
                if let g = g, !g.overflowing {
                    pending.append((id: id, t: t, h: g.liquidHeight, interior: g.shape.interiorHeight))
                }
            }
            var keep: [(id: Int, t: Double, h: CGFloat, interior: CGFloat)] = []
            for p in pending {
                if t - p.t < 0.4 {
                    keep.append(p)
                    continue
                }
                let g: GlassState? = s.snapshot.glasses.first(where: { (x: GlassState) -> Bool in x.id == p.id })
                if let g = g, !g.overflowing {
                    checked += 1
                    let grew: CGFloat = g.liquidHeight - p.h
                    if grew > p.interior * 0.015 { problems.append("glass \(p.id) rose \(grew) pt after its verdict") }
                }
            }
            pending = keep
        }
        #expect(checked >= 2, "verdicts checked \(checked)")
        #expect(problems.isEmpty, "\(problems)")
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

    // MARK: Round 6: the late game (REVIEW-5)

    @Test func reposeProgressTelegraphsTheSandSlide() {
        guard let level = LevelCatalog.levels(in: .sandBar).first else {
            Issue.record("no Sand Bar shift")
            return
        }
        // A phone (no flat gate), so the tilt drives the jug straight away.
        let s: GameSession = GameSession(mode: .shift(level.id), layout: phoneLayout(), seed: 8)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .playing)
        #expect(s.snapshot.jug.liquid.id == LiquidID.sand)
        #expect(s.snapshot.jug.reposeProgress == 0)
        let fill: Double = s.snapshot.jug.fill
        let threshold: Double = JugGeometry.pourThreshold(JugGeometry.standard, fill: fill)
        let repose: Double = LiquidCatalog.liquid(.sand).reposeDegrees

        // Tip slowly (0.1° of lid a frame) until the sand lets go.
        var tilt: Double = 0
        var last: Double = 0
        var beforeSlide: Double = 0
        var telegraphed: Bool = false
        var falling: [Double] = []
        var slideAngle: Double? = nil
        var progressAtSlide: Double = -1
        while tilt < 90 && slideAngle == nil {
            tilt += 0.1
            s.step(dt: 1.0 / 60.0, tilt: tilt)
            let jug: JugState = s.snapshot.jug
            if jug.flow > 0 {
                slideAngle = jug.angle
                progressAtSlide = jug.reposeProgress
                break
            }
            let p: Double = jug.reposeProgress
            if p < last - 1e-9 { falling.append(jug.angle) }
            if p >= 0.7 && p < 1 { telegraphed = true }
            // Nothing before the angle at which a liquid would pour.
            if jug.angle < threshold - 0.6 && p > 0 { falling.append(-jug.angle) }
            last = p
            beforeSlide = p
        }
        #expect(falling.isEmpty, "progress not monotonic / early at \(falling)")
        #expect(telegraphed, "no 0.7…1 telegraph before the slide")
        #expect(beforeSlide >= 0.9, "progress just before the slide \(beforeSlide)")
        #expect(progressAtSlide == 1, "progress while sliding \(progressAtSlide)")
        if let a = slideAngle {
            // "1 = it slides now": the slide comes at the liquid pour point plus the angle of repose.
            #expect(abs(a - (threshold + repose)) < 2, "slid at \(a), expected ≈ \(threshold + repose)")
        } else {
            Issue.record("the sand never slid")
        }

        // Flowing: it stays 1. Tipped back upright: 0 again.
        run(s, seconds: 0.3, tilt: tilt, events: &events)
        #expect(s.snapshot.jug.reposeProgress == 1)
        run(s, seconds: 0.5, tilt: 0, events: &events)
        #expect(s.snapshot.jug.reposeProgress == 0)

        // Liquids never report it.
        let water: GameSession = GameSession(mode: .shift("1-1"), layout: phoneLayout(), seed: 8)
        var wt: Double = 0
        var maxWater: Double = 0
        while wt < 60 {
            water.step(dt: 1.0 / 60.0, tilt: wt)
            maxWater = max(maxWater, water.snapshot.jug.reposeProgress)
            wt += 0.5
        }
        #expect(maxWater == 0)
    }

    @Test func snapshotsReportTheirVenueAndRushTier() {
        for l in LevelCatalog.levels {
            let s: GameSession = GameSession(mode: .shift(l.id), layout: duoLayout(), seed: 2)
            s.step(dt: 1.0 / 60.0, tilt: 0)
            let venue: VenueID? = s.snapshot.venue
            #expect(venue == l.venue, "\(l.id) reports \(String(describing: venue))")
            #expect(s.snapshot.rushTier == 0)
        }
        for mode in [GameMode.daily(297), GameMode.practice] {
            let s: GameSession = GameSession(mode: mode, layout: duoLayout(), seed: 2)
            s.step(dt: 1.0 / 60.0, tilt: 0)
            let venue: VenueID? = s.snapshot.venue
            #expect(venue == nil, "\(mode) reports \(String(describing: venue))")
            #expect(s.snapshot.rushTier == 0)
        }
        let rush: GameSession = GameSession(mode: .rush, layout: duoLayout(), seed: 2)
        #expect(rush.snapshot.rushTier == 1)
        let rushVenue: VenueID? = rush.snapshot.venue
        #expect(rushVenue == VenueID.lemonadeStand)
    }

    @Test func rushTravelsOneVenuePerTier() {
        #expect(Rules.rushVenue(tier: 0) == VenueID.lemonadeStand)
        #expect(Rules.rushVenue(tier: 1) == VenueID.lemonadeStand)
        #expect(Rules.rushVenue(tier: 2) == VenueID.sodaFountain)
        #expect(Rules.rushVenue(tier: 3) == VenueID.conveyor)
        #expect(Rules.rushVenue(tier: 4) == VenueID.milkshakeDiner)
        #expect(Rules.rushVenue(tier: 5) == VenueID.potionShop)
        #expect(Rules.rushVenue(tier: 6) == VenueID.sodaFountain)
        #expect(Rules.rushVenue(tier: 7) == VenueID.conveyor)
        #expect(Rules.rushVenue(tier: 9) == VenueID.potionShop)
        #expect(Rules.rushVenue(tier: 10) == VenueID.sodaFountain)
        var tier: Int = 1
        while tier <= 40 {
            #expect(Rules.rushVenue(tier: tier) != VenueID.sandBar)
            tier += 1
        }
        for v in VenueID.allCases {
            let menu: (liquids: [LiquidID], glasses: [String]) = GameSession.rushMenu(v)
            #expect(!menu.liquids.isEmpty && !menu.glasses.isEmpty, "\(v) menu is empty")
            for id in menu.glasses { #expect(GlassCatalog.shape(id).id == id, "\(v) serves unknown glass \(id)") }
        }

        // An idle Rush walks through the tiers (a patience timeout is `.short`, which never strikes in Rush; a belt
        // glass is judged as it rides past). Every glass at the stop must come from its tier's venue menu, ride a belt
        // exactly when that venue is the Conveyor, and the snapshot must report the tier and venue as it arrives.
        let s: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: 21)
        var seen: [Int] = []
        var problems: [String] = []
        var belts: Int = 0
        var handoffs: [Int] = []
        var t: Double = 0
        while t < 900 && seen.count < 4 * CoreTuning.rushTierEvery + 1 && !s.isFinished {
            s.step(dt: 1.0 / 30.0, tilt: 0)
            t += 1.0 / 30.0
            let snap: GameSnapshot = s.snapshot
            let shown: VenueID? = snap.venue
            if shown != Rules.rushVenue(tier: snap.rushTier) {
                problems.append("t \(t): venue \(String(describing: shown)) for tier \(snap.rushTier)")
            }
            // Round 7 (QA-3 P2-2): at Conveyor → Diner, the first glass that stands still is sent only as the last belt
            // glass starts leaving, and never slides in over it (mug handles on the left included).
            for b in snap.glasses where b.patienceTotal == nil && !b.isWaitingInSlot {
                for n in snap.glasses where n.patienceTotal != nil && !n.isWaitingInSlot && n.phase == .arriving {
                    if !handoffs.contains(n.id) { handoffs.append(n.id) }
                    if b.phase != .leaving { problems.append("t \(t): glass \(n.id) sent while belt glass \(b.id) is \(b.phase)") }
                    let gap: Double = Double(b.x - n.x) - NextGlassSlot.bodyHalfWidth(n.shape)
                        - NextGlassSlot.bodyHalfWidth(b.shape) - NextGlassSlot.handleReach(b.shape)
                    if gap < 0 { problems.append("t \(t): glass \(n.id) overlaps belt glass \(b.id) by \(-gap) pt") }
                }
            }
            for g in snap.glasses where g.phase == .filling && !seen.contains(g.id) {
                let k: Int = seen.count
                seen.append(g.id)
                let want: Int = k / CoreTuning.rushTierEvery + 1
                if snap.rushTier != want { problems.append("glass \(k): tier \(snap.rushTier), want \(want)") }
                let venue: VenueID = Rules.rushVenue(tier: want)
                let menu: (liquids: [LiquidID], glasses: [String]) = GameSession.rushMenu(venue)
                if !menu.liquids.contains(g.liquid.id) { problems.append("glass \(k): \(g.liquid.id) in \(venue)") }
                if !menu.glasses.contains(g.shape.id) { problems.append("glass \(k): \(g.shape.id) in \(venue)") }
                let onBelt: Bool = g.patienceTotal == nil
                if onBelt { belts += 1 }
                if onBelt != (venue == .conveyor) { problems.append("glass \(k): belt \(onBelt) in \(venue)") }
            }
        }
        #expect(!s.isFinished)
        #expect(seen.count == 4 * CoreTuning.rushTierEvery + 1, "glasses at the stop \(seen.count) in \(t) s")
        #expect(belts == CoreTuning.rushTierEvery, "belt glasses \(belts)")
        #expect(handoffs.count == 1, "belt → counter handoffs \(handoffs)")
        #expect(problems.isEmpty, "\(problems)")
        #expect(s.snapshot.rushTier == 5)
        let finalVenue: VenueID? = s.snapshot.venue
        #expect(finalVenue == VenueID.potionShop)
    }

    @Test func rushOverPoursBreakTheStreakButOnlyRimSpillsStrike() {
        // Round 6 (founder, BALANCE.md §7). Find a seed whose first Rush glass leaves room past the Good band.
        var picked: GameSession? = nil
        var seed: UInt64 = 1
        while seed <= 40 && picked == nil {
            let candidate: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: seed)
            var warm: [GameEvent] = []
            run(candidate, seconds: 1.0, tilt: 0, events: &warm)
            if let g = activeGlass(candidate), Double(g.lineHeight / g.shape.interiorHeight) <= 0.65 {
                picked = candidate
            }
            seed += 1
        }
        guard let s = picked, let first = activeGlass(s) else {
            Issue.record("no Rush seed with a first line ≤ 0.65")
            return
        }
        let lineFraction: Double = Double(first.lineHeight / first.shape.interiorHeight)
        let stopAt: Double = min(0.2, CoreTuning.goodBand + (1.0 - lineFraction - CoreTuning.goodBand) * 0.5)
        var events: [GameEvent] = []
        var stopped: Bool = false
        var t: Double = 0
        while t < 20 && servedJudgements(events).isEmpty {
            var tilt: Double = 0
            if !stopped {
                if s.snapshot.telemetry.projectedDistanceToLine >= stopAt {
                    stopped = true
                } else {
                    tilt = pourLid(fill: max(0.03, s.snapshot.jug.fill)) + 10
                }
            }
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
        }
        let judged: [Judgement] = servedJudgements(events)
        #expect(judged == [Judgement.over])
        #expect(overflows(events) == 0)
        #expect(s.snapshot.strikes == 0)
        #expect(s.snapshot.streak == 0)
        #expect(!s.isFinished)
        let strikeEvents: Int = count(events) { (e: GameEvent) -> Bool in
            if case .strike = e { return true }
            return false
        }
        #expect(strikeEvents == 0)
    }

    @Test func theHourglassHasAWaistAndStaysJudgeable() {
        let g: GlassShape = GlassCatalog.shape("hourglass")
        #expect(g.id == "hourglass")
        // No new GlassStyle case (exhaustive switches elsewhere): it draws as a profile with the jar's (no) extras.
        #expect(g.style == GlassStyle.jar)
        let interior: CGFloat = g.interiorHeight
        // Two bulbs and a waist in the middle third, under half as wide as either bulb, wide enough for a full stream.
        var lowBulb: CGFloat = 0
        var highBulb: CGFloat = 0
        var waist: CGFloat = CGFloat.greatestFiniteMagnitude
        var waistY: CGFloat = 0
        var y: CGFloat = 0
        while y <= interior {
            let w: CGFloat = GlassMath.halfWidth(g, at: y)
            if y < interior / 3 {
                lowBulb = max(lowBulb, w)
            } else if y > interior * 2 / 3 {
                highBulb = max(highBulb, w)
            } else if w < waist {
                waist = w
                waistY = y
            }
            y += 1
        }
        #expect(waist * 2 <= lowBulb && waist * 2 <= highBulb, "waist \(waist), bulbs \(lowBulb) / \(highBulb)")
        #expect(waist * 2 >= CGFloat(CoreTuning.streamWidthMax) + 8, "waist \(waist * 2) wide")
        #expect(g.rimHalfWidth > waist)
        // The level races through the waist: the same volume lifts it ≥ 2.5× as far as in either bulb.
        let dv: CGFloat = 300
        let atWaist: CGFloat = waistY + 1
        let riseWaist: CGFloat = GlassMath.height(g, forVolume: GlassMath.volume(g, upTo: atWaist) + dv) - atWaist
        let atLow: CGFloat = interior * 0.25
        let riseLow: CGFloat = GlassMath.height(g, forVolume: GlassMath.volume(g, upTo: atLow) + dv) - atLow
        let atHigh: CGFloat = interior * 0.8
        let riseHigh: CGFloat = GlassMath.height(g, forVolume: GlassMath.volume(g, upTo: atHigh) + dv) - atHigh
        #expect(riseWaist >= riseLow * 2.5 && riseWaist >= riseHigh * 2.5, "rise \(riseWaist) vs \(riseLow) / \(riseHigh)")
        // Fillable: about a mug's worth, and a sand jug serves several.
        let cap: CGFloat = GlassMath.capacity(g)
        #expect(cap > 14_000 && cap < 26_000, "capacity \(cap)")
        // Judgeable: wherever the line sits (0.2…0.9), the default Perfect band holds at least as much drink as the
        // vial's (the game's tightest glass) at its middle.
        let band: CGFloat = CGFloat(CoreTuning.defaultPerfectBand)
        let vial: GlassShape = GlassCatalog.shape("vial")
        let vialMid: CGFloat = vial.interiorHeight * 0.5
        let vialBand: CGFloat = GlassMath.volume(vial, upTo: vialMid + band * vial.interiorHeight)
            - GlassMath.volume(vial, upTo: vialMid - band * vial.interiorHeight)
        var line: CGFloat = 0.2
        while line <= 0.9 {
            let h: CGFloat = line * interior
            let held: CGFloat = GlassMath.volume(g, upTo: h + band * interior) - GlassMath.volume(g, upTo: h - band * interior)
            #expect(held >= vialBand, "line \(line): band holds \(held) < vial \(vialBand)")
            line += 0.01
        }
        // It stands on the counter like any glass (rim clear of the crease) and fits the next-glass slot on the Duo.
        #expect(g.baseThickness + interior <= GlassCatalog.maxStandingHeight)
        let slot: Double? = NextGlassSlot.x(for: g, layout: duoLayout(), stop: (x: 372, shape: GlassCatalog.shape("bowl")))
        #expect(slot != nil)
    }

    @Test func creamSodaReadsAsSodaNotBeer() {
        let cream: Liquid = LiquidCatalog.liquid(.creamSoda)
        // Caramel, not lager gold: clearly redder than it is green at the bottom, a pale vanilla top.
        #expect(cream.bottom.r - cream.bottom.g >= 0.28, "bottom \(cream.bottom)")
        #expect(cream.top.r > 0.95 && cream.top.g > 0.85, "top \(cream.top)")
        // A small, white head: whiter than the old cream, smaller than cola's and root beer's.
        if let foam = cream.foam {
            #expect(min(foam.r, min(foam.g, foam.b)) >= 0.98, "foam \(foam)")
        } else {
            Issue.record("cream soda lost its head")
        }
        let head: Double = cream.foamPerVolume * cream.foamSettle
        let cola: Liquid = LiquidCatalog.liquid(.cola)
        let rootBeer: Liquid = LiquidCatalog.liquid(.rootBeer)
        #expect(head < 0.5 * cola.foamPerVolume * cola.foamSettle)
        #expect(head < rootBeer.foamPerVolume * rootBeer.foamSettle)
        // Still "foamy" for the Daily generator (> 0.3, ≤ 1.0), so every version generates the same Daily.
        #expect(cream.foamPerVolume > 0.3 && cream.foamPerVolume <= 1.0)
        #expect(cream.fizzy)
    }

    // MARK: Round 7 (QA-3): the start hold, Rush hand-offs, dry-jug dead air

    @Test func theStartHoldFreezesTheBeltPatienceAndFadingLinesUntilReleased() {
        // QA-3 P1-3: the conveyor intro card. A phone (no flat gate), so only the hold stops the belt.
        guard let beltLevel = LevelCatalog.levels.first(where: { (l: Level) -> Bool in l.conveyorSpeed != nil }) else {
            Issue.record("no conveyor shift")
            return
        }
        let s: GameSession = GameSession(mode: .shift(beltLevel.id), layout: phoneLayout(), seed: 3)
        #expect(!s.isStartHeld)
        s.setStartHold(true)
        #expect(s.isStartHeld)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        #expect(s.snapshot.phase == .playing)
        let x0: CGFloat? = activeGlass(s)?.x
        run(s, seconds: 3.0, tilt: 0, events: &events)
        let x1: CGFloat? = activeGlass(s)?.x
        #expect(x0 != nil)
        #expect(x1 == x0)
        #expect(servedJudgements(events).isEmpty)
        #expect(s.isStartHeld)
        // The App dismisses the card: the belt runs.
        s.setStartHold(false)
        #expect(!s.isStartHeld)
        run(s, seconds: 0.5, tilt: 0, events: &events)
        let x2: CGFloat? = activeGlass(s)?.x
        if let a = x1, let b = x2 {
            #expect(b > a)
        } else {
            Issue.record("the belt glass went missing")
        }

        // Pouring releases the hold by itself ("Pour to start"), and the belt runs on.
        let p: GameSession = GameSession(mode: .shift(beltLevel.id), layout: phoneLayout(), seed: 3)
        p.setStartHold(true)
        var pre: [GameEvent] = []
        run(p, seconds: 1.0, tilt: 0, events: &pre)
        let pid: Int? = activeGlass(p)?.id
        let px0: CGFloat? = activeGlass(p)?.x
        var poured: [GameEvent] = []
        run(p, seconds: 0.5, tilt: pourLid(fill: p.snapshot.jug.fill) + 15, events: &poured)
        #expect(pourStarts(poured) >= 1)
        #expect(!p.isStartHeld)
        let moved: GlassState? = p.snapshot.glasses.first(where: { (g: GlassState) -> Bool in g.id == pid })
        if let a = px0, let g = moved {
            #expect(g.x > a)
        } else {
            Issue.record("no belt glass to watch")
        }

        // Patience waits behind the hold.
        if let timed = LevelCatalog.levels.first(where: { (l: Level) -> Bool in
            l.conveyorSpeed == nil && l.orders.first?.patience != nil
        }) {
            let q: GameSession = GameSession(mode: .shift(timed.id), layout: phoneLayout(), seed: 3)
            q.setStartHold(true)
            var qe: [GameEvent] = []
            run(q, seconds: 4.0, tilt: 0, events: &qe)
            let full: Double? = activeGlass(q)?.patienceTotal
            let held: Double? = activeGlass(q)?.patienceLeft
            #expect(full != nil)
            #expect(held == full)
            q.setStartHold(false)
            run(q, seconds: 1.0, tilt: 0, events: &qe)
            let after: Double? = activeGlass(q)?.patienceLeft
            if let f = full, let a = after {
                #expect(a < f - 0.5)
            } else {
                Issue.record("the timed glass went missing")
            }
        } else {
            Issue.record("no shift with patience on its first glass")
        }

        // A fading line doesn't fade behind the hold.
        if let fading = LevelCatalog.levels.first(where: { (l: Level) -> Bool in
            l.conveyorSpeed == nil && l.orders.first?.lineFadesAfter != nil
        }), let fade = fading.orders.first?.lineFadesAfter {
            let f: GameSession = GameSession(mode: .shift(fading.id), layout: phoneLayout(), seed: 3)
            f.setStartHold(true)
            var fe: [GameEvent] = []
            run(f, seconds: fade + 2.0, tilt: 0, events: &fe)
            let opacity: Double? = activeGlass(f)?.lineOpacity
            #expect(opacity == Double(1))
        } else {
            Issue.record("no shift with a fading first line")
        }
    }

    @Test func rushKeepsTheStreamsDrinkUntilThePourStops() {
        // QA-3 P2-3: a glass sent to the stop mid-pour (a belt serve, or a changeover under a running stream) doesn't
        // change the stream's drink under the player's hand; the jug takes it once the stream has stopped and landed.
        var found: Bool = false
        var problems: [String] = []
        var seed: UInt64 = 1
        while seed <= 30 && !found {
            let s: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: seed)
            seed += 1
            var t: Double = 0
            var prevFlow: Double = 0
            var prevLiquid: LiquidID = s.snapshot.jug.liquid.id
            var want: LiquidID? = nil
            while t < 30 && !s.isFinished && want == nil {
                s.debugSetJugFill(1.0)
                let tilt: Double = t < 1.0 ? 0 : 70
                s.step(dt: 1.0 / 60.0, tilt: tilt)
                t += 1.0 / 60.0
                let jug: JugState = s.snapshot.jug
                if prevFlow > 0 && jug.flow > 0 && jug.liquid.id != prevLiquid {
                    problems.append("t \(t): the stream turned \(prevLiquid) → \(jug.liquid.id) mid-pour")
                }
                prevFlow = jug.flow
                prevLiquid = jug.liquid.id
                if jug.flow > 0 {
                    let sent: GlassState? = s.snapshot.glasses.first(where: { (g: GlassState) -> Bool in
                        g.phase == .arriving && !g.isWaitingInSlot
                    })
                    if let g = sent, g.liquid.id != jug.liquid.id { want = g.liquid.id }
                }
            }
            guard let next = want else { continue }
            found = true
            // Laid back: the jug takes the new drink only once nothing flows.
            var switched: Bool = false
            var lt: Double = 0
            while lt < 2.0 && !switched {
                s.step(dt: 1.0 / 60.0, tilt: 0)
                lt += 1.0 / 60.0
                if s.snapshot.jug.liquid.id == next {
                    switched = true
                    #expect(s.snapshot.jug.flow == 0)
                }
            }
            #expect(switched, "the jug never took \(next)")
        }
        #expect(found, "no Rush seed sent a new drink to the stop mid-pour")
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func aDryJugRefillReachesItsVerdictWithinASecondAndAHalf() {
        // QA-3 P2-7: laid back after running dry short of the line: one refill swap, a short wait to pour again, then
        // the verdict ≈ 1.5 s after the lay-back (was ≈ 4.9 s).
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: phoneLayout(), seed: 13)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let glass = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        let tilt: Double = pourLid(fill: s.snapshot.jug.fill) + 12
        var t: Double = 0
        var third: Bool = false
        while t < 8 && !third {
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tilt))
            t += 1.0 / 60.0
            if let g = activeGlass(s), g.liquidHeight >= g.lineHeight * 0.35 { third = true }
        }
        #expect(third)
        s.debugSetJugFill(0)
        run(s, seconds: 1.0, tilt: tilt, events: &events)
        #expect(s.snapshot.jug.fill == 0)
        #expect(servedJudgements(events).isEmpty)
        var back: [GameEvent] = []
        var waited: Double = 0
        while waited < 6 && servedJudgements(back).isEmpty {
            back.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: 0))
            waited += 1.0 / 60.0
        }
        #expect(servedJudgements(back) == [Judgement.short])
        #expect(waited >= 1.0 && waited <= 1.6, "verdict \(waited) s after the lay-back")
        #expect(swaps(back) == 1)
        var servedID: Int = -1
        for e in back {
            if case .served(let id, _, _) = e { servedID = id }
        }
        #expect(servedID == glass.id)
    }

    @Test func aDryJugOverAGlassThatIsAlreadyAHitIsJudgedWithoutARefill() {
        // QA-3 P2-7: run dry just short of the line (inside the Good band), lay back: judged ~0.9 s later with no
        // refill swap; the next glass brings the refill.
        let s: GameSession = GameSession(mode: .shift("1-1"), layout: phoneLayout(), seed: 13)
        var events: [GameEvent] = []
        run(s, seconds: 1.0, tilt: 0, events: &events)
        guard let glass = activeGlass(s) else {
            Issue.record("no glass")
            return
        }
        var stopped: Bool = false
        var lastTilt: Double = 0
        var t: Double = 0
        while t < 12 && !stopped {
            let tl: Double = carefulTilt(s, offset: 12, stopAt: -0.03, stopped: &stopped)
            if stopped { break }
            lastTilt = tl
            events.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: tl))
            t += 1.0 / 60.0
        }
        #expect(stopped)
        // Runs dry right there, still tipped: no verdict, no swap.
        s.debugSetJugFill(0)
        run(s, seconds: 1.0, tilt: lastTilt, events: &events)
        #expect(s.snapshot.jug.fill == 0)
        #expect(servedJudgements(events).isEmpty)
        #expect(swaps(events) == 0)
        var back: [GameEvent] = []
        var waited: Double = 0
        while waited < 6 && servedJudgements(back).isEmpty {
            back.append(contentsOf: s.step(dt: 1.0 / 60.0, tilt: 0))
            waited += 1.0 / 60.0
        }
        let judged: [Judgement] = servedJudgements(back)
        #expect(judged.count == 1)
        if let j = judged.first { #expect(j.isHit, "judged \(j)") }
        #expect(waited <= 1.05, "verdict \(waited) s after the lay-back")
        #expect(swaps(back) == 0)
        var servedID: Int = -1
        for e in back {
            if case .served(let id, _, _) = e { servedID = id }
        }
        #expect(servedID == glass.id)
        // The next glass is sent with a refilled jug (one swap).
        var next: [GameEvent] = []
        run(s, seconds: 2.0, tilt: 0, events: &next)
        #expect(swaps(next) == 1)
        #expect(s.snapshot.jug.fill >= 0.5)
    }

    // MARK: Round 8: upcoming orders (Rush's belt queue)

    /// The upcoming orders that are not on the counter yet (a waiting slot glass already is).
    private func unplacedUpcoming(_ s: GameSession) -> [GlassOrder] {
        let up: [GlassOrder] = s.upcomingOrders
        let waiting: Bool = s.snapshot.glasses.contains(where: { (g: GlassState) -> Bool in g.isWaitingInSlot })
        if waiting && !up.isEmpty { return Array(up.dropFirst()) }
        return up
    }

    private func glassMatches(_ g: GlassState, _ o: GlassOrder) -> Bool {
        if g.shape.id != o.glass || g.liquid.id != o.liquid { return false }
        let line: Double = o.line * Double(g.shape.interiorHeight)
        return abs(Double(g.lineHeight) - line) < 0.001
    }

    @Test func rushConveyorTierPeeksTheNextGlassesAndSpawnsThem() {
        // An idle Rush (seed 21, as `rushTravelsOneVenuePerTier`) walks through tier 3, the Conveyor. While a belt
        // glass rides there is no slot glass, yet `upcomingOrders` must name the next two; and every glass that appears,
        // in every tier, must be the one peeked the frame before, with peeks stable until a glass is placed.
        let s: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: 21)
        var maxID: Int = 0
        for g in s.snapshot.glasses { maxID = max(maxID, g.id) }
        var peeked: [GlassOrder] = unplacedUpcoming(s)
        #expect(s.upcomingOrders.count == GameSession.upcomingDepth)
        #expect(s.upcomingOrder == s.upcomingOrders.first)
        var problems: [String] = []
        var matched: Int = 0
        var beltGlasses: [Int] = []
        var beltPeekMatches: Int = 0
        var t: Double = 0
        while t < 900 && s.snapshot.rushTier <= 4 && !s.isFinished {
            let beltRiding: Bool = s.snapshot.glasses.contains(where: { (g: GlassState) -> Bool in
                g.patienceTotal == nil && !g.isWaitingInSlot && g.phase != .leaving
            })
            s.step(dt: 1.0 / 30.0, tilt: 0)
            t += 1.0 / 30.0
            var fresh: [GlassState] = []
            for g in s.snapshot.glasses where g.id > maxID { fresh.append(g) }
            var k: Int = 0
            while k < fresh.count {
                let g: GlassState = fresh[k]
                maxID = max(maxID, g.id)
                if k < peeked.count {
                    if glassMatches(g, peeked[k]) {
                        matched += 1
                        if beltRiding { beltPeekMatches += 1 }
                    } else {
                        problems.append("t \(t): glass \(g.id) \(g.shape.id)/\(g.liquid.id), peeked \(peeked[k])")
                    }
                } else {
                    problems.append("t \(t): glass \(g.id) appeared with no peek")
                }
                k += 1
            }
            let now: [GlassOrder] = unplacedUpcoming(s)
            if fresh.isEmpty && !now.isEmpty && !peeked.isEmpty && now.first != peeked.first {
                problems.append("t \(t): peek changed with no glass placed")
            }
            peeked = now
            for b in s.snapshot.glasses where b.patienceTotal == nil && !b.isWaitingInSlot && b.phase != .leaving {
                if !beltGlasses.contains(b.id) { beltGlasses.append(b.id) }
                if s.upcomingOrders.count != GameSession.upcomingDepth {
                    problems.append("t \(t): belt glass \(b.id) riding, upcoming \(s.upcomingOrders.count)")
                }
                if s.upcomingOrder == nil { problems.append("t \(t): belt glass \(b.id) riding, upcomingOrder nil") }
            }
        }
        #expect(!s.isFinished)
        #expect(beltGlasses.count == CoreTuning.rushTierEvery, "belt glasses \(beltGlasses.count)")
        #expect(beltPeekMatches >= CoreTuning.rushTierEvery - 1, "glasses spawned while a belt glass rode \(beltPeekMatches)")
        #expect(matched >= 4 * CoreTuning.rushTierEvery - 1, "matched \(matched)")
        #expect(problems.isEmpty, "\(problems.prefix(5))")
    }

    @Test func readingUpcomingOrdersNeverChangesTheRun() {
        // Peeking is cached, never drawn on read: a Rush that is asked every frame plays out exactly as one never asked.
        let a: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: 42)
        let b: GameSession = GameSession(mode: .rush, layout: phoneLayout(), seed: 42)
        var ea: [String] = []
        var eb: [String] = []
        var asked: Int = 0
        var t: Double = 0
        while t < 40 {
            let tilt: Double = t < 1 ? 0 : 40 + 25 * sin(t * 1.7)
            asked += a.upcomingOrders.count
            for e in a.step(dt: 1.0 / 60.0, tilt: tilt) { ea.append(String(describing: e)) }
            asked += a.upcomingOrders.count
            for e in b.step(dt: 1.0 / 60.0, tilt: tilt) { eb.append(String(describing: e)) }
            t += 1.0 / 60.0
        }
        #expect(asked > 0)
        #expect(ea == eb)
        #expect(a.snapshot.score == b.snapshot.score)
        let ga: [String] = a.snapshot.glasses.map { (g: GlassState) -> String in "\(g.id) \(g.shape.id) \(g.liquid.id)" }
        let gb: [String] = b.snapshot.glasses.map { (g: GlassState) -> String in "\(g.id) \(g.shape.id) \(g.liquid.id)" }
        #expect(ga == gb)
        #expect(a.upcomingOrders == b.upcomingOrders)
    }

    @Test func shiftUpcomingOrdersListTheNextTwoFixedOrders() {
        guard let level = LevelCatalog.levels.first(where: { (l: Level) -> Bool in l.orders.count >= 3 }) else {
            Issue.record("no shift with 3 orders")
            return
        }
        let s: GameSession = GameSession(mode: .shift(level.id), layout: phoneLayout(), seed: 3)
        let up: [GlassOrder] = s.upcomingOrders
        #expect(up.count == 2)
        #expect(up.first == level.orders[1])
        #expect(up.last == level.orders[2])
        #expect(s.upcomingOrder == level.orders[1])
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
