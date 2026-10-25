import CoreGraphics
import Foundation

/// A jug's interior, in local coordinates (y up, origin at the inner floor centre).
/// `outline` is a closed counter-clockwise polygon whose top edge runs from the spout `lip` back across the mouth.
/// `pivot` is the local point the jug rotates about (near the lip, so the spout barely moves while pouring).
/// `capacity` is the 2D area of a full jug (surface `CoreTuning.jugHeadroom` below the lip when upright).
struct JugShape {
    var outline: [CGPoint]
    var lip: CGPoint
    var pivot: CGPoint
    var capacity: CGFloat
}

/// Rotation + level-surface geometry of the jug. Angle in degrees; positive = clockwise = spout tips down.
enum JugGeometry {

    /// The house pitcher: ~164 wide × 216 tall interior, round belly, narrowing neck, spout lip at the upper right.
    static let standard: JugShape = JugGeometry.makeStandard(scale: 1.0)

    /// Rush's "one big shared jug" (same shape, scaled by `CoreTuning.rushJugScale`).
    static let big: JugShape = JugGeometry.makeStandard(scale: CoreTuning.rushJugScale)

    static func makeStandard(scale: Double) -> JugShape {
        let raw: [(Double, Double)] = [
            (-50, 0), (50, 0), (64, 5), (74, 20), (80, 48), (81, 88), (76, 126), (66, 156), (57, 174),   // right wall, neck
            (60, 186), (70, 197), (84, 205), (96, 210),                                                // spout channel → lip
            (86, 214), (40, 216), (-56, 216),                                                          // across the mouth
            (-58, 190), (-64, 164), (-76, 130), (-82, 88), (-81, 48), (-75, 20), (-64, 5),               // left wall (handle side)
        ]
        let s: CGFloat = CGFloat(scale)
        let outline: [CGPoint] = raw.map { (p: (Double, Double)) -> CGPoint in CGPoint(x: CGFloat(p.0) * s, y: CGFloat(p.1) * s) }
        let lip: CGPoint = CGPoint(x: 96 * s, y: 210 * s)
        let pivot: CGPoint = CGPoint(x: 86 * s, y: 202 * s)
        let fullLevel: CGFloat = lip.y - CGFloat(CoreTuning.jugHeadroom) * s
        let cap: CGFloat = CorePolygon.area(CorePolygon.clipBelow(outline, level: fullLevel))
        return JugShape(outline: outline, lip: lip, pivot: pivot, capacity: cap)
    }

    /// World-space outline + liquid polygon + lip for a given rotation/fill, positioned so `pivot` sits at `at`.
    /// `headAboveLip` > 0 means the level surface is above the lip, i.e. the jug pours.
    static func pose(_ jug: JugShape, angle: Double, fill: Double, at pivot: CGPoint)
        -> (outline: [CGPoint], liquid: [CGPoint], lip: CGPoint, headAboveLip: CGFloat) {
        let outline: [CGPoint] = transform(jug.outline, jug: jug, angle: angle, at: pivot)
        let lip: CGPoint = transform(point: jug.lip, jug: jug, angle: angle, at: pivot)
        let f: Double = CoreMath.clamp(fill, 0, 1)
        let volume: CGFloat = CGFloat(f) * jug.capacity
        if volume <= 0 {
            // Empty: report how far the lowest interior point is below the lip (negative head).
            var minY: CGFloat = outline[0].y
            for p in outline where p.y < minY { minY = p.y }
            return (outline, [], lip, minY - lip.y)
        }
        let level: CGFloat = CorePolygon.levelForArea(outline, area: volume)
        let liquid: [CGPoint] = CorePolygon.clipBelow(outline, level: level)
        return (outline, liquid, lip, level - lip.y)
    }

    /// Only the head above the lip (cheaper than `pose` when the polygons aren't needed).
    static func head(_ jug: JugShape, angle: Double, fill: Double) -> CGFloat {
        let o: CGPoint = CGPoint(x: 0, y: 0)
        let outline: [CGPoint] = transform(jug.outline, jug: jug, angle: angle, at: o)
        let lip: CGPoint = transform(point: jug.lip, jug: jug, angle: angle, at: o)
        let volume: CGFloat = CGFloat(CoreMath.clamp(fill, 0, 1)) * jug.capacity
        if volume <= 0 {
            var minY: CGFloat = outline[0].y
            for p in outline where p.y < minY { minY = p.y }
            return minY - lip.y
        }
        return CorePolygon.levelForArea(outline, area: volume) - lip.y
    }

    /// The smallest jug angle (0…180, 0.25° steps) at which a jug with this fill starts to pour.
    static func pourThreshold(_ jug: JugShape, fill: Double) -> Double {
        var a: Double = 0
        while a <= 180 {
            if head(jug, angle: a, fill: fill) > 0 { return a }
            a += 0.25
        }
        return 180
    }

    /// Unit direction the spout points (world, y up) at this angle: from the vertex before the lip to the lip.
    static func spoutDirection(_ jug: JugShape, angle: Double) -> CGVector {
        var idx: Int = 0
        var best: CGFloat = CGFloat.greatestFiniteMagnitude
        for (i, p) in jug.outline.enumerated() {
            let dx: CGFloat = p.x - jug.lip.x
            let dy: CGFloat = p.y - jug.lip.y
            let d: CGFloat = dx * dx + dy * dy
            if d < best { best = d; idx = i }
        }
        let prev: CGPoint = jug.outline[(idx - 1 + jug.outline.count) % jug.outline.count]
        var vx: Double = Double(jug.lip.x - prev.x)
        var vy: Double = Double(jug.lip.y - prev.y)
        let len: Double = max(1e-9, (vx * vx + vy * vy).squareRoot())
        vx /= len
        vy /= len
        let r: Double = CoreMath.radians(angle)
        let c: Double = cos(r)
        let s: Double = sin(r)
        return CGVector(dx: CGFloat(vx * c + vy * s), dy: CGFloat(-vx * s + vy * c))
    }

    /// How far the pivot must be raised above `at` so the rotated interior stays above `floorY`.
    static func liftToClear(_ jug: JugShape, angle: Double, at pivot: CGPoint, floorY: CGFloat) -> CGFloat {
        let outline: [CGPoint] = transform(jug.outline, jug: jug, angle: angle, at: pivot)
        var minY: CGFloat = outline[0].y
        for p in outline where p.y < minY { minY = p.y }
        return max(0, floorY - minY)
    }

    // MARK: Transforms

    /// Rotate a local point clockwise by `angle` about the jug's pivot and place the pivot at `at`.
    static func transform(point p: CGPoint, jug: JugShape, angle: Double, at: CGPoint) -> CGPoint {
        let r: Double = CoreMath.radians(angle)
        let c: Double = cos(r)
        let s: Double = sin(r)
        let dx: Double = Double(p.x - jug.pivot.x)
        let dy: Double = Double(p.y - jug.pivot.y)
        return CGPoint(x: at.x + CGFloat(dx * c + dy * s), y: at.y + CGFloat(-dx * s + dy * c))
    }

    static func transform(_ pts: [CGPoint], jug: JugShape, angle: Double, at: CGPoint) -> [CGPoint] {
        let r: Double = CoreMath.radians(angle)
        let c: Double = cos(r)
        let s: Double = sin(r)
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)
        for p in pts {
            let dx: Double = Double(p.x - jug.pivot.x)
            let dy: Double = Double(p.y - jug.pivot.y)
            out.append(CGPoint(x: at.x + CGFloat(dx * c + dy * s), y: at.y + CGFloat(-dx * s + dy * c)))
        }
        return out
    }

    /// Rotate world points clockwise by `angle` degrees about `center` (used to tilt a sand pile's surface).
    static func rotate(_ pts: [CGPoint], by angle: Double, about center: CGPoint) -> [CGPoint] {
        if angle == 0 { return pts }
        let r: Double = CoreMath.radians(angle)
        let c: Double = cos(r)
        let s: Double = sin(r)
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)
        for p in pts {
            let dx: Double = Double(p.x - center.x)
            let dy: Double = Double(p.y - center.y)
            out.append(CGPoint(x: center.x + CGFloat(dx * c + dy * s), y: center.y + CGFloat(-dx * s + dy * c)))
        }
        return out
    }
}

/// Polygon helpers (shoelace area, clip below a horizontal line, level-for-area bisection).
enum CorePolygon {

    /// Signed shoelace area (positive for counter-clockwise).
    static func signedArea(_ p: [CGPoint]) -> CGFloat {
        let n: Int = p.count
        if n < 3 { return 0 }
        var a: CGFloat = 0
        var i: Int = 0
        while i < n {
            let p1: CGPoint = p[i]
            let p2: CGPoint = p[(i + 1) % n]
            a += p1.x * p2.y - p2.x * p1.y
            i += 1
        }
        return a * 0.5
    }

    static func area(_ p: [CGPoint]) -> CGFloat {
        return abs(signedArea(p))
    }

    /// The part of polygon `p` at or below y = `level` (Sutherland–Hodgman against one half-plane; area-exact for
    /// non-convex polygons too).
    static func clipBelow(_ p: [CGPoint], level: CGFloat) -> [CGPoint] {
        let n: Int = p.count
        if n < 3 { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(n + 4)
        var i: Int = 0
        while i < n {
            let a: CGPoint = p[i]
            let b: CGPoint = p[(i + 1) % n]
            let aIn: Bool = a.y <= level
            let bIn: Bool = b.y <= level
            if aIn { out.append(a) }
            if aIn != bIn {
                let dy: CGFloat = b.y - a.y
                let t: CGFloat = abs(dy) > 1e-12 ? (level - a.y) / dy : 0
                out.append(CGPoint(x: a.x + t * (b.x - a.x), y: level))
            }
            i += 1
        }
        return out.count >= 3 ? out : []
    }

    /// The horizontal level whose clipped area equals `area` (bisection; clamps to the polygon's extent).
    static func levelForArea(_ p: [CGPoint], area target: CGFloat) -> CGFloat {
        if p.isEmpty { return 0 }
        var lo: CGFloat = p[0].y
        var hi: CGFloat = p[0].y
        for q in p {
            if q.y < lo { lo = q.y }
            if q.y > hi { hi = q.y }
        }
        if target <= 0 { return lo }
        if target >= CorePolygon.area(p) { return hi }
        var it: Int = 0
        while it < 34 {
            let mid: CGFloat = (lo + hi) * 0.5
            if CorePolygon.area(CorePolygon.clipBelow(p, level: mid)) < target { lo = mid } else { hi = mid }
            it += 1
        }
        return (lo + hi) * 0.5
    }
}
