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
