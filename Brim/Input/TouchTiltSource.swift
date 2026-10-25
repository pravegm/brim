import CoreGraphics
import Foundation

/// The fallback control for phones without a fold (GAME-DESIGN §3): drag **up** to tip the jug, release and it eases
/// back upright. Full 90° of lid tilt over ~45% of the view height; a re-grab continues from the current tilt; dragging
/// past either end re-anchors, so coming back responds at once (no dead travel).
///
/// The App feeds it UIKit view coordinates (points, y down) and should set `viewHeight` to the play view's height.
@MainActor
final class TouchTiltSource: TiltSource {
    /// Height of the view the touches come from (points).
    var viewHeight: CGFloat
    /// Fraction of `viewHeight` that spans the full 90°.
    static let fullTiltFraction: CGFloat = 0.45
    /// Spring stiffness while following the finger (fast, but no steps at the touch rate).
    static let followOmega = 28.0
    /// Spring stiffness on release: back below the 6° dead zone in ~0.2 s, settled by ~0.25 s.
    static let releaseOmega = 22.0

    private(set) var isDragging = false
    private var anchorY: CGFloat = 0
    private var anchorTilt = 0.0
    private(set) var target = 0.0
    private var spring = FeelSpring()
    private var lastTime: TimeInterval?

    init(viewHeight: CGFloat = 844) {
        self.viewHeight = viewHeight
    }

    /// The smoothed tilt as of the last `tilt(at:)`.
    var currentTilt: Double { spring.value }

    func began(at y: CGFloat) {
        isDragging = true
        anchorY = y
        anchorTilt = TiltMath.clamp(spring.value, 0, 90)
        target = anchorTilt
    }

    func moved(to y: CGFloat) {
        guard isDragging else {
            began(at: y)
            return
        }
        let span = max(viewHeight * Self.fullTiltFraction, 40)
        let wanted = anchorTilt + Double((anchorY - y) / span) * 90
        if wanted > 90 {
            anchorTilt = 90
            anchorY = y
        } else if wanted < 0 {
            anchorTilt = 0
            anchorY = y
        }
        target = TiltMath.clamp(wanted, 0, 90)
    }

    func ended() {
        isDragging = false
        target = 0
    }

    /// Same as `ended()` (a cancelled gesture also lets go of the jug).
    func cancelled() {
        ended()
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
        spring.step(toward: target, omega: isDragging ? Self.followOmega : Self.releaseOmega, dt: dt)
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

/// CI scripts and demos: lid tilt from piecewise-linear keyframes (`t` in seconds after `start`, tilt in degrees).
/// Before the first keyframe it holds the first value, after the last it holds the last; no keyframes = 0.
@MainActor
final class DemoTiltSource: TiltSource {
    let keyframes: [(t: Double, tilt: Double)]
    let start: TimeInterval

    init(keyframes: [(t: Double, tilt: Double)], start: TimeInterval) {
        self.keyframes = keyframes.sorted { $0.t < $1.t }
        self.start = start
    }

    func tilt(at time: TimeInterval) -> Double {
        Self.value(of: keyframes, at: time - start)
    }

    /// Piecewise-linear interpolation, clamped to 0…90.
    nonisolated static func value(of keyframes: [(t: Double, tilt: Double)], at local: Double) -> Double {
        guard let first = keyframes.first, let last = keyframes.last else { return 0 }
        if local <= first.t { return TiltMath.clamp(first.tilt, 0, 90) }
        if local >= last.t { return TiltMath.clamp(last.tilt, 0, 90) }
        for index in 1..<keyframes.count {
            let b = keyframes[index]
            guard local <= b.t else { continue }
            let a = keyframes[index - 1]
            let span = b.t - a.t
            let u = span > 0 ? (local - a.t) / span : 1
            return TiltMath.clamp(a.tilt + (b.tilt - a.tilt) * u, 0, 90)
        }
        return TiltMath.clamp(last.tilt, 0, 90)
    }
}
