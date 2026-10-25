import Foundation

// Smoothing building blocks for the tilt pipeline, adapted from Squish (`Core/HingeTracker.swift`, `Core/Filters.swift`).
// Names are prefixed/namespaced so they never clash with helpers other modules may define.

/// Small pure helpers for the tilt pipeline.
enum TiltMath {
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    /// Lid tilt in degrees (0 = flat … 90) from the hinge angle (180 = flat): `clamp(180 − θ, 0…90)` (GAME-DESIGN §4).
    static func lidTilt(forHingeAngle angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        return clamp(180 - angle, 0, 90)
    }

    /// Hinge angle for a lid tilt (HUD/debug): 180 − tilt.
    static func hingeAngle(forLidTilt tilt: Double) -> Double {
        guard tilt.isFinite else { return 180 }
        return 180 - clamp(tilt, 0, 90)
    }
}

/// One-Euro filter (Casiez et al., CHI 2012): heavy smoothing while the input is slow, low lag while it moves fast.
/// Squish's tuning for the Duo hinge: minCutoff 2.0, β 0.12, dCutoff 1.5; dt clamped to 1/240…0.2 s.
struct OneEuroSmoother {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private(set) var value: Double?
    /// Filtered derivative of the input (units per second).
    private(set) var derivative: Double = 0
    private var lastTime: Double?

    init(minCutoff: Double = 2.0, beta: Double = 0.12, dCutoff: Double = 1.5) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    mutating func reset() {
        value = nil
        derivative = 0
        lastTime = nil
    }

    mutating func filter(_ x: Double, at time: Double) -> Double {
        guard x.isFinite else { return value ?? 0 }
        guard let previous = value, let previousTime = lastTime else {
            value = x
            lastTime = time
            derivative = 0
            return x
        }
        let dt = min(max(time - previousTime, 1.0 / 240.0), 0.2)
        let rawDerivative = (x - previous) / dt
        derivative += (rawDerivative - derivative) * Self.alpha(cutoff: dCutoff, dt: dt)
        let cutoff = minCutoff + beta * abs(derivative)
        let filtered = previous + (x - previous) * Self.alpha(cutoff: cutoff, dt: dt)
        value = filtered
        lastTime = time
        return filtered
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let r = 2 * Double.pi * cutoff * dt
        return r / (r + 1)
    }
}

/// The closing guard (ROUND-3 decision 1, "closing never pours"), on the raw hinge reports (the freshest truth).
///
/// Cut the pour when the hinge is below `cutBelow` (latched until it is above `reopenAbove`), or when it closes faster
/// than `fastCloseSpeed` (the cut holds `fastCloseHold` after the last fast report). Between 90° and 78° the lid tilt
/// is simply clamped to 90 by `TiltMath.lidTilt`. Pure, with explicit times, so it is testable.
///
/// Speed from report pairs: the Duo sends nothing while the hinge is still, so a report after a long silence is
/// treated as one nominal interval of motion (a close from rest is caught on its first report, not its second).
struct ClosingGuard {
    static let cutBelow = 78.0
    static let reopenAbove = 88.0
    /// °/s of closing (angle falling) that cuts the pour at any angle.
    static let fastCloseSpeed = 160.0
    static let fastCloseHold = 0.35
    /// A gap longer than this means the hinge had stopped reporting (it was still).
    static let staleGap = 0.25
    /// The Duo's report interval while moving (25–30 Hz).
    static let nominalInterval = 1.0 / 30
    /// Lid tilt reported while the guard cuts: the jug stands exactly upright (`Rules.jugAngle` = 0, no outflow), but
    /// it is NOT inside the dead zone (`tilt < Rules.deadZone` arms the flat gate), so a closing or half-shut phone
    /// can never open the flat gate on its way back. Set it to 0 to get the literal "tilt 0".
    static let closedTilt: Double = Rules.deadZone

    /// Latched below `cutBelow`, released above `reopenAbove`.
    private(set) var belowLatch = false
    /// The fast-close cut lasts until this time.
    private(set) var holdUntil = -Double.infinity
    /// °/s, positive while closing, from the last two reports (diagnostics).
    private(set) var closingSpeed = 0.0
    private var previousAngle: Double?
    private var previousTime = 0.0

    init() {}

    mutating func sample(_ angle: Double, at time: Double) {
        if let previous = previousAngle {
            let gap = time - previousTime
            let dt = gap > Self.staleGap ? Self.nominalInterval : TiltMath.clamp(gap, 1.0 / 60, Self.staleGap)
            closingSpeed = (previous - angle) / dt
        } else {
            closingSpeed = 0
        }
        previousAngle = angle
        previousTime = time
        if angle < Self.cutBelow {
            belowLatch = true
        } else if angle > Self.reopenAbove {
            belowLatch = false
        }
        if closingSpeed > Self.fastCloseSpeed {
            holdUntil = max(holdUntil, time + Self.fastCloseHold)
        }
    }

    func isCut(at time: Double) -> Bool {
        belowLatch || time < holdUntil
    }

    /// Forget the motion; keep the below-78° latch (the phone is as shut as it was until a report says otherwise).
    mutating func reset() {
        previousAngle = nil
        closingSpeed = 0
        holdUntil = -Double.infinity
    }
}

/// The hold stabiliser (REVIEW-2 risk "hinge noise": ±5° hinge → ±8° jug). After the One-Euro, it filters harder
/// while the hand is holding still and gets out of the way while it moves.
///
/// Intent is read from the NET speed of the raw reports over the last `window` (tremor and quantisation cancel out,
/// a deliberate move doesn't), or from a deviation larger than `escape`. Held: a first-order low-pass at `restCutoff`.
/// Moving (≥ `moveSpeed`): pass-through, zero added lag. A short `hangover` keeps it open just after a move stops, so
/// the tracker's settle isn't smeared. Pure, with explicit times, so it is testable.
struct HoldStabiliser {
    static let restCutoff = 0.6
    static let restSpeed = 6.0
    static let moveSpeed = 20.0
    static let window = 0.25
    static let escape = 4.0
    static let hangover = 0.12
    static let capacity = 12

    private var times: [Double] = []
    private var angles: [Double] = []
    private(set) var value: Double?
    /// 0 = held (full smoothing) … 1 = moving (pass-through).
    private(set) var motion = 0.0
    private var lastTime = 0.0

    init() {}

    mutating func reset() {
        times.removeAll()
        angles.removeAll()
        value = nil
        motion = 0
    }

    /// A raw hinge report (degrees, receipt time).
    mutating func sample(_ angle: Double, at time: Double) {
        times.append(time)
        angles.append(angle)
        if times.count > Self.capacity {
            let extra = times.count - Self.capacity
            times.removeFirst(extra)
            angles.removeFirst(extra)
        }
    }

    /// Net speed of the raw reports (°/s) over the last `window`; 0 once the reports have stopped.
    func speed(at time: Double) -> Double {
        let count = times.count
        guard count >= 2 else { return 0 }
        let newestTime = times[count - 1]
        let newestAngle = angles[count - 1]
        if time - newestTime > Self.window { return 0 }
        var index = count - 1
        while index > 0 && newestTime - times[index - 1] <= Self.window {
            index -= 1
        }
        if index < count - 1 {
            return abs(newestAngle - angles[index]) / max(newestTime - times[index], 1.0 / 60)
        }
        // The first report after a silence: assume one nominal interval of motion.
        return abs(newestAngle - angles[count - 2]) / ClosingGuard.nominalInterval
    }

    mutating func filter(_ x: Double, at time: Double) -> Double {
        guard x.isFinite else { return value ?? 180 }
        guard let previous = value else {
            value = x
            lastTime = time
            motion = 0
            return x
        }
        let dt = TiltMath.clamp(time - lastTime, 1.0 / 240, 0.2)
        lastTime = time
        let bySpeed = TiltMath.clamp((speed(at: time) - Self.restSpeed) / (Self.moveSpeed - Self.restSpeed), 0, 1)
        let byDeviation = TiltMath.clamp((abs(x - previous) - Self.escape) / Self.escape, 0, 1)
        let u = max(bySpeed, byDeviation)
        let k = max(u * u * (3 - 2 * u), motion * exp(-dt / Self.hangover))
        motion = k
        let r = 2 * Double.pi * Self.restCutoff * dt
        let rest = r / (r + 1)
        let alpha = rest + (1 - rest) * k
        let out = previous + (x - previous) * alpha
        value = out
        return out
    }
}

/// Critically damped spring, integrated with the exact closed form so it is stable at any frame time.
struct FeelSpring {
    var value: Double = 0
    var velocity: Double = 0

    init(value: Double = 0) {
        self.value = value
    }

    mutating func step(toward target: Double, omega: Double, dt: Double) {
        guard dt > 0, omega > 0 else { return }
        let x0 = value - target
        let decay = exp(-omega * dt)
        let newX = (x0 + (velocity + omega * x0) * dt) * decay
        velocity = (velocity - omega * (velocity + omega * x0) * dt) * decay
        value = target + newX
    }
}

/// The hinge at display rate (Squish `HingeTracker`, unchanged in behaviour). The Duo reports 25–30 Hz while moving
/// and nothing while still, so the picture must move continuously *between* reports and never hold, then jump.
///
/// An alpha-beta tracker on the raw samples: between samples it extrapolates at the tracked velocity for about one
/// sample interval, then eases to a stop; each correction is blended in over ~40 ms; once reports stop it glides onto
/// the last raw reading. Jumps larger than `snapDegrees` snap. Pure, with explicit times, so it is testable.
struct HingePredictor {
    static let alpha = 0.75
    static let beta = 0.35
    static let maxSpeed = 900.0
    static let coast = 1.0
    static let ease = 0.3
    static let horizonMin = 0.03
    static let horizonMax = 0.2
    static let snapDegrees = 90.0
    static let restGlide = 0.05

    private(set) var estimate: Double?
    /// °/s, positive while the angle grows (opening).
    private(set) var velocity = 0.0
    private(set) var lastSampleTime = 0.0
    /// Smoothed time between samples (s).
    private(set) var interval = 1.0 / 30
    private var offset = 0.0
    private var offsetTime = 0.0
    private var lastReading = 180.0

    init() {}

    mutating func reset() {
        estimate = nil
        velocity = 0
        offset = 0
    }

    mutating func sample(_ angle: Double, at time: Double) {
        lastReading = angle
        guard estimate != nil else {
            estimate = angle
            velocity = 0
            lastSampleTime = time
            offset = 0
            offsetTime = time
            return
        }
        let shown = self.angle(at: time)
        let dt = min(max(time - lastSampleTime, 1.0 / 240), 0.5)
        let predicted = raw(at: time)
        let tau = max(0.03, Self.ease * interval)
        let prior = velocity * exp(-max(0, (time - lastSampleTime) - 2 * horizon) / tau)
        interval += (min(dt, 0.25) - interval) * 0.3
        let surprise = angle - predicted
        if abs(surprise) > Self.snapDegrees {
            estimate = angle
            velocity = 0
            lastSampleTime = time
            offset = 0
            offsetTime = time
            return
        }
        estimate = predicted + Self.alpha * surprise
        velocity = TiltMath.clamp(prior + Self.beta / dt * surprise, -Self.maxSpeed, Self.maxSpeed)
        lastSampleTime = time
        offset = shown - raw(at: time)
        offsetTime = time
    }

    var horizon: Double { TiltMath.clamp(Self.coast * interval, Self.horizonMin, Self.horizonMax) }

    private func extrapolation(at time: Double) -> Double {
        let age = max(time - lastSampleTime, 0)
        if age <= horizon { return age }
        let tau = max(0.03, Self.ease * interval)
        return horizon + tau * (1 - exp(-(age - horizon) / tau))
    }

    private func raw(at time: Double) -> Double {
        (estimate ?? 180) + velocity * extrapolation(at: time)
    }

    /// The hinge angle to use at `time` (degrees, 0…180).
    func angle(at time: Double) -> Double {
        guard estimate != nil else { return 180 }
        let blend = exp(-max(time - offsetTime, 0) / max(0.04, 0.35 * interval))
        let moving = TiltMath.clamp(raw(at: time) + offset * blend, 0, 180)
        let rest = horizon + 3 * max(0.03, Self.ease * interval)
        let age = max(time - lastSampleTime, 0)
        guard age > rest else { return moving }
        let k = 1 - exp(-(age - rest) / Self.restGlide)
        return moving + (lastReading - moving) * k
    }

    /// Reports per second, from the smoothed interval.
    var rate: Double { 1 / max(interval, 1e-3) }
}
