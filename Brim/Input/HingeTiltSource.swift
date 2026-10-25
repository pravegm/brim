import Foundation

/// The jug control on the iPhone Duo: hinge samples in (from `HingeReader`), lid tilt out at display rate.
///
/// Pipeline (research/02 §2, Squish's real-Duo lessons): raw samples (25–30 Hz while moving, none while still) →
/// `HingePredictor` (alpha-beta, predicts between samples) sampled at every frame → One-Euro (minCutoff 2.0, β 0.12)
/// → lid tilt = clamp(180 − θ, 0…90). The dead zone is the session's business (`Rules.deadZone`).
@MainActor
final class HingeTiltSource: TiltSource {
    private var predictor = HingePredictor()
    private var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
    /// True once any real hinge sample has arrived.
    private(set) var hasHinge = false
    /// The filtered hinge angle (180 = flat), as of the last `tilt(at:)` (or the first sample before any frame).
    private(set) var lastAngle: Double?
    /// The last raw reading and when it arrived (diagnostics).
    private(set) var lastRawAngle: Double?
    private(set) var lastSampleTime: TimeInterval?
    private var lastQuery: TimeInterval?
    private var lastTilt = 0.0

    init() {}

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
        if lastAngle == nil { lastAngle = angle }
    }

    func tilt(at time: TimeInterval) -> Double {
        guard hasHinge, time.isFinite else { return 0 }
        // Asked twice for the same frame (or an older one): same answer, and the filter doesn't advance.
        if let previous = lastQuery, time <= previous { return lastTilt }
        lastQuery = time
        let predicted = predictor.angle(at: time)
        let filtered = filter.filter(predicted, at: time)
        lastAngle = filtered
        lastTilt = TiltMath.lidTilt(forHingeAngle: filtered)
        return lastTilt
    }

    /// Forget the motion history (keeps `hasHinge`): e.g. after the app returns from the background.
    func reset() {
        predictor.reset()
        filter.reset()
        lastQuery = nil
        if let raw = lastRawAngle, let stamp = lastSampleTime {
            predictor.sample(raw, at: stamp)
        }
    }

    /// Lid tilt for a hinge angle (degrees): clamp(180 − angle, 0…90).
    nonisolated static func lidTilt(forHingeAngle angle: Double) -> Double {
        TiltMath.lidTilt(forHingeAngle: angle)
    }

    /// Hinge angle for a lid tilt (HUD/debug): 180 − tilt.
    nonisolated static func hingeAngle(forLidTilt tilt: Double) -> Double {
        TiltMath.hingeAngle(forLidTilt: tilt)
    }
}
