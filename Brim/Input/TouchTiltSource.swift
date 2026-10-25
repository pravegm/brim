import CoreGraphics
import Foundation

/// The fallback control for phones without a fold (GAME-DESIGN §3): drag **up** to tip the jug, release and it eases
/// back upright. Full 90° of lid tilt over ~40 % of the view height (≈ 340 pt on a 6.1" phone); the first
/// `kickDistance` points carry the jug just past the 6° dead zone, so a small drag already starts a full jug pouring
/// (≈ 25 pt), and the rest of the travel is linear for fine control. A re-grab continues from the current tilt;
/// dragging past either end re-anchors, so coming back responds at once (no dead travel).
///
/// The App feeds it UIKit view coordinates (points, y down) and should set `viewHeight` to the play view's height.
@MainActor
final class TouchTiltSource: TiltSource {
    /// Height of the view the touches come from (points).
    var viewHeight: CGFloat
    /// Fraction of `viewHeight` that spans the full 90°.
    static let fullTiltFraction: CGFloat = 0.40
    /// Spring stiffness while following the finger (fast, but no steps at the touch rate).
    static let followOmega = 28.0
    /// Spring stiffness on release: back below the 6° dead zone in ~0.2 s, settled by ~0.25 s.
    static let releaseOmega = 22.0

    private(set) var isDragging = false
    private var anchorY: CGFloat = 0
    /// Drag distance (points, up = positive) equivalent to the tilt at the anchor.
    private var anchorDrag = 0.0
    private(set) var target = 0.0
    private var spring = FeelSpring()
    private var lastTime: TimeInterval?

    init(viewHeight: CGFloat = 844) {
        self.viewHeight = viewHeight
    }

    /// The smoothed tilt as of the last `tilt(at:)`.
    var currentTilt: Double { spring.value }

    /// Drag distance for the full 90° (points).
    var span: Double { max(Double(viewHeight * Self.fullTiltFraction), 60) }

    func began(at y: CGFloat) {
        isDragging = true
        anchorY = y
        anchorDrag = Self.drag(forTilt: TiltMath.clamp(spring.value, 0, 90), span: span)
        target = Self.tilt(forDrag: anchorDrag, span: span)
    }

    func moved(to y: CGFloat) {
        guard isDragging else {
            began(at: y)
            return
        }
        let full = span
        var drag = anchorDrag + Double(anchorY - y)
        if drag > full {
            drag = full
            anchorDrag = full
            anchorY = y
        } else if drag < 0 {
            drag = 0
            anchorDrag = 0
            anchorY = y
        }
        target = Self.tilt(forDrag: drag, span: full)
    }

    /// Lid tilt (0…90) for a drag of `drag` points up, with `span` points for the full 90°.
    nonisolated static func tilt(forDrag drag: Double, span: Double) -> Double {
        TouchTiltCurve.tilt(forDrag: drag, span: span)
    }

    /// The inverse of `tilt(forDrag:span:)`.
    nonisolated static func drag(forTilt tilt: Double, span: Double) -> Double {
        TouchTiltCurve.drag(forTilt: tilt, span: span)
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
        TiltInputLog.shared.noteRead(self)
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

/// The drag → lid-tilt curve of `TouchTiltSource` (pure; no actor). The first `kickDistance` points take the lid from
/// 0 to `kickTilt` (3° past the session's dead zone), then the rest of the span is linear up to 90°.
enum TouchTiltCurve {
    static let kickDistance = 10.0
    static var kickTilt: Double { min(max(Rules.deadZone, 0), 30) + 3 }

    static func tilt(forDrag drag: Double, span: Double) -> Double {
        guard drag.isFinite, drag > 0 else { return 0 }
        let full = span.isFinite ? max(span, kickDistance + 1) : 340
        if drag <= kickDistance { return kickTilt * drag / kickDistance }
        return TiltMath.clamp(kickTilt + (90 - kickTilt) * (drag - kickDistance) / (full - kickDistance), 0, 90)
    }

    static func drag(forTilt tilt: Double, span: Double) -> Double {
        guard tilt.isFinite, tilt > 0 else { return 0 }
        let full = span.isFinite ? max(span, kickDistance + 1) : 340
        let t = min(tilt, 90)
        if t <= kickTilt { return kickDistance * t / kickTilt }
        return kickDistance + (t - kickTilt) / (90 - kickTilt) * (full - kickDistance)
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
        TiltInputLog.shared.noteRead(self)
        return Self.value(of: keyframes, at: time - start)
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
