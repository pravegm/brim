import CoreGraphics
import Foundation

/// A jug's interior, in local coordinates (y up, origin at the inner floor centre).
/// `outline` is a closed counter-clockwise polygon whose top edge runs from the spout `lip` back across the mouth.
/// `pivot` is the local point the jug rotates about (the lip itself, so the spout never moves sideways while
/// pouring and the stream always lands in the same place).
/// `capacity` is the 2D area of a full jug (surface `CoreTuning.jugHeadroom` below the lip when upright).
struct JugShape {
    var outline: [CGPoint]
    var lip: CGPoint
    var pivot: CGPoint
    var capacity: CGFloat
}

/// Rotation + level-surface geometry of the jug. Angle in degrees; positive = clockwise = spout tips down.
enum JugGeometry {

    /// The house pitcher, round 2: a LIDDED jug, ~146 wide (170 with the spout) × 216 tall interior, round belly,
    /// narrowing neck and a real spout channel (~12 pt wide) from the neck up to the lip at the upper right.
    /// The polygon is closed on purpose: the top edge is a lid, so a surface above the lip is physically true (like
    /// a teapot), and when tipped the liquid fills the spout channel right up to the lip, where the stream leaves.
    ///
    /// Vertex map (Scene: `JugState.outline` keeps this order, rotated and placed in world space):
    /// - `rightWallIndices` 0…8: floor, right wall, neck;
    /// - `spoutChannelIndices` 8…15: channel floor from the neck out to the lip (index `lipIndex` = 12), then the
    ///   channel roof back to where the lid starts;
    /// - `lidIndices` 15…18: the lid (closed mouth), spout side → handle side. Draw a lid here, not an open rim;
    /// - 18…25: left wall (handle side) back down to the floor.
    /// Round 3: built at `CoreTuning.jugScale` (0.93), so the interior is ~158 × 201 (the vertex map is unchanged).
    static let standard: JugShape = JugGeometry.makeStandard(scale: CoreTuning.jugScale)

    /// Rush's "one big shared jug" (same shape, scaled by `CoreTuning.rushJugScale` on top of `jugScale`; its extra
    /// volume comes from `CoreTuning.rushVolumeBoost`).
    static let big: JugShape = JugGeometry.makeStandard(scale: CoreTuning.jugScale * CoreTuning.rushJugScale)

    static let rightWallIndices: ClosedRange<Int> = 0...8
    static let spoutChannelIndices: ClosedRange<Int> = 8...15
    static let lipIndex: Int = 12
    static let lidIndices: ClosedRange<Int> = 15...18

    static func makeStandard(scale: Double) -> JugShape {
        let raw: [(Double, Double)] = [
            (-46, 0), (46, 0), (59, 6), (67, 22), (72, 50), (73, 92), (69, 130), (62, 156), (56, 170),  // 0…8 right wall, neck
            (63, 180), (74, 188), (86, 194), (97, 198),                                                // 9…12 channel floor → lip
            (91, 206), (79, 208), (67, 210),                                                           // 13…15 channel roof
            (36, 214), (-18, 216), (-52, 214),                                                         // 16…18 lid
            (-56, 190), (-62, 164), (-70, 130), (-73, 90), (-73, 50), (-67, 22), (-58, 6),               // 19…25 left wall
        ]
        let s: CGFloat = CGFloat(scale)
        let outline: [CGPoint] = raw.map { (p: (Double, Double)) -> CGPoint in CGPoint(x: CGFloat(p.0) * s, y: CGFloat(p.1) * s) }
        let lip: CGPoint = CGPoint(x: 97 * s, y: 198 * s)
        let pivot: CGPoint = lip
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
    static func pourThreshold(_ jug: JugShape, fill: Double, step: Double = 0.25) -> Double {
        let inc: Double = max(0.05, step)
        var a: Double = 0
        while a <= 180 {
            if head(jug, angle: a, fill: fill) > 0 { return a }
            a += inc
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
