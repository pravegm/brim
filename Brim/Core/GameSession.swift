import CoreGraphics
import Foundation

/// The whole game simulation for one run. Plain Swift, deterministic for a given seed and input timeline.
///
/// Each `step` sub-steps at ≤ 1/240 s:
///   lid tilt → jug angle → level surface in the jug polygon → head above the lip → weir flow (lagged) →
///   stream particles (ballistic, carrying volume) → glasses (enter through the mouth) / counter (puddles) →
///   foam, overflow, serving, judging, score, events.
final class GameSession {

    // MARK: - Public surface

    let mode: GameMode
    let layout: WorldLayout
    private(set) var snapshot: GameSnapshot
    private(set) var result: RunResult?
    var isFinished: Bool { return phase == .finished }

    // MARK: - Internal types

    private struct Particle {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var volume: Double
        var flow: Double        // normalized outflow at emission (drives width and foam)
        var speed0: Double      // exit speed (drives thinning)
        var born: Double
        var isDrop: Bool
        var glassID: Int        // -1 until it falls through a glass mouth
    }

    private struct Spray {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var life: Double
        var radius: Double
        var glassID: Int        // -1 = thrown up from the counter; else kept inside that glass's mouth
    }

    /// Spilt drink pooled on the counter. Drawn as a run of points (see `CoreTuning.puddlePointSpacing`).
    private struct Puddle {
        var x: Double
        var volume: Double
    }

    private struct Plan {
        var order: GlassOrder
        var belt: Double?
        var band: Double
    }

    private struct Glass {
        var id: Int
        var order: GlassOrder
        var shape: GlassShape
        var liquid: Liquid
        var belt: Double?
        var band: Double
        var capacity: Double
        var interior: Double
        var rimHalf: Double
        var wall: Double
        var floorY: Double
        var landingX: Double     // where the reference stream crosses this glass's rim height
        var arriveX: Double      // where the arrival slide ends
        var x: Double
        var startX: Double
        var phase: GlassPhase
        var phaseTime: Double
        var volume: Double
        var foam: Double
        var pouredIn: Double
        var patienceLeft: Double?
        var arrivedAt: Double?
        var overflowed: Bool
        var result: Judgement?
        var inBand: Bool
        var nearingSent: Bool
        var lastLanding: Double
        var lineOpacity: Double
        var lockSent: Bool
    }

    // MARK: - Configuration

    private var rng: CoreRNG
    private let jug: JugShape
    /// Drink volume (glass pt²) of a full jug: polygon area × `jugVolumeScale` (× `rushVolumeBoost` in Rush).
    private let jugVolume: Double
    private let isRush: Bool
    private let isPractice: Bool
    private let maxStrikes: Int
    private let startFill: Double
    private var plans: [Plan] = []
    private let fixedOrderCount: Int?

    // MARK: - State

    private var phase: SessionPhase = .intro
    private var time: Double = 0
    /// The flat gate (Duo only): no outflow, jug upright, patience paused, until the lid tilt is inside the dead zone.
    private var needsFlat: Bool = false
    private let usesFlatGate: Bool

    // Jug
    private var jugLiquid: Liquid
    private var jugFill: Double
    private var jugAngle: Double = 0
    private var outflow: Double = 0
    private var jugFills: [LiquidID: Double] = [:]
    private var swapTimer: Double = 0
    private var pendingLiquid: Liquid? = nil
    private var pendingFill: Double = 0
    private var sandFlowing: Bool = false
    private var avalanche: Double = 0
    private var pouring: Bool = false
    private var glugPhase: Double = 0
    private var glugNext: Double = 1
    private var emitAccumulator: Double = 0
    private var jugDry: Bool = false
    private var lipX: Double = 0
    private var lipY: Double = 0
    private var exitDX: Double = 1
    private var exitDY: Double = 0
    /// Seconds since the jug could last deliver (head > 0); the spout rope snaps after `CoreTuning.ropeMaxTime`.
    private var headlessTime: Double = 0

    // Stream and splashes
    private var particles: [Particle] = []
    private var sprays: [Spray] = []
    private var puddles: [Puddle] = []
    private var lastCounterLanding: Double = -10

    // Glasses and orders
    private var glasses: [Glass] = []
    private var nextGlassID: Int = 1
    private var nextPlanIndex: Int = 0
    private var generated: Int = 0
    private var idleTime: Double = 0

    // Score
    private var score: Int = 0
    private var streak: Int = 0
    private var bestStreak: Int = 0
    private var multiplier: Int = 1
    private var strikes: Int = 0
    private var ordersDone: Int = 0
    private var perfects: Int = 0
    private var hits: Int = 0
    private var spills: Int = 0
    private var judgements: [Judgement] = []
    private var poured: Double = 0
    private var pendingFinish: Double? = nil

    // Telemetry
    private var frameLanded: Double = 0
    private var landingRate: Double = 0

    // MARK: - Init

    init(mode: GameMode, layout: WorldLayout, seed: UInt64) {
        self.mode = mode
        self.layout = layout
        self.rng = CoreRNG(seed: seed)

        var plans: [Plan] = []
        var start: Double = 1.0
        var rush: Bool = false
        var practice: Bool = false
        var strikesAllowed: Int = CoreTuning.maxStrikes
        var fixedCount: Int? = nil
        switch mode {
        case .shift(let id):
            let level: Level = LevelCatalog.level(id) ?? LevelCatalog.levels[0]
            let belt: Double? = level.conveyorSpeed.map { (s: Double) -> Double in s * CoreTuning.beltScale }
            for o in level.orders {
                plans.append(Plan(order: o, belt: belt, band: level.perfectBand))
            }
            start = CoreMath.clamp(level.jugFill, 0.05, 1.0)
            fixedCount = plans.count
        case .daily(let day):
            for o in LevelCatalog.dailyOrders(day: day) {
                plans.append(Plan(order: o, belt: nil, band: CoreTuning.defaultPerfectBand))
            }
            fixedCount = plans.count
        case .rush:
            rush = true
        case .practice:
            practice = true
            strikesAllowed = 0
        }
        self.plans = plans
        self.fixedOrderCount = fixedCount
        self.startFill = start
        self.isRush = rush
        self.isPractice = practice
        self.maxStrikes = strikesAllowed
        let shape: JugShape = rush ? JugGeometry.big : JugGeometry.standard
        self.jug = shape
        self.jugVolume = Double(shape.capacity) * CoreTuning.jugVolumeScale * (rush ? CoreTuning.rushVolumeBoost : 1.0)
        self.jugFill = start
        self.usesFlatGate = layout.hasFold && !practice
        self.needsFlat = layout.hasFold && !practice

        let firstLiquid: LiquidID = plans.first?.order.liquid ?? .water
        self.jugLiquid = LiquidCatalog.liquid(firstLiquid)
        self.snapshot = GameSession.placeholderSnapshot(mode: mode, liquid: LiquidCatalog.liquid(firstLiquid))

        updateJugFrame(angle: 0)
        var ignored: [GameEvent] = []
        spawnNextGlass(events: &ignored, initial: true)
        snapshot = makeSnapshot()
    }

    // MARK: - Step

    /// Advance the simulation. `tilt` is the LID tilt in degrees (0 = flat/upright jug … 90).
    @discardableResult
    func step(dt: Double, tilt: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        let safeDt: Double = dt.isFinite ? dt : 0
        let frameDt: Double = CoreMath.clamp(safeDt, 0, CoreTuning.maxFrameDt)
        let lidTilt: Double = tilt.isFinite ? tilt : 0
        if needsFlat && frameDt > 0 && lidTilt < Rules.deadZone && phase != .finished {
            needsFlat = false
            events.append(.flatArmed)
        }
        // Until the gate opens the jug stays upright whatever the hinge says (a tipped jug with no stream would be
        // a physically impossible frame).
        let angle: Double = needsFlat ? 0 : Rules.jugAngle(forLidTilt: lidTilt)
        if frameDt > 0 {
            let count: Int = max(1, Int((frameDt / CoreTuning.maxSubstep - 1e-9).rounded(.up)))
            let h: Double = frameDt / Double(count)
            frameLanded = 0
            var i: Int = 0
            while i < count {
                substep(h, angle: angle, events: &events)
                i += 1
            }
            let rate: Double = frameLanded / frameDt
            landingRate += (rate - landingRate) * (1 - exp(-frameDt / CoreTuning.landingTau))
        }
        snapshot = makeSnapshot()
        return events
    }

    // MARK: - Sub-step

    private func substep(_ h: Double, angle: Double, events: inout [GameEvent]) {
        time += h
        if phase == .intro && time >= CoreTuning.introDuration {
            phase = .playing
        }

        // Jug swap in progress.
        if swapTimer > 0 {
            swapTimer -= h
            if swapTimer <= 0 {
                swapTimer = 0
                if let l = pendingLiquid {
                    jugLiquid = l
                    jugFill = pendingFill
                    jugFills[l.id] = pendingFill
                }
                pendingLiquid = nil
            }
        }

        jugAngle = angle
        updateJugFrame(angle: angle)
        updateOutflow(h, events: &events)
        updatePourEdges(h, events: &events)
        integrateParticles(h, events: &events)
        integrateSprays(h)
        updateGlasses(h, events: &events)
        checkJugEmpty(events: &events)

        if let pf = pendingFinish {
            let left: Double = pf - h
            if left <= 0 {
                pendingFinish = nil
                finish(events: &events)
            } else {
                pendingFinish = left
            }
        }
    }

    // MARK: - Jug

    private var flowNorm: Double {
        return CoreMath.clamp(outflow / CoreTuning.flowNormRef, 0, 1)
    }

    /// Resting position of the jug's pivot (its spout lip) before the crease lift.
    private func baseAnchor() -> CGPoint {
        return CGPoint(x: layout.jugPivot.x + CGFloat(CoreTuning.lipOffsetX),
                       y: layout.jugPivot.y - CGFloat(CoreTuning.lipDrop))
    }

    /// World pivot for this angle (lifted so the jug clears the crease).
    private func anchor(forAngle angle: Double) -> CGPoint {
        let base: CGPoint = baseAnchor()
        let floorY: CGFloat = layout.creaseMaxY + CGFloat(CoreTuning.jugClearance)
        let lift: CGFloat = JugGeometry.liftToClear(jug, angle: angle, at: base, floorY: floorY)
        return CGPoint(x: base.x, y: base.y + lift)
    }

    /// Exit direction of the stream at this jug angle (spout direction, clamped).
    private func exitDirection(angle: Double) -> (Double, Double) {
        let d: CGVector = JugGeometry.spoutDirection(jug, angle: angle)
        var deg: Double = atan2(Double(d.dy), Double(d.dx)) * 180.0 / Double.pi
        deg = CoreMath.clamp(deg, CoreTuning.exitDirMinDeg, CoreTuning.exitDirMaxDeg)
        let r: Double = CoreMath.radians(deg)
        return (cos(r), sin(r))
    }

    private func exitSpeed(flow: Double, liquid: Liquid) -> Double {
        return (CoreTuning.exitSpeedMin + CoreTuning.exitSpeedPerFlow * flow)
            / (1 + CoreTuning.exitViscositySlow * liquid.lagTau)
    }

    private func updateJugFrame(angle: Double) {
        let a: CGPoint = anchor(forAngle: angle)
        let lip: CGPoint = JugGeometry.transform(point: jug.lip, jug: jug, angle: angle, at: a)
        lipX = Double(lip.x)
        lipY = Double(lip.y)
        let d: (Double, Double) = exitDirection(angle: angle)
        exitDX = d.0
        exitDY = d.1
    }

    /// The angle the level-surface geometry uses: sand only "sees" the tip beyond its angle of repose.
    private func geometryAngle(_ angle: Double) -> Double {
        let repose: Double = jugLiquid.reposeDegrees
        if repose <= 0 { return angle }
        let effective: Double = sandFlowing ? max(0, repose - CoreTuning.sandHysteresis) : repose
        return max(0, angle - effective)
    }

    private func updateOutflow(_ h: Double, events: inout [GameEvent]) {
        let canPour: Bool = phase == .playing && swapTimer <= 0 && jugFill > 0 && !needsFlat
        var target: Double = 0
        var deliverable: Bool = false
        if canPour {
            let head: Double = Double(JugGeometry.head(jug, angle: geometryAngle(jugAngle), fill: jugFill))
            if head > 0 {
                deliverable = true
                target = min(CoreTuning.flowCap, CoreTuning.flowK * pow(head, 1.5))
            }
            if jugLiquid.reposeDegrees > 0 {
                if target > 0 {
                    if !sandFlowing {
                        sandFlowing = true
                        avalanche = CoreTuning.avalancheDuration
                    }
                } else {
                    sandFlowing = false
                    avalanche = 0
                }
                if avalanche > 0 && target > 0 {
                    target *= 1 + CoreTuning.avalancheBoost * (avalanche / CoreTuning.avalancheDuration)
                    avalanche = max(0, avalanche - h)
                }
            }
        } else {
            sandFlowing = false
            avalanche = 0
        }

        headlessTime = deliverable ? 0 : headlessTime + h
        if swapTimer > 0 || phase == .finished || needsFlat {
            outflow = 0
        } else {
            let lag: Double = max(0, jugLiquid.lagTau)
            var tau: Double
            if target >= outflow {
                tau = CoreTuning.riseTauBase + CoreTuning.riseTauPerLag * lag
            } else if deliverable {
                // Tipping back while it still pours: the surface lags briefly.
                tau = CoreTuning.declineTauPerLag * lag
            } else {
                // The jug can't deliver any more: only the rope in the spout drains, thins and snaps.
                tau = CoreMath.clamp(CoreTuning.ropeTauPerLag * lag, CoreTuning.ropeTauMin, CoreTuning.ropeTauMax)
            }
            tau = max(0.005, tau)
            outflow += (target - outflow) * (1 - exp(-h / tau))
            if !deliverable {
                let snap: Double = CoreTuning.outflowCutoff + CoreTuning.ropeSnapPerLag * lag
                if outflow < snap || headlessTime >= CoreTuning.ropeMaxTime { outflow = 0 }
            }
        }

        let cap: Double = jugVolume
        let available: Double = jugFill * cap
        var dv: Double = outflow * h
        if dv > available { dv = available }
        if dv < 0 { dv = 0 }
        if available <= 0 { outflow = 0 }
        if dv > 0 {
            jugFill = max(0, jugFill - dv / cap)
            poured += dv
        }
        emit(dv)
    }

    private func emit(_ dv: Double) {
        emitAccumulator += dv
        if emitAccumulator <= 0 { return }
        let f: Double = flowNorm
        let streaming: Bool = f >= CoreTuning.dropFlowThreshold
        let finalDrop: Bool = outflow <= 0 && emitAccumulator >= 1
        if !streaming && emitAccumulator < CoreTuning.dripVolume && !finalDrop { return }
        if outflow <= 0 && emitAccumulator < 1 { return }

        let speed: Double = exitSpeed(flow: f, liquid: jugLiquid)
        let vol: Double = emitAccumulator
        emitAccumulator = 0
        if particles.count >= CoreTuning.maxParticles {
            // Over the cap: fold the volume into the newest particle.
            let last: Int = particles.count - 1
            particles[last].volume += vol
            return
        }
        let p: Particle = Particle(x: lipX + exitDX * 2, y: lipY + exitDY * 2,
                                   vx: exitDX * speed, vy: exitDY * speed,
                                   volume: vol, flow: f, speed0: max(1, speed), born: time,
                                   isDrop: !streaming, glassID: -1)
        particles.append(p)
    }

    private func updatePourEdges(_ h: Double, events: inout [GameEvent]) {
        let f: Double = flowNorm
        if !pouring && f > CoreTuning.pourOnFlow {
            pouring = true
            glugPhase = 0.65
            events.append(.pourStarted)
        } else if pouring && f < CoreTuning.pourOffFlow {
            pouring = false
            events.append(.pourStopped)
        }
        if pouring && jugLiquid.reposeDegrees <= 0 {
            let hz: Double = (CoreTuning.glugBaseHz + CoreTuning.glugPerFlowHz * f)
                / (1 + CoreTuning.glugViscositySlow * jugLiquid.lagTau)
            glugPhase += h * hz
            if glugPhase >= glugNext {
                glugPhase -= glugNext
                glugNext = rng.range(0.85, 1.15)
                let intensity: Double = CoreMath.clamp((0.25 + 0.75 * f) * rng.range(0.88, 1.12), 0, 1)
                events.append(.glug(intensity: intensity))
            }
        }
    }

    private func beginSwap(to liquid: Liquid, fill: Double, events: inout [GameEvent]) {
        swapTimer = CoreTuning.jugSwapPause
        pendingLiquid = liquid
        pendingFill = fill
        outflow = 0
        sandFlowing = false
        avalanche = 0
        events.append(.jugSwapped)
    }

    private func checkJugEmpty(events: inout [GameEvent]) {
        if jugFill >= CoreTuning.jugEmptyFill { return }
        if phase != .playing { return }
        if isRush {
            if jugDry || pendingFinish != nil { return }
            if outflow > 0 || !particles.isEmpty { return }
            // Something to serve still? Then the normal serve rule judges it first (a Perfect may refill the jug).
            for g in glasses {
                if g.phase == .arriving { return }
                if g.phase == .filling && g.pouredIn >= CoreTuning.minServeVolume { return }
            }
            jugDry = true
            events.append(.jugEmpty)
            pendingFinish = CoreTuning.finishDelay
        } else {
            if swapTimer > 0 { return }
            let refill: Double = max(startFill, 0.5)
            jugFills[jugLiquid.id] = refill
            beginSwap(to: jugLiquid, fill: refill, events: &events)
        }
    }

    // MARK: - Stream particles

    private func rimY(_ g: Glass) -> Double {
        return g.floorY + g.interior
    }

    private func visibleTop(_ g: Glass) -> Double {
        return Double(GlassMath.height(g.shape, forVolume: CGFloat(g.volume + g.foam)))
    }

    private func glassIndex(id: Int) -> Int? {
        var i: Int = 0
        while i < glasses.count {
            if glasses[i].id == id { return i }
            i += 1
        }
        return nil
    }

    private func integrateParticles(_ h: Double, events: inout [GameEvent]) {
        if particles.isEmpty { return }
        let g: Double = CoreTuning.gravity
        let counterY: Double = Double(layout.counterY)
        var kept: [Particle] = []
        kept.reserveCapacity(particles.count)
        for var p in particles {
            let prevX: Double = p.x
            let prevY: Double = p.y
            p.vy -= g * h
            p.x += p.vx * h
            p.y += p.vy * h

            if p.glassID < 0 {
                var lostOnRim: Bool = false
                var gi: Int = 0
                while gi < glasses.count {
                    let glass: Glass = glasses[gi]
                    let ry: Double = rimY(glass)
                    if prevY > ry && p.y <= ry {
                        let t: Double = (prevY - ry) / max(1e-9, prevY - p.y)
                        let cx: Double = prevX + (p.x - prevX) * t
                        let dx: Double = abs(cx - glass.x)
                        if dx < glass.rimHalf - 1 {
                            p.glassID = glass.id
                            break
                        } else if dx < glass.rimHalf + glass.wall + 1.5 {
                            // Clipped the rim: it splashes off down the outside.
                            let side: Double = cx < glass.x ? -1 : 1
                            counterLanding(x: cx, footX: glass.x + side * (glass.rimHalf + glass.wall + 8),
                                           volume: p.volume, flow: p.flow, isDrop: p.isDrop, y: ry, events: &events)
                            lostOnRim = true
                            break
                        }
                    }
                    gi += 1
                }
                if lostOnRim { continue }
            }

            if p.glassID >= 0 {
                guard let gi = glassIndex(id: p.glassID) else { continue }
                let surface: Double = glasses[gi].floorY + visibleTop(glasses[gi])
                if p.y <= surface {
                    deposit(p, into: gi, surfaceY: surface, events: &events)
                    continue
                }
            } else if p.y <= counterY {
                counterLanding(x: p.x, footX: p.x, volume: p.volume, flow: p.flow, isDrop: p.isDrop, y: counterY,
                               events: &events)
                continue
            } else if p.x < -80 || p.x > Double(layout.size.width) + 80 {
                continue
            }
            kept.append(p)
        }
        particles = kept
    }

    private func deposit(_ p: Particle, into gi: Int, surfaceY: Double, events: inout [GameEvent]) {
        glasses[gi].volume += p.volume
        glasses[gi].pouredIn += p.volume
        let fpv: Double = glasses[gi].liquid.foamPerVolume
        if fpv > 0 {
            let factor: Double = CoreMath.clamp(p.flow / CoreTuning.foamRefFlow, CoreTuning.foamFactorMin,
                                                CoreTuning.foamFactorMax)
            glasses[gi].foam += fpv * p.volume * factor
        }
        if glasses[gi].phase == .filling { frameLanded += p.volume }

        let strength: Double = p.isDrop ? 0.2 : CoreMath.clamp(0.2 + 0.8 * p.flow.squareRoot(), 0, 1)
        if p.isDrop || time - glasses[gi].lastLanding > CoreTuning.splashEdgeGap {
            events.append(.splashInGlass(glassID: glasses[gi].id, x: CGFloat(p.x), strength: strength))
        }
        glasses[gi].lastLanding = time
        glasses[gi].lockSent = false
        maybeSpray(x: p.x, y: surfaceY, flow: p.flow, glassID: glasses[gi].id)
        checkOverflow(gi, events: &events)
    }

    private func counterLanding(x: Double, footX: Double, volume: Double, flow: Double, isDrop: Bool, y: Double,
                                events: inout [GameEvent]) {
        if isDrop || time - lastCounterLanding > CoreTuning.splashEdgeGap {
            let strength: Double = isDrop ? 0.2 : CoreMath.clamp(0.2 + 0.8 * flow.squareRoot(), 0, 1)
            events.append(.splashOnCounter(x: CGFloat(x), strength: strength))
        }
        addSpill(x: footX, volume: volume)
        lastCounterLanding = time
        maybeSpray(x: x, y: y, flow: flow, glassID: -1)
    }

    private func maybeSpray(x: Double, y: Double, flow: Double, glassID: Int) {
        if sprays.count >= CoreTuning.maxDroplets { return }
        let chance: Double = CoreTuning.splashChanceBase + CoreTuning.splashChancePerFlow * flow
        if !rng.chance(chance) { return }
        var sx: Double = x + rng.range(-3, 3)
        var spreadV: Double = 90
        if glassID >= 0, let gi = glassIndex(id: glassID) {
            let inner: Double = max(2, glasses[gi].rimHalf - CoreTuning.splashMouthInset)
            sx = CoreMath.clamp(sx, glasses[gi].x - inner, glasses[gi].x + inner)
            spreadV = 55
        }
        let power: Double = 0.5 + flow
        let s: Spray = Spray(x: sx, y: y + 1,
                             vx: rng.range(-spreadV, spreadV) * power,
                             vy: rng.range(140, 320) * power,
                             life: rng.range(CoreTuning.splashLifeMin, CoreTuning.splashLifeMax),
                             radius: rng.range(1.2, 3.0), glassID: glassID)
        sprays.append(s)
    }

    private func integrateSprays(_ h: Double) {
        if sprays.isEmpty { return }
        let floorY: Double = Double(layout.counterY)
        var kept: [Spray] = []
        kept.reserveCapacity(sprays.count)
        for var s in sprays {
            s.vy -= CoreTuning.gravity * h
            s.x += s.vx * h
            s.y += s.vy * h
            s.life -= h
            if s.life <= 0 || s.y <= floorY { continue }
            if s.glassID >= 0 {
                // Splash crown droplets stay inside the mouth (they bounce off the inner wall) and fall back in.
                guard let gi = glassIndex(id: s.glassID) else { continue }
                let g: Glass = glasses[gi]
                let inner: Double = max(2, g.rimHalf - CoreTuning.splashMouthInset)
                if s.x < g.x - inner {
                    s.x = g.x - inner
                    s.vx = abs(s.vx) * 0.4
                } else if s.x > g.x + inner {
                    s.x = g.x + inner
                    s.vx = -abs(s.vx) * 0.4
                }
                let surface: Double = g.floorY + visibleTop(g)
                if s.vy < 0 && s.y <= surface { continue }
            }
            kept.append(s)
        }
        sprays = kept
    }

    // MARK: - Puddles

    private func puddleRadius(_ volume: Double) -> Double {
        return CoreMath.clamp(CoreTuning.puddleBaseRadius + CoreTuning.puddleRadiusPerSqrtVolume * max(0, volume).squareRoot(),
                              CoreTuning.puddleBaseRadius, CoreTuning.puddleMaxRadius)
    }

    /// Pools `volume` of spilt drink at counter x (joins a nearby puddle or starts one).
    private func addSpill(x: Double, volume: Double) {
        if volume <= 0 { return }
        var best: Int = -1
        var bestD: Double = Double.greatestFiniteMagnitude
        var i: Int = 0
        while i < puddles.count {
            let d: Double = abs(puddles[i].x - x)
            if d < puddleRadius(puddles[i].volume) + CoreTuning.puddleJoinMargin && d < bestD {
                best = i
                bestD = d
            }
            i += 1
        }
        if best >= 0 {
            // Volume-weighted centre, so a puddle creeps toward where it is fed.
            let v0: Double = puddles[best].volume
            let total: Double = v0 + volume
            puddles[best].x = (puddles[best].x * v0 + x * volume) / max(1e-9, total)
            puddles[best].volume = total
            clampPuddle(best)
        } else {
            puddles.append(Puddle(x: x, volume: volume))
            clampPuddle(puddles.count - 1)
        }
        // Keep the encoded point count bounded: drop the oldest puddles first.
        while puddles.count > 1 && puddlePointCount() > CoreTuning.maxPuddlePoints {
            puddles.removeFirst()
        }
    }

    @discardableResult
    private func clampPuddle(_ i: Int) -> Int {
        let r: Double = puddleRadius(puddles[i].volume)
        let lo: Double = CoreTuning.safeMinX + r
        let hi: Double = CoreTuning.safeMaxX - r
        puddles[i].x = lo <= hi ? CoreMath.clamp(puddles[i].x, lo, hi) : (CoreTuning.safeMinX + CoreTuning.safeMaxX) * 0.5
        return i
    }

    private func puddlePoints(_ p: Puddle) -> Int {
        let half: Double = max(0, puddleRadius(p.volume) - CoreTuning.puddlePointInset)
        return 1 + Int((2 * half / CoreTuning.puddlePointSpacing).rounded(.down))
    }

    private func puddlePointCount() -> Int {
        var n: Int = 0
        for p in puddles { n += puddlePoints(p) }
        return n
    }

    /// Snapshot encoding: each puddle → a run of points `puddlePointSpacing` apart along the counter line, centred on
    /// the puddle and spanning ± (radius − inset). Puddles never overlap their runs by less than one spacing.
    private func encodedPuddles() -> [CGPoint] {
        var out: [CGPoint] = []
        let y: CGFloat = layout.counterY
        for p in puddles {
            let n: Int = puddlePoints(p)
            let span: Double = Double(n - 1) * CoreTuning.puddlePointSpacing
            var k: Int = 0
            while k < n {
                let x: Double = p.x - span * 0.5 + Double(k) * CoreTuning.puddlePointSpacing
                out.append(CGPoint(x: CGFloat(x), y: y))
                k += 1
            }
        }
        return out
    }

    private func checkOverflow(_ gi: Int, events: inout [GameEvent]) {
        let cap: Double = glasses[gi].capacity
        let total: Double = glasses[gi].volume + glasses[gi].foam
        if total <= cap * (1 + CoreTuning.overflowTolerance) { return }
        let excess: Double = total - cap
        let foamSpill: Double = min(glasses[gi].foam, excess)
        glasses[gi].foam -= foamSpill
        glasses[gi].volume = max(0, glasses[gi].volume - (excess - foamSpill))
        // Everything over the brim sheets down the glass and pools around its foot.
        addSpill(x: glasses[gi].x, volume: excess)
        if !glasses[gi].overflowed {
            glasses[gi].overflowed = true
            events.append(.overflowStarted(glassID: glasses[gi].id))
            // Live spill: judged the instant it goes over the rim (the overflow keeps sheeting while it leaves).
            if glasses[gi].phase == .filling && phase == .playing && pendingFinish == nil {
                serve(gi, events: &events)
            }
        }
    }

    // MARK: - Glasses

    private func updateGlasses(_ h: Double, events: inout [GameEvent]) {
        let idleNow: Bool = outflow <= 0 && particles.isEmpty
        idleTime = idleNow ? idleTime + h : 0

        var i: Int = 0
        while i < glasses.count {
            glasses[i].phaseTime += h

            // Foam settles.
            if glasses[i].foam > 0 {
                let settle: Double = max(0.05, glasses[i].liquid.foamSettle)
                glasses[i].foam *= exp(-h / settle)
                if glasses[i].foam < 0.5 { glasses[i].foam = 0 }
            }

            switch glasses[i].phase {
            case .arriving:
                let u: Double = glasses[i].phaseTime / CoreTuning.arriveDuration
                glasses[i].x = CoreMath.lerp(CoreTuning.arriveFromX, glasses[i].arriveX, CoreMath.easeOutCubic(u))
                if u >= 1 {
                    glasses[i].x = glasses[i].arriveX
                    glasses[i].phase = .filling
                    glasses[i].phaseTime = 0
                    glasses[i].arrivedAt = time
                    events.append(.glassArrived(glassID: glasses[i].id))
                }
            case .filling:
                if let belt = glasses[i].belt { glasses[i].x += belt * h }
                updateFilling(i, h, events: &events)
            case .served:
                if let belt = glasses[i].belt { glasses[i].x += belt * h }
                let streamBusy: Bool = glasses[i].belt == nil && (outflow > 0 || !particles.isEmpty)
                let waited: Bool = glasses[i].phaseTime >= CoreTuning.resultHold + CoreTuning.changeoverWaitMax
                if glasses[i].phaseTime >= CoreTuning.resultHold && (!streamBusy || waited) {
                    glasses[i].phase = .leaving
                    glasses[i].phaseTime = 0
                    glasses[i].startX = glasses[i].x
                    if glasses[i].belt == nil { spawnNextGlass(events: &events, initial: false) }
                }
            case .leaving:
                let u: Double = CoreMath.clamp(glasses[i].phaseTime / CoreTuning.leaveDuration, 0, 1)
                let drift: Double = (glasses[i].belt ?? 0) * glasses[i].phaseTime
                let k: Double = CoreTuning.leaveLinear
                let ease: Double = k * u + (1 - k) * u * u
                glasses[i].x = glasses[i].startX + drift + (CoreTuning.leaveToX - glasses[i].startX) * ease
            }
            i += 1
        }

        glasses.removeAll(where: { (g: Glass) -> Bool in
            g.phase == .leaving && g.phaseTime >= CoreTuning.leaveDuration
        })
    }

    private func updateFilling(_ i: Int, _ h: Double, events: inout [GameEvent]) {
        // Line fade ("line fades" orders): reveal again once served.
        if let fade = glasses[i].order.lineFadesAfter, let arrived = glasses[i].arrivedAt {
            let t: Double = time - arrived - fade
            glasses[i].lineOpacity = 1 - CoreMath.clamp(t / CoreTuning.lineFadeDuration, 0, 1)
        }

        let interior: Double = glasses[i].interior
        let lineH: Double = glasses[i].order.line * interior
        let top: Double = visibleTop(glasses[i])

        let inBand: Bool = abs(top - lineH) <= glasses[i].band * interior
        if inBand && !glasses[i].inBand {
            events.append(.enteredPerfectBand(glassID: glasses[i].id))
        }
        glasses[i].inBand = inBand

        if !glasses[i].nearingSent && pouring && lineH > 0 && top >= CoreTuning.nearingLineFraction * lineH {
            glasses[i].nearingSent = true
            events.append(.nearingLine(glassID: glasses[i].id))
        }

        if phase != .playing || pendingFinish != nil { return }

        // Overflowed before it was in place (it slid in under a running stream): judge it now.
        if glasses[i].overflowed {
            serve(i, events: &events)
            return
        }

        let foamH: Double = top - Double(GlassMath.height(glasses[i].shape, forVolume: CGFloat(glasses[i].volume)))
        let settled: Bool = foamH <= CoreTuning.foamSettledFraction * interior

        // Lock-in cue: the stream has finished landing (nothing pouring, nothing in the air) with the settled top
        // inside the Perfect band. Fires the moment it is true, ~serveIdle before the verdict.
        if !glasses[i].lockSent && idleTime > 0 && glasses[i].pouredIn >= CoreTuning.minServeVolume && settled
            && inBand {
            glasses[i].lockSent = true
            events.append(.lockedIn(glassID: glasses[i].id))
        }

        if glasses[i].belt != nil {
            // Conveyor: judged once the mouth has passed the stream.
            if glasses[i].x - glasses[i].rimHalf > glasses[i].landingX + CoreTuning.conveyorExitMargin {
                serve(i, events: &events)
            }
            return
        }

        if let p = glasses[i].patienceLeft, !needsFlat {
            let left: Double = p - h
            glasses[i].patienceLeft = max(0, left)
            if left <= 0 {
                serve(i, events: &events)
                return
            }
        }

        if glasses[i].pouredIn >= CoreTuning.minServeVolume && idleTime >= CoreTuning.serveIdle {
            if settled || idleTime >= CoreTuning.serveIdle + CoreTuning.foamServeGrace {
                serve(i, events: &events)
            }
        }
    }

    private func serve(_ i: Int, events: inout [GameEvent]) {
        let interior: Double = glasses[i].interior
        let top: Double = visibleTop(glasses[i])
        let lineH: Double = glasses[i].order.line * interior
        let j: Judgement = Rules.judge(top: CGFloat(top), line: CGFloat(lineH), interior: CGFloat(interior),
                                       overflowed: glasses[i].overflowed, perfectBand: glasses[i].band)
        glasses[i].result = j
        glasses[i].phase = .served
        glasses[i].phaseTime = 0
        glasses[i].lineOpacity = 1
        glasses[i].inBand = false
        ordersDone += 1
        judgements.append(j)

        let oldStreak: Int = streak
        let oldMultiplier: Int = multiplier
        switch j {
        case .perfect:
            streak += 1
            perfects += 1
        case .great, .good:
            break
        case .short, .spill:
            streak = 0
        }
        if j.isHit { hits += 1 }
        if j == .spill { spills += 1 }
        bestStreak = max(bestStreak, streak)
        multiplier = Rules.multiplier(forStreak: streak)
        let points: Int = isPractice ? 0 : Rules.points(for: j, multiplier: multiplier)
        score += points
        events.append(.served(glassID: glasses[i].id, judgement: j, points: points))
        if streak != oldStreak { events.append(.streak(streak)) }
        if multiplier != oldMultiplier { events.append(.multiplier(multiplier)) }

        // Strikes: shifts and daily count spills and shorts; Rush counts spills; practice never.
        var strike: Bool = false
        if !isPractice {
            if isRush {
                strike = j == .spill
            } else {
                strike = j == .spill || j == .short
            }
        }
        if strike {
            strikes += 1
            events.append(.strike(strikes))
        }

        if isRush && (j == .perfect || j == .great) {
            let want: Double = j == .perfect ? CoreTuning.rushRefill : CoreTuning.rushRefillGreat
            let add: Double = min(want, 1 - jugFill)
            if add > 0 {
                jugFill += add
                events.append(.jugRefilled(fraction: add))
            }
        }

        // End of run?
        if !isPractice {
            if maxStrikes > 0 && strikes >= maxStrikes {
                pendingFinish = CoreTuning.finishDelay
            } else if let total = fixedOrderCount, ordersDone >= total {
                pendingFinish = CoreTuning.finishDelay
            } else if isRush && jugFill < CoreTuning.jugEmptyFill {
                jugDry = true
                events.append(.jugEmpty)
                pendingFinish = CoreTuning.finishDelay
            }
        }

        // Conveyor glasses ride on; the next one is sent down the belt straight away.
        if glasses[i].belt != nil { spawnNextGlass(events: &events, initial: false) }
    }

    private func finish(events: inout [GameEvent]) {
        if phase == .finished { return }
        phase = .finished
        outflow = 0
        var stars: Int = 0
        var cleared: Bool = true
        switch mode {
        case .shift:
            let total: Int = fixedOrderCount ?? ordersDone
            cleared = strikes < maxStrikes && ordersDone >= total
            stars = cleared ? Rules.stars(perfects: perfects, hits: hits, spills: spills, total: total) : 0
            if stars < 1 { cleared = false }
        case .daily:
            cleared = strikes < maxStrikes
        case .rush, .practice:
            cleared = true
        }
        let r: RunResult = RunResult(mode: mode, score: score, stars: stars, perfects: perfects, bestStreak: bestStreak,
                                     judgements: judgements, poured: poured, cleared: cleared)
        result = r
        events.append(.finished(r))
    }

    // MARK: - Orders and spawning

    private func nextPlan() -> Plan? {
        if fixedOrderCount != nil {
            if nextPlanIndex >= plans.count { return nil }
            let p: Plan = plans[nextPlanIndex]
            nextPlanIndex += 1
            return p
        }
        let p: Plan = isRush ? makeRushPlan(generated) : makePracticePlan()
        generated += 1
        return p
    }

    private func spawnNextGlass(events: inout [GameEvent], initial: Bool) {
        if phase == .finished || pendingFinish != nil { return }
        if isRush && jugDry { return }
        guard let plan = nextPlan() else { return }
        let shape: GlassShape = GlassCatalog.shape(plan.order.glass)
        let liquid: Liquid = LiquidCatalog.liquid(plan.order.liquid)
        let capacity: Double = Double(GlassMath.capacity(shape))
        let interior: Double = Double(shape.interiorHeight)
        let rimHalf: Double = Double(shape.rimHalfWidth)
        let floorY: Double = Double(layout.counterY + shape.baseThickness)

        // The jug for this drink (decided first: the glass is placed for the fill it will be poured from).
        if initial {
            jugLiquid = liquid
            jugFill = startFill
            jugFills[liquid.id] = startFill
        } else if isRush {
            jugLiquid = liquid       // one big shared jug
        } else {
            let current: Liquid = pendingLiquid ?? jugLiquid
            if current.id != liquid.id {
                let currentFill: Double = pendingLiquid != nil ? pendingFill : jugFill
                jugFills[current.id] = currentFill
                beginSwap(to: liquid, fill: jugFills[liquid.id] ?? startFill, events: &events)
            }
        }
        let pourFill: Double = pendingLiquid != nil ? pendingFill : jugFill

        let landing: Double = referenceLandingX(rimY: floorY + interior, liquid: liquid, fill: pourFill)
        var arriveX: Double = landing
        if let belt = plan.belt {
            let leadIn: Double = CoreMath.clamp(belt * 0.9, 10, CoreTuning.conveyorLeadIn)
            arriveX = landing - rimHalf - leadIn
        }
        let prefill: Double = CoreMath.clamp(plan.order.prefill, 0, 0.95)
        let preVolume: Double = Double(GlassMath.volume(shape, upTo: CGFloat(prefill * interior)))
        let g: Glass = Glass(id: nextGlassID, order: plan.order, shape: shape, liquid: liquid, belt: plan.belt,
                             band: plan.band, capacity: capacity, interior: interior, rimHalf: rimHalf,
                             wall: Double(shape.wall), floorY: floorY, landingX: landing, arriveX: arriveX,
                             x: CoreTuning.arriveFromX, startX: CoreTuning.arriveFromX, phase: .arriving, phaseTime: 0,
                             volume: preVolume, foam: 0, pouredIn: 0,
                             patienceLeft: plan.belt == nil ? plan.order.patience : nil,
                             arrivedAt: nil, overflowed: false, result: nil, inBand: false, nearingSent: false,
                             lastLanding: -10, lineOpacity: 1, lockSent: false)
        nextGlassID += 1
        glasses.append(g)
    }

    /// Where a stream leaving the lip at `angle` with normalized `flow` crosses height `rimY`.
    private func landingX(angle: Double, flow: Double, rimY: Double, liquid: Liquid) -> Double {
        let a: CGPoint = anchor(forAngle: angle)
        let lip: CGPoint = JugGeometry.transform(point: jug.lip, jug: jug, angle: angle, at: a)
        let dir: (Double, Double) = exitDirection(angle: angle)
        let speed: Double = exitSpeed(flow: flow, liquid: liquid)
        let t: Double = GameSession.fallTime(fromY: Double(lip.y), vy: dir.1 * speed, toY: rimY)
        return Double(lip.x) + dir.0 * speed * t
    }

    /// The glass's stop x: the middle of the landing range over the pours this jug fill will really use (from its
    /// pour point to `placementAngleSpan` beyond it, flows 0.15…0.9), plus the bias. Deterministic.
    private func referenceLandingX(rimY: Double, liquid: Liquid, fill: Double) -> Double {
        let geoStart: Double = JugGeometry.pourThreshold(jug, fill: CoreMath.clamp(fill, 0.02, 1), step: 1)
        let start: Double = min(geoStart + liquid.reposeDegrees, 125)
        var lo: Double = Double.greatestFiniteMagnitude
        var hi: Double = -Double.greatestFiniteMagnitude
        let maxAngle: Double = Rules.jugAngle(forLidTilt: 90)
        for k in 0...4 {
            let angle: Double = min(maxAngle, start + CoreTuning.placementAngleSpan * Double(k) / 4.0)
            for f in [0.15, 0.5, 0.9] {
                let x: Double = landingX(angle: angle, flow: f, rimY: rimY, liquid: liquid)
                lo = min(lo, x)
                hi = max(hi, x)
            }
        }
        return (lo + hi) * 0.5 + CoreTuning.glassPlacementBias
    }

    private static func fallTime(fromY y0: Double, vy: Double, toY y1: Double) -> Double {
        let d: Double = y0 - y1
        if d <= 0 { return 0 }
        let g: Double = CoreTuning.gravity
        return (vy + (vy * vy + 2 * g * d).squareRoot()) / g
    }

    private func round2(_ v: Double) -> Double {
        return (v * 100).rounded() / 100
    }

    /// Rush: tier every 8 glasses — patience shrinks, foamy/viscous drinks and odd glasses mix in, conveyors from
    /// tier 3, prefilled curveballs from tier 4, the Perfect band narrows.
    private func makeRushPlan(_ n: Int) -> Plan {
        let tier: Int = n / CoreTuning.rushTierEvery
        var liquids: [LiquidID] = [.water, .lemonade, .orangeJuice]
        var pool: [String] = ["tumbler", "highball", "pint", "jar"]
        if tier >= 1 {
            liquids.append(contentsOf: [.cola, .creamSoda])
            pool.append(contentsOf: ["mug", "flute"])
        }
        if tier >= 2 {
            liquids.append(contentsOf: [.rootBeer, .milkshake, .mapleSyrup])
            pool.append(contentsOf: ["bowl", "sundae", "beaker"])
        }
        if tier >= 3 {
            liquids.append(contentsOf: [.honey, .berrySmoothie, .potionBlue, .potionPink])
            pool.append(contentsOf: ["shot", "vial"])
        }
        let liquid: LiquidID = rng.pick(liquids)
        let glass: String = rng.pick(pool)
        let line: Double = round2(rng.range(0.45, tier >= 2 ? 0.9 : 0.85))
        let shape: GlassShape = GlassCatalog.shape(glass)
        let needed: Double = Double(GlassMath.volume(shape, upTo: shape.interiorHeight * CGFloat(line)))
        let sizeFactor: Double = CoreMath.clamp((needed / CoreTuning.rushPatienceVolumeRef).squareRoot(), 0.8, 1.5)
        let viscosity: Double = 1 + LiquidCatalog.liquid(liquid).lagTau
        var patience: Double? = max(5.0, 9.5 - 0.7 * Double(tier)) * sizeFactor * viscosity
        var belt: Double? = nil
        if tier >= 3 && rng.chance(tier >= 4 ? 0.5 : 0.35) {
            belt = min(40, 18 + 4 * Double(tier - 3)) * CoreTuning.beltScale
            patience = nil
        }
        var prefill: Double = 0
        if tier >= 4 && line >= 0.6 && rng.chance(0.15) { prefill = 0.2 }
        let band: Double = max(0.018, 0.03 - 0.002 * Double(tier))
        let order: GlassOrder = GlassOrder(glass: glass, liquid: liquid, line: line, patience: patience,
                                           lineFadesAfter: nil, prefill: prefill)
        return Plan(order: order, belt: belt, band: band)
    }

    /// Practice: calm, endless basics.
    private func makePracticePlan() -> Plan {
        let liquids: [LiquidID] = [.water, .lemonade, .orangeJuice]
        let pool: [String] = ["tumbler", "highball", "jar", "pint", "mug"]
        let line: Double = round2(rng.range(0.5, 0.8))
        let order: GlassOrder = GlassOrder(glass: rng.pick(pool), liquid: rng.pick(liquids), line: line)
        return Plan(order: order, belt: nil, band: 0.03)
    }

    // MARK: - Telemetry

    private func activeGlassIndex() -> Int? {
        var i: Int = 0
        while i < glasses.count {
            if glasses[i].phase == .filling { return i }
            i += 1
        }
        return nil
    }

    private func glassVelocity(_ g: Glass) -> Double {
        if g.phase == .filling || g.phase == .served { return g.belt ?? 0 }
        return 0
    }

    /// Volume (pt²) that will still land in glass `g` if the jug goes upright now: particles already in it or bound
    /// for its mouth, plus the lagged outflow still to come (≈ outflow · lagTau) if the stream is landing in it.
    private func incomingVolume(_ g: Glass) -> Double {
        let gravity: Double = CoreTuning.gravity
        let ry: Double = rimY(g)
        let vel: Double = glassVelocity(g)
        var incoming: Double = 0
        for p in particles {
            if p.glassID == g.id {
                incoming += p.volume
                continue
            }
            if p.glassID >= 0 || p.y <= ry { continue }
            let t: Double = (p.vy + (p.vy * p.vy + 2 * gravity * (p.y - ry)).squareRoot()) / gravity
            let px: Double = p.x + p.vx * t
            let gx: Double = g.x + vel * t
            if abs(px - gx) < g.rimHalf - 1 { incoming += p.volume }
        }
        if outflow > 0 || emitAccumulator > 0 {
            let speed: Double = exitSpeed(flow: flowNorm, liquid: jugLiquid)
            let vy: Double = exitDY * speed
            let t: Double = GameSession.fallTime(fromY: lipY, vy: vy, toY: ry)
            let px: Double = lipX + exitDX * speed * t
            let gx: Double = g.x + vel * t
            if abs(px - gx) < g.rimHalf - 1 {
                // If the jug goes upright now, only the spout rope still drains (exp. decay, cut at ropeMaxTime).
                let lag: Double = max(0, jugLiquid.lagTau)
                let ropeTau: Double = CoreMath.clamp(CoreTuning.ropeTauPerLag * lag, CoreTuning.ropeTauMin,
                                                     CoreTuning.ropeTauMax)
                let tail: Double = outflow * ropeTau * (1 - exp(-CoreTuning.ropeMaxTime / ropeTau))
                incoming += tail + emitAccumulator
            }
        }
        return incoming
    }

    private func telemetry() -> PourTelemetry {
        let f: Double = flowNorm
        let landing: Double = CoreMath.clamp(landingRate / CoreTuning.flowNormRef, 0, 1)
        guard let gi = activeGlassIndex() else {
            return PourTelemetry(flow: f, landingRate: landing, activeFill: 0, distanceToLine: -1,
                                 projectedDistanceToLine: -1, liquid: jugLiquid.id)
        }
        let g: Glass = glasses[gi]
        let interior: Double = max(1, g.interior)
        let lineH: Double = g.order.line * interior
        let top: Double = visibleTop(g)

        // Projection: everything in the air + the lag tail lands, then the head settles until serving.
        let incoming: Double = incomingVolume(g)
        let liquidFinal: Double = g.volume + incoming
        var foamFinal: Double = 0
        let fpv: Double = g.liquid.foamPerVolume
        if fpv > 0 || g.foam > 0 {
            let factor: Double = CoreMath.clamp(f / CoreTuning.foamRefFlow, CoreTuning.foamFactorMin,
                                                CoreTuning.foamFactorMax)
            let foamNow: Double = g.foam + fpv * incoming * factor
            let settle: Double = max(0.05, g.liquid.foamSettle)
            let early: Double = foamNow * exp(-CoreTuning.projectionFoamTime / settle)
            let late: Double = foamNow * exp(-(CoreTuning.projectionFoamTime + CoreTuning.foamServeGrace) / settle)
            // Serving waits (up to the grace) for the head to drop below the "settled" height.
            let liquidTopFinal: Double = Double(GlassMath.height(g.shape, forVolume: CGFloat(liquidFinal)))
            let settledTop: Double = min(interior, liquidTopFinal + CoreTuning.foamSettledFraction * interior)
            let settledFoamVolume: Double = max(0, Double(GlassMath.volume(g.shape, upTo: CGFloat(settledTop))) - liquidFinal)
            foamFinal = min(early, max(settledFoamVolume, late))
        }
        let totalFinal: Double = liquidFinal + foamFinal
        var projTop: Double
        if totalFinal <= g.capacity {
            projTop = Double(GlassMath.height(g.shape, forVolume: CGFloat(totalFinal)))
        } else {
            projTop = interior + (totalFinal - g.capacity) / max(1, 2 * g.rimHalf)
        }
        if g.overflowed { projTop = max(projTop, interior + 1) }

        return PourTelemetry(flow: f, landingRate: landing, activeFill: CoreMath.clamp(top / interior, 0, 1),
                             distanceToLine: (top - lineH) / interior,
                             projectedDistanceToLine: (projTop - lineH) / interior,
                             liquid: jugLiquid.id)
    }

    // MARK: - Snapshot

    private func streamWidth(flow: Double, speed0: Double, speed: Double) -> Double {
        let base: Double = max(CoreTuning.streamWidthMin, CoreTuning.streamWidthMax * flow.squareRoot())
        let ref: Double = max(speed0, CoreTuning.streamThinRefSpeed)
        let thin: Double = max(CoreTuning.streamThinFloor, pow(max(1e-6, ref / max(speed, 1e-6)), CoreTuning.streamThinning))
        return max(CoreTuning.streamWidthMin, base * min(1, thin))
    }

    private func makeStream() -> [StreamPoint] {
        var pts: [StreamPoint] = []
        let f: Double = flowNorm
        var prevBorn: Double = time
        if outflow > 0 && f >= CoreTuning.dropFlowThreshold {
            let s0: Double = exitSpeed(flow: f, liquid: jugLiquid)
            pts.append(StreamPoint(position: CGPoint(x: lipX, y: lipY),
                                   width: CGFloat(streamWidth(flow: f, speed0: s0, speed: s0))))
        }
        var i: Int = particles.count - 1
        while i >= 0 {
            let p: Particle = particles[i]
            i -= 1
            if p.isDrop { continue }
            if !pts.isEmpty && prevBorn - p.born > CoreTuning.streamGapTime {
                // A break in the ribbon: pinch both ends to zero width.
                pts[pts.count - 1].width = 0
                pts.append(StreamPoint(position: CGPoint(x: p.x, y: p.y), width: 0))
                prevBorn = p.born
                continue
            }
            let speed: Double = (p.vx * p.vx + p.vy * p.vy).squareRoot()
            pts.append(StreamPoint(position: CGPoint(x: p.x, y: p.y),
                                   width: CGFloat(streamWidth(flow: p.flow, speed0: p.speed0, speed: speed))))
            prevBorn = p.born
        }
        if pts.count == 1 { return [] }
        return pts
    }

    private func makeDroplets() -> [Droplet] {
        var out: [Droplet] = []
        for p in particles where p.isDrop {
            let r: Double = CoreMath.clamp((p.volume / Double.pi).squareRoot(), 1.8, 5.0)
            out.append(Droplet(position: CGPoint(x: p.x, y: p.y), velocity: CGVector(dx: p.vx, dy: p.vy),
                               radius: CGFloat(r)))
        }
        for s in sprays {
            out.append(Droplet(position: CGPoint(x: s.x, y: s.y), velocity: CGVector(dx: s.vx, dy: s.vy),
                               radius: CGFloat(s.radius)))
        }
        return out
    }

    private func makeJugState() -> JugState {
        let a: CGPoint = anchor(forAngle: jugAngle)
        let geoAngle: Double = geometryAngle(jugAngle)
        let pose = JugGeometry.pose(jug, angle: geoAngle, fill: jugFill, at: a)
        let extra: Double = jugAngle - geoAngle
        var outline: [CGPoint] = pose.outline
        var liquid: [CGPoint] = pose.liquid
        var lip: CGPoint = pose.lip
        if extra != 0 {
            // Sand: the pile keeps its slope; rotate the whole pose on to the real angle.
            outline = JugGeometry.rotate(outline, by: extra, about: a)
            liquid = JugGeometry.rotate(liquid, by: extra, about: a)
            let rotatedLip: [CGPoint] = JugGeometry.rotate([lip], by: extra, about: a)
            lip = rotatedLip[0]
        }
        return JugState(liquid: jugLiquid, angle: jugAngle, fill: jugFill, outline: outline, liquidPolygon: liquid,
                        lip: lip, pivot: a, flow: flowNorm)
    }

    private func makeGlassStates() -> [GlassState] {
        var out: [GlassState] = []
        for g in glasses {
            let liquidH: Double = Double(GlassMath.height(g.shape, forVolume: CGFloat(g.volume)))
            let top: Double = visibleTop(g)
            let lineH: Double = g.order.line * g.interior
            let inBand: Bool = g.phase == .filling && abs(top - lineH) <= g.band * g.interior
            out.append(GlassState(id: g.id, shape: g.shape, liquid: g.liquid, x: CGFloat(g.x), phase: g.phase,
                                  liquidHeight: CGFloat(liquidH), foamHeight: CGFloat(max(0, top - liquidH)),
                                  lineHeight: CGFloat(lineH), lineOpacity: g.lineOpacity, inPerfectBand: inBand,
                                  overflowing: g.overflowed, patienceLeft: g.patienceLeft,
                                  patienceTotal: g.belt == nil ? g.order.patience : nil, result: g.result))
        }
        return out
    }

    private func makeSnapshot() -> GameSnapshot {
        var s: GameSnapshot = GameSnapshot(time: time, phase: phase, mode: mode, jug: makeJugState(), stream: makeStream(),
                                           droplets: makeDroplets(), glasses: makeGlassStates(),
                                           puddles: encodedPuddles(), score: score, streak: streak,
                                           multiplier: multiplier, strikes: strikes, maxStrikes: maxStrikes,
                                           ordersDone: ordersDone, ordersTotal: fixedOrderCount, perfects: perfects,
                                           telemetry: telemetry())
        s.needsFlat = needsFlat
        return s
    }

    private static func placeholderSnapshot(mode: GameMode, liquid: Liquid) -> GameSnapshot {
        let jug: JugState = JugState(liquid: liquid, angle: 0, fill: 0, outline: [], liquidPolygon: [],
                                     lip: CGPoint(x: 0, y: 0), pivot: CGPoint(x: 0, y: 0), flow: 0)
        return GameSnapshot(time: 0, phase: .intro, mode: mode, jug: jug, stream: [], droplets: [], glasses: [],
                            puddles: [], score: 0, streak: 0, multiplier: 1, strikes: 0, maxStrikes: 0,
                            ordersDone: 0, ordersTotal: nil, perfects: 0, telemetry: PourTelemetry())
    }

    // MARK: - Flat gate

    /// Re-arm the flat gate (call on resume, and after anything that let the hinge move unobserved): no outflow and
    /// an upright jug until the lid tilt has been inside the dead zone once. No-op on phones without a fold and in
    /// practice. `snapshot.needsFlat` turns true at once; `.flatArmed` fires when it opens again.
    func requireFlat() {
        if !usesFlatGate || phase == .finished { return }
        needsFlat = true
        snapshot.needsFlat = true
    }

    // MARK: - Test / debug hooks (internal; used by unit tests and demo scripts)

    /// Set the jug's fill (0…1). Tests use it to keep Rush going until the spill rule ends it.
    func debugSetJugFill(_ fill: Double) {
        jugFill = CoreMath.clamp(fill, 0, 1)
        if isRush { jugDry = false }
    }
}
