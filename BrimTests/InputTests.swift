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
                               landing: Double? = nil, phase: SessionPhase = .playing) -> GameSnapshot {
    let liquid = inputTestLiquid()
    let jug = JugState(liquid: liquid, angle: 0, fill: 1, outline: [], liquidPolygon: [], lip: .zero, pivot: .zero,
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
    var finals: [(judgement: Judgement, distance: Double)] = []
    var overflowTimes: [Double] = []

    init(fillPerFlow: Double = 0.55, fall: Double = 0.4, decline: Double = 0.12, armAfter: Double = 0) {
        self.fillPerFlow = fillPerFlow
        self.fall = fall
        self.decline = decline
        self.armAfter = armAfter
        self.armed = armAfter <= 0
    }

    var snapshot: GameSnapshot {
        var airborne = 0.0
        for drop in air { airborne += drop.amount }
        let projected = phase == .filling ? volume + airborne - line : -1
        let glass = inputTestGlass(id: glassID, phase: phase, overflowing: overflowing, result: result)
        var snap = inputTestSnapshot(glasses: [glass], flow: flow, projected: projected, landing: landing)
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
        let target = armed ? min(max((tilt - pourPoint) / 45, 0), 1) : 0
        let tau = target > flow ? 0.05 : decline
        flow += (target - flow) * (1 - exp(-dt / tau))
        if flow < 0.003 && target == 0 { flow = 0 }
        let emitted = flow * fillPerFlow * dt
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
                    finals.append((judgement: .spill, distance: volume - line))
                    phaseTime = 0
                } else if flow < 0.004 && air.isEmpty && volume > 0.05 {
                    idle += dt
                    if idle >= 0.35 {
                        let d = volume - line
                        let a = abs(d)
                        let j: Judgement = a <= 0.025 ? .perfect : (a <= 0.06 ? .great : (a <= 0.12 ? .good : (d < 0 ? .short : .spill)))
                        result = j
                        finals.append((judgement: j, distance: d))
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

// MARK: - Tests

@MainActor
struct InputTests {
    // MARK: Closing guard (ROUND-3 decision 1: closing never pours)

    @Test func theClosedTiltIsUprightButNeverFlat() {
        // The jug stands exactly upright (no outflow) …
        #expect(Rules.jugAngle(forLidTilt: ClosingGuard.closedTilt) == 0.0)
        // … but a closing phone never reads as "laid flat", so it can't open the flat gate on its way back.
        #expect(!(ClosingGuard.closedTilt < Rules.deadZone))
        #expect(ClosingGuard.cutBelow < ClosingGuard.reopenAbove)
    }

    @Test func fastCloseCutsThePourWithinOneSample() {
        // Held at 150° (reporting, or one report then the Duo's silence while still), then shut at 300°/s to 20°.
        // 30 Hz reports, 120 Hz frames.
        for silentBefore in [false, true] {
            let source = HingeTiltSource()
            var tiltBefore = 0.0
            var firstMoveFrame: Int?
            var leakedFrames = 0
            for frame in 0..<360 {
                let time = Double(frame) / 120
                if frame % 4 == 0 {
                    if time < 1 {
                        if !silentBefore || frame == 0 { source.ingest(angleDegrees: 150, at: time) }
                    } else {
                        let angle = max(150 - 300 * (time - 1), 20)
                        source.ingest(angleDegrees: angle, at: time)
                        if angle < 150 && firstMoveFrame == nil { firstMoveFrame = frame }
                    }
                }
                let tilt = source.tilt(at: time)
                if frame == 119 { tiltBefore = tilt }
                // From the frame of the first moving report on, the pour is cut.
                if firstMoveFrame != nil && tilt != ClosingGuard.closedTilt { leakedFrames += 1 }
            }
            #expect(abs(tiltBefore - 30) < 0.5)
            #expect(firstMoveFrame != nil)
            #expect(leakedFrames == 0)
            #expect(source.isClosing)
            #expect(Rules.jugAngle(forLidTilt: source.tilt(at: 3.5)) == 0.0)
        }
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
            if source.isClosing != cut { problems.append("isClosing " + label) }
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
            if source.isClosing { everCut = true }
        }
        #expect(everCut == false)
        #expect(abs(tilt - 60) < 0.5)
    }

    @Test func aFastFlickHoldsTheCutBrieflyThenPoursAgain() {
        // 150° → 120° at 300°/s, then held: cut for 0.35 s after the last fast report, then the jug follows again.
        let source = HingeTiltSource()
        var tiltDuring = 0.0
        var closingDuring = false
        var tiltAfter = 0.0
        var closingAfter = true
        for frame in 0..<360 {
            let time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: time < 1 ? 150 : max(150 - 300 * (time - 1), 120), at: time) }
            let tilt = source.tilt(at: time)
            if frame == 144 {
                tiltDuring = tilt
                closingDuring = source.isClosing
            }
            if frame == 180 {
                tiltAfter = tilt
                closingAfter = source.isClosing
            }
        }
        #expect(tiltDuring == ClosingGuard.closedTilt)
        #expect(closingDuring)
        #expect(closingAfter == false)
        #expect(abs(tiltAfter - 60) < 1)
        // `lastAngle` stays current from the reports alone (the App reads it while the run is paused).
        source.ingest(angleDegrees: 64, at: 3.2)
        #expect(source.lastAngle == 64.0)
        #expect(source.isClosing)
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
