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
    /// The world is the same on every canvas; `adoptCanvas(_:)` can update `visibleRect` and `hasFold` mid-run.
    private(set) var layout: WorldLayout
    private(set) var snapshot: GameSnapshot
    private(set) var result: RunResult?
    var isFinished: Bool { return phase == .finished }

    /// Round 4 (REVIEW-3 P1-4 fallback): the order after the glass at the stop, when it is known without drawing from
    /// the RNG: the waiting glass's, else a plan already generated, else the next fixed order (shifts, Daily). Lets
    /// the HUD show a small "next" icon when no waiting glass fits on screen (no `isWaitingInSlot` glass in the
    /// snapshot). nil after the last order, and in practice until the next plan exists. Round 8: `upcomingOrders.first`.
    var upcomingOrder: GlassOrder? {
        return upcomingOrders.first
    }

    /// Round 8 (QA-3 / ROUND-8 Core row): up to `upcomingDepth` (2) orders after the glass at the stop, in the order
    /// they will appear: the waiting glass's, then plans already generated, then the next fixed orders (shifts, Daily).
    /// Rush generates its plans two ahead as each glass is placed (`topUpRushPeek`), so this is filled in every tier,
    /// the Conveyor's included. Reading it never draws from the RNG: a run is the same whether or not anyone looks.
    var upcomingOrders: [GlassOrder] {
        var out: [GlassOrder] = []
        if let wi = waitingIndex() { out.append(glasses[wi].order) }
        var k: Int = 0
        while out.count < GameSession.upcomingDepth && k < peekedPlans.count {
            out.append(peekedPlans[k].order)
            k += 1
        }
        if fixedOrderCount != nil {
            var n: Int = nextPlanIndex
            while out.count < GameSession.upcomingDepth && n < plans.count {
                out.append(plans[n].order)
                n += 1
            }
        }
        return out
    }

    /// How many upcoming orders `upcomingOrders` names (and Rush keeps generated ahead).
    static let upcomingDepth: Int = 2

    /// Round 7 (QA-3 P1-3): true while the App holds the run behind a venue intro card (`setStartHold(_:)`). Belts,
    /// patience and line-fade clocks are frozen exactly as behind the flat gate; pouring is allowed and releases it.
    private(set) var isStartHeld: Bool = false

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
    /// Round 3: it belongs to the glass that spilled it and dries once that glass leaves.
    private struct Puddle {
        var x: Double
        var volume: Double
        var owner: Int          // glass id (-1 = no glass nearby)
        var dryAge: Double?     // nil while its glass is still on the counter; else seconds spent drying
    }

    private struct Plan {
        var order: GlassOrder
        var belt: Double?
        var band: Double
        /// Round 6: Rush tier (1…) this order was drawn for; 0 outside Rush.
        var tier: Int = 0
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
        /// Round 3: queued in the next-glass slot (sliding to it or standing there), not yet sent to the stop.
        var waiting: Bool
        /// Round 5 (QA-2 P2-1): seconds at the stop while playing with the flat gate open (drives "line fades").
        var lineClock: Double
        /// Round 5 (QA-2 P2-2): conveyor: seconds since the mouth passed the stream (waiting for drink inside it).
        var exitWait: Double
        /// Round 6: the Rush tier of its order (0 outside Rush).
        var tier: Int
        /// Round 7 (QA-3 P2-2): a belt glass whose successor stands still (Rush Conveyor → Diner): the next glass is
        /// sent when this one starts leaving, as between non-belt glasses, not at its serve.
        var sendNextOnLeave: Bool
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
    /// Round 6: a shift's venue (reported in every snapshot); nil for Rush, Daily and practice.
    private let shiftVenue: VenueID?

    // MARK: - State

    private var phase: SessionPhase = .intro
    private var time: Double = 0
    /// The flat gate (Duo only): no outflow, jug upright, patience paused, until the lid tilt reads flat
    /// (`Rules.readsFlat`: ≤ `Rules.flatGateTilt`, round 5).
    private var needsFlat: Bool = false
    private var usesFlatGate: Bool

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
    /// Round 5: the jug angle the hand asks for this sub-step (before the tip-back hold below).
    private var commandAngle: Double = 0
    /// Round 5 (founder decision 3): a shift jug ran dry mid-glass. It stays empty (fill 0, no stream, the glass is
    /// not judged by stopping) until the glass is served or the jug is tipped back below `dryRefillAngle` for
    /// `CoreTuning.jugDryTipBackTime`; then it is swapped for a refilled one.
    private var jugRanDry: Bool = false
    private var dryTipBack: Double = 0
    private var dryRefillAngle: Double = 0
    /// Round 5: after a refill swap that started with the hand tipped, the jug is held at this angle (just short of its
    /// pour point) until the hand has tipped back to it once, so a jug that arrives already tipped never gushes.
    /// nil = no hold.
    private var tipBackLimit: Double? = nil
    /// Round 6 (`JugState.reposeProgress`): the jug fill the cached pour threshold below was computed for (NaN = never).
    private var reposeCacheFill: Double = Double.nan
    private var reposeCacheThreshold: Double = 0

    // Hot-path caches (round 4, QA P2-8; results are identical, only repeated work and allocations are skipped)
    /// The angle `lipX/lipY/exitDX/exitDY` were last computed for (NaN = never).
    private var jugFrameAngle: Double = Double.nan
    /// `JugGeometry.head` is pure in (geometry angle, fill): reused while neither changes (a held or idle jug).
    private var headCacheAngle: Double = Double.nan
    private var headCacheFill: Double = Double.nan
    private var headCacheValue: Double = 0
    /// Reused buffer for the rotated jug outline inside `JugGeometry.head`.
    private var jugScratch: [CGPoint] = []

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
    /// Plans generated (or taken from the fixed list) but not yet placed, oldest first.
    private var peekedPlans: [Plan] = []
    private var idleTime: Double = 0
    /// Round 6: Rush: the tier (1…) of the glass last sent to the stop; 0 outside Rush (`GameSnapshot.rushTier`).
    private var rushTierNow: Int = 0
    /// Set by `requireFlat()` (seconds spent flat since): no judgement by stopping until the player pours again.
    private var resumeHold: Double? = nil
    /// Round 7 (QA-3 P2-7): how long `resumeHold` lasts: `resumeServeIdle` after a resume, `dryRefillServeHold` after
    /// a dry jug's refill.
    private var resumeHoldLimit: Double = CoreTuning.resumeServeIdle
    /// Round 7 (QA-3 P2-7): the jug ran dry over a glass that is already a hit and was laid back: it is served as it
    /// stands (no refill for it; the next glass brings the refill).
    private var dryServeNow: Bool = false
    /// Round 7 (QA-3 P2-3): Rush's next drink, waiting for the stream to stop (and land) before the jug takes it.
    private var pendingRushLiquid: Liquid? = nil

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
        var venue: VenueID? = nil
        switch mode {
        case .shift(let id):
            let level: Level = LevelCatalog.level(id) ?? LevelCatalog.levels[0]
            let belt: Double? = level.conveyorSpeed.map { (s: Double) -> Double in s * CoreTuning.beltScale }
            for o in level.orders {
                plans.append(Plan(order: o, belt: belt, band: level.perfectBand))
            }
            start = CoreMath.clamp(level.jugFill, 0.05, 1.0)
            fixedCount = plans.count
            venue = level.venue
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
        self.shiftVenue = venue
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
        if needsFlat && frameDt > 0 && Rules.readsFlat(lidTilt: lidTilt) && phase != .finished {
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
        // Rush: the jug takes the next glass's drink once the stream has stopped and landed (round 7, QA-3 P2-3).
        if let next = pendingRushLiquid, outflow <= 0 && particles.isEmpty {
            jugLiquid = next
            pendingRushLiquid = nil
        }

        commandAngle = angle
        var shown: Double = angle
        if let limit = tipBackLimit {
            if swapTimer <= 0 && angle <= limit {
                tipBackLimit = nil
            } else {
                shown = min(angle, limit)
            }
        }
        jugAngle = shown
        updateJugFrame(angle: shown)
        updateOutflow(h, events: &events)
        updateResumeHold(h)
        updatePourEdges(h, events: &events)
        integrateParticles(h, events: &events)
        integrateSprays(h)
        updateGlasses(h, events: &events)
        updatePuddles(h)
        checkJugEmpty(h, events: &events)

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

    /// World pivot for this angle (lifted so the jug clears the crease; higher at rest so its walls clear the fold).
    private func anchor(forAngle angle: Double) -> CGPoint {
        let base: CGPoint = baseAnchor()
        let rest: Double = CoreMath.clamp(1 - angle / max(0.001, CoreTuning.jugRestBlendAngle), 0, 1)
        let clearance: Double = CoreTuning.jugClearance + (CoreTuning.jugRestClearance - CoreTuning.jugClearance) * rest
        let floorY: CGFloat = layout.creaseMaxY + CGFloat(clearance)
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
        // Pure in the angle (the jug and the layout never change): skip the work while the angle holds (QA P2-8).
        if angle == jugFrameAngle { return }
        jugFrameAngle = angle
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

    /// Head above the lip for the current angle and fill (cached; see `headCacheAngle`).
    private func currentHead() -> Double {
        let ga: Double = geometryAngle(jugAngle)
        if ga == headCacheAngle && jugFill == headCacheFill { return headCacheValue }
        let value: Double = Double(JugGeometry.head(jug, angle: ga, fill: jugFill, scratch: &jugScratch))
        headCacheAngle = ga
        headCacheFill = jugFill
        headCacheValue = value
        return value
    }

    private func updateOutflow(_ h: Double, events: inout [GameEvent]) {
        let canPour: Bool = phase == .playing && swapTimer <= 0 && jugFill > 0 && !needsFlat && tipBackLimit == nil
        var target: Double = 0
        var deliverable: Bool = false
        if canPour {
            let head: Double = currentHead()
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
            // Round 7 (QA-3 P1-3): pouring starts the run (the intro card's "Pour to start").
            isStartHeld = false
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

    private func checkJugEmpty(_ h: Double, events: inout [GameEvent]) {
        if phase != .playing { return }
        if isRush {
            if jugFill >= CoreTuning.jugEmptyFill { return }
            if jugDry || pendingFinish != nil { return }
            if outflow > 0 || !particles.isEmpty { return }
            // Something to serve still? Then the normal serve rule judges it first (a Perfect may refill the jug).
            for g in glasses {
                if g.phase == .arriving && !g.waiting { return }
                if g.phase == .filling && g.pouredIn >= CoreTuning.minServeVolume { return }
            }
            jugDry = true
            events.append(.jugEmpty)
            pendingFinish = CoreTuning.finishDelay
            return
        }
        // Shifts / Daily (round 5, founder decision 3): never refill mid-pour.
        if jugRanDry {
            if swapTimer > 0 || pendingFinish != nil || dryServeNow { return }
            dryTipBack = commandAngle < dryRefillAngle ? dryTipBack + h : 0
            if dryTipBack >= CoreTuning.jugDryTipBackTime {
                if let gi = activeGlassIndex(), dryGlassIsAHit(gi) {
                    // Round 7 (QA-3 P2-7): already a hit: laying back is "done". No refill for it (the next glass
                    // brings one, so a change of drink stays one swap): lock-in now, the verdict `serveIdle` later.
                    dryServeNow = true
                    idleTime = 0
                } else {
                    refillDryJug(events: &events)
                    // The glass under the spout waits briefly for the player to pour again (the swap), so tipping back
                    // for a fresh jug doesn't get it judged as it stands; then lock-in and the verdict `serveIdle`
                    // later (round 7, QA-3 P2-7: was the full `resumeServeIdle`, ~5 s of dead air).
                    if activeGlassIndex() != nil {
                        resumeHold = 0
                        resumeHoldLimit = CoreTuning.dryRefillServeHold
                    }
                }
            }
            return
        }
        if jugFill >= CoreTuning.jugEmptyFill || swapTimer > 0 { return }
        // Ran dry (only happens while pouring): the stream stops at the lip and the jug shows empty (fill 0).
        jugRanDry = true
        dryServeNow = false
        jugFill = 0
        outflow = 0
        sandFlowing = false
        avalanche = 0
        dryTipBack = 0
        dryRefillAngle = pourHoldAngle(liquid: jugLiquid, fill: refillFill())
        // No event: `.jugEmpty` stays Rush's run-end. Feedback / Scene read the dry jug from the snapshot
        // (`jug.fill == 0` while tipped: the glug-out cue, the empty-jug look).
    }

    /// The fill a shift jug is refilled to.
    private func refillFill() -> Double {
        return max(startFill, 0.5)
    }

    /// Just short of the jug angle at which a jug of this drink and fill starts to pour.
    private func pourHoldAngle(liquid: Liquid, fill: Double) -> Double {
        let threshold: Double = JugGeometry.pourThreshold(jug, fill: CoreMath.clamp(fill, 0.02, 1))
        return max(0, threshold + liquid.reposeDegrees - CoreTuning.tipBackHoldMargin)
    }

    /// A swap to a refilled jug: like any swap, plus the tip-back hold if the hand is already tipped past the new
    /// jug's pour point (it would otherwise arrive pouring and gush). A hand that starts tipping during the swap pours
    /// as usual once it is done.
    private func beginRefill(to liquid: Liquid, fill: Double, events: inout [GameEvent]) {
        beginSwap(to: liquid, fill: fill, events: &events)
        let limit: Double = pourHoldAngle(liquid: liquid, fill: fill)
        tipBackLimit = commandAngle > limit ? limit : nil
    }

    /// Round 7 (QA-3 P2-7): would glass `gi` be a hit if it were judged as it stands (and can it be served by
    /// stopping)?
    private func dryGlassIsAHit(_ gi: Int) -> Bool {
        let g: Glass = glasses[gi]
        if g.pouredIn < CoreTuning.minServeVolume { return false }
        let j: Judgement = Rules.judge(top: CGFloat(judgedTop(g)), line: CGFloat(g.order.line * g.interior),
                                       interior: CGFloat(g.interior), overflowed: g.overflowed, perfectBand: g.band)
        return j.isHit
    }

    private func refillDryJug(events: inout [GameEvent]) {
        jugRanDry = false
        dryTipBack = 0
        let refill: Double = refillFill()
        jugFills[jugLiquid.id] = refill
        beginRefill(to: jugLiquid, fill: refill, events: &events)
    }

    /// Would a jug at `fill` run short of the drink glass `gi` needs to its line (with the margin)? Only when a
    /// refill would actually hold more.
    private func jugShort(_ fill: Double, forGlass gi: Int) -> Bool {
        let refill: Double = refillFill()
        if fill >= refill { return false }
        let g: Glass = glasses[gi]
        let lineVolume: Double = Double(GlassMath.volume(g.shape, upTo: CGFloat(g.order.line * g.interior)))
        let need: Double = max(0, lineVolume - g.volume)
        return fill * jugVolume < need * CoreTuning.jugRefillMargin
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
        // Compacted in place (round 4, QA P2-8: no new array per sub-step). Nothing below adds or removes particles,
        // so reading slot `r` and writing slot `w ≤ r` keeps the order and the survivors exactly as before.
        let n: Int = particles.count
        var w: Int = 0
        var r: Int = 0
        while r < n {
            var p: Particle = particles[r]
            r += 1
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
                                           volume: p.volume, flow: p.flow, isDrop: p.isDrop, y: ry, owner: glass.id,
                                           events: &events)
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
                               owner: spillOwner(atX: p.x), events: &events)
                continue
            } else if p.x < -80 || p.x > Double(layout.size.width) + 80 {
                continue
            }
            particles[w] = p
            w += 1
        }
        if w < n { particles.removeLast(n - w) }
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
                                owner: Int, events: inout [GameEvent]) {
        if isDrop || time - lastCounterLanding > CoreTuning.splashEdgeGap {
            let strength: Double = isDrop ? 0.2 : CoreMath.clamp(0.2 + 0.8 * flow.squareRoot(), 0, 1)
            events.append(.splashOnCounter(x: CGFloat(x), strength: strength))
        }
        addSpill(x: footX, volume: volume, owner: owner)
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
        // Compacted in place, like the particles (nothing below adds sprays).
        let n: Int = sprays.count
        var w: Int = 0
        var r: Int = 0
        while r < n {
            var s: Spray = sprays[r]
            r += 1
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
            sprays[w] = s
            w += 1
        }
        if w < n { sprays.removeLast(n - w) }
    }

    // MARK: - Puddles

    private func puddleRadius(_ volume: Double) -> Double {
        return CoreMath.clamp(CoreTuning.puddleBaseRadius + CoreTuning.puddleRadiusPerSqrtVolume * max(0, volume).squareRoot(),
                              CoreTuning.puddleBaseRadius, CoreTuning.puddleMaxRadius)
    }

    /// Drawn radius: the full radius while its glass is here, shrinking to 0 over `puddleDryTime` once it dries.
    private func puddleDrawRadius(_ p: Puddle) -> Double {
        let r: Double = puddleRadius(p.volume)
        guard let age = p.dryAge else { return r }
        let u: Double = CoreMath.clamp(age / max(0.01, CoreTuning.puddleDryTime), 0, 1)
        return r * (1 - u * u)
    }

    /// Whose spill is this: the nearest glass on the counter (not one waiting in the slot), or -1.
    private func spillOwner(atX x: Double) -> Int {
        var owner: Int = -1
        var best: Double = Double.greatestFiniteMagnitude
        for g in glasses where !g.waiting {
            let d: Double = abs(g.x - x)
            if d < best {
                best = d
                owner = g.id
            }
        }
        return owner
    }

    /// The glass still stands on the counter (not leaving, not gone).
    private func ownerPresent(_ id: Int) -> Bool {
        if id < 0 { return false }
        guard let gi = glassIndex(id: id) else { return false }
        return glasses[gi].phase != .leaving
    }

    /// Drying: a puddle starts drying when its glass leaves and is gone `puddleDryTime` later.
    private func updatePuddles(_ h: Double) {
        if puddles.isEmpty { return }
        var i: Int = 0
        while i < puddles.count {
            if let age = puddles[i].dryAge {
                puddles[i].dryAge = age + h
            } else if !ownerPresent(puddles[i].owner) {
                puddles[i].dryAge = 0
            }
            i += 1
        }
        puddles.removeAll(where: { (p: Puddle) -> Bool in (p.dryAge ?? 0) >= CoreTuning.puddleDryTime })
    }

    /// Pools `volume` of spilt drink at counter x (joins a nearby puddle of the same glass or starts one).
    private func addSpill(x: Double, volume: Double, owner: Int) {
        if volume <= 0 { return }
        var best: Int = -1
        var bestD: Double = Double.greatestFiniteMagnitude
        var i: Int = 0
        while i < puddles.count {
            let d: Double = abs(puddles[i].x - x)
            if puddles[i].owner == owner && d < puddleRadius(puddles[i].volume) + CoreTuning.puddleJoinMargin
                && d < bestD {
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
            // A spill from a glass that is already leaving (or from no glass) dries from the start.
            let dry: Double? = ownerPresent(owner) ? nil : 0
            puddles.append(Puddle(x: x, volume: volume, owner: owner, dryAge: dry))
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
        let half: Double = max(0, puddleDrawRadius(p) - CoreTuning.puddlePointInset)
        return 1 + Int((2 * half / CoreTuning.puddlePointSpacing).rounded(.down))
    }

    private func puddlePointCount() -> Int {
        var n: Int = 0
        for p in puddles { n += puddlePoints(p) }
        return n
    }

    /// Snapshot encoding: each puddle → a run of points `puddlePointSpacing` apart along the counter line, centred on
    /// the puddle and spanning ± (drawn radius − inset). A drying puddle's run shrinks to one point, then vanishes.
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
        addSpill(x: glasses[gi].x, volume: excess, owner: glasses[gi].id)
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
                glasses[i].x = CoreMath.lerp(glasses[i].startX, glasses[i].arriveX, CoreMath.easeOutCubic(u))
                if u >= 1 {
                    glasses[i].x = glasses[i].arriveX
                    if glasses[i].waiting {
                        // Standing in the next-glass slot until the one at the stop leaves.
                        glasses[i].phaseTime = CoreTuning.arriveDuration
                    } else {
                        glasses[i].phase = .filling
                        glasses[i].phaseTime = 0
                        glasses[i].arrivedAt = time
                        events.append(.glassArrived(glassID: glasses[i].id))
                        spawnWaitingGlass()
                    }
                }
            case .filling:
                // The belt waits behind the flat gate, like patience does.
                // Round 5 (QA-2 P2-3): nor during the intro (nothing can pour yet). Round 7 (QA-3 P1-3): nor behind
                // the App's start hold (a venue intro card).
                if let belt = glasses[i].belt, !clocksHeld, phase != .intro { glasses[i].x += belt * h }
                updateFilling(i, h, events: &events)
            case .served:
                if let belt = glasses[i].belt { glasses[i].x += belt * h }
                let streamBusy: Bool = glasses[i].belt == nil && (outflow > 0 || !particles.isEmpty)
                let waited: Bool = glasses[i].phaseTime >= CoreTuning.resultHold + CoreTuning.changeoverWaitMax
                if glasses[i].phaseTime >= CoreTuning.resultHold && (!streamBusy || waited) {
                    glasses[i].phase = .leaving
                    glasses[i].phaseTime = 0
                    glasses[i].startX = glasses[i].x
                    if glasses[i].belt == nil || glasses[i].sendNextOnLeave {
                        glasses[i].sendNextOnLeave = false
                        advanceQueue(events: &events)
                    }
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
        // Line fade ("line fades" orders): reveal again once served. Round 5 (QA-2 P2-1): its clock runs only while
        // playing with the flat gate open, like patience, so the line can't fade before the player can pour.
        if phase == .playing && !clocksHeld { glasses[i].lineClock += h }
        if let fade = glasses[i].order.lineFadesAfter {
            let t: Double = glasses[i].lineClock - fade
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
        if !glasses[i].lockSent && !servingHeld && idleTime > 0 && glasses[i].pouredIn >= CoreTuning.minServeVolume
            && settled && inBand {
            glasses[i].lockSent = true
            events.append(.lockedIn(glassID: glasses[i].id))
        }

        if glasses[i].belt != nil {
            // Conveyor: judged once the mouth has passed the stream and the drink already inside it has landed
            // (round 5, QA-2 P2-2; waits at most `conveyorInsideWaitMax`).
            if glasses[i].x - glasses[i].rimHalf > glasses[i].landingX + CoreTuning.conveyorExitMargin {
                glasses[i].exitWait += h
                if !hasDrinkInside(glasses[i].id) || glasses[i].exitWait >= CoreTuning.conveyorInsideWaitMax {
                    serve(i, events: &events)
                }
            }
            return
        }

        if let p = glasses[i].patienceLeft, !clocksHeld {
            let left: Double = p - h
            glasses[i].patienceLeft = max(0, left)
            if left <= 0 {
                serve(i, events: &events)
                return
            }
        }

        // Paused mid-pour (or behind the flat gate): no verdict by stopping until the player pours again.
        if servingHeld { return }

        if glasses[i].pouredIn >= CoreTuning.minServeVolume && idleTime >= CoreTuning.serveIdle {
            if settled || idleTime >= CoreTuning.serveIdle + CoreTuning.foamServeGrace {
                serve(i, events: &events)
            }
        }
    }

    /// Stream particles that have fallen through this glass's mouth and not landed yet.
    private func hasDrinkInside(_ id: Int) -> Bool {
        for p in particles where p.glassID == id { return true }
        return false
    }

    /// The top a glass is judged at: the liquid plus at most a settled head (`foamSettledFraction` of the interior).
    /// Serving waits for the head to settle (cap 3 s of idle), so this is the visible top except when the cap hits
    /// (round 5, founder decision 4).
    private func judgedTop(_ g: Glass) -> Double {
        let liquidTop: Double = Double(GlassMath.height(g.shape, forVolume: CGFloat(g.volume)))
        return min(visibleTop(g), liquidTop + CoreTuning.foamSettledFraction * g.interior)
    }

    private func serve(_ i: Int, events: inout [GameEvent]) {
        let interior: Double = glasses[i].interior
        let top: Double = judgedTop(glasses[i])
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
        case .short, .over, .spill:
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

        // Strikes: shifts and daily count spills, overs and shorts; practice never. Round 6 (founder, BALANCE.md §7):
        // Rush counts only real rim spills; an over or a short breaks the streak but doesn't strike.
        // Note (QA-2 P2-4; Rush stays endless by design): a Rush patience timeout is judged on what is in the glass —
        // usually `.short`, which doesn't strike in Rush — so an idle Rush never ends by itself. Banking the score on
        // quit is the App's job.
        var strike: Bool = false
        if !isPractice {
            if isRush {
                strike = j == .spill
            } else {
                strike = j == .spill || j == .over || j == .short
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

        // Round 5 (decision 3): a jug that ran dry during this glass is swapped between glasses, when the next one is
        // sent to the stop (`sendToStop`: at once on a conveyor, as this one leaves otherwise), so a change of drink
        // is one swap, not two.

        // Conveyor glasses ride on; the next one is sent down the belt straight away. Round 7 (QA-3 P2-2): unless the
        // next glass stands still (Rush's Conveyor → Diner tier change): it would slide in on top of this one while it
        // still rides, so it is sent as this one starts leaving, like any non-belt changeover.
        if glasses[i].belt != nil {
            if pendingFinish == nil && phase != .finished && nextGlassLeavesTheBelt() {
                glasses[i].sendNextOnLeave = true
            } else {
                advanceQueue(events: &events)
            }
        }
    }

    /// Round 7 (QA-3 P2-2): is the glass after the current one a non-belt glass (the waiting one's, else the next
    /// plan's, peeked without consuming it)?
    private func nextGlassLeavesTheBelt() -> Bool {
        if isRush && jugDry { return false }
        if let wi = waitingIndex() { return glasses[wi].belt == nil }
        guard let p = peekPlan() else { return false }
        return p.belt == nil
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

    /// The next plan without consuming it (Rush/practice generate it now and keep it).
    private func peekPlan() -> Plan? {
        if let p = peekedPlans.first { return p }
        guard let p = nextPlan() else { return nil }
        peekedPlans.append(p)
        return p
    }

    private func takePlan() -> Plan? {
        if !peekedPlans.isEmpty { return peekedPlans.removeFirst() }
        return nextPlan()
    }

    /// Round 8: Rush keeps its next `upcomingDepth` plans generated, so `upcomingOrders` knows them in every tier (no
    /// slot glass on the Conveyor). Called only where a plan is consumed (a glass placed), at fixed points of the
    /// simulation, never from a getter: the RNG sequence depends on the seed and inputs alone. Plans are generated in
    /// the same order and with the same index (`generated`, which sets the tier) as before; only earlier.
    private func topUpRushPeek() {
        if !isRush { return }
        while peekedPlans.count < GameSession.upcomingDepth {
            guard let p = nextPlan() else { return }
            peekedPlans.append(p)
        }
    }

    private func waitingIndex() -> Int? {
        var i: Int = 0
        while i < glasses.count {
            if glasses[i].waiting { return i }
            i += 1
        }
        return nil
    }

    /// Sends the next glass to the stop under the spout: the one waiting in the slot if there is one (and refills
    /// the slot), else a fresh one from the left edge.
    private func advanceQueue(events: inout [GameEvent]) {
        if phase == .finished || pendingFinish != nil { return }
        if isRush && jugDry { return }
        if let wi = waitingIndex() {
            sendToStop(wi, initial: false, events: &events)
            spawnWaitingGlass()
            return
        }
        spawnNextGlass(events: &events, initial: false)
    }

    /// A glass for this plan at the left edge (not placed yet).
    private func makeGlass(_ plan: Plan) -> Glass {
        let shape: GlassShape = GlassCatalog.shape(plan.order.glass)
        let liquid: Liquid = LiquidCatalog.liquid(plan.order.liquid)
        let interior: Double = Double(shape.interiorHeight)
        let prefill: Double = CoreMath.clamp(plan.order.prefill, 0, 0.95)
        let preVolume: Double = Double(GlassMath.volume(shape, upTo: CGFloat(prefill * interior)))
        let g: Glass = Glass(id: nextGlassID, order: plan.order, shape: shape, liquid: liquid, belt: plan.belt,
                             band: plan.band, capacity: Double(GlassMath.capacity(shape)), interior: interior,
                             rimHalf: Double(shape.rimHalfWidth), wall: Double(shape.wall),
                             floorY: Double(layout.counterY + shape.baseThickness), landingX: CoreTuning.arriveFromX,
                             arriveX: CoreTuning.arriveFromX, x: CoreTuning.arriveFromX, startX: CoreTuning.arriveFromX,
                             phase: .arriving, phaseTime: 0, volume: preVolume, foam: 0, pouredIn: 0,
                             patienceLeft: plan.belt == nil ? plan.order.patience : nil,
                             arrivedAt: nil, overflowed: false, result: nil, inBand: false, nearingSent: false,
                             lastLanding: -10, lineOpacity: 1, lockSent: false, waiting: false, lineClock: 0,
                             exitWait: 0, tier: plan.tier, sendNextOnLeave: false)
        nextGlassID += 1
        return g
    }

    /// Fills the next-glass slot (shifts, daily, Rush; not practice, not conveyors) if it is empty.
    private func spawnWaitingGlass() {
        if isPractice || phase == .finished || pendingFinish != nil { return }
        if isRush && jugDry { return }
        if waitingIndex() != nil { return }
        // No slot while a belt glass is on the counter: it rides in through the slot and along the belt.
        var stopIndex: Int? = nil
        var i: Int = 0
        while i < glasses.count {
            let g: Glass = glasses[i]
            if g.phase != .leaving && g.belt != nil { return }
            if (g.phase == .arriving || g.phase == .filling) && !g.waiting { stopIndex = i }
            i += 1
        }
        guard let plan = peekPlan(), plan.belt == nil else { return }
        // Round 4 (REVIEW-3 P1-4): the slot keeps `nextGlassEdgeMargin` from the visible edge to the COASTER's edge, at
        // the waiting glass's drawn scale. If it can't (narrow phones, wide glasses) there is no waiting glass: the
        // plan stays peeked and the glass slides in from the left edge when its turn comes (pre-round-3 behaviour).
        var stop: (x: Double, shape: GlassShape)? = nil
        if let si = stopIndex { stop = (x: glasses[si].arriveX, shape: glasses[si].shape) }
        let shape: GlassShape = GlassCatalog.shape(plan.order.glass)
        guard let x = NextGlassSlot.x(for: shape, layout: layout, stop: stop) else { return }
        peekedPlans.removeFirst()
        var g: Glass = makeGlass(plan)
        g.waiting = true
        g.arriveX = x
        g.lineOpacity = 0
        glasses.append(g)
        topUpRushPeek()
    }

    private func spawnNextGlass(events: inout [GameEvent], initial: Bool) {
        if phase == .finished || pendingFinish != nil { return }
        if isRush && jugDry { return }
        guard let plan = takePlan() else { return }
        glasses.append(makeGlass(plan))
        sendToStop(glasses.count - 1, initial: initial, events: &events)
        topUpRushPeek()
    }

    /// Decides the jug for this glass's drink and slides it from where it stands to its stop under the spout.
    private func sendToStop(_ gi: Int, initial: Bool, events: inout [GameEvent]) {
        let liquid: Liquid = glasses[gi].liquid
        let rimHalf: Double = glasses[gi].rimHalf
        let floorY: Double = glasses[gi].floorY
        let interior: Double = glasses[gi].interior

        // The jug for this drink (decided first: the glass is placed for the fill it will be poured from).
        if initial {
            jugLiquid = liquid
            jugFill = startFill
            jugFills[liquid.id] = startFill
        } else if isRush {
            // One big shared jug. Round 7 (QA-3 P2-3): a belt serve sends the next glass mid-pour, so the change of
            // drink waits until the stream has stopped and landed (`substep`); the stream never changes colour or body
            // under the player's hand.
            if outflow > 0 || !particles.isEmpty {
                pendingRushLiquid = liquid
            } else {
                jugLiquid = liquid
                pendingRushLiquid = nil
            }
        } else {
            // Round 5 (decision 3): refills happen here, between glasses — a jug that ran dry, or one that would run
            // short of this glass's drink.
            let current: Liquid = pendingLiquid ?? jugLiquid
            let currentFill: Double = pendingLiquid != nil ? pendingFill : jugFill
            if current.id != liquid.id {
                jugFills[current.id] = currentFill
                jugRanDry = false
                let stored: Double = jugFills[liquid.id] ?? startFill
                if jugShort(stored, forGlass: gi) {
                    let refill: Double = refillFill()
                    jugFills[liquid.id] = refill
                    beginRefill(to: liquid, fill: refill, events: &events)
                } else {
                    beginSwap(to: liquid, fill: stored, events: &events)
                }
            } else if jugRanDry || jugShort(currentFill, forGlass: gi) {
                jugRanDry = false
                let refill: Double = max(currentFill, refillFill())
                jugFills[liquid.id] = refill
                beginRefill(to: liquid, fill: refill, events: &events)
            }
        }
        let pourFill: Double = pendingLiquid != nil ? pendingFill : jugFill

        let landing: Double = referenceLandingX(rimY: floorY + interior, liquid: liquid, fill: pourFill)
        var arriveX: Double = landing
        if let belt = glasses[gi].belt {
            let leadIn: Double = CoreMath.clamp(belt * 0.9, 10, CoreTuning.conveyorLeadIn)
            arriveX = landing - rimHalf - leadIn
        }
        glasses[gi].landingX = landing
        glasses[gi].arriveX = arriveX
        glasses[gi].startX = glasses[gi].x
        glasses[gi].phase = .arriving
        glasses[gi].phaseTime = 0
        glasses[gi].waiting = false
        glasses[gi].lineOpacity = 1
        // Round 6: Rush changes room as the first glass of a new tier slides to the stop (the one before is leaving).
        if isRush { rushTierNow = max(1, glasses[gi].tier) }
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

    /// Rush: a tier every `CoreTuning.rushTierEvery` (12) glasses (`GameSnapshot.rushTier` 1…). Round 6 (REVIEW-5 §5, founder decision 2): Rush
    /// travels: tier t is served in `Rules.rushVenue(tier:)` from that venue's menu (`rushMenu`). Every Conveyor
    /// glass rides a belt and no other does (so a belt glass never glides across a counter). Across tiers patience
    /// shrinks, the Perfect band narrows and, from tier 5, prefilled curveballs mix in. Foamy drinks keep their lines
    /// under the head's comfort zone (as the Daily does), belt lines stay in the campaign's 0.4–0.65.
    private func makeRushPlan(_ n: Int) -> Plan {
        let step: Int = max(0, n / CoreTuning.rushTierEvery)     // 0-based difficulty step
        let tier: Int = step + 1
        let venue: VenueID = Rules.rushVenue(tier: tier)
        let menu: (liquids: [LiquidID], glasses: [String]) = GameSession.rushMenu(venue)
        let liquid: LiquidID = rng.pick(GameSession.rushLiquidPool(venue, step: step))
        let glass: String = rng.pick(menu.glasses)
        let drink: Liquid = LiquidCatalog.liquid(liquid)
        let onBelt: Bool = venue == .conveyor
        var line: Double
        if onBelt {
            line = rng.range(0.4, 0.65)
        } else {
            line = rng.range(0.45, step >= 2 ? 0.9 : 0.85)
            let headCap: Double = drink.foamPerVolume > 1.0 ? 0.68 : (drink.foamPerVolume > 0.3 ? 0.8 : 0.95)
            line = min(line, headCap)
            if venue == .sodaFountain {
                // Round 8 (REVIEW-6 N1): Fizz lines ≤ 0.70, lower for bigger heads (cola 0.65, root beer 0.61).
                let foamOver: Double = max(0, drink.foamPerVolume - 0.4)
                line = min(line, CoreTuning.rushFizzLineCap - CoreTuning.rushFizzLineCapPerFoam * foamOver)
            }
        }
        line = round2(line)
        let shape: GlassShape = GlassCatalog.shape(glass)
        let needed: Double = Double(GlassMath.volume(shape, upTo: shape.interiorHeight * CGFloat(line)))
        let sizeFactor: Double = CoreMath.clamp((needed / CoreTuning.rushPatienceVolumeRef).squareRoot(), 0.8, 1.5)
        let viscosity: Double = 1 + drink.lagTau
        let fizzBonus: Double = venue == .sodaFountain ? CoreTuning.rushFizzPatienceBonus : 0
        var patience: Double? = max(5.0, 9.5 - 0.7 * Double(step)) * sizeFactor * viscosity + fizzBonus
        var belt: Double? = nil
        if onBelt {
            belt = min(40, 18 + 4 * Double(max(0, step - 2))) * CoreTuning.beltScale
            patience = nil
        }
        var prefill: Double = 0
        if !onBelt && step >= 4 && line >= 0.6 && rng.chance(0.15) { prefill = 0.2 }
        let band: Double = max(0.018, 0.03 - 0.002 * Double(step))
        let order: GlassOrder = GlassOrder(glass: glass, liquid: liquid, line: line, patience: patience,
                                           lineFadesAfter: nil, prefill: prefill)
        return Plan(order: order, belt: belt, band: band, tier: tier)
    }

    /// Round 8 (REVIEW-6 N1, BALANCE.md §10): the weighted drink pool a Rush tier draws from (one `pick`, as before;
    /// always drinks of `rushMenu(venue)`). The Fizz tiers lean on cream soda, the smallest head: the first visit
    /// (tier 2) pours cream soda 4 : 1 cola and no root beer, which the model casual spilled 40 % of the time even at
    /// 0.6 lines; later visits (tiers 6, 10, …: experts) bring root beer back, 3 : 1 : 1. Other venues: their menu.
    static func rushLiquidPool(_ venue: VenueID, step: Int) -> [LiquidID] {
        if venue == .sodaFountain {
            if step <= 1 { return [.creamSoda, .creamSoda, .creamSoda, .creamSoda, .cola] }
            return [.creamSoda, .creamSoda, .creamSoda, .cola, .rootBeer]
        }
        return rushMenu(venue).liquids
    }

    /// Round 6: what a Rush tier in this venue serves (drinks and glasses, drawn independently). Tier 1's Lemonade
    /// Stand is the old first tier exactly. The Sand Bar is never a Rush venue (its menu is here for completeness).
    static func rushMenu(_ venue: VenueID) -> (liquids: [LiquidID], glasses: [String]) {
        switch venue {
        case .lemonadeStand:
            return (liquids: [.water, .lemonade, .orangeJuice], glasses: ["tumbler", "highball", "pint", "jar"])
        case .sodaFountain:
            return (liquids: [.cola, .creamSoda, .rootBeer], glasses: ["tumbler", "highball", "pint", "mug", "flute", "jar"])
        case .conveyor:
            return (liquids: [.water, .lemonade, .orangeJuice, .cola, .creamSoda],
                    glasses: ["tumbler", "mug", "bowl", "sundae", "shot"])
        case .milkshakeDiner:
            return (liquids: [.milkshake, .berrySmoothie, .honey, .mapleSyrup],
                    glasses: ["tumbler", "highball", "sundae", "bowl", "jar", "mug", "shot"])
        case .potionShop:
            return (liquids: [.potionBlue, .potionPink], glasses: ["beaker", "vial", "flute", "shot"])
        case .sandBar:
            return (liquids: [.sand], glasses: ["hourglass", "jar", "beaker", "vial", "shot"])
        }
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
            // Round 5: serving waits for the head to settle and judges at most a settled head (`judgedTop`).
            let liquidTopFinal: Double = Double(GlassMath.height(g.shape, forVolume: CGFloat(liquidFinal)))
            let settledTop: Double = min(interior, liquidTopFinal + CoreTuning.foamSettledFraction * interior)
            let settledFoamVolume: Double = max(0, Double(GlassMath.volume(g.shape, upTo: CGFloat(settledTop))) - liquidFinal)
            foamFinal = min(early, settledFoamVolume)
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
        pts.reserveCapacity(particles.count + 1)
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
        out.reserveCapacity(sprays.count + 8)
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
        var state: JugState = JugState(liquid: jugLiquid, angle: jugAngle, fill: jugFill, outline: outline,
                                       liquidPolygon: liquid, lip: lip, pivot: a, flow: flowNorm)
        state.reposeProgress = currentReposeProgress()
        return state
    }

    /// Round 6 (REVIEW-5 §4, `JugState.reposeProgress`): sand only. A liquid at this fill would start to pour at the
    /// pour threshold T; sand holds for `reposeDegrees` more and slides at T + repose. Progress is 0 up to T, rises
    /// linearly to 1 at the slide, and stays 1 while the sand flows (until it is tipped back past the hysteresis).
    /// 0 for liquids, an empty or swapping jug, behind the flat gate and outside play.
    private func currentReposeProgress() -> Double {
        let repose: Double = jugLiquid.reposeDegrees
        if repose <= 0 { return 0 }
        if sandFlowing { return 1 }
        if phase != .playing || needsFlat || swapTimer > 0 || jugRanDry || jugFill < CoreTuning.jugEmptyFill { return 0 }
        // Pure in the fill, which doesn't change while the sand holds: recomputed only once the fill has moved.
        if !(abs(jugFill - reposeCacheFill) < 0.002) {
            reposeCacheThreshold = JugGeometry.pourThreshold(jug, fill: CoreMath.clamp(jugFill, 0.02, 1), step: 0.5)
            reposeCacheFill = jugFill
        }
        return CoreMath.clamp((jugAngle - reposeCacheThreshold) / repose, 0, 1)
    }

    private func makeGlassStates() -> [GlassState] {
        var out: [GlassState] = []
        out.reserveCapacity(glasses.count)
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
        // Round 6: shifts report their venue; Rush its tier and that tier's venue; Daily / practice leave it to the App.
        if isRush {
            s.rushTier = max(1, rushTierNow)
            s.venue = Rules.rushVenue(tier: s.rushTier)
        } else {
            s.venue = shiftVenue
        }
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
    /// an upright jug until the lid tilt has read flat once (`Rules.readsFlat`: 0…`Rules.flatGateTilt`, round 5).
    /// No-op on phones without a fold and in practice. `snapshot.needsFlat` turns true at once; `.flatArmed` fires when it opens again.
    ///
    /// Round 3 (pause mid-pour): it also holds the glass under the spout. Whatever is already in the air still lands,
    /// patience is frozen until the gate opens, and the glass is NOT judged by stopping (no `.lockedIn`, no serve)
    /// until the player pours again and stops — or, if they never pour, `CoreTuning.resumeServeIdle` s after the gate
    /// opened (so nobody is stuck). An overflow is still a live spill.
    func requireFlat() {
        if !usesFlatGate || phase == .finished { return }
        needsFlat = true
        resumeHold = 0
        resumeHoldLimit = CoreTuning.resumeServeIdle
        // The jug is upright behind the gate: the spout rope is cut now (it would otherwise read as a fresh pour).
        outflow = 0
        headlessTime = CoreTuning.ropeMaxTime
        snapshot.needsFlat = true
    }

    /// Round 4 (QA P1-3): the canvas changed mid-run (Duo tabletop ↔ the book-pose touch column, etc.). Keep the run:
    /// only what depends on the canvas follows it — `visibleRect` (where the next waiting glass stands) and `hasFold`
    /// (the flat gate, via `setUsesFlatGate`). The world itself (size, crease, counter, pivot) never changes.
    func adoptCanvas(_ newLayout: WorldLayout) {
        layout.visibleRect = newLayout.visibleRect
        layout.hasFold = newLayout.hasFold
        setUsesFlatGate(newLayout.hasFold)
    }

    /// Round 4 (QA P1-3): turn the flat gate on (a fold) or off (touch / no fold) without rebuilding the session.
    /// Turning it on doesn't close it by itself (the App's resume calls `requireFlat()` as usual); turning it off opens
    /// it at once. Never on in practice.
    func setUsesFlatGate(_ on: Bool) {
        usesFlatGate = on && !isPractice
        if !usesFlatGate && needsFlat {
            needsFlat = false
            snapshot.needsFlat = false
        }
    }

    /// Round 7 (QA-3 P1-3): hold the run while the App shows a venue intro card ("Pour to start"). While held, belts,
    /// patience and line-fade clocks stand still and nothing is judged by stopping, exactly as behind the flat gate,
    /// but the jug works: the first `.pourStarted` releases the hold by itself. The App sets it with the card and
    /// clears it when the card is dismissed. Ignored once the run has finished. Independent of the flat gate.
    func setStartHold(_ on: Bool) {
        if on && phase == .finished { return }
        isStartHeld = on
    }

    /// Belts, patience and line-fade clocks stand still (flat gate closed, or the App's start hold).
    private var clocksHeld: Bool {
        return needsFlat || isStartHeld
    }

    /// True while stopping must not judge the glass under the spout (gate closed, start hold, held after a resume, or
    /// the jug ran dry and hasn't been swapped yet, unless it is being served as it stands).
    private var servingHeld: Bool {
        return clocksHeld || resumeHold != nil || (jugRanDry && !dryServeNow)
    }

    private func updateResumeHold(_ h: Double) {
        guard let held = resumeHold else { return }
        if needsFlat { return }                 // the clock starts once the phone is flat again
        if outflow > 0 {
            resumeHold = nil                    // pouring again: the normal "stop to serve" rule takes over
        } else if held + h >= resumeHoldLimit {
            resumeHold = nil
            idleTime = 0                        // lock-in, then the verdict ~serveIdle later
        } else {
            resumeHold = held + h
        }
    }

    // MARK: - Test / debug hooks (internal; used by unit tests and demo scripts)

    /// Set the jug's fill (0…1). Tests use it to keep Rush going until the spill rule ends it.
    func debugSetJugFill(_ fill: Double) {
        jugFill = CoreMath.clamp(fill, 0, 1)
        if isRush { jugDry = false }
        if !isRush && jugFill >= CoreTuning.jugEmptyFill { jugRanDry = false }
    }
}

extension GlassState {
    /// Round 3: the next order, queued in the next-glass slot on the counter (sliding to it or standing at
    /// x ≈ `CoreTuning.nextGlassX`). Nothing is poured into it; it slides to the stop (its line appearing,
    /// `lineOpacity` 1) as the judged glass leaves. Encoded as `.arriving` with `lineOpacity` 0.
    var isWaitingInSlot: Bool {
        return phase == .arriving && lineOpacity <= 0
    }
}

/// Round 4 (REVIEW-3 P1-1, P1-4): the next-glass slot's geometry, shared by Core (placement) and Scene (drawing) so
/// the margin holds for what is actually drawn. All in world pt; "full size" = the glass as drawn at the stop.
///
/// Contract for Scene: draw the waiting glass at `scale(hasFold:)` (horizontally about its centre x) and its slot
/// coaster no wider than `coasterHalfWidth(_:)` each side (scaling it down too is fine). Then the slot's outermost
/// drawn edge is ≥ `CoreTuning.nextGlassEdgeMargin` (16) inside `visibleRect` on every canvas.
enum NextGlassSlot {
    /// Coaster outline stroke (Scene: 1.4 pt line) rounded up.
    static let coasterStroke: Double = 1
    /// The mug's handle reaches this far left of its wall at full size (Scene draws it on the left).
    static let mugHandleReach: Double = 30

    /// Drawn scale of the waiting glass.
    static func scale(hasFold: Bool) -> Double {
        return hasFold ? CoreTuning.nextGlassScaleFold : CoreTuning.nextGlassScalePhone
    }

    /// The glass body's outer half-width at full size (widest interior half-width + wall).
    static func bodyHalfWidth(_ s: GlassShape) -> Double {
        var w: CGFloat = 0
        for p in s.profile where p.x > w { w = p.x }
        return Double(w + max(2, s.wall))
    }

    /// Extra reach on the left at full size (the mug's handle).
    static func handleReach(_ s: GlassShape) -> Double {
        return s.style == .mug ? mugHandleReach : 0
    }

    /// Outer half-width of what the glass stands on at full size: the foot of a stemmed glass, else floor + wall
    /// (Scene's `SceneGlass.baseOuterHalfWidth`).
    static func footHalfWidth(_ s: GlassShape) -> Double {
        guard let first = s.profile.first, let last = s.profile.last else { return 20 }
        let f0: Double = Double(first.x + max(2, s.wall))
        let stemmed: Bool = (s.style == .flute || s.style == .sundae || s.style == .bowl) && s.baseThickness >= 20
        return stemmed ? max(f0 + 4, Double(last.x) * 0.62) : f0
    }

    /// The slot coaster's half-width at full size, stroke included (Scene's slot coaster: 120 pt wide ×
    /// clamp((foot × 2 + 40) / 120, 0.75…1.5)). Core assumes it is NOT scaled down with the glass (the safe side).
    static func coasterHalfWidth(_ s: GlassShape) -> Double {
        let k: Double = CoreMath.clamp((footHalfWidth(s) * 2 + 40) / 120, 0.75, 1.5)
        return 60 * k + coasterStroke
    }

    /// How far the slot reaches left of its x: the coaster, or the scaled glass with its handle if that is wider.
    static func leftReach(_ s: GlassShape, hasFold: Bool) -> Double {
        return max(coasterHalfWidth(s), (bodyHalfWidth(s) + handleReach(s)) * scale(hasFold: hasFold))
    }

    /// How far the scaled glass reaches right of the slot x (the gap to the glass at the stop is measured from it).
    static func rightReach(_ s: GlassShape, hasFold: Bool) -> Double {
        return bodyHalfWidth(s) * scale(hasFold: hasFold)
    }

    /// The slot x for a glass of `shape`: `CoreTuning.nextGlassX`, nudged right so its left reach keeps
    /// `nextGlassEdgeMargin` inside `visibleRect`, and left so its right reach keeps `nextGlassGap` from the glass at
    /// the stop (`stop`: its stop x and shape; full size, mug handle included). nil = it doesn't fit: no waiting glass.
    static func x(for shape: GlassShape, layout: WorldLayout, stop: (x: Double, shape: GlassShape)?) -> Double? {
        let fold: Bool = layout.hasFold
        let lo: Double = Double(layout.visibleRect.minX) + CoreTuning.nextGlassEdgeMargin + leftReach(shape, hasFold: fold)
        var x: Double = max(CoreTuning.nextGlassX, lo)
        if let st = stop {
            let stopLeft: Double = st.x - bodyHalfWidth(st.shape) - handleReach(st.shape)
            let hi: Double = stopLeft - CoreTuning.nextGlassGap - rightReach(shape, hasFold: fold)
            if hi < lo { return nil }
            x = min(x, hi)
        }
        return x
    }
}
