import Foundation

/// How the autopilot finishes each glass (CI frames, the menu's attract loop).
///
/// Round 5 (decision 4): `over` fills past the Good band but stops below the brim, so Core stamps "OVER" (a miss with
/// nothing spilled); `spill` keeps pouring until liquid really runs over the rim (Core's `.spill` now means exactly
/// that, and it is judged live on the overflow).
enum AutopilotStyle: String, CaseIterable, Sendable {
    case perfect, great, short, over, spill

    /// Stop pouring once the projected top reaches this signed distance from the line (fraction of interior height).
    /// `spill` ignores it and keeps pouring until the glass overflows. `over` is capped below the brim per glass
    /// (`goal(lineFraction:)`).
    var stopDistance: Double {
        switch self {
        case .perfect: return -0.003
        case .great: return 0.045
        case .short: return -0.16
        case .over: return 0.18
        case .spill: return 1.0
        }
    }

    /// Settled this far under the goal, the autopilot tips in again for a top-up (as a careful human would).
    var topUpMargin: Double {
        switch self {
        case .perfect: return 0.018
        case .great: return 0.03
        case .short: return 0.06
        case .over: return 0.025
        case .spill: return 1.0
        }
    }

    /// Room kept under the brim by the `over` style (fraction of interior height): its stop is a projection, so it
    /// keeps clear of a real overflow (which would be a spill).
    static let overBrimClearance = 0.05

    /// The stop goal for a glass whose line sits at `lineFraction` of its interior height. Only `over` depends on the
    /// glass: past the Good band (12 %) when there is room, never closer than `overBrimClearance` to the brim.
    func goal(lineFraction: Double) -> Double {
        guard self == .over else { return stopDistance }
        let line = lineFraction.isFinite ? TiltMath.clamp(lineFraction, 0, 1) : 0.8
        return min(stopDistance, max(1 - line - Self.overBrimClearance, 0))
    }
}

/// A tilt source that plays the game like a calm human, reading the last snapshot.
///
/// It is a feedback controller on `telemetry.projectedDistanceToLine`, not a script tuned to Core's constants:
/// - waits while glasses arrive, and holds the jug flat (0) while `snapshot.needsFlat` (the start gate);
/// - tips in until liquid flows (remembering where the pour point was), then steers the outflow so the projection
///   approaches the goal at a rate measured in *glass heights per second* (generous far away, a trickle near the line);
///   the flow that achieves that rate is learned live per glass (`fillPerFlow`), so bigger or smaller glasses and a
///   retuned jug don't matter;
/// - lays the jug back when projection + rate × `leadTime` reaches the goal. `leadTime` adapts: after every stop it
///   compares where the glass really settled with the projection at the stop, and it also watches the stream's fall
///   time (if the projection ever ignores liquid in the air, the lead grows to cover the fall);
/// - tops up if it settled clearly short; the `spill` style keeps pouring ~0.4 s past the overflow so the disaster
///   reads (Core judges the spill live, the instant it overflows).
/// Its output goes through a critically damped spring and a speed limit, so it never jumps. Robust to a nil snapshot,
/// finished runs, empty jugs (it backs off and waits for the swap) and conveyors.
@MainActor
final class AutopilotTiltSource: TiltSource {
    let style: AutopilotStyle
    private let snapshot: () -> GameSnapshot?

    private enum Stage { case waiting, reacting, pouring, stopped, resting, spilling }

    private struct StopRecord {
        var projected: Double
        var rate: Double
    }

    private var stage: Stage = .waiting
    private var stageStart: TimeInterval = 0
    private var glassID: Int?
    /// The hand's intent (degrees of lid tilt); the output springs toward it.
    private var command = 0.0
    private var spring = FeelSpring()
    private var lastTime: TimeInterval?
    /// Lid tilt where liquid started to flow last time (the hand remembers where the pour point was).
    private var learnedStartTilt = 20.0
    private var searching = false
    private var searchStart: TimeInterval = 0
    private var lastProjected: Double?
    /// d(projectedDistanceToLine)/dt, smoothed (interior heights per second).
    private var projectedRate = 0.0
    /// How fast this glass rises per unit of outflow (interior heights per second at flow 1), learned live.
    private var fillPerFlow: Double?
    private var overflowSince: TimeInterval?
    private var beyondBrimSince: TimeInterval?
    private var topUps = 0
    private var stopRecord: StopRecord?
    private var flowOnset: (time: TimeInterval, projected: Double)?
    private var streamLanding = false
    /// The jug's drink viscosity lag (s), from the snapshot.
    private var liquidLag = 0.0
    /// Stops measured so far (the lead is a guess until the first one).
    private var learnedStops = 0
    /// The jug ran dry: laid back, waiting for the fresh one (round 5).
    private var waitingForJug = false

    /// Seconds of the current approach rate still to come after the decision to stop (lay-back pour + anything the
    /// projection misses). Learned from every stop; starts at a calm human's guess.
    private(set) var leadTime = 0.14
    /// Smoothed time from the lip to the glass for the last pours (diagnostics, and the lead's safety net).
    private(set) var observedFallTime: Double?

    /// Reaction time after a glass settles under the spout.
    static let reaction = 0.25
    static let initialLead = 0.14   // = leadTime's starting value
    static let minLead = -0.25
    static let maxLead = 0.9
    /// Speed limit on the output (°/s).
    static let maxSpeed = 160.0
    /// Spill style: keep pouring this long after the overflow so the spill is a real, visible disaster (the CI frame is
    /// ~0.3 s after it). Short of Core's resultHold + most of the changeover, so the tail doesn't land in the next glass.
    static let spillLinger = 0.38
    /// Jug fill (0…1) that counts as dry (Core shows exactly 0 once a shift jug runs dry mid-glass).
    static let dryJugFill = 0.002

    init(style: AutopilotStyle, snapshot: @escaping () -> GameSnapshot?) {
        self.style = style
        self.snapshot = snapshot
    }

    func tilt(at time: TimeInterval) -> Double {
        TiltInputLog.shared.noteRead(self)
        guard time.isFinite else { return spring.value }
        let dt: Double
        if let last = lastTime {
            dt = TiltMath.clamp(time - last, 0, 0.1)
        } else {
            dt = 1.0 / 60
        }
        lastTime = max(time, lastTime ?? time)
        let snap = snapshot()
        if let snap, snap.needsFlat {
            // The start gate: the phone is "laid flat" until the session arms. Output exactly 0.
            rest()
            spring = FeelSpring()
            return 0
        }
        decide(snap, time: time, dt: dt)
        return output(dt: dt)
    }

    // MARK: - The hand's intent

    private func decide(_ snap: GameSnapshot?, time: TimeInterval, dt: Double) {
        guard let snap, snap.phase == .playing else {
            rest()
            return
        }

        // The glass we were pouring into just overflowed (Core judges it on the spot).
        if let id = glassID, overflowSince == nil,
           let current = snap.glasses.first(where: { $0.id == id }), current.overflowing {
            overflowSince = time
            if style == .spill && stage == .pouring { enter(.spilling, at: time) }
        }
        if stage == .spilling {
            if time - stageStart < Self.spillLinger {
                // The hand is a beat late: keep pouring (a touch more) while it sheets over the rim.
                command = TiltMath.clamp(command + 8 * dt, 0, 88)
            } else {
                enter(.stopped, at: time)
                command = 0
            }
            return
        }

        guard let glass = snap.glasses.first(where: { $0.phase == .filling && $0.result == nil }) else {
            // Nothing to fill (glasses arriving or leaving): jug upright, wait.
            rest()
            return
        }
        let telemetry = snap.telemetry
        let lagTau = snap.jug.liquid.lagTau
        liquidLag = lagTau.isFinite ? TiltMath.clamp(lagTau, 0, 2) : 0
        if glass.id != glassID {
            finishGlass()
            glassID = glass.id
            enter(.reacting, at: time)
            topUps = 0
            overflowSince = nil
            beyondBrimSince = nil
            lastProjected = nil
            projectedRate = 0
            fillPerFlow = nil
            stopRecord = nil
            flowOnset = nil
            streamLanding = false
        }
        let projected = telemetry.projectedDistanceToLine.isFinite ? telemetry.projectedDistanceToLine : -1
        let goal = style.goal(lineFraction: Self.lineFraction(of: glass))
        if let previous = lastProjected, dt > 0 {
            let raw = (projected - previous) / dt
            projectedRate += (raw - projectedRate) * min(1, dt / 0.12)
        }
        lastProjected = projected
        let flow = telemetry.flow.isFinite ? max(telemetry.flow, 0) : 0
        let landing = telemetry.landingRate.isFinite ? max(telemetry.landingRate, 0) : 0
        observeFall(time: time, flow: flow, landing: landing, projected: projected)
        if stage == .pouring && !searching && flow > 0.08 && projectedRate > 0.005 && dt > 0 {
            let sample = projectedRate / flow
            if let k = fillPerFlow {
                fillPerFlow = k + (sample - k) * min(1, dt / 0.3)
            } else {
                fillPerFlow = sample
            }
        }

        // Round 5 (decision 3): a shift jug that runs dry mid-glass shows fill 0 and the stream stops; the fresh jug
        // only comes once the glass is served or the jug has been tipped back for 0.4 s (and a refill that lands while
        // still tipped won't pour until tipped back). So lay the jug back at once and wait for the fresh one.
        let jugFill = snap.jug.fill.isFinite ? snap.jug.fill : 1
        if jugFill <= Self.dryJugFill && flow < 0.02 {
            if !waitingForJug {
                waitingForJug = true
                if stage != .stopped { enter(.resting, at: time) }
                searching = false
            }
            command = 0
            return
        }
        if waitingForJug {
            // A fresh jug: react like a person, then pour (or top up) again.
            waitingForJug = false
            if stage == .resting { enter(.reacting, at: time) }
        }

        switch stage {
        case .waiting:
            enter(.reacting, at: time)
            command = 0
        case .reacting:
            command = 0
            if time - stageStart >= Self.reaction { beginPour(at: time) }
        case .pouring:
            pour(snap: snap, glass: glass, projected: projected, goal: goal, flow: flow, time: time, dt: dt)
        case .stopped:
            command = 0
            let streamDone = flow < 0.004 && time - stageStart > 0.1
            if style != .spill, topUps < 2, streamDone, goal - projected > style.topUpMargin {
                learnFromStop(final: projected)
                topUps += 1
                beginPour(at: time)
            }
        case .resting:
            command = 0
            if time - stageStart > 1.5 { beginPour(at: time) }
        case .spilling:
            break
        }
    }

    private func pour(snap: GameSnapshot, glass: GlassState, projected: Double, goal: Double, flow: Double,
                      time: TimeInterval, dt: Double) {
        if shouldStop(projected: projected, goal: goal, glass: glass, time: time) {
            stopRecord = StopRecord(projected: projected, rate: max(projectedRate, 0))
            enter(.stopped, at: time)
            command = 0
            searching = false
            return
        }
        if flow < 0.03 {
            // Nothing coming yet: keep tipping in, like a hand feeling for the pour point.
            if !searching {
                searching = true
                searchStart = time
            }
            command += 40 * dt
            if command >= 86 && time - searchStart > 3 {
                // The jug is empty (it's being swapped): lay it back and wait.
                enter(.resting, at: time)
                command = 0
                searching = false
                return
            }
        } else {
            if searching {
                searching = false
                learnedStartTilt = TiltMath.clamp(0.6 * learnedStartTilt + 0.4 * spring.value, 8, 80)
            }
            // Remaining distance net of what the lead says is still to come: a bigger lead slows the hand earlier.
            let remaining = goal - projected - max(projectedRate, 0) * max(effectiveLead, 0)
            let wanted = style == .spill ? 0.8 : wantedFlow(remaining: remaining)
            // Viscous drinks answer slowly: a gentler hand so it doesn't hunt.
            let gain = 70 / (1 + 4 * liquidLag)
            var push = TiltMath.clamp((wanted - flow) * gain, -45, 45)
            if flow > 0.95 && push > 0 { push = 0 }
            command += push * dt
        }
        command = TiltMath.clamp(command, 0, 88)
    }

    /// Tip briskly to just before where it poured last time, then feel for the flow.
    private func beginPour(at time: TimeInterval) {
        enter(.pouring, at: time)
        command = max(spring.value, learnedStartTilt - 6)
        searching = false
        stopRecord = nil
    }

    /// The line as a fraction of the glass's interior height (0.8 if the shape is degenerate).
    private static func lineFraction(of glass: GlassState) -> Double {
        let interior = Double(glass.shape.interiorHeight)
        guard interior > 0 else { return 0.8 }
        let line = Double(glass.lineHeight) / interior
        return line.isFinite ? line : 0.8
    }

    private func shouldStop(projected: Double, goal: Double, glass: GlassState, time: TimeInterval) -> Bool {
        if style == .spill {
            // Safety net if the session never flags the overflow: stop once the projection has been well past the
            // brim for a while (time-based, so a fast glass still overflows for real before the hand lets go).
            // Only a real overflow (`overflowing`, Core's `.spill`) ends the pour early; an `.over` verdict can't
            // happen while the stream still runs, so the spill style never settles for one.
            let line = Self.lineFraction(of: glass)
            if projected > (1 - line) + 0.15 {
                if beyondBrimSince == nil { beyondBrimSince = time }
            } else {
                beyondBrimSince = nil
            }
            if let since = beyondBrimSince { return time - since > 1.2 }
            return false
        }
        let lead = max(projectedRate, 0) * effectiveLead
        return projected + lead >= goal
    }

    /// The lead in use: the learned one, but until a stop has been measured at least a guess that grows with the
    /// drink's viscosity (thick drinks keep coming for a moment after the jug lays back).
    private var effectiveLead: Double {
        if learnedStops > 0 { return leadTime }
        return max(leadTime, Self.initialLead + 0.35 * liquidLag)
    }

    /// The flow that makes the projection approach the goal at `desiredRate`, once this glass's response is known.
    private func wantedFlow(remaining: Double) -> Double {
        let rate = Self.desiredRate(remaining: remaining)
        if let k = fillPerFlow, k > 0.02 {
            return TiltMath.clamp(rate / k, 0.08, 0.85)
        }
        return Self.desiredFlow(remaining: remaining)
    }

    private func enter(_ next: Stage, at time: TimeInterval) {
        stage = next
        stageStart = time
    }

    /// Nothing to pour into: jug upright, forget the glass (learning from how it settled first).
    private func rest() {
        finishGlass()
        glassID = nil
        stage = .waiting
        command = 0
        searching = false
        waitingForJug = false
        lastProjected = nil
        projectedRate = 0
        flowOnset = nil
        streamLanding = false
    }

    // MARK: - Learning

    /// The glass was judged (or left): its last live projection is where it really settled.
    private func finishGlass() {
        if let final = lastProjected { learnFromStop(final: final) }
        stopRecord = nil
    }

    /// Where the glass settled vs. the projection when the hand decided to stop → the lead that would have been exact.
    private func learnFromStop(final: Double) {
        guard let record = stopRecord else { return }
        stopRecord = nil
        guard style != .spill else { return }
        if overflowSince != nil {
            // It ran over although the hand meant to stop (the `over` style near the brim, a hidden lag): the settled
            // level says nothing (liquid was lost), but the lead was clearly too short. Grow it.
            leadTime = min(leadTime + 0.15, Self.maxLead)
            learnedStops += 1
            return
        }
        guard final.isFinite, record.rate > 0.015 else { return }
        let observed = TiltMath.clamp((final - record.projected) / record.rate, Self.minLead, Self.maxLead)
        // The first measurement replaces the guess outright; after that, a calm average.
        leadTime = learnedStops == 0 ? observed : leadTime + (observed - leadTime) * 0.5
        learnedStops += 1
    }

    /// Times the stream's fall (first outflow → first landing). If the projection did not move while the stream was
    /// in the air, the session isn't counting airborne liquid: the lead must at least cover the fall.
    private func observeFall(time: TimeInterval, flow: Double, landing: Double, projected: Double) {
        if flow < 0.004 && landing < 0.005 {
            flowOnset = nil
            streamLanding = false
            return
        }
        if streamLanding { return }
        if flowOnset == nil {
            if flow > 0.03 && landing < 0.01 { flowOnset = (time: time, projected: projected) }
            return
        }
        guard let onset = flowOnset, landing > 0.03 else { return }
        streamLanding = true
        flowOnset = nil
        let fall = time - onset.time
        guard fall > 0.05, fall < 1.5 else { return }
        if let previous = observedFallTime {
            observedFallTime = previous + (fall - previous) * 0.5
        } else {
            observedFallTime = fall
        }
        if projected - onset.projected < 0.003 {
            leadTime = max(leadTime, min(fall + 0.1, Self.maxLead))
        }
    }

    // MARK: - Targets

    /// The approach rate the hand aims for (interior heights per second), given how far the projection still has to
    /// go: generous far from the line, a careful trickle close to it.
    nonisolated static func desiredRate(remaining: Double) -> Double {
        let far = 0.40
        let near = 0.065
        if remaining >= 0.30 { return far }
        if remaining <= 0.035 { return near }
        return near + (far - near) * (remaining - 0.035) / 0.265
    }

    /// Fallback flow target (0…1 of the jug's max) before this glass's response is known.
    nonisolated static func desiredFlow(remaining: Double) -> Double {
        let far = 0.6
        let near = 0.14
        if remaining >= 0.30 { return far }
        if remaining <= 0.04 { return near }
        return near + (far - near) * (remaining - 0.04) / 0.26
    }

    // MARK: - The hand itself

    private func output(dt: Double) -> Double {
        guard dt > 0 else { return spring.value }
        let previous = spring.value
        // Laying back is brisk; tipping in is a smooth ease.
        let omega = command < spring.value - 1 ? 16.0 : 10.0
        spring.step(toward: command, omega: omega, dt: dt)
        let maxStep = Self.maxSpeed * dt
        if spring.value - previous > maxStep {
            spring.value = previous + maxStep
            spring.velocity = min(spring.velocity, Self.maxSpeed)
        } else if previous - spring.value > maxStep {
            spring.value = previous - maxStep
            spring.velocity = max(spring.velocity, -Self.maxSpeed)
        }
        if spring.value < 0 {
            spring.value = 0
            spring.velocity = max(spring.velocity, 0)
        } else if spring.value > 90 {
            spring.value = 90
            spring.velocity = min(spring.velocity, 0)
        }
        return spring.value
    }
}
