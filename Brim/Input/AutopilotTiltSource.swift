import Foundation

/// How the autopilot finishes each glass (CI frames, the menu's attract loop).
enum AutopilotStyle: String, CaseIterable, Sendable {
    case perfect, great, short, spill

    /// Stop pouring once the projected top reaches this signed distance from the line (fraction of interior height).
    /// `spill` ignores it and keeps pouring until the glass overflows.
    var stopDistance: Double {
        switch self {
        case .perfect: return -0.005
        case .great: return 0.035
        case .short: return -0.15
        case .spill: return 1.0
        }
    }

    /// Settled this far under the goal, the autopilot tips in again for a top-up (as a careful human would).
    var topUpMargin: Double {
        switch self {
        case .perfect: return 0.02
        case .great: return 0.03
        case .short: return 0.06
        case .spill: return 1.0
        }
    }
}

/// A tilt source that plays the game like a calm human, reading the last snapshot:
/// waits while glasses arrive; tips in until the flow is healthy; eases off as `projectedDistanceToLine` nears the
/// goal; lays the jug back when the projection (plus the pour still to come while it lays back) reaches the goal;
/// tops up if it settled clearly short. Its output goes through a critically damped spring and a speed limit, so it
/// never jumps. Robust to a nil snapshot, finished runs, empty jugs (it backs off and waits for the swap) and conveyors.
@MainActor
final class AutopilotTiltSource: TiltSource {
    let style: AutopilotStyle
    private let snapshot: () -> GameSnapshot?

    private enum Stage { case waiting, reacting, pouring, stopped, resting }

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
    /// d(projectedDistanceToLine)/dt, smoothed (per second).
    private var projectedRate = 0.0
    private var overflowSince: TimeInterval?
    private var topUps = 0

    /// Reaction time after a glass settles under the spout.
    static let reaction = 0.3
    /// How far ahead the stop decision looks (≈ the time the laid-back jug still pours).
    static let stopLead = 0.16
    /// Speed limit on the output (°/s).
    static let maxSpeed = 160.0

    init(style: AutopilotStyle, snapshot: @escaping () -> GameSnapshot?) {
        self.style = style
        self.snapshot = snapshot
    }

    func tilt(at time: TimeInterval) -> Double {
        guard time.isFinite else { return spring.value }
        let dt: Double
        if let last = lastTime {
            dt = TiltMath.clamp(time - last, 0, 0.1)
        } else {
            dt = 1.0 / 60
        }
        lastTime = max(time, lastTime ?? time)
        decide(time: time, dt: dt)
        return output(dt: dt)
    }

    // MARK: - The hand's intent

    private func decide(time: TimeInterval, dt: Double) {
        guard let snap = snapshot(), snap.phase == .playing,
              let glass = snap.glasses.first(where: { $0.phase == .filling && $0.result == nil })
        else {
            // Nothing to fill (intro, glasses arriving or leaving, run over): jug upright, wait.
            glassID = nil
            stage = .waiting
            command = 0
            searching = false
            lastProjected = nil
            return
        }
        let telemetry = snap.telemetry
        if glass.id != glassID {
            glassID = glass.id
            enter(.reacting, at: time)
            topUps = 0
            overflowSince = nil
            lastProjected = nil
            projectedRate = 0
        }
        let projected = telemetry.projectedDistanceToLine.isFinite ? telemetry.projectedDistanceToLine : -1
        if let previous = lastProjected, dt > 0 {
            let raw = (projected - previous) / dt
            projectedRate += (raw - projectedRate) * min(1, dt / 0.12)
        }
        lastProjected = projected
        let flow = telemetry.flow.isFinite ? max(telemetry.flow, 0) : 0
        if glass.overflowing && overflowSince == nil { overflowSince = time }

        switch stage {
        case .waiting:
            enter(.reacting, at: time)
            command = 0
        case .reacting:
            command = 0
            if time - stageStart >= Self.reaction { beginPour(at: time) }
        case .pouring:
            if shouldStop(projected: projected, glass: glass, time: time) {
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
                let remaining = style.stopDistance - projected
                let wanted = style == .spill ? 0.75 : Self.desiredFlow(remaining: remaining)
                // Viscous drinks answer slowly: a gentler hand so it doesn't hunt.
                let lag = max(snap.jug.liquid.lagTau, 0)
                let gain = 70 / (1 + 4 * lag)
                command += TiltMath.clamp((wanted - flow) * gain, -45, 45) * dt
            }
            command = TiltMath.clamp(command, 0, 88)
        case .stopped:
            command = 0
            if style != .spill, topUps < 2, flow < 0.005, time - stageStart > 0.2,
               style.stopDistance - projected > style.topUpMargin {
                topUps += 1
                beginPour(at: time)
            }
        case .resting:
            command = 0
            if time - stageStart > 1.5 { beginPour(at: time) }
        }
    }

    /// Tip briskly to just before where it poured last time, then feel for the flow.
    private func beginPour(at time: TimeInterval) {
        enter(.pouring, at: time)
        command = max(spring.value, learnedStartTilt - 6)
        searching = false
    }

    private func shouldStop(projected: Double, glass: GlassState, time: TimeInterval) -> Bool {
        if style == .spill {
            // Keep pouring until it overflows, then a moment more so the spill reads. Safety net: stop well past the
            // brim if the session never flags the overflow.
            if let since = overflowSince { return time - since > 0.35 }
            let interior = Double(glass.shape.interiorHeight)
            let line = interior > 0 ? Double(glass.lineHeight) / interior : 0.8
            return projected > (1 - line) + 0.25
        }
        let lead = max(projectedRate, 0) * Self.stopLead
        return projected + lead >= style.stopDistance
    }

    private func enter(_ next: Stage, at time: TimeInterval) {
        stage = next
        stageStart = time
    }

    /// The flow the hand aims for, given how far the projection still has to go (fraction of interior height):
    /// generous far from the line, a careful trickle close to it.
    nonisolated static func desiredFlow(remaining: Double) -> Double {
        let far = 0.65
        let near = 0.16
        if remaining >= 0.30 { return far }
        if remaining <= 0.04 { return near }
        return near + (far - near) * (remaining - 0.04) / 0.26
    }

    // MARK: - The hand itself

    private func output(dt: Double) -> Double {
        guard dt > 0 else { return spring.value }
        let previous = spring.value
        // Laying back is brisk; tipping in is a gentle ease.
        let omega = command < spring.value - 1 ? 16.0 : 7.0
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
