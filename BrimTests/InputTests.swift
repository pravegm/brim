import CoreGraphics
import Foundation
import Testing
@testable import Brim

// MARK: - Fixtures (memberwise initialisers of the Contracts types)

private func inputTestLiquid() -> Liquid {
    Liquid(id: .water, name: "Water", top: RGBA(0.6, 0.85, 1), bottom: RGBA(0.4, 0.65, 0.95), foam: nil,
           lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.5, fizzy: false)
}

private func inputTestGlass(id: Int = 1, phase: GlassPhase, overflowing: Bool = false,
                            result: Judgement? = nil) -> GlassState {
    let shape = GlassShape(id: "tumbler", name: "Tumbler", style: .tumbler,
                           profile: [CGPoint(x: 55, y: 0), CGPoint(x: 62, y: 120)], baseThickness: 8, wall: 3)
    return GlassState(id: id, shape: shape, liquid: inputTestLiquid(), x: 335, phase: phase, liquidHeight: 0,
                      foamHeight: 0, lineHeight: 96, lineOpacity: 1, inPerfectBand: false, overflowing: overflowing,
                      patienceLeft: nil, patienceTotal: nil, result: result)
}

private func inputTestSnapshot(glasses: [GlassState], flow: Double = 0, projected: Double = -0.8,
                               landing: Double? = nil, phase: SessionPhase = .playing,
                               jugFill: Double = 1) -> GameSnapshot {
    let liquid = inputTestLiquid()
    let jug = JugState(liquid: liquid, angle: 0, fill: jugFill, outline: [], liquidPolygon: [], lip: .zero, pivot: .zero,
                       flow: flow)
    let telemetry = PourTelemetry(flow: flow, landingRate: landing ?? flow, activeFill: 0.1, distanceToLine: projected,
                                  projectedDistanceToLine: projected, liquid: .water)
    return GameSnapshot(time: 0, phase: phase, mode: .practice, jug: jug, stream: [], droplets: [], glasses: glasses,
                        puddles: [], score: 0, streak: 0, multiplier: 1, strikes: 0, maxStrikes: 3, ordersDone: 0,
                        ordersTotal: nil, perfects: 0, telemetry: telemetry)
}

/// A toy bar for the autopilot (deliberately NOT Core's numbers, so the pilot can't be tuned to them): outflow follows
/// the lid tilt past a pour point, rising fast and falling with a lag the projection does not see; the stream falls
/// `fall` s; the projection counts what is airborne. Live spill judging, serve 0.35 s after the last drop, a 0.3 s hold
/// and a 0.45 s changeover. Heights are fractions of the interior; the line sits at 0.8 (96 of 120).
/// Round 5: an optional jug of `jugCapacity` glass heights that runs dry like Core's shift jug (fill 0, the stream
/// stops) and is swapped for a fresh one once the glass is judged or the jug has been tipped back for 0.4 s.
@MainActor
private final class ToyBar {
    let fillPerFlow: Double
    let fall: Double
    let decline: Double
    let armAfter: Double
    let line = 0.8
    let pourPoint = 12.0
    var time = 0.0
    var glassID = 1
    var volume = 0.0
    var air: [(land: Double, amount: Double)] = []
    var flow = 0.0
    var landing = 0.0
    var idle = 0.0
    var phase: GlassPhase = .arriving
    var phaseTime = 0.0
    var result: Judgement?
    var overflowing = false
    var armed: Bool
    var maxTiltWhileFlat = 0.0
    var finals: [(judgement: Judgement, distance: Double, glass: Int)] = []
    var overflowTimes: [Double] = []
    let jugCapacity: Double
    var jugLeft: Double
    var tippedBack = 0.0
    var dryTimes: [Double] = []
    var swapTimes: [Double] = []
    var dryGlasses = Set<Int>()
    var tiltLog: [(time: Double, tilt: Double)] = []

    init(fillPerFlow: Double = 0.55, fall: Double = 0.4, decline: Double = 0.12, armAfter: Double = 0,
         jugCapacity: Double = Double.infinity) {
        self.fillPerFlow = fillPerFlow
        self.fall = fall
        self.decline = decline
        self.armAfter = armAfter
        self.armed = armAfter <= 0
        self.jugCapacity = jugCapacity
        self.jugLeft = jugCapacity
    }

    var snapshot: GameSnapshot {
        var airborne = 0.0
        for drop in air { airborne += drop.amount }
        let projected = phase == .filling ? volume + airborne - line : -1
        let glass = inputTestGlass(id: glassID, phase: phase, overflowing: overflowing, result: result)
        let jugFill = jugCapacity.isFinite ? jugLeft / jugCapacity : 1
        var snap = inputTestSnapshot(glasses: [glass], flow: flow, projected: projected, landing: landing,
                                     jugFill: jugFill)
        snap.needsFlat = !armed
        return snap
    }

    func step(tilt: Double, dt: Double) {
        time += dt
        phaseTime += dt
        if !armed {
            maxTiltWhileFlat = max(maxTiltWhileFlat, tilt)
            if time >= armAfter && tilt < 6 { armed = true }
        }
        tiltLog.append((time: time, tilt: tilt))
        if jugLeft <= 0 {
            tippedBack = tilt < pourPoint ? tippedBack + dt : 0
            if tippedBack >= 0.4 || result != nil {
                jugLeft = jugCapacity
                swapTimes.append(time)
                tippedBack = 0
            }
        }
        let target = armed && jugLeft > 0 ? min(max((tilt - pourPoint) / 45, 0), 1) : 0
        let tau = target > flow ? 0.05 : decline
        flow += (target - flow) * (1 - exp(-dt / tau))
        if flow < 0.003 && target == 0 { flow = 0 }
        let emitted = min(flow * fillPerFlow * dt, jugLeft)
        jugLeft -= emitted
        if jugCapacity.isFinite && jugLeft <= 1e-9 && emitted > 0 {
            jugLeft = 0
            flow = 0
            dryTimes.append(time)
            dryGlasses.insert(glassID)
        }
        if emitted > 0 { air.append((land: time + fall, amount: emitted)) }
        var landed = 0.0
        var aloft: [(land: Double, amount: Double)] = []
        for drop in air {
            if drop.land <= time { landed += drop.amount } else { aloft.append(drop) }
        }
        air = aloft
        landing += (landed / dt / fillPerFlow - landing) * (1 - exp(-dt / 0.08))
        switch phase {
        case .arriving:
            if phaseTime >= 0.45 {
                phase = .filling
                phaseTime = 0
            }
        case .filling:
            volume += landed
            if result == nil {
                if volume > 1 && !overflowing {
                    overflowing = true
                    result = .spill
                    overflowTimes.append(time)
                    finals.append((judgement: .spill, distance: volume - line, glass: glassID))
                    phaseTime = 0
                } else if flow < 0.004 && air.isEmpty && volume > 0.05 {
                    idle += dt
                    if idle >= 0.35 {
                        let d = volume - line
                        let a = abs(d)
                        // Round 5: past the Good band with nothing over the rim is `.over`, not `.spill`.
                        let j: Judgement = a <= 0.025 ? .perfect : (a <= 0.06 ? .great : (a <= 0.12 ? .good : (d < 0 ? .short : .over)))
                        result = j
                        finals.append((judgement: j, distance: d, glass: glassID))
                        phaseTime = 0
                    }
                } else {
                    idle = 0
                }
            } else if phaseTime >= 0.75 {
                glassID += 1
                volume = 0
                result = nil
                overflowing = false
                phaseTime = 0
                idle = 0
            }
        case .served, .leaving:
            break
        }
    }
}

/// Runs the pilot against the bar at 60 Hz; returns the tilt of every frame.
@MainActor
private func runToyBar(_ bar: ToyBar, _ pilot: AutopilotTiltSource, seconds: Double) -> [Double] {
    var tilts: [Double] = []
    let dt = 1.0 / 60
    var frame = 0
    while Double(frame) * dt < seconds {
        let tilt = pilot.tilt(at: Double(frame) * dt)
        tilts.append(tilt)
        bar.step(tilt: tilt, dt: dt)
        frame += 1
    }
    return tilts
}

/// Deterministic jitter in −1…1 (a 32-bit LCG), for the hold-stabiliser tests.
private struct InputJitter {
    var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296.0 * 2 - 1
    }
}

/// A hinge held at 150° with ±1° report jitter (30 Hz reports, 120 Hz frames, 5 s): the tilt's spread and mean after
/// the first second.
@MainActor
private func inputHeldSpread(stabilise: Bool) -> (sd: Double, mean: Double) {
    let source = HingeTiltSource(stabilise: stabilise)
    var dice = InputJitter(seed: 42)
    var tilts: [Double] = []
    for frame in 0..<600 {
        let time = Double(frame) / 120
        if frame % 4 == 0 { source.ingest(angleDegrees: 150 + dice.next(), at: time) }
        let tilt = source.tilt(at: time)
        if time >= 1 { tilts.append(tilt) }
    }
    let mean = tilts.reduce(0, +) / Double(max(tilts.count, 1))
    var variance = 0.0
    for tilt in tilts { variance += (tilt - mean) * (tilt - mean) }
    return (sd: (variance / Double(max(tilts.count, 1))).squareRoot(), mean: mean)
}

/// `GameController.advance` on a Duo, in miniature (round 5): read the hinge, re-lock the flat gate when it reports
/// closing, step the session. Counts what a player would notice.
@MainActor
private final class DuoRig {
    let hinge = HingeTiltSource()
    let session: GameSession
    var measureFrom = Double.infinity
    private(set) var relocks = 0
    private(set) var flatArms = 0
    private(set) var closingFrames = 0
    private(set) var cutFramesAfterArming = 0
    private(set) var maxFlowSince = 0.0
    private var lastReport: Double?

    init(level: String = "1-1") {
        TiltInputLog.shared.clear()
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        session = GameSession(mode: .shift(level), layout: layout, seed: 1)
        session.requireFlat()
    }

    /// A raw hinge report. With `silentWhenStill`, a report equal to the previous one is dropped (the Duo sends
    /// nothing while the hinge is still).
    func report(_ angle: Double, at time: Double, silentWhenStill: Bool) {
        if silentWhenStill, let last = lastReport, last == angle { return }
        lastReport = angle
        hinge.ingest(angleDegrees: angle, at: time)
    }

    @discardableResult
    func frame(at time: Double, dt: Double) -> Double {
        let tilt = hinge.tilt(at: time)
        if hinge.isClosing { closingFrames += 1 }
        if hinge.isClosing && !session.snapshot.needsFlat {
            session.requireFlat()
            relocks += 1
        }
        let events = session.step(dt: dt, tilt: tilt)
        for event in events {
            if case .flatArmed = event { flatArms += 1 }
        }
        if flatArms > 0 && tilt == ClosingGuard.closedTilt { cutFramesAfterArming += 1 }
        if time >= measureFrom { maxFlowSince = max(maxFlowSince, session.snapshot.jug.flow) }
        return tilt
    }
}

// MARK: - Tests

@MainActor
struct InputTests {
    // MARK: Closing guard (ROUND-3 decision 1: closing never pours; ROUND-5 decision 2: lifting is not closing)

    @Test func theClosedTiltIsUprightAndNeverOpensTheFlatGate() {
        // The jug stands exactly upright (no outflow) …
        #expect(Rules.jugAngle(forLidTilt: ClosingGuard.closedTilt) == 0.0)
        #expect(ClosingGuard.cutBelow < ClosingGuard.reopenAbove)
        #expect(ClosingGuard.reopenAbove < ClosingGuard.fastCloseBelow)
        // … and a re-locked gate fed the cut tilt stays locked (decision 1 moved the gate to a lid tilt ≤ 12°, so the
        // old 6° value would now read as "flat" and flicker the gate open every other frame).
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift("1-1"), layout: layout, seed: 1)
        session.requireFlat()
        var armed = false
        for _ in 0..<180 {
            for event in session.step(dt: 1.0 / 60, tilt: ClosingGuard.closedTilt) {
                if case .flatArmed = event { armed = true }
            }
        }
        #expect(armed == false)
        #expect(session.snapshot.needsFlat)
        #expect(session.snapshot.jug.flow == 0.0)
    }

    @Test func closingGuardCountsOnlyGenuineFastClosesBelow120() {
        // A fast tip above 120°, or one that ends just below it: a pour, not a close.
        var high = ClosingGuard()
        high.sample(150, at: 0)
        high.sample(136, at: 1.0 / 30)
        high.sample(123, at: 2.0 / 30)
        high.sample(110, at: 0.1)
        #expect(high.isCut(at: 0.1) == false)
        // Both reports below 120° and fast: cut for `fastCloseHold`, with no re-lock.
        var low = ClosingGuard()
        low.sample(115, at: 0)
        low.sample(100, at: 1.0 / 30)
        #expect(low.isCut(at: 1.0 / 30))
        #expect(low.belowLatch == false)
        #expect(low.isCut(at: 1.0 / 30 + ClosingGuard.fastCloseHold + 0.01) == false)
        // Bunched callbacks: a 3° step 4 ms apart reads as 180°/s but is no close.
        var bunched = ClosingGuard()
        bunched.sample(112, at: 0)
        bunched.sample(109, at: 0.004)
        #expect(bunched.closingSpeed > ClosingGuard.fastCloseSpeed)
        #expect(bunched.isCut(at: 0.004) == false)
        // Resuming a tip after a still hold (the Duo sent nothing): the first report's 8° says nothing about speed.
        var resumed = ClosingGuard()
        resumed.sample(118, at: 0)
        resumed.sample(110, at: 0.6)
        #expect(resumed.isCut(at: 0.6) == false)
        // A slam from rest: the first report already dropped 15°.
        var slam = ClosingGuard()
        slam.sample(115, at: 0)
        slam.sample(100, at: 0.6)
        #expect(slam.isCut(at: 0.6))
        // A slow drift below 78° latches; only above 88° releases it.
        var drift = ClosingGuard()
        drift.sample(80, at: 0)
        drift.sample(77, at: 0.1)
        #expect(drift.belowLatch)
        drift.sample(88, at: 0.5)
        #expect(drift.belowLatch)
        drift.sample(88.5, at: 0.6)
        #expect(drift.belowLatch == false)
    }

    @Test func aFastCloseFrom120To20CutsAtOnceAndReLocksOnlyBelow78() {
        // Held at 120° (reporting, or one report then the Duo's silence while still), then shut at 400°/s to 20°.
        // 30 Hz reports, 120 Hz frames.
        for silentBefore in [false, true] {
            TiltInputLog.shared.clear()
            let source = HingeTiltSource()
            var raw = 120.0
            var firstMoveFrame: Int?
            var leakedFrames = 0
            var cutWithoutRelock = false
            var relockedAbove78 = false
            for frame in 0..<360 {
                let time = Double(frame) / 120
                if frame % 4 == 0 {
                    raw = time < 1 ? 120 : max(120 - 400 * (time - 1), 20)
                    if !silentBefore || frame == 0 || raw < 120 {
                        source.ingest(angleDegrees: raw, at: time)
                        if raw < 120 && firstMoveFrame == nil { firstMoveFrame = frame }
                    }
                }
                let tilt = source.tilt(at: time)
                // From the frame of the first moving report on, the pour is cut.
                if firstMoveFrame != nil && tilt != ClosingGuard.closedTilt { leakedFrames += 1 }
                if source.isCutting && !source.isClosing { cutWithoutRelock = true }
                if source.isClosing && raw >= ClosingGuard.cutBelow { relockedAbove78 = true }
            }
            #expect(firstMoveFrame != nil)
            #expect(leakedFrames == 0)
            // The gate re-locks (isClosing) only once the hinge is below 78°; before that the pour is merely cut.
            #expect(cutWithoutRelock)
            #expect(relockedAbove78 == false)
            #expect(source.isClosing)
            #expect(source.tilt(at: 3.5) == ClosingGuard.closedTilt)
        }
        TiltInputLog.shared.clear()
    }

    @Test func aFullSlamFromThePourRangeLeaksAtMostOneReport() {
        // 150° → 20° at 400°/s: above 120° it is a pour; the cut lands on the first fast pair below 120°.
        TiltInputLog.shared.clear()
        let source = HingeTiltSource()
        var firstBelow120: Int?
        var firstCut: Int?
        var leakedBeforeCut = 0
        var leakedAfterCut = 0
        for frame in 0..<360 {
            let time = Double(frame) / 120
            if frame % 4 == 0 {
                let raw: Double = time < 1 ? 150 : max(150 - 400 * (time - 1), 20)
                source.ingest(angleDegrees: raw, at: time)
                if raw < ClosingGuard.fastCloseBelow && firstBelow120 == nil { firstBelow120 = frame }
            }
            let cut = source.tilt(at: time) == ClosingGuard.closedTilt
            if cut && firstCut == nil { firstCut = frame }
            if firstBelow120 != nil && firstCut == nil && !cut { leakedBeforeCut += 1 }
            if firstCut != nil && !cut { leakedAfterCut += 1 }
        }
        #expect(firstBelow120 != nil)
        #expect(firstCut != nil)
        // At most one report interval (30 Hz, read at 120 Hz).
        #expect(leakedBeforeCut <= 4)
        #expect(leakedAfterCut == 0)
        #expect(source.isClosing)
        TiltInputLog.shared.clear()
    }

    @Test func aQuickTipFrom150To110At400DegPerSecondPoursAndNeverCloses() {
        // QA-2 P1-1a on a Duo, through the session: flat (the gate opens), lift to 150°, then a quick tip to 110° at
        // 400°/s and hold (reporting, or silent while still). It pours, and the gate never re-locks.
        for silent in [false, true] {
            let rig = DuoRig()
            rig.measureFrom = 1.8
            var tilt = 0.0
            for frame in 0..<(120 * 4) {
                let time = Double(frame) / 120
                if frame % 4 == 0 {
                    let angle: Double
                    if time < 1 {
                        angle = 178
                    } else if time < 1.5 {
                        angle = 178 - 56 * (time - 1)
                    } else {
                        angle = max(150 - 400 * (time - 1.5), 110)
                    }
                    rig.report(angle, at: time, silentWhenStill: silent)
                }
                tilt = rig.frame(at: time, dt: 1.0 / 120)
            }
            #expect(rig.flatArms == 1)
            #expect(rig.closingFrames == 0)
            #expect(rig.relocks == 0)
            #expect(rig.cutFramesAfterArming == 0)
            #expect(rig.session.snapshot.needsFlat == false)
            #expect(rig.maxFlowSince > 0.1, "never poured (max flow \(rig.maxFlowSince))")
            #expect(abs(tilt - 70) < 1)
        }
        TiltInputLog.shared.clear()
    }

    @Test func tippingFurtherAfterAStillHoldPours() {
        // QA-2 P1-1b: pour down to 118°, hold still 0.6 s (the Duo sends nothing), then tip on at 90°/s. The first
        // report after the silence has already dropped 8° (it read as 240°/s before round 5).
        let rig = DuoRig()
        rig.measureFrom = 2.7
        var tilt = 0.0
        for frame in 0..<(120 * 4) {
            let time = Double(frame) / 120
            if frame % 4 == 0 {
                if time < 1 {
                    rig.report(178, at: time, silentWhenStill: false)
                } else if time < 2.001 {
                    rig.report(178 - 60 * (time - 1), at: time, silentWhenStill: false)
                } else if time >= 2.599 {
                    rig.report(max(110 - 90 * max(time - 2.6, 0), 100), at: time, silentWhenStill: false)
                }
            }
            tilt = rig.frame(at: time, dt: 1.0 / 120)
        }
        #expect(rig.flatArms == 1)
        #expect(rig.closingFrames == 0)
        #expect(rig.relocks == 0)
        #expect(rig.cutFramesAfterArming == 0)
        #expect(rig.maxFlowSince > 0.1, "never poured (max flow \(rig.maxFlowSince))")
        #expect(abs(tilt - 80) < 1)
        TiltInputLog.shared.clear()
    }

    @Test func slowCloseCutsBelow78AndOnlyReopensAbove88() {
        // 150° → 60° at 30°/s, a second shut-ish, then back to 150° at 30°/s.
        let source = HingeTiltSource()
        var raw = 150.0
        var problems: [String] = []
        var sawClamp = false
        for frame in 0..<(120 * 8) {
            let time = Double(frame) / 120
            let closing = time < 3
            if frame % 4 == 0 {
                if time < 3 {
                    raw = 150 - 30 * time
                } else if time < 4 {
                    raw = 60
                } else {
                    raw = min(60 + 30 * (time - 4), 150)
                }
                source.ingest(angleDegrees: raw, at: time)
            }
            let tilt = source.tilt(at: time)
            let cut = tilt == ClosingGuard.closedTilt
            let label = String(format: "t=%.3f raw=%.1f tilt=%.2f", time, raw, tilt)
            if closing && raw > ClosingGuard.cutBelow && raw < 90 {
                // Between 90° and 78°: full tip (clamped to 90), not cut — a slow close isn't a fast one.
                if tilt > 85 { sawClamp = true } else { problems.append("clamp " + label) }
            }
            if raw < ClosingGuard.cutBelow && !cut { problems.append("below78 " + label) }
            if !closing && raw <= ClosingGuard.reopenAbove && !cut { problems.append("reopen<=88 " + label) }
            if !closing && raw > ClosingGuard.reopenAbove && cut { problems.append("reopen>88 " + label) }
            // A slow close has no fast cut: the re-lock (isClosing) and the cut are the same thing here.
            if source.isClosing != cut { problems.append("isClosing " + label) }
            if source.isCutting != cut { problems.append("isCutting " + label) }
        }
        #expect(problems == [String]())
        #expect(sawClamp)
        #expect(abs(source.tilt(at: 8.5) - 30) < 0.5)
    }

    @Test func aQuickDeliberateLiftStillPours() {
        // Lifting the lid from flat to 120° at 120°/s is a pour, not a close.
        let source = HingeTiltSource()
        var everCut = false
        var tilt = 0.0
        for frame in 0..<360 {
            let time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: time < 1 ? 175 : max(175 - 120 * (time - 1), 120), at: time) }
            tilt = source.tilt(at: time)
            if source.isCutting || source.isClosing { everCut = true }
        }
        #expect(everCut == false)
        #expect(abs(tilt - 60) < 0.5)
    }

    @Test func aFastFlickBelow120CutsBrieflyWithoutReLockingThenPoursAgain() {
        // 125° → 95° at 300°/s, then held: cut for 0.35 s after the last fast pair below 120°, the gate never
        // re-locks, then the jug follows again.
        TiltInputLog.shared.clear()
        let source = HingeTiltSource()
        var tiltDuring = 0.0
        var cuttingDuring = false
        var closingEver = false
        var tiltAfter = 0.0
        var cuttingAfter = true
        for frame in 0..<360 {
            let time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: time < 1 ? 125 : max(125 - 300 * (time - 1), 95), at: time) }
            let tilt = source.tilt(at: time)
            if source.isClosing { closingEver = true }
            if frame == 144 {
                tiltDuring = tilt
                cuttingDuring = source.isCutting
            }
            if frame == 180 {
                tiltAfter = tilt
                cuttingAfter = source.isCutting
            }
        }
        #expect(tiltDuring == ClosingGuard.closedTilt)
        #expect(cuttingDuring)
        #expect(closingEver == false)
        #expect(cuttingAfter == false)
        #expect(abs(tiltAfter - 85) < 1)
        // `lastAngle` stays current from the reports alone (the App reads it while the run is paused).
        source.ingest(angleDegrees: 64, at: 3.2)
        #expect(source.lastAngle == 64.0)
        #expect(source.isClosing)
        TiltInputLog.shared.clear()
    }

    // MARK: Hold stabiliser (REVIEW-2 hinge-noise risk)

    @Test func holdStabiliserCalmsAHeldHinge() {
        let calm = inputHeldSpread(stabilise: true)
        let plain = inputHeldSpread(stabilise: false)
        #expect(calm.sd < 0.25)
        #expect(calm.sd < plain.sd * 0.5)
        #expect(abs(calm.mean - 30) < 0.3)
    }

    @Test func holdStabiliserAddsNoLagToDeliberateMoves() {
        for speed in [60.0, 30.0] {
            let calm = HingeTiltSource()
            let plain = HingeTiltSource(stabilise: false)
            let duration = 60 / speed
            var worstExtra = 0.0
            var worstLate = 0.0
            var settled = 99.0
            for frame in 0..<600 {
                let time = Double(frame) / 120
                let truth: Double = time < 1 ? 170 : max(170 - speed * (time - 1), 110)
                if frame % 4 == 0 {
                    calm.ingest(angleDegrees: truth, at: time)
                    plain.ingest(angleDegrees: truth, at: time)
                }
                _ = calm.tilt(at: time)
                _ = plain.tilt(at: time)
                let calmError = abs((calm.lastAngle ?? 0) - truth)
                let plainError = abs((plain.lastAngle ?? 0) - truth)
                if time >= 1 && time <= 1 + duration {
                    worstExtra = max(worstExtra, calmError - plainError)
                    if time >= 1 + duration / 2 { worstLate = max(worstLate, abs(calmError - plainError)) }
                }
                if abs(time - (1 + duration + 0.3)) < 1.0 / 240 { settled = calmError }
            }
            // At most a fraction of a degree in the first instants of a move, none once it is under way, and the
            // stop settles as fast as without the stabiliser.
            #expect(worstExtra < (speed >= 60 ? 0.5 : 1.0))
            #expect(worstLate < 0.05)
            #expect(settled < 0.3)
        }
    }

    // MARK: Filters and the other sources

    @Test func oneEuroSmoothsJitter() {
        var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
        var worst = 0.0
        for index in 0..<240 {
            let time = Double(index) / 120
            let noisy = 120.0 + (index % 2 == 0 ? 2.0 : -2.0)
            let out = filter.filter(noisy, at: time)
            if index > 60 { worst = max(worst, abs(out - 120)) }
        }
        #expect(worst < 1.0)
    }

    @Test func oneEuroConvergesAfterAStep() {
        var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
        var time = 0.0
        for _ in 0..<60 {
            _ = filter.filter(100, at: time)
            time += 1.0 / 120
        }
        var out = 0.0
        for _ in 0..<120 {
            out = filter.filter(150, at: time)
            time += 1.0 / 120
        }
        #expect(abs(out - 150) < 0.5)
    }

    @Test func tiltMappingClamps() {
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 190) == 0.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 180) == 0.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 120) == 60.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 90) == 90.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 20) == 90.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: Double.nan) == 0.0)
        #expect(HingeTiltSource.hingeAngle(forLidTilt: 30) == 150.0)
    }

    @Test func hingeSourceFollowsSamples() {
        let source = HingeTiltSource()
        #expect(source.hasHinge == false)
        #expect(source.tilt(at: 0) == 0.0)
        var time = 0.0
        var tilt = 0.0
        for frame in 0..<240 {
            time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: 120, at: time) }
            tilt = source.tilt(at: time)
        }
        #expect(source.hasHinge)
        #expect(abs(tilt - 60) < 0.5)
        let angle = source.lastAngle ?? -1
        #expect(abs(angle - 120) < 0.5)
    }

    @Test func hingeSourceMovesSmoothlyBetweenSamples() {
        // A steady close from 170° at 40°/s, reported at 30 Hz, read at 120 Hz: no frame-to-frame jump bigger than a
        // couple of degrees (the picture never holds and then steps).
        let source = HingeTiltSource()
        var previous: Double?
        var biggestStep = 0.0
        for frame in 0..<180 {
            let time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: 170 - 40 * time, at: time) }
            let tilt = source.tilt(at: time)
            if let previous, frame > 30 { biggestStep = max(biggestStep, abs(tilt - previous)) }
            previous = tilt
        }
        #expect(biggestStep < 2)
    }

    @Test func touchTipsAndEasesBackToZero() {
        let touch = TouchTiltSource(viewHeight: 1000)
        #expect(abs(touch.span - 400) < 1e-9)
        var time = 0.0
        _ = touch.tilt(at: time)
        touch.began(at: 800)
        touch.moved(to: 800 - 225)
        for _ in 0..<120 {
            time += 1.0 / 120
            _ = touch.tilt(at: time)
        }
        let expected = TouchTiltSource.tilt(forDrag: 225, span: 400)
        #expect(expected > 45)
        #expect(expected < 60)
        #expect(abs(touch.currentTilt - expected) < 1)
        touch.moved(to: 800 - 450)
        for _ in 0..<120 {
            time += 1.0 / 120
            _ = touch.tilt(at: time)
        }
        #expect(touch.currentTilt > 88)
        touch.ended()
        var tilt = touch.currentTilt
        for _ in 0..<36 {
            time += 1.0 / 120
            tilt = touch.tilt(at: time)
        }
        #expect(tilt < 2)
        #expect(tilt >= 0)
    }

    @Test func touchNeverLeavesRange() {
        let touch = TouchTiltSource(viewHeight: 800)
        var time = 0.0
        touch.began(at: 700)
        touch.moved(to: -2000)
        for _ in 0..<60 {
            time += 1.0 / 60
            #expect(touch.tilt(at: time) <= 90)
        }
        touch.moved(to: 5000)
        for _ in 0..<60 {
            time += 1.0 / 60
            #expect(touch.tilt(at: time) >= 0)
        }
    }

    @Test func touchCurveStartsThePourOnASmallDrag() {
        let span = 0.40 * 844.0
        // The first 10 pt carry the lid past the dead zone; a drag of ~25 pt is well into the pour.
        #expect(TouchTiltSource.tilt(forDrag: 10, span: span) > Rules.deadZone)
        #expect(TouchTiltSource.tilt(forDrag: 26, span: span) > Rules.deadZone + 6)
        #expect(TouchTiltSource.tilt(forDrag: 0, span: span) == 0.0)
        #expect(TouchTiltSource.tilt(forDrag: -40, span: span) == 0.0)
        #expect(abs(TouchTiltSource.tilt(forDrag: span, span: span) - 90) < 1e-9)
        var previous = -1.0
        for step in 0...400 {
            let drag = Double(step)
            let tilt = TouchTiltSource.tilt(forDrag: drag, span: span)
            #expect(tilt >= previous)
            #expect(tilt <= 90)
            previous = tilt
            if drag <= span {
                #expect(abs(TouchTiltSource.drag(forTilt: tilt, span: span) - drag) < 1e-6)
            }
        }
    }

    @Test func touchRegrabContinuesFromTheCurrentTilt() {
        let touch = TouchTiltSource(viewHeight: 844)
        var time = 0.0
        touch.began(at: 600)
        touch.moved(to: 600 - 120)
        for _ in 0..<120 {
            time += 1.0 / 120
            _ = touch.tilt(at: time)
        }
        let held = touch.currentTilt
        touch.ended()
        touch.began(at: 300)
        // A fresh grab doesn't move the jug until the finger moves.
        #expect(abs(touch.target - touch.currentTilt) < 1e-6)
        touch.moved(to: 300 - 1)
        #expect(touch.target > touch.currentTilt)
        #expect(held > 20)
    }

    @Test func demoInterpolatesKeyframes() {
        let demo = DemoTiltSource(keyframes: [(t: 0, tilt: 0), (t: 1, tilt: 40), (t: 2, tilt: 40), (t: 3, tilt: 0)],
                                  start: 10)
        #expect(abs(demo.tilt(at: 10.5) - 20) < 1e-9)
        #expect(demo.tilt(at: 9) == 0.0)
        #expect(abs(demo.tilt(at: 11.5) - 40) < 1e-9)
        #expect(abs(demo.tilt(at: 12.5) - 20) < 1e-9)
        #expect(demo.tilt(at: 30) == 0.0)
        let empty = DemoTiltSource(keyframes: [], start: 0)
        #expect(empty.tilt(at: 5) == 0.0)
    }

    @Test func autopilotRestsWithoutAGlass() {
        let noGlass = inputTestSnapshot(glasses: [])
        let pilot = AutopilotTiltSource(style: .perfect) { noGlass }
        var tilt = 1.0
        for frame in 0..<120 { tilt = pilot.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)

        let arriving = inputTestSnapshot(glasses: [inputTestGlass(phase: .arriving)])
        let waiting = AutopilotTiltSource(style: .perfect) { arriving }
        for frame in 0..<120 { tilt = waiting.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)

        let nothing = AutopilotTiltSource(style: .spill) { nil }
        for frame in 0..<60 { tilt = nothing.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)
    }

    @Test func autopilotTipsInWhenFarFromTheLine() {
        let far = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0, projected: -0.8)
        let pilot = AutopilotTiltSource(style: .perfect) { far }
        var tilt = 0.0
        var previous = 0.0
        var biggestStep = 0.0
        for frame in 0..<90 {
            tilt = pilot.tilt(at: Double(frame) / 60)
            biggestStep = max(biggestStep, abs(tilt - previous))
            previous = tilt
        }
        #expect(tilt > 6)
        #expect(tilt <= 90)
        // Human-like: no jumps (≤ 160°/s at 60 Hz).
        #expect(biggestStep <= 160.0 / 60 + 1e-9)
    }

    @Test func autopilotLaysBackAtTheLine() {
        var snapshot = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0.5, projected: -0.6)
        let pilot = AutopilotTiltSource(style: .perfect) { snapshot }
        var time = 0.0
        var tilt = 0.0
        for _ in 0..<90 {
            tilt = pilot.tilt(at: time)
            time += 1.0 / 60
        }
        #expect(tilt > 6)
        // The projection reaches the line: the jug goes back upright within half a second.
        snapshot = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0.2, projected: 0.0)
        for _ in 0..<30 {
            tilt = pilot.tilt(at: time)
            time += 1.0 / 60
        }
        #expect(tilt < 6)
    }

    @Test func autopilotDesiredFlowEasesNearTheLine() {
        #expect(AutopilotTiltSource.desiredFlow(remaining: 0.8) > AutopilotTiltSource.desiredFlow(remaining: 0.1))
        #expect(AutopilotTiltSource.desiredFlow(remaining: 0.1) > AutopilotTiltSource.desiredFlow(remaining: 0.01))
        #expect(AutopilotTiltSource.desiredRate(remaining: 0.8) > AutopilotTiltSource.desiredRate(remaining: 0.1))
        #expect(AutopilotTiltSource.desiredRate(remaining: 0.1) > AutopilotTiltSource.desiredRate(remaining: 0.01))
        #expect(AutopilotStyle.great.stopDistance > AutopilotStyle.perfect.stopDistance)
        #expect(AutopilotStyle.short.stopDistance < AutopilotStyle.perfect.stopDistance)
    }

    @Test func autopilotHoldsFlatUntilArmed() {
        var gated = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0, projected: -0.8)
        gated.needsFlat = true
        let pilot = AutopilotTiltSource(style: .spill) { gated }
        for frame in 0..<120 {
            #expect(pilot.tilt(at: Double(frame) / 60) == 0.0)
        }
    }

    @Test func autopilotPoursPerfectsOnAToyBar() {
        let bar = ToyBar()
        let pilot = AutopilotTiltSource(style: .perfect) { bar.snapshot }
        let tilts = runToyBar(bar, pilot, seconds: 30)
        #expect(bar.finals.count >= 4)
        #expect(bar.overflowTimes.isEmpty)
        // Every glass, the first included, is a genuine Perfect.
        #expect(bar.finals.allSatisfy { $0.judgement == .perfect })
        var biggestStep = 0.0
        for index in 1..<tilts.count { biggestStep = max(biggestStep, abs(tilts[index] - tilts[index - 1])) }
        #expect(biggestStep <= 160.0 / 60 + 1e-9)
    }

    @Test func autopilotLearnsAHiddenLag() {
        // The outflow dies away slowly after the jug lays back, and the projection doesn't know: the first glass may
        // run over, then the learned lead makes the rest Perfect.
        let bar = ToyBar(decline: 0.3)
        let pilot = AutopilotTiltSource(style: .perfect) { bar.snapshot }
        _ = runToyBar(bar, pilot, seconds: 30)
        #expect(bar.finals.count >= 4)
        #expect(bar.finals.dropFirst().allSatisfy { $0.judgement == .perfect })
        #expect(pilot.leadTime > 0.25)
    }

    @Test func autopilotWaitsForTheFlatGateThenPours() {
        let bar = ToyBar(armAfter: 1.0)
        let pilot = AutopilotTiltSource(style: .perfect) { bar.snapshot }
        _ = runToyBar(bar, pilot, seconds: 20)
        #expect(bar.maxTiltWhileFlat == 0.0)
        #expect(bar.armed)
        #expect(bar.finals.count >= 2)
        #expect(bar.finals.allSatisfy { $0.judgement == .perfect })
    }

    @Test func autopilotSpillsForReal() {
        // A fast glass: the pilot must still be pouring when it overflows, and keep pouring a moment after (the CI
        // spill frame is captured ~0.3 s after the overflow).
        let bar = ToyBar(fillPerFlow: 1.1)
        let pilot = AutopilotTiltSource(style: .spill) { bar.snapshot }
        let tilts = runToyBar(bar, pilot, seconds: 6)
        #expect(!bar.overflowTimes.isEmpty)
        guard let overflow = bar.overflowTimes.first else { return }
        let index = min(Int(((overflow + 0.3) * 60).rounded()), tilts.count - 1)
        #expect(tilts[index] > 20)
        #expect(bar.finals.first?.judgement == .spill)
        // Round 5: a spill is liquid really over the rim; the spill style never settles for an `.over`.
        #expect(!bar.finals.contains { $0.judgement == .over })
    }

    @Test func autopilotSpillsForRealOnAnOrdinaryGlassToo() {
        // The usual fill rate: it keeps pouring through the Good band and the brim until the glass overflows.
        let bar = ToyBar()
        let pilot = AutopilotTiltSource(style: .spill) { bar.snapshot }
        _ = runToyBar(bar, pilot, seconds: 8)
        #expect(!bar.overflowTimes.isEmpty)
        #expect(bar.finals.first?.judgement == .spill)
        #expect(!bar.finals.contains { $0.judgement == .over })
    }

    @Test func autopilotLaysBackWhenTheJugRunsDryAndPoursOnWithAFreshOne() {
        // Round 5 (decision 3): the jug runs dry mid-glass (fill 0, the stream stops); the fresh jug only comes once
        // the jug is tipped back for 0.4 s. A jug of 2 glass heights: every third glass runs it dry.
        let bar = ToyBar(jugCapacity: 2.0)
        let pilot = AutopilotTiltSource(style: .perfect) { bar.snapshot }
        _ = runToyBar(bar, pilot, seconds: 30)
        #expect(!bar.dryTimes.isEmpty)
        #expect(!bar.swapTimes.isEmpty)
        #expect(bar.swapTimes.count >= bar.dryTimes.count - 1)
        #expect(bar.overflowTimes.isEmpty)
        guard let dry = bar.dryTimes.first, let swap = bar.swapTimes.first else { return }
        // It lays back promptly, so the fresh jug arrives within a second, and nothing is tipped while it waits.
        #expect(swap - dry < 1.0)
        var tippedWhileWaiting = 0.0
        for entry in bar.tiltLog where entry.time > dry + 0.6 && entry.time < swap {
            tippedWhileWaiting = max(tippedWhileWaiting, entry.tilt)
        }
        #expect(tippedWhileWaiting < 6)
        // It pours on: every glass that didn't run the jug dry is a genuine Perfect, before and after the swap.
        #expect(bar.finals.count >= 5)
        #expect(bar.finals.contains { $0.glass > (bar.dryGlasses.min() ?? 0) && $0.judgement == .perfect })
        #expect(bar.finals.filter { !bar.dryGlasses.contains($0.glass) }.allSatisfy { $0.judgement == .perfect })
    }

    @Test func autopilotOverFillsPastTheGoodBandButNeverOverflows() {
        // Round 5 (decision 4): the `over` style stops past the Good band (12 %) and short of the brim, so the glass is
        // an honest OVER, not a spill.
        let bar = ToyBar()
        let pilot = AutopilotTiltSource(style: .over) { bar.snapshot }
        _ = runToyBar(bar, pilot, seconds: 30)
        #expect(bar.finals.count >= 4)
        #expect(bar.overflowTimes.isEmpty)
        #expect(bar.finals.allSatisfy { $0.judgement == .over })
    }

    @Test func autopilotGoalsPerGlass() {
        // Only `over` depends on the glass: past the Good band when there is room, never closer than the clearance
        // to the brim.
        #expect(AutopilotStyle.perfect.goal(lineFraction: 0.9) == AutopilotStyle.perfect.stopDistance)
        #expect(AutopilotStyle.spill.goal(lineFraction: 0.9) == AutopilotStyle.spill.stopDistance)
        #expect(AutopilotStyle.over.goal(lineFraction: 0.5) == AutopilotStyle.over.stopDistance)
        #expect(AutopilotStyle.over.stopDistance > 0.12)
        let tall = AutopilotStyle.over.goal(lineFraction: 0.8)
        #expect(tall > 0.12)
        #expect(tall <= 0.2 - AutopilotStyle.overBrimClearance + 1e-9)
        #expect(AutopilotStyle.over.goal(lineFraction: 0.97) >= 0)
        #expect(AutopilotStyle.over.goal(lineFraction: Double.nan).isFinite)
    }

    // MARK: Touch on a Duo (round 4, QA P2-3)

    @Test func touchOnADuoBetween70And78StillPours() {
        TiltInputLog.shared.clear()
        let hinge = HingeTiltSource()
        let touch = TouchTiltSource(viewHeight: 800)
        let layout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)
        let session = GameSession(mode: .shift("1-1"), layout: layout, seed: 1)
        // The lid rests at 75°: below the guard's 78° cut (latched), above the App's 70° autopause.
        hinge.ingest(angleDegrees: 75, at: 0)
        #expect(hinge.closingCut(at: 0))
        var maxFlow = 0.0
        var frame = 0
        while frame < 300 {
            let time = Double(frame) / 60
            if frame == 60 { touch.began(at: 600) }
            if frame > 60 { touch.moved(to: 600 - CGFloat(min(frame - 60, 40)) * 5) }
            // GameController.advance: read the active source (touch), the closing guard's requireFlat, then step.
            let tilt = touch.tilt(at: time)
            if hinge.isClosing && !session.snapshot.needsFlat { session.requireFlat() }
            session.step(dt: 1.0 / 60, tilt: tilt)
            maxFlow = max(maxFlow, session.snapshot.jug.flow)
            frame += 1
        }
        #expect(hinge.drivesThePour == false)
        #expect(hinge.isClosing == false)
        #expect(maxFlow > 0.05, "touch never poured (max flow \(maxFlow))")
        // With the hinge as the input again, the guard still cuts at 75°.
        _ = hinge.tilt(at: 5.5)
        #expect(hinge.drivesThePour)
        #expect(hinge.isClosing)
        TiltInputLog.shared.clear()
    }
}
