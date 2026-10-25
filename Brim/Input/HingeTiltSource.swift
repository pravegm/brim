import Foundation

/// The jug control on the iPhone Duo: hinge samples in (from `HingeReader`), lid tilt out at display rate.
///
/// Pipeline (research/02 §2, Squish's real-Duo lessons): raw samples (25–30 Hz while moving, none while still) →
/// `HingePredictor` (alpha-beta, predicts between samples) sampled at every frame → One-Euro (minCutoff 2.0, β 0.12)
/// → `HoldStabiliser` (filters harder only while the hand holds still) → lid tilt = clamp(180 − θ, 0…90).
/// The dead zone is the session's business (`Rules.deadZone`).
///
/// Closing never pours (ROUND-3 decision 1): `ClosingGuard` watches the raw reports. Below 78° (until back above 88°),
/// or while the hinge closes faster than 160°/s (+0.35 s), the output is `ClosingGuard.closedTilt`: the jug upright,
/// no outflow, and never read as "flat" by the flat gate. Between 90° and 78° the tilt is clamped to 90.
@MainActor
final class HingeTiltSource: TiltSource {
    private var predictor = HingePredictor()
    private var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
    private var stabiliser = HoldStabiliser()
    private var closingGuard = ClosingGuard()
    private let stabilise: Bool
    /// True once any real hinge sample has arrived.
    private(set) var hasHinge = false
    /// The freshest hinge angle (180 = flat): the filtered angle after each frame's `tilt(at:)`, and the raw reading
    /// as soon as a sample arrives (so it stays current while no frames ask, e.g. while the run is paused).
    private(set) var lastAngle: Double?
    /// The last raw reading and when it arrived (diagnostics).
    private(set) var lastRawAngle: Double?
    private(set) var lastSampleTime: TimeInterval?
    private var lastQuery: TimeInterval?
    private var lastTilt = 0.0

    /// `stabilise: false` skips the hold stabiliser (tests compare against it).
    init(stabilise: Bool = true) {
        self.stabilise = stabilise
    }

    /// True while the closing guard cuts the pour (below 78° until back above 88°, or within 0.35 s of a fast close),
    /// as of the latest frame or sample. Use `closingCut(at:)` for a specific time.
    ///
    /// Round 4 (QA P2-3): only while the hinge is the pour input (`drivesThePour`). With touch on a Duo (the setting,
    /// or touch chosen in book pose) at 70°–78°, the App's per-frame `requireFlat()` on `isClosing` re-closed the flat
    /// gate every frame and nothing could pour; the hinge doesn't pour then, so there is nothing to cut.
    var isClosing: Bool {
        guard hasHinge, drivesThePour else { return false }
        let latest = max(lastQuery ?? -Double.infinity, lastSampleTime ?? -Double.infinity)
        return closingGuard.isCut(at: latest)
    }

    /// True while the hinge is the tilt source being read: no other tilt source (touch, autopilot, demo keyframes) has
    /// been read since this one (`TiltInputLog`). True before any source has been read.
    var drivesThePour: Bool {
        guard let last = TiltInputLog.shared.lastRead else { return true }
        return last === self
    }

    /// `isClosing` at a given time (the fast-close hold expires with time even when no frame or report arrives).
    func closingCut(at time: TimeInterval) -> Bool {
        hasHinge && closingGuard.isCut(at: time)
    }

    /// Closing speed from the last two raw reports (°/s, positive while closing; diagnostics).
    var closingSpeed: Double { closingGuard.closingSpeed }

    /// One hinge report: degrees (180 = flat), stamped on receipt with `CACurrentMediaTime()`.
    func ingest(angleDegrees: Double, at time: TimeInterval) {
        guard angleDegrees.isFinite, time.isFinite else { return }
        let angle = TiltMath.clamp(angleDegrees, 0, 180)
        // Never let a sample go back in time (it would make the predictor's dt negative).
        let stamp = max(time, lastSampleTime ?? time)
        hasHinge = true
        lastRawAngle = angle
        lastSampleTime = stamp
        predictor.sample(angle, at: stamp)
        stabiliser.sample(angle, at: stamp)
        closingGuard.sample(angle, at: stamp)
        lastAngle = angle
    }

    func tilt(at time: TimeInterval) -> Double {
        TiltInputLog.shared.noteRead(self)
        guard hasHinge, time.isFinite else { return 0 }
        // Asked twice for the same frame (or an older one): same answer, and the filters don't advance.
        if let previous = lastQuery, time <= previous { return lastTilt }
        lastQuery = time
        let predicted = predictor.angle(at: time)
        var angle = filter.filter(predicted, at: time)
        if stabilise {
            angle = stabiliser.filter(angle, at: time)
        }
        lastAngle = angle
        if closingGuard.isCut(at: time) {
            lastTilt = ClosingGuard.closedTilt
        } else {
            lastTilt = TiltMath.lidTilt(forHingeAngle: angle)
        }
        return lastTilt
    }

    /// Forget the motion history (keeps `hasHinge` and the below-78° latch): e.g. after the app returns from the
    /// background.
    func reset() {
        predictor.reset()
        filter.reset()
        stabiliser.reset()
        closingGuard.reset()
        lastQuery = nil
        if let raw = lastRawAngle, let stamp = lastSampleTime {
            predictor.sample(raw, at: stamp)
        }
    }

    /// Lid tilt for a hinge angle (degrees): clamp(180 − angle, 0…90). The plain mapping, without the closing guard.
    nonisolated static func lidTilt(forHingeAngle angle: Double) -> Double {
        TiltMath.lidTilt(forHingeAngle: angle)
    }

    /// Hinge angle for a lid tilt (HUD/debug): 180 − tilt.
    nonisolated static func hingeAngle(forLidTilt tilt: Double) -> Double {
        TiltMath.hingeAngle(forLidTilt: tilt)
    }
}

/// Which tilt source was read last (round 4, QA P2-3). The App reads exactly one source per frame (the active one) and
/// then asks the hinge `isClosing`; every source notes itself here when read, so the hinge can tell whether it is the
/// pour input without the App passing its input mode around. Weak: a released source never counts.
@MainActor
final class TiltInputLog {
    static let shared = TiltInputLog()

    private(set) weak var lastRead: AnyObject?

    init() {}

    func noteRead(_ source: AnyObject) {
        if lastRead !== source { lastRead = source }
    }

    /// Forget (tests).
    func clear() {
        lastRead = nil
    }
}
